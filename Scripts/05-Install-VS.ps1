. "$PSScriptRoot\00-Config.ps1"

Write-Log "Installing Visual Studio..."

$vs = "$($Config.BundlePath)\vs_community.exe"

if (!(Test-Path $vs)) {
    Exit-OnError "VS installer not found"
}

Start-Process $vs -ArgumentList "--quiet --wait --norestart" -Wait

Write-Log "VS installed"
exit 0