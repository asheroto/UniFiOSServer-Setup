#Requires -RunAsAdministrator

<#PSScriptInfo

.VERSION 2.0.0

.GUID ea50c320-7d51-4b4a-843b-1a8a16d3769b

.AUTHOR asheroto

.COMPANYNAME asheroto

.TAGS PowerShell UniFi UniFiOS Server Windows boot startup scheduled-task service-account

.PROJECTURI https://github.com/asheroto/UniFiOSServer-Setup

.RELEASENOTES
[Version 2.0.0] - Add -Step1/-Step2/-Step3 flow. Add -TaskOnly for setups where UniFi OS Server is already installed. Add -Username to override the service account name. Add -Interactive for non-silent installer UI. Startup task is created disabled and enabled via -Step3. Moved desktop shortcut to svc_unifi after install. Password limited to 3 special characters. svc_unifi added to Users and Administrators groups. Fix re-run error when LsaPolicy type already exists. Nested virtualization check non-blocking with warning at end. Added section headers to output.
[Version 1.0.1] - Warn if WSL2 is not installed and provide instructions. Warn if UniFi Network Application is running and prompt user to export settings before continuing.
[Version 1.0.0] - Initial release.

#>

<#
.SYNOPSIS
    Sets up UniFi OS Server on Windows with a dedicated service account and auto-start on boot.
.DESCRIPTION
    Checks prerequisites (OS version, nested virtualization), warns if the old UniFi Network Application is running, creates a local service account (svc_unifi), grants it the Log On as a Batch Job right, and registers a scheduled task to launch UniFi OS Server 30 seconds after boot.
.EXAMPLE
    Setup-UniFiOSServer.ps1
.NOTES
    Version      : 2.0.0
    Created by   : asheroto
.LINK
    https://github.com/asheroto/UniFiOSServer-Setup
#>
[CmdletBinding()]
param (
    [switch]$Version,
    [switch]$Help,
    [switch]$Step1,
    [switch]$Step2,
    [switch]$Interactive,
    [switch]$Step3,
    [switch]$TaskOnly,
    [string]$Username = 'svc_unifi',
    [switch]$SetPassword
)

# Version
$CurrentVersion = '2.0.0'
$SvcUser        = $Username
$TaskName       = 'UniFi OS Server'

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
    Write-Host "  --- $Title ---" -ForegroundColor Cyan
    Write-Host ""
}

function Get-HypervisorInfo {
    $cs  = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor

    $hypervisor = $null
    if ($cs.Manufacturer -like 'Microsoft*' -and $cs.Model -like '*Virtual*') { $hypervisor = 'Hyper-V' }
    elseif ($cs.Manufacturer -like 'VMware*')                                  { $hypervisor = 'VMware' }
    elseif ($cs.Manufacturer -like 'innotek*' -or $cs.Model -like '*VirtualBox*') { $hypervisor = 'VirtualBox' }

    return @{
        Hypervisor         = $hypervisor
        NestedVirtMissing  = ($hypervisor -and -not $cpu.VirtualizationFirmwareEnabled)
    }
}

function Write-NestedVirtWarning {
    param([string]$Hypervisor, [string]$Indent = '  ')
    Write-Host "${Indent}WARNING: This machine is a $Hypervisor VM and nested virtualization is not enabled." -ForegroundColor Yellow
    Write-Host "${Indent}WSL2 requires nested virtualization -- UniFi OS Server will not work without it." -ForegroundColor White
    Write-Host "${Indent}Shut down this VM and enable nested virtualization on the host:" -ForegroundColor White
    Write-Host ""
    switch ($Hypervisor) {
        'Hyper-V' {
            Write-Host "${Indent}  Set-VMProcessor -VMName `"YourVMName`" -ExposeVirtualizationExtensions `$true" -ForegroundColor Cyan
        }
        'VMware' {
            Write-Host "${Indent}  Option 1 - Add to the VM's .vmx file:" -ForegroundColor White
            Write-Host "${Indent}    vhv.enable = `"TRUE`"" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "${Indent}  Option 2 - VMware UI: VM Settings > Processors > Enable Intel VT-x/AMD-V" -ForegroundColor White
        }
        'VirtualBox' {
            Write-Host "${Indent}  VBoxManage modifyvm `"YourVMName`" --nested-hw-virt on" -ForegroundColor Cyan
        }
    }
    Write-Host ""
}

# Display $PSVersionTable and Get-Host if -Verbose is specified
if ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
    $PSVersionTable
    Get-Host
}

Write-Host ""
Write-Host "  Setup-UniFiOSServer v$CurrentVersion" -ForegroundColor Cyan

if ($Step3) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "  ERROR: Scheduled task '$TaskName' not found. Run the script without parameters first." -ForegroundColor Red
        exit 1
    }
    Enable-ScheduledTask -TaskName $TaskName | Out-Null
    Write-Host ""
    Write-Host "  Scheduled task '$TaskName' has been enabled." -ForegroundColor Green
    Write-Host "  UniFi OS Server will start automatically on the next boot." -ForegroundColor White
    Write-Host ""
    Write-Host "  Complete any remaining setup steps in UniFi OS Server." -ForegroundColor White
    Write-Host "  The web interface is accessible from any user account at:" -ForegroundColor White
    Write-Host ""
    Write-Host "    https://localhost:11443" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Or via the UniFi cloud console if the device has been attached." -ForegroundColor White
    Write-Host ""
    Write-Host "  After rebooting, allow a few minutes for UniFi OS Server to" -ForegroundColor Gray
    Write-Host "  fully start before attempting to access the web interface." -ForegroundColor Gray
    Write-Host ""
    exit 0
}

if ($env:USERNAME -eq $SvcUser -and -not $Step2 -and -not $TaskOnly) {
    Write-Host ""
    Write-Host "  ERROR: Do not run setup as $SvcUser." -ForegroundColor Red
    Write-Host "  To install UniFi OS Server under this account, run:" -ForegroundColor White
    Write-Host ""
    Write-Host "    .\Setup-UniFiOSServer.ps1 -Step2" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

if ($Step2) {
    if ($env:USERNAME -ne $SvcUser) {
        Write-Host ""
        Write-Host "  ERROR: -Step2 must be run as $SvcUser, not $env:USERNAME." -ForegroundColor Red
        Write-Host "  Log off and log on as $SvcUser, then run:" -ForegroundColor White
        Write-Host ""
        Write-Host "    .\Setup-UniFiOSServer.ps1 -Step2" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  If you forgot the password, reset it or run -Step1 again." -ForegroundColor White
        Write-Host ""
        exit 1
    }
    $vmInfo2 = Get-HypervisorInfo
    Write-Section "Install UniFi OS Server"
    try {
        $apiUri = 'https://fw-update.ubnt.com/api/firmware-latest?filter=eq~~product~~unifi-os-server&filter=eq~~channel~~release'
        $raw    = Invoke-WebRequest -Uri $apiUri -UseBasicParsing
        $dlUrl  = [regex]::Match($raw.Content, 'https://fw-download\.ubnt\.com/data/unifi-os-server/[^"]+windows-x64-msi[^"]+\.exe').Value

        if (-not $dlUrl) {
            Write-Error "Could not find UniFi OS Server download URL. Download manually from https://www.ui.com/download"
            exit 1
        }

        $installer = Join-Path $env:TEMP "UniFiOSServer-Setup.exe"
        if (Test-Path $installer) {
            Write-Host "Installer already downloaded, skipping download." -ForegroundColor White
        } else {
            Write-Host "Downloading UniFi OS Server (~1.3 GB)..." -ForegroundColor White
            Start-BitsTransfer -Source $dlUrl -Destination $installer
        }

        $installerArgs = if ($Interactive) { @('/AllUsers') } else { @('/S', '/AllUsers') }
        if ($Interactive) {
            Write-Host ""
            Write-Host "  IMPORTANT: When prompted, choose " -NoNewline -ForegroundColor Yellow
            Write-Host "Install for anyone on this computer" -NoNewline -ForegroundColor Cyan
            Write-Host " and install to " -NoNewline -ForegroundColor Yellow
            Write-Host "Program Files" -NoNewline -ForegroundColor Cyan
            Write-Host ", not AppData." -ForegroundColor Yellow
            Write-Host ""
        }
        Write-Host "Installing... this may take several minutes." -ForegroundColor White
        $proc = Start-Process -FilePath $installer -ArgumentList $installerArgs -PassThru
        $elapsed = 0
        while (-not $proc.HasExited) {
            Start-Sleep -Seconds 5
            $elapsed += 5
            Write-Host "  Still installing... ($elapsed sec elapsed)" -ForegroundColor Gray
        }

        if ($proc.ExitCode -eq 0) {
            Remove-Item $installer -Force -ErrorAction SilentlyContinue

            $publicShortcut  = Join-Path $env:PUBLIC "Desktop\UniFi OS Server.lnk"
            $userDesktop     = Join-Path (Split-Path $env:USERPROFILE) "$SvcUser\Desktop"
            $userShortcut    = Join-Path $userDesktop "UniFi OS Server.lnk"
            if (Test-Path $publicShortcut) {
                if (-not (Test-Path $userDesktop)) { New-Item -ItemType Directory -Path $userDesktop -Force | Out-Null }
                Move-Item -Path $publicShortcut -Destination $userShortcut -Force -ErrorAction SilentlyContinue
                Write-Host "Moved desktop shortcut to $SvcUser's desktop." -ForegroundColor White
            }

            Write-Host "UniFi OS Server installed successfully." -ForegroundColor Green
            Write-Host ""
            Write-Host "  =========  NEXT STEPS  ========================================" -ForegroundColor Yellow
            Write-Host ""

            $istep = 1
            Write-Host "  $istep. " -NoNewline -ForegroundColor Yellow
            Write-Host "Run UniFi OS Server by double-clicking the icon on the desktop." -ForegroundColor White
            Write-Host ""
            $istep++

            Write-Host "  $istep. " -NoNewline -ForegroundColor Yellow
            Write-Host "A dialog may appear to complete the WSL2 installation." -ForegroundColor White
            Write-Host "     Click OK and allow it to finish. If prompted to reboot, click OK, then run -Step3." -ForegroundColor White
            Write-Host ""
            $istep++

            Write-Host "  $istep. " -NoNewline -ForegroundColor Yellow
            Write-Host "IMPORTANT: Do not launch UniFi OS Server from any account" -ForegroundColor Yellow
            Write-Host "     other than $SvcUser. It relies on that specific user profile" -ForegroundColor Yellow
            Write-Host "     for its WSL2 container -- launching it under a different account" -ForegroundColor Yellow
            Write-Host "     may corrupt the container." -ForegroundColor Yellow
            Write-Host ""
            $istep++

            Write-Host "  $istep. " -NoNewline -ForegroundColor Yellow
            Write-Host "Once initial setup is complete, enable the startup task:" -ForegroundColor White
            Write-Host ""
            Write-Host "     .\Setup-UniFiOSServer.ps1 -Step3" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  ================================================================" -ForegroundColor Yellow
            Write-Host ""
            if ($vmInfo2.NestedVirtMissing) {
                Write-Section "Nested Virtualization Warning"
                Write-NestedVirtWarning -Hypervisor $vmInfo2.Hypervisor
            }
        } else {
            Write-Warning "Installer exited with code $($proc.ExitCode) -- verify the installation completed."
        }
    } catch {
        Write-Error "Failed to download or install UniFi OS Server: $_"
    }
    exit 0
}

if (-not $Step1 -and -not $TaskOnly) {
    Write-Host ""
    Write-Host "  For best results, run this before installing UniFi OS Server." -ForegroundColor Gray
    Write-Host "  If it is already installed, run with -TaskOnly instead." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Run this script with a step parameter to get started:" -ForegroundColor White
    Write-Host ""
    Write-Host "    -Step1     Create the service account and register the startup task." -ForegroundColor Cyan
    Write-Host "               Run as Administrator." -ForegroundColor Gray
    Write-Host ""
    Write-Host "    -Step2     Download and install UniFi OS Server." -ForegroundColor Cyan
    Write-Host "               Run as $SvcUser." -ForegroundColor Gray
    Write-Host ""
    Write-Host "    -Step3     Enable the startup task after initial setup is complete." -ForegroundColor Cyan
    Write-Host "               Run as Administrator." -ForegroundColor Gray
    Write-Host ""
    Write-Host "    -TaskOnly  If UniFi OS Server is already installed, use this to" -ForegroundColor Cyan
    Write-Host "               create the service account and startup task only." -ForegroundColor Cyan
    Write-Host "               Specify the account with -Username." -ForegroundColor Gray
    Write-Host ""
    Write-Host "    -SetPassword  Prompt for a custom password for the service account." -ForegroundColor Cyan
    Write-Host "                  If omitted, a random password is generated." -ForegroundColor Gray
    Write-Host ""
    exit 0
}

if ($Step1) {

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

$vmInfo = Get-HypervisorInfo

} # end if ($Step1)

Write-Section "Configuration"
$ExePath  = "C:\Program Files\UniFi OS Server\UniFi OS Server.exe"

Write-Section "Create Service Account"
if ($Username -ne 'svc_unifi') {
    # Existing account provided - prompt for its password without resetting it
    Write-Host "Using existing account: $SvcUser"
    $secCred = Get-Credential -UserName "$env:COMPUTERNAME\$SvcUser" -Message "Enter the password for $SvcUser"
    if (-not $secCred) {
        Write-Host ""
        Write-Host "  ERROR: No credentials provided. Exiting." -ForegroundColor Red
        exit 1
    }
    $secPwd  = $secCred.Password
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd))
} else {
    if ($SetPassword) {
        $secCred = Get-Credential -UserName "$env:COMPUTERNAME\$SvcUser" -Message "Enter the password to set for $SvcUser"
        if (-not $secCred) {
            Write-Host ""
            Write-Host "  ERROR: No credentials provided. Exiting." -ForegroundColor Red
            exit 1
        }
        $secPwd  = $secCred.Password
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd))
    } else {
        $alphaNum = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        $special  = '!@#$'
        $specials = -join ((1..3) | ForEach-Object { $special[(Get-Random -Maximum $special.Length)] })
        $base     = -join ((1..13) | ForEach-Object { $alphaNum[(Get-Random -Maximum $alphaNum.Length)] })
        $password = -join (($base + $specials).ToCharArray() | Get-Random -Count 16)
        $secPwd   = [System.Security.SecureString]::new()
        foreach ($c in $password.ToCharArray()) { $secPwd.AppendChar($c) }
        $secPwd.MakeReadOnly()
    }

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
        Start-Sleep -Seconds 2
    }
}

foreach ($group in @('Users', 'Administrators')) {
    $members = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue
    if ($members.Name -notcontains "$env:COMPUTERNAME\$SvcUser") {
        Write-Host "Adding $SvcUser to $group group"
        Add-LocalGroupMember -Group $group -Member $SvcUser -ErrorAction SilentlyContinue
    }
}

Write-Section "Grant Log On As a Batch Job"
# LSA P/Invoke is used instead of secedit because it modifies only this specific right without exporting and re-importing the entire security policy.
if (-not ([System.Management.Automation.PSTypeName]'LsaPolicy').Type) { Add-Type @'
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
'@ }

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
    -RunLevel Highest | Out-Null

if (-not $TaskOnly) {
    Disable-ScheduledTask -TaskName $TaskName | Out-Null
}

Write-Host ""
Write-Host "  Task '" -NoNewline -ForegroundColor Green
Write-Host $TaskName -NoNewline -ForegroundColor Cyan
if ($TaskOnly) {
    Write-Host "' registered (enabled) under " -NoNewline -ForegroundColor Green
} else {
    Write-Host "' registered (disabled) under " -NoNewline -ForegroundColor Green
}
Write-Host $SvcUser -NoNewline -ForegroundColor Cyan
Write-Host "." -ForegroundColor Green

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
Write-Host "Log on as : " -NoNewline -ForegroundColor White
Write-Host "$env:COMPUTERNAME\$SvcUser" -ForegroundColor Cyan
if ($Username -eq 'svc_unifi') {
    Write-Host "     Password  : " -NoNewline -ForegroundColor White
    Write-Host $password -ForegroundColor Cyan
}
Write-Host ""
$step++

Write-Host "  $step. " -NoNewline -ForegroundColor Yellow
Write-Host "Install UniFi OS Server." -ForegroundColor White
Write-Host "     Option A - Run this script with " -NoNewline -ForegroundColor White
Write-Host "-Step2" -NoNewline -ForegroundColor Cyan
Write-Host " to download and install automatically." -ForegroundColor White
Write-Host "     Option B - Download manually from " -NoNewline -ForegroundColor White
Write-Host "https://www.ui.com/download" -NoNewline -ForegroundColor Cyan
Write-Host " -- install for " -NoNewline -ForegroundColor White
Write-Host "all users" -NoNewline -ForegroundColor Cyan
Write-Host ", choose " -NoNewline -ForegroundColor White
Write-Host "Program Files" -NoNewline -ForegroundColor Cyan
Write-Host ", not AppData." -ForegroundColor White
Write-Host ""
$step++

if ($vmInfo -and $vmInfo.NestedVirtMissing) {
    Write-Host "  $step. " -NoNewline -ForegroundColor Yellow
    Write-Host "Enable nested virtualization before continuing." -ForegroundColor Yellow
    Write-Host ""
    Write-NestedVirtWarning -Hypervisor $vmInfo.Hypervisor -Indent '     '
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


Write-Host "  ================================================================" -ForegroundColor Yellow
Write-Host "  IMPORTANT: Please read all steps above before proceeding." -ForegroundColor Yellow
if ($Username -eq 'svc_unifi') {
    Write-Host "             Save the $SvcUser password -- it is not stored anywhere." -ForegroundColor Yellow
}
Write-Host "  ================================================================" -ForegroundColor Yellow
Write-Host ""