# GPX and recovery integration validation — 18 November 2026

Production source: `15b5bfc` on `codex/gpx-recovery-validation-20261118`.
Validation-only fixture follow-ups: `38f3ae3` and `25f7a3c` (no production code change).

The DeepSeek ZIP was reviewed and corrected in an isolated full worktree before local integration. Existing production location/FFI code, map gestures, saved-route speed behavior, settings backup file/paste paths, identifiers and historical changelog were preserved. No IPA packaging, release, visibility change or paid billing was requested or performed.

## Changes

- GPX reads use security-scoped access and a bounded detached worker with cancellation forwarded from its owner. Request identities, cancellation and workspace generation reject stale successes and errors. Review is separate from applying to the planner; cancellation and failure leave the editor intact. Root handoff waits for review dismissal before presenting the planner.
- XML parsing checks GPX roots, namespaces and parent paths, ignores extension coordinates, validates coordinates and blocks declarations/entities. Accepts GPX 1.0/1.1, tracks, routes, waypoints, and multiple paths. Users select a path and either one separated segment or explicitly join gaps. Limits are 32 MiB and 100,000 points, matching the saved-trip point ceiling. Export uses locale-independent decimals.
- Recovery preserves distinct unreadable originals before subsequent saves, including saves without a preceding load. Explicit discard clears an unreadable live original to prevent reappearance, but keeps readable live data. Raw recovery copies can be exported; unreadable bytes are not claimed to be automatically repairable. Recovery is visible in Library and Import & export. Recents retention preserves bad originals before removing live data; explicit privacy/history clearing removes associated copies.
- Diagnostic monitors only run while developer logging is enabled. Background recording remains supported; generation checks reject old callbacks after stop/restart. Remote-check idle refreshes avoid redundant notification cleanup; startup and active teardown remain intact.

## Completed evidence

Run https://github.com/HonorableLordFishy/Elsepin/actions/runs/44386371938 at `15b5bfc` passed:
- All 625 Swift regression tests, zero failures.
- All 27 resource/script tests. Same suite also passed locally using the repository's bundled Python.
- Companion/CloudFindMy helper test job.
- Production Release app and extension compilation; no compiler warnings found in the saved device log. Test-only marker exclusion check passed. No IPA was generated.
- Five simulator tests on iPhone 17 / iOS 27.2: GPX review apply/cancel; invalid import/retry and pending cancellation; saved-place recovery discard followed by reload; dark-sheet controls; actual RootView import handing off to the production planner.
- XCTest summary: five passed, zero failures, zero skips, zero runtime warnings, one execution of each case. The host log includes debugger-version lookup notices and SpringBoard diagnostic noise; no application assertion/crash was reported.

Screenshots inspected: light import review, dark import review, invalid-file retry, saved-place recovery and the actual planner/map after importing. Recovery and import use existing native themed surfaces; controls are reachable and text is not clipped in these captures.

The initially named large-text test did NOT actually propagate its large-text/narrow settings into the sheet. Screenshot inspection caught this. The fixture was updated to apply accessibility5 and 320-point width inside the presented review. Run `44387926237` exposed a test-only compile error from attempting to override read-only Reduce Motion/Transparency environment values. Commit `25f7a3c` removes those invalid overrides; those two system accessibility settings are not claimed as exercised in this follow-up. Run `44392831262` reruns the narrow/largest-text/dark check; see final outcome below.

Earlier run `44385804563` passed Swift/native compilation but was cancelled before UI completion after a fixture check incorrectly assumed the planner would not resample imported coordinates. The corrected test checks endpoints and GPX provenance. No failed assertion was hidden or converted to success.

Evidence files are in `.build/review-validation/` in the main checkout, outside source control. The normal checkout is merged only after required simulator checks and screenshot inspection.

## Limits

This is focused regression coverage, not a claim that every app feature was retested. No physical-phone pairing, location injection, Stop/clear, signed-widget behavior, battery/thermal measurement or third-party Files-provider access was verified here. Native GPX file selection and recovery export through a real cloud Files provider remain phone checks; parsing/export byte preservation and native review/confirmation UI have separate evidence. UI failure tests use malformed disposable GPX data; slow-import timing is injected only in the simulator fixture, not production. No simulated successful connection is presented as physical spoofing proof.


## Final layout follow-up

Run https://github.com/HonorableLordFishy/Elsepin/actions/runs/44392831262 at `25f7a3c` passed the corrected 320-point, accessibility5, dark import test: one pass, zero failures/skips/runtime warnings, one execution. Screenshot inspected: text is genuinely enlarged; list scrolls and both Cancel and Use this path remain reachable. The native picker summary uses an ellipsis at this extreme size; the picker retains full option labels. Reduce Motion/Transparency were not changed by this fixture. All 625 Swift tests also passed again. Only validation fixture/workflow files differ from the production source compiled in run 44386371938, so that production compilation evidence remains applicable.

Together the runs cover five distinct native UI scenarios, with the accessibility scenario rerun under corrected constraints. This is not six different scenarios. No native UI assertion failed; the failed intermediate accessibility run was a fixture compile failure, corrected before final validation.
