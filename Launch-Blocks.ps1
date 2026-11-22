[CmdletBinding()]
param([string] $OctaveHome, [switch] $SelfTest)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $OctaveHome) {
    $searchRoots = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\GNU Octave'),
        (Join-Path $env:ProgramFiles 'GNU Octave')
    )
    $installations = @(foreach ($root in $searchRoots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Directory |
                Where-Object { $_.Name -match '^Octave-\d+\.\d+\.\d+$' }
        }
    })
    $installations = @($installations | Sort-Object {
        [version] ($_.Name -replace '^Octave-', '')
    } -Descending)
    if ($installations.Count -eq 0) {
        throw 'Octave was not found. Supply -OctaveHome with the installation folder.'
    }
    $OctaveHome = $installations[0].FullName
}
$binRoot = Join-Path $OctaveHome 'mingw64\bin'
$sourcePath = $PSScriptRoot.Replace('\', '/').Replace("'", "''")
if ($SelfTest) {
    & (Join-Path $PSScriptRoot 'tests/Run-Tests.ps1') -OctaveHome $OctaveHome
    return
}
$executable = Join-Path $binRoot 'octave-gui.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw "Octave not found: $executable" }
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $executable
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WorkingDirectory = $PSScriptRoot
foreach ($argument in @('--gui', '--persist', '--eval', "addpath('$sourcePath'); octave_blocks();")) {
    $startInfo.ArgumentList.Add($argument)
}
$child = [System.Diagnostics.Process]::Start($startInfo)
Write-Output "Launched Octave Blocks (process $($child.Id))."
