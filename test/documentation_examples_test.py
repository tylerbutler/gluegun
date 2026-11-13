"""Check the direct source imports used by the two source-backed guides."""

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_documentation_examples", ROOT / "scripts/check_documentation_examples.py",
)
documentation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(documentation)


class GuideWiringTests(unittest.TestCase):
    def page(self, raw_import):
        return (
            "import { Code } from '@astrojs/starlight/components';\n"
            f"import guideSource from '{raw_import}';\n"
            '<Code code={guideSource} lang="gleam" />\n'
        )

    def test_source_backed_pages_resolve(self):
        documentation.check_guide_wiring()

    def test_missing_canonical_source_is_rejected(self):
        with patch.object(Path, "is_file", return_value=False):
            with self.assertRaisesRegex(ValueError, "Canonical guide source is missing"):
                documentation.check_guide_wiring()

    def test_missing_or_wrong_raw_import_is_rejected(self):
        for raw_import in documentation.GUIDES.values():
            page = self.page(raw_import)
            for broken in (
                page.replace(f"import guideSource from '{raw_import}';\n", ""),
                page.replace(raw_import, raw_import.removesuffix("?raw")),
                page.replace(raw_import, "./wrong.gleam?raw"),
            ):
                with self.subTest(page=broken), self.assertRaises(ValueError):
                    documentation.validate_guide_wiring(broken, raw_import)

    def test_missing_or_indirect_code_binding_is_rejected(self):
        raw_import = next(iter(documentation.GUIDES.values()))
        page = self.page(raw_import)
        for broken in (
            page.replace('<Code code={guideSource} lang="gleam" />', ""),
            page.replace("code={guideSource}", "code={otherSource}"),
            page.replace("code={guideSource}", "code={guideSource.slice(1)}"),
            page.replace('lang="gleam"', 'lang="text"'),
            page.replace("import { Code } from '@astrojs/starlight/components';", ""),
        ):
            with self.subTest(page=broken), self.assertRaises(ValueError):
                documentation.validate_guide_wiring(broken, raw_import)


if __name__ == "__main__":
    unittest.main()
