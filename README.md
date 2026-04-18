[![GitHub Downloads - All Releases](https://img.shields.io/github/downloads/asheroto/UniFiOSServer-Setup/total?label=release%20downloads)](https://github.com/asheroto/UniFiOSServer-Setup/releases)
[![Release](https://img.shields.io/github/v/release/asheroto/UniFiOSServer-Setup)](https://github.com/asheroto/UniFiOSServer-Setup/releases)
[![GitHub Release Date - Published_At](https://img.shields.io/github/release-date/asheroto/UniFiOSServer-Setup)](https://github.com/asheroto/UniFiOSServer-Setup/releases)

[![GitHub Sponsor](https://img.shields.io/github/sponsors/asheroto?label=Sponsor&logo=GitHub)](https://github.com/sponsors/asheroto?frequency=one-time&sponsor=asheroto)
<a href="https://ko-fi.com/asheroto"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Ko-Fi Button" height="20px"></a>
<a href="https://www.buymeacoffee.com/asheroto"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&emoji=&slug=seb6596&button_colour=FFDD00&font_colour=000000&font_family=Lato&outline_colour=000000&coffee_colour=ffffff](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=asheroto&button_colour=FFDD00&font_colour=000000&font_family=Lato&outline_colour=000000&coffee_colour=ffffff)" height="40px"></a>

# Setup UniFi OS Server on Windows

UniFi OS Server must run under the same user account it was initially configured in -- this is a Windows limitation. On Linux/Docker it runs as a system service and has no such constraint.

The script does the following:

- Verifies the OS is supported (Windows 10 1903+, Windows 11, or Windows Server 2022+)
- Warns if the old UniFi Network Application is running, and prompts you to export your settings before continuing
- Detects if running in a Hyper-V, VMware, or VirtualBox VM and warns if nested virtualization is not enabled, providing the host-side command to enable it
- Creates a local service account (`svc_unifi`), grants it the **Log On as a Batch Job** right, and registers a scheduled task to launch UniFi OS Server 30 seconds after boot
- Downloads and installs UniFi OS Server (~1.3 GB) with WSL2 via `-Step2`
- Supports existing installations via `-TaskOnly` -- creates the service account and task without reinstalling

## Quick Run

Open an elevated PowerShell session (Run as Administrator). There are two ways to run the script: using the short URL one-liner, or downloading and running locally.

**Method 1** - short URL one-liner (no download required, supports parameters):

```powershell
&([ScriptBlock]::Create((irm asheroto.com/unifios)))
```

**Method 2** - download and run locally. Download [Setup-UniFiOSServer.ps1](https://github.com/asheroto/UniFiOSServer-Setup/releases/latest/download/Setup-UniFiOSServer.ps1) from [Releases](https://github.com/asheroto/UniFiOSServer-Setup/releases), then run:

```powershell
.\Setup-UniFiOSServer.ps1
```

## Prerequisites

- Windows 10 1903+, Windows 11, or Windows Server 2022+
- Run as Administrator

## Usage

For best results, run this before installing UniFi OS Server. If it is already installed, run with `-TaskOnly` instead.

### Step 1 - Run setup as Administrator

```powershell
&([ScriptBlock]::Create((irm asheroto.com/unifios))) -Step1
# or
.\Setup-UniFiOSServer.ps1 -Step1
```

Creates `svc_unifi`, grants it the required rights, and registers the startup task (disabled). **Save the password printed to the console** - it is not stored anywhere.

### Step 2 - Log on as svc_unifi

Log off and log on as `svc_unifi` using the password shown. Use `.\svc_unifi` (dot-backslash) at the login screen - it is a local account.

### Step 3 - Install UniFi OS Server

```powershell
&([ScriptBlock]::Create((irm asheroto.com/unifios))) -Step2
# or
.\Setup-UniFiOSServer.ps1 -Step2
```

Downloads and installs UniFi OS Server (~1.3 GB) with WSL2. Click OK on any WSL2 dialogs that appear. Alternatively, install manually from https://www.ui.com/download - choose **all users** and `Program Files`, not `AppData`.

### Step 4 - Complete initial setup

Launch UniFi OS Server and finish the initial configuration while logged in as `svc_unifi`. Do not launch it from any other account.

A dialog may appear asking to install WSL2 -- click OK and allow it to complete. If prompted to reboot, click OK, then run `-Step3`.

### Step 5 - Enable the startup task

Run as Administrator:

```powershell
&([ScriptBlock]::Create((irm asheroto.com/unifios))) -Step3
# or
.\Setup-UniFiOSServer.ps1 -Step3
```

UniFi OS Server will start automatically under `svc_unifi` on the next boot. Complete any remaining setup steps via the web interface at `https://localhost:11443`, or via the UniFi cloud console if the device has been attached.

## Parameters

| Parameter             | Description |
|-----------------------|-------------|
| `-Step1`              | Create the service account and register the startup task. Run as Administrator. |
| `-Step2`              | Download and install UniFi OS Server (~1.3 GB). Must be run as `svc_unifi`. |
| `-Step3`              | Enable the startup task after initial setup is complete. Run as Administrator. |
| `-TaskOnly`           | If UniFi OS Server is already installed, creates the service account and startup task only (task is left enabled). You will be prompted for credentials. |
| `-Interactive`        | Used with `-Step2`. Launches the installer UI instead of running silently. |
| `-SetPassword`        | Prompt for a custom password for the service account instead of generating one randomly. |
| `-Version`            | Print the script version and exit. |
| `-Help`               | Show full help and exit. |

## Notes

- `svc_unifi` is added to the **Users** and **Administrators** groups -- both are required for interactive login and for UniFi OS Server to function correctly (privileged ports, WSL2, and the scheduled task's Run Level Highest setting)
- If `svc_unifi` already exists, you will be prompted for the existing password. Use `-SetPassword` to reset it instead.
- If the scheduled task already exists, it is removed and re-created
- The password is randomly generated (16 characters) and passed directly to Task Scheduler -- **it is not saved anywhere**. Copy it from the console output before closing the window
- Running under SYSTEM will launch the process but UniFi OS Server will not function correctly; it requires the user context it was configured in
- Do not launch UniFi OS Server from any account other than `svc_unifi` -- it relies on that specific user profile for its WSL2 container and launching it under a different account may corrupt the container
