# Development

## Local source tree

Keep source checkout separate from any live Minecraft server. A live server is test data, not the repository.

## Bootstrap

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

This downloads pinned third-party dependencies into `.deps\`, which is ignored by Git.

## Build

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1
```

The build creates `dist\` and compiles `CopperlineDeck.exe`.

## Validation

Before committing:

```powershell
node --check .\src\runtime\webui\app.js
node --check .\src\runtime\webui\energy-lab.js
```

PowerShell syntax can be validated without executing scripts:

```powershell
Get-ChildItem .\src -Recurse -Filter *.ps1 | ForEach-Object {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName,
        [ref]$null,
        [ref]$errors
    )
    if ($errors) { throw ($errors | Out-String) }
}
```

The GitHub Actions workflow performs equivalent checks on Windows.

## Live-server testing rules

- Back up the file being changed.
- UI-only changes must never restart Java.
- Compare the Java PID/start time before and after shell-only tests.
- Keep WebView JavaScript errors at zero.
- Never commit live logs, worlds, player databases, auth data, or server secrets.

## Branch model

- Feature branches start from `development`.
- `development` is continuously integrated.
- `release` is for stabilization only.
- `main` receives release-ready code.
