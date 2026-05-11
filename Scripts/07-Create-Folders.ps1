# ================================
# NTFS PERMISSIONS (ROBUST VERSION)
# ================================
. "$PSScriptRoot\00-Config.ps1"
Write-Log "Applying NTFS permissions..."

$path = $Config.EncoreShare

function Read-FolderName {
    param(
        [string]$Prompt,
        [string]$DefaultValue
    )

    $value = Read-Host "$Prompt [$DefaultValue]"

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value.Trim()
}

try {
    $serviceAccount = Resolve-ServiceAccount

    $shareFolderNames = @(
        (Read-FolderName -Prompt "Enter Production folder name" -DefaultValue "PROD"),
        (Read-FolderName -Prompt "Enter Test folder name" -DefaultValue "TEST"),
        (Read-FolderName -Prompt "Enter Training folder name" -DefaultValue "TRAIN")
    )

    $shareFolderConfigPath = Join-Path $Config.LogPath "EncoreShareFolders.txt"
    $shareFolderNames | Set-Content -LiteralPath $shareFolderConfigPath -Encoding utf8
    Write-Log "Saved EnCoreShare folder names to: $shareFolderConfigPath"

    $folders = @(
        $Config.InstallRoot,
        $Config.EncoreShare
    )

    $folders += $shareFolderNames | ForEach-Object {
        Join-Path $Config.EncoreShare $_
    }

    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Write-Log "Created folder: $folder"
        }
        else {
            Write-Log "Folder already exists: $folder"
        }
    }

    # Validate service account exists
    try {
        $account = New-Object System.Security.Principal.NTAccount($serviceAccount)
        $sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
        Write-Log "Service account validated: $serviceAccount"
    }
    catch {
        Exit-OnError "Service account not found or not resolvable: $serviceAccount"
    }

    $acl = Get-Acl $path

    # Disable inheritance (keep existing temporarily)
    $acl.SetAccessRuleProtection($true, $true)

    # Define rules safely
    $rules = @(
        @{ Identity = $serviceAccount; Rights = "FullControl" },
        @{ Identity = "SYSTEM"; Rights = "FullControl" },
        @{ Identity = (Get-LocalAdministratorsName); Rights = "FullControl" }
    )

    foreach ($r in $rules) {

        try {
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
        catch {
            Write-Log "Failed applying permission: $($r.Identity)" "ERROR"
            throw
        }
    }

    Set-Acl -Path $path -AclObject $acl

    Write-Log "NTFS permissions applied successfully"
}
catch {
    Exit-OnError "Failed configuring NTFS permissions: $($_.Exception.Message)"
}

exit 0
