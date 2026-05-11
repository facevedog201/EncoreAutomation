# ================================
# 07-Create-Updates-Folder.ps1
# ================================
. "$PSScriptRoot\00-Config.ps1"

Write-Log "Creating Updates folder and applying permissions..."

$updatesPath = Join-Path $Config.InstallRoot "Updates"
$serviceAccount = Resolve-ServiceAccount

try {
    $account = New-Object System.Security.Principal.NTAccount($serviceAccount)
    $sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
    Write-Log "Service account validated: $serviceAccount"
}
catch {
    Exit-OnError "Service account not found or not resolvable: $serviceAccount"
}

try {
    if (-not (Test-Path -LiteralPath $Config.InstallRoot)) {
        New-Item -ItemType Directory -Path $Config.InstallRoot -Force | Out-Null
        Write-Log "Created folder: $($Config.InstallRoot)"
    }

    if (-not (Test-Path -LiteralPath $updatesPath)) {
        New-Item -ItemType Directory -Path $updatesPath -Force | Out-Null
        Write-Log "Created folder: $updatesPath"
    }
    else {
        Write-Log "Folder already exists: $updatesPath"
    }

    $acl = Get-Acl -Path $updatesPath
    $acl.SetAccessRuleProtection($true, $true)
    $acl.SetOwner($account)

    $rules = @(
        @{ Identity = $serviceAccount; Rights = "FullControl" },
        @{ Identity = "SYSTEM"; Rights = "FullControl" },
        @{ Identity = (Get-LocalAdministratorsName); Rights = "FullControl" }
    )

    foreach ($r in $rules) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $r.Identity,
            $r.Rights,
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )

        $acl.SetAccessRule($rule)
        Write-Log "Applied permission: $($r.Identity)"
    }

    Set-Acl -Path $updatesPath -AclObject $acl
    Write-Log "Owner set to: $serviceAccount"
    Write-Log "Updates folder permissions applied successfully"
}
catch {
    Exit-OnError "Failed configuring Updates folder: $($_.Exception.Message)"
}

exit 0
