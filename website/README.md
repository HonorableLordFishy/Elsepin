# Elsepin website

Static HTML, CSS, JavaScript, and a standard-library Python builder. No runtime
package dependencies, analytics, account forms, or location requests. The approved
artwork and eight native palettes are reused; the maps and phone are explicitly
illustrations of the development app.

## Build and preview

```sh
python3 website/build.py
python3 -m http.server 8770 --bind 127.0.0.1 --directory website/dist
```

Open http://127.0.0.1:8770/ on the computer running the server. On this Windows
workspace, `.build/python-3.13.7/python.exe` is the available Python executable.
The local preview is separate from https://elsepin.onrender.com; rebuilding does
not update the live site.

Only `website/dist` is the export. The builder uses an explicit file allowlist and
rejects unexpected existing output or symlink output. Keep QA screenshots, logs,
helper state, source, credentials, and pairing files outside it. If an old export
contains unexpected files, move that export aside for inspection and rebuild.

## Product truth

- `Shared/ShiftAppearance.swift`: theme colors and default (Bloom).
- `Shared/AppearancePolicy.swift`: theme-owned light/dark mode, Glacier following
  the device, and solid/glass material. Native typography is fixed; the old website
  font picker was inaccurate and is removed.
- `Brand/AppearanceIcons/manifest.json`: thirteen approved icon choices, primary
  Prism Jumpgate. PNG files are copied byte-for-byte.
- `Brand/product.json`: current development inventory, aligned with `project.yml`.
- `website/release.json`: separately verified **public** release metadata. The
  public release is 2.6.0 as checked on 14 November; 2.6.1 build 84 is development.
  Recheck the official public release before publishing. A successful CI artifact
  is not approval to call a build a public release.

The studio's Device appearance control simulates a device setting for Glacier;
other themes own their appearance, matching the app. All selections exist in page
memory and reset on reload. Preview teleport never accesses geolocation or a
location engine. App capabilities still depend on signing and pairing.

## Source map and typography

- `public/index.html`: homepage, features, appearance studio, setup and FAQ.
- `public/styles.css`: deep-blue map composition, glass controls, responsive
  layout, enlarged-text adaptations, and accessibility media queries.
- `public/city-map.svg`: original illustrated city diagram, with no external tiles.
- `public/app.js`: shared navigation, scroll-linked map chapters, and a native
  preview dialog. The same studio node moves into the dialog and returns when
  closed, preserving all choices and restoring focus/scroll position.
- `public/symbols.svg`: authored SVG control symbols; approved app icons are separate.
- `public/guide.html`, `privacy.html`, `404.html`: complete supporting pages.
- `public/fonts/`: locally served Manrope and Sora, with their
  complete SIL licenses. Original files came from Google Fonts' `ofl/manrope` and
  `ofl/sora` directories. No external font requests at runtime.
- `build.py`: catalog extraction, release token substitution, and allowlisted export.
- `tests/`: export/data-contract and actual-browser regression checks.
- `VERIFICATION.md`: decisions, evidence, limitations, and before/after links.
- `PRODUCT.md`, `DIRECTION.md`, `DESIGN.md`: scoped product facts, the owner's
  replacement direction, and the built website's design system.

The three story chapters use normal page scrolling. A passive listener requests
at most one animation frame while the hero/story is visible; no idle animation
loop runs. Reduced motion gives a static presentation. Reduced transparency uses
opaque panels, including on this Windows computer where that preference is on.
Glass surfaces are visible when the system allows transparency. The preview uses
three selectable example pins, a simulated teleport/stop action, and Map/Library/
Settings illustrations. It never changes the visitor's real location.

Explicit `tabindex="0"` on links retains DOM order while making links reachable
under WebKit's restrictive default keyboard settings. Skip links target a main
element with `tabindex="-1"`. Don't replace native links with click handlers.

## Checks

```sh
python3 -m unittest discover -s website/tests -v
node --check website/public/app.js
```

For browser checks, install **development-only** tools in the ignored QA workspace:

```sh
npm install --prefix .build/website-qa --no-audit --no-fund playwright @axe-core/playwright
node .build/website-qa/node_modules/playwright/cli.js install chromium webkit
```

Then set `ELSEPIN_QA_MODULES` to the absolute `.build/website-qa/node_modules` path
and run `node website/tests/browser.cjs` with the preview server running.
`CHROMIUM_EXECUTABLE` optionally selects an existing Chromium binary;
`ELSEPIN_PREVIEW_URL` and `ELSEPIN_QA_OUTPUT` optionally override the local URL and
ignored evidence directory. The verified run used Playwright 1.65.1 and axe-core
through `@axe-core/playwright`. These tools are not site dependencies or exports.

The browser suite covers both Chromium and WebKit: preview open/close and focus
restoration, scroll chapters, selectable map pins, every theme/icon, surfaces,
Glacier device modes, all screens, simulated actions, reset, repeated input,
keyboard navigation, reduced motion, 320/1440px layouts, 200% text, all pages,
missing catalog, JavaScript disabled, and request/storage observations. Chromium
also runs axe accessibility scans and a forced-colors check. Actual iPhone Safari,
VoiceOver, touch feel and production-network performance require separate checks.

## Deployment boundary

The Render service uses the public Elsepin-Releases repository's `website/`
directory. The source Elsepin repository is also public by the owner's prior
decision; that does not authorize publication of this revision. Deploys are manual.

After explicit approval, copy only a verified `website/dist` into the release
repository's `website/` directory. Its existing Render configuration uses build
command `test -f website/index.html` and publish directory `website`. Never publish
the source root or `.build`. No environment variables, persistent disk, or location
helper deployment is needed for the static website.

On 15 November the owner approved pushing this rewrite and deploying it to the
existing Elsepin Render site. They approved only the Stop/reconnection copy edit
for the website, adding Wi-Fi and a conditional note that another device's Wi-Fi
hotspot can also work. The app's test IPA remains separate from public releases.
