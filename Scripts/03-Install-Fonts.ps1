# ================================
# 03-Install-Fonts.ps1
# ================================

. "$PSScriptRoot\00-Config.ps1"

Write-Log "Starting font installation..."

# ================================
# VALIDATE SOURCE
# ================================
$fontSource = "$($Config.BundlePath)\Fonts"

if (!(Test-Path $fontSource)) {
    Exit-OnError "Fonts folder not found: $fontSource"
}

Write-Log "Font source: $fontSource"

# ================================
# LOAD WINDOWS FONTS FOLDER (COM)
# ================================
try {
    $shell = New-Object -ComObject Shell.Application
    $fontsFolder = $shell.Namespace(0x14)
}
catch {
    Exit-OnError "Failed to initialize Shell COM object"
}

# ================================
# GET EXISTING FONTS
# ================================
function Get-NormalizedFontKey {
    param([string]$Name)

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    return ([regex]::Replace($baseName.ToLowerInvariant(), "[^a-z0-9]", ""))
}

function Get-InstalledFontFileNames {
    $fontFiles = @{}

    Get-ChildItem "C:\Windows\Fonts" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $fontFiles[$_.Name.ToLowerInvariant()] = $true
        $fontFiles[(Get-NormalizedFontKey -Name $_.Name)] = $true
    }

    $fontRegistry = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue

    if ($fontRegistry) {
        foreach ($property in $fontRegistry.PSObject.Properties) {
            if ($property.Name -like "PS*") {
                continue
            }

            $value = [string]$property.Value

            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $fileName = [System.IO.Path]::GetFileName($value)
                $fontFiles[$fileName.ToLowerInvariant()] = $true
                $fontFiles[(Get-NormalizedFontKey -Name $fileName)] = $true
            }
        }
    }

    return $fontFiles
}

$existingFonts = Get-InstalledFontFileNames

# ================================
# DEDUPE SOURCE FILES
# ================================
$fontFiles = Get-ChildItem -Path $fontSource -Recurse -File -Include *.ttf, *.otf |
    Sort-Object Name -Unique

# ================================
# INSTALL FONTS
# ================================
foreach ($fontFile in $fontFiles) {

    $fontName = $fontFile.Name
    $normalizedFontKey = Get-NormalizedFontKey -Name $fontName

    # ================================
    # SKIP IF FONT ALREADY EXISTS
    # ================================
    if ($existingFonts.ContainsKey($fontName.ToLowerInvariant()) -or $existingFonts.ContainsKey($normalizedFontKey)) {

        Write-Log "Skipping existing font: $($fontFile.Name)"
        continue
    }

    try {

        Write-Log "Installing font: $($fontFile.Name)"

        # Windows font installation method
        $fontsFolder.CopyHere($fontFile.FullName, 0x10)

        Start-Sleep -Milliseconds 500
        $existingFonts[$fontName.ToLowerInvariant()] = $true
        $existingFonts[$normalizedFontKey] = $true

        Write-Log "Installed successfully: $($fontFile.Name)"
    }
    catch {

        Write-Log "ERROR installing font: $($fontFile.Name)" "ERROR"
        Write-Log $_.Exception.Message "ERROR"
    }
}

Write-Log "Font installation process completed"

exit 0
