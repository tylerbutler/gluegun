"""Check a tagged Hex package without publishing or extracting its files."""

import io
import os
from pathlib import Path
import re
import tarfile
import tomllib


def hex_release(ref, version):
    if ref != f"refs/tags/v{version}":
        raise ValueError(f"Release ref {ref!r} does not match version {version!r}")
    match = re.fullmatch(
        r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
        r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", version,
    )
    if not match:
        raise ValueError(f"Invalid release version: {version!r}")
    return int(match[1]) >= 1


def inspect_package(archive, source):
    with tarfile.open(archive) as outer:
        contents = outer.extractfile("contents.tar.gz")
        if contents is None:
            raise ValueError("Hex archive has no package contents")
        with tarfile.open(fileobj=io.BytesIO(contents.read()), mode="r:gz") as inner:
            members = inner.getmembers()
    names = {member.name for member in members}
    required = {"LICENSE", "README.md", "gleam.toml", "src/gluegun_ffi.erl"}
    required.update(
        path.as_posix() for path in source.rglob("*")
        if path.is_file() and path.suffix in {".gleam", ".erl", ".hrl"}
    )
    missing = required - names
    unexpected = {
        member.name for member in members
        if not member.isfile() or not (
            member.name in {"LICENSE", "README.md", "gleam.toml"}
            or re.fullmatch(r"src/[\w/@.-]+\.(gleam|erl|hrl|app\.src)", member.name)
            or re.fullmatch(r"include/[\w@.-]+\.hrl", member.name)
        )
        or ".." in Path(member.name).parts
    }
    if missing or unexpected:
        raise ValueError(
            f"Invalid package contents: missing={sorted(missing)}, "
            f"unexpected={sorted(unexpected)}",
        )
    print(f"Inspected {len(names)} package files; source and licence present.")


def main():
    config = tomllib.loads(Path("gleam.toml").read_text())
    eligible = hex_release(os.environ["GITHUB_REF"], config["version"])
    inspect_package(
        Path("build") / f'{config["name"]}-{config["version"]}.tar', Path("src"),
    )
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"hex={str(eligible).lower()}\n")


if __name__ == "__main__":
    main()
