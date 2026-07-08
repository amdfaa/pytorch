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
    def test_rocm_so_files_are_valid_basenames(self):
        rocm_libs = load_module_from_path(
            "test_rocm_libs_source", REPO_ROOT / "torch" / "_rocm_libs.py"
        )

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
