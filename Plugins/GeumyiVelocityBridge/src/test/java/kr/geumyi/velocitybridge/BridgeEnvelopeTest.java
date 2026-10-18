package kr.geumyi.velocitybridge;

import static org.junit.jupiter.api.Assertions.*;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.HexFormat;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class BridgeEnvelopeTest {
    private static final Instant NOW = Instant.ofEpochSecond(1792267200L);
    private static final String GENERATION = "parent-100-child-101";

    private static byte[] key() {
        byte[] result = new byte[32];
        for (int i = 0; i < result.length; i++) result[i] = (byte)i;
        return result;
    }

    private static BridgeEnvelope.Message fixture() {
        return BridgeEnvelope.issue(key(), "wild", "status", GENERATION,
            NOW, new SecureRandom());
    }

    @Test
    void matchesGoPhaseCCanonicalGoldenVector() {
        BridgeEnvelope.Message golden = new BridgeEnvelope.Message(
            1, "wild", "status", GENERATION,
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 1792267200L, 1792267220L,
            "1488217fd43660a2e0810dc60caf3f93d89d4ba4bb9b4920967f42d31fff70c5");
        assertEquals(118, BridgeEnvelope.canonical(golden).length);
        var verifier = new BridgeEnvelope.Verifier(key());
        assertTrue(verifier.verifyOnce(golden, "wild", "status", GENERATION, NOW));
        assertFalse(verifier.verifyOnce(golden, "wild", "status", GENERATION, NOW));
    }

    @Test
    void statusOnlyServerIssuedNonceMatchesExistingGoGoldenVector() {
        BridgeEnvelope.Message signed = BridgeEnvelope.signIssuedStatusChallenge(
            key(), "wild", GENERATION, "A".repeat(32),
            1792267200L, 1792267220L);
        assertEquals("status", signed.operation());
        assertEquals(
            "1488217fd43660a2e0810dc60caf3f93d89d4ba4bb9b4920967f42d31fff70c5",
            signed.mac());
        assertEquals(118, BridgeEnvelope.canonical(signed).length);
        var verifier = new BridgeEnvelope.Verifier(key());
        assertTrue(verifier.verifyOnce(signed,"wild","status",GENERATION,NOW));
        assertFalse(verifier.verifyOnce(signed,"wild","status",GENERATION,NOW));
    }

    @Test
    void statusOnlyIssuedSignerRejectsMutatedScopeOrNonces() {
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.signIssuedStatusChallenge(new byte[8],"wild",
                GENERATION,"A".repeat(32),1792267200L,1792267220L));
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.signIssuedStatusChallenge(key(),"lobby",
                GENERATION,"A".repeat(32),1792267200L,1792267220L));
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.signIssuedStatusChallenge(key(),"wild",
                "wrong/generation","A".repeat(32),1792267200L,1792267220L));
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.signIssuedStatusChallenge(key(),"wild",
                GENERATION,"?",1792267200L,1792267220L));
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.signIssuedStatusChallenge(key(),"wild",
                GENERATION,"A".repeat(32),0,20));
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.signIssuedStatusChallenge(key(),"wild",
                GENERATION,"A".repeat(32),1792267200L,1792267221L));
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.signIssuedStatusChallenge(key(),"wild",
                GENERATION,"A".repeat(32),1792267200L,1792267200L));
    }

    @Test
    void rejectsCrossProxyActionGenerationAndTampering() {
        var valid = fixture();
        assertFalse(new BridgeEnvelope.Verifier(key()).verifyOnce(
            valid, "playground", "status", GENERATION, NOW));
        assertFalse(new BridgeEnvelope.Verifier(key()).verifyOnce(
            valid, "wild", "prepare_shutdown", GENERATION, NOW));
        assertFalse(new BridgeEnvelope.Verifier(key()).verifyOnce(
            valid, "wild", "status", "parent-200-child-201", NOW));
        assertFalse(new BridgeEnvelope.Verifier(key()).verifyOnce(
            valid, "wild", "status", GENERATION, NOW.plusSeconds(21)));
        var tampered = new BridgeEnvelope.Message(valid.version(),valid.target(),
            valid.operation(),valid.generation(),valid.nonce(),valid.issuedUnix(),
            valid.expiresUnix()+1,valid.mac());
        assertFalse(new BridgeEnvelope.Verifier(key()).verifyOnce(
            tampered, "wild", "status", GENERATION, NOW));
        var wrongSignature = new BridgeEnvelope.Message(valid.version(),valid.target(),
            valid.operation(),valid.generation(),valid.nonce(),valid.issuedUnix(),
            valid.expiresUnix(), "00".repeat(32));
        assertFalse(new BridgeEnvelope.Verifier(key()).verifyOnce(
            wrongSignature, "wild", "status", GENERATION, NOW));
    }

    @Test
    void rejectsUnknownControlAndWeakKeys() {
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.issue(new byte[]{1}, "wild", "status", GENERATION, NOW, new SecureRandom()));
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.issue(key(), "wild", "kill", GENERATION, NOW, new SecureRandom()));
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.issue(key(), "all", "status", GENERATION, NOW, new SecureRandom()));
        assertThrows(IllegalArgumentException.class, () ->
            BridgeEnvelope.issue(key(), "wild", "status", "invalid/generation", NOW, new SecureRandom()));
        assertThrows(IllegalArgumentException.class, () ->
            new BridgeEnvelope.Verifier(new byte[16]));
    }

    @Test
    void racingReplaysCanBeAcceptedAtMostOnce() throws Exception {
        var request = fixture();
        var verifier = new BridgeEnvelope.Verifier(key());
        var start = new CountDownLatch(1);
        var done = new CountDownLatch(24);
        var accepted = new AtomicInteger();
        try (ExecutorService pool = Executors.newFixedThreadPool(8)) {
            for (int i=0;i<24;i++) {
                pool.submit(() -> {
                    try {
                        start.await();
                        if (verifier.verifyOnce(request,"wild","status",GENERATION,NOW))
                            accepted.incrementAndGet();
                    } catch (InterruptedException ex) {
                        Thread.currentThread().interrupt();
                    } finally {
                        done.countDown();
                    }
                });
            }
            start.countDown();
            assertTrue(done.await(10,TimeUnit.SECONDS));
        }
        assertEquals(1, accepted.get());
    }

    @Test
    void validMessageDoesNotEnableShutdownCapability() {
        assertTrue(BridgeEnvelope.isOperation("prepare_shutdown"));
        assertTrue(BridgeEnvelope.isOperation("confirm_shutdown"));
        // Vocabulary support is NOT an executable command handler.
        assertEquals(1, GeumyiVelocityBridge.class.getDeclaredMethods().length);
        assertEquals("onInitialize",GeumyiVelocityBridge.class.getDeclaredMethods()[0].getName());
        assertEquals(64, HexFormat.of().formatHex(new byte[32]).length());
    }
}
