# Sets up the repo (portable Godot in engine/, shared/ linked into each game) and launches a game.
#   run.ps1 -Game tv-theatre|mushroom [-Mode play|edit|test2p|setup]
# The .bat files in the repo root call this, so you can just double-click those.
param(
    [ValidateSet("tv-theatre", "mushroom", "all")] [string]$Game = "all",
    [ValidateSet("play", "edit", "test2p", "setup")] [string]$Mode = "setup"
)
$ErrorActionPreference = "Stop"
$GodotVersion = "4.7.2-stable"
$Root = Split-Path -Parent $PSScriptRoot
$Engine = Join-Path $Root "engine"
$Godot = Join-Path $Engine "godot.exe"
$Games = @("tv-theatre", "mushroom")

# 1. Portable Godot, pinned so everyone runs the same engine.
if (-not (Test-Path $Godot)) {
    $zipName = "Godot_v${GodotVersion}_win64.exe.zip"
    $url = "https://github.com/godotengine/godot/releases/download/$GodotVersion/$zipName"
    $zip = Join-Path $Engine $zipName
    Write-Host "Downloading Godot $GodotVersion (about 85 MB) into engine/ ..."
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $Engine -Force
    Remove-Item $zip
    Move-Item (Join-Path $Engine "Godot_v${GodotVersion}_win64.exe") $Godot -Force
    $console = Join-Path $Engine "Godot_v${GodotVersion}_win64_console.exe"
    if (Test-Path $console) { Move-Item $console (Join-Path $Engine "godot_console.exe") -Force }
    # Self-contained mode: editor settings live in engine/editor_data, not in AppData.
    New-Item -ItemType File -Force (Join-Path $Engine "._sc_") | Out-Null
}

# 2. Link shared/ into each game (a directory junction, no admin rights needed).
#    Edits made through either game land in the one shared/ folder.
foreach ($g in $Games) {
    $link = Join-Path $Root "$g\shared"
    if (-not (Test-Path $link)) {
        New-Item -ItemType Junction -Path $link -Target (Join-Path $Root "shared") | Out-Null
    }
    if (-not (Test-Path (Join-Path $Root "$g\.godot"))) {
        Write-Host "First-time import of $g ..."
        & (Join-Path $Engine "godot_console.exe") --headless --path (Join-Path $Root $g) --import | Out-Null
    }
}

if ($Game -eq "all" -or $Mode -eq "setup") { Write-Host "Setup done."; exit 0 }

$path = Join-Path $Root $Game
switch ($Mode) {
    "play" { Start-Process $Godot -ArgumentList @("--path", "`"$path`"") }
    "edit" { Start-Process $Godot -ArgumentList @("-e", "--path", "`"$path`"") }
    "test2p" {
        # Two windows on this PC: one hosts, one joins. Handy for testing alone.
        Start-Process $Godot -ArgumentList @("--path", "`"$path`"", "--", "--host", "--name=Host")
        Start-Sleep -Seconds 2
        Start-Process $Godot -ArgumentList @("--path", "`"$path`"", "--", "--join=127.0.0.1", "--name=Guest")
    }
}
