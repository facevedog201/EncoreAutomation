# ================================
# Deploy EnCoreShare (1 → Many)
# ================================

. "$PSScriptRoot\00-Config.ps1"

Write-Log "Starting EnCoreShare base content deployment..."

$source = "$($Config.BundlePath)\EnCoreShare"

$shareFolderConfigPath = Join-Path $Config.LogPath "EncoreShareFolders.txt"

if (Test-Path -LiteralPath $shareFolderConfigPath) {
    $shareFolderNames = Get-Content -LiteralPath $shareFolderConfigPath | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
    Write-Log "Using EnCoreShare folder names from: $shareFolderConfigPath"
}
else {
    $shareFolderNames = @("PROD", "TEST", "TRAIN")
    Write-Log "Using default EnCoreShare folder names"
}

$targets = $shareFolderNames | ForEach-Object {
    Join-Path $Config.EncoreShare $_
}

# ================================
# VALIDATE SOURCE
# ================================
if (!(Test-Path $source)) {
    Exit-OnError "Source path not found: $source"
}

Write-Log "Source: $source"

# ================================
# COPY TO EACH TARGET
# ================================
foreach ($target in $targets) {

    if (!(Test-Path $target)) {
        Write-Log "Target not found, skipping: $target" "ERROR"
        continue
    }

    Write-Log "Copying content to: $target"

    try {
        robocopy $source $target /E /COPYALL /R:2 /W:2 /NFL /NDL /NP | Out-Null

        if ($LASTEXITCODE -le 3) {
            Write-Log "Copy successful: $target"
        }
        else {
            Write-Log "Robocopy warning (ExitCode: $LASTEXITCODE) for $target" "WARNING"
        }
    }
    catch {
        Write-Log "Copy failed for: $target" "ERROR"
    }
}

Write-Log "Deployment completed successfully"
exit 0
