# Website replacement — 15 November 2026

## Publication follow-up

The owner subsequently approved the website push/deployment and only copy edit
5 from the Humanizer proposals. Stop guidance now includes Wi-Fi, LocalDevVPN,
and the conditional wording "Connecting to another device’s Wi-Fi hotspot can
also work." Clearing uncertainty remains explicit. Matching guidance is in both
GitHub READMEs and the app. All other proposed Humanizer edits to website copy
were declined and are unchanged. Public release v2.6.0 was rechecked on GitHub
on 15 November; building test IPA 85 does not publish a new app release.

## Original local verification

Local website work only. No native source changes, IPA packaging, commit, push,
release, upload, or deployment. Preview: http://127.0.0.1:8770/ on this computer.
The public Render URL still serves the previous website.

## What changed

The owner rejected the cream/green refinement and explicitly requested a full
replacement with a better map, scroll animation, glass styling, and a working
preview action. The replacement uses a full-screen illustrated city, Sora display
type, Manrope controls, deep blue surfaces, mint routes, and the approved icon.
Normal scrolling moves the map through three feature chapters. No scroll hijack,
autoplay sound, external map tiles, or perpetual animation loop was introduced.

Open preview now opens a native modal containing the existing live studio. It
preserves selected theme/icon/screen/pin, restores focus and page position, supports
Escape and two close buttons, and retains the studio's state when moved back into
the page. Three example pins, simulated teleport/stop, eight real palettes,
thirteen approved icons, and Map/Library/Settings illustrations are interactive.
Every simulated action is labeled and never accesses a real location engine.

Supporting guide, FAQ, privacy and error pages share the new design. Development
inventory is 2.6.1 build 84; public release metadata is separately verified as
2.6.0 on 14 November. Bloom is the native default; Glacier follows device mode.
Original icon PNGs and licenses are preserved. Font files are self-hosted with
their SIL licenses. Unused exploratory fonts are excluded from the export.

## Verification and evidence

- Python export/data-contract suite: **9 passed, 1 skipped**. Windows did not
  permit creating the symlink needed by that test. The builder still rejects
  symlink output, stale unallowlisted files and unexpected assets.
- JavaScript syntax check and `git diff --check`: passed.
- Main browser suite: **47 passed**, zero browser errors; **29 axe scans** found
  no violations. Chromium 159 and Playwright WebKit 27.2 were exercised through
  Playwright 1.65.1. All theme/icon choices, surfaces, screens, reset, pins,
  modal open/close and focus, scroll chapters, mobile menu/FAQ, reduced motion,
  JavaScript disabled, missing catalog and forced colors were tested.
- Screens covered desktop 1440px, 390px phone, 320px phone and 200% text. Actual
  screenshots were inspected. This caught a narrower-than-intended native dialog
  at large text; its explicit width, fixed padding and compact heading were fixed.
  Large-text library items use full-width text rather than narrow icon-side columns.
- After those corrections, **8 focused check groups passed** with **8 additional
  axe scans** and no violations/errors. These covered both engines at 1440/390px
  and 320px with 200% text, dialog width, pin/theme interactions, close/focus,
  settings reflow, both transparency preferences and setup-nav hover contrast.
  The helper initially used an incorrect hard-coded Glacier color; it was corrected
  to compare against the source-derived catalog. No app change was needed for that
  assertion. Earlier passing layout evidence was retained for the focused resume.
- The local load observation was 534,825 decoded resource bytes, 111ms DOMContentLoaded
  and zero recorded layout shift. These are local observations, not a production
  speed or network-performance claim. No external preview requests, storage,
  cookies, geolocation or analytics were observed.
- A fresh independent reviewer returned **ship for local user review**, with no
  material fixes in the seven supplied desktop/mobile/large-text captures.
  Its condition, the final focused regression check, has now passed. The named Impeccable reviewer
  role was unavailable; a fresh general agent performed the bounded review.

Main browser receipts: `.build/website-qa/rewrite-verified/browser-report.json`.
Final focused layout receipts: `.build/website-qa/rewrite-final/final-checks.json`.
Screenshots are deliberately outside the export:

- Before: `.build/website-qa/before/live-desktop.png`, `live-320.png`.
- After: `.build/website-qa/rewrite-final/desktop.png`, `mobile.png`.
- Preview: `dialog-desktop.png`, `dialog-mobile.png`, `dialog-large-top.png`.
- Sections: `story.png`, `studio.png`, `large-library.png` in the same final folder.
- Previous rejected refinement preserved in `.build/website-qa/refinement-snapshot/`.

## Design tooling and limits

Impeccable led the work; Emil, mobile-native and animate informed interaction and
layout decisions. Awwwards references included Flashquad's product-led focal point
and Telescope's clear visual chapters; their layouts were not copied. The Codebase
Memory transport was unavailable; relevant native facts were checked directly in
source, and the excluded website files were read directly.

One manual detector pass on the rewrite reported 16 static warnings. Small link
text and the setup-nav hover contrast were corrected. Remaining scoped-color and
logical-padding warnings were assessed against computed browser layouts and axe;
the diagram's location ring intentionally distinguishes a position marker. No
global detector settings or skill files were changed to hide findings.

Reduced-transparency mode is enabled on this Windows account. Its opaque panels
are an intentional fallback, not a glass rendering failure. The final visual
captures also exercise no-preference mode so the actual frosted surfaces can be
inspected. Reduced motion disables map transforms and uses a static story.

Windows WebKit is not physical iPhone Safari. Real iPhone VoiceOver/touch feel,
Safari chrome/keyboard resizing, production hosting and network performance have
not been tested. Browser preview success proves nothing about real pairing,
spoofing, battery or the native app's location engine. Before publication, recheck
the public release metadata and perform a brief real-phone website review.
