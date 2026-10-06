# Architecture

Copperline Deck currently consists of four layers.

## 1. Native launcher

`src/launcher/CopperlineDeckLauncher.cs` is a minimal Windows launcher. Its only responsibility is to start the PowerShell shell without showing an intermediate console window.

The launcher must remain intentionally small. Application behavior belongs in the runtime layer.

## 2. Desktop shell

`src/runtime/CopperlineDeck.ps1` owns:

- the WinForms application window;
- status controls and command input;
- WebView2 initialization;
- log synchronization;
- server state presentation;
- visibility and occlusion checks;
- rendering pause/resume signaling.

The shell does not directly own the Minecraft Java process.

## 3. Server manager

`src/runtime/server-manager.ps1` owns the long-lived Minecraft process and redirected stdin/stdout.

`server-control.ps1` communicates with the manager through request/response files under `.control\`. This allows the UI to close without stopping the server.

This separation is important and should be preserved during refactoring.

## 4. Web UI

`src/runtime/webui/` contains the log renderer and GPU effects.

- `index.html` defines the log surface and floating controls.
- `app.js` handles log rendering, PixiJS graphics, particles, links, and renderer suspension.
- `energy-lab.js` contains the energy-cycle and shader logic.

The web UI receives messages from the host and must not gain direct authority to start processes or mutate server files.

## Current coupling

The original deployment placed application files directly inside a Fabric server directory. The development snapshot therefore still assumes relative access to:

- `logs\`;
- `.control\`;
- `world\session.lock`;
- the Fabric server jar;
- a bundled Java runtime.

The next architecture milestone is a profile object that separates **application root** from **server root**.

## Target direction

A future installation should resemble:

```text
Copperline Deck application
  profiles/
    local-fabric.json
    modded-server.json
  runtime/
  webui/

Minecraft servers
  D:\Servers\Fabric-A
  D:\Servers\Create-Pack
```

Copperline Deck should then manage one or more external server roots without copying application code into those directories.
