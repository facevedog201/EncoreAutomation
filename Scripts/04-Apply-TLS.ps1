# ================================
# 04-Apply-TLS.ps1
# ================================

. "$PSScriptRoot\00-Config.ps1"

Write-Log "Applying TLS settings..."

# ==========================================
# TLS SCRIPTS
# ==========================================
$scripts = @(
    "$($Config.BundlePath)\Scripts\tlssettings1.ps1",
    "$($Config.BundlePath)\Scripts\tlssettings2.ps1"
)

foreach ($script in $scripts) {
    $scriptName = Split-Path $script -Leaf
    $localScript = Join-Path $PSScriptRoot $scriptName

    if (!(Test-Path $script) -and (Test-Path $localScript)) {
        Write-Log "Using local TLS script fallback: $localScript"
        $script = $localScript
    }

    # ==========================================
    # VALIDATE SCRIPT EXISTS
    # ==========================================
    if (!(Test-Path $script)) {

        Exit-OnError "Missing TLS script: $script"
    }

    try {

        Write-Log "Preparing TLS script: $script"

        # Unblock downloaded files
        Unblock-File -Path $script -ErrorAction SilentlyContinue

        # ==========================================
        # EXECUTE USING POWERSHELL.EXE
        # ==========================================
        Write-Log "Executing TLS script: $script"

        $process = Start-Process powershell.exe `
            -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$script`"" `
            -Wait `
            -PassThru `
            -WindowStyle Hidden

        # ==========================================
        # VALIDATE EXIT CODE
        # ==========================================
        if ($process.ExitCode -eq 0) {

            Write-Log "TLS script completed successfully: $script"
        }
        else {

            Exit-OnError "TLS script failed with exit code $($process.ExitCode): $script"
        }
    }
    catch {

        Exit-OnError "Error executing TLS script: $script - $($_.Exception.Message)"
    }

    # Small pause between scripts
    Start-Sleep -Seconds 5
}

Write-Log "TLS configuration completed successfully."

exit 0
