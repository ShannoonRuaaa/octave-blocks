[CmdletBinding()]
param(
    [string] $OctaveHome,
    [string] $Compiler,
    [string] $OutputDirectory,
    [switch] $Benchmark
)

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
    if ($installations.Count -eq 0) { throw 'Supply -OctaveHome with an Octave installation.' }
    $OctaveHome = $installations[0].FullName
}
$binRoot = Join-Path $OctaveHome 'mingw64\bin'
$octaveExecutable = Join-Path $binRoot 'octave-cli.exe'
if (-not (Test-Path -LiteralPath $octaveExecutable)) { throw "Octave not found: $octaveExecutable" }
if (-not $Compiler) { $Compiler = Join-Path $binRoot 'gcc.exe' }
if (-not (Test-Path -LiteralPath $Compiler)) { throw "C compiler not found: $Compiler" }
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Join-Path $PSScriptRoot '.artifacts') ('octave-blocks-c-input-lookup-' + [guid]::NewGuid().ToString('N'))
}
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$artifactRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$octaveSource = (Split-Path -Parent $PSScriptRoot).Replace('\', '/').Replace("'", "''")
$octaveArtifacts = $artifactRoot.Replace('\', '/').Replace("'", "''")
$inputLookupPreviousPath = $env:PATH
try {
    $env:PATH = $binRoot + [IO.Path]::PathSeparator + (Split-Path -Parent $Compiler) + [IO.Path]::PathSeparator + $env:PATH
    & $octaveExecutable --quiet --eval "addpath('$octaveSource'); addpath(fullfile('$octaveSource','tests')); test_ob_c_input_lookup('$octaveArtifacts'); test_ob_c_number_format('$octaveArtifacts');"
    if ($LASTEXITCODE -ne 0) { throw 'C input lookup harness preparation failed.' }
    foreach ($continuous in @(0, 1)) {
        $source = Join-Path $artifactRoot "c-input-lookup-$continuous.c"
        $binary = Join-Path $artifactRoot "c-input-lookup-$continuous.exe"
        & $Compiler '-std=c99' '-O2' '-Wall' '-Wextra' '-Werror' '-pedantic' $source '-lm' '-o' $binary
        if ($LASTEXITCODE -ne 0) { throw "C input lookup compilation failed for continuous=$continuous" }
        if ($Benchmark -and $continuous -eq 1) { & $binary '--benchmark' } else { & $binary }
        if ($LASTEXITCODE -ne 0) { throw "C input lookup oracle failed for continuous=$continuous" }
    }
    $formatSource = Join-Path $artifactRoot 'c-number-format.c'
    $formatBinary = Join-Path $artifactRoot 'c-number-format.exe'
    & $Compiler '-std=c99' '-O2' '-Wall' '-Wextra' '-Werror' '-pedantic-errors' $formatSource '-lm' '-o' $formatBinary
    if ($LASTEXITCODE -ne 0) { throw 'C number formatting compilation failed.' }
    & $formatBinary
    if ($LASTEXITCODE -ne 0) { throw 'C number formatting bitwise checks failed.' }
    Write-Output "C input lookup and number formatting verification passed. Artifacts: $artifactRoot"
} finally { $env:PATH = $inputLookupPreviousPath }
