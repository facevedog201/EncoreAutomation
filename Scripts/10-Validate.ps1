. "$PSScriptRoot\00-Config.ps1"

Write-Log "Running validation..."

# IIS
if (!(Get-WindowsFeature Web-Server).Installed) {
    Exit-OnError "IIS not installed"
}

# SMB
$testFile = "$($Config.EncoreShare)\test.txt"

try {
    New-Item $testFile -ItemType File -Force
    Remove-Item $testFile
    Write-Log "SMB OK"
} catch {
    Exit-OnError "SMB failed"
}

# SQL Port
if (!(Test-NetConnection -ComputerName localhost -Port 1433).TcpTestSucceeded) {
    Write-Log "WARNING: SQL port not reachable"
}

Write-Log "VALIDATION PASSED"
exit 0