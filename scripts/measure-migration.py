"""Development-only, automated interface observations; never human effort timing."""
import argparse
import copy
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("--results", type=Path, required=True)
parser.add_argument("--cli", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
cli = args.cli.resolve()
(root / ".heni-runs").mkdir(exist_ok=True)
trial = json.loads(args.results.read_text())
assert len(trial["families"]) == 4, "a complete successful trial is required"
legacy = (root / "test/migration/Legacy.hs").read_text().splitlines()

def region(name):
    first = next(i for i, line in enumerate(legacy) if line.strip() == "-- BEGIN " + name)
    last = next(i for i, line in enumerate(legacy) if line.strip() == "-- END " + name)
    return {i for i in range(first + 1, last) if legacy[i].strip() and not legacy[i].lstrip().startswith("--")}

def timing(values):
    return {"repeats": len(values), "minSeconds": min(values), "maxSeconds": max(values), "medianSeconds": statistics.median(values)}

def stages(report):
    return [(name, observation["stage"]) for details in report["metadata"]["caseDetails"].values()
            for name, observation in details.items() if isinstance(observation, dict) and isinstance(observation.get("stage"), dict)]

families = []
authoring = []
diagnostic_negative = None
for family in trial["families"]:
    name = family["family"]
    before = region(name + "-orchestration") - region(name + "-definition")
    domain = region(name + "-definition")
    fixture = root / "examples/migrations" / name
    definition = json.loads((fixture / "heni.json").read_text())
    helper_loc = sum(sum(bool(line.strip()) and not line.lstrip().startswith("--") for line in p.read_text().splitlines()) for p in (fixture / "tools").glob("*.hs"))
    row = {"family": name, "comparisonLocalOrchestrationLOC": len(before) + 1,
           "comparisonDefinitionLOC": len(domain), "manifestLifecycleScaffoldingLOC": 0,
           "retainedDomainBuildHelperLOC": helper_loc, "legacyIntendedCaught": family["legacyIntendedCaught"],
           "legacyUnrelatedCompileAccepted": family["legacyUnrelatedCompileAccepted"],
           "typedFreshSeconds": family["typedFreshSeconds"], "cliParallelReuseSeconds": family["cliParallelReuseSeconds"],
           "wholeCampaignRepeatsPerCondition": 1, "outcomes": family["outcomes"]}
    for label, report in [("typedFresh", family["typedReport"]), ("cliParallelReuse", family["cliReport"])]:
        observations = stages(report)
        baseline = [s["durationSeconds"] for role, s in observations if role == "baseline-build"]
        row[label] = {"baselineBuildInvocations": len(baseline), "baselineBuildTiming": timing(baseline),
                      "sumBuildStageSeconds": sum(s["durationSeconds"] for _, s in observations if s["stage"] == "build"),
                      "sumAllStageSeconds": sum(s["durationSeconds"] for _, s in observations)}
    row["typedElapsedMinusStagesSeconds"] = row["typedFreshSeconds"] - row["typedFresh"]["sumAllStageSeconds"]
    families.append(row)
    samples = []
    with tempfile.TemporaryDirectory(prefix="migration-authoring-", dir=root / ".heni-runs") as scratch:
        scratch = Path(scratch)
        shutil.copytree(fixture, scratch / "source")
        for _ in range(3):
            started = time.perf_counter()
            value = copy.deepcopy(definition)
            new = copy.deepcopy(value["cases"][0])
            new.update(id="authoring-variant", description="A new harmless label change demonstrates a surviving case.")
            if name == "patch-catalogue":
                new["edits"] = [{"kind": "patch", "content": (fixture / "patches/survivor.patch").read_text()}]
            else:
                new["edits"] = [{"kind": "replace", "path": {"generated-code": "model.txt", "diagnostic-checker": "policy.txt"}.get(name, "src/Capacity.hs"), "old": "baseline", "new": "authoring-variant"}]
            value["cases"].append(new)
            value["sourceRoot"] = "source"
            manifest = scratch / "heni.json"
            manifest.write_text(json.dumps(value, indent=2) + "\n")
            checked = subprocess.run([str(cli), "check", str(manifest), "--json"], capture_output=True, text=True, check=True)
            assert json.loads(checked.stdout)["testsExecuted"] is False
            samples.append(time.perf_counter() - started)
        if name == "diagnostic-checker":
            wrong = copy.deepcopy(definition)
            wrong["sourceRoot"] = "source"
            wrong["cases"][0].update(id="wrong-diagnostic", edits=[{"kind": "replace", "path": "policy.txt", "old": "timeout=30", "new": "timeout=-1"}])
            manifest.write_text(json.dumps(wrong, indent=2) + "\n")
            checked = subprocess.run([str(cli), "run", str(manifest), "--output", str(scratch / "wrong-run"), "--json"], capture_output=True, text=True)
            assert checked.returncode == 1
            case = json.loads(checked.stdout)["result"]["cases"][0]
            observed = (scratch / "wrong-run/wrong-diagnostic-candidate-test.stdout.log").read_text().strip()
            assert case["verdict"] == "wrong-failure" and observed == "policy.timeout: duration must be positive"
            diagnostic_negative = {"verdict": case["verdict"], "expected": "policy.capacity: maximum must be positive", "observed": observed, "exit": 1}
    authoring.append({"family": name, "templateFieldsChanged": ["id", "description", "edits"], "validationCommands": 1,
                      "testsExecutedDuringCheck": False, "automatedSerializationAndCheck": timing(samples)})

report_root = Path(trial["evidenceDirectory"]) / "rich-cli"
diagnosis = []
for _ in range(5):
    started = time.perf_counter()
    stored = json.loads((report_root / "report.json").read_text())
    case = next(c for c in stored["result"]["cases"] if c["id"] == "wrong-named")
    expected = next(c for c in stored["metadata"]["definitions"] if c["id"] == "wrong-named")["expect"]["failures"]
    stage = next(s for s in case["evidence"]["stages"] if s["stage"] == "test")
    protocol = next(p for p in stage["logPaths"] if p.endswith("evidence.jsonl"))
    events = [json.loads(line) for line in (report_root / protocol).read_text().splitlines()]
    actual = [e["testId"] for e in events if e["kind"] == "failed"]
    assert case["verdict"] == "wrong-failure" and expected == ["suite/intended"] and actual == ["suite/other"]
    diagnosis.append(time.perf_counter() - started)

with tempfile.TemporaryDirectory(prefix="migration-reproduce-", dir=root / ".heni-runs") as scratch:
    started = time.perf_counter()
    result = subprocess.run([str(cli), "run", str(root / "examples/migrations/diagnostic-checker/heni.json"), "--output", str(Path(scratch) / "run"), "--json"], capture_output=True, text=True, check=True)
    reproduction_seconds = time.perf_counter() - started
    reproduced = json.loads(result.stdout)["result"]["cases"]
    assert [c["verdict"] for c in reproduced] == ["caught"]

measurement = {"operator": "automated Python observation of agent-authored fixtures; no human effort inference",
               "method": "nonblank/noncomment physical lines inside named Legacy.hs regions; local wrapper line included; definitions subtracted",
               "comparisonSharedOrchestrationLOC": len(region("shared-orchestration")), "platform": trial["platform"],
               "families": families, "authoring": authoring, "diagnosticRuleMismatch": diagnostic_negative,
               "diagnosis": {"artifactReads": 2, "expectedFailures": expected, "actualFailures": actual, "automatedReadTime": timing(diagnosis)},
               "reproduction": {"commands": 1, "case": "diagnostic-checker/invalid-capacity", "exit": 0, "verdict": "caught", "seconds": reproduction_seconds},
               "limits": ["Whole-campaign variance is not estimated from one run per condition.", "Fresh library and parallel/reuse CLI conditions differ.", "Elapsed-minus-stages includes copies, edits and report IO; it is not isolated CPU overhead.", "Authoring/diagnosis timings exclude human reasoning."]}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(measurement, indent=2) + "\n")
print("Recorded automated scaffolding, authoring/check, diagnosis, reproduction and runtime observations")
