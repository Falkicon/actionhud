"""Repository-level quality checks that do not require a WoW client."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path
from xml.etree import ElementTree


L_KEY_RE = re.compile(r'L\["((?:[^"\\]|\\.)+)"\]')
L_DEFINITION_RE = re.compile(r'^\s*L\["((?:[^"\\]|\\.)+)"\]\s*=', re.MULTILINE)
LUACHECK_VERSION = "1.2.0"
DEVELOPMENT_PACKAGE_EXCLUSIONS = (
    ".github",
    ".luacheckrc",
    "Tests",
    "_test_",
    "docs",
    "requirements-dev.txt",
)


class QualityError(AssertionError):
    """Raised when the repository violates a checked invariant."""


def _relative_inside(root: Path, base: Path, reference: str) -> Path:
    target = (base / reference.replace("\\", "/")).resolve()
    try:
        return target.relative_to(root.resolve())
    except ValueError as error:
        raise QualityError(f"Manifest reference escapes repository: {reference}") from error


def collect_manifest_files(root: Path) -> set[Path]:
    """Return the complete TOC/XML dependency graph and validate every edge."""
    root = root.resolve()
    toc = root / "ActionHud.toc"
    if not toc.is_file():
        raise QualityError(f"Missing addon manifest: {toc}")

    found: set[Path] = {Path("ActionHud.toc")}
    visited_xml: set[Path] = set()

    def add_reference(base: Path, reference: str) -> Path:
        relative = _relative_inside(root, base, reference)
        target = root / relative
        if not target.is_file():
            raise QualityError(f"Missing manifest dependency: {relative.as_posix()}")
        found.add(relative)
        return target

    def visit_xml(path: Path) -> None:
        relative_xml = path.resolve().relative_to(root)
        if relative_xml in visited_xml:
            return
        visited_xml.add(relative_xml)
        try:
            tree = ElementTree.parse(path)
        except ElementTree.ParseError as error:
            raise QualityError(f"Invalid XML manifest {relative_xml.as_posix()}: {error}") from error
        for element in tree.iter():
            kind = element.tag.rsplit("}", 1)[-1]
            if kind not in {"Script", "Include"}:
                continue
            reference = element.attrib.get("file")
            if not reference:
                raise QualityError(f"Empty {kind} reference in {relative_xml.as_posix()}")
            target = add_reference(path.parent, reference)
            if kind == "Include":
                visit_xml(target)

    for raw_line in toc.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        target = add_reference(root, line)
        if target.suffix.lower() == ".xml":
            visit_xml(target)

    return found


def parse_pkgmeta_ignores(path: Path) -> tuple[str, ...]:
    """Read the top-level `.pkgmeta` ignore list without a YAML dependency."""
    if not path.is_file():
        raise QualityError(f"Missing package manifest: {path}")
    ignores: list[str] = []
    in_ignore = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if raw_line == "ignore:":
            in_ignore = True
            continue
        if in_ignore and raw_line and not raw_line.startswith((" ", "\t")):
            break
        if not in_ignore:
            continue
        match = re.match(r"^\s+-\s+(.+?)\s*$", raw_line)
        if match:
            value = match.group(1).split(" #", 1)[0].strip().replace("\\", "/").rstrip("/")
            if value:
                ignores.append(value)
    if not ignores:
        raise QualityError(".pkgmeta has no top-level ignore entries")
    return tuple(ignores)


def is_package_ignored(relative: Path | str, ignores: tuple[str, ...]) -> bool:
    value = Path(relative).as_posix()
    if value.startswith("./"):
        value = value[2:]
    return any(value == ignored or value.startswith(ignored + "/") for ignored in ignores)


def _first_party_lua(root: Path) -> set[Path]:
    paths: set[Path] = set()
    for path in root.rglob("*.lua"):
        relative = path.relative_to(root)
        if any(part.startswith(".") for part in relative.parts):
            continue
        if relative.parts[0] in {"Libs", "Tests", "_test_", "tmp"}:
            continue
        paths.add(relative)
    return paths


def validate_package_closure(root: Path, manifest_files: set[Path]) -> None:
    """Ensure active files ship and inactive first-party Lua cannot ship accidentally."""
    ignores = parse_pkgmeta_ignores(root / ".pkgmeta")
    ignored_active = sorted(path.as_posix() for path in manifest_files if is_package_ignored(path, ignores))
    if ignored_active:
        raise QualityError("Loaded manifest files excluded from package: " + ", ".join(ignored_active))

    inactive_lua = _first_party_lua(root) - manifest_files
    leaking = sorted(path.as_posix() for path in inactive_lua if not is_package_ignored(path, ignores))
    if leaking:
        raise QualityError("Inactive first-party Lua missing .pkgmeta exclusions: " + ", ".join(leaking))

    missing_tooling = [
        entry
        for entry in DEVELOPMENT_PACKAGE_EXCLUSIONS
        if (root / entry).exists() and not is_package_ignored(entry, ignores)
    ]
    if missing_tooling:
        raise QualityError("Development tooling missing .pkgmeta exclusions: " + ", ".join(missing_tooling))


def validate_localization(root: Path, manifest_files: set[Path]) -> None:
    """Require every literal localization lookup in loaded first-party Lua to be defined."""
    base_locale = Path("Locales/enUS.lua")
    if base_locale not in manifest_files:
        raise QualityError("Locales/enUS.lua is not loaded by ActionHud.toc")

    defined = set(L_DEFINITION_RE.findall((root / base_locale).read_text(encoding="utf-8-sig")))

    uses: dict[str, set[str]] = {}
    dynamic_lookups: list[str] = []
    for relative in sorted(manifest_files):
        if relative.suffix.lower() != ".lua" or relative.parts[0] in {"Libs", "Locales"}:
            continue
        content = (root / relative).read_text(encoding="utf-8-sig")
        for key in L_KEY_RE.findall(content):
            uses.setdefault(key, set()).add(relative.as_posix())
        if re.search(r"\bL\s*\[", L_KEY_RE.sub("", content)):
            dynamic_lookups.append(relative.as_posix())

    if dynamic_lookups:
        raise QualityError(
            'Localization lookups must use literal L["KEY"] syntax: ' + ", ".join(dynamic_lookups)
        )

    missing = sorted(set(uses) - defined)
    if missing:
        details = "; ".join(f'{key!r} ({", ".join(sorted(uses[key]))})' for key in missing)
        raise QualityError("Missing enUS localization keys: " + details)


def validate_repository(root: Path) -> None:
    manifest_files = collect_manifest_files(root)
    validate_localization(root, manifest_files)
    validate_package_closure(root, manifest_files)


def active_first_party_lua(manifest_files: set[Path]) -> list[Path]:
    return sorted(
        path for path in manifest_files if path.suffix.lower() == ".lua" and path.parts[0] != "Libs"
    )


def run_luacheck(root: Path, executable: str = "luacheck") -> None:
    resolved = shutil.which(executable)
    if not resolved and Path(executable).is_file():
        resolved = str(Path(executable).resolve())
    if not resolved:
        raise QualityError(f"Luacheck executable not found: {executable}")
    version = subprocess.run(
        [resolved, "--version"], cwd=root, check=False, capture_output=True, text=True
    )
    if version.returncode or not re.search(
        rf"^Luacheck:\s+{re.escape(LUACHECK_VERSION)}\s*$", version.stdout, re.MULTILINE
    ):
        reported = (version.stdout or version.stderr).splitlines()
        detail = reported[0] if reported else "unknown version"
        raise QualityError(f"Luacheck {LUACHECK_VERSION} required; found {detail}")
    files = active_first_party_lua(collect_manifest_files(root))
    if not files:
        raise QualityError("No active first-party Lua files found for linting")
    result = subprocess.run(
        [resolved, "--config", ".luacheckrc", *(path.as_posix() for path in files)],
        cwd=root,
        check=False,
    )
    if result.returncode:
        raise QualityError(f"Luacheck failed with exit code {result.returncode}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--lint", action="store_true", help="Run Luacheck on active first-party Lua")
    parser.add_argument("--luacheck", default="luacheck", help="Luacheck executable name or path")
    args = parser.parse_args()
    validate_repository(args.root)
    if args.lint:
        run_luacheck(args.root, args.luacheck)
    result = "SUCCESS: manifest, localization, and package closure verified"
    if args.lint:
        result += "; active first-party Lua lint passed"
    print(result)


if __name__ == "__main__":
    main()
