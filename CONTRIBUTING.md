# Contributing

Copperline Deck is currently in an early extraction and architecture phase.

## Workflow

1. Branch from `development`.
2. Keep changes focused and reviewable.
3. Do not commit Minecraft worlds, server logs, mod jars, Java runtimes, WebView2 caches, generated binaries, or credentials.
4. Run the validation workflow locally where possible.
5. Open a pull request back into `development`.

Release preparation will flow from `development` to `release`, then to `main`.

## Coding expectations

- Preserve server safety: UI-only changes must not restart Java.
- Keep runtime state outside tracked source files.
- Prefer explicit configuration over hard-coded machine paths.
- Keep the WebView rendering layer isolated from server control logic.
- Add comments for non-obvious Win32 behavior, not for self-evident code.
- Update docs when behavior or architecture changes materially.

## Commit style

Use concise imperative commit messages, for example:

- `Add profile-based server configuration`
- `Pause renderer when window is occluded`
- `Refactor command transport into runtime module`
