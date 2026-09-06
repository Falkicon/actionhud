import os
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime
from quality import validate_repository


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    # Lua fixtures load addon files relative to the repository root.
    os.chdir(ROOT)
    validate_repository(ROOT)
    run_python_tests()

    syntax_runtime = LuaRuntime()
    for directory, subdirs, files in os.walk(ROOT):
        subdirs[:] = [
            name for name in subdirs
            if name not in {"Libs", "Tests", "_test_", "tmp"} and not name.startswith(".")
        ]
        for name in sorted(files):
            if name.endswith(".lua"):
                syntax_runtime.execute("assert(loadfile(...))", str(Path(directory) / name))

    for path in sorted((ROOT / "Tests").glob("test_*.lua")):
        relative = path.relative_to(ROOT).as_posix()
        print(f"TEST {relative}", flush=True)
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.execute("assert(loadfile(...))()", str(path))


def run_python_tests() -> None:
    suite = unittest.defaultTestLoader.discover(str(ROOT / "Tests"), pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
