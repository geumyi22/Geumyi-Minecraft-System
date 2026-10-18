package kr.geumyi.velocitybridge;

import java.util.HashMap;
import java.util.Map;
import java.util.Objects;

/**
 * Offline-only admission fence and drain model.
 *
 * This class is deliberately NOT registered with Velocity events and DOES NOT
 * invoke ProxyServer.shutdown(), block players, or mutate production runtime.
 * A future real plugin must intercept EVERY login entry point before creating
 * a session, account for in-flight logins until online visibility is proven,
 * freeze a pinned JVM generation, and recheck actual live player count.
 */
final class AdmissionFence {
    private enum State { OPEN, FROZEN }
    private enum Login { PENDING, COMMITTED_UNPUBLISHED }

    private final String generation;
    private State state = State.OPEN;
    private final Map<Long, Login> admissions = new HashMap<>();
    private long nextTicket = 1;
    private long freezeEpoch = 0;

    AdmissionFence(String generation) {
        if (generation == null || !generation.matches("[A-Za-z0-9_.:-]{8,128}")) {
            throw new IllegalArgumentException("invalid JVM generation");
        }
        this.generation = generation;
    }

    /** Returns a positive test-only ticket, or 0 when admission is frozen. */
    synchronized long enterLogin(String expectedGeneration) {
        if (!generation.equals(expectedGeneration) || state != State.OPEN || nextTicket <= 0
                || nextTicket == Long.MAX_VALUE) {
            return 0;
        }
        long ticket = nextTicket++;
        admissions.put(ticket, Login.PENDING);
        return ticket;
    }

    /**
     * A successful handshake is still a potentially active player until
     * markVisible() confirms the real proxy session list has accounted for it.
     */
    synchronized boolean finishLogin(long ticket, boolean handshakeSucceeded) {
        Login stateBefore = admissions.get(ticket);
        if (ticket <= 0 || stateBefore != Login.PENDING) {
            return false;
        }
        if (!handshakeSucceeded) {
            admissions.remove(ticket);
            return true;
        }
        admissions.put(ticket, Login.COMMITTED_UNPUBLISHED);
        return true;
    }

    synchronized boolean markVisible(long ticket) {
        if (ticket <= 0 || admissions.get(ticket) != Login.COMMITTED_UNPUBLISHED) {
            return false;
        }
        admissions.remove(ticket);
        return true;
    }

    /** Returns a session-local test epoch; NOT an authenticated control token. */
    synchronized long freeze(String expectedGeneration) {
        if (!Objects.equals(generation, expectedGeneration) || state != State.OPEN
                || freezeEpoch == Long.MAX_VALUE) {
            return 0;
        }
        state = State.FROZEN;
        return ++freezeEpoch;
    }

    /**
     * Pure simulation of a possible NO-PLAYERS preflight.
     * onlinePlayers is a caller-provided TEST observation, not an attestation.
     * A live implementation must recheck under an authenticated, race-safe
     * admission fence and must never infer 0 from failed IO.
     */
    synchronized boolean offlineDrainShapeComplete(
            String expectedGeneration, long expectedFreezeEpoch, int onlinePlayers) {
        return state == State.FROZEN
                && generation.equals(expectedGeneration)
                && expectedFreezeEpoch > 0
                && expectedFreezeEpoch == freezeEpoch
                && onlinePlayers == 0
                && admissions.isEmpty();
    }

    /** New per-process generation required after any unfreeze/restart. */
    synchronized void cancelFreeze() {
        state = State.OPEN;
        freezeEpoch++;
    }

    synchronized int inFlightOrUnpublished() {
        return admissions.size();
    }
}
