# Build GSC 4.3.2

Requires Go 1.23.2 or compatible on Windows. Run `powershell -File build.ps1`.

The original installer embeds payload files. Before building, restore these exact versioned JARs to `cmd/setup/payload/` from the existing [mc-2026.09.26-v3 release](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/mc-2026.09.26-v3):

- GeumyiStatusAgent-0.5.4.jar (inside the GSC FINAL archive / Agent bundle)
- GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar
- GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar

The build script compiles Host and Client EXEs from this source before embedding them into Setup. JARs/EXEs remain ignored; do not commit payload binaries or configured credentials. Existing placeholder-only managed templates remain because the installer reads those exact paths.

Run `go test ./...` for the recovered unit tests. Building the complete installer still requires the release payloads above.
