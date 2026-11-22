[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [string] $Revision = 'HEAD',
    [string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$') {
    throw 'Use a version such as 0.2.0-preview.1.'
}
$root = Split-Path -Parent $PSScriptRoot
$safeRoot = $root.Replace('\','/')
$gitArguments = @('-c', "safe.directory=$safeRoot", '-C', $root)
$status = & git @gitArguments status --porcelain
if ($LASTEXITCODE -ne 0 -or $status) { throw 'Commit the release changes before packaging.' }
$commit = & git @gitArguments rev-parse --verify "$Revision^{commit}"
if ($LASTEXITCODE -ne 0) { throw 'Unknown release revision.' }
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('octave-blocks-release-' + [guid]::NewGuid().ToString('N'))
}
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$folder = (Resolve-Path -LiteralPath $OutputDirectory).Path
$name = "octave-blocks-$Version"
$zip = Join-Path $folder "$name.zip"
if (Test-Path -LiteralPath $zip) { throw 'Release ZIP already exists; choose a fresh output folder.' }
& git @gitArguments archive --format=zip "--prefix=$name/" "--output=$zip" $commit
if ($LASTEXITCODE -ne 0) { throw 'Git archive failed.' }
$digest = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  $name.zip" | Set-Content -LiteralPath (Join-Path $folder 'SHA256SUMS.txt') -Encoding ascii
Write-Output "Packaged revision: $commit"
Write-Output "Release artifacts: $folder"
