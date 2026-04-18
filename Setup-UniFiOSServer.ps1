#Requires -RunAsAdministrator

<#PSScriptInfo

.VERSION 1.1.0

.GUID ea50c320-7d51-4b4a-843b-1a8a16d3769b

.AUTHOR asheroto

.COMPANYNAME asheroto

.TAGS PowerShell UniFi UniFiOS Server Windows boot startup scheduled-task service-account

.PROJECTURI https://github.com/asheroto/UniFiOSServer-Setup

.RELEASENOTES
[Version 1.1.0] - Add -Install parameter to download and launch the UniFi OS Server installer automatically. Move nested virtualization warning to end of output instead of exiting early.
[Version 1.0.1] - Enable WSL2 automatically if not already installed. Warn if UniFi Network Application is running and prompt user to export settings before continuing.
[Version 1.0.0] - Initial release.

#>

<#
.SYNOPSIS
    Sets up UniFi OS Server on Windows with a dedicated service account and auto-start on boot.
.DESCRIPTION
    Checks prerequisites (OS version, WSL2, nested virtualization), warns if the old UniFi Network Application is running, creates a local service account (svc_unifi), grants it the Log On as a Batch Job right, and registers a scheduled task to launch UniFi OS Server 30 seconds after boot.
.EXAMPLE
    Setup-UniFiOSServer.ps1
.NOTES
    Version      : 1.1.0
    Created by   : asheroto
.LINK
    https://github.com/asheroto/UniFiOSServer-Setup
#>
[CmdletBinding()]
param (
    [switch]$Version,
    [switch]$Help,
    [switch]$Install
)

# Version
$CurrentVersion = '1.1.0'

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

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  -- $Title" -ForegroundColor DarkGray
    Write-Host ""
}

# Display $PSVersionTable and Get-Host if -Verbose is specified
if ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
    $PSVersionTable
    Get-Host
}

Write-Host ""
Write-Host "  Setup-UniFiOSServer v$CurrentVersion" -ForegroundColor Cyan

Write-Section "OS Version Check"
# Desktop: Windows 10 1903+ (build 18362), Windows 11 (build 22000+)
# Server:  Windows Server 2022+ (build 20348)
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
if ($os.ProductType -eq 1) {
    # Desktop
    if ($build -lt 18362) {
        Write-Error "Windows 10 1903 or higher is required. Detected: $($os.Caption) (build $build)"
        exit 1
    }
} else {
    # Server
    if ($build -lt 20348) {
        Write-Error "Windows Server 2022 or higher is required. Detected: $($os.Caption) (build $build)"
        exit 1
    }
}

Write-Section "UniFi Network Application Check"
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

Write-Section "Nested Virtualization Check"
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor

$hypervisor = $null
if ($cs.Manufacturer -like 'Microsoft*' -and $cs.Model -like '*Virtual*') { $hypervisor = 'Hyper-V' }
elseif ($cs.Manufacturer -like 'VMware*')                                  { $hypervisor = 'VMware' }
elseif ($cs.Manufacturer -like 'innotek*' -or $cs.Model -like '*VirtualBox*') { $hypervisor = 'VirtualBox' }

$nestedVirtMissing = $hypervisor -and -not $cpu.VirtualizationFirmwareEnabled

Write-Section "WSL2 Check"
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
$vmPlatform = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue

$wsl2Missing = $wslFeature.State -ne 'Enabled' -or $vmPlatform.State -ne 'Enabled'

Write-Section "Configuration"
$ExePath   = "C:\Program Files\UniFi OS Server\UniFi OS Server.exe"
$TaskName  = "UniFi OS Server"
$SvcUser   = "svc_unifi"

Write-Section "Create Service Account"
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

Write-Section "Grant Log On As a Batch Job"
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

Write-Section "Scheduled Task"
$Action = New-ScheduledTaskAction -Execute $ExePath -WorkingDirectory (Split-Path $ExePath)

$Trigger = New-ScheduledTaskTrigger -AtStartup
$Trigger.Delay = "PT30S"

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Removing existing task: $TaskName"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

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

Write-Section "Install UniFi OS Server"
$serverInstalled = $false
if ($Install) {
    Write-Host ""
    Write-Host "Fetching UniFi OS Server download URL..." -ForegroundColor White
    try {
        $apiUri  = 'https://fw-update.ubnt.com/api/firmware-latest?filter=eq~~product~~unifi-os-server&filter=eq~~channel~~release'
        $raw     = Invoke-WebRequest -Uri $apiUri -UseBasicParsing
        $dlUrl   = [regex]::Match($raw.Content, 'https://fw-download\.ubnt\.com/data/unifi-os-server/[^"]+windows-x64-msi[^"]+\.exe').Value

        if (-not $dlUrl) {
            Write-Error "Could not find UniFi OS Server download URL. Download manually from https://www.ui.com/download"
        } else {
            $installer = Join-Path $env:TEMP "UniFiOSServer-Setup.exe"
            Write-Host "Downloading UniFi OS Server (~1.3 GB)..." -ForegroundColor White
            Start-BitsTransfer -Source $dlUrl -Destination $installer

            Write-Host "Launching installer..." -ForegroundColor White
            $proc = Start-Process -FilePath $installer -ArgumentList '/AllUsers' -Wait -PassThru
            Remove-Item $installer -Force -ErrorAction SilentlyContinue

            if ($proc.ExitCode -eq 0) {
                Write-Host "UniFi OS Server installed successfully." -ForegroundColor Green
                $serverInstalled = $true
            } else {
                Write-Warning "Installer exited with code $($proc.ExitCode) -- verify the installation completed."
            }
        }
    } catch {
        Write-Error "Failed to download or install UniFi OS Server: $_"
    }
}

Write-Host ""
Write-Host "  =========  NEXT STEPS  ========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Before the scheduled task can run, UniFi OS Server must be" -ForegroundColor White
Write-Host "  launched and initially configured under the service account." -ForegroundColor White
Write-Host ""

$step = 1
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

if (-not $serverInstalled) {
    Write-Host "  $step. " -NoNewline -ForegroundColor Yellow
    Write-Host "Download and install UniFi OS Server for " -NoNewline -ForegroundColor White
    Write-Host "all users" -NoNewline -ForegroundColor Cyan
    Write-Host " (choose " -NoNewline -ForegroundColor White
    Write-Host "Program Files" -NoNewline -ForegroundColor Cyan
    Write-Host ", not AppData):" -ForegroundColor White
    Write-Host "     https://www.ui.com/download" -ForegroundColor Cyan
    Write-Host ""
    $step++
}

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

if ($wsl2Missing) {
    Write-Host "  WARNING: WSL2 is not installed. Run the following command, then reboot:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    wsl --install --no-distribution" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  After rebooting, install UniFi OS Server, then re-run this script." -ForegroundColor White
    Write-Host ""
}

if ($nestedVirtMissing) {
    Write-Host "  WARNING: This machine is a $hypervisor VM and nested virtualization is not enabled." -ForegroundColor Yellow
    Write-Host "  WSL2 requires nested virtualization. Shut down this VM and enable it on the host:" -ForegroundColor White
    Write-Host ""
    switch ($hypervisor) {
        'Hyper-V' {
            Write-Host '    Set-VMProcessor -VMName "YourVMName" -ExposeVirtualizationExtensions $true' -ForegroundColor Cyan
        }
        'VMware' {
            Write-Host "    Option 1 - Add to the VM's .vmx file:" -ForegroundColor White
            Write-Host '      vhv.enable = "TRUE"' -ForegroundColor Cyan
            Write-Host ""
            Write-Host "    Option 2 - VMware UI: VM Settings > Processors > Enable Intel VT-x/AMD-V" -ForegroundColor White
        }
        'VirtualBox' {
            Write-Host '    VBoxManage modifyvm "YourVMName" --nested-hw-virt on' -ForegroundColor Cyan
        }
    }
    Write-Host ""
}