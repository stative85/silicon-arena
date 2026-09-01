#Requires -Version 5.1
<#
.SYNOPSIS
    SCAR TABLE — launch the visual scene. Nothing else required.

.DESCRIPTION
    No LM Studio, no browser, no model, no ports. Finds Godot, validates it by
    running it, and opens the table scene.
#>
[CmdletBinding()]
param([switch]$Wait)

$ErrorActionPreference = 'Stop'

$ProjectDir = $PSScriptRoot
$SceneArg = 'scenes/scar_table/scar_table.tscn'

function Find-Godot {
    $candidates = @()
    # Godot ships as a folder whose NAME ends in .exe, holding the real binaries.
    $roots = @(
        (Join-Path $env:USERPROFILE 'Downloads'),
        $ProjectDir
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $candidates += Get-ChildItem -Path $root -Filter 'Godot_v4*' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '.exe' } |
            Sort-Object Length -Descending |
            ForEach-Object { $_.FullName }
    }
    $cmd = Get-Command 'godot' -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }

    foreach ($c in $candidates) {
        # Validate by RUNNING it. The console build is a 200KB stub next to a
        # 170MB binary, and picking by size or name has misfired here before.
        try {
            $out = & $c --version 2>&1 | Out-String
            if ($out -match '4\.6') { return $c }
        } catch { }
    }
    return $null
}

$godot = Find-Godot
if (-not $godot) {
    Write-Host ''
    Write-Host '  Could not find Godot 4.6.' -ForegroundColor Red
    Write-Host '  Looked in your Downloads folder and this project folder.' -ForegroundColor Yellow
    Write-Host ''
    Read-Host 'Press Enter to close'
    exit 1
}

Write-Host ''
Write-Host '  SCAR TABLE' -ForegroundColor White
Write-Host "  godot: $godot" -ForegroundColor DarkGray
Write-Host ''

$argList = @('--path', $ProjectDir, $SceneArg)
if ($Wait) {
    & $godot @argList
} else {
    Start-Process -FilePath $godot -ArgumentList $argList -WorkingDirectory $ProjectDir | Out-Null
    Start-Sleep -Seconds 3
    Write-Host '  running.' -ForegroundColor Green
}
