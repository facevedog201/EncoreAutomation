# EnCore Server Setup Scripts

PowerShell automation scripts for deploying and configuring an **EnCore** server environment on Windows Server with IIS.

---

## Prerequisites

- Windows Server with PowerShell 5.1+
- Must be executed **as Administrator**
- Install bundle directory at `C:\InstallBundle` (or alongside the scripts in an `InstallBundle` subfolder)
- Environment variable `ENCORE_SERVICE_PASSWORD` set before running (falls back to a default if not set)

### Required Install Bundle structure

```
InstallBundle\
├── RequiredSoftware\
│   ├── SQLSysClrTypes.msi
│   └── ReportViewer.msi
├── Fonts\                     # .ttf / .otf font files
├── Scripts\
│   ├── tlssettings1.ps1
│   └── tlssettings2.ps1
├── EncoreUpdater\
│   ├── *UpdateManager*.msi
│   ├── *UpdateService*.msi
│   └── *DeployService*.msi
├── EnCoreShare\               # Base share content
├── IISFiles\                  # favicon.ico, version.txt, sql.config
├── Tools\WinSCP\              # Auto-downloaded if missing
├── Updates\                   # Created automatically
└── vs_community.exe
```

---

## Quick Start

Run the full automated setup with a single command:

```powershell
# Web Server role
.\Run-All-EnCore-Setup.ps1 -Role Web -DomainName "company"

# Database Server role
.\Run-All-EnCore-Setup.ps1 -Role Database
```

If `-Role` is omitted, the script will prompt interactively.

### Runner parameters

| Parameter | Type | Description |
|---|---|---|
| `-Role` | `Web` \| `Database` | Server role to deploy |
| `-DomainName` | string | Domain prefix (e.g. `company` → `company.local`) |
| `-DelaySeconds` | int | Pause between scripts (default: 5) |
| `-ContinueOnError` | switch | Keep running if a step fails |
| `-Skip` | string[] | Script names to skip |
| `-ForceRerunCompleted` | switch | Ignore saved checkpoints |
| `-ResetCheckpoints` | switch | Clear all checkpoints before running |

> **Checkpoints:** Each completed script saves a `.done` file under `C:\EnCore-Automation\Logs\Checkpoints\<Role>\`. Re-running the suite skips already-completed steps automatically.

---

## Script Reference

### `00-Config.ps1`
Global configuration and shared utilities. Dot-sourced by every other script.

- Defines `$Global:Config` (paths, service account, passwords)
- Creates the log directory at `C:\EnCore-Automation\Logs`
- Provides `Write-Log`, `Exit-OnError`, `Resolve-ServiceAccount`, and `Get-LocalAdministratorsName` functions
- Validates that the session is running as Administrator

**Key config values to set before running:**

```powershell
$Global:Config = @{
    ServiceAccount = "DOMAIN\svc_encore"   # Set this
    InstallRoot    = "C:\EnCore"
    InetPubPath    = "C:\inetpub"
    EncoreShare    = "C:\EncoreShare"
}
```

Set the service password via environment variable:
```powershell
$env:ENCORE_SERVICE_PASSWORD = "YourSecurePassword"
```

---

### `01-Install-IIS.ps1`
Installs IIS Windows features.

```powershell
.\01-Install-IIS.ps1 -Mode Full      # Full feature set (Web role)
.\01-Install-IIS.ps1 -Mode Default   # Minimal Web-Server only (Database role)
```

Full mode installs ~27 IIS features including ASP.NET 4.5, WebSockets, Windows Auth, compression, and management tools.

---

### `02-Install-Prerequisites.ps1`
Installs required MSI packages silently:
- `SQLSysClrTypes.msi`
- `ReportViewer.msi`

---

### `03-Install-Fonts.ps1`
Installs `.ttf` and `.otf` fonts from `InstallBundle\Fonts\` into Windows using the Shell COM object. Skips fonts that are already installed (checks by filename and normalized key).

---

### `04-Apply-TLS.ps1`
Applies TLS hardening by executing `tlssettings1.ps1` and `tlssettings2.ps1`. Falls back to local copies if the bundle path versions are not found.

---

### `tlssettings1.ps1`
Registry changes to **enable TLS 1.2** and **disable TLS 1.0 and TLS 1.1** via `SCHANNEL\Protocols`.

### `tlssettings2.ps1`
Registry changes to enforce strong cryptography for .NET Framework 4.x (`SchUseStrongCrypto`, `SystemDefaultTlsVersions`) for both 32-bit and 64-bit.

---

### `05-Install-VS.ps1`
Installs Visual Studio Community silently from `InstallBundle\vs_community.exe`.

---

### `05A-Install-EncoreDeployService.ps1`
Launches the **EnCore Deploy Service** MSI installer interactively (requires manual wizard input). After installation, validates the Windows service exists and is running under the configured service account.

---

### `05A-Install-EncoreUpdateService.ps1`
Launches the **EnCore Update Manager** and **EnCore Update Service** MSI installers interactively (requires manual wizard input for each). Validates both services are running under the correct account.

---

### `06-ServiceAccount-Rights.ps1`
Grants the service account the following local security policy rights via `secedit`:
- `SeServiceLogonRight` — Log on as a service
- `SeBatchLogonRight` — Log on as a batch job

---

### `07-Create-Folders.ps1`
Creates the EnCore directory structure and applies NTFS permissions.

- Prompts for environment folder names (default: `PROD`, `TEST`, `TRAIN`)
- Creates `C:\EnCore` and `C:\EncoreShare\<PROD|TEST|TRAIN>`
- Saves folder names to `Logs\EncoreShareFolders.txt` for use by later scripts
- Grants **FullControl** (with inheritance) to: service account, SYSTEM, and local Administrators

---

### `07-Create-Updates-Folder.ps1`
Creates `C:\EnCore\Updates` and applies NTFS permissions (service account as owner, FullControl for service account, SYSTEM, and Administrators).

---

### `08-Configure-IIS.ps1`
Configures IIS for EnCore with three sites.

```powershell
.\08-Configure-IIS.ps1 -DomainName "company"
# Creates: office-encore.company.local (port 80)
#          plant-encore.company.local  (port 81)
#          test-encore.company.local   (port 82)
```

For each site:
- Stops and disables the default IIS site/app pool
- Creates a dedicated App Pool (`.NET v4.0`, custom identity, no idle timeout, no periodic recycle)
- Creates the physical folder under `C:\inetpub\<site-name>`
- Applies NTFS permissions
- Copies `favicon.ico`, `version.txt`, and `sql.config` from the bundle

---

### `09-Setup-Tasks.ps1`
Creates a Windows Scheduled Task `RollEDILogs` that runs `RollEDILogs.cmd` daily at midnight under the service account.

---

### `10-Validate.ps1`
Post-installation validation:
- Confirms IIS (`Web-Server` feature) is installed
- Tests write access to `EncoreShare`
- Checks SQL Server port 1433 connectivity (warning only if unreachable)

---

### `11-Deploy-EncoreShare.ps1`
Copies base content from `InstallBundle\EnCoreShare\` to each environment subfolder (`PROD`, `TEST`, `TRAIN`) using `robocopy /E /COPYALL`. Reads folder names from `Logs\EncoreShareFolders.txt` if available.

---

### `12-Deploy-K2-From-FTP.ps1`
Downloads a K2 deployment package from an FTPS server and deploys it to all IIS sites.

```powershell
.\12-Deploy-K2-From-FTP.ps1 -FtpServer "updates.example.com" -FtpUser "user" -FtpPassword "pass"
```

Workflow:
1. Auto-downloads WinSCP NuGet package if not present in `InstallBundle\Tools\WinSCP\`
2. Scans the FTPS certificate fingerprint and prompts for acceptance
3. Lists available ZIP packages from the remote `/K2/General` folder
4. Prompts the user to select a package, downloads it, and extracts it
5. Deploys extracted content + `UserData` folder to every IIS site

---

## Execution Order (Web Role)

```
01 Install IIS (Full)
02 Install Prerequisites
03 Install Fonts
06 Service Account Rights
05 Install Visual Studio
04 Apply TLS
05A Install EnCore Update Service
07 Create Folders
08 Configure IIS
09 Setup Tasks
11 Deploy EncoreShare
10 Validate
```

## Execution Order (Database Role)

```
01 Install IIS (Default)
02 Install Prerequisites
06 Service Account Rights
04 Apply TLS
05A Install EnCore Update Service
07 Create Updates Folder
```

---

## Logging

All scripts log to `C:\EnCore-Automation\Logs\<ScriptName>.log` with timestamps and severity levels (`INFO`, `WARNING`, `ERROR`). The orchestrator log is at `Run-All-EnCore-Setup.log` in the same directory.

---

## Notes

- `05A-Install-EncoreDeployService.ps1` and `05A-Install-EncoreUpdateService.ps1` share the same prefix — they are alternative service installers for different EnCore configurations. Only one is typically run per deployment.
- The `12-Deploy-K2-From-FTP.ps1` script is run **after** the base setup and can be re-run independently for future K2 updates.
- All NTFS permission rules resolve the local Administrators group by SID (`S-1-5-32-544`) to be locale-safe on non-English Windows installations.
