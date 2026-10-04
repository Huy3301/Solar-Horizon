param (
    [switch]$ImportOnly
)

$godotBin = $env:GODOT_BIN
if (-not $godotBin) {
    $candidates = Get-ChildItem -Path "$env:USERPROFILE\tools\godot\*console.exe"
    if ($candidates.Count -gt 0) {
        $godotBin = $candidates[0].FullName
    } else {
        Write-Error "Godot binary not found."
        exit 1
    }
}

$repo = (Get-Item .).FullName
$logFile = "$repo\import.log"

Write-Host "Running Godot import..."
cmd.exe /c """$godotBin"" --headless --path ""$repo"" --import > ""$logFile"" 2>&1"
$importOutputStr = Get-Content $logFile -Raw
Write-Host $importOutputStr

$hasError = $false
if ($importOutputStr -match "SCRIPT ERROR" -or $importOutputStr -match "Parse Error" -or $importOutputStr -match "ERROR:") {
    $hasError = $true
}

if (-not $ImportOnly) {
    if (Test-Path "tests/run_tests.gd") {
        Write-Host "Running tests..."
        cmd.exe /c """$godotBin"" --headless --path ""$repo"" --script res://tests/run_tests.gd > ""$logFile"" 2>&1"
        $testExit = $LASTEXITCODE
        $testOutputStr = Get-Content $logFile -Raw
        Write-Host $testOutputStr
        
        if ($testExit -ne 0) {
            $hasError = $true
        }
    }
}

if ($hasError) {
    Write-Host "Validation FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "Validation PASSED" -ForegroundColor Green
    exit 0
}
