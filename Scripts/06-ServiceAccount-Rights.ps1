. "$PSScriptRoot\00-Config.ps1"

Write-Log "Configuring service account rights..."

$cfgPath = Join-Path $env:TEMP "encore-secpol.cfg"
$dbPath = Join-Path $env:TEMP "encore-secedit.sdb"

secedit /export /cfg $cfgPath | Out-Null

if ($LASTEXITCODE -ne 0) {
    Exit-OnError "Failed exporting local security policy"
}

function Add-AccountToRight {
    param(
        [string[]]$Content,
        [string]$RightName,
        [string]$Account
    )

    $lineIndex = -1
    for ($i = 0; $i -lt $Content.Count; $i++) {
        if ($Content[$i] -match "^$RightName\s*=") {
            $lineIndex = $i
            break
        }
    }

    if ($lineIndex -lt 0) {
        return @($Content + "$RightName = $Account")
    }

    $parts = $Content[$lineIndex] -replace "^$RightName\s*=\s*", ""
    $accounts = @($parts -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    if ($accounts -notcontains $Account) {
        $accounts += $Account
    }

    $Content[$lineIndex] = "$RightName = $($accounts -join ',')"
    return $Content
}

$content = Get-Content $cfgPath
$content = Add-AccountToRight -Content $content -RightName "SeServiceLogonRight" -Account $Config.ServiceAccount
$content = Add-AccountToRight -Content $content -RightName "SeBatchLogonRight" -Account $Config.ServiceAccount
$content | Set-Content $cfgPath

secedit /configure /db $dbPath /cfg $cfgPath /areas USER_RIGHTS | Out-Null

if ($LASTEXITCODE -ne 0) {
    Exit-OnError "Failed applying local security policy"
}

Write-Log "Service account rights applied"
exit 0
