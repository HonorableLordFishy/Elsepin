# Elsepin

![Elsepin banner with a route crossing a dark map](elsepin-cover.svg)

Drop a pin, take the joystick, or build a trip from start to finish. Elsepin is an iPhone location simulator with a map for exploring, a planner for rehearsing routes, and a Library for the places you want to come back to.

**2.6.1 · Build 98** · iPhone · iOS 18 or later · Requires IPA signing

[Download Elsepin](https://github.com/N3moStudio/Elsepin-Releases/releases/latest) · [Setup guide](https://github.com/N3moStudio/Elsepin-Releases/blob/main/SETUP.md) · [Release notes](https://github.com/N3moStudio/Elsepin-Releases/releases/tag/2.6.1) · [Website](https://elsepin.onrender.com/)

## What you can do

| | |
| --- | --- |
| **Start with a pin** | Search a business or address, drop a pin, or enter coordinates. Review your pick, then tap **Teleport**. Use the joystick for manual movement once a session is active. |
| **Plan a trip at your pace** | Walk, run, cycle, e-bike or drive with a speed for each leg. Add fixed waits or simulated traffic lights, adjust arrival behavior, and optionally queue a next route from the destination. |
| **Keep the good routes** | Save and favorite pins and routes, mark named areas, revisit recent trips, and import GPX tracks, routes or waypoints for review. Back up settings and library items through Files. |
| **Make the map yours** | Set pin size and zoom visibility, switch map layers, and choose from eight themes and thirteen icons. Use Live Activities and saved-location widgets where your device and signing setup support them. |

## What’s new in build 98

- **Movement pacing.** Route and joystick movement account for elapsed time. Green lights let you pass through selected stops, and red lights add a short, simulated wait.
- **Files and route editing.** GPX imports carry the selected track’s name and points into the planner. When changing a leg’s mode, choose **Keep path** or **New directions**. Edits to a saved route retain its favorite and folder.
- **Map and session controls.** Longer pin addresses have room to wrap, along-route search covers more of the trip, and **Stop spoofing** asks for confirmation on cellular.

[Full changelog](https://github.com/N3moStudio/Elsepin-Releases/blob/main/CHANGELOG.md) · [Build history](https://github.com/N3moStudio/Elsepin-Releases/blob/main/docs/BUILD-HISTORY.md)

## Get started

1. Download the IPA and sign it with a compatible sideloading tool. Keep the bundled extension if your signing setup supports widgets or Live Activities. Back up your Library before replacing an existing installation.
2. Join Wi-Fi and connect [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044). Open Elsepin and follow **Wi-Fi → LocalDevVPN → Pairing → Check connection**.
3. Pair on a compatible iOS 27 device or import an **RPPairing** file from a computer. Once the connection check passes, select a pin or preview a route and confirm to start.

[Pairing and installation steps](https://github.com/N3moStudio/Elsepin-Releases/blob/main/SETUP.md)

## Frequently asked questions

### Which permissions does Elsepin use?

Local Network access allows pairing, the developer tunnel, and optional Windows-helper checks. Location access centers the map on your real location and supports location checks. If enabled, background location can help iOS keep a session active. Notifications support pairing and session reminders. Face ID is used when you enable app lock.

### Can I use cellular data?

Start a fresh developer connection on Wi-Fi with LocalDevVPN connected. Another device’s Wi-Fi hotspot can work. An already connected session may continue on cellular while iOS keeps it active and the connection stays usable.

### How do I get back to my real location?

Use **Stop spoofing** to request a clear. **End route** stops travel and holds your last simulated point. If clearing fails, reconnect to Wi-Fi and LocalDevVPN, then try again and check your location in another app. If you close or force-quit Elsepin, the clear remains unverified.

### Will another app show the same location?

A successful command means the developer service accepted it. Other apps can use cached or differently timed reports. Optional Find My Devices and Life360 checks have separate setup and depend on report freshness and provider access. Find My People is unsupported. [Privacy and verification limits](https://elsepin.onrender.com/privacy.html)

### Does a widget start movement?

A saved-location widget prepares a pin. You still confirm the move in Elsepin.

## Source and credits

Elsepin continues Shift, which was built from Locus, and uses the idevice project for the developer connection. Previously licensed components retain their original terms. A separate rights notice covers the original additions it lists. [Source repository](https://github.com/HonorableLordFishy/Elsepin) · [License and attribution](https://github.com/HonorableLordFishy/Elsepin/blob/main/NOTICE.md) · [New additions rights notice](https://github.com/HonorableLordFishy/Elsepin/blob/main/NEW-ADDITIONS-LICENSE.md) · [Report a problem](https://github.com/N3moStudio/Elsepin-Releases/issues)
