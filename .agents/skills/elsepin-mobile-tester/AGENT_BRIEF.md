# Elsepin iPhone test brief

Use invented route names, coordinates and settings in a disposable library. Read docs/APP-MAP.md and docs/BACKUPS.md for ownership and merge rules. Capture the decisive picker, review, rejection and reopened state. Keep the simulator model, runtime, commit, run ID and attempt with the results.

| Journey | Evidence to collect |
| --- | --- |
| First launch and daily use | Start clean. Follow setup to the device handoff. Find a synthetic place and save it. Create a route, change a leg, save, leave, reopen and relaunch. Repeat an edit and cancel. Check the actual pin, route, mode or speed. Record any seeded starting state. |
| GPX round trip | Create a named path with a sharp turn. Export it through Files, open the planner's Import GPX picker, select that same file, review, save and reopen from Library. Compare the track name, endpoints and bend. Record the provider and exact path. |
| JSON selective restore | Export a real backup through Files. Change two distinguishable values. Select the exported file through Files, review both differences, apply one and relaunch. Verify the restored value and the deliberately excluded one. |
| Cancel, reject, retry | Cancel the picker and immediately reopen it. Select malformed data and, where available, a valid document advertised as generic data. Verify that rejection preserves the editor and library. Complete a valid import using the same editor. Record how each input arrived. |
| Larger routes | Use increasing counts and a known turn. For each file record exact bytes, input count, elapsed selection-to-review and save-to-committed-state times, plus geometry after reopening. State the clock boundaries and whether UI polling contributes. Report parser ceilings separately from the largest successful measurement. |
| Readability and controls | At normal and accessibility text sizes, reach important actions, back out of editors and inspect actual screens. Exercise the simulator's start, stop and reconnect UI and identify the substituted engine. |
| Physical iPhone | Pair a real device and establish LocalDevVPN. Start a held pin and a route on Wi-Fi, then switch to cellular. At Stop, choose Keep spoofing and verify the session continues. Confirm Stop and check clearing from another app. Reconnect on Wi-Fi or hotspot and start again. Check any cloud Files provider separately. |

Report pass, fail, skipped and untested separately. Disclose retry-only passes and fixture limitations. A selectable file must be tapped in the system picker for a Files claim. Parser tests establish parser behavior. A success banner alone cannot establish persistence. Development validation ends with native checks and evidence.
