# ================================
# 05A-Install-EncoreDeployService.ps1
# ================================
. "$PSScriptRoot\00-Config.ps1"
# ================================
# ENSURE RUN AS ADMIN
# ================================
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Host "Restarting script as Administrator..." -ForegroundColor Yellow

    Start-Process powershell.exe `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs

    exit
}

Write-Log "Installing EnCore Deploy Service (interactive mode)..."

$deployPath = "$($Config.BundlePath)\EncoreUpdater"

if (!(Test-Path $deployPath)) {
    Exit-OnError "EncoreUpdater folder not found: $deployPath"
}

$msi = Get-ChildItem $deployPath -Filter "*DeployService*.msi" | Select-Object -First 1

if (!$msi) {
    Exit-OnError "Deploy Service MSI not found"
}

Write-Log "Using installer: $($msi.Name)"

# ================================
# LAUNCH INTERACTIVE INSTALLER
# ================================
try {
    Write-Log "Launching MSI installer (manual input required)..."

    Start-Process "msiexec.exe" `
        -ArgumentList "/i `"$($msi.FullName)`"" `
        -Wait

    Write-Log "Installer closed"
}
catch {
    Exit-OnError "Failed launching MSI installer"
}

# ================================
# USER CONFIRMATION
# ================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "Complete the installation wizard manually." -ForegroundColor Yellow
Write-Host "Make sure to set the correct Service Account." -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""

Read-Host "Press ENTER once installation is completed"

# ================================
# VALIDATE SERVICE
# ================================
Write-Log "Validating Deploy Service installation..."

Start-Sleep -Seconds 3

$service = Get-Service | Where-Object {
    $_.Name -like "*EncoreDeploy*" -or $_.DisplayName -like "*Encore*Deploy*"
}

if (!$service) {
    Exit-OnError "Deploy service not found after installation"
}

Write-Log "Service detected: $($service.Name)"

# ================================
# VALIDATE SERVICE ACCOUNT
# ================================
try {
    $svc = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq $service.Name }

    Write-Log "Service running as: $($svc.StartName)"

    if ($svc.StartName -ne $Config.ServiceAccount) {
        Write-Log "WARNING: Service is not running under expected account ($($Config.ServiceAccount))" "WARNING"
    }
}
catch {
    Write-Log "Could not validate service account" "ERROR"
}

# ================================
# ENSURE SERVICE RUNNING
# ================================
try {
    if ($service.Status -ne "Running") {
        Start-Service $service.Name
        Write-Log "Service started successfully"
    }
    else {
        Write-Log "Service already running"
    }
}
catch {
    Write-Log "Failed to start service" "ERROR"
}

Write-Log "EnCore Deploy Service installation completed"
exit 0