[![GitHub Downloads - All Releases](https://img.shields.io/github/downloads/asheroto/UniFiOSServer-AutoStart/total?label=release%20downloads)](https://github.com/asheroto/UniFiOSServer-AutoStart/releases)
[![Release](https://img.shields.io/github/v/release/asheroto/UniFiOSServer-AutoStart)](https://github.com/asheroto/UniFiOSServer-AutoStart/releases)
[![GitHub Release Date - Published_At](https://img.shields.io/github/release-date/asheroto/UniFiOSServer-AutoStart)](https://github.com/asheroto/UniFiOSServer-AutoStart/releases)

[![GitHub Sponsor](https://img.shields.io/github/sponsors/asheroto?label=Sponsor&logo=GitHub)](https://github.com/sponsors/asheroto?frequency=one-time&sponsor=asheroto)
<a href="https://ko-fi.com/asheroto"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Ko-Fi Button" height="20px"></a>
<a href="https://www.buymeacoffee.com/asheroto"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&emoji=&slug=seb6596&button_colour=FFDD00&font_colour=000000&font_family=Lato&outline_colour=000000&coffee_colour=ffffff](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=asheroto&button_colour=FFDD00&font_colour=000000&font_family=Lato&outline_colour=000000&coffee_colour=ffffff)" height="40px"></a>

# Enable UniFi OS Server Auto-Start on Boot (Windows)

UniFi OS Server must run under the same user account it was initially configured in -- this is a Windows limitation. On Linux/Docker it runs as a system service and has no such constraint.

This script creates a dedicated local service account (`svc_unifi`), grants it the **Log On as a Batch Job** right, and registers a scheduled task to launch UniFi OS Server 30 seconds after boot under that account.

## Quick Run

Open an elevated PowerShell session (Run as Administrator) and run:

```powershell
irm asheroto.com/UniFiOS | iex
```

Alternatively, download the latest [Enable-UniFiOSAutoStart.ps1](https://github.com/asheroto/UniFiOSServer-AutoStart/releases/latest/download/Enable-UniFiOSAutoStart.ps1) from [Releases](https://github.com/asheroto/UniFiOSServer-AutoStart/releases) and run it locally:

```powershell
.\Enable-UniFiOSAutoStart.ps1
```

## Prerequisites

- Windows Server 2022 or higher (WSL2 is not supported on earlier versions)
- Run as Administrator

## Usage

Run the script in an elevated PowerShell session -- no prompts required. When it finishes, follow the **Next Steps** printed to the console:

1. Log off the current session
2. Log on as `.\svc_unifi` using the password shown
3. Download and install UniFi OS Server for **all users** -- when the installer asks where to install, choose `Program Files` (not `AppData`). Download from: https://www.ui.com/download
4. Launch UniFi OS Server and complete initial setup
5. Log off `svc_unifi`

The scheduled task will start UniFi OS Server under `svc_unifi` automatically on all future reboots.

## Notes

- If `svc_unifi` already exists, the script resets its password
- If the scheduled task already exists, it is removed and re-created
- The password is randomly generated (32 characters) and passed directly to Task Scheduler -- it is not saved anywhere. Copy it from the console output during setup
- Running under SYSTEM will launch the process but UniFi OS Server will not function correctly; it requires the user context it was configured in