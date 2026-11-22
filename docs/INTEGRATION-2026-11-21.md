# Elsepin review integration — 21 November 2026

Integration branch: `codex/integration-20261121`, based on `6178ba1`.
No release publication or repository visibility changes are authorized in this pass.

## Source inventory

All incoming backups remain untouched. The integration is a new Git branch in
`C:/Users/naith/Documents/GitHub/Elsepin`; the original commit remains available.
The external parent is
`C:/Users/naith/Desktop/ipa/My Projects (N3mo Studio)/Elsepin-fixes-20261120-223038`.

| Copy | Verified role |
| --- | --- |
| `00-original-backup` | Clean `6178ba1` baseline |
| `02-backup-before-fixes` | Baseline plus LocationEngine and CURRENT-WORK edits |
| `01-working-copy` | Twelve uncommitted changed files against the same baseline |
| `01-working-copy/.build/ci-snapshot` | `d3fed18`; eleven changed source/test/script files match the working copy byte for byte |
| `backup-original` | Eight changed tracked files; historical intermediate snapshot |
| `02-review-pack` | Historical pre-fix pack, not an integration source |

The CI clone omits documentation, website material and other files; it is not a
complete replacement for the original repository. Its public repository is
`HonorableLordFishy/elsepin-ci-validation`. The primary
`HonorableLordFishy/Elsepin` repository was verified private before integration.
No public-source push is part of this integration.

Local evidence: `.build/integration-20261121/source-catalog.json` and
`third-party.patch`. This preserves provenance without overwriting the supplied
copies or mixing old source packs into the integration.

## Review decisions

- Retain update comparison fixes, diagnostic records, route overlay support and
  useful regression coverage. Preserve all prior changelog entries and features.
- Correct the search action that was relabeled as adding a destination while its
  callback still opened Save Pin. Keep saving pins as a separate action.
- Fit the route when choosing a search area; make long-route sampling explicit
  and retain bounded requests and manual area search.
- Replace the Files test's immediate Open-button query with bounded handling of
  both direct selection and delayed Open. Preserve import/apply/relaunch checks.
  Stage the current test's actual exported bytes, not an arbitrary old export.
- A failed fresh TCP probe must not discard or preempt a usable existing DVT
  command connection. Reuse only matching connection/credential context and
  report the actual native command result. A remembered location or existing
  handle alone is not evidence of a successful write or clear.

## Validation boundary

Windows has no usable local Xcode simulator (`xcrun` is unavailable). Native
compilation and UI checks require GitHub's Mac runner. Simulator adapters use
disposable data and cannot verify LocalDevVPN, physical movement, other apps'
locations, Wi-Fi handoff, battery, or sideloaded entitlements.

Incoming CI claims are not substituted for integration evidence.

## Integration evidence

- Private run `44984720688`, source `10c79ba`: 640 Swift regressions passed;
  production app and extension compiled; 27 of 28 simulator scenarios passed.
  The route-search test found an inherited map accessibility label masking the
  full-screen button's own label. Fixed in `0b18713`. The Files scenario passed
  on retry after a simulator DocumentsApp termination error.
- Run `44985294242`, source `580f6e6`: 644 Swift regressions passed, including
  version/build metadata cases; production app and extension compiled. Its route
  UI test still encountered the accessibility label fixed in the next revision.
- Run `44985879023`, source `0b18713`: settings export, file selection, selective
  import, relaunch, repeat import and paste passed again. Route search reached
  the two distinct place actions; the test expected a Cancel button, but the
  native popover uses outside-tap dismissal. The test now checks that dismissal
  and unchanged travel. Native parent/child duplicate accessibility nodes are
  resolved to a single visible action. No production cancellation behavior was
  removed to make the test pass.
- Inspected screenshots: narrow/max-text route details and reachable Pause/Stop;
  dark accessibility fallback and Resume/Stop; repeated backup import with no
  duplicate changes; route-search choice with separate Add stop and Save pin.
  Broad-run evidence contains one system `_UIGravityWellEffectAnchorView` warning;
  focused review evidence has no runtime warnings. No visible layout failure was
  demonstrated by that warning; it is not claimed resolved.
- Anonymous stable-release metadata returned HTTP 200 with version 2.6.1, build
  89. Same-version installed builds 91 and 93 must not offer that older build.
  Higher known build numbers are handled by portable regression tests. Release
  metadata was read only, not changed.

- Run `44986552814`, source `4963db9`: the complete route-search choice, native
  cancellation, confirmation, added planner stop and non-resuming exit passed.
- Final run `44986984508`, source `3a9b214`: 644 Swift regressions and the expanded
  route-search UI scenario passed without retries or runtime warnings. It also
  cancels the final edit confirmation, opens/closes a fresh search, verifies no
  old choice reappears, then completes the confirmed edit. Inspected the final
  planner screenshot showing the added stop and existing route. Production
  source changes since the broad run are bounded by these focused checks; this
  is not a claim that every scenario ran again on the final revision.

IPA job `44987373797` successfully packaged exact source
`3a9b2140ef0abb205a043b27a9b7b5267958053a`. The build passed 644 Swift tests,
27 package/resource tests, 20 Companion tests (one Windows-only case skipped),
and 106 cloud helper tests. Production app and extension compiled without
compiler warnings and both contain version 2.6.1, build 93, linked SDK 27.1.
Downloaded the original artifact and verified integrity, artifact identity,
bundle identities, both versions, device binaries, 13 icon choices and resources.
Copied the verified IPA to the usual delivery folder, verified that copy, then
removed only the previous Elsepin build 91 there. Other projects and backups are
untouched. No release was published and no repository visibility was changed.
Primary Elsepin remains private; the external CI repository remains public.

Raw evidence is under the ignored `.build/integration-20261121/` directory.
Physical checks still needed:
disconnect Wi-Fi during a working LocalDevVPN session, send a genuinely new
location, then Stop/clear and confirm the result in another app; reconnect after
an actual command failure. Simulator fixtures cannot establish those outcomes.
