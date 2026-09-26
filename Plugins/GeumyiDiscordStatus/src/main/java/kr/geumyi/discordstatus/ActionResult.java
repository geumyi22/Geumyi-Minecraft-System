package kr.geumyi.discordstatus;

record ActionResult(boolean ok, String code, String message) {
    static ActionResult ok(String message) { return new ActionResult(true, "ok", message); }
    static ActionResult fail(String code, String message) { return new ActionResult(false, code, message); }
}
