import pathlib
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]

COVERAGE_CONDITION = (
    "github.event_name == 'push' && github.ref == 'refs/heads/main' && "
    "matrix.version == '1' && matrix.os == 'ubuntu-latest'"
)


class CoveragePolicyTests(unittest.TestCase):
    def load_ci_job(self):
        workflow_path = ROOT / ".github" / "workflows" / "ci.yml"
        with workflow_path.open(encoding="utf-8") as file:
            workflow = yaml.safe_load(file)

        return workflow["jobs"]["test"]

    def test_only_main_current_ubuntu_collects_coverage(self) -> None:
        job = self.load_ci_job()
        steps = job["steps"]
        runtest = next(
            step
            for step in steps
            if step.get("uses", "").startswith("julia-actions/julia-runtest@")
        )
        process = next(
            step
            for step in steps
            if step.get("uses", "").startswith(
                "julia-actions/julia-processcoverage@"
            )
        )
        upload = next(
            step
            for step in steps
            if step.get("name") == "Upload coverage to Codecov"
        )

        self.assertEqual(
            job["env"]["COVERAGE_ENABLED"],
            f"${{{{ {COVERAGE_CONDITION} }}}}",
        )
        self.assertEqual(
            runtest["with"]["coverage"], "${{ env.COVERAGE_ENABLED }}"
        )
        self.assertEqual(process["if"], "env.COVERAGE_ENABLED == 'true'")
        self.assertEqual(upload["if"], "env.COVERAGE_ENABLED == 'true'")


if __name__ == "__main__":
    unittest.main()
