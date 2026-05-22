import pathlib
import tomllib
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]

MINIMUM_JULIA_VERSION = "1.10"
LATEST_STABLE_JULIA_VERSION = "1"
QUBOTOOLS_COMPAT_VERSION = "0.12"


class JuliaCiPolicyTests(unittest.TestCase):
    def read_text(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def load_toml(self, relative_path: str):
        with (ROOT / relative_path).open("rb") as file:
            return tomllib.load(file)

    def load_yaml(self, relative_path: str):
        return yaml.safe_load(self.read_text(relative_path))

    def test_package_compat_matches_supported_floor(self) -> None:
        compat = self.load_toml("Project.toml")["compat"]

        self.assertEqual(compat["julia"], MINIMUM_JULIA_VERSION)
        self.assertIn(
            QUBOTOOLS_COMPAT_VERSION,
            [entry.strip() for entry in compat["QUBOTools"].split(",")],
        )

    def test_docs_compat_exercises_current_qubotools_minor(self) -> None:
        compat = self.load_toml("docs/Project.toml")["compat"]

        self.assertEqual(compat["QUBOTools"], QUBOTOOLS_COMPAT_VERSION)

    def test_ci_matrix_covers_floor_and_latest_stable(self) -> None:
        workflow = self.load_yaml(".github/workflows/ci.yml")
        matrix = workflow["jobs"]["test"]["strategy"]["matrix"]

        versions = {str(version) for version in matrix["version"]}

        self.assertEqual(versions, {MINIMUM_JULIA_VERSION, LATEST_STABLE_JULIA_VERSION})

    def test_documentation_build_uses_latest_stable_julia(self) -> None:
        workflow = self.load_yaml(".github/workflows/documentation.yml")
        steps = workflow["jobs"]["build"]["steps"]
        setup_steps = [
            step
            for step in steps
            if step.get("uses", "").startswith("julia-actions/setup-julia@")
        ]

        self.assertEqual(len(setup_steps), 1)
        self.assertEqual(
            setup_steps[0]["with"]["version"],
            LATEST_STABLE_JULIA_VERSION,
        )


if __name__ == "__main__":
    unittest.main()
