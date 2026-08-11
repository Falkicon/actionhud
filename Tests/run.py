from pathlib import Path
from xml.etree import ElementTree

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
TESTS = (
    "Tests/test_utils.lua",
    "Tests/test_actionbars_cooldown.lua",
    "Tests/test_unitframe_identity.lua",
    "Tests/test_unit_event_router.lua",
    "Tests/test_layout_manager.lua",
)


def main() -> None:
    verify_manifest()

    syntax_runtime = LuaRuntime()
    for path in ROOT.rglob("*.lua"):
        relative = path.relative_to(ROOT)
        if relative.parts[0] in {"Libs", "Tests"}:
            continue
        syntax_runtime.execute("assert(loadfile(...))", str(path))

    for relative in TESTS:
        print(f"TEST {relative}", flush=True)
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.execute("assert(loadfile(...))()", str(ROOT / relative))


def verify_manifest() -> None:
    def verify_xml(path: Path) -> None:
        tree = ElementTree.parse(path)
        for element in tree.iter():
            kind = element.tag.rsplit("}", 1)[-1]
            if kind not in {"Script", "Include"}:
                continue
            reference = element.attrib.get("file")
            if not reference:
                continue
            target = path.parent / reference.replace("\\", "/")
            assert target.is_file(), f"Missing manifest dependency: {target}"
            if kind == "Include":
                verify_xml(target)

    for raw_line in (ROOT / "ActionHud.toc").read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        target = ROOT / line.replace("\\", "/")
        assert target.is_file(), f"Missing TOC dependency: {target}"
        if target.suffix.lower() == ".xml":
            verify_xml(target)


if __name__ == "__main__":
    main()
