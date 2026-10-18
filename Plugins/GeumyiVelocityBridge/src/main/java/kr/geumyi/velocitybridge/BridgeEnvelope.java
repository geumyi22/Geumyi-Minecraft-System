package kr.geumyi.velocitybridge;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import java.util.regex.Pattern;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Pure, offline protocol model compatible with the Go Phase C canonical
 * length-prefixed HMAC envelope. There is no network listener, player action,
 * scheduler, disk storage, or Velocity shutdown capability in this class.
 * A validated envelope is NOT an authorization to stop a proxy.
 */
public final class BridgeEnvelope {
    private static final Pattern NONCE = Pattern.compile("[A-Za-z0-9_-]{32,64}");
    private static final Pattern GENERATION = Pattern.compile("[A-Za-z0-9_.:-]{8,128}");
    private static final int NONCE_LIMIT = 1024;
    private static final int LIFE_SECONDS = 20;
    private static final int FUTURE_SKEW_SECONDS = 5;
    private static final int PAST_SKEW_SECONDS = 30;

    private BridgeEnvelope() {}

    public record Message(
        int version, String target, String operation, String generation,
        String nonce, long issuedUnix, long expiresUnix, String mac
    ) {}

    public static boolean isTarget(String target) {
        return "wild".equals(target) || "playground".equals(target) || "other".equals(target);
    }

    public static boolean isOperation(String operation) {
        return "status".equals(operation)
            || "prepare_shutdown".equals(operation)
            || "confirm_shutdown".equals(operation);
    }

    private static void writeText(DataOutputStream out, String text) throws IOException {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        out.writeLong(bytes.length);
        out.write(bytes);
    }

    public static byte[] canonical(Message msg) {
        try {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            DataOutputStream out = new DataOutputStream(buffer);
            out.writeLong(msg.version());
            writeText(out, msg.target());
            writeText(out, msg.operation());
            writeText(out, msg.generation());
            writeText(out, msg.nonce());
            out.writeLong(msg.issuedUnix());
            out.writeLong(msg.expiresUnix());
            out.flush();
            return buffer.toByteArray();
        } catch (IOException e) {
            throw new IllegalStateException("in-memory envelope encoding failed", e);
        }
    }

    private static byte[] digest(byte[] key, Message msg) {
        try {
            Mac signer = Mac.getInstance("HmacSHA256");
            signer.init(new SecretKeySpec(key, "HmacSHA256"));
            return signer.doFinal(canonical(msg));
        } catch (Exception e) {
            throw new IllegalStateException("HMAC-SHA256 unavailable", e);
        }
    }

    /** This is a test/protocol helper only; it does not persist credentials. */
    public static Message issue(
        byte[] key, String target, String operation, String generation,
        Instant now, SecureRandom random
    ) {
        if (key == null || key.length < 32 || !isTarget(target)
            || !isOperation(operation) || generation == null
            || !GENERATION.matcher(generation).matches()
            || now == null || random == null) {
            throw new IllegalArgumentException("invalid offline envelope scope");
        }
        byte[] nonce = new byte[24];
        random.nextBytes(nonce);
        String encoded = Base64.getUrlEncoder().withoutPadding().encodeToString(nonce);
        long issued = now.getEpochSecond();
        Message unsigned = new Message(1, target, operation, generation, encoded,
            issued, issued + LIFE_SECONDS, "");
        return new Message(1, target, operation, generation, encoded, issued,
            issued + LIFE_SECONDS, HexFormat.of().formatHex(digest(key, unsigned)));
    }

    /**
     * Signs a SERVER-ISSUED, STATUS-ONLY challenge; unlike issue(), the
     * caller must use the exact nonce that the server just issued.
     *
     * This is an inert protocol helper. It neither connects to a pipe nor
     * retrieves a player count, executes a command, or authorizes shutdown.
     * The GSC-side verifier must ALSO retain an in-memory one-shot issuance
     * ledger. A correct HMAC alone never authenticates a Windows process.
     */
    public static Message signIssuedStatusChallenge(
        byte[] key, String target, String generation, String nonce,
        long issuedUnix, long expiresUnix
    ) {
        if (key == null || key.length < 32 || !isTarget(target)
            || generation == null || !GENERATION.matcher(generation).matches()
            || nonce == null || !NONCE.matcher(nonce).matches()
            || issuedUnix <= 0 || expiresUnix <= issuedUnix
            || expiresUnix - issuedUnix > LIFE_SECONDS) {
            throw new IllegalArgumentException("invalid issued status-only challenge");
        }
        Message unsigned = new Message(1, target, "status", generation,
            nonce, issuedUnix, expiresUnix, "");
        return new Message(1, target, "status", generation, nonce,
            issuedUnix, expiresUnix, HexFormat.of().formatHex(digest(key, unsigned)));
    }

    /** One verifier per isolated proxy/key. Never use this as a live access grant. */
    public static final class Verifier {
        private final byte[] key;
        private final Map<String, Long> seen = new HashMap<>();

        public Verifier(byte[] key) {
            if (key == null || key.length < 32) {
                throw new IllegalArgumentException("key must be at least 256 bits");
            }
            this.key = key.clone();
        }

        public synchronized boolean verifyOnce(
            Message msg, String expectedTarget, String expectedOperation,
            String expectedGeneration, Instant now
        ) {
            if (msg == null || now == null || !isTarget(expectedTarget)
                || !isOperation(expectedOperation) || expectedGeneration == null
                || !GENERATION.matcher(expectedGeneration).matches()
                || msg.version() != 1
                || !expectedTarget.equals(msg.target())
                || !expectedOperation.equals(msg.operation())
                || !expectedGeneration.equals(msg.generation())
                || msg.nonce() == null || !NONCE.matcher(msg.nonce()).matches()
                || msg.mac() == null) {
                return false;
            }
            long timestamp = now.getEpochSecond();
            if (msg.issuedUnix() > timestamp + FUTURE_SKEW_SECONDS
                || msg.issuedUnix() < timestamp - PAST_SKEW_SECONDS
                || msg.expiresUnix() <= timestamp
                || msg.expiresUnix() > msg.issuedUnix() + LIFE_SECONDS
                || msg.expiresUnix() <= msg.issuedUnix()) {
                return false;
            }
            byte[] mac;
            try {
                mac = HexFormat.of().parseHex(msg.mac());
            } catch (IllegalArgumentException badMac) {
                return false;
            }
            if (mac.length != 32 || !MessageDigest.isEqual(mac, digest(key, msg))) {
                return false;
            }
            seen.entrySet().removeIf(entry -> entry.getValue() <= timestamp);
            if (seen.containsKey(msg.nonce()) || seen.size() >= NONCE_LIMIT) {
                return false;
            }
            seen.put(msg.nonce(), msg.expiresUnix());
            return true;
        }
    }
}
