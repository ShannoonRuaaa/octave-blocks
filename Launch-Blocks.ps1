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
    $executable = Join-Path $binRoot 'octave-cli.exe'
    if (-not (Test-Path -LiteralPath $executable)) { throw "Octave not found: $executable" }
    & $executable --quiet --eval "addpath('$sourcePath'); test_ob_run(); test_ob_editor_core(); test_ob_solvers(); test_ob_subsystems(); test_ob_inputs(); test_ob_multirate(); test_ob_controls(); test_ob_runtime(); test_ob_runtime_metadata(); test_ob_conditional(); test_ob_enabled_continuous(); test_ob_enabled_multirate(); test_ob_linear_systems(); test_ob_matlab_numeric(); test_ob_multioutput(); test_ob_algebraic(); test_ob_zero_crossings(); test_ob_continuous_controls();"
    if ($LASTEXITCODE -ne 0) { throw 'Octave Blocks verification failed.' }
    & $executable --quiet --eval "addpath('$sourcePath'); test_ob_performance_graph(); test_ob_performance_metadata(); test_ob_performance_events(); [passed,total]=test(fullfile('$sourcePath','ob_execution_order.m'),'quiet'); assert(total>0 && passed==total); [passed,total]=test(fullfile('$sourcePath','ob_edges.m'),'quiet'); assert(total>0 && passed==total); addpath(fullfile('$sourcePath','private')); [passed,total]=test(fullfile('$sourcePath','private','ob_zc_snapshot.m'),'quiet'); assert(total>0 && passed==total);"
    if ($LASTEXITCODE -ne 0) { throw 'Optimization compatibility verification failed.' }
    & (Join-Path $PSScriptRoot 'Test-Codegen.ps1') -OctaveHome $OctaveHome
    & (Join-Path $PSScriptRoot 'Test-Editor.ps1') -OctaveHome $OctaveHome
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
