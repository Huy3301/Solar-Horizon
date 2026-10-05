# Solar Horizon CI Pipeline: import -> tests -> validate
param (
    [string]$GodotBin = ""
)

$ErrorActionPreference = "Stop"

if (-not $GodotBin) {
    if ($env:GODOT_BIN) {
        $GodotBin = $env:GODOT_BIN
    } else {
        $candidates = Get-ChildItem -Path "$env:USERPROFILE\tools\godot\*console.exe" -ErrorAction SilentlyContinue
        if ($candidates -and $candidates.Count -gt 0) {
            $GodotBin = $candidates[0].FullName
        } else {
            $found = Get-Command "godot" -ErrorAction SilentlyContinue
            if ($found) {
                $GodotBin = $found.Source
            }
        }
    }
}

if (-not $GodotBin -or -not (Test-Path $GodotBin)) {
    Write-Error "Godot binary not found. Set GODOT_BIN environment variable or pass -GodotBin."
    exit 1
}

$repo = (Get-Item (Join-Path $PSScriptRoot "..")).FullName
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Solar Horizon CI" -ForegroundColor Cyan
Write-Host "Repo: $repo" -ForegroundColor Cyan
Write-Host "Godot: $GodotBin" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

function Invoke-GodotWithTimeout {
    param (
        [string]$GodotPath,
        [string[]]$Arguments,
        [string]$OutputFile,
        [int]$TimeoutSeconds = 90
    )
    if (Test-Path $OutputFile) { Remove-Item -Force $OutputFile -ErrorAction SilentlyContinue }
    
    $argString = ($Arguments | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GodotPath
    $psi.Arguments = $argString
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    $stdoutTask = $p.StandardOutput.ReadToEndAsync()
    $stderrTask = $p.StandardError.ReadToEndAsync()

    $finished = $p.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) {
        try { $p.Kill() } catch {}
        Write-Host "ERROR: Execution timed out after $TimeoutSeconds seconds! Process terminated." -ForegroundColor Red
        return -1
    }

    [System.Threading.Tasks.Task]::WaitAll($stdoutTask, $stderrTask)
    $allOutput = $stdoutTask.Result + "`n" + $stderrTask.Result
    Set-Content -Path $OutputFile -Value $allOutput

    return [int]$p.ExitCode
}

# 1. Import (timeout 90s)
Write-Host "`n[Stage 1/3] Headless Import..." -ForegroundColor Yellow
$importLog = "$repo\ci_import.log"
$importExit = Invoke-GodotWithTimeout -GodotPath $GodotBin -Arguments @("--headless", "--path", $repo, "--editor", "--quit") -OutputFile $importLog -TimeoutSeconds 90
$importOutput = ""
if (Test-Path $importLog) {
    $importOutput = Get-Content $importLog -Raw
    Remove-Item -Force $importLog -ErrorAction SilentlyContinue
}

if ($importExit -ne 0 -or $importOutput -match "SCRIPT ERROR" -or $importOutput -match "Parse Error") {
    Write-Host $importOutput
    Write-Error "Stage 1: Headless import failed with exit code $importExit."
    exit 1
}
Write-Host "Stage 1: Headless import passed." -ForegroundColor Green

# 2. Tests (timeout 90s)
Write-Host "`n[Stage 2/3] Test Suite..." -ForegroundColor Yellow
$testLog = "$repo\ci_test.log"
$testExit = Invoke-GodotWithTimeout -GodotPath $GodotBin -Arguments @("--headless", "--path", $repo, "--script", "res://tests/run_tests.gd") -OutputFile $testLog -TimeoutSeconds 90
$testOutput = ""
if (Test-Path $testLog) {
    $testOutput = Get-Content $testLog -Raw
    Write-Host $testOutput
    Remove-Item -Force $testLog -ErrorAction SilentlyContinue
}

if ($testExit -ne 0) {
    Write-Error "Stage 2: Tests failed with exit code $testExit."
    exit 1
}
Write-Host "Stage 2: Tests passed." -ForegroundColor Green

# 3. Validate
Write-Host "`n[Stage 3/3] Validation..." -ForegroundColor Yellow
$validateScript = Join-Path $PSScriptRoot "validate.ps1"
if (Test-Path $validateScript) {
    & powershell.exe -ExecutionPolicy Bypass -File $validateScript
    $valExit = $LASTEXITCODE
    if ($valExit -ne 0) {
        Write-Error "Stage 3: Validation script failed with exit code $valExit."
        exit 1
    }
}
Write-Host "Stage 3: Validation passed." -ForegroundColor Green

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "All CI stages PASSED successfully!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
exit 0
