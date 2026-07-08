# Owner(s): ["oncall: package/deploy"]

import importlib.util
import tempfile
from pathlib import Path

from torch.testing._internal.common_utils import run_tests, TestCase


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_module_from_path(module_name: str, path: Path):
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestRocmLibs(TestCase):
    def load_rocm_libs_with_source_replacement(self, old: str, new: str):
        source = (REPO_ROOT / "torch" / "_rocm_libs.py").read_text()
        self.assertIn(old, source)
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "_rocm_libs.py"
            path.write_text(source.replace(old, new, 1))
            return load_module_from_path("test_rocm_libs_bad", path)

    def test_rocm_so_files_are_valid_basenames(self):
        rocm_libs = load_module_from_path(
            "test_rocm_libs_source", REPO_ROOT / "torch" / "_rocm_libs.py"
        )

        rocm_libs._validate_rocm_so_files()
        self.assertEqual(
            rocm_libs.ROCM_SO_FILES_ALL,
            rocm_libs.ROCM_SO_FILES + rocm_libs.ROCM_SO_FILES_BUNDLE_ONLY,
        )
        self.assertEqual(
            len(rocm_libs.ROCM_SO_FILES_ALL), len(set(rocm_libs.ROCM_SO_FILES_ALL))
        )

        for name in rocm_libs.ROCM_SO_FILES_ALL:
            self.assertIsInstance(name, str)
            self.assertEqual(Path(name).name, name)
            self.assertTrue(name.startswith("lib"), name)
            self.assertIn(".so", name)

    def test_rocm_so_files_validation_rejects_bad_entries(self):
        bad_entries = (
            ("\"libamd_comgr.so\"", "123"),
            ("\"libamd_comgr.so\"", "\"rocm/libamd_comgr.so\""),
            ("\"libamd_comgr.so\"", "\"rocm\\\\libamd_comgr.so\""),
            ("\"libamd_comgr.so\"", "\"amd_comgr\""),
            ("\"libmagma.so\"", "\"libamd_comgr.so\""),
        )

        for old, new in bad_entries:
            with self.subTest(new=new):
                with self.assertRaises(AssertionError):
                    self.load_rocm_libs_with_source_replacement(old, new)

    def test_rocm_so_files_validation_rejects_all_list_drift(self):
        with self.assertRaises(AssertionError):
            self.load_rocm_libs_with_source_replacement(
                "ROCM_SO_FILES_ALL: list[str] = ROCM_SO_FILES + ROCM_SO_FILES_BUNDLE_ONLY",
                "ROCM_SO_FILES_ALL: list[str] = ROCM_SO_FILES",
            )

    def test_repair_wheel_loader_prefers_unpacked_torch_copy(self):
        repair_wheel = load_module_from_path(
            "test_repair_wheel",
            REPO_ROOT / ".ci" / "manywheel" / "repair_wheel.py",
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            unpacked_torch = Path(tmpdir) / "torch"
            unpacked_torch.mkdir()
            (unpacked_torch / "_rocm_libs.py").write_text(
                "ROCM_SO_FILES_ALL = ['libfrom-wheel.so']\n"
            )

            self.assertEqual(
                repair_wheel.load_rocm_so_files(unpacked_torch),
                ["libfrom-wheel.so"],
            )

    def test_repair_wheel_loader_falls_back_to_source_tree(self):
        repair_wheel = load_module_from_path(
            "test_repair_wheel_fallback",
            REPO_ROOT / ".ci" / "manywheel" / "repair_wheel.py",
        )
        rocm_libs = load_module_from_path(
            "test_rocm_libs_fallback", REPO_ROOT / "torch" / "_rocm_libs.py"
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            unpacked_torch = Path(tmpdir) / "torch"
            unpacked_torch.mkdir()

            self.assertEqual(
                repair_wheel.load_rocm_so_files(unpacked_torch),
                rocm_libs.ROCM_SO_FILES_ALL,
            )


if __name__ == "__main__":
    run_tests()
