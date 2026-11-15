"""Export boundary, product truth, and link regression tests; standard library only."""
from contextlib import redirect_stdout
from html.parser import HTMLParser
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from urllib.parse import urlsplit, unquote
import importlib.util
import json
import re
import shutil
import unittest

SPEC = importlib.util.spec_from_file_location('site_build', Path(__file__).resolve().parents[1] / 'build.py')
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class Page(HTMLParser):
    def __init__(self, content):
        super().__init__()
        self.ids, self.links = set(), []
        self.feed(content)

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if 'id' in attributes:
            if attributes['id'] in self.ids:
                raise AssertionError('Duplicate ID: ' + attributes['id'])
            self.ids.add(attributes['id'])
        for key in ('href', 'src'):
            if key in attributes:
                self.links.append(attributes[key])


class WebsiteExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.out = Path(self.temp.name) / 'dist'
        self.override = patch.object(builder, 'OUT', self.out)
        self.override.start()

    def tearDown(self):
        self.override.stop()
        self.temp.cleanup()

    def build(self):
        with redirect_stdout(StringIO()):
            builder.build()

    def test_native_defaults_and_catalog_are_consistent(self):
        catalog = builder.catalog()
        self.assertEqual(len(catalog['themes']), 8)
        self.assertEqual(len(catalog['icons']), 13)
        self.assertEqual(catalog['defaults']['theme'], 'bloom')
        self.assertEqual(catalog['defaults']['icon'], catalog['icons'][0]['id'])
        modes = {item['id']: item['mode'] for item in catalog['themes']}
        self.assertEqual(modes['glacier'], 'system')
        self.assertEqual(modes['bloom'], 'light')
        self.assertEqual(modes['ion'], 'dark')
        self.assertEqual(len(set(item['id'] for item in catalog['icons'])), 13)

    def test_inventory_tracks_development_not_public_release(self):
        product = json.loads((builder.ROOT / 'Brand/product.json').read_text())
        project = (builder.ROOT / 'project.yml').read_text()
        self.assertIn('MARKETING_VERSION: "' + product['version'] + '"', project)
        self.assertRegex(project, r'CURRENT_PROJECT_VERSION:\s*"?' + str(product['build']) + r'"?\s')
        self.assertEqual(product['releaseState'], 'development')
        tokens = builder.page_tokens()
        self.assertNotEqual(tokens['public_version'], tokens['development_version'])
        self.assertTrue(tokens['public_release_url'].endswith('/v' + tokens['public_version']))

    def test_every_palette_is_complete(self):
        for theme in builder.catalog()['themes']:
            for mode in ('light', 'dark'):
                self.assertEqual(set(theme[mode]), set(builder.INKS))
                for value in theme[mode].values():
                    self.assertRegex(value, r'^#[a-f0-9]{6}$')

    def test_no_unresolved_tokens_or_corrupt_punctuation(self):
        self.build()
        for path in self.out.glob('*.html'):
            text = path.read_text(encoding='utf-8')
            self.assertNotIn('{{', text)
            self.assertNotIn('\ufffd', text)
            self.assertNotIn('Â', text)
        self.assertNotIn('Â', json.dumps(builder.catalog(), ensure_ascii=False))

    def test_export_does_not_sweep_up_new_source_files(self):
        source = Path(self.temp.name) / 'public'
        shutil.copytree(builder.PUBLIC, source)
        (source / 'private-state.json').write_text('{"secret":"not-for-export"}')
        (source / '.env').write_text('TOKEN=not-for-export')
        with patch.object(builder, 'PUBLIC', source):
            self.build()
        self.assertFalse((self.out / 'private-state.json').exists())
        self.assertFalse((self.out / '.env').exists())
        self.assertFalse((self.out / 'release.json').exists())

    def test_stale_unallowlisted_output_fails_closed(self):
        self.out.mkdir()
        (self.out / 'private-state.json').write_text('do not publish')
        with self.assertRaisesRegex(ValueError, 'Unexpected site output'):
            self.build()
        self.assertFalse((self.out / 'index.html').exists())

    def test_symlink_output_fails_closed(self):
        target = Path(self.temp.name) / 'elsewhere'
        target.mkdir()
        try:
            self.out.symlink_to(target, target_is_directory=True)
        except OSError:
            self.skipTest('OS does not permit unprivileged symlinks')
        with self.assertRaisesRegex(ValueError, 'symbolic link'):
            self.build()

    def test_internal_links_fragments_and_assets_resolve(self):
        self.build()
        pages = {path.relative_to(self.out).as_posix(): Page(path.read_text(encoding='utf-8'))
                 for path in self.out.rglob('*') if path.suffix in ('.html', '.svg')}
        for name, page in pages.items():
            for link in page.links:
                url = urlsplit(link)
                if url.scheme or url.netloc:
                    self.assertEqual(url.scheme, 'https')
                    continue
                target = unquote(url.path).lstrip('/') or name
                self.assertTrue((self.out / target).is_file(), (name, link))
                if url.fragment:
                    self.assertIn(url.fragment, pages[target].ids, (name, link))
        css = (self.out / 'styles.css').read_text()
        for target in re.findall(r"url\('([^']+)'\)", css):
            self.assertTrue((self.out / target).is_file())

    def test_required_licenses_and_approved_icon_pixels_are_preserved(self):
        self.build()
        self.assertEqual((self.out / 'licenses.txt').read_bytes(), (builder.ROOT / 'Locus/Resources/OpenSourceNotices.txt').read_bytes())
        for name in ('manrope-OFL.txt', 'sora-OFL.txt'):
            self.assertIn('SIL OPEN FONT LICENSE', (self.out / 'fonts' / name).read_text())
        for icon in builder.catalog()['icons']:
            original = builder.ROOT / 'Locus/Resources/IconPreviews' / (icon['id'].replace('ElsepinIcon-', 'ShiftIcon-') + '.png')
            self.assertEqual(original.read_bytes(), (self.out / 'assets' / (icon['id'] + '.png')).read_bytes())

    def test_repeat_build_is_deterministic(self):
        self.build()
        before = {path.relative_to(self.out): path.read_bytes() for path in self.out.rglob('*') if path.is_file()}
        self.build()
        after = {path.relative_to(self.out): path.read_bytes() for path in self.out.rglob('*') if path.is_file()}
        self.assertEqual(before, after)


if __name__ == '__main__':
    unittest.main()
