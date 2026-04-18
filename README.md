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
- Checks that WSL2 is installed -- if not, provides instructions to install it and exits
- Detects if running in a Hyper-V, VMware, or VirtualBox VM and warns if nested virtualization is not enabled, providing the host-side command to enable it
- Creates a local service account (`svc_unifi`), or resets its password if it already exists
- Grants the account the **Log On as a Batch Job** right
- Registers a scheduled task to launch UniFi OS Server 30 seconds after boot under that account
- Optionally downloads and launches the UniFi OS Server installer automatically (`-Install`)

## Quick Run

Open an elevated PowerShell session (Run as Administrator). There are three ways to run the script: using `irm` with the short URL, using `irm` with the full release URL, or downloading and running locally.

**Method 1** - `irm` short URL (recommended):

```powershell
irm asheroto.com/UniFiOS | iex
```

**Method 2** - `irm` full release URL:

```powershell
irm https://github.com/asheroto/UniFiOSServer-Setup/releases/latest/download/Setup-UniFiOSServer.ps1 | iex
```

**Method 3** - download and run locally. Download [Setup-UniFiOSServer.ps1](https://github.com/asheroto/UniFiOSServer-Setup/releases/latest/download/Setup-UniFiOSServer.ps1) from [Releases](https://github.com/asheroto/UniFiOSServer-Setup/releases), then run:

```powershell
.\Setup-UniFiOSServer.ps1
```

To also download and install UniFi OS Server automatically, add `-Install`:

```powershell
.\Setup-UniFiOSServer.ps1 -Install
```

## Prerequisites

- Windows 10 1903+, Windows 11, or Windows Server 2022+
- Run as Administrator

## Usage

Run the script in an elevated PowerShell session -- no prompts required. When it finishes, follow the **Next Steps** printed to the console:

1. Log off the current session
2. Log on as `.\svc_unifi` using the password shown -- **save this password**, it is not stored anywhere. `svc_unifi` is a **local account**, not a domain account. Use `.\svc_unifi` (with the dot-backslash) at the login screen, not `svc_unifi` alone
3. Download and install UniFi OS Server for **all users** -- when the installer asks where to install, choose `Program Files` (not `AppData`). Download from: https://www.ui.com/download
4. Launch UniFi OS Server and complete initial setup
5. Log off `svc_unifi`

The scheduled task will start UniFi OS Server under `svc_unifi` automatically on all future reboots.

## Parameters

| Parameter  | Description |
|------------|-------------|
| `-Install` | Fetch the latest UniFi OS Server release from Ubiquiti, download it (~1.3 GB), and launch the installer automatically. |
| `-Version` | Print the script version and exit. |
| `-Help`    | Show full help and exit. |

## Notes

- If `svc_unifi` already exists, the script resets its password
- If the scheduled task already exists, it is removed and re-created
- The password is randomly generated (32 characters) and passed directly to Task Scheduler -- **it is not saved anywhere**. Copy it from the console output before closing the window
- Running under SYSTEM will launch the process but UniFi OS Server will not function correctly; it requires the user context it was configured in