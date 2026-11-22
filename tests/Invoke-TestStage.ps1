[CmdletBinding()]
param([Parameter(Mandatory)] [string] $Specification, [Parameter(Mandatory)] [string] $OctaveHome)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$definition = Get-Content -LiteralPath $Specification -Raw | ConvertFrom-Json
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $OctaveHome 'mingw64/bin'
$env:PATH = $bin + [IO.Path]::PathSeparator + (Join-Path $OctaveHome 'usr/bin') + [IO.Path]::PathSeparator + $env:PATH
$scratch = Join-Path (Split-Path -Parent $Specification) 'scratch'
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$env:TMPDIR = $scratch; $env:TEMP = $scratch; $env:TMP = $scratch
try {
    if ($definition.PSObject.Properties.Name -contains 'Code') {
        $source = $root.Replace('\','/').Replace("'","''")
        & (Join-Path $bin 'octave-cli.exe') --quiet --eval "addpath('$source'); ob_setup('tests'); $($definition.Code)"
        exit $LASTEXITCODE
    }
    $arguments = @{OctaveHome=$OctaveHome}
    if ($definition.Script -ne 'Test-Editor.ps1') {
        $arguments.OutputDirectory = Join-Path (Split-Path -Parent $Specification) ($definition.Name + '-artifacts')
    }
    & (Join-Path $PSScriptRoot $definition.Script) @arguments
    exit 0
} catch {
    Write-Error $_
    exit 1
}
