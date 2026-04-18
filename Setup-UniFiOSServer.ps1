#Requires -RunAsAdministrator

<#PSScriptInfo

.VERSION 1.0.1

.GUID ea50c320-7d51-4b4a-843b-1a8a16d3769b

.AUTHOR asheroto

.COMPANYNAME asheroto

.TAGS PowerShell UniFi UniFiOS Server Windows boot startup scheduled-task service-account

.PROJECTURI https://github.com/asheroto/UniFiOSServer-AutoStart

.RELEASENOTES
[Version 1.0.1] - Enable WSL2 automatically if not already installed. Warn if UniFi Network Application is running and prompt user to export settings before continuing.
[Version 1.0.0] - Initial release.

#>

<#
.SYNOPSIS
    Configures UniFi OS Server to start automatically on boot under a dedicated service account.
.DESCRIPTION
    Creates a local service account (svc_unifi), grants it the Log On as a Batch Job right, and registers a scheduled task to launch UniFi OS Server 30 seconds after boot. This works around the Windows requirement that UniFi OS Server run under the same user account it was initially configured in.
.EXAMPLE
    Enable-UniFiOSAutoStart.ps1
.NOTES
    Version      : 1.0.1
    Created by   : asheroto
.LINK
    https://github.com/asheroto/UniFiOSServer-AutoStart
#>
[CmdletBinding()]
param (
    [switch]$Version,
    [switch]$Help
)

# Version
$CurrentVersion = '1.0.1'

# Display version if -Version is specified
if ($Version.IsPresent) {
    $CurrentVersion
    exit 0
}

# Display full help if -Help is specified
if ($Help) {
    Get-Help -Name $MyInvocation.MyCommand.Source -Full
    exit 0
}

# Display $PSVersionTable and Get-Host if -Verbose is specified
if ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
    $PSVersionTable
    Get-Host
}

# ===== OS Version Check =====
$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -eq 1) {
    Write-Error "This script requires Windows Server. Desktop editions are not supported."
    exit 1
}
# Windows Server 2022 = build 20348
if ([int]$os.BuildNumber -lt 20348) {
    Write-Error "Windows Server 2022 or higher is required (WSL2 is not supported on older versions). Detected: $($os.Caption) (build $($os.BuildNumber))"
    exit 1
}

# ===== UniFi Network Application Check =====
$unifiSvc  = Get-Service -Name "UniFi" -ErrorAction SilentlyContinue
$unifiProc = Get-Process -Name "UniFi" -ErrorAction SilentlyContinue

if (($unifiSvc -and $unifiSvc.Status -eq 'Running') -or $unifiProc) {
    Write-Host ""
    Write-Host "  WARNING: The UniFi Network Application appears to be running." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Before continuing, you must export your settings from the old" -ForegroundColor White
    Write-Host "  application so you can restore them in UniFi OS Server:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Settings > Backup > Download Backup" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Once exported, stop and disable the old application:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Stop-Service -Name 'UniFi' -Force" -ForegroundColor Cyan
    Write-Host "    Set-Service  -Name 'UniFi' -StartupType Disabled" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Then re-run this script to continue setup." -ForegroundColor White
    Write-Host ""
    exit 1
}

# ===== WSL2 Check =====
$wslFeature    = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
$vmFeature     = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
$wsl2WasEnabled = $false

if ($wslFeature.State -ne 'Enabled' -or $vmFeature.State -ne 'Enabled') {
    Write-Host "WSL2 is not enabled. Enabling required Windows features..."
    if ($wslFeature.State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
    }
    if ($vmFeature.State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    }
    Write-Host "WSL2 features enabled."
    $wsl2WasEnabled = $true
}

# ===== Config =====
$ExePath   = "C:\Program Files\UniFi OS Server\UniFi OS Server.exe"
$TaskName  = "UniFi OS Server"
$SvcUser   = "svc_unifi"

# ===== Create Service Account =====
$chars    = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
$password = -join ((1..32) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
$secPwd   = [System.Security.SecureString]::new()
foreach ($c in $password.ToCharArray()) { $secPwd.AppendChar($c) }
$secPwd.MakeReadOnly()

$ExistingUser = Get-LocalUser -Name $SvcUser -ErrorAction SilentlyContinue
if (-not $ExistingUser) {
    Write-Host "Creating local user: $SvcUser"
    New-LocalUser -Name $SvcUser `
                  -Password $secPwd `
                  -PasswordNeverExpires `
                  -UserMayNotChangePassword `
                  -AccountNeverExpires `
                  -Description "UniFi OS Server service account" | Out-Null
} else {
    Write-Host "User $SvcUser already exists - resetting password"
    Set-LocalUser -Name $SvcUser -Password $secPwd
}

# ===== Grant Log On As a Batch Job =====
# LSA P/Invoke is used instead of secedit because it modifies only this specific right without exporting and re-importing the entire security policy.
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;

public class LsaPolicy {
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern uint LsaOpenPolicy(
        ref LSA_UNICODE_STRING SystemName,
        ref LSA_OBJECT_ATTRIBUTES ObjectAttributes,
        uint DesiredAccess,
        out IntPtr PolicyHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    static extern uint LsaAddAccountRights(
        IntPtr PolicyHandle,
        IntPtr AccountSid,
        LSA_UNICODE_STRING[] UserRights,
        uint CountOfRights);

    [DllImport("advapi32.dll")]
    static extern int LsaClose(IntPtr ObjectHandle);

    [DllImport("advapi32.dll")]
    static extern int LsaNtStatusToWinError(uint Status);

    [StructLayout(LayoutKind.Sequential)]
    struct LSA_UNICODE_STRING {
        public ushort Length;
        public ushort MaximumLength;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string Buffer;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public int Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }

    const uint POLICY_ALL_ACCESS = 0x00F0FFF;

    public static void GrantRight(string accountName, string rightName) {
        var sid = (SecurityIdentifier)new NTAccount(accountName).Translate(typeof(SecurityIdentifier));
        byte[] sidBytes = new byte[sid.BinaryLength];
        sid.GetBinaryForm(sidBytes, 0);

        var sysName = new LSA_UNICODE_STRING();
        var objAttrs = new LSA_OBJECT_ATTRIBUTES {
            Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES))
        };

        IntPtr policy;
        uint status = LsaOpenPolicy(ref sysName, ref objAttrs, POLICY_ALL_ACCESS, out policy);
        if (status != 0) throw new Exception("LsaOpenPolicy failed: " + LsaNtStatusToWinError(status));

        IntPtr sidPtr = Marshal.AllocHGlobal(sidBytes.Length);
        try {
            Marshal.Copy(sidBytes, 0, sidPtr, sidBytes.Length);
            var rights = new[] {
                new LSA_UNICODE_STRING {
                    Buffer        = rightName,
                    Length        = (ushort)(rightName.Length * 2),
                    MaximumLength = (ushort)((rightName.Length + 1) * 2)
                }
            };
            status = LsaAddAccountRights(policy, sidPtr, rights, 1);
            if (status != 0) throw new Exception("LsaAddAccountRights failed: " + LsaNtStatusToWinError(status));
        } finally {
            Marshal.FreeHGlobal(sidPtr);
            LsaClose(policy);
        }
    }
}
'@

Write-Host "Granting SeBatchLogonRight to $SvcUser"
[LsaPolicy]::GrantRight("$env:COMPUTERNAME\$SvcUser", "SeBatchLogonRight")

# ===== Action =====
$Action = New-ScheduledTaskAction -Execute $ExePath -WorkingDirectory (Split-Path $ExePath)

# ===== Trigger =====
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Trigger.Delay = "PT30S"

# ===== Settings =====
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

# ===== Remove Existing Task =====
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Removing existing task: $TaskName"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# ===== Register Task =====
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -User "$env:COMPUTERNAME\$SvcUser" `
    -Password $password `
    -RunLevel Highest

Write-Host ""
Write-Host "  Task '" -NoNewline -ForegroundColor Green
Write-Host $TaskName -NoNewline -ForegroundColor Cyan
Write-Host "' registered under " -NoNewline -ForegroundColor Green
Write-Host $SvcUser -NoNewline -ForegroundColor Cyan
Write-Host "." -ForegroundColor Green

Write-Host ""
Write-Host "  =========  NEXT STEPS  ========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Before the scheduled task can run, UniFi OS Server must be" -ForegroundColor White
Write-Host "  launched and initially configured under the service account." -ForegroundColor White
Write-Host ""

$step = 1
if ($wsl2WasEnabled) {
    Write-Host "  $step. " -NoNewline -ForegroundColor Yellow
    Write-Host "Reboot the machine to finish enabling WSL2, then continue the steps below." -ForegroundColor White
    Write-Host ""
    $step++
}

Write-Host "  $step. " -NoNewline -ForegroundColor Yellow
Write-Host "Log off the current session." -ForegroundColor White
Write-Host ""
$step++

Write-Host "  $step. " -NoNewline -ForegroundColor Yellow
Write-Host "Log on as:  " -NoNewline -ForegroundColor White
Write-Host "$env:COMPUTERNAME\$SvcUser" -ForegroundColor Cyan
Write-Host "     Password:  " -NoNewline -ForegroundColor White
Write-Host $password -ForegroundColor Cyan
Write-Host ""
$step++

Write-Host "  $step. " -NoNewline -ForegroundColor Yellow
Write-Host "Download and install UniFi OS Server for " -NoNewline -ForegroundColor White
Write-Host "all users" -NoNewline -ForegroundColor Cyan
Write-Host " (choose " -NoNewline -ForegroundColor White
Write-Host "Program Files" -NoNewline -ForegroundColor Cyan
Write-Host ", not AppData):" -ForegroundColor White
Write-Host "     https://www.ui.com/download" -ForegroundColor Cyan
Write-Host ""
$step++

Write-Host "  $step. " -NoNewline -ForegroundColor Yellow
Write-Host "Launch UniFi OS Server and complete initial setup." -ForegroundColor White
Write-Host ""
$step++

Write-Host "  $step. " -NoNewline -ForegroundColor Yellow
Write-Host "Log off $SvcUser." -ForegroundColor White
Write-Host ""
Write-Host "  The scheduled task will start UniFi OS Server under $SvcUser" -ForegroundColor Gray
Write-Host "  automatically on all future reboots." -ForegroundColor Gray
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Yellow
Write-Host ""