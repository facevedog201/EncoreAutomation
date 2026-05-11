# ================================
# 00-Config.ps1
# ================================

$defaultBundlePath = "C:\InstallBundle"
if (-not (Test-Path -LiteralPath $defaultBundlePath)) {
    $defaultBundlePath = Join-Path $PSScriptRoot "InstallBundle"
}

$servicePassword = $env:ENCORE_SERVICE_PASSWORD
if ([string]::IsNullOrWhiteSpace($servicePassword)) {
    $servicePassword = "Password"   # Ideal: set ENCORE_SERVICE_PASSWORD before running.
}

# -------- GLOBAL CONFIG --------
$Global:Config = @{
    # Service Account
    ServiceAccount   = "" # Ideal: set Service account domain\username before running.
    ServicePassword  = $servicePassword

    # Paths
    InstallRoot      = "C:\EnCore"
    InetPubPath      = "C:\inetpub" # Ideal: set default inetpub folder before running.
    EncoreShare      = "C:\EncoreShare" # Ideal: set EncoreShare path before running.
    ScriptsPath      = $PSScriptRoot  # Ideal: set Copy C:\InstallBundle\Scripts before running.
    BundlePath       = $defaultBundlePath # Ideal: set Copy C:\InstallBundle\ before running.

    # Logging
    LogPath          = "C:\EnCore-Automation\Logs"
}

# -------- CREATE LOG DIRECTORY --------
if (!(Test-Path $Config.LogPath)) {
    New-Item -ItemType Directory -Path $Config.LogPath -Force | Out-Null
}

# -------- LOGGING FUNCTION --------
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )

    $caller = Get-PSCallStack | Select-Object -Skip 1 -First 1
    $scriptName = if ($caller.ScriptName) {
        Split-Path $caller.ScriptName -Leaf
    }
    else {
        "EnCore-Automation"
    }

    $logFile = "$($Config.LogPath)\$scriptName.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $entry = "$timestamp [$Level] $Message"

    # Output to console + file
    Write-Host $entry
    $entry | Out-File -FilePath $logFile -Append -Encoding utf8
}

# -------- ERROR HANDLER --------
function Exit-OnError {
    param (
        [string]$Message
    )

    Write-Log $Message "ERROR"
    exit 1
}

function Get-LocalAdministratorsName {
    $sid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    return $sid.Translate([System.Security.Principal.NTAccount]).Value
}

function Resolve-ServiceAccount {
    if (-not [string]::IsNullOrWhiteSpace($Config.ServiceAccount)) {
        return $Config.ServiceAccount.Trim()
    }

    $promptValue = Read-Host "Enter service account (domain\\username or .\\username)"

    if ([string]::IsNullOrWhiteSpace($promptValue)) {
        Exit-OnError "Service account is required"
    }

    $Config.ServiceAccount = $promptValue.Trim()
    Write-Log "Using service account: $($Config.ServiceAccount)"
    return $Config.ServiceAccount
}

# -------- VALIDATION (BASELINE) --------
function Test-Environment {
    Write-Log "Running environment validation..."

    if (-not ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {

        Exit-OnError "Script must be run as Administrator"
    }

    Write-Log "Running as Administrator ✔"
}

# Run baseline validation automatically
Test-Environment
