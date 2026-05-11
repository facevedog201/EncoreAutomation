# ================================
# 12-Deploy-K2-From-FTP.ps1
# ================================
param(
    [string]$FtpServer = "updates.amtechinext.com",
    [string]$FtpUser = "encoreuser",
    [string]$FtpPassword = 'Web1234$',
    [string]$RemoteFolder = "/K2/General",
    [string]$WinSCPVersion = "6.5.6"
)

Import-Module WebAdministration
. "$PSScriptRoot\00-Config.ps1"

$ErrorActionPreference = "Stop"

Write-Log "Starting K2 deployment from FTP..."

function Ensure-WinSCPTools {
    $toolsRoot = Join-Path $Config.BundlePath "Tools\WinSCP"
    $dllPath = Join-Path $toolsRoot "WinSCPnet.dll"
    $exePath = Join-Path $toolsRoot "WinSCP.exe"

    if ((Test-Path -LiteralPath $dllPath) -and (Test-Path -LiteralPath $exePath)) {
        return @{
            DllPath = $dllPath
            ExePath = $exePath
        }
    }

    Write-Log "Downloading WinSCP automation package..."

    if (-not (Test-Path -LiteralPath $toolsRoot)) {
        New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
    }

    $packagePath = Join-Path $toolsRoot "WinSCP.nupkg"
    $zipPath = Join-Path $toolsRoot "WinSCP.zip"
    $extractPath = Join-Path $toolsRoot "package"
    $packageUrl = "https://www.nuget.org/api/v2/package/WinSCP/$WinSCPVersion"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    try {
        Invoke-WebRequest -Uri $packageUrl -OutFile $packagePath
    }
    catch {
        Write-Log "Invoke-WebRequest failed for WinSCP package, trying curl.exe fallback..." "WARNING"

        $curlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source

        if ([string]::IsNullOrWhiteSpace($curlPath)) {
            throw
        }

        & $curlPath --location --fail --output $packagePath $packageUrl

        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $packagePath)) {
            Exit-OnError "Failed downloading WinSCP automation package."
        }
    }

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Copy-Item -LiteralPath $packagePath -Destination $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $downloadedDll = Join-Path $extractPath "lib\net40\WinSCPnet.dll"
    $downloadedExe = Join-Path $extractPath "tools\WinSCP.exe"

    if (!(Test-Path -LiteralPath $downloadedDll) -or !(Test-Path -LiteralPath $downloadedExe)) {
        Exit-OnError "Failed to prepare WinSCP automation package."
    }

    Copy-Item -LiteralPath $downloadedDll -Destination $dllPath -Force
    Copy-Item -LiteralPath $downloadedExe -Destination $exePath -Force

    Write-Log "WinSCP tools prepared in: $toolsRoot"

    return @{
        DllPath = $dllPath
        ExePath = $exePath
    }
}

function New-WinSCPSessionOptions {
    param(
        [string]$CertificateFingerprint = ""
    )

    $sessionOptions = New-Object WinSCP.SessionOptions
    $sessionOptions.Protocol = [WinSCP.Protocol]::Ftp
    $sessionOptions.HostName = $FtpServer
    $sessionOptions.UserName = $FtpUser
    $sessionOptions.Password = $FtpPassword
    $sessionOptions.FtpSecure = [WinSCP.FtpSecure]::Explicit
    $sessionOptions.FtpMode = [WinSCP.FtpMode]::Passive
    $sessionOptions.TimeoutInMilliseconds = 30000

    if ([string]::IsNullOrWhiteSpace($CertificateFingerprint)) {
        $sessionOptions.GiveUpSecurityAndAcceptAnyTlsHostCertificate = $true
    }
    else {
        $sessionOptions.TlsHostCertificateFingerprint = $CertificateFingerprint
    }

    return $sessionOptions
}

function Select-ZipEntry {
    param([array]$ZipEntries)

    if (-not $ZipEntries -or $ZipEntries.Count -eq 0) {
        Exit-OnError "No ZIP files found in FTP folder."
    }

    Write-Host ""
    Write-Host "Available ZIP packages:" -ForegroundColor Yellow

    for ($i = 0; $i -lt $ZipEntries.Count; $i++) {
        Write-Host "$($i + 1) - $($ZipEntries[$i].RemotePath)"
    }

    [int]$selectedIndex = 0

    do {
        $selection = Read-Host "Choose package number"
        $isValidNumber = [int]::TryParse($selection, [ref]$selectedIndex)
    } while (-not $isValidNumber -or $selectedIndex -lt 1 -or $selectedIndex -gt $ZipEntries.Count)

    return $ZipEntries[$selectedIndex - 1]
}

function Get-DeploySitePaths {
    $sites = Get-Website | Where-Object {
        $_.Name -ne "Default Web Site" -and
        -not [string]::IsNullOrWhiteSpace($_.PhysicalPath) -and
        (Test-Path -LiteralPath $_.PhysicalPath)
    }

    if (-not $sites) {
        Exit-OnError "No IIS sites found for deployment."
    }

    return $sites | Select-Object Name, PhysicalPath
}

$winScpTools = Ensure-WinSCPTools
Add-Type -Path $winScpTools.DllPath

$updatesRoot = Join-Path $Config.BundlePath "Updates"
$localK2Folder = Join-Path $updatesRoot "K2\General"

if (-not (Test-Path -LiteralPath $localK2Folder)) {
    New-Item -ItemType Directory -Path $localK2Folder -Force | Out-Null
}

Write-Log "Connecting to FTP: $FtpServer"
Write-Log "Remote folder: $RemoteFolder"
Write-Log "Local folder: $localK2Folder"

$fingerprintSession = New-Object WinSCP.Session
$fingerprintSession.ExecutablePath = $winScpTools.ExePath
$scanOptions = New-WinSCPSessionOptions
$fingerprint = $fingerprintSession.ScanFingerprint($scanOptions, "SHA-256")
$fingerprintSession.Dispose()

Write-Host ""
Write-Host "FTP server certificate fingerprint (SHA-256): $fingerprint" -ForegroundColor Yellow
$acceptCertificate = Read-Host "Accept this FTP certificate? (Y/N)"

if ($acceptCertificate -notmatch '^(Y|YES)$') {
    Exit-OnError "TLS certificate was not accepted."
}

Write-Log "User accepted TLS certificate fingerprint: $fingerprint"

$sessionOptions = New-WinSCPSessionOptions -CertificateFingerprint $fingerprint
$session = New-Object WinSCP.Session
$session.ExecutablePath = $winScpTools.ExePath

try {
    $session.Open($sessionOptions)
    Write-Log "Connected to FTPS successfully."

    $generalDirectory = $session.ListDirectory($RemoteFolder)
    $zipEntries = @()

    foreach ($item in $generalDirectory.Files) {
        if ($item.Name -in @(".", "..")) {
            continue
        }

        if (-not $item.IsDirectory) {
            if ($item.Name -like "*.zip") {
                $zipEntries += [PSCustomObject]@{
                    RemotePath = $item.FullName
                    LocalFolder = $localK2Folder
                    FileName = $item.Name
                }
            }

            continue
        }

        $remoteSubFolder = $item.FullName
        $localSubFolder = Join-Path $localK2Folder $item.Name

        if (-not (Test-Path -LiteralPath $localSubFolder)) {
            New-Item -ItemType Directory -Path $localSubFolder -Force | Out-Null
        }

        $subDirectory = $session.ListDirectory($remoteSubFolder)

        foreach ($subItem in $subDirectory.Files) {
            if ($subItem.Name -in @(".", "..")) {
                continue
            }

            if ($subItem.IsDirectory) {
                continue
            }

            if ($subItem.Name -like "*.zip") {
                $zipEntries += [PSCustomObject]@{
                    RemotePath = $subItem.FullName
                    LocalFolder = $localSubFolder
                    FileName = $subItem.Name
                }
            }
        }
    }

    $selectedZip = Select-ZipEntry -ZipEntries ($zipEntries | Sort-Object RemotePath)
    $localZipPath = Join-Path $selectedZip.LocalFolder $selectedZip.FileName

    Write-Log "Downloading selected ZIP: $($selectedZip.RemotePath)"
    $transferResult = $session.GetFiles($selectedZip.RemotePath, $localZipPath, $false)
    $transferResult.Check()

    Write-Log "Downloaded ZIP to: $localZipPath"
}
finally {
    $session.Dispose()
}

$extractRoot = Join-Path $updatesRoot "Extracted"
$extractFolder = Join-Path $extractRoot ([System.IO.Path]::GetFileNameWithoutExtension($selectedZip.FileName))

if (Test-Path -LiteralPath $extractFolder) {
    Remove-Item -LiteralPath $extractFolder -Recurse -Force
}

New-Item -ItemType Directory -Path $extractFolder -Force | Out-Null
Write-Log "Extracting ZIP to: $extractFolder"
Expand-Archive -LiteralPath $localZipPath -DestinationPath $extractFolder -Force

$userDataCandidates = @(
    (Join-Path $Config.BundlePath "Resources\UserData"),
    (Join-Path $Config.BundlePath "UserData")
)

$userDataPath = $userDataCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $userDataPath) {
    Exit-OnError "UserData folder not found in InstallBundle."
}

$sitePaths = Get-DeploySitePaths

foreach ($site in $sitePaths) {
    $sitePath = $site.PhysicalPath
    Write-Log "Deploying package to IIS site: $($site.Name) -> $sitePath"

    Get-ChildItem -LiteralPath $extractFolder -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $sitePath -Recurse -Force
    }

    Write-Log "Copied extracted package to: $sitePath"

    $siteUserDataPath = Join-Path $sitePath "UserData"

    if (Test-Path -LiteralPath $siteUserDataPath) {
        Remove-Item -LiteralPath $siteUserDataPath -Recurse -Force
    }

    Copy-Item -LiteralPath $userDataPath -Destination $sitePath -Recurse -Force
    Write-Log "Copied UserData to: $siteUserDataPath"
}

Write-Log "K2 deployment completed successfully"
exit 0
