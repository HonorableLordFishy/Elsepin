---
name: Elsepin Website
description: Deep-blue cartography and glass controls for an illustrated location-simulation preview.
colors:
  mint: "#b5f9dc"
  action-ink: "#10251e"
  focus-violet: "#a989ff"
  paper: "#0b121c"
  ink: "#f2f6fb"
  muted: "#afbdcd"
  line: "#ffffff26"
  studio: "#121e2c"
  glass-solid: "#172635"
typography:
  display:
    fontFamily: "Sora, Manrope, sans-serif"
    fontSize: "clamp(3.5rem, 7.1vw, 7.25rem)"
    fontWeight: 500
    lineHeight: 1.12
    letterSpacing: "-0.055em"
  headline:
    fontFamily: "Sora, Manrope, sans-serif"
    fontSize: "clamp(2.65rem, 4.9vw, 5rem)"
    fontWeight: 500
    lineHeight: 1.12
    letterSpacing: "-0.055em"
  title:
    fontFamily: "Manrope, Arial, sans-serif"
    fontSize: "1.15rem"
    fontWeight: 650
    lineHeight: 1.4
  body:
    fontFamily: "Manrope, Arial, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.65
  label:
    fontFamily: "Manrope, Arial, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 700
    lineHeight: 1.65
rounded:
  field: "0.25rem"
  note: "0.75rem"
  choice: "0.85rem"
  control: "1rem"
  action: "1.1rem"
  hud: "1.25rem"
  navigation: "1.5rem"
  dialog: "1.6rem"
  phone: "2rem"
spacing:
  compact: "0.5rem"
  control-gap: "0.8rem"
  unit: "1rem"
  group: "1.5rem"
  panel: "2rem"
  narrow-columns: "3rem"
  mobile-section: "4rem"
  columns: "6rem"
  section: "7rem"
components:
  button-primary:
    backgroundColor: "{colors.mint}"
    textColor: "{colors.action-ink}"
    typography: "{typography.label}"
    rounded: "{rounded.action}"
    padding: "1rem 1.4rem"
  button-primary-hover:
    backgroundColor: "#ffffff"
  button-ghost:
    backgroundColor: "#ffffff0a"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.action}"
    padding: "1rem 1.4rem"
  button-navigation:
    backgroundColor: "#f5f9ff"
    textColor: "#152032"
    rounded: "{rounded.control}"
    padding: "0.65rem 1rem"
  button-text:
    textColor: "{colors.ink}"
    padding: "0.35rem 0"
  theme-choice:
    backgroundColor: "#ffffff04"
    textColor: "{colors.ink}"
    rounded: "{rounded.choice}"
    padding: "0.9rem 0.8rem"
  theme-choice-selected:
    backgroundColor: "#b5f9dc16"
  appearance-select:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.field}"
    padding: "0.35rem 0.25rem"
  navigation:
    textColor: "{colors.ink}"
    rounded: "{rounded.navigation}"
    padding: "0.7rem 1rem 0.7rem 1.1rem"
  glass-status:
    textColor: "{colors.ink}"
    rounded: "{rounded.hud}"
    padding: "1.15rem 1.3rem"
  preview-badge:
    textColor: "{colors.ink}"
    rounded: "{rounded.phone}"
    padding: "0.25rem 0.55rem"
  preview-dialog:
    backgroundColor: "#101b2bed"
    textColor: "{colors.ink}"
    rounded: "{rounded.dialog}"
    width: "min(1100px, calc(100% - 3rem))"
---

# Design System: Elsepin Website

## Overview

**Creative North Star: "The map is the stage"**

Deep-blue cartography supplies the setting; mint routes, the approved prism artwork, and pearl-edged glass controls bring the foreground into focus. Sora headlines give the website a geometric, open character while Manrope carries readable instructions and compact controls. The direction is taken from `DIRECTION.md`, not from a catalog seed or an inferred standing preference.

This system belongs only to `website/`: its homepage, guide, privacy page, and error page. It does not replace the repository's native design system. The phone is an explicitly labeled web illustration; its eight source-derived native themes, thirteen approved icons, and rounded preview typography are a contained product demonstration. Bloom, solid surfaces, and Prism Jumpgate are the illustrated defaults. The website itself remains dark independently of the illustrated device setting.

**Key Characteristics:**

- Detailed blue cartography behind readable foreground content.
- Pearl-edged glass, mint actions, and visible violet keyboard focus.
- Large geometric headings with calm, compact supporting text.
- Ordinary scrolling with a three-chapter map story and a static reduced-motion presentation.
- One live appearance studio shared by the page and a native browser dialog.

This records the local implementation in `public/styles.css`, `public/app.js`, and `public/index.html`. Product and export boundaries remain in `PRODUCT.md` and `README.md`; verification belongs in `VERIFICATION.md`. This document does not establish publication approval or on-device acceptance.

## Colors

Cool dark neutrals let the mint actions and approved app artwork remain distinct from the map's muted streets and water.

### Primary

- **Route mint** (`mint`) emphasizes the hero, major actions, story status, and selected appearance controls.
- **Deep green action ink** (`action-ink`) keeps primary-button text legible against the pale mint fill.

### Secondary

- **Focus violet** (`focus-violet`) supplies the shared keyboard focus ring. It is an interaction signal, not a replacement for the native theme's accent.

### Neutral

- **Midnight paper** (`paper`) is the page canvas and the base of the map scrims.
- **Pearl ink** (`ink`) is the primary text color.
- **Blue-gray secondary ink** (`muted`) carries supporting copy and captions.
- **Pearl divider** (`line`) separates sections and controls without a heavy grid.
- **Deep studio** (`studio`) is the supporting-page note surface.
- **Opaque blue glass** (`glass-solid`) is the fallback surface when transparency is reduced or backdrop blur is unavailable.

The frontmatter captures reused website primitives. Map artwork has its own drawn palette; the preview's native palettes come from the generated catalog. Neither should be collapsed into the website's mint accent. Sidecar tonal ramps are synthesized display aids, not additional production tokens.

**The Preview Boundary Rule.** Website colors style the surrounding page; native catalog colors stay scoped to the phone illustration.

## Typography

**Display Font:** Sora, with Manrope and sans-serif fallbacks.  
**Body Font:** Manrope, with Arial and sans-serif fallbacks.

Both fonts are served locally with their SIL licenses. The pairing is geometric without making instructions theatrical. There is no website font picker and no promise that these web fonts are the native app's typography.

The normative role values are in the frontmatter. Display is reserved for the hero and document title; headline serves section headings; title serves short feature and setup headings; body carries prose; label describes the main action treatment. Component labels may use smaller observed sizes rather than forcing every control into one size.

Hero headings balance text within an approximately eleven-character measure. Lead copy uses a wider line height and stays within (35rem); supporting-page prose stays within (70ch). Narrow layouts reduce the display scale. At (760px) and below, section headings use (2.5rem); at (360px) and below, the hero uses (2.8rem). Text remains scalable; only decorative phone status chrome uses fixed pixel sizing.

## Layout

The shared shell is `min(80rem, calc(100% - 6rem))`. Major sections use the `section` spacing role. The wide appearance studio has two equal columns, with controls capped at (32rem) and a phone stage capped at (25rem). Setup and FAQ are related two-column layouts; supporting documents pair a (15rem) sticky contents rail with a flexible prose column. Grid children explicitly allow shrinking.

At (1100px), major column gaps reduce to the `narrow-columns` role. At (760px), the shell becomes `calc(100% - 2.5rem)`, navigation becomes a disclosure, content columns stack, and the phone stage stops sticking. The icon grid moves from seven to five columns. The mobile preview dialog puts the phone before its controls. At (360px), shell gutters narrow further and hero actions span the available width.

The (24em) content-fit query makes the hero content-driven, removes the sticky-story overlay, hides its floating status, and uses four icon columns. A (20em) phone-container query wraps illustration content. These adaptations support narrow screens and enlarged text without clipping essential controls. Safe-area insets protect the page edges.

The wide hero uses viewport height bounded by minimum and maximum sizes. Each map-story chapter occupies roughly a viewport, with the illustration sticky behind the copy. Scrolling stays native: a passive listener schedules at most one animation frame while the hero or story is visible, and there is no idle animation loop. Reduced motion replaces this with ordinary static chapters.

## Elevation & Depth

Depth comes from real illustrated map content behind translucent surfaces, dark scrims behind text, pearl borders, subtle inset highlights, and soft structural shadows. Glass uses a layered white gradient over blue, a (24px) backdrop blur, and (160%) saturation. The dialog uses a stronger (28px) blur and a separate dimmed, blurred backdrop. The phone has its own framed silhouette and deeper shadow.

Exact reusable shadow and motion recipes live in `.impeccable/design.json`, because those properties are outside the frontmatter component schema. The important distinction is structural: status cards sit above the map, the dialog sits above the page, and document notes use a simple opaque surface.

**The Legible Glass Rule.** Preserve an opaque fallback and readable foreground content whenever a translucent surface is used.

`prefers-reduced-transparency` makes glass panels, ghost actions, and the dialog opaque and removes their backdrop blur; the phone's glass tray and search illustration return to their theme surface. Unsupported backdrop filtering also gives shared glass an opaque background. Forced-colors mode uses system surfaces and borders, removes decorative map layers and shadows, and outlines selected buttons.

## Shapes

Controls use softly rounded rectangles rather than one universal pill radius. Small fields, notes, theme choices, actions, navigation, and dialogs each have the observed radii in the frontmatter. Circular markers and close controls distinguish location and dismissal from ordinary actions. The phone uses a larger rounded frame; its illustration is visually separate from the surrounding website.

Pearl hairlines define glass edges. Selected theme choices add a mint border and inset stroke; selected icons keep a mint outline around the approved artwork. Artwork is not redrawn or recolored to match a selected theme. SVG interface symbols use rounded caps and joins with a consistent current-color stroke.

## Components

### Buttons and links

Primary actions are pale mint with dark text, a soft inset highlight, and a minimum (52px) height. Ghost actions keep a translucent bordered surface. Navigation's preview action uses a pearl fill and a minimum (44px) height. Secondary text actions remain underlined and retain a minimum (44px) target. Links remain native links; buttons handle in-page actions.

Fine-pointer hover changes the primary fill to white, adds mint to text links, and lifts appearance choices by (2px). Press feedback scales ordinary actions to (0.98). Shared state transitions last (160ms); the pointer-only settling feedback lasts (180ms). Keyboard input disables CSS transitions and smooth scrolling; reduced motion also suppresses the scripted feedback. All focusable controls retain the violet (3px) focus outline with (5px) offset. Disabled controls use reduced opacity and a default cursor.

### Appearance choices and fields

Theme buttons show three palette swatches and a name; `aria-pressed` reports selection. Thirteen approved icon choices have independent selection and accessible names. Native selects choose Solid/Glass and the simulated device appearance. The latter is enabled only for Glacier, which follows the device; other themes own their light/dark appearance. Help text states that distinction.

There is no functional text-search input on the website. The search-like field inside the phone is an illustration. Do not document it as a real location-search form. Preview choices remain in memory and reset on reload. Reset restores Bloom, Solid, Prism Jumpgate, the Map screen, and Waterfront.

### Navigation

The floating wide header combines the approved app icon, lowercase wordmark, ordinary links, and the preview action. The mobile disclosure exposes its state through `aria-expanded`, closes after navigation, and supports Escape with focus restoration. Without JavaScript, links stay visible. Skip links move to a focusable main landmark. Explicit zero tab indices on anchors retain DOM order under restrictive WebKit keyboard settings.

### Map status and illustrated phone

Glass status cards use an icon, short title, supporting line, and optional chapter count. The three story chapters change the map position and status as the visitor scrolls. Decorative map layers are hidden from assistive technology.

The phone offers Map, Library, and Settings illustrations, three selectable example pins, and a simulated teleport/stop control. Selection is expressed through text and `aria-pressed`, with status announcements for changes. The teleport dot has a (450ms) transform transition; it is removed by reduced motion and the keyboard-input treatment. Captions identify the preview as a development-design illustration that does not change location.

### Preview dialog

Open preview calls the native browser dialog. The same studio element moves into it, preserving selections, event handlers, and unique IDs; closing returns it to the original page slot. The trigger's scroll position is restored, and focus returns to the visible trigger or the mobile menu control. Close controls appear at both ends; Escape and outside clicks also dismiss it. The dialog's native modal behavior contains focus.

The wide dialog is bounded by its frontmatter width and `calc(100dvh - 3rem)` height. On narrow screens it leaves (8px) outer margins and stacks the studio. Its top bar remains visible as dialog content scrolls. Pointer opening uses a (250ms) opacity/short-rise entrance; keyboard activation and reduced motion skip it. No duplicate independent studio is created.

### Supporting content

Setup is an ordered list with mint numerals and dividers. FAQ uses native disclosure elements and a visible plus/minus cue. Document notes use the `studio` surface. Release links distinguish the public build from the illustrated development design; this visual system does not establish release status.

## Do's and Don'ts

### Do:

- **Do** keep website tokens separate from source-derived native preview palettes.
- **Do** preserve approved icon artwork and the Bloom, Solid, Prism Jumpgate reset state.
- **Do** keep map content behind glass and provide opaque, reduced-motion, and forced-colors presentations.
- **Do** preserve native scrolling, keyboard focus, dialog state, and narrow or enlarged-text layouts.
- **Do** label the illustrated preview and distinguish development design from the public release.

### Don't:

- **Don't** apply this website system to the native app or overwrite the repository's native design guidance.
- **Don't** restore the superseded cream editorial website direction.
- **Don't** add real-location claims, a functional-looking unimplemented search form, or a native font picker.
- **Don't** duplicate the live studio, persist preview choices without a new requirement, or replace links with click-only navigation.
- **Don't** treat local screenshots, component specimens, or this document as proof of physical-device behavior or permission to publish.
