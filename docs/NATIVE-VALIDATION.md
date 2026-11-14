# Native validation without IPA packaging

`Validate Elsepin (no IPA)` is separate from `Build Elsepin IPA`. It runs Swift
regressions, resource checks, a Release build of the production app and extension,
and focused XCUITests. It uploads logs, xcresult evidence and screenshots only.
It does not archive, package, sign for distribution, publish a release or deploy.
Changes on `codex/pins-search-69` to the scoped source/workflow paths trigger it;
the workflow also declares manual dispatch for use once available on the default branch.

## Production and simulator boundaries

`project.yml` remains the device build source of truth. The vendor idevice archive
is device-only. `scripts/make_validation_project.py` derives an ignored
`ElsepinValidation.xcodeproj` with a separate app identifier, no App Group
entitlement, and simulator-only supported platforms. It excludes the production
app entry point, three FFI-dependent engine/pairing files and search providers.
The original production location implementation is not edited or linked into
this test executable. Public engine error/cancellation declarations are copied
from the original source during generation, avoiding a second error contract.

Only `Validation/Support` supplies the replacement entry point and adapters.
Compile guards reject device compilation or compilation without
`ELSEPIN_UI_TESTING`. Launch requires `--elsepin-ui-test` and the validation bundle
identifier. The banner says **SIMULATOR TEST DATA**. Each launch clears that
app's disposable defaults/library sandbox; the production bundle, personal
library, pairing and shared widget data are not accessed or overwritten.

Connection/session acceptance is synthetic. The real `SpoofSession` worker,
Pause/Resume/Stop controls and views run against that adapter, which sends no
coordinates and opens no developer tunnel. Pairing itself always reports
unavailable. Search results are deterministic; delayed responses deliberately
exercise the view's stale-response guard. Map tiles still come from MapKit.
The production search request has a small value-response boundary and unchanged
MapKit cancellation/deadline behavior. Its completer implementation was moved
unchanged into its own file so it can be excluded from this simulator target.

## UI coverage and evidence

The fixture presents the real native views at 320pt width, with normal or maximum
accessibility text and light/dark appearances. The fallback test uses the native
Settings app to enable Reduce Motion, Reduce Transparency and Increase Contrast,
then restores them. Tests exercise moving,
paused, connecting and failed states, long route/Library names, empty Library,
search submit/retry, cancellation and dismissal/foreground interruption.
Screenshots and accessibility trees are attached to the xcresult and exported
with `xcresulttool`. Actual inspection/findings belong in the run receipt below;
a test plan or fixture is not a passed check.

These results cannot prove physical-device location injection, developer pairing,
VPN transitions, signing/App Groups, provider apps, VoiceOver navigation or battery
behavior. The production app/extension compile is separate evidence from simulated
UI command acceptance.

## Impeccable doctor — 14 November 2026

Doctor reported one `route` finding: `hook-not-installed`, referring to
`.codex/hooks.json`. No auto-repair or schema/configuration defect was reported.
Its hook guidance lists web source extensions, not Swift. Installing or disabling
that repo-wide web detector would not validate these native screens (and the repo
also contains a website), so configuration is left intact. Native checks use the
current project design guidance and simulator screenshots instead.

## Run receipt

Pending: see GitHub run 43649680065 and subsequent fixes. No new IPA is requested.
