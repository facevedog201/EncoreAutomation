$RegPath1 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319"
New-ItemProperty -path $RegPath1 `
-name SystemDefaultTlsVersions -value 1 -PropertyType DWORD
New-ItemProperty -path $RegPath1 `
-name SchUseStrongCrypto -value 1 -PropertyType DWORD
 
$RegPath2 = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319"
New-ItemProperty -path $RegPath2 `
-name SystemDefaultTlsVersions -value 1 -PropertyType DWORD
New-ItemProperty -path $RegPath2 `
-name SchUseStrongCrypto -value 1 -PropertyType DWORD
