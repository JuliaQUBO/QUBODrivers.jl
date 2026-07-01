import pathlib
import re
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
ACTION_VERSION_REF = re.compile(r"v(?P<major>[1-9]\d*)(?:\.\d+){0,2}")
MINIMUM_LABELER_MAJOR = 6
MINIMUM_SHARED_CHECKOUT_MAJOR = 6

# Minimum set of glob patterns the documentation label must cover.
# This is a contract floor — removing a pattern here is a deliberate
# decision to relax the labeler; adding one to labeler.yml without
# adding it here is allowed.
REQUIRED_DOC_PATTERNS = (
    "docs/**",
    "**/*.md",
    "**/*.rst",
    "README*",
    "CHANGELOG*",
    "NEWS*",
    "CITATION.cff",
    "LICENSE*",
    "papers/**",
    ".github/ISSUE_TEMPLATE/**",
    ".github/pull_request_template.md",
)


def parse_action_major(uses: object) -> tuple[str, int]:
    if not isinstance(uses, str):
        raise ValueError(f"Action reference must be a string, got {uses!r}")

    action, separator, ref = uses.rpartition("@")
    if not separator or not action:
        raise ValueError(f"Action reference {uses!r} must be pinned as owner/name@vN")

    match = ACTION_VERSION_REF.fullmatch(ref)
    if match is None:
        raise ValueError(f"Action reference {uses!r} must use a pinned vN version ref")

    return action, int(match.group("major"))


class LabelAutomationContractTests(unittest.TestCase):
    def read_text(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def load_yaml(self, relative_path: str):
        return yaml.safe_load(self.read_text(relative_path))

    def assert_uses_action_at_least(
        self,
        uses: object,
        expected_action: str,
        minimum_major: int,
    ) -> None:
        try:
            action, major = parse_action_major(uses)
        except ValueError as exc:
            self.fail(str(exc))

        self.assertEqual(action, expected_action)
        self.assertGreaterEqual(
            major,
            minimum_major,
            f"{expected_action} must use v{minimum_major} or newer",
        )

    def test_action_reference_parser_accepts_supported_major_bumps(self) -> None:
        self.assertEqual(
            parse_action_major("actions/labeler@v7"),
            ("actions/labeler", 7),
        )
        self.assertEqual(
            parse_action_major("actions/checkout@v7"),
            ("actions/checkout", 7),
        )
        self.assertEqual(
            parse_action_major("actions/checkout@v6.0.2"),
            ("actions/checkout", 6),
        )

    def test_action_reference_parser_rejects_stale_and_floating_refs(self) -> None:
        with self.assertRaises(AssertionError):
            self.assert_uses_action_at_least(
                "actions/labeler@v5",
                "actions/labeler",
                MINIMUM_LABELER_MAJOR,
            )
        with self.assertRaises(AssertionError):
            self.assert_uses_action_at_least(
                "actions/checkout@v5",
                "actions/checkout",
                MINIMUM_SHARED_CHECKOUT_MAJOR,
            )

        with self.assertRaises(AssertionError):
            self.assert_uses_action_at_least(
                "actions/labeler@latest",
                "actions/labeler",
                MINIMUM_LABELER_MAJOR,
            )
        with self.assertRaises(AssertionError):
            self.assert_uses_action_at_least(
                "actions/checkout@latest",
                "actions/checkout",
                MINIMUM_SHARED_CHECKOUT_MAJOR,
            )

    def test_documentation_labeler_uses_any_glob_to_all_files(self) -> None:
        labeler = self.load_yaml(".github/labeler.yml")

        self.assertIn("documentation", labeler)

        all_glob_patterns: list = []
        for rule in labeler["documentation"]:
            for entry in rule.get("changed-files", []):
                self.assertNotIn(
                    "all-globs-to-all-files",
                    entry,
                    "documentation label uses all-globs-to-all-files — this requires every "
                    "pattern to match every changed file, so a PR touching only docs/ would "
                    "never receive the label. Use any-glob-to-all-files instead.",
                )
                all_glob_patterns.extend(entry.get("any-glob-to-all-files", []))

        self.assertTrue(
            all_glob_patterns,
            "documentation label has no any-glob-to-all-files entries",
        )

        for pattern in REQUIRED_DOC_PATTERNS:
            self.assertIn(
                pattern,
                all_glob_patterns,
                f"Required pattern {pattern!r} is missing from the documentation label's "
                "any-glob-to-all-files list",
            )

    def test_sync_permissions_use_issues_only(self) -> None:
        header = self.read_text(".github/workflows/label-sync.yml").split("jobs:", 1)[0]

        self.assertIn("permissions:\n  contents: read\n  issues: write\n", header)
        self.assertNotIn("pull-requests:", header)

    def test_backfill_permissions_use_pull_request_read(self) -> None:
        header = self.read_text(".github/workflows/label-backfill.yml").split("jobs:", 1)[0]

        self.assertIn(
            "permissions:\n  contents: read\n  issues: write\n  pull-requests: read\n",
            header,
        )

    def test_pr_labeler_keeps_pull_request_write(self) -> None:
        header = self.read_text(".github/workflows/pr-labeler.yml").split("jobs:", 1)[0]

        self.assertIn(
            "permissions:\n  contents: read\n  pull-requests: write\n",
            header,
        )

    def test_pr_labeler_uses_supported_labeler_action(self) -> None:
        workflow = self.load_yaml(".github/workflows/pr-labeler.yml")
        steps = workflow["jobs"]["label"]["steps"]
        labeler_steps = [
            step
            for step in steps
            if step.get("uses", "").startswith("actions/labeler@")
        ]

        self.assertEqual(len(labeler_steps), 1)
        self.assert_uses_action_at_least(
            labeler_steps[0].get("uses"),
            "actions/labeler",
            MINIMUM_LABELER_MAJOR,
        )

    def test_shared_label_maintenance_uses_supported_checkout(self) -> None:
        for workflow_path, job_name in (
            (".github/workflows/label-sync.yml", "sync"),
            (".github/workflows/label-backfill.yml", "backfill"),
        ):
            workflow = self.load_yaml(workflow_path)
            steps = workflow["jobs"][job_name]["steps"]
            checkout_steps = [
                step
                for step in steps
                if step.get("with", {}).get("repository") == "JuliaQUBO/.github"
            ]

            self.assertEqual(
                len(checkout_steps),
                1,
                f"{workflow_path} should check out shared label automation once",
            )
            self.assert_uses_action_at_least(
                checkout_steps[0].get("uses"),
                "actions/checkout",
                MINIMUM_SHARED_CHECKOUT_MAJOR,
            )


if __name__ == "__main__":
    unittest.main()
