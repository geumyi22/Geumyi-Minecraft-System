# GeumyiStatusAgent 0.5.4 build

Requires JDK 21 (`javac`, `jar`). Run `./build.sh`.

This recovered package contains all nine Java source files. Five helper sources were recovered from preserved earlier source/bytecode evidence; the four 0.5.4 overlay sources were preserved directly.

A clean full-source build is used for compilation validation. It is **not** expected to be byte-identical to the historical deployed JAR because that artifact retained precompiled helper classes from its older binary base. See `RECOVERY.md` for the entry-level comparison.

Output: `GeumyiStatusAgent-0.5.4.jar`.
