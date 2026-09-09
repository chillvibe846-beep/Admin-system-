#requires -RunAsAdministrator
# ============================================================
# MASTER PC - IT ASSET MANAGEMENT SETUP
# Windows 10/11 Pro
# Expected computer name: MASTER
# ============================================================

$ErrorActionPreference = "Stop"

# -----------------------------
# Configuration
# -----------------------------
$ExpectedHostName = "MASTER"
$ShareName        = "IT-Asset-Management"
$RootPath         = "C:\IT-Asset-Management"
$ITUser           = "ITAdmin"

# -----------------------------
# Helper
# -----------------------------
function Write-Step($Text) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

# -----------------------------
# 1. Verify Windows + hostname
# -----------------------------
Write-Step "1. Checking Admin PC"

$os = Get-CimInstance Win32_OperatingSystem
$computerName = $env:COMPUTERNAME

Write-Host "Computer name : $computerName"
Write-Host "Windows       : $($os.Caption)"

if ($computerName -ne $ExpectedHostName) {
    Write-Host ""
    Write-Host "STOP: This PC is not named MASTER." -ForegroundColor Red
    Write-Host "Current name: $computerName"
    Write-Host "Expected    : $ExpectedHostName"
    Write-Host ""
    Write-Host "Rename this PC to MASTER, restart Windows, then run this script again."
    exit 1
}

if ($os.Caption -notmatch "Windows 10|Windows 11") {
    Write-Host ""
    Write-Host "STOP: This script is intended for Windows 10/11." -ForegroundColor Red
    exit 1
}

# -----------------------------
# 2. Create folder structure
# -----------------------------
Write-Step "2. Creating central folders"

$folders = @(
    $RootPath,
    "$RootPath\Laptop Audit Reports",
    "$RootPath\Purchase Invoices",
    "$RootPath\Warranty",
    "$RootPath\Service Records",
    "$RootPath\User Handover",
    "$RootPath\Backup",
    "$RootPath\Deployment"
)

foreach ($folder in $folders) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Write-Host "Created/verified: $folder"
}

# -----------------------------
# 3. Create or verify ITAdmin
# -----------------------------
Write-Step "3. Checking ITAdmin account"

$existingUser = Get-LocalUser -Name $ITUser -ErrorAction SilentlyContinue

if (-not $existingUser) {
    Write-Host "ITAdmin does not exist. You will be asked to create its password."
    $Password = Read-Host "Enter password for $ITUser" -AsSecureString

    New-LocalUser `
        -Name $ITUser `
        -Password $Password `
        -FullName "Office IT Administrator" `
        -Description "IT Asset Management network access" | Out-Null

    Write-Host "Created local account: $ITUser" -ForegroundColor Green
}
else {
    Write-Host "Existing account found: $ITUser" -ForegroundColor Green
}

# Keep the account as a normal user. It does NOT need local Administrator rights
# merely to access the shared IT asset folder.
try {
    Add-LocalGroupMember -Group "Users" -Member $ITUser -ErrorAction SilentlyContinue
} catch {}

# -----------------------------
# 4. NTFS permissions
# -----------------------------
Write-Step "4. Setting folder permissions"

# Administrators = Full Control
# ITAdmin = Modify
icacls $RootPath /grant "Administrators:(OI)(CI)(F)" | Out-Null
icacls $RootPath /grant "${ITUser}:(OI)(CI)(M)" | Out-Null

Write-Host "NTFS permissions configured." -ForegroundColor Green

# -----------------------------
# 5. SMB share
# -----------------------------
Write-Step "5. Creating SMB network share"

$existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue

if ($existingShare) {
    Write-Host "Share already exists. Updating access."
    try {
        Revoke-SmbShareAccess -Name $ShareName -AccountName "Everyone" -Force -ErrorAction SilentlyContinue
    } catch {}

    Grant-SmbShareAccess `
        -Name $ShareName `
        -AccountName "$computerName\$ITUser" `
        -AccessRight Change `
        -Force | Out-Null
}
else {
    New-SmbShare `
        -Name $ShareName `
        -Path $RootPath `
        -ChangeAccess "$computerName\$ITUser" `
        -FullAccess "Administrators" | Out-Null
}

Write-Host "Share: \\$computerName\$ShareName" -ForegroundColor Green

# -----------------------------
# 6. Firewall rules
# -----------------------------
Write-Step "6. Configuring Windows Firewall"

try {
    Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction Stop
    Write-Host "File and Printer Sharing rules enabled." -ForegroundColor Green
} catch {
    Write-Host "Could not enable File and Printer Sharing group automatically." -ForegroundColor Yellow
}

try {
    Enable-NetFirewallRule -DisplayGroup "Network Discovery" -ErrorAction Stop
    Write-Host "Network Discovery rules enabled." -ForegroundColor Green
} catch {
    Write-Host "Could not enable Network Discovery group automatically." -ForegroundColor Yellow
}

# -----------------------------
# 7. Check network profile
# -----------------------------
Write-Step "7. Checking network profile"

$profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue

if ($profiles) {
    $profiles | Select-Object Name, InterfaceAlias, NetworkCategory |
        Format-Table -AutoSize

    $publicProfiles = @($profiles | Where-Object NetworkCategory -eq "Public")

    if ($publicProfiles.Count -gt 0) {
        Write-Host ""
        Write-Host "WARNING: One or more active network connections are Public." -ForegroundColor Yellow
        Write-Host "For office file sharing, set the trusted office network to Private."
        Write-Host "Do this in Windows Settings > Network & Internet > Network Properties."
    }
}
else {
    Write-Host "No active network profile detected." -ForegroundColor Yellow
}

# -----------------------------
# 8. Create connection info
# -----------------------------
Write-Step "8. Creating connection information"

$connectionFile = "$RootPath\ADMIN_CONNECTION.txt"

$ipAddresses = @(
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*"
    } |
    Select-Object -ExpandProperty IPAddress
)

@"
OFFICE IT ASSET MANAGEMENT - MASTER PC
=======================================

Computer Name:
$computerName

Network Share:
\\$computerName\$ShareName

Username:
$computerName\$ITUser

Central Folder:
$RootPath

Use this path from another office PC:
\\$computerName\$ShareName

Detected IPv4 address(es):
$($ipAddresses -join "`r`n")

IMPORTANT:
- Do not put the ITAdmin password in this file.
- Keep the ITAdmin password private.
- The MASTER PC must remain powered on and connected to the office network.
"@ | Set-Content -Path $connectionFile -Encoding UTF8

# -----------------------------
# 9. Create a deployment note
# -----------------------------
$readme = "$RootPath\README.txt"

@"
OFFICE IT ASSET MANAGEMENT
==========================

MASTER PC
---------
Computer name: $computerName
Share: \\$computerName\$ShareName

Folders
-------
Laptop Audit Reports
Purchase Invoices
Warranty
Service Records
User Handover
Backup
Deployment

Laptop workflow
---------------
1. Run the approved laptop audit script.
2. Generate the CSV/TXT audit report.
3. Upload the report to:
   \\$computerName\$ShareName\Laptop Audit Reports
4. Review/import the information into the Master Asset Register.

Security
--------
- ITAdmin is used for network access to the asset-management share.
- Never store the ITAdmin password inside a script or batch file.
- Do not collect passwords or BitLocker recovery keys in audit reports.
"@ | Set-Content -Path $readme -Encoding UTF8

# -----------------------------
# 10. Excel check
# -----------------------------
Write-Step "10. Checking Microsoft Excel"

$excelInstalled = $false

try {
    $excel = New-Object -ComObject Excel.Application
    $excelInstalled = $true
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
} catch {
    $excelInstalled = $false
}

if ($excelInstalled) {
    Write-Host "Microsoft Excel detected." -ForegroundColor Green
    Write-Host "Copy the supplied Master Asset Register.xlsx into:"
    Write-Host "$RootPath" -ForegroundColor Yellow
}
else {
    Write-Host "Microsoft Excel was not detected." -ForegroundColor Yellow
    Write-Host "The central share is still ready; the Excel workbook can be opened on another PC."
}

# -----------------------------
# 11. Final verification
# -----------------------------
Write-Step "11. Final verification"

Write-Host "Computer name : $computerName"
Write-Host "Share         : \\$computerName\$ShareName"
Write-Host "Root folder   : $RootPath"
Write-Host "IT account    : $computerName\$ITUser"

$shareTest = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue

if ($shareTest) {
    Write-Host ""
    Write-Host "SUCCESS: Central IT Asset Management share is ready." -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "ERROR: SMB share was not found. Review the messages above." -ForegroundColor Red
}

Write-Host ""
Write-Host "Next step: from another laptop, open:" -ForegroundColor Cyan
Write-Host "\\$computerName\$ShareName" -ForegroundColor Yellow
Write-Host ""
Write-Host "If Windows asks for credentials, use:" -ForegroundColor Cyan
Write-Host "$computerName\$ITUser" -ForegroundColor Yellow
Write-Host "(Enter the ITAdmin password you created.)"
Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
