$ErrorActionPreference = "Stop"

# 1. Check Android SDK
$androidSdk = $env:ANDROID_HOME
if ([string]::IsNullOrEmpty($androidSdk)) {
    $androidSdk = $env:ANDROID_SDK_ROOT
}

if ([string]::IsNullOrEmpty($androidSdk) -or -not (Test-Path $androidSdk)) {
    Write-Error "Android SDK not found. Please set ANDROID_HOME or ANDROID_SDK_ROOT environment variable to a valid path."
    exit 1
}

Write-Host "Found Android SDK at: $androidSdk"

# 2. Check Godot Export Templates
$godotVersion = "4.7.2.stable"
$templatesPath = Join-Path $env:APPDATA "Godot\export_templates\$godotVersion"
if (-not (Test-Path $templatesPath)) {
    Write-Error "Godot export templates not found for version $godotVersion at: $templatesPath. Please install them."
    exit 1
}

Write-Host "Found Godot export templates at: $templatesPath"

# 3. Export Android APK
$godotExe = "C:\Users\nguye\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godotExe)) {
    $found = Get-ChildItem "C:\Users\nguye\tools\godot\*console.exe" | Select-Object -First 1
    if ($found) {
        $godotExe = $found.FullName
    }
}

if (-not (Test-Path $godotExe)) {
    Write-Error "Godot executable not found at C:\Users\nguye\tools\godot\."
    exit 1
}

$projectPath = "C:\code\Solar-Horizon"
$exportPath = "$projectPath\exports\android\SolarHorizon.apk"

# Ensure export directory exists
$exportDir = Split-Path $exportPath
if (-not (Test-Path $exportDir)) {
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
}

Write-Host "Starting Android export..."
& $godotExe --headless --path $projectPath --export-release "Android" $exportPath

if ($LASTEXITCODE -eq 0) {
    Write-Host "Android export completed successfully: $exportPath"
} else {
    Write-Error "Android export failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
