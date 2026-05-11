# ================================
# 08-Configure-IIS.ps1
# ================================

param(
    [string]$DomainName
)

Import-Module WebAdministration
. "$PSScriptRoot\00-Config.ps1"

Write-Log "Starting IIS configuration..."

# ================================
# INPUT DOMAIN
# ================================
$domainInput = $DomainName

if ([string]::IsNullOrWhiteSpace($domainInput)) {
    $domainInput = Read-Host "Enter domain name (example: company)"
}

if ([string]::IsNullOrWhiteSpace($domainInput)) {
    Exit-OnError "Domain cannot be empty"
}

$domain = "$domainInput.local"

Write-Log "Using domain: $domain"

# ================================
# DEFINE SITES / APP POOLS
# ================================
$sites = @(
    @{ Name = "office-encore.$domain"; Port = 80 },
    @{ Name = "plant-encore.$domain";  Port = 81 },
    @{ Name = "test-encore.$domain";   Port = 82 }
)

# ================================
# STOP DEFAULT APP POOL + SITE
# ================================
if (Test-Path "IIS:\AppPools\DefaultAppPool") {
    Stop-WebAppPool "DefaultAppPool"
    Write-Log "DefaultAppPool stopped"
}

if (Test-Path "IIS:\Sites\Default Web Site") {
    Stop-Website "Default Web Site"
    Write-Log "Default Web Site stopped"
}

# ================================
# CREATE APP POOLS
# ================================
foreach ($site in $sites) {

    $appPoolName = $site.Name

    if (!(Test-Path "IIS:\AppPools\$appPoolName")) {

        New-WebAppPool -Name $appPoolName
        Write-Log "Created AppPool: $appPoolName"

        # .NET Version
        Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name managedRuntimeVersion -Value "v4.0"

        # Identity
        Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name processModel.identityType -Value 3
        Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name processModel.userName -Value $Config.ServiceAccount
        Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name processModel.password -Value $Config.ServicePassword

        # Tuning (EnCore best practice)
        Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name processModel.idleTimeout -Value ([TimeSpan]::Zero)
        Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name processModel.shutdownTimeLimit -Value ([TimeSpan]::FromSeconds(300))
        Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name processModel.startupTimeLimit -Value ([TimeSpan]::FromSeconds(300))
        Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name recycling.periodicRestart.time -Value ([TimeSpan]::Zero)

        Write-Log "Configured AppPool: $appPoolName"
    }
    else {
        Write-Log "AppPool already exists: $appPoolName"
    }
}

# ================================
# CREATE SITE FOLDERS
# ================================
foreach ($site in $sites) {

    $path = "$($Config.InetPubPath)\$($site.Name)"

    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Log "Created folder: $path"
    }
}

# ================================
# CREATE IIS SITES
# ================================
foreach ($site in $sites) {

    $siteName = $site.Name
    $path = "$($Config.InetPubPath)\$siteName"
    $port = $site.Port

    if (!(Get-Website | Where-Object {$_.Name -eq $siteName})) {

        New-Website `
            -Name $siteName `
            -Port $port `
            -PhysicalPath $path `
            -ApplicationPool $siteName

        Write-Log "Created Site: $siteName on port $port"
    }
    else {
        Write-Log "Site already exists: $siteName"
    }
}

# ================================
# START SITES
# ================================
foreach ($site in $sites) {
    Start-Website $site.Name
    Write-Log "Started Site: $($site.Name)"
}

# ================================
# APPLY NTFS PERMISSIONS TO IIS SITES
# ================================
Write-Log "Applying NTFS permissions to IIS site folders..."

try {
    foreach ($site in $sites) {

        $path = "$($Config.InetPubPath)\$($site.Name)"

        if (!(Test-Path $path)) {
            Write-Log "Skipping (not found): $path" "ERROR"
            continue
        }

        Write-Log "Applying permissions to: $path"

        $acl = Get-Acl $path

        # Keep inheritance but ensure correct access
        $acl.SetAccessRuleProtection($true, $true)

        # Define rule (service account)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Config.ServiceAccount,
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )

        $acl.SetAccessRule($rule)

        # SYSTEM (always required)
        $ruleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM",
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )

        $acl.SetAccessRule($ruleSystem)

        # Administrators (language-safe using SID)
        $ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule(
            (Get-LocalAdministratorsName),
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )

        $acl.SetAccessRule($ruleAdmins)

        # Apply
        Set-Acl -Path $path -AclObject $acl

        Write-Log "Permissions applied to: $path"
    }

    Write-Log "All IIS site permissions configured successfully"
}
catch {
    Exit-OnError "Failed applying IIS folder permissions: $($_.Exception.Message)"
}

# ================================
# COPY REQUIRED FILES TO IIS SITES
# ================================
Write-Log "Copying required files to IIS site folders..."

try {
    $requiredFiles = @(
        "favicon.ico",
        "version.txt",
        "sql.config"
    )

    $preferredSourceFolders = @(
        (Join-Path $Config.BundlePath "IISFiles"),
        (Join-Path $Config.BundlePath "ConfigFiles"),
        $Config.BundlePath,
        $PSScriptRoot
    )

    $filesToCopy = @{}

    foreach ($fileName in $requiredFiles) {
        $sourceFile = $null

        foreach ($folder in $preferredSourceFolders) {
            $candidate = Join-Path $folder $fileName

            if (Test-Path -LiteralPath $candidate) {
                $sourceFile = Get-Item -LiteralPath $candidate
                break
            }
        }

        if (-not $sourceFile) {
            $sourceFile = Get-ChildItem -LiteralPath $Config.BundlePath -Recurse -File -Filter $fileName -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }

        if (-not $sourceFile) {
            Exit-OnError "Required IIS file not found in bundle: $fileName"
        }

        $filesToCopy[$fileName] = $sourceFile.FullName
        Write-Log "Found $fileName at: $($sourceFile.FullName)"
    }

    foreach ($site in $sites) {
        $sitePath = "$($Config.InetPubPath)\$($site.Name)"

        if (!(Test-Path -LiteralPath $sitePath)) {
            Exit-OnError "IIS site folder not found while copying required files: $sitePath"
        }

        foreach ($fileName in $requiredFiles) {
            $destination = Join-Path $sitePath $fileName
            Copy-Item -LiteralPath $filesToCopy[$fileName] -Destination $destination -Force
            Write-Log "Copied $fileName to: $destination"
        }
    }

    Write-Log "Required files copied to all IIS site folders"
}
catch {
    Exit-OnError "Failed copying required IIS files: $($_.Exception.Message)"
}

Write-Log "IIS configuration completed successfully"
exit 0
