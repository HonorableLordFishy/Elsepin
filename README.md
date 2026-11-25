# Elsepin

![Elsepin banner with a route crossing a dark map](docs/public/elsepin-cover.svg)

Elsepin is an iPhone location simulator. Drop a pin to test a place, steer with the joystick, or play a route with your own stops, speeds and arrival behavior. Keep the places and routes you want to use again in your Library.

**2.6.1 · Build 98** · iPhone · iOS 18 or later · Requires IPA signing

[Download Elsepin](https://github.com/N3moStudio/Elsepin-Releases/releases/latest) · [Setup](SETUP.md) · [Release notes](docs/releases/2.6.1.md) · [Website](https://elsepin.onrender.com/)

## From one pin to a whole trip

- **Pick a place.** Search a business or address, enter coordinates, or drop a pin on the map. Review your selection before you tap **Teleport**. With a session active, you can move manually with the joystick.
- **Play a route.** Choose walking, running, cycling, e-bike or driving for each leg. Set a speed, add stops with fixed waits or simulated traffic lights, and choose what happens at arrival. Keep an existing path when changing modes, or ask for new directions.
- **Make a library.** Save pins, named areas and routes. Favorite items for quick access, reopen recent routes, or import GPX tracks, routes and waypoints for review. Export settings and saved items as a backup.
- **Make it yours.** Choose from eight themes and thirteen app icons, set pin size and zoom visibility, and switch between Solid and Liquid Glass. Live Activities and saved-location widgets depend on device and signing support. A widget opens a pin for review and requires in-app confirmation.

Build 98 paces routes and joystick travel using elapsed time, keeps green-light waypoints moving, and adds short red-light waits at stops where you enable the option. It also carries the selected GPX name and geometry into the planner, makes long pin addresses easier to read, and adds a confirmation before stopping on cellular.

## Set up your iPhone

Sign and install the IPA, connect to Wi-Fi, turn on LocalDevVPN, and follow Elsepin's pairing checklist. On compatible iOS 27 devices you can pair on the phone. You can also import an RPPairing file generated on a computer. The [setup guide](SETUP.md) covers permissions, pairing files and troubleshooting.

A fresh developer connection needs Wi-Fi and LocalDevVPN. Another device's Wi-Fi hotspot can work. An established session may continue on cellular while iOS lets Elsepin run and the connection remains usable. To end location simulation, use **Stop spoofing**. If clearing fails, reconnect Wi-Fi and LocalDevVPN, retry, and check the location in another app. Closing Elsepin leaves the clear unverified.

## Build and contribute

Official downloads and user support live in the [Elsepin-Releases repository](https://github.com/N3moStudio/Elsepin-Releases). This repository contains the SwiftUI app in `Locus/`, the WidgetKit and Live Activity extension in `LocusActivity/`, portable logic and tests in `Shared/` and `Tests/`, and optional helper source in `Companion/` and `CloudFindMy/`.

- **Build with Xcode.** Use a Mac with Xcode and XcodeGen, following the [build instructions](docs/BUILDING.md). Regenerate the project from `project.yml`. The manual **Build Elsepin IPA** Actions workflow packages the app and extension.
- **Run checks.** Run `swift test` and `python3 -m unittest discover -s scripts/tests -v`. The **Validate Elsepin (no IPA)** workflow builds both targets and runs isolated simulator tests. Physical pairing, location clearing and signing support need a device.
- **Find your bearings.** Start with the [app map](docs/APP-MAP.md), [build history](docs/BUILD-HISTORY.md), [changelog](CHANGELOG.md), and [privacy notes](docs/PRIVACY.md).
- **Maintain release documentation.** Edit the [public README source](docs/public/README.md) here. Run `python3 scripts/export_public_docs.py /path/to/Elsepin-Releases` to sync the supported files, then add `--check` to verify the copy.

## Credits and licenses

Elsepin continues Shift, which was built from Locus. The developer connection uses the idevice project. Locus, Shift and other previously licensed work retain their original terms. The [MIT license](LICENSE) and [third-party notices](NOTICE.md) document those terms. The [new additions rights notice](NEW-ADDITIONS-LICENSE.md) applies to the original implementations it expressly lists.
