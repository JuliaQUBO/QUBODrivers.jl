import pathlib
import tomllib
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]

MINIMUM_JULIA_VERSION = "1.10"
LATEST_STABLE_JULIA_VERSION = "1"
QUBOTOOLS_CURRENT_COMPAT_VERSION = "0.13"
SUPPORTED_CI_RUNNERS = {"ubuntu-latest", "windows-2025-vs2026"}
DEPRECATED_WORKFLOW_REFERENCES = (
    "actions/checkout@v4",
    "actions/setup-python@v5",
    "julia-actions/setup-julia@v1",
    "julia-actions/setup-julia@latest",
    "actions/labeler@v5",
    "codecov/codecov-action@v5",
    "windows-latest",
)


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
            QUBOTOOLS_CURRENT_COMPAT_VERSION,
            [entry.strip() for entry in compat["QUBOTools"].split(",")],
        )

    def test_docs_compat_exercises_current_qubotools_minor(self) -> None:
        package_compat = self.load_toml("Project.toml")["compat"]
        docs_compat = self.load_toml("docs/Project.toml")["compat"]

        self.assertEqual(docs_compat["QUBOTools"], package_compat["QUBOTools"])
        self.assertIn(
            QUBOTOOLS_CURRENT_COMPAT_VERSION,
            [entry.strip() for entry in docs_compat["QUBOTools"].split(",")],
        )

    def test_ci_matrix_covers_floor_and_latest_stable(self) -> None:
        workflow = self.load_yaml(".github/workflows/ci.yml")
        matrix = workflow["jobs"]["test"]["strategy"]["matrix"]

        versions = {str(version) for version in matrix["version"]}

        self.assertEqual(versions, {MINIMUM_JULIA_VERSION, LATEST_STABLE_JULIA_VERSION})

    def test_ci_matrix_uses_explicit_supported_runners(self) -> None:
        workflow = self.load_yaml(".github/workflows/ci.yml")
        matrix = workflow["jobs"]["test"]["strategy"]["matrix"]

        self.assertEqual(set(matrix["os"]), SUPPORTED_CI_RUNNERS)

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

    def test_dependabot_tracks_julia_compat_environments(self) -> None:
        dependabot = self.load_yaml(".github/dependabot.yml")
        expected_groups_by_directory = {
            "/": "root-julia-dependencies",
            "/docs": "docs-julia-dependencies",
            "/test": "test-julia-dependencies",
        }

        julia_updates = {
            update["directory"]: update
            for update in dependabot["updates"]
            if update["package-ecosystem"] == "julia"
        }

        self.assertEqual(
            set(julia_updates),
            set(expected_groups_by_directory),
        )

        for directory, group_name in expected_groups_by_directory.items():
            project_path = (
                "Project.toml"
                if directory == "/"
                else f"{directory.removeprefix('/')}/Project.toml"
            )

            self.assertIn("compat", self.load_toml(project_path))
            self.assertEqual(julia_updates[directory]["schedule"]["interval"], "weekly")
            self.assertEqual(
                julia_updates[directory]["groups"][group_name]["patterns"],
                ["*"],
            )

    def test_dependabot_tracks_github_actions_monthly(self) -> None:
        dependabot = self.load_yaml(".github/dependabot.yml")
        github_actions_updates = [
            update
            for update in dependabot["updates"]
            if update["package-ecosystem"] == "github-actions"
        ]

        self.assertEqual(len(github_actions_updates), 1)
        self.assertEqual(github_actions_updates[0]["directory"], "/")
        self.assertEqual(github_actions_updates[0]["schedule"]["interval"], "monthly")

    def test_workflows_do_not_use_deprecated_action_or_runner_references(self) -> None:
        workflow_text = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted((ROOT / ".github" / "workflows").glob("*.yml"))
        )

        for reference in DEPRECATED_WORKFLOW_REFERENCES:
            self.assertNotIn(reference, workflow_text)


if __name__ == "__main__":
    unittest.main()
