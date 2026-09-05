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

    def test_wrong_luacheck_version_fails(self) -> None:
        root = self.make_repo()
        with patch("quality.shutil.which", return_value=sys.executable):
            with self.assertRaisesRegex(QualityError, "Luacheck 1.2.0 required"):
                run_luacheck(root)


if __name__ == "__main__":
    unittest.main()
