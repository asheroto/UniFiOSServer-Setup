![UniFiOSServer-Setup screenshot](https://github.com/user-attachments/assets/106ed97e-092c-41d7-93cc-e2056962da54)

[![GitHub Downloads - All Releases](https://img.shields.io/github/downloads/asheroto/UniFiOSServer-Setup/total?label=release%20downloads)](https://github.com/asheroto/UniFiOSServer-Setup/releases)
[![Release](https://img.shields.io/github/v/release/asheroto/UniFiOSServer-Setup)](https://github.com/asheroto/UniFiOSServer-Setup/releases)
[![GitHub Release Date - Published_At](https://img.shields.io/github/release-date/asheroto/UniFiOSServer-Setup)](https://github.com/asheroto/UniFiOSServer-Setup/releases)

[![GitHub Sponsor](https://img.shields.io/github/sponsors/asheroto?label=Sponsor&logo=GitHub)](https://github.com/sponsors/asheroto?frequency=one-time&sponsor=asheroto)
<a href="https://ko-fi.com/asheroto"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Ko-Fi Button" height="20px"></a>
<a href="https://www.buymeacoffee.com/asheroto"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="40px"></a>

# Setup UniFi OS Server on Windows

[UniFi OS Server](https://www.ui.com/download) is Ubiquiti's self-hosted controller platform, replacing the legacy UniFi Network Application. It runs UniFi OS in a WSL2 container on Windows, giving you the same experience as a physical UniFi console (such as a Dream Machine or Cloud Gateway) without dedicated hardware.

Running it on Windows requires a bit of setup: unlike Linux or Docker, where it runs as a system service under a dedicated account, Windows ties the WSL2 environment to the user profile it was first configured in. That means it must always launch as that same user -- otherwise the container won't start correctly.

This script automates the entire process: it creates a dedicated local service account, configures the required rights, installs UniFi OS Server, and registers a scheduled task so it starts automatically at boot.

<details>
<summary>How it works</summary>

The script does the following:

- Verifies the OS is supported (Windows 10 1903+, Windows 11, or Windows Server 2022+)
- Warns if the old UniFi Network Application is running and provides commands to disable it -- it does **not** uninstall it or delete any data
- Detects if running in a Hyper-V, VMware, or VirtualBox VM and warns if nested virtualization is not enabled, providing the host-side command to enable it
- Creates a local service account (`svc_unifi`), grants it the **Log On as a Batch Job** right, and registers a scheduled task to launch UniFi OS Server 30 seconds after boot
- Downloads and installs UniFi OS Server (~1.3 GB) with WSL2 via `-Step2`
- Supports existing installations via `-TaskOnly` -- creates the service account and task without reinstalling

</details>

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

Open an elevated PowerShell session (Run as Administrator) and follow the steps below. Each step shows the short URL one-liner first, then the equivalent local command.

---

**Step 1** — Create the service account and register the startup task (run as Administrator):

```powershell
# One-liner
&([ScriptBlock]::Create((irm asheroto.com/unifios))) -Step1

# Local
.\Setup-UniFiOSServer.ps1 -Step1
```

Creates `svc_unifi`, grants it the required rights, and registers the startup task (disabled). **Save the password printed to the console** — it is not stored anywhere.

Then: log off and log on as `svc_unifi` using the password shown. Use `.\svc_unifi` (dot-backslash) at the login screen — it is a local account.

---

**Step 2** — Install UniFi OS Server (run as `svc_unifi`):

```powershell
# One-liner
&([ScriptBlock]::Create((irm asheroto.com/unifios))) -Step2

# Local
.\Setup-UniFiOSServer.ps1 -Step2
```

Downloads and installs UniFi OS Server (~1.3 GB) with WSL2. Click OK on any WSL2 dialogs that appear. Alternatively, install manually from https://www.ui.com/download — choose **all users** and `Program Files`, not `AppData`.

Then: launch UniFi OS Server from the desktop shortcut and complete initial configuration while logged in as `svc_unifi`. Do not launch it from any other account. A dialog may appear to complete the WSL2 installation — click OK and allow it to finish. If prompted to reboot, do so before continuing.

---

**Step 3** — Enable the startup task (run as Administrator):

```powershell
# One-liner
&([ScriptBlock]::Create((irm asheroto.com/unifios))) -Step3

# Local
.\Setup-UniFiOSServer.ps1 -Step3
```

Run this after you have launched UniFi OS Server, logged in, and completed first-time configuration. UniFi OS Server will start automatically under `svc_unifi` on every subsequent boot. Complete any remaining setup via the web interface at `https://localhost:11443`, or via the UniFi cloud console if the device has been attached.

## Parameters

| Parameter             | Description |
|-----------------------|-------------|
| `-Step1`              | Create the service account and register the startup task. Run as Administrator. |
| `-Step2`              | Download and install UniFi OS Server (~1.3 GB). Must be run as `svc_unifi`. |
| `-Step3`              | Enable the startup task after initial setup is complete. Run as Administrator. |
| `-TaskOnly`           | If UniFi OS Server is already installed, creates the service account and startup task only (task is left enabled). You will be prompted for credentials. |
| `-SetPassword`        | Prompt for a custom password for the service account instead of generating one randomly. |
| `-Interactive`        | Used with `-Step2`. Launches the installer UI instead of running silently. |
| `-Version`            | Print the script version and exit. |
| `-Help`               | Show full help and exit. |

## Notes

- `svc_unifi` is added to the **Users** and **Administrators** groups -- both are required for interactive login and for UniFi OS Server to function correctly (privileged ports, WSL2, and the scheduled task's Run Level Highest setting)
- If `svc_unifi` already exists, you will be prompted for the existing password. Use `-SetPassword` to reset it instead.
- If the scheduled task already exists, it is removed and re-created
- The password is randomly generated (16 characters) and passed directly to Task Scheduler -- **it is not saved anywhere**. Copy it from the console output before closing the window
- Running under SYSTEM will launch the process but UniFi OS Server will not function correctly; it requires the user context it was configured in
- Do not launch UniFi OS Server from any account other than `svc_unifi` -- it relies on that specific user profile for its WSL2 container and launching it under a different account may corrupt the container