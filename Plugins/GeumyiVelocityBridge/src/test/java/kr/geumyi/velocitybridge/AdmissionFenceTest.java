package kr.geumyi.velocitybridge;

import static org.junit.jupiter.api.Assertions.*;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;

/** Pure Java fixtures: no Velocity listener, process stop or real login. */
final class AdmissionFenceTest {
    private static final String GEN = "parent-1234-child-5678";

    @Test
    void emptyFrozenGenerationHasOnlyOfflineShapeNotRuntimePermission() {
        AdmissionFence fence = new AdmissionFence(GEN);
        assertFalse(fence.offlineDrainShapeComplete(GEN, 1, 0));
        long epoch = fence.freeze(GEN);
        assertTrue(epoch > 0);
        assertFalse(fence.offlineDrainShapeComplete("parent-wrong-child-1", epoch, 0));
        assertFalse(fence.offlineDrainShapeComplete(GEN, epoch + 1, 0));
        assertFalse(fence.offlineDrainShapeComplete(GEN, epoch, -1));
        assertFalse(fence.offlineDrainShapeComplete(GEN, epoch, 1));
        assertTrue(fence.offlineDrainShapeComplete(GEN, epoch, 0));
        assertEquals(0, fence.enterLogin(GEN));
        assertEquals(0, fence.enterLogin("parent-wrong-child-1"));
        fence.cancelFreeze();
        assertFalse(fence.offlineDrainShapeComplete(GEN, epoch, 0));
    }

    @Test
    void pendingLoginAndUnpublishedSuccessBothDenyDrain() {
        AdmissionFence fence = new AdmissionFence(GEN);
        long pending = fence.enterLogin(GEN);
        assertTrue(pending > 0);
        long epoch = fence.freeze(GEN);
        assertFalse(fence.offlineDrainShapeComplete(GEN, epoch, 0));
        assertEquals(1, fence.inFlightOrUnpublished());
        assertTrue(fence.finishLogin(pending, true));
        assertEquals(1, fence.inFlightOrUnpublished());
        assertFalse(fence.offlineDrainShapeComplete(GEN, epoch, 0));
        // Integration MUST call markVisible only after the actual Velocity
        // player appears in its authoritative online-session collection.
        assertTrue(fence.markVisible(pending));
        assertFalse(fence.markVisible(pending));
        assertFalse(fence.finishLogin(pending, false));
        assertTrue(fence.offlineDrainShapeComplete(GEN, epoch, 0));
        assertFalse(fence.offlineDrainShapeComplete(GEN, epoch, 1));
    }

    @Test
    void failedHandshakeAndWrongGenerationFailClosed() {
        AdmissionFence fence = new AdmissionFence(GEN);
        assertThrows(IllegalArgumentException.class, () -> new AdmissionFence("x"));
        assertEquals(0, fence.enterLogin("other-generation-123"));
        assertEquals(0, fence.freeze("other-generation-123"));
        long ticket = fence.enterLogin(GEN);
        assertTrue(fence.finishLogin(ticket, false));
        assertFalse(fence.finishLogin(ticket, false));
        long epoch = fence.freeze(GEN);
        assertTrue(fence.offlineDrainShapeComplete(GEN, epoch, 0));
        assertEquals(0, fence.enterLogin(GEN));
        assertEquals(0, fence.freeze(GEN));
        fence.cancelFreeze();
        assertFalse(fence.offlineDrainShapeComplete(GEN, epoch, 0));
        long newer = fence.freeze(GEN);
        assertTrue(newer > epoch);
        assertFalse(fence.offlineDrainShapeComplete(GEN, epoch, 0));
    }

    @Test
    void concurrentAdmissionAndFreezeMustKeepPendingEvidence() throws Exception {
        AdmissionFence fence = new AdmissionFence(GEN);
        ExecutorService pool = Executors.newFixedThreadPool(12);
        CountDownLatch go = new CountDownLatch(1);
        List<Future<Long>> futures = new ArrayList<>();
        try {
            for (int i = 0; i < 100; i++) {
                futures.add(pool.submit(() -> {
                    go.await();
                    return fence.enterLogin(GEN);
                }));
            }
            go.countDown();
            long epoch = fence.freeze(GEN);
            int accepted = 0;
            for (Future<Long> fut : futures) {
                long ticket = fut.get(5, TimeUnit.SECONDS);
                if (ticket > 0) accepted++;
            }
            assertEquals(accepted, fence.inFlightOrUnpublished());
            if (accepted > 0) {
                assertFalse(fence.offlineDrainShapeComplete(GEN, epoch, 0));
            } else {
                assertTrue(fence.offlineDrainShapeComplete(GEN, epoch, 0));
            }
            assertEquals(0, fence.enterLogin(GEN));
        } finally {
            pool.shutdownNow();
            assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS));
        }
    }
}
