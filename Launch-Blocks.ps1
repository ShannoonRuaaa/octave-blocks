[CmdletBinding()]
param([string] $OctaveHome, [switch] $SelfTest)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ProcessStartInfo.ArgumentList is unavailable in Windows PowerShell 5.1.
# Quote according to the Windows C runtime rules, including empty arguments
# and backslashes before quotes or the closing quote.
function Format-WindowsArgument {
    param([string] $Value)
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}
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
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if (-not $pwsh) { throw 'The test runner needs PowerShell 7+. Install pwsh or run tests/Run-Tests.ps1 from PowerShell 7.' }
        & $pwsh.Source -NoProfile -File (Join-Path $PSScriptRoot 'tests/Run-Tests.ps1') -OctaveHome $OctaveHome
        exit $LASTEXITCODE
    }
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
$arguments = @('--gui', '--persist', '--eval', "addpath('$sourcePath'); ob_setup(); octave_blocks();")
$startInfo.Arguments = ($arguments | ForEach-Object { Format-WindowsArgument $_ }) -join ' '
$child = [System.Diagnostics.Process]::Start($startInfo)
Write-Output "Launched Octave Blocks (process $($child.Id))."
