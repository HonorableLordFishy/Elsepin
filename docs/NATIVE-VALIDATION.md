# Native validation without IPA packaging

`Validate Elsepin (no IPA)` is separate from `Build Elsepin IPA`. It runs Swift
regressions, resource checks, a Release build of the production app and extension,
and focused XCUITests. It uploads logs, xcresult evidence and screenshots only.
It does not archive, package, sign for distribution, publish a release or deploy.
Changes on `codex/pins-search-69` to the scoped source/workflow paths trigger it;
manual dispatch is available on that branch. Its default `all` focus runs both jobs.
The `search` focus reruns the four search cases; `home` runs the solid/glass idle
tray cases; `pins` runs the live zoom/rotation visibility case; `routes` runs the
new Usual speeds/saved-itinerary case. These focused runs
compile the isolated simulator app and skip the production job,
so already validated production code need not be rebuilt for fixture-only checks.

## Build 87 route check - blocked by simulator startup

Production build `43790846355` passed 725 checks (one Windows-only case skipped),
compiled the app/extension cleanly and produced a verified IPA. The new isolated
route case compiled in both simulator attempts but has no passing runtime result.
Run `43790842470` was cancelled after prolonged boot/app-readiness waits; fresh
run `43792787491` timed out in `simctl bootstatus` after 180 seconds, before launch.
No new screenshots or interaction success are claimed. Logs and partial artifacts
are in `.build/artifacts/build87/`; physical speed/recalculation confirmation remains.

The test injects deterministic directions into the actual planner to check new
defaults, saved settings, retained places/waits, Keep path, failure restore and
cancellation. Those rapid model checks finish before its map is mounted. UI steps
then exercise leg movement and whole-itinerary recalculation. It cannot prove
real Apple routing, pairing or spoofing. Boot/install and XCTest timeouts now
bound runner failures. Production location-engine code remains unchanged.

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
unavailable. Search results are deterministic; responses released after cancellation deliberately
exercise the view's stale-response guard. Map tiles still come from MapKit.
The production search request has a small value-response boundary and unchanged
MapKit cancellation/deadline behavior. Its completer implementation was moved
unchanged into its own file so it can be excluded from this simulator target.

## UI coverage and evidence

The fixture constrains the root Map/Library content to 320pt width, with normal or
maximum accessibility text and light/dark appearances. System-presented search
sheets use the simulator's native presentation width. The fallback test uses the native
Settings app to enable Reduce Motion, Reduce Transparency and Increase Contrast,
then restores them. Tests exercise moving,
paused, connecting and failed states, long route/Library names, empty Library,
route-place search submit/retry, cancellation and dismissal/foreground interruption.
Screenshots and accessibility trees are attached to the xcresult and exported
with `xcresulttool`. Actual inspection/findings belong in the run receipt below;
a test plan or fixture is not a passed check.

The `map-pins` scenario runs the real MapHomeView with disposable saved pins and
a synthetic moving route. Its simulator-only probe observes actual visible-pin
changes from continuous camera callbacks. The UI test pinches across the one-mile
cutoff in both directions, checks those live transitions, then rotates a map near
the cutoff and compares ground width. The probe and camera-position controls are
excluded from production compilation. This measures map behavior, not spoofing.

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

### Live pin visibility - 15 November 2026

Production code at `2a1b281` passed 580 Swift tests (six new visibility/cadence
cases), 22 resource checks and Release app/extension compilation in
[run 43763782418](https://github.com/N3moStudio/Elsepin/actions/runs/43763782418).
Its 13 existing UI cases passed. The new case initially failed because test
controls were behind the route tray; screenshots exposed the misplaced input.
A follow-up (`43766542813`) exposed a pinch finger hitting Expand. Neither was
an app crash. The fixture now observes only its own overlay, asserts its gesture
rectangle clears the tray, and passes the native two-finger input to MapKit.

[Focused run 43767731864](https://github.com/N3moStudio/Elsepin/actions/runs/43767731864)
at `c70d265` passed with zero runtime warnings on iPhone SE (3rd generation), iOS
27.0. Inspected screenshots/AX snapshots show 0.282 mi across with one pin,
1.310 mi with none, and 0.900 mi with one after a 45-degree rotation. Live-callback
hide/show counters increased during the two pinches; rotation preserved ground
width within the asserted tolerance, and Pause/Stop remained reachable. This
brings distinct passing UI coverage to 14 across these runs; fixture-only changes
after `2a1b281` are excluded from the production compilation condition.

Production compilation had no compiler warnings/errors. The simulator build
reported a non-blocking missing-AppIntents metadata-extraction warning for the
test bundle. Full logs/screenshots remain under `.build/artifacts/pin-visibility/`.
No IPA was packaged. Real-device spoofing, battery and the pin editor's gestures
are not established by this check; its shared viewport code compiled successfully.

Production validation at `c80dfdbf9d6814a6a0573c681453a1464d35affb`,
[run 43666953418](https://github.com/N3moStudio/Elsepin/actions/runs/43666953418):
567 Swift tests, including all nine `RouteFlowPresentationTests`, and 22 Python
resource/helper tests passed. The Release app and embedded activity extension
compiled with zero compiler errors or warnings. All 11 simulator UI cases passed
with zero runtime warnings. This validation-only run created no IPA.

The two additional idle-screen spacing cases passed at `a317623` in
[run 43667656079](https://github.com/N3moStudio/Elsepin/actions/runs/43667656079),
also without runtime warnings. This is 13 distinct UI cases across the full suite
and the idle follow-up; the only intervening changes were fixture/tests/workflow
and the app/extension build number. Screenshots from both runs were inspected.

An earlier simulator run (`43658708902`) failed before any test executed: the XCTest
runner exited during bootstrapping (`XCTWaiter(StallHandling)`). This is not an
app-test failure or a UI pass. Earlier runs did execute the UI suite and supplied
the screenshots used for corrections below. The portrait iPhone SE (3rd generation)
/ iOS 27.0 run `43661802428` then passed all 11 UI tests with zero runtime warnings.
Screenshot inspection found an additional Stop/tab-bar overlap. A stronger
assertion confirmed the inset outside TabView did not reach the map. Insets now
live inside each tab, and test cleanup restores system accessibility settings
even after an assertion fails. Run `43664601901` passed 10/11 tests and reported
zero runtime warnings. The remaining fake slow-search timer expired while XCTest
was locating Cancel; the adapter now releases stale responses only after the view
cancels them. Production search behavior is unchanged.

That run's screenshot inspection also found the bottom inset was counted twice,
leaving a 10pt route-details viewport at maximum text. Source `c80dfdb` reserves
it once and asserts at least 44pt for the scrollable details. Full validation
`43666953418` passed; the fixture-only search rerun `43666772248` passed all four
search cases without runtime warnings. The owner's build 83 phone screenshot
also demonstrated the excessive idle-tray gap. Build 84 includes the correction.

Screenshot review confirmed that the idle tray has a 30pt gap above navigation
in both solid and glass modes, maximum-text route details have a usable scrolling
viewport, and movement/clear controls remain outside that scroll view and above
navigation. Long Library names wrap and scroll. Search submission, retry, cancelled
late results, and background interruption retain the correct current query/result.
Connecting and failed states retain their distinct status and recovery actions.

Demonstrated issues corrected during validation:

- Debug compilation exposed an oversized RootView expression; typed callbacks
  and a stable Map subview preserve state while bounding type-checking work.
- The isolated app entry point exposed a shared GPX notification declaration;
  it now lives in a support file available to both builds.
- Maximum text squeezed long Library names beside decorative icons and actions.
  Accessibility layouts give names the full row width and move actions below.
- A solid navigation bar expanded to cover route controls at maximum text size.
  Its constrained controls now support Large Content Viewer; content text remains
  scalable. This follows Apple's [large-content-viewer guidance](https://developer.apple.com/documentation/swiftui/view/accessibilityshowslargecontentviewer()).
- The status/header area crowded the route controls at maximum text size. Concise
  visible status retains the full accessibility label, and route help moves into
  the scrollable details.
- Environment reads inside the brand Shape caused runtime warnings. The enclosing
  View now resolves the environment and passes an explicit design to the Shape.
- Alert dismissal no longer redundantly publishes a cleared error during a view
  update. The subsequent simulator run reported no runtime warnings.
- Resume uses its full-width title at accessibility sizes; decorative action icons
  no longer force the word onto two lines. Long names use leading alignment.
- Solid tab-bar visibility is applied inside each tab, eliminating duplicate
  navigation. Route controls respect the bottom safe-area inset while the map
  continues drawing underneath it; only route details scroll when space is tight.

Test harness corrections include real system permission setup, supported
device/runtime selection, native Settings selectors, and search fixture results
that do not accidentally collide with a saved pin. None changes production
connection acceptance or makes simulated results proof of real-device spoofing.

## Short physical-iPhone check for build 84

1. Confirm pairing/code delivery, then connect with LocalDevVPN enabled.
2. Start a short local route. Check movement in another map, then Pause/Resume.
3. Interrupt the VPN, background/reopen Elsepin, reconnect and retry. Confirm the
   route is retained and the UI does not falsely claim confirmed movement.
4. With the tunnel available, Stop/clear and verify actual GPS returns in another
   map and the session UI ends. A failed clear must not be presented as success.

The owner subsequently requested IPA delivery. Build 83 was an interim artifact;
build 84 from `a317623` supersedes it and includes the bottom-spacing correction.
Manual packaging run `43667658944` passed 711 tests with one Windows-only skip,
compiled the app/extension without compiler warnings/errors, and produced the
inspected device IPA. Only the previous Elsepin IPA was replaced in the delivery
folder. No release was published. Simulator success is not real-device spoofing proof.
