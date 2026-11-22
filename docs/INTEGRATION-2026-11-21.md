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

Incoming CI claims are not substituted for integration evidence. Record the
exact final source/run, test results, screenshots and IPA delivery below when
completed. Until then, this document records work in progress only.
