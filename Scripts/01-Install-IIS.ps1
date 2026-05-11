param(
    [ValidateSet("Full", "Default")]
    [string]$Mode = "Full"
)

. "$PSScriptRoot\00-Config.ps1"

if ($Mode -eq "Default") {
    Write-Log "Installing IIS default feature set for EnCore..."

    try {
        $result = Get-WindowsFeature -Name "Web-Server"

        if ($result.Installed -eq $false) {
            Install-WindowsFeature -Name "Web-Server" -IncludeManagementTools -ErrorAction Stop
            Write-Log "Installed default IIS role: Web-Server"
        }
        else {
            Write-Log "Default IIS role already installed: Web-Server"
        }
    }
    catch {
        Exit-OnError "Failed installing default IIS role"
    }

    Write-Log "IIS default installation completed successfully"
    exit 0
}

Write-Log "Installing IIS full feature set for EnCore..."

$features = @(
    "Web-Server",
    "Web-Default-Doc",
    "Web-Dir-Browsing",
    "Web-Http-Errors",
    "Web-Static-Content",
    "Web-Http-Logging",
    "Web-Log-Libraries",
    "Web-Request-Monitor",
    "Web-Http-Tracing",
    "Web-Stat-Compression",
    "Web-Dyn-Compression",
    "Web-Filtering",
    "Web-Basic-Auth",
    "Web-Windows-Auth",
    "Web-Url-Auth",
    "Web-IP-Security",
    "Web-Net-Ext45",
    "Web-Asp-Net45",
    "Web-ISAPI-Ext",
    "Web-ISAPI-Filter",
    "Web-WebSockets",
    "Web-Mgmt-Console",
    "Web-Mgmt-Tools",
    "Web-Mgmt-Service",
    "Web-WMI",
    "NET-Framework-45-Core",
    "NET-Framework-45-ASPNET",
    "NET-WCF-HTTP-Activation45"
)

foreach ($feature in $features) {
    try {
        $result = Get-WindowsFeature -Name $feature

        if ($result.Installed -eq $false) {
            Install-WindowsFeature -Name $feature -IncludeManagementTools -ErrorAction Stop
            Write-Log "Installed: $feature"
        }
        else {
            Write-Log "Already installed: $feature"
        }
    }
    catch {
        Exit-OnError "Failed installing $feature"
    }
}

Write-Log "IIS FULL installation completed successfully"
exit 0
