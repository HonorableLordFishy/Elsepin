# Elsepin

Private development repository for Elsepin, the continuation of Shift.

**Public release: 2.6.0 (59). Current test build: 2.6.1 (86).** The 2.6.1 release is an unpublished draft awaiting final iPhone acceptance. Prism Jumpgate remains the primary icon; development has eight themes and thirteen icon choices.

Bloom is the development default. Appearance offers Solid or Liquid Glass and compact rounded typography with accessibility support. The website is in `website/`; the public introduction is maintained in `docs/public/README.md`. See [changes since 2.6.0](docs/CHANGES-SINCE-2.6.0.md) for the complete pending update.

## Start here

- [Product Atlas / brand and compatibility map](docs/BRAND-MAP.md)
- [Feature map](docs/APP-MAP.md)
- [Change Ledger](docs/CHANGE-LEDGER.md)
- [Complete changelog](CHANGELOG.md) and [build history](docs/BUILD-HISTORY.md)
- [Setup guide](SETUP.md)
- [Build instructions](docs/BUILDING.md)
- [Website source and publishing](website/README.md)
- [Identity brief and outstanding name checks](docs/ELSEPIN-IDENTITY.md)

## Distribution boundaries

Approved public downloads and help belong in [Elsepin-Releases](https://github.com/N3moStudio/Elsepin-Releases). This private repository contains implementation and validation work. No new IPA is published merely because source changes are pushed. The paid Veypax product uses its own private repository, versioning and plan policies.

## Stop and reconnect

If Elsepin can’t clear the location, connect to Wi-Fi, reconnect LocalDevVPN, and try again. Connecting to another device’s Wi-Fi hotspot can also work. Closing or force-quitting Elsepin doesn’t confirm that it cleared. Check the location in another app too.

## Licenses and provenance

Elsepin continues Shift and includes code derived from Locus and the idevice project. Inherited and previously MIT-licensed work retains its [MIT license](LICENSE). Only expressly listed new original additions use the separate [rights notice](NEW-ADDITIONS-LICENSE.md). Third-party notices remain packaged in the app. This is not a claim that inherited code is proprietary or that prior permissions have been revoked.

## Validation

Use **Actions → Build Elsepin IPA → Run workflow** to build an IPA. Tests and
resource checks run first; the only downloadable artifact is the IPA. Running
this workflow does not publish a release.

Public documentation is maintained here and exported with
`python3 scripts/export_public_docs.py /path/to/Elsepin-Releases`. Add `--check`
to verify the public copy matches. The export includes only the introduction,
setup guide, complete changelog, release summary/draft and public build register, never app source.

Shared-rule tests can run with `swift test`; native SwiftUI and extension validation require Xcode on a Mac. `scripts/check_app_identity.py`, `scripts/check_appearance.py` and `scripts/package_helpers.py --check` protect install identity, icon resources and source-only helper packages. See the Change Ledger for the exact tested revision and remaining device checks.
