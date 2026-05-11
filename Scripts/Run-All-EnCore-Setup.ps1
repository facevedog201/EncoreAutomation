param(
    [ValidateSet("Web", "Database")]
    [string]$Role = "",

    [string]$DomainName = "",

    [int]$DelaySeconds = 5,

    [switch]$ContinueOnError,

    [string[]]$Skip = @(),

    [switch]$ForceRerunCompleted,

    [switch]$ResetCheckpoints
)

$ErrorActionPreference = "Stop"

$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be executed as Administrator." -ForegroundColor Red
    exit 1
}

Set-ExecutionPolicy Bypass -Scope Process -Force

$BasePath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$BasePath\00-Config.ps1"

$LogFile = Join-Path $Config.LogPath "Run-All-EnCore-Setup.log"
$CheckpointRoot = Join-Path $Config.LogPath "Checkpoints"

function Write-RunnerLog {
    param([string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"

    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

function Get-SafeCheckpointName {
    param([string]$ScriptName)

    return ($ScriptName -replace '[^a-zA-Z0-9._-]', '_')
}

function Get-CheckpointDirectory {
    param([string]$SelectedRole)

    $path = Join-Path $CheckpointRoot $SelectedRole

    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    return $path
}

function Get-CheckpointPath {
    param(
        [string]$SelectedRole,
        [string]$ScriptName
    )

    $checkpointDir = Get-CheckpointDirectory -SelectedRole $SelectedRole
    $safeName = Get-SafeCheckpointName -ScriptName $ScriptName
    return (Join-Path $checkpointDir "$safeName.done")
}

function Set-Checkpoint {
    param(
        [string]$SelectedRole,
        [string]$ScriptName
    )

    $checkpointPath = Get-CheckpointPath -SelectedRole $SelectedRole -ScriptName $ScriptName
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Set-Content -LiteralPath $checkpointPath -Value "Completed: $timestamp" -Encoding utf8
}

function Test-Checkpoint {
    param(
        [string]$SelectedRole,
        [string]$ScriptName
    )

    $checkpointPath = Get-CheckpointPath -SelectedRole $SelectedRole -ScriptName $ScriptName
    return (Test-Path -LiteralPath $checkpointPath)
}

function Reset-RoleCheckpoints {
    param([string]$SelectedRole)

    $checkpointDir = Join-Path $CheckpointRoot $SelectedRole

    if (Test-Path -LiteralPath $checkpointDir) {
        Remove-Item -LiteralPath $checkpointDir -Recurse -Force
    }
}

$ScriptSets = @{
    Web = @(
        "01-Install-IIS.ps1",
        "02-Install-Prerequisites.ps1",
        "03-Install-Fonts.ps1",
        "06-ServiceAccount-Rights.ps1",
        "05-Install-VS.ps1",
        "04-Apply-TLS.ps1",
        "05A-Install-EncoreUpdateService.ps1",
        "07-Create-Folders.ps1",
        "08-Configure-IIS.ps1",
        "09-Setup-Tasks.ps1",
        "11-Deploy-EncoreShare.ps1",
        "10-Validate.ps1"
    )
    Database = @(
        "01-Install-IIS.ps1",
        "02-Install-Prerequisites.ps1",
        "06-ServiceAccount-Rights.ps1",
        "04-Apply-TLS.ps1",
        "05A-Install-EncoreUpdateService.ps1",
        "07-Create-Updates-Folder.ps1"
    )
}

$IISModeByRole = @{
    Web = "Full"
    Database = "Default"
}

if ([string]::IsNullOrWhiteSpace($Role)) {
    Write-Host ""
    Write-Host "Select server role:" -ForegroundColor Yellow
    Write-Host "1 - Web Server"
    Write-Host "2 - Database Server"

    $choice = Read-Host "Enter option (1 or 2)"

    switch ($choice) {
        "1" { $Role = "Web" }
        "2" { $Role = "Database" }
        default { exit 1 }
    }
}

$Scripts = $ScriptSets[$Role]

if ($ResetCheckpoints) {
    Reset-RoleCheckpoints -SelectedRole $Role
    Write-RunnerLog "Reset checkpoints for role: $Role"
}

Write-RunnerLog "========================================"
Write-RunnerLog "Starting EnCore Automated Deployment. Role: $Role"
Write-RunnerLog "BundlePath: $($Config.BundlePath)"
Write-RunnerLog "LogPath: $($Config.LogPath)"
Write-RunnerLog "CheckpointPath: $(Get-CheckpointDirectory -SelectedRole $Role)"
Write-RunnerLog "========================================"

foreach ($Script in $Scripts) {
    if ($Skip -contains $Script) {
        Write-RunnerLog "Skipping script by request: $Script"
        continue
    }

    if ((-not $ForceRerunCompleted) -and (Test-Checkpoint -SelectedRole $Role -ScriptName $Script)) {
        Write-RunnerLog "Skipping completed script from checkpoint: $Script"
        continue
    }

    $ScriptPath = Join-Path $BasePath $Script

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        Write-RunnerLog "Script not found: $ScriptPath"

        if (-not $ContinueOnError) {
            exit 1
        }

        continue
    }

    Write-RunnerLog "Starting script: $Script"

    try {
        $global:LASTEXITCODE = $null

        if ($Script -eq "01-Install-IIS.ps1") {
            & $ScriptPath -Mode $IISModeByRole[$Role]
        }
        elseif ($Script -eq "08-Configure-IIS.ps1" -and -not [string]::IsNullOrWhiteSpace($DomainName)) {
            & $ScriptPath -DomainName $DomainName
        }
        else {
            & $ScriptPath
        }

        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            throw "Script returned exit code $LASTEXITCODE"
        }

        Write-RunnerLog "Completed successfully: $Script"
        Set-Checkpoint -SelectedRole $Role -ScriptName $Script
    }
    catch {
        Write-RunnerLog "ERROR executing $Script"
        Write-RunnerLog $_.Exception.Message

        if (-not $ContinueOnError) {
            Write-RunnerLog "Stopping deployment because ContinueOnError was not specified."
            exit 1
        }
    }

    if ($DelaySeconds -gt 0) {
        Write-RunnerLog "Waiting $DelaySeconds seconds before next script..."
        Start-Sleep -Seconds $DelaySeconds
    }
}

Write-RunnerLog "========================================"
Write-RunnerLog "EnCore Deployment Completed"
Write-RunnerLog "========================================"

Write-Host ""
Write-Host "Deployment process finished." -ForegroundColor Green
