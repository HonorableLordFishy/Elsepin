#!/usr/bin/env python3
"""Build an allowlisted static site. Never publish the repository or helper state.

Theme colors come from the same Swift palette used by the app. Icon pixels come
from approved app previews; this script doesn't redraw or recolor any artwork.
"""
from pathlib import Path
import json
import re
import shutil
import html

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'website'
PUBLIC = SITE / 'public'
OUT = SITE / 'dist'
INKS = ['accent', 'onAccent', 'secondary', 'canvas', 'surface', 'text', 'muted']
DETAILS = {
    'glacier': 'Ice blue and silver. Follows your device’s light or dark appearance.',
    'afterhours': 'Deep ink and violet. A softer kind of night.',
    'porcelain': 'Chalk and graphite. Quiet, with just enough contrast.',
    'ion': 'Citron and graphite. A bright point in a dark palette.',
    'ember': 'Copper highlights on warm charcoal.',
    'bloom': 'Petal pink and berry. The app’s default, with a softer side.',
    'blueprint': 'Pale paper and cobalt. Clear from the first glance.',
    'titanium': 'Platinum details on a grounded ink canvas.',
}
FONT_FILES = ['manrope.ttf', 'sora.ttf', 'manrope-OFL.txt', 'sora-OFL.txt']
PUBLIC_FILES = ['index.html', 'styles.css', 'app.js', 'guide.html', 'privacy.html', '404.html', 'robots.txt', 'healthz', 'symbols.svg', 'city-map.svg']


def catalog():
    source = (ROOT / 'Shared/ShiftAppearance.swift').read_text(encoding='utf-8')
    palettes = re.findall(r'case \.(\w+):\s*light = \[([^]]+)\]\s*night = \[([^]]+)\]', source)
    assert len(palettes) == 8, 'Update the catalog parser when the palette format changes.'
    themes = []
    policy = (ROOT / 'Shared/AppearancePolicy.swift').read_text(encoding='utf-8')
    modes = {}
    for cases, mode in re.findall(r'case ([^:]+): return "(dark|light|system)"', policy):
        for name in re.findall(r'\.(\w+)', cases):
            modes[name] = mode
    for name, light, dark in palettes:
        def colors(text):
            values = re.findall(r'0x([A-Fa-f0-9]{6})', text)
            assert len(values) == len(INKS)
            return dict(zip(INKS, ['#' + v.lower() for v in values]))
        themes.append(dict(id=name, title=name.capitalize(), detail=DETAILS[name],
                           mode=modes[name], light=colors(light), dark=colors(dark)))
    manifest = json.loads((ROOT / 'Brand/AppearanceIcons/manifest.json').read_text(encoding='utf-8'))
    icons = []
    for entry in manifest:
        title = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', entry['design'])
        if entry['finish'] != 'Default': title += ' · ' + entry['finish']
        icons.append(dict(id=entry['preview'].replace('ShiftIcon-', 'ElsepinIcon-'), title=title))
    default = re.search(r'static let defaultStyle = ShiftVisualStyle\.(\w+)', source).group(1)
    product = json.loads((ROOT / 'Brand/product.json').read_text(encoding='utf-8'))
    assert product['defaultTheme'] == default, 'Brand inventory must match the native theme default.'
    return dict(themes=themes, icons=icons, defaults=dict(theme=default, icon=icons[0]['id'], material='solid'))


def page_tokens():
    product = json.loads((ROOT / 'Brand/product.json').read_text(encoding='utf-8'))
    release = json.loads((SITE / 'release.json').read_text(encoding='utf-8'))
    assert re.fullmatch(r'https://github\.com/N3moStudio/Elsepin-Releases/releases/tag/v[\d.]+', release['url'])
    return dict(development_version=product['version'], public_version=release['version'],
                public_release_url=release['url'], release_checked=release['checked'])


def build():
    # Fail closed on stale output: never deploy an old QA page or stray file.
    # The caller can move its prior dist folder aside, then rebuild cleanly.
    data = catalog()
    allowed = {Path(name) for name in PUBLIC_FILES + ['catalog.js', 'licenses.txt']}
    allowed |= {Path('fonts') / name for name in FONT_FILES}
    allowed |= {Path('assets') / (icon['id'] + '.png') for icon in data['icons']}
    allowed.add(Path('assets/prism.png'))
    if OUT.is_symlink():
        raise ValueError('The site output must not be a symbolic link.')
    for existing in OUT.rglob('*') if OUT.exists() else []:
        if existing.is_symlink() or not existing.resolve().is_relative_to(OUT.resolve()):
            raise ValueError('The site output contains an unsafe path.')
        if existing.is_file() and existing.relative_to(OUT) not in allowed:
            raise ValueError(f'Unexpected site output; move it aside before building: {existing.name}')
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'assets').mkdir(exist_ok=True)
    # Explicit allowlist: a stray secret or future helper file cannot enter the site.
    for name in PUBLIC_FILES:
        content = (PUBLIC / name).read_text(encoding='utf-8')
        if name.endswith('.html'):
            for key, value in page_tokens().items():
                content = content.replace('{{' + key + '}}', html.escape(value, quote=True))
            assert '{{' not in content, f'Unresolved page token in {name}'
        (OUT / name).write_text(content, encoding='utf-8')
    (OUT / 'fonts').mkdir(exist_ok=True)
    for name in FONT_FILES:
        shutil.copyfile(PUBLIC / 'fonts' / name, OUT / 'fonts' / name)
    (OUT / 'catalog.js').write_text('window.ELSEPIN_CATALOG = ' + json.dumps(data, ensure_ascii=True) + ';\n', encoding='utf-8')
    for icon in data['icons']:
        shutil.copyfile(ROOT / 'Locus/Resources/IconPreviews' / (icon['id'].replace('ElsepinIcon-', 'ShiftIcon-') + '.png'), OUT / 'assets' / (icon['id'] + '.png'))
    shutil.copyfile(ROOT / 'Locus/Resources/IconPreviews/ShiftIcon-PrismJumpgate-Default.png', OUT / 'assets/prism.png')
    shutil.copyfile(ROOT / 'Locus/Resources/OpenSourceNotices.txt', OUT / 'licenses.txt')
    print(f'Static site ready: {OUT} ({len(data["themes"])} themes, {len(data["icons"])} icons).')


if __name__ == '__main__':
    build()
