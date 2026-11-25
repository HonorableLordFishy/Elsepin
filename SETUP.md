# Get started with Elsepin

## Install

1. Download [Elsepin 2.6.1, Build 98](https://github.com/N3moStudio/Elsepin-Releases/releases/tag/2.6.1) for a compatible iPhone running iOS 18 or later.
2. Sign the IPA using your preferred compatible signing method, such as SideStore or FlareStore. Keep the bundled extension for widgets and Live Activities; capabilities depend on the signing setup.
3. **For 2.4.x → 2.5.x, export your library first:** the new app identity creates a separate installation. Follow [the migration checklist](docs/TESTING-2.5.md). For later updates with the same identity, use the same signing setup and install over the current app.

Export a backup before replacing an existing installation. Import a
library through **Settings → Import & export** using a file or pasted JSON.
Review individual changes before saving. See [backup import help](docs/BACKUPS.md)
and [location widgets and named areas](docs/WIDGETS-AND-AREAS.md).

## Connect

Open Elsepin’s setup checklist: **Wi-Fi → LocalDevVPN → Pairing → Check connection**.
Install and connect [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044).
The default tunnel address is `10.7.0.1`.

Allow **Local Network** access for pairing and the developer connection. **Location**
access centers the map and supports location checks. If enabled, background
location can help keep a session active. Optional notifications support pairing
alerts and session reminders. If you enable app lock, Elsepin uses Face ID or
your device passcode.

**On-device pairing, where supported (iOS 27):**

1. Open **Settings → Connection → Pair on this iPhone**, then start pairing.
2. Allow the requested Local Network access. Follow Elsepin’s prompts into iPhone **Settings → Privacy & Security → Developer Mode → Pair with Host**.
3. Choose **Elsepin**. Enter your iPhone passcode when iOS requests it, then the separate six-digit pairing code shown by Elsepin.
4. Return to Elsepin and complete the connection check.

**Import an existing pairing:** generate an **RPPairing** file using
[idevice_pair](https://github.com/jkcoxson/idevice_pair/releases) on your computer,
then import, share, or paste it into Elsepin. A SideStore `.mobiledevicepairing`
file is a different format. Keep pairing files private.

## Move

Search or select a location, review the pin, then tap **Teleport**. For a journey,
choose **Show route**, review it, then **Start route**. The joystick becomes
available after a session is established.

- **Pause route** holds the current point.
- Set stop waits with Hours / Minutes / Seconds, from **0** (pass through) to **24 hours**. For example, choose **15 seconds** for a short stop.
- Turn on **Simulate traffic light** at selected stops to pass through on green and wait briefly on red.
- Choose **Settings → Usual speeds → Speed units** for mph or km/h. Changing units does not change a trip’s actual speed.
- **End route** stops travel while retaining the held point.
- **Stop spoofing** requests clearing the simulated location. A failed clear is not a successful reset; reconnect and retry.

Use Wi-Fi and LocalDevVPN to establish a fresh developer connection. Another
device’s Wi-Fi hotspot can also work. An established session may continue on
cellular while iOS lets Elsepin run and the connection remains usable. On
cellular, **Stop spoofing** asks for confirmation. If clearing fails, reconnect
Wi-Fi and LocalDevVPN, retry Stop, and check the location in another app. Closing
or force-quitting Elsepin leaves the clear unverified.

## Optional Find My checks

Existing builds offer **Find My & Life360** under advanced settings, with a [cloud helper](CloudFindMy/RENDER-SETUP.txt)
or [Windows helper](Companion/README.txt). Use your own service and account;
one helper is active at a time. The Windows computer must remain awake and
reachable on the same Wi-Fi. A cloud helper can work while that computer is off.

**Connection checks (3–15 seconds)** control Elsepin’s own connection evidence.
Find My reports are fetched separately, around once per minute; faster Elsepin
checks cannot make Apple produce a newer report. Devices is not Find My People.

Helper guides retain their minimum compatible version, 2.3.2. Life360 cloud
support requires an up-to-date helper. These experiments are optional, unofficial
and depend on provider availability. See [privacy and limits](docs/PRIVACY.md).
