# Build StatusAgent 0.5.4 (partial source)

Requires JDK 21 and Bash. The four Java source files are the recovered 0.5.4 overlay. Helper class source is **source not yet recovered**.

The unmodified build script expects `base/GeumyiStatusAgent-0.4.5.jar`. Obtain it from `GeumyiServerCenter_FINAL_v4.2.3.zip → GeumyiStatusAgent-0.5.4-BUNDLE.zip → GeumyiStatusAgent-0.5.4-Source.zip → base/` in the existing mc-2026.09.26-v3 release. This is a build dependency, not the current runtime version. Keep it local and ignored.

Then run `bash build.sh`; output is GeumyiStatusAgent-0.5.4.jar. No decompiled or invented helper source was added.
