package kr.geumyi.servertools;

/** Public Bukkit service contract for trusted local companion plugins such as GeumyiDiscordStatus. */
public interface GeumyiServerToolsApi {
    String version();
    boolean maintenanceActive();
    String maintenanceReason();
    void setMaintenance(boolean enabled, String reason);
    String runtimeSessionId();
    boolean runtimeHealthy();

    /** GST 1.1+: structured performance/diagnostics snapshot. Defaults preserve 1.0 consumer compatibility. */
    default String performanceSnapshotJson() { return "{}"; }
    default boolean lagIncidentActive() { return false; }
    default long lagIncidentCount() { return 0L; }
    default String runtimeStatusJson() { return "{}"; }
}
