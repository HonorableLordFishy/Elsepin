---
name: elsepin-mobile-tester
description: Run Elsepin's iPhone simulator journeys, inspect actual Files imports and saved routes, and diagnose native test failures with GitHub Actions or local Xcode.
---

Read the adjacent [test brief](AGENT_BRIEF.md), the repository's AGENTS.md and docs/BUILDING.md. The active Codex session directs the tests. CI runs Swift, Python and XCTest; it needs no model credentials.

1. Fetch origin, inspect branch ancestry and dirty files, and record the full commit. Use a working branch for changes. Inspect the current inputs in .github/workflows/validate-native.yml.
2. Dispatch **Validate Elsepin (no IPA)** for the branch. With an authenticated GitHub CLI, run `gh workflow run validate-native.yml --ref BRANCH -f ui_focus=all`, or use GitHub's workflow dispatch API. Match the new run's event, branch and head SHA before using its results.
3. Full validation compiles the production Locus scheme and its LocusActivity extension. For simulator work the workflow generates ElsepinValidation.xcodeproj, builds the Locus scheme and runs LocusValidationUITests against com.n3mostudio.elsepin.validation. For local Xcode, follow the simulator steps in the workflow, including provider warmup and export observation for backup tests. Use disposable simulator data.
4. Start with ElsepinFlowUITests.swift, ElsepinImportUITests.swift and ElsepinBackupUITests.swift in Validation/UITests. Reuse visible controls and verify committed state after reopening. Keep synthetic data, simulated connections and injected failures identifiable in results.
5. Inspect both simulator jobs. Download **simulator-validation-evidence**, **simulator-document-evidence** and **device-validation-evidence** from the run. Simulator jobs collect .build/simulator-evidence/{ui-tests.log,summary.json,result-detail.json,attachments/manifest.json}; local execution also produces UI.xcresult there. Device build and regression logs are under .build/validation-evidence. Use the manifest to resolve screenshots and hierarchy attachments. The upload excludes the raw xcresult and expires after seven days.
6. Investigate each failed attempt, including successful retries. Inspect evidence at the last correct screen before deciding whether to change the app, test or runner. Rerun one journey with `-f ui_focus=single -f ui_test=ElsepinBackupUITests/testGPXExportAndImportThroughNativeFiles` (substitute the test you diagnosed), then run its regressions on the corrected SHA. Record cases the runner could not exercise. Report actual outcomes and link the run.
