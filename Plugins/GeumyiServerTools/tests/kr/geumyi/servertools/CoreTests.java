package kr.geumyi.servertools;

public final class CoreTests {
  public static void main(String[] args) {
    check(GscRuntimeBridge.javaMajor("26.0.2") == 26, "java 26 parse");
    check(GscRuntimeBridge.javaMajor("25") == 25, "java 25 parse");
    check(GscRuntimeBridge.javaMajor("1.8.0_402") == 8, "java 8 parse");
    check(GscRuntimeBridge.json("a\"b\\c\n").equals("a\\\"b\\\\c\\n"), "json escape");

    LagDetector detector = new LagDetector();
    check(detector.update(1, 17.5, 55, 50, 18, 50, 85, 3, 2) == LagDetector.Transition.NONE, "lag bad 1");
    check(detector.update(2, 17.4, 60, 50, 18, 50, 85, 3, 2) == LagDetector.Transition.NONE, "lag bad 2");
    check(detector.update(3, 17.0, 65, 50, 18, 50, 85, 3, 2) == LagDetector.Transition.STARTED, "lag start");
    check(detector.active(), "lag active");
    check(detector.incidentCount() == 1, "lag count");
    check(detector.update(4, 20, 20, 50, 18, 50, 85, 3, 2) == LagDetector.Transition.NONE, "recover 1");
    check(detector.update(5, 20, 20, 50, 18, 50, 85, 3, 2) == LagDetector.Transition.RECOVERED, "recover 2");
    check(!detector.active(), "lag inactive");
    check(LagDetector.severity(14.9, 40, 50).equals("CRITICAL"), "severity tps");
    check(LagDetector.severity(19.9, 100, 50).equals("CRITICAL"), "severity mspt");

    DiagnosticsService.LagIncident i = new DiagnosticsService.LagIncident(1, 100, 0, "WARN", "MSPT 60",
      17.5, 60, 70, 3, 1000, 500, "world", 800, 450);
    String json = i.toJson("start");
    check(json.contains("\"id\":1"), "incident json id");
    check(json.contains("\"hottest_world\""), "incident json world");
    System.out.println("CoreTests PASS");
  }
  private static void check(boolean ok, String name) { if (!ok) throw new AssertionError(name); }
}
