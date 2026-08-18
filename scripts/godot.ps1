param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GodotArgs
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$engine = Join-Path $root '.tools\godot\Godot_v4.7.1-stable_win64.exe'

if (-not (Test-Path $engine)) {
    throw "Godot engine not found at $engine"
}

$env:APPDATA = Join-Path $root '.tools\godot-appdata'
$env:LOCALAPPDATA = Join-Path $root '.tools\godot-local'
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null

& $engine @GodotArgs
exit $LASTEXITCODE

