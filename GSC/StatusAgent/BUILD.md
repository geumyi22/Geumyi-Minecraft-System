# GeumyiStatusAgent 0.5.4 build

Requires JDK 21 (`javac`, `jar`). Run `./build.sh`.

This recovered package now contains all nine Java source files. The five helper sources were recovered from the preserved 0.4.0 source package; four were byte-identical through the 0.4.5 base JAR, and `ServerState` was recovered by the single verified 0.4.5 delta (`reportedJavaPort`).

The build is deterministic with a fixed JAR timestamp. Output: `GeumyiStatusAgent-0.5.4.jar`.
