import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from quality import QualityError, run_luacheck, validate_repository


class RepositoryQualityTests(unittest.TestCase):
    def make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "Locales").mkdir()
        (root / "ActionHud.toc").write_text("Locales\\enUS.lua\nMain.lua\n", encoding="utf-8")
        (root / "Locales" / "enUS.lua").write_text('L["Known"] = true\n', encoding="utf-8")
        (root / "Main.lua").write_text('print(L["Known"])\n', encoding="utf-8")
        (root / ".pkgmeta").write_text("ignore:\n  - Tests\n", encoding="utf-8")
        return root

    def test_valid_minimal_repository(self) -> None:
        validate_repository(self.make_repo())

    def test_pkgmeta_externals_fail(self) -> None:
        root = self.make_repo()
        (root / ".pkgmeta").write_text(
            "ignore:\n  - Tests\nexternals:\n  Libs/LibStub: https://example.invalid\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(QualityError, "externals"):
            validate_repository(root)

    def test_library_version_drift_fails(self) -> None:
        root = self.make_repo()
        library = root / "Libs" / "AceEvent-3.0"
        library.mkdir(parents=True)
        (library / "AceEvent-3.0.lua").write_text('local MAJOR, MINOR = "AceEvent-3.0", 9\n', encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "AceEvent-3.0 minor 9, pinned 4"):
            validate_repository(root)

    def test_missing_localization_key_fails(self) -> None:
        root = self.make_repo()
        (root / "Main.lua").write_text('print(L["Missing"])\n', encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "Missing enUS localization keys"):
            validate_repository(root)

    def test_dynamic_localization_lookup_fails(self) -> None:
        root = self.make_repo()
        (root / "Main.lua").write_text("print(L[key])\n", encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "must use literal"):
            validate_repository(root)

    def test_inactive_lua_without_package_exclusion_fails(self) -> None:
        root = self.make_repo()
        (root / "Dormant.lua").write_text("return {}\n", encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "Inactive first-party Lua"):
            validate_repository(root)

    def test_loaded_file_excluded_from_package_fails(self) -> None:
        root = self.make_repo()
        (root / ".pkgmeta").write_text("ignore:\n  - Main.lua\n", encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "Loaded manifest files excluded"):
            validate_repository(root)

    def test_missing_manifest_dependency_fails(self) -> None:
        root = self.make_repo()
        (root / "ActionHud.toc").write_text("Missing.lua\n", encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "Missing manifest dependency"):
            validate_repository(root)

    def test_duplicate_localization_key_fails(self) -> None:
        root = self.make_repo()
        (root / "Locales" / "enUS.lua").write_text('L["Known"] = true\nL["Known"] = true\n', encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "Duplicate enUS localization keys"):
            validate_repository(root)

    def test_unsupported_interface_fails(self) -> None:
        root = self.make_repo()
        (root / "ActionHud.toc").write_text("## Interface: 120100, 110205\nLocales\\enUS.lua\nMain.lua\n", encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "Unsupported TOC Interface values: 110205"):
            validate_repository(root)

    def test_toc_version_must_match_changelog(self) -> None:
        root = self.make_repo()
        (root / "ActionHud.toc").write_text("## Version: 1.2.0\nLocales\\enUS.lua\nMain.lua\n", encoding="utf-8")
        (root / "CHANGELOG.md").write_text("# Changelog\n\n## [Unreleased]\n\n## [1.1.0] - 2026-01-01\n", encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "TOC version 1.2.0 does not match latest CHANGELOG release 1.1.0"):
            validate_repository(root)

    def test_trailing_whitespace_fails(self) -> None:
        root = self.make_repo()
        (root / "Main.lua").write_text('print(L["Known"]) \n', encoding="utf-8")
        with self.assertRaisesRegex(QualityError, "Trailing whitespace: Main.lua:1"):
            validate_repository(root)

    def test_wrong_luacheck_version_fails(self) -> None:
        root = self.make_repo()
        with patch("quality.shutil.which", return_value=sys.executable):
            with self.assertRaisesRegex(QualityError, "Luacheck 1.2.0 required"):
                run_luacheck(root)


if __name__ == "__main__":
    unittest.main()
