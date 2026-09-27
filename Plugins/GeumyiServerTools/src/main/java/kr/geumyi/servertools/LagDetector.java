package kr.geumyi.servertools;

/**
 * Pure state machine for lag incident detection. Kept Bukkit-free so it can be unit tested.
 */
final class LagDetector {
    enum Transition { NONE, STARTED, RECOVERED }

    private boolean active;
    private int badSamples;
    private int goodSamples;
    private long startedAt;
    private long incidentCount;

    Transition update(long time, double tps1m, double mspt, double memoryPercent,
                      double lowTps, double highMspt, double highMemoryPercent,
                      int triggerSamples, int recoverySamples) {
        triggerSamples = Math.max(1, triggerSamples);
        recoverySamples = Math.max(1, recoverySamples);

        boolean bad = bad(tps1m, mspt, memoryPercent, lowTps, highMspt, highMemoryPercent);
        if (!active) {
            goodSamples = 0;
            badSamples = bad ? badSamples + 1 : 0;
            if (badSamples >= triggerSamples) {
                active = true;
                startedAt = time;
                incidentCount++;
                badSamples = 0;
                return Transition.STARTED;
            }
            return Transition.NONE;
        }

        badSamples = 0;
        goodSamples = bad ? 0 : goodSamples + 1;
        if (goodSamples >= recoverySamples) {
            active = false;
            goodSamples = 0;
            return Transition.RECOVERED;
        }
        return Transition.NONE;
    }

    boolean active() { return active; }
    long startedAt() { return startedAt; }
    long incidentCount() { return incidentCount; }

    static boolean bad(double tps1m, double mspt, double memoryPercent,
                       double lowTps, double highMspt, double highMemoryPercent) {
        boolean tpsBad = finite(tps1m) && tps1m > 0 && tps1m < lowTps;
        boolean msptBad = finite(mspt) && mspt >= highMspt;
        boolean memBad = finite(memoryPercent) && memoryPercent >= highMemoryPercent;
        return tpsBad || msptBad || memBad;
    }

    static String severity(double tps1m, double mspt, double memoryPercent) {
        if ((finite(mspt) && mspt >= 100.0)
                || (finite(tps1m) && tps1m > 0 && tps1m < 15.0)
                || (finite(memoryPercent) && memoryPercent >= 95.0)) return "CRITICAL";
        return "WARN";
    }

    private static boolean finite(double d) { return !Double.isNaN(d) && !Double.isInfinite(d); }
}
