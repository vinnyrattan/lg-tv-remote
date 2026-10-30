# LG webOS TV Remote — PowerShell GUI for Windows

A Windows desktop GUI for connecting to an LG webOS smart TV over your local network. Pair with the TV, reconnect using a saved key, inspect installed apps and settings, launch apps, and send custom SSAP WebSocket requests without writing connection code.

Independent community tool; not affiliated with LG. Compatibility depends on the TV model, firmware, and permissions granted by the TV. This is a remote-control client, not a rooting or automatic debloating tool.

## Features

- Connect, disconnect, reconnect, and request a new pairing.
- Choose pairing permissions for app lists, settings, current app, software information, app launching, and volume controls.
- Read TV identity, installed apps, launcher tiles, available services, selected privacy settings, and other supported information.
- Select an installed app and launch it when permitted.
- Send custom `ssap://` requests with JSON parameters.
- View requests and formatted replies in a session log.
- Store pairing keys encrypted for the current Windows account.
- Confirm the TV certificate on first use and when its fingerprint changes.

## Requirements

- Windows with a desktop session and PowerShell 7 or later. Windows PowerShell 5.1 is not supported.
- An LG webOS TV with its local remote-control service enabled.
- Computer and TV on a network that allows communication between them.
- Access to the TV remote to approve pairing.

No third-party PowerShell modules, Python, Node.js, cloud account, or administrator privileges are required by this app.

## Install on Windows

1. Install PowerShell 7 from a terminal:

   ```powershell
   winget install --id Microsoft.PowerShell --source winget
   ```

   Alternatively, follow [Microsoft's PowerShell installation instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).

2. Download this repository using **Code → Download ZIP**, then extract it. Keep `LG-TV-Remote.ps1` and `Start-LG-TV.cmd` together.
3. Review the script before running it. For trusted downloads, if Windows blocks the extracted files, use their **Properties → Unblock** option when present.
4. Double-click **Start-LG-TV.cmd**.

The launcher requires `pwsh.exe` on PATH. Restart your terminal or sign out and back in if a new PowerShell installation is not found.

You can also start the GUI from its folder:

```powershell
pwsh -NoProfile -STA -File .\LG-TV-Remote.ps1
```

The launcher uses `-ExecutionPolicy Bypass` for its child PowerShell process only; it does not change your saved execution policy. Organizational policies may still prevent execution. A digital signature is not included.

## Connect and pair

1. Turn on the TV. Find its IPv4 address in the TV's network settings or your router's device list.
2. Enter that address in **TV address**. This version accepts IPv4 addresses, not hostnames.
3. Select the permissions you need. Start with the default read permissions. Selecting a box requests permission; it does not guarantee the TV will grant it.
4. Click **Request pairing**.
5. Confirm the local certificate fingerprint when prompted. Verify that the address belongs to your TV before trusting it.
6. Accept the connection prompt on the TV. Keep the app open while approval is pending.
7. Wait for **Paired and connected**, then select an action and click **Run request**.

Use **Connect** or **Reconnect** on later visits with the same TV address. Re-enter the address each time; it is not automatically filled in. A router DHCP reservation can keep the TV address stable.

To change requested permissions, select the boxes and click **Request pairing** again. Merely checking a box does not alter an existing pairing key.

For app launching, request **Launch apps**, run **Installed apps**, choose an app in the adjacent list, then click **Launch app**.

## How the connection works

```text
Windows GUI → local network → wss://<TV IPv4 address>:3001 → LG TV SSAP service
```

The app uses .NET's `ClientWebSocket` to open a TLS-encrypted WebSocket connection on TCP port 3001. It exchanges JSON messages using LG's SSAP remote-control interface.

First-time registration sends a pairing manifest listing requested permissions. After approval on the TV, a successful registration returns a `client-key`. Future registrations send that key instead of requiring a fresh prompt. Requests contain a unique ID, a `ssap://` URI, and JSON parameters; the GUI matches replies to request IDs.

LG TVs may use locally issued or self-signed certificates. The app permits the TLS handshake, then compares the certificate fingerprint with the locally trusted fingerprint before sending pairing credentials. First-use or changed certificates require confirmation. This is trust on first use, not validation through a public certificate authority. A TV firmware update can change its certificate; verify the device before accepting a change.

The tool connects directly to the address you enter. It does not discover TVs, open router ports, contact a hosted backend, or intentionally upload its logs. Keep it on a trusted LAN; do not forward port 3001 to the internet. TV and streaming-app network traffic is separate and is not blocked by this client.

## Permissions and limitations

| Permission | Intended use |
| --- | --- |
| `READ_INSTALLED_APPS` | Installed app inventory |
| `READ_SETTINGS` | Settings exposed for reading |
| `READ_RUNNING_APPS` | Foreground/running app information |
| `READ_UPDATE_INFO` | Software information |
| `LAUNCH` | Launching installed apps |
| `CONTROL_AUDIO` | Audio controls on supported firmware |
| `WRITE_SETTINGS` | Requesting settings changes where permitted |

Firmware can restrict individual commands even after pairing. A permission name is not administrator access. Some settings are unavailable through SSAP, and newer firmware may reject operations supported on older models.

The app does not automatically remove apps, disable telemetry or microphones, configure startup apps, modify firmware, or obtain root access. The built-in privacy actions read selected settings. Custom requests can change behavior if the TV allows them, so review the URI and parameters before confirming.

### Custom request example

Read Live Plus viewing-recognition status:

**Address**

```text
ssap://settings/getSystemSettings
```

**JSON parameters**

```json
{"category":"option","keys":["livePlus"]}
```

This reads the setting; it does not disable it.

## Local data and privacy

Runtime data is saved outside the repository at:

```text
%LOCALAPPDATA%\LG-TV-Remote\settings.json
```

This file contains TV addresses, certificate fingerprints, and pairing keys encrypted using Windows account protection through PowerShell secure-string serialization. It is not portable between accounts or machines in the normal case. Encryption does not protect against software running as your Windows user, so treat the whole file as sensitive.

The GUI does not save its request log automatically. However, replies can contain serial numbers, device names, installed apps, addresses, and other identifying details. Redact screenshots and copied replies before sharing them. Pairing credentials are not intentionally printed in the log.

**Forget saved key** removes the selected TV's key from local storage and disconnects. It retains the trusted certificate record and does not revoke existing TV-side authorizations or keys held by other clients. Remove authorized remote devices using your TV's available controls if you need revocation; options differ by model.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No saved key | Use Request pairing first. |
| Connection refused or timed out | TV is on, address is current, LAN access is allowed, and the remote-control service is enabled. Guest Wi-Fi/client isolation can block access. |
| No approval prompt | Look at the TV screen, retry Request pairing, and check the TV's connection/remote-control settings. |
| `401 insufficient permissions` | Request pairing with the relevant permission selected. Protected commands may still be denied. |
| `404 no such service or method` | The endpoint is unavailable on this firmware. |
| `500` / keys not allowed | The settings API does not expose the requested category/key combination. |
| Certificate changed | Verify the TV and address before trusting the replacement fingerprint. |
| Address changed | Enter the new address and pair again; records are stored by IP address. |

The GUI waits for a reply during a request and temporarily disables action buttons. After a timeout, reconnect before retrying. Compatibility has not been verified across the full LG TV range.

