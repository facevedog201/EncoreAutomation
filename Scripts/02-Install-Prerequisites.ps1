. "$PSScriptRoot\00-Config.ps1"

Write-Log "Installing prerequisites..."

$apps = @(
    "$($Config.BundlePath)\RequiredSoftware\SQLSysClrTypes.msi",
    "$($Config.BundlePath)\RequiredSoftware\ReportViewer.msi"
)

foreach ($app in $apps) {
    if (!(Test-Path $app)) {
        Exit-OnError "Missing: $app"
    }

    Start-Process msiexec.exe -ArgumentList "/i `"$app`" /qn /norestart" -Wait
    Write-Log "Installed: $app"
}

exit 0