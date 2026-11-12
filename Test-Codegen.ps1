[CmdletBinding()]
param([string] $OctaveHome, [string] $Compiler, [string] $OutputDirectory)

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
if (-not $Compiler) { $Compiler = Join-Path $binRoot 'gcc.exe' }
if (-not (Test-Path -LiteralPath $Compiler)) { throw "C compiler not found: $Compiler" }
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('octave-blocks-codegen-' + [guid]::NewGuid().ToString('N'))
}
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$artifactRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$octaveSource = $PSScriptRoot.Replace('\', '/').Replace("'", "''")
$octaveArtifacts = $artifactRoot.Replace('\', '/').Replace("'", "''")
$codegenPreviousPath = $env:PATH
try {
    $env:PATH = $binRoot + [IO.Path]::PathSeparator + (Split-Path -Parent $Compiler) + [IO.Path]::PathSeparator + $env:PATH
    & $octaveExecutable --quiet --eval "addpath('$octaveSource'); test_ob_codegen('$octaveArtifacts');"
    if ($LASTEXITCODE -ne 0) { throw 'C export preparation failed.' }
    $cases = Get-Content -LiteralPath (Join-Path $artifactRoot 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($case in $cases) {
        $source = Join-Path $artifactRoot $case.source
        $binary = Join-Path $artifactRoot ($case.name + '.exe')
        $arguments = @('-std=c99', '-O2', '-Wall', '-Wextra', '-Werror')
        if ($case.standalone) { $arguments += '-DOB_STANDALONE' }
        $arguments += @($source, '-lm', '-o', $binary)
        & $Compiler @arguments
        if ($LASTEXITCODE -ne 0) { throw "Compilation failed for $($case.name)" }
        $output = & $binary
        if ($LASTEXITCODE -ne 0) { throw "Generated executable failed for $($case.name)" }
        if ($case.standalone) {
            $output | Set-Content -LiteralPath (Join-Path $artifactRoot ($case.name + '.csv')) -Encoding utf8NoBOM
        } else { $output | Write-Output }
    }
    & $octaveExecutable --quiet --eval "addpath('$octaveSource'); verify_ob_codegen('$octaveArtifacts');"
    if ($LASTEXITCODE -ne 0) { throw 'Generated C differs from Octave.' }
    Write-Output "Code generation verification passed. Artifacts: $artifactRoot"
} finally { $env:PATH = $codegenPreviousPath }
