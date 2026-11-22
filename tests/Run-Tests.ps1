[CmdletBinding()]
param([string] $OctaveHome, [ValidateRange(1,4)] [int] $Workers = 2, [string[]] $Stages)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OctaveHome) {
    $roots = @((Join-Path $env:LOCALAPPDATA 'Programs/GNU Octave'), (Join-Path $env:ProgramFiles 'GNU Octave'))
    $installed = @(foreach ($directory in $roots) {
        if (Test-Path -LiteralPath $directory) {
            Get-ChildItem -LiteralPath $directory -Directory | Where-Object Name -Match '^Octave-\d+\.\d+\.\d+$'
        }
    }) | Sort-Object { [version]($_.Name -replace '^Octave-','') } -Descending
    if (-not $installed) { throw 'Supply -OctaveHome with your GNU Octave installation.' }
    $OctaveHome = $installed[0].FullName
}
$bin = Join-Path $OctaveHome 'mingw64/bin'
$cli = Join-Path $bin 'octave-cli.exe'
if (-not (Test-Path -LiteralPath $cli)) { throw "Octave not found: $cli" }
$run = Join-Path $PSScriptRoot ('.artifacts/gate-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($run) | Out-Null
$definitions = @(
    @{Name='engine'; Code='test_ob_run(); test_ob_editor_core(); test_ob_solvers(); test_ob_subsystems(); test_ob_inputs(); test_ob_multirate(); test_ob_controls(); test_ob_runtime(); test_ob_runtime_metadata();'},
    @{Name='conditional'; Code='test_ob_conditional(); test_ob_enabled_continuous(); test_ob_enabled_multirate(); test_ob_combined_controls(); test_ob_nested_reset();'},
    @{Name='events'; Code='test_ob_zero_crossings(); test_ob_continuous_controls();'},
    @{Name='systems'; Code='test_ob_linear_systems(); test_ob_matlab_numeric(); test_ob_multioutput(); test_ob_algebraic(); test_ob_delay_integrator(); test_ob_delay_matlab();'},
    @{Name='performance'; Code='test_ob_performance_graph(); test_ob_performance_metadata(); test_ob_performance_events(); test_ob_runtime_fast_paths();'},
    @{Name='audit'; Code='test_ob_codegen_metadata(); test_ob_codegen_adjacency(); test_ob_builtin_controls(); test_ob_transfer_builtin(); test_ob_dmperm_order(); test_ob_advanced_simulink(); test_ob_c_event_inventory();'},
    @{Name='embedded'; Code='test_ob_execution_order_bist(); test_ob_edges_bist(); test_ob_zc_snapshot_bist(); test_ob_block_parameters_bist(); test_ob_transport_delay_bist(); test_ob_ode_settings_bist(); test_ob_dormand_prince_bist();'},
    @{Name='api'; Code='test_ob_simulink_api(); test_ob_simulink_api_reference(); test_ob_simulink_delay_integrator();'},
    @{Name='reference-conditional'; Code='test_ob_simulink_conditional();'},
    @{Name='reference-extended'; Code='test_ob_simulink_extended();'},
    @{Name='reference-benchmarks'; Code='test_ob_simulink_benchmarks("",false,true);'},
    @{Name='accelerator'; Code='test_ob_accelerate();'},
    @{Name='c-codegen'; Script='Test-Codegen.ps1'},
    @{Name='c-combined'; Script='Test-CombinedCodegen.ps1'},
    @{Name='c-input'; Script='Test-CInputLookup.ps1'},
    @{Name='c-event'; Script='Test-EventCodegen.ps1'},
    @{Name='c-edges'; Script='Test-EventCodegenEdges.ps1'},
    @{Name='c-hierarchy'; Script='Test-EventCodegenHierarchy.ps1'},
    @{Name='package'; Script='Test-Package.ps1'},
    @{Name='editor'; Script='Test-Editor.ps1'}
)
if ($Stages) {
    $unknown = @($Stages | Where-Object { $_ -notin $definitions.Name })
    if ($unknown) { throw "Unknown stages: $unknown" }
    $definitions = @($definitions | Where-Object Name -In $Stages)
}
function Get-SourceHashes {
    $hashes = [ordered]@{}
    foreach ($directory in @('inst','tests','tools')) {
        Get-ChildItem -LiteralPath (Join-Path $root $directory) -File -Recurse |
            Where-Object { $_.FullName -notlike '*\.artifacts\*' -and $_.Extension -in @('.m','.ps1') } |
            Sort-Object FullName | ForEach-Object {
                $relative = [IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')
                $hashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
    }
    foreach ($file in @('ob_setup.m','DESCRIPTION','COPYING','LICENSE','NOTICE')) {
        $hashes[$file] = (Get-FileHash -LiteralPath (Join-Path $root $file) -Algorithm SHA256).Hash
    }
    return $hashes
}
$before = Get-SourceHashes
$before | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run 'source-hashes.json') -Encoding utf8
$revision = & git -c "safe.directory=$($root.Replace('\','/'))" -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not identify the test revision.' }
$version = & $cli --version | Select-Object -First 1
$manifest = [ordered]@{Revision=$revision; Octave=$version; PowerShell=$PSVersionTable.PSVersion.ToString(); StartedUtc=[DateTime]::UtcNow.ToString('o'); Stages=@(); SourceUnchanged=$false; Complete=$false}
$manifestFile = Join-Path $run 'manifest.json'
$queue = [Collections.Generic.Queue[object]]::new()
foreach ($definition in $definitions) { $queue.Enqueue($definition) }
$active = [Collections.Generic.List[object]]::new()
$shell = (Get-Process -Id $PID).Path
Write-Output "Verification artifacts: $run"
while ($queue.Count -or $active.Count) {
    while ($queue.Count -and $active.Count -lt $Workers) {
        $definition = $queue.Dequeue()
        if ($definition.Name -eq 'editor' -and $active.Count) { $queue.Enqueue($definition); break }
        $spec = Join-Path $run ($definition.Name + '.json')
        $definition | ConvertTo-Json | Set-Content -LiteralPath $spec -Encoding utf8
        $stdout = Join-Path $run ($definition.Name + '.log')
        $stderr = Join-Path $run ($definition.Name + '.stderr.log')
        $arguments = @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Invoke-TestStage.ps1'),'-Specification',$spec,'-OctaveHome',$OctaveHome)
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $shell; $start.UseShellExecute = $false; $start.CreateNoWindow = $true; $start.WindowStyle = 'Hidden'
        $start.WorkingDirectory = $root; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
        foreach ($argument in $arguments) { $start.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::Start($start)
        $active.Add(@{Definition=$definition; Process=$process; OutTask=$process.StandardOutput.ReadToEndAsync(); ErrTask=$process.StandardError.ReadToEndAsync(); Started=[DateTime]::UtcNow; Out=$stdout; Err=$stderr})
        Write-Output "Started $($definition.Name)"
        if ($definition.Name -eq 'editor') { break }
    }
    foreach ($job in @($active.ToArray())) {
        if (-not $job.Process.HasExited) { continue }
        $job.Process.WaitForExit()
        $job.OutTask.GetAwaiter().GetResult() | Set-Content -LiteralPath $job.Out -Encoding utf8
        $job.ErrTask.GetAwaiter().GetResult() | Set-Content -LiteralPath $job.Err -Encoding utf8
        $entry = @{Name=$job.Definition.Name; ExitCode=$job.Process.ExitCode; Seconds=([DateTime]::UtcNow-$job.Started).TotalSeconds; Stdout=$job.Out; Stderr=$job.Err}
        $manifest.Stages += $entry
        Write-Output "Finished $($entry.Name): exit $($entry.ExitCode)"
        $active.Remove($job) | Out-Null
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestFile -Encoding utf8
    }
    if ($active.Count) { Start-Sleep -Milliseconds 500 }
}
$after = Get-SourceHashes
$manifest.SourceUnchanged = (($before | ConvertTo-Json -Compress) -ceq ($after | ConvertTo-Json -Compress))
$manifest.FinishedUtc = [DateTime]::UtcNow.ToString('o')
$manifest.Complete = ($manifest.SourceUnchanged -and @($manifest.Stages | Where-Object ExitCode -NE 0).Count -eq 0)
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestFile -Encoding utf8
if (-not $manifest.Complete) { throw "Verification failed or source changed; inspect $manifestFile" }
Write-Output "All $($manifest.Stages.Count) stages passed with unchanged source. Manifest: $manifestFile"
