[CmdletBinding()]
param([string] $OctaveHome, [switch] $Benchmark)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $OctaveHome) {
    $roots = @((Join-Path $env:LOCALAPPDATA 'Programs\GNU Octave'), (Join-Path $env:ProgramFiles 'GNU Octave'))
    $installations = @(foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Directory |
                Where-Object { $_.Name -match '^Octave-\d+\.\d+\.\d+$' }
        }
    })
    $installations = @($installations | Sort-Object { [version] ($_.Name -replace '^Octave-', '') } -Descending)
    if ($installations.Count -eq 0) { throw 'Supply -OctaveHome with an Octave installation.' }
    $OctaveHome = $installations[0].FullName
}
$executable = Join-Path $OctaveHome 'mingw64\bin\octave-gui.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw "Octave GUI runtime not found: $executable" }
$artifactDirectory = Join-Path ([IO.Path]::GetTempPath()) ('octave-blocks-editor-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($artifactDirectory) | Out-Null
$logFile = Join-Path $artifactDirectory 'editor.log'
$octaveLog = $logFile.Replace('\', '/').Replace("'", "''")
$source = $PSScriptRoot.Replace('\', '/').Replace("'", "''")
$extra = ''
if ($Benchmark) { $extra = 'benchmark_ob_editor_ui([10 40],6);' }
$expression = @"
addpath('$source'); diary('$octaveLog');
try
  test_ob_editor_graphics(); $extra
  diary off; exit(0);
catch err
  disp(err.message);
  for frame=err.stack', disp([frame.name ':' num2str(frame.line)]); endfor
  diary off; exit(1);
end_try_catch
"@
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = $executable
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.WindowStyle = 'Hidden'
$start.WorkingDirectory = $PSScriptRoot
foreach ($argument in @('--gui', '--quiet', '--eval', $expression)) { $start.ArgumentList.Add($argument) }
$child = [Diagnostics.Process]::Start($start)
$child.WaitForExit()
if (Test-Path -LiteralPath $logFile) { Get-Content -LiteralPath $logFile }
if ($child.ExitCode -ne 0) { throw "Qt editor verification failed (exit $($child.ExitCode)). Log: $logFile" }
Write-Output "Qt editor verification passed. Artifacts: $artifactDirectory"
