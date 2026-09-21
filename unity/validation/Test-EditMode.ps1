<#
.SYNOPSIS
Compiles this kit in a real Unity Editor and runs its EditMode tests.

.DESCRIPTION
Builds a throwaway Unity project outside the repository, copies in
Assets/Companion together with the three canonical character helpers, and runs
the Companion.Presentation.Tests suite in batch mode.

This proves script compilation and receiver behaviour only. It imports no glTF
model, builds no scene and exports no Android project, so rendering, the
Unity-as-a-Library export and every device measurement remain unverified.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File validation/Test-EditMode.ps1
#>
param(
    [string]$UnityPath,
    [string]$ProjectPath = (Join-Path $env:TEMP 'CompanionRoomTests'),
    [switch]$Fresh
)

$ErrorActionPreference = 'Stop'
$kit = Resolve-Path (Join-Path $PSScriptRoot '..')
$character = Join-Path $kit '../assets/characters/robert/unity'

if (-not $UnityPath) {
    $editors = Join-Path ${env:ProgramFiles} 'Unity\Hub\Editor'
    if (-not (Test-Path $editors)) { throw "No Unity Hub editor directory at $editors. Pass -UnityPath." }
    $found = Get-ChildItem $editors -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'Editor\Unity.exe' } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
    if (-not $found) { throw "No Unity.exe found under $editors. Pass -UnityPath." }
    $UnityPath = $found
}
Write-Output "Unity:   $UnityPath"
Write-Output "Project: $ProjectPath"

if ($Fresh -and (Test-Path $ProjectPath)) { Remove-Item $ProjectPath -Recurse -Force }

if (-not (Test-Path (Join-Path $ProjectPath 'ProjectSettings'))) {
    Write-Output 'Creating the throwaway project (first run takes several minutes)...'
    $create = Start-Process -FilePath $UnityPath -PassThru -Wait -ArgumentList @(
        '-batchmode', '-quit', '-nographics', '-silent-crashes',
        '-createProject', $ProjectPath, '-logFile', (Join-Path $ProjectPath '..\companion-create.log'))
    if ($create.ExitCode -ne 0) { throw "Project creation failed with exit code $($create.ExitCode)." }
}

# The Test Framework is not a built-in module, so request it explicitly.
$manifestPath = Join-Path $ProjectPath 'Packages\manifest.json'
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if (-not $manifest.dependencies.'com.unity.test-framework') {
    $manifest.dependencies | Add-Member -NotePropertyName 'com.unity.test-framework' -NotePropertyValue '1.5.1'
    # Windows PowerShell's -Encoding utf8 writes a BOM, and Unity's package
    # manager rejects the manifest as invalid JSON if one is present.
    [System.IO.File]::WriteAllText(
        $manifestPath,
        ($manifest | ConvertTo-Json -Depth 10),
        (New-Object System.Text.UTF8Encoding $false))
    Write-Output 'Added com.unity.test-framework to the project manifest.'
}

$assets = Join-Path $ProjectPath 'Assets\Companion'
if (Test-Path $assets) { Remove-Item $assets -Recurse -Force }
Copy-Item (Join-Path $kit 'Assets\Companion') $assets -Recurse
New-Item -ItemType Directory -Path (Join-Path $assets 'Character') -Force | Out-Null
foreach ($script in @('RobertFacePlayer.cs', 'RobertSkinController.cs', 'RobertSkinDefinition.cs')) {
    Copy-Item (Join-Path $character $script) (Join-Path $assets "Character\$script") -Force
}
Write-Output 'Staged the kit and the canonical character helpers.'

$log = Join-Path $ProjectPath '..\companion-editmode.log'
$results = Join-Path $ProjectPath '..\companion-editmode.xml'
foreach ($f in @($log, $results)) { if (Test-Path $f) { Remove-Item $f } }

Write-Output 'Running EditMode tests...'
$run = Start-Process -FilePath $UnityPath -PassThru -Wait -ArgumentList @(
    '-batchmode', '-nographics', '-silent-crashes',
    '-projectPath', $ProjectPath,
    '-runTests', '-testPlatform', 'EditMode',
    '-testResults', $results, '-logFile', $log)

$compileErrors = Select-String -Path $log -Pattern 'error CS\d+' -ErrorAction SilentlyContinue
if ($compileErrors) {
    $compileErrors | Select-Object -First 20 | ForEach-Object { Write-Output $_.Line }
    throw 'Unity script compilation failed.'
}
if (-not (Test-Path $results)) { throw "No test results were written. See $log (exit code $($run.ExitCode))." }

[xml]$xml = Get-Content $results -Raw
$root = $xml.'test-run'
foreach ($case in $xml.SelectNodes('//test-case')) {
    Write-Output ("{0,-8} {1}" -f $case.result, $case.name)
    if ($case.result -ne 'Passed' -and $case.failure) { Write-Output ("         " + $case.failure.message.InnerText) }
}
Write-Output "total=$($root.total) passed=$($root.passed) failed=$($root.failed)"
if ([int]$root.failed -gt 0 -or $root.result -notlike 'Passed*') { throw 'EditMode tests failed.' }
Write-Output 'EditMode tests passed. Rendering, glTF import, the Android export and device behaviour remain unverified.'
