# Native validation without IPA packaging

`Validate Elsepin (no IPA)` is separate from `Build Elsepin IPA`. It runs Swift
regressions, resource checks, a Release build of the production app and extension,
and focused XCUITests. It uploads logs, xcresult evidence and screenshots only.
It does not archive, package, sign for distribution, publish a release or deploy.
Changes on `codex/pins-search-69` to the scoped source/workflow paths trigger it;
manual dispatch is available on that branch. Its default `all` focus runs both jobs.
The `search` focus reruns the four search cases; `home` runs the solid/glass idle
tray cases; `pins` runs the live zoom/rotation visibility case; `routes` runs the
three Usual speeds/saved-itinerary cases. The `backups` focus exercises settings
file export, selective import, cancellation, relaunch persistence and paste, plus the
Swift backup/import-rule tests. These focused runs
compile the isolated simulator app and skip the production job,
so already validated production code need not be rebuilt for fixture-only checks.
`validate_device=true` also runs the full production job for a focused dispatch.
The optional `simulator_runner=macos-26` uses the stable SDK 26 image when the
preview Xcode 27 simulator cannot start. Production compilation remains Xcode 27.
`simulator_runtime` can request an exact installed iOS version for a focused
comparison. An unavailable requested version fails rather than silently choosing
another runtime. The default still selects the newest general-purpose runtime.

## Build 87 route checks - simulator repair

The standalone route fixture was missing the `TripLibrary` environment object.
It now injects the same library and embedded-editor environment as the normal
route sheet. The runner chooses the newest supported general-purpose iPhone
runtime; the successful run used iPhone 17 / iOS 27.2 with SDK 27.1. Compile before
boot to avoid competing for memory, then require bounded boot readiness before UI
testing. Failed/incomplete result bundles no longer break evidence collection.

Run `43799395957` at `c96fc4b` passed all three interactive cases, zero skips,
zero runtime warnings, in 266 seconds of test execution. The initial expanded run
`43797161250` passed the new-route case but exposed two automation issues: a
combined accessibility label and a row underneath the sticky Show route action.
Tests now read the slider's accessible value and scroll controls fully above that
action before tapping. Screenshot review also identified an extra Cancel button
in the standalone fixture. Final run `43800631629` at `7bd442d` matched the normal
sheet environment and again passed all three cases, zero skips/runtime warnings.
Its screenshots were inspected: native Back/Done, selected modes and reopened
speeds render correctly, with the duplicate Cancel removed from the fixture.

Coverage uses the actual settings, leg editor, planner and TripLibrary writes:

- Set Usual walking speed to 6 mph through its slider; create both drawn and
  planned routes; save and load them from disk; retain an existing trip's 1.4 mph.
- Switch a saved leg to Drive and observe its 85 mph usual speed. Save custom
  Drive/E-bike leg speeds (39/12 mph in the final run), read a fresh TripLibrary
  from disk and reopen both leg editors to verify those values.
- Recalculate with E-bike, observe its 31 mph preset, choose a custom speed
  (21 mph in the passing run), save and reopen. Assert saved identity/name,
  endpoint coordinates/names, stop IDs/order/names/90- and 30-second waits,
  smoothing, arrival choice and all three leg modes/speeds.

Evidence and inspected screenshots: `.build/artifacts/build87/simulator-repair/`.
The local resource suite passed 22 tests. Production app code and build 87 IPA
are unchanged. Directions remain deterministic test responses, not real Apple
route calculations or evidence of device spoofing.

### Earlier blocked attempts

Production build `43790846355` passed 725 checks (one Windows-only case skipped),
compiled the app/extension cleanly and produced a verified IPA. The initial route
case compiled in both early simulator attempts, but neither produced a passing runtime result.
Run `43790842470` was cancelled after prolonged boot/app-readiness waits; fresh
run `43792787491` timed out in `simctl bootstatus` after 180 seconds, before launch.
Those attempts supplied no screenshots or interaction proof. Their logs and partial
artifacts remain in `.build/artifacts/build87/`; the successful follow-up is above.

The test injects deterministic directions into the actual planner to check new
defaults, saved settings, retained places/waits, Keep path, failure restore and
cancellation. Those rapid model checks finish before its map is mounted. UI steps
then exercise leg movement and whole-itinerary recalculation. It cannot prove
real Apple routing, pairing or spoofing. Boot/install and XCTest timeouts now
bound runner failures. Production location-engine code remains unchanged.

## Settings file import repair (included in test build 88)

The owner confirmed that Files opens on the phone but its files cannot be
selected. Source `295a0b9` replaces the custom picker sheet/delegate with SwiftUI's
native `fileImporter`, allows file items independently of provider JSON/data
classification, and retains security-scoped access through the coordinated read.
Completion and cancellation have explicit owners. The same bounded backup
validator and selected-only review still protect both file and paste imports.
Paste backup text and the manual JSON help link remain available.

Production validation in run `43807961473` passed all 581 Swift tests and 22
resource tests and compiled the app/extension with no compiler errors/warnings.
No IPA was created. The focused backup-rule selection also passed 58 cases
(a subset of the 581, not additional distinct coverage).

The initial UI attempts did not complete import. Their screenshots exposed
automation navigating before Files loaded and an extra fixture modal shell.
After correcting those, simulator logs specifically reported
`FILocalAppContainerNode<Elsepin>` enumeration failing with `nilError` despite
a valid 830-byte exported JSON existing in Documents. The iOS 27 history Back
button also returns to Recents, not necessarily the parent folder.

The fixture now matches Settings' pushed navigation. For file import validation,
`scripts/stage_validation_backup.py` copies the actual UI-exported JSON unchanged
into the disposable simulator's general Files storage, verifies its bytes, and
writes an internal receipt. It does not manufacture a backup, inject an import
result, or bypass the native picker, review, confirmation or persistence. The
test uses Browse / On My iPhone to select that file, like a downloaded backup.
Only the validation app and owned simulator are accessed; the simulator is
deleted afterward. Paste validation reads the same real export onto the
disposable clipboard and taps the production Paste button.

Run `43809800873` failed before import because its simulator setup could not
resolve Files' shared storage. Run `43812196014` initialized Files first and
resolved the exact LocalStorage group from owned simulator metadata. The real
exported file was selectable, opened review, and cancellation preserved settings.
Applying the selected settings then exposed a fixture-only missing RoutePlanner
environment object (crash at BackupImportReviewView.swift:213). Production RootView
already supplies that object above navigation; the fixture now does too at
`b5f7640`. Subsequent startup attempts did not reach app interaction:
`43813978799` timed out in bootstatus; `43815407351` booted but stalled taking a
preliminary SpringBoard screenshot; `43816735672` exposed that this runner does
not contain the usual Simulator.app GUI path. The separate GUI launch and boot
screenshot were removed. XCTest still must launch the app, exercise controls and
capture its interaction screenshots. Startup and cleanup have bounded durations.
Run `43817929821` again timed out in bootstatus before app launch. Stable SDK 26
run `43819584379` compiled the app/UI target, then found an existing contrast-test
expression too complex for that compiler. Splitting its arithmetic into typed
steps preserves the calculation and all assertions. Run `43820255219` at
`976c09f` passed compilation and the expanded 66 backup/contrast rules and started
the simulator. It selected the app-container copy (which now enumerated but did
not deliver selection), so it did not reach review. The test now always navigates
to Locations / On My iPhone and asserts that destination before selecting the
staged export. Run `43822380158` reached that exact location with the real export
visible, but its title assertion expected a button instead of iOS 26's static
text. The query now accepts either native representation. Run `43824300829` at
`5a5df35` passed compilation and 66 rules but stopped earlier, at a blank native
export sheet. Its screenshot and system log show Files' LocalStorage indexing
timing out. `25b5491` adds a readiness check through the actual Files app, requiring
the disposable app folder to enumerate before opening the export sheet. Run
`43825953906` passed that prerequisite and exported the actual settings file.
Its native picker displayed the staged JSON as enabled, but selection failed in
the system's bookmark resolution with FileProvider error -1005 (nonexistent item
identifier). The staged file existed and its bytes matched the real UI export;
the app did not receive it for review. This is not a completed import UI pass.
Run `43827975555` at `fdde2ba` compiled and booted the available iOS 27.1 image
(iPhone Duo, not the general iPhone 17 used in the successful route checks),
but its Files app could not launch: FBSApplicationLibrary returned nil for
`com.apple.DocumentsApp`; simctl also reported no such file/directory. It supplied
no backup interaction evidence. The complete file/apply/relaunch/paste test
remains enabled and **unverified** after the fixture correction. The relevant
screenshots and provider/startup logs were inspected; do not treat these failed
runs as production app failures or silently skip their assertions. Completing
this check needs a working Files runtime or phone acceptance of a newly built IPA.
Source visibility was restored to private and verified on 16 November. These
validation runs created no IPA or release. The seven runtime-selector Python
tests passed locally.
Evidence is retained in
`.build/artifacts/build87/backup-validation/`. Build 87 predates this file-import
repair. On 16 November the owner requested build 88 for phone testing; run
`43903180690` packaged the repair with Paste retained. Its native build, 727
automated checks (plus one platform skip) and package inspection passed, and its
IPA replaced build 87. This does not change the incomplete simulator interaction
result above. See BUILD-HISTORY.md and `.build/artifacts/build88/`.

## Production and simulator boundaries

`project.yml` remains the device build source of truth. The vendor idevice archive
is device-only. `scripts/make_validation_project.py` derives an ignored
`ElsepinValidation.xcodeproj` with a separate app identifier, no App Group
entitlement, and simulator-only supported platforms. It excludes the production
app entry point, three FFI-dependent engine/pairing files and search providers.
The original production location implementation is not edited or linked into
this test executable. Public engine error/cancellation declarations are copied
from the original source during generation, avoiding a second error contract.

On SDK 26 only, `validation_sdk_compatibility.py` generates guarded copies using
the app's existing pre-iOS-27 resource-usage and MetricKit fallback behavior. It
does not alter production files, backup controls, import/export readers, data
models or persistence. SDK 27 validation continues compiling the original two
files. This fallback cannot validate iOS 27 resource-pressure or MetricManager
diagnostics. Generated copies are ignored build products, not IPA inputs.

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
