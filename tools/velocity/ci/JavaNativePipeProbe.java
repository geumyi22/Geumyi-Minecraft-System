import java.io.IOException;
import java.io.RandomAccessFile;
import java.security.MessageDigest;
import java.time.Instant;
import kr.geumyi.velocitybridge.BridgeEnvelope;

/**
 * Dedicated CI-only Java 25 Windows named-pipe feasibility probe.
 * NOT a Velocity plugin, not packaged in an operator release and never
 * connects to Minecraft. The CI script creates one random test-local pipe.
 */
public final class JavaNativePipeProbe {
    private JavaNativePipeProbe() { }

    public static void main(String[] args) throws IOException {
        if (args.length != 1 || !args[0].matches("GSC452-CI-PIPE-[0-9a-f]{24}")) {
            throw new IllegalArgumentException("CI pipe name must be random and explicitly scoped");
        }
        String endpoint = "\\\\.\\pipe\\" + args[0];
        try (RandomAccessFile pipe = new RandomAccessFile(endpoint, "rw")) {
            // The exact 4-byte big-endian length prefix used by the Go
            // velocitybridge/frame.go transport, WITHOUT live JSON commands.
            // Independent cross-language golden fixture also tested by
            // GSC/ServerCenter/internal/velocitybridge/auth_test.go.
            byte[] key = new byte[32];
            for (int i = 0; i < key.length; i++) key[i] = (byte) i;
            String nonce = "A".repeat(32);
            String generation = "parent-100-child-101";
            BridgeEnvelope.Message signed = new BridgeEnvelope.Message(
                1, "wild", "status", generation, nonce,
                1792267200L, 1792267220L,
                "1488217fd43660a2e0810dc60caf3f93d89d4ba4bb9b4920967f42d31fff70c5");
            byte[] canonical = BridgeEnvelope.canonical(signed);
            final int length = pipe.readInt();
            if (length != canonical.length || length != 118 || length > 2048) {
                throw new IOException("CI cross-language frame length was out of bounds");
            }
            byte[] received = new byte[length];
            pipe.readFully(received);
            if (!MessageDigest.isEqual(received, canonical)) {
                throw new IOException("CI native pipe payload differs from Go canonical HMAC encoding");
            }
            BridgeEnvelope.Verifier verifier = new BridgeEnvelope.Verifier(key);
            if (!verifier.verifyOnce(signed, "wild", "status", generation,
                    Instant.ofEpochSecond(1792267200L))) {
                throw new IOException("CI Java HMAC check rejected the Go golden vector");
            }
            if (verifier.verifyOnce(signed, "wild", "status", generation,
                    Instant.ofEpochSecond(1792267200L))) {
                throw new IOException("CI Java accepted replayed Go golden envelope");
            }
            byte[] response = "GSC452-CI-JAVA-HMAC-PASS"
                .getBytes(java.nio.charset.StandardCharsets.US_ASCII);
            pipe.writeInt(response.length);
            pipe.write(response);
        }
        System.out.println("GSC452_WINDOWS_JAVA_NATIVE_PIPE_BYTE_EXCHANGE_PASS");
    }
}
