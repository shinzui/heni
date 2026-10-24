---
type: Guide
title: "Gate CI and retain mutation evidence"
description: "Use campaign exit codes as the CI gate and preserve portable reports for diagnosis and recovery."
docId: DOC-18
tags: ["ci", "exit-codes", "reports", "artifacts"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: heni-cli/app/Heni/Cli.hs
  - resource: heni-cli/test/Main.hs
  - resource: src/Test/Heni/Report.hs
---

# Gate CI and retain mutation evidence

Build the CLI and target test dependencies before the mutation job. An offline
target command requires those dependencies to be available to fresh workspaces.
Use the compiler/platform combinations in [compatibility](compatibility.md).
Start with a small selected fault whose unchanged test already passes.

For a CI shell with `set -e`, explicitly retain the run status while collecting
artifacts. This example uses a caller-relative output path, which must be new:

```sh
cabal build heni-cli:exe:heni
heni_exe=$(cabal list-bin heni-cli:exe:heni)
heni_exit=0
"$heni_exe" run examples/minimal/heni.json \
  --case guard-bypass --output .heni-runs/ci-caught --json \
  > heni-result.json || heni_exit=$?
# Configure your CI to upload heni-result.json and all of .heni-runs/ci-caught/,
# including report.json, journal records, and relative logs, even on failure.
exit "$heni_exit"
```

Use a unique job/attempt path on repeated or shared workspaces. If an output
location sits inside captured source, exclude it with `sourcePolicy.excludes` or
use a default-excluded name. The example uses `.heni-runs`, which is excluded.
The redirected `heni-result.json` sits at the repository root; for a consumer
manifest whose source root includes that file, redirect outside the source or
exclude it as well. The minimal example captures only `examples/minimal`.

| `run` exit | Meaning | CI action |
| --- | --- | --- |
| 0 | Trustworthy campaign met every selected contract. | Pass this gate. |
| 1 | Mutation contract failed, including a survivor or wrong failure. | Fail and inspect case evidence. |
| 2 | Configuration or infrastructure failure. | Fail and repair execution or definitions. |
| 130 | SIGINT interruption with partial finalization. | Treat as interrupted and keep evidence. |

Do not derive the gate from a percentage alone: unresolved cases, failed baselines,
and controls matter. `check` checks structure and applicability without running
builds/tests; `list` only reads definitions. Neither substitutes for `run`.
`report` can render a failed run successfully and exit 0, so its exit is not the
campaign status. Machine output is on stdout and diagnostics/progress on stderr.
Invoke the built executable directly when redirecting machine output so Cabal's
own build messages cannot enter the JSON file.

To inspect downloaded artifacts, keep the whole report directory together:

```sh
cabal run heni-cli:exe:heni -- report .heni-runs/ci-caught/report.json
cabal run heni-cli:exe:heni -- report .heni-runs/ci-caught --recover
```

Recovery reads the journal without resuming commands. Recovered evidence is
explicitly untrustworthy; run a fresh campaign for a passing gate. Missing or
escaping artifact paths and interior journal corruption are rejected. Command
metadata redacts environment values and declared sensitive argv indexes, while
raw logs and property counterexamples retain what the consumer emits. Keep
credentials out of those outputs. See [reports](reports.md) and
[troubleshooting](troubleshooting.md) for diagnosis.
