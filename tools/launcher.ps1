# Launcher for both games. play.bat in the repo root runs this.
#
# First run: downloads the pinned portable Godot into engine/ and links shared/ into each game.
# Then shows a menu. Can also be called directly:
#   launcher.ps1 -Game tv-theatre|mushroom [-Mode play|edit|test2p]
#   launcher.ps1 -Setup
param(
    [ValidateSet("", "tv-theatre", "mushroom")] [string]$Game = "",
    [ValidateSet("play", "edit", "test2p")] [string]$Mode = "play",
    [switch]$Setup
)
$ErrorActionPreference = "Stop"
$GodotVersion = "4.7.2-stable"
$Root = Split-Path -Parent $PSScriptRoot
$Engine = Join-Path $Root "engine"
$Godot = Join-Path $Engine "godot.exe"
$GameNames = [ordered]@{ "tv-theatre" = "STANDBY... GO! (TV studio + theatre)"; "mushroom" = "Mushroom Foraging" }

function Install-Engine {
    if (Test-Path $Godot) { return }
    $name = "Godot_v${GodotVersion}_win64"
    $zip = Join-Path $Engine "$name.exe.zip"
    Write-Host "Downloading Godot $GodotVersion (about 85 MB, one time only)..."
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/$GodotVersion/$name.exe.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $Engine -Force
    Remove-Item $zip
    Move-Item (Join-Path $Engine "$name.exe") $Godot -Force
    Remove-Item (Join-Path $Engine "${name}_console.exe") -ErrorAction SilentlyContinue
    # Self-contained mode: editor settings stay in engine/ instead of AppData.
    New-Item -ItemType File -Force (Join-Path $Engine "._sc_") | Out-Null
}

# Each game sees shared/ as res://shared through a directory junction (no admin rights needed).
function Connect-Shared {
    foreach ($g in $GameNames.Keys) {
        $dir = Join-Path $Root "games\$g"
        if (-not (Test-Path (Join-Path $dir "shared"))) {
            New-Item -ItemType Junction -Path (Join-Path $dir "shared") -Target (Join-Path $Root "shared") | Out-Null
        }
        if (-not (Test-Path (Join-Path $dir ".godot"))) {
            Write-Host "Preparing $($GameNames[$g]) for its first launch..."
            Start-Process $Godot -ArgumentList "--headless --path `"$dir`" --import" -Wait -WindowStyle Hidden
        }
    }
}

function Start-Game([string]$g, [string]$m) {
    $path = "`"$(Join-Path $Root "games\$g")`""
    switch ($m) {
        "play" { Start-Process $Godot -ArgumentList "--path $path" }
        "edit" { Start-Process $Godot -ArgumentList "-e --path $path" }
        "test2p" {
            Start-Process $Godot -ArgumentList "--path $path -- --host --name=Host"
            Start-Sleep -Seconds 2
            Start-Process $Godot -ArgumentList "--path $path -- --join=127.0.0.1 --name=Guest"
        }
    }
}

Install-Engine
Connect-Shared
if ($Setup) { Write-Host "Setup done."; exit 0 }
if ($Game) { Start-Game $Game $Mode; exit 0 }

$menu = @(
    @("tv-theatre", "play", "Play  STANDBY... GO! (TV studio + theatre)"),
    @("mushroom", "play", "Play  Mushroom Foraging"),
    @("tv-theatre", "test2p", "Test  STANDBY... GO! alone, two windows (host + guest)"),
    @("mushroom", "test2p", "Test  Mushroom Foraging alone, two windows (host + guest)"),
    @("tv-theatre", "edit", "Edit  STANDBY... GO! in the Godot editor"),
    @("mushroom", "edit", "Edit  Mushroom Foraging in the Godot editor")
)
Write-Host ""
for ($i = 0; $i -lt $menu.Count; $i++) { Write-Host "  $($i + 1)  $($menu[$i][2])" }
Write-Host ""
$choice = Read-Host "Pick a number and press Enter"
$n = 0
if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $menu.Count) {
    Start-Game $menu[$n - 1][0] $menu[$n - 1][1]
} else {
    Write-Host "No such option."
    exit 1
}
