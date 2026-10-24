# Heni initial specification

Status: proposed design, 2026-10-24. There is no implementation yet. Command
examples, module boundaries, and manifest fields below describe the intended
interface and must be exercised in a prototype before becoming a released API.

## 1. Purpose and audience

Heni is a Haskell library and CLI for running deliberate mutations and verifying
that tests catch the intended faults. It helps authors answer: “Does this test
actually protect the behavior I care about?”

The intended users are Haskell package maintainers, application teams, compiler
and DSL authors, and maintainers of validators or evidence checkers. A user
should be able to add one useful mutation without first adopting a new test
framework or infrastructure stack.

Success means less runner code, more precise failure attribution, and mutation
evidence that another contributor can reproduce. A mutation score alone cannot
establish that a program is correct.

## 2. Distribution and portability

Publish a library package, `heni`, and a CLI package, `heni-cli`, whose executable
is named `heni`. Keep command-line parsing and terminal presentation dependencies
in the CLI package. Keep the core's dependency set small and its public types
independent of any one test framework. Verify package-name availability before
the first upload.

Both packages must build from their Hackage source distributions with Cabal and
released dependencies. Git, Nix, OKF, Mori, remote builders, and services such as
Kafka or PostgreSQL are optional integrations or consumer-supplied test resources.
They must not be required to use the generic library or run its core test suite.
The patch adapter may require Git and must declare that requirement explicitly.

The initial supported execution platforms are Linux and macOS. Path handling and
process supervision must be designed so Windows support can be added; document
platform limits explicitly until that support is tested. Select supported GHC
versions and dependency bounds from successful CI builds and current upstream
releases before publication. This specification does not invent those bounds.

## 3. First-release scope

The first release must support:

1. Curated source or fixture mutations with stable IDs and a human explanation.
2. Patch application, checked UTF-8 text replacement, and a Haskell API for
   custom transformations in an isolated workspace.
3. An unchanged baseline, explicit build/check and test stages, and nonempty
   test selection where the expectation names tests.
4. Precise expected failures, bounded subprocesses, and complete result records.
5. A library and CLI with identical execution and classification semantics.
6. Versioned JSON manifests and reports, readable terminal output, and CI exits.
7. Optional property-test replay hooks and explicitly declared crash probes.

Automatic AST mutation generation, a GHC plugin, distributed scheduling,
coverage-derived test selection, and framework-specific in-process test runners
are later extensions. Define seams for them without making them prerequisites
for the initial execution core. Most transformations and diagnostic expectations
remain in the consumer's repository.

Small invalid-input unit tests can continue to use their existing test framework.
Heni earns its place when a case needs mutation application, isolation, staged
execution, attribution, or durable evidence.

## 4. Core model and public library

Use the `Test.Heni` namespace. The top-level module should expose a small,
documented path from defining a case to obtaining a structured result. Proposed
internal responsibilities are:

| Responsibility | Contract |
| --- | --- |
| Case definition | Stable ID, description, tags, edits, stages, selection, expectation, and budgets. |
| Workspace | An immutable source snapshot and a disposable mutable workspace. |
| Edit | Checked transformations with explicit preconditions and touched files. |
| Process | Structured executable/arguments, working directory, environment overrides, budgets, and termination. |
| Expectation | A predicate over stage, exit/signal, selection evidence, and diagnostics. |
| Runner | Baselines, controls, scheduling, reset, cancellation, and classification. |
| Report | Versioned serializable results and evidence references. |

Prefer concrete data types and functions for common cases. Custom edit and
expectation hooks must return structured errors and evidence. Keep process,
workspace, and test-framework details behind explicit interfaces; avoid a large
typeclass hierarchy before multiple real consumers establish the need.

The CLI must call this library. It must not maintain a second outcome classifier.
The library must return results without calling `exitWith` or printing mandatory
terminal output. Supply a progress callback or event stream for callers that
want live feedback. Asynchronous cancellation must still terminate owned
children and close evidence files.

Haskell-only hooks may exceed the portable manifest vocabulary. The API must
describe that boundary honestly; every built-in manifest feature must have a
library equivalent, but arbitrary Haskell functions need not serialize to JSON.

## 5. Execution contract

For each selected case, the runner must:

1. Validate the manifest, referenced commands, paths, IDs, selectors, and budgets.
2. Snapshot the declared source inputs and record their identity. Define whether
   the snapshot includes committed files, dirty edits, and untracked files;
   never silently test HEAD when the user selected working-tree contents.
3. Prepare a disposable workspace with its own writable build directory and any
   declared resource setup. Record the effective build configuration.
4. Build and run the unchanged baseline for the same selection and configuration
   the mutant will use. Verify that the selected tests exist and pass.
5. Restore the pristine snapshot, apply exactly this case's edit sequence, and
   verify that the mutation changed the intended files.
6. Build or check the mutated candidate. Run the selected test command only when
   the declared expectation requires it and the preceding stage succeeded.
7. Evaluate the expected outcome using structured stage and failure evidence.
   Run any declared replay step, preserving the original and replay outcomes.
8. Write the case result and logs, then reset or discard the workspace. A failed
   reset invalidates reuse of that worker; continue only in a fresh workspace.

An unchanged baseline may be reused for cases with the same snapshot,
configuration, environment contract, and selector. An incremental build directory
may be reused within an isolated worker if every case starts from identical
source bytes and the build tool observes restored inputs correctly. Separate
workers must not share a writable candidate tree or build directory.

Support explicit no-op control cases. A no-op must leave bytes unchanged and its
tests must pass; controls are the sole exception to the changed-bytes rule. A
failed or timed-out control invalidates the run's confidence in its detections.
Baseline success and controls reduce false attribution but do not prove absence
of flakiness.

Source snapshots must exclude run outputs and build artifacts by default. The
report records inclusion/exclusion rules and the manifest, tests, configuration,
and runner version used. Cleanup must preserve logs needed to explain failures.
Heni must never restore a backup over a user's active checkout.

## 6. Edits and workspace boundaries

Text replacements declare a target file, old text, new text, and required match
count. The default match count is exactly one. Missing or ambiguous anchors and
an empty change are invalid mutations, not survivors or successful detections.
Apply multi-edit cases in a declared order; later edits observe earlier edits.

Patch application must be checked and atomic with respect to the case workspace.
A partially applied patch must not contaminate the next case. File creation and
deletion must have preconditions and appear in the recorded diff. Invalid UTF-8
must produce an explicit edit error; binary edits require a separate API.

All file mutations and working directories must stay inside the disposable
workspace. Reject absolute mutation targets, parent traversal, and symlink
escapes. Execute commands as an executable plus argument list, without implicit
shell interpolation. Shell scripts remain available through an explicit shell
command. A workspace isolates files; it is not an operating-system sandbox for
consumer-supplied commands or a way to roll back external service effects.

## 7. Expected failures and verdicts

The default semantic expectation is: the candidate builds, a nonempty selection
executes, and the named assertion fails. A plain nonzero subprocess exit is
insufficient. Standard test adapters should provide test IDs, selected/executed
counts, and named failures. Generic command expectations must declare the
accepted exit code and a specific diagnostic witness, and document their weaker
ability to distinguish assertion failure from setup failure.

| Result | Meaning |
| --- | --- |
| `caught` | The declared fault was detected through the required stage and witness. |
| `survived` | Valid mutation, passing baseline, and executed selection, but the required detection did not occur. |
| `invalid-mutation` | Edit preconditions failed, the patch is stale, or a required change was absent. |
| `uncovered` | A required selector matched no tests, or execution evidence shows the intended selection did not run. |
| `unexpected-build-failure` | A semantic mutant did not reach its test stage. |
| `wrong-failure` | The command failed through a different test, diagnostic, exit, or signal. |
| `timed-out` | A stage exceeded its declared budget. |
| `infrastructure-error` | Preparation, resource setup, process launch, reporting, or cleanup failed. |
| `not-run` | A selected case was skipped because execution stopped or its baseline failed. |

Record baseline and control failures as run-level failures with affected cases.
Every selected case must appear exactly once in the final report, including
cases that never started. An invalid configuration is a configuration error,
with a diagnostic naming the field and case where possible.

An intentional build-rejection case must declare the build/check stage and
expected diagnostic. Report it as `caught` with detection kind
`expected-build-rejection`, separately from semantic test kills. An unrelated
compiler error does not satisfy that expectation.

A crash expectation must declare the accepted signal and a case-specific probe
showing that the intended native operation was reached. Generic crashes and
runner-enforced termination never count as successful semantic detections.
Timeouts remain distinct outcomes. Future hang-detection features require a
separate explicit contract.

For property cases, record the generator configuration and replay token. When
replay is required, the counterexample must reproduce the same named failure;
otherwise classify the result as `wrong-failure` with replay evidence.

## 8. Commands, adapters, and resources

The generic command interface is the baseline integration. Supply Cabal-oriented
examples and optional adapters for Tasty and Hspec. The generic core must not
depend on those test libraries or require migrating consumer test suites.

Each stage has a wall-clock budget, output policy, working directory, and
environment overrides. Distinguish a normal exit, signal termination, and
runner-enforced timeout. On timeout or interruption, terminate and reap the
owned process group where supported, using a bounded grace period. Specify and
test descendant-process behavior on each supported platform.

Setup/teardown hooks and resource concurrency limits must be explicit. Consumers
own broker, database, and other external fixtures. Parallel execution is opt-in
for cases using shared services unless the user declares independent resource
names or an appropriate concurrency limit. Avoid multiplying Cabal build jobs
by mutation-worker jobs without a documented resource budget.

## 9. CLI and portable manifests

The proposed command surface is:

```text
heni check heni.json
heni list heni.json
heni run heni.json --case guard-bypass --output mutation-results
heni run heni.json --tag regression --jobs 2 --output mutation-results
heni report mutation-results/report.json
```

`check` validates the definition and edit applicability without running mutation
tests. It must clearly distinguish static checks from test-discovery or baseline
execution, which may need a build. `list` explains IDs, tags, selectors, and
expectations. `run` records the selected cases and supports cancellation.
`report` renders stored evidence without rerunning commands. Selecting nothing
must be explicit in the output and fail `run` by default.

Use JSON as the initial interchange format, with a published JSON Schema and a
top-level `schemaVersion`. Reject unsupported versions and unknown keys to catch
typos. Commands are reusable named definitions; cases reference them by ID.
Describe defaults in the schema and include the effective values in reports.

This illustrative case uses a generic diagnostic expectation. It does not
provide the richer test-count and named-assertion evidence of a test adapter:

```json
{
  "schemaVersion": 1,
  "commands": {
    "build": {"executable": "cabal", "arguments": ["build", "example-tests"], "timeoutSeconds": 120},
    "test": {"executable": "cabal", "arguments": ["test", "example-tests", "--test-show-details=direct"], "timeoutSeconds": 30}
  },
  "cases": [{
    "id": "guard-bypass",
    "description": "Removing the capacity guard must be detected.",
    "tags": ["regression"],
    "edits": [{"kind": "replace", "path": "src/Capacity.hs", "old": "used < limit", "new": "True", "occurrences": 1}],
    "build": "build",
    "test": "test",
    "expect": {"kind": "diagnostic", "stage": "test", "exitCode": 1, "outputContains": "rejects full capacity: FAIL"}
  }]
}
```

Run the unchanged command with the same selector before using this expectation.
The example is a design sketch; release examples must be runnable and checked
against the actual manifest decoder and JSON Schema.

Proposed exit contract: `0` means every selected case met its expectation and
baselines/controls passed; `1` means a completed run failed that contract; `2`
means configuration or infrastructure prevented a trustworthy complete run.
On interruption, use the platform's documented interruption convention and
retain a partial report. Infrastructure errors take precedence over detected
survivors when selecting the overall exit status.

## 10. Reports, selection, and efficiency

The report must include schema and tool versions, source snapshot identity and
dirty-state policy, effective configuration, platform/tool versions, selected
IDs, case descriptions, applied diffs, stage durations, commands, outcomes,
diagnostic witnesses, selected/executed test counts when available, replay data,
and relative log paths. Record external resource versions when supplied by the
consumer. Do not dump the full inherited environment or credentials into reports.

Write progress and case results incrementally, then finalize the summary
atomically. Failed and cancelled runs must retain useful evidence. Allow output
retention and log-volume limits, but never silently truncate the witness used to
justify a detection. Reports should be portable with their referenced log files.

Start with explicit case and tag selection. Later changed-file selection must
account for tests, fixtures, the runner configuration, and source changes. When
impact cannot be established, rerun conservatively; a source-only filter can
miss a weakened test. Coverage-driven selection requires versioned coverage
provenance and must not silently drop missing mutation IDs.

Always show result counts and incomplete cases. If a semantic mutation score is
displayed, define it as caught semantic cases divided by caught plus survived
semantic cases, alongside the separate counts for invalid, uncovered, timed-out,
wrong-failure, and unrun cases. A score with unresolved cases must be labeled
incomplete and cannot make the CI gate pass. Report expected build rejections,
controls, and explicit reviewed exclusions separately. Do not automatically
declare an undetected mutation equivalent.

## 11. Validation and release criteria

The runner's own tests must cover false-positive classifications, baseline and
control failure, empty selection, ambiguous/no-op edits, partial patch failure,
restoration, timeout and cancellation cleanup, wrong named failures, replay
mismatch, partial reports, and worker independence. Use small self-contained
fixture packages or subprocesses; heavyweight services belong in optional
integration suites.

Before the first public release:

1. Demonstrate a useful case from a fresh standalone Cabal project using only
   released dependencies, through both the library and the CLI.
2. Exercise representative patch, replacement, named-test, diagnostic,
   intentional build-rejection, and replay cases. Run baseline/control checks
   and prove that wrong failures cannot produce a successful result.
3. Provide a quickstart, runnable examples, complete Haddock for exposed
   modules, manifest/report schemas, command help, and a troubleshooting guide
   for every outcome. The first successful mutation should take only a small
   manifest or a short Haskell definition.
4. Run `cabal check` for each package; build and test from extracted `cabal sdist`
   archives; build Haddock; verify examples and all required fixtures are in the
   archives. Validate against the advertised Linux/macOS and GHC matrix.
5. Include accurate package metadata, maintainer/contact and source links,
   changelogs, and a maintainer-selected open-source license and license file.
   Follow the Haskell Package Versioning Policy for public API changes. Choose
   tested dependency bounds and document compatibility.
6. Verify intended Hackage names, prepare candidate uploads, and review their
   rendered documentation and installability before publication. Publication
   itself is a later release action.

These are Heni's release quality criteria. Cabal's official
[packaging guide](https://cabal.readthedocs.io/en/stable/how-to-package-haskell-code.html)
and [command reference](https://cabal.readthedocs.io/en/stable/cabal-commands.html)
describe package construction, checks, source distributions, documentation, and
uploads; the [PVP](https://pvp.haskell.org/) defines versioning policy.

## 12. Delivery order and evidence of value

First implement the result model and classification fixtures, then isolated
workspaces and checked edits, followed by generic process execution. Add the
portable manifest and CLI through the same library entry point. Introduce test
adapters and replay only after the core can demonstrate the full baseline to
report cycle.

Validate extraction against the patterns in [RES-1](research/mutation-testing-survey.md):
one compact replacement runner, a patch catalogue, a generated-code mutation,
and an external-command diagnostic case. Preserve the specific expectation and
compare outcomes before and after migration. Keep these consumer migrations as
separate work from bootstrapping this repository.

Measure new-case authoring effort, shared versus consumer-specific runner code,
failure diagnosis effort, and elapsed build/test time independently. The initial
claim is reduced orchestration and more trustworthy verdicts; runtime speedups
must be measured. Keep unsupported cases and integration costs in the results.

Open design decisions include the minimum GHC matrix, license choice, exact
adapter output protocols, patch implementation, resource-hook API, and which
report fields become stable in version 1. Resolve them with prototypes and real
consumer evidence before committing to a broad public abstraction.
