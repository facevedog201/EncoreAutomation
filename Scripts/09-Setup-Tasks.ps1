. "$PSScriptRoot\00-Config.ps1"

Write-Log "Creating scheduled tasks..."

$securePassword = ConvertTo-SecureString $Config.ServicePassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($Config.ServiceAccount, $securePassword)

$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $($Config.ScriptsPath)\RollEDILogs.cmd"
$trigger = New-ScheduledTaskTrigger -Daily -At 12am

try {
    Register-ScheduledTask `
        -TaskName "RollEDILogs" `
        -Action $action `
        -Trigger $trigger `
        -User $cred.UserName `
        -Password $Config.ServicePassword `
        -RunLevel Highest `
        -Force

    Write-Log "Scheduled task created successfully"
}
catch {
    Exit-OnError "Failed creating scheduled task: $($_.Exception.Message)"
}