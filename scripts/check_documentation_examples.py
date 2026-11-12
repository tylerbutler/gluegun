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
    ("website/src/content/docs/quick-start.md", 0): "doc_quick_start",
    ("website/src/content/docs/guides/http2.md", 0): "doc_http2_guide",
}


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
            'gleam_stdlib = ">= 0.53.0 and < 2.0.0"\n'
            'gleam_erlang = ">= 1.0.0 and < 2.0.0"\n'
            'gleam_http = ">= 4.0.0 and < 5.0.0"\n'
        )
        for name, relative, source in snippets:
            print(f"{name}: {relative}", flush=True)
            (src / f"{name}.gleam").write_text(source)
        subprocess.run(["gleam", "build"], cwd=package, check=True)
        print(f"Compiled {len(snippets)} documentation examples.", flush=True)

        # Only the test variants redirect endpoints and inject cleanup errors.
        # The unmodified public-API examples above must compile first.
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
