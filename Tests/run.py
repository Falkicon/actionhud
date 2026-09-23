import argparse
import os
import unittest
from pathlib import Path

from lupa.lua51 import LuaError, LuaRuntime
from quality import validate_repository


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description="Run repository checks and Lua test suites.")
    parser.add_argument("filters", nargs="*", help="only run Lua suites whose file name contains one of these")
    args = parser.parse_args()

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

    suites = sorted((ROOT / "Tests").glob("test_*.lua"))
    if args.filters:
        suites = [path for path in suites if any(text in path.name for text in args.filters)]
        if not suites:
            raise SystemExit(f"No Lua suites match: {', '.join(args.filters)}")
    failures = []
    for path in suites:
        relative = path.relative_to(ROOT).as_posix()
        print(f"TEST {relative}", flush=True)
        runtime = LuaRuntime(unpack_returned_tuples=True)
        try:
            runtime.execute("assert(loadfile(...))()", str(path))
        except LuaError as error:
            failures.append(relative)
            print(f"FAIL {relative}\n{error}", flush=True)
    print(f"\n{len(suites) - len(failures)} of {len(suites)} Lua suites passed", flush=True)
    for relative in failures:
        print(f"FAILED {relative}", flush=True)
    if failures:
        raise SystemExit(1)


def run_python_tests() -> None:
    suite = unittest.defaultTestLoader.discover(str(ROOT / "Tests"), pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
