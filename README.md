# Copperline Deck

Copperline Deck is an experimental Windows desktop control console for Minecraft servers.

The current development snapshot grew out of a real Fabric server control panel and already provides:

- server start, stop, restart, and console command delivery;
- live, colorized server logs;
- a WebView2 + PixiJS GPU-accelerated visual layer;
- automatic effect suspension when the window is minimized, hidden, or fully occluded;
- a lightweight process manager that keeps the Minecraft server running when the UI is closed;
- a native Windows launcher and taskbar identity.

## Project status

**Version:** `0.1.0-dev`

This repository is in the extraction/refactoring phase. The UI and manager are functional, but the current runtime still assumes that Copperline Deck is deployed into the Minecraft server directory. Decoupling server profiles from the application directory is the next major milestone.

Do not treat the current development branch as a polished end-user release.

## Branches

- `main` — stable project metadata and future stable releases.
- `development` — active integration branch. Current working snapshot lives here.
- `release` — release-staging branch. It remains conservative until the first packaged release is ready.

Feature work should branch from `development` and return through pull requests.

## Repository layout

```text
src/
  launcher/                Native Windows launcher source
  runtime/                 PowerShell host, manager, and WebView UI
    webui/                  HTML/JS visual console
scripts/
  bootstrap.ps1            Downloads build-time third-party dependencies
  build.ps1                Produces a runnable dist/ tree
  package.ps1              Produces a zip artifact
config/
  copperline.example.psd1  Draft server-profile configuration
docs/
  ARCHITECTURE.md
  DEVELOPMENT.md
  ROADMAP.md
```

## Build

Requirements:

- Windows 10/11
- Windows PowerShell 5.1+
- .NET Framework C# compiler (`csc.exe`)
- Internet access for the dependency bootstrap

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1
```

The runnable tree is written to `dist\`.

To create a zip:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\package.ps1
```

## Current limitations

The development snapshot still contains assumptions inherited from the original deployment:

- Fabric server jar name is fixed;
- Java runtime location and JVM memory arguments are currently fixed in the manager;
- the default server port is assumed to be 25565;
- the application runtime is expected to live beside server data;
- UI text is currently primarily Russian.

These are tracked as refactoring work, not hidden behavior. See [ROADMAP](docs/ROADMAP.md).

## License

No open-source license has been selected yet. Until a `LICENSE` file is added, normal copyright restrictions apply.

## Third-party components

Third-party binaries are not committed to this repository. The bootstrap script downloads pinned versions of PixiJS and Microsoft WebView2 components. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
