"""Compile the code readers see, then exercise owned HTTP connection cleanup."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "website" / "src" / "content" / "docs"
FENCE = re.compile(r"^```gleam[^\n]*\n(.*?)^```", re.MULTILINE | re.DOTALL)
FUNCTION = re.compile(r"^(?:pub )?fn ", re.MULTILINE)
OWNED = {
    ("README.md", 0): "doc_basic",
    ("README.md", 3): "doc_facade",
    ("README.md", 5): "doc_http2",
}
GUIDES = {
    "quick-start.mdx": "../../../../examples/basic_request/src/basic_request/guide.gleam?raw",
    "guides/http2.mdx": "../../../../../examples/http2_preferred/src/http2_preferred/guide.gleam?raw",
}


def validate_guide_wiring(page, raw_import):
    imports = (
        r"""^import\s+\{\s*Code\s*\}\s+from\s+['"]@astrojs/starlight/components['"];?\s*$""",
        rf"""^import\s+guideSource\s+from\s+['"]{re.escape(raw_import)}['"];?\s*$""",
    )
    if not all(re.search(pattern, page, re.MULTILINE) for pattern in imports):
        raise ValueError(f"Guide must import Code and guideSource from {raw_import}")
    if not re.search(
        r"""^<Code\s+code=\{guideSource\}\s+lang=['"]gleam['"]\s*/>\s*$""",
        page, re.MULTILINE,
    ):
        raise ValueError("Guide must pass guideSource directly to Code as Gleam")


def check_guide_wiring():
    for relative, raw_import in GUIDES.items():
        page = DOCS / relative
        validate_guide_wiring(page.read_text(), raw_import)
        source = page.parent / raw_import.removesuffix("?raw")
        if not source.is_file():
            raise ValueError(f"Canonical guide source is missing: {source}")


def examples():
    for path in [ROOT / "README.md", *sorted(DOCS.rglob("*.md*"))]:
        if "reference" in path.relative_to(ROOT).parts:
            continue
        relative = path.relative_to(ROOT).as_posix()
        for index, match in enumerate(FENCE.finditer(path.read_text())):
            source = match[1]
            # Import-only expressions are partial illustrations, not modules.
            if not source.startswith("import ") or not FUNCTION.search(source):
                continue
            name = OWNED.get(
                (relative, index), f"doc_{path.stem.lower().replace('-', '_')}_{index}",
            )
            yield name, relative, source

    landing = (DOCS / "index.mdx").read_text()
    match = re.search(r"export const gleamExample = `([^`]+)`;", landing)
    if match is None:
        raise ValueError("Cannot find the landing-page Gleam example")
    # The landing-page Code component displays a function body, without imports.
    source = (
        "import gleam/http\nimport gleam/int\nimport gleam/io\n"
        "import gleam/result\nimport gluegun/client\nimport gluegun/connection\n"
        "pub fn main() {\n" + match[1] + "\n}\n"
    )
    yield "doc_landing", "website/src/content/docs/index.mdx", source


def check():
    check_guide_wiring()
    snippets = list(examples())
    names = {name for name, _, _ in snippets}
    if len(names) != len(snippets):
        raise ValueError("Documentation example module names must be unique")
    if not {*OWNED.values(), "doc_landing"} <= names:
        raise ValueError("An owned HTTP example is missing from compilation")

    # Keep mise's pinned tool configuration in the generated package's parents.
    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="doc-examples-", dir=ROOT / "build") as directory:
        package = Path(directory)
        src = package / "src"
        src.mkdir()
        (package / "gleam.toml").write_text(
            'name = "documentation_examples"\nversion = "0.0.0"\ntarget = "erlang"\n'
            "[dependencies]\n"
            f"gluegun = {{ path = {json.dumps(str(ROOT))} }}\n"
            f"basic_request = {{ path = {json.dumps(str(ROOT / 'examples/basic_request'))} }}\n"
            f"http2_preferred = {{ path = {json.dumps(str(ROOT / 'examples/http2_preferred'))} }}\n"
            'gleam_stdlib = ">= 0.53.0 and < 2.0.0"\n'
            'gleam_erlang = ">= 1.0.0 and < 2.0.0"\n'
            'gleam_http = ">= 4.0.0 and < 5.0.0"\n'
        )
        for name, relative, source in snippets:
            print(f"{name}: {relative}", flush=True)
            (src / f"{name}.gleam").write_text(source)
        subprocess.run(["gleam", "build"], cwd=package, check=True)
        print(f"Compiled {len(snippets)} documentation examples.", flush=True)

        # Only remaining owned fences get test-only endpoint/cleanup rewrites.
        # Canonical guide dependencies and all public-API examples compile first.
        for name, _, source in snippets:
            if name not in {*OWNED.values(), "doc_landing"}:
                continue
            source = source.replace("connection.open(", "documentation_fixture.open(")
            source = source.replace("gluegun.open(", "documentation_fixture.open(")
            source = source.replace("connection.terminate(", "documentation_fixture.terminate(")
            source = source.replace("gluegun.terminate(", "documentation_fixture.terminate(")
            source = source.replace("milliseconds(5000)", "milliseconds(200)")
            (src / f"{name}.gleam").write_text("import documentation_fixture\n" + source)
        for name in ("documentation_fixture.gleam", "documentation_examples_test.erl"):
            shutil.copyfile(ROOT / "scripts" / name, src / name)
        subprocess.run(
            ["gleam", "run", "-m", "documentation_fixture"], cwd=package, check=True,
        )


if __name__ == "__main__":
    check()
