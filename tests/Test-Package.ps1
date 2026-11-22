[CmdletBinding()]
param([string] $OctaveHome, [string] $OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PSScriptRoot ('.artifacts/package-' + [guid]::NewGuid().ToString('N'))
}
$releaseVersion = (Get-Content -LiteralPath (Join-Path $root 'DESCRIPTION') | Select-String '^Version:').ToString().Split(':')[1].Trim()
& (Join-Path $root 'tools/Package-Release.ps1') -Version $releaseVersion -Revision HEAD -OutputDirectory $OutputDirectory
$folder = (Resolve-Path -LiteralPath $OutputDirectory).Path.Replace('\','/').Replace("'","''")
$bin = Join-Path $OctaveHome 'mingw64/bin'
$env:PATH = $bin + [IO.Path]::PathSeparator + (Join-Path $OctaveHome 'usr/bin') + [IO.Path]::PathSeparator + $env:PATH
$expression = @"
folder='$folder';
pkg('local_list',fullfile(folder,'packages.list'));
pkg('prefix',fullfile(folder,'installed'),fullfile(folder,'arch'));
pkg('install',fullfile(folder,'octave-blocks-$releaseVersion.tar.gz'));
pkg('load','octave-blocks');
assert(isempty(which('test_ob_run')) && isempty(which('ob_c_number_list')));
m=ob_oscillator(); t=0:.1:1;
r=ob_run(m,t); assert(max(abs(ob_scope_data(r,4)(:)-cos(t(:))))<1e-5);
ob_codegen(m,fullfile(folder,'package-adaptive.c'),[0 1 .1],struct('solver','ode45'));
source=fileread(fullfile(folder,'package-adaptive.c'));
assert(!isempty(strfind(source,'SPDX-License-Identifier: GPL-3.0-or-later')));
setenv('OB_ACCELERATOR_CACHE',fullfile(folder,'cache'));
[a,info]=ob_accelerate(m,t); assert(max(abs(ob_scope_data(a,4)(:)-ob_scope_data(r,4)(:)))<1e-12);
ob_simulink_setup(); new_system('package_smoke'); bdclose('package_smoke');
pkg('unload','octave-blocks');
assert(isempty(which('ob_run')) && isempty(which('new_system')));
disp('Native package install, API, simulation, acceleration, GPL emission and unload passed');
"@
& (Join-Path $bin 'octave-cli.exe') --quiet --eval $expression
if ($LASTEXITCODE -ne 0) { throw 'Installed package verification failed.' }
$source = Join-Path $OutputDirectory 'package-adaptive.c'
$binary = Join-Path $OutputDirectory 'package-adaptive.exe'
& (Join-Path $bin 'gcc.exe') -std=c99 -O2 -Wall -Wextra -Werror -DOB_STANDALONE $source -lm -o $binary
if ($LASTEXITCODE -ne 0) { throw 'Installed package C compilation failed.' }
$csv = & $binary
if ($LASTEXITCODE -ne 0) { throw 'Installed package generated model failed.' }
Write-Output "Installed package C execution passed ($($csv.Count) CSV lines)."
