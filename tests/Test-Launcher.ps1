[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Launch-Blocks.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
# Load only the quoting helper, so this check never launches the editor.
$function = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Format-WindowsArgument'}, $true)
. ([scriptblock]::Create($function.Extent.Text))
$cases = @(
    @('', '""'),
    @('plain', 'plain'),
    @('two words', '"two words"'),
    @('a"b', '"a\"b"'),
    @('C:\folder name\', '"C:\folder name\\"'),
    @('a\"b', '"a\\\"b"')
)
foreach ($case in $cases) {
    $actual = Format-WindowsArgument $case[0]
    if ($actual -cne $case[1]) { throw "Argument quoting mismatch: $actual" }
}
Write-Output "Launcher syntax and $($cases.Count) Windows argument quoting cases passed on PowerShell $($PSVersionTable.PSVersion)."
