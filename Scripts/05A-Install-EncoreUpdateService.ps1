# ================================
# 05A-Install-EncoreUpdateService.ps1
# ================================
. "$PSScriptRoot\00-Config.ps1"

Write-Log "Installing EnCore Update Manager and EnCore Update Service..."

$updaterPath = "$($Config.BundlePath)\EncoreUpdater"

if (!(Test-Path -LiteralPath $updaterPath)) {
    Exit-OnError "EncoreUpdater folder not found: $updaterPath"
}

$requiredInstallers = @(
    @{
        Label = "EnCore Update Manager"
        Pattern = "*UpdateManager*.msi"
        ServicePatterns = @("*Encore*Update*Manager*")
    },
    @{
        Label = "EnCore Update Service"
        Pattern = "*UpdateService*.msi"
        ServicePatterns = @("*Encore*Update*Service*")
    }
)

foreach ($installerInfo in $requiredInstallers) {
    $msi = Get-ChildItem -LiteralPath $updaterPath -Filter $installerInfo.Pattern -File | Select-Object -First 1

    if (!$msi) {
        Exit-OnError "$($installerInfo.Label) MSI not found in $updaterPath"
    }

    Write-Log "Launching installer for $($installerInfo.Label): $($msi.Name)"

    try {
        Start-Process "msiexec.exe" -ArgumentList "/i `"$($msi.FullName)`"" -Wait
    }
    catch {
        Exit-OnError "Failed launching installer for $($installerInfo.Label)"
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "Complete the installation wizard(s) manually." -ForegroundColor Yellow
Write-Host "Make sure to set the correct Service Account." -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""

Read-Host "Press ENTER once all EnCore update components are installed"

foreach ($installerInfo in $requiredInstallers) {
    $service = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        foreach ($pattern in $installerInfo.ServicePatterns) {
            if ($_.Name -like $pattern -or $_.DisplayName -like $pattern) {
                return $true
            }
        }

        return $false
    } | Select-Object -First 1

    if (!$service) {
        Exit-OnError "$($installerInfo.Label) service not found after installation"
    }

    Write-Log "Detected service for $($installerInfo.Label): $($service.Name)"

    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name = '$($service.Name)'"

        if ($svc) {
            Write-Log "$($installerInfo.Label) service account: $($svc.StartName)"

            if ($svc.StartName -ne $Config.ServiceAccount) {
                Write-Log "WARNING: $($installerInfo.Label) is not running under expected account ($($Config.ServiceAccount))" "WARNING"
            }
        }
    }
    catch {
        Write-Log "Could not validate service account for $($installerInfo.Label)" "ERROR"
    }

    try {
        if ($service.Status -ne "Running") {
            Start-Service -Name $service.Name
            Write-Log "Started service for $($installerInfo.Label)"
        }
        else {
            Write-Log "Service already running for $($installerInfo.Label)"
        }
    }
    catch {
        Write-Log "Failed to start service for $($installerInfo.Label)" "ERROR"
    }
}

Write-Log "EnCore update components installation completed"
exit 0
