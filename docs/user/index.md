---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Explanation

- [Evidence classification](classification.md) - Understand validity gates, evidence attribution, verdict precedence, and semantic scoring.

# Guide

- [Author a precise manifest case](authoring-cases.md) - Define a checked mutation, prove its baseline, and distinguish a caught fault from a false positive.
- [Implement verified build reuse in Haskell](build-reuse-guide.md) - Connect a content-aware GHC build wrapper to BuildReuse and reject stale observations before running tests.
- [Gate CI and retain mutation evidence](ci-guide.md) - Use campaign exit codes as the CI gate and preserve portable reports for diagnosis and recovery.
- [Attribute a native crash from Haskell](crash-guide.md) - Place a fresh reachability probe and distinguish real signals from missing probes, numeric exits, and timeouts.
- [Register checked custom edits in Haskell](custom-edit-guide.md) - Implement a trusted WorkspaceOps transformation and register it with its matching CustomEdit key.
- [Write controls and expected compiler rejection in Haskell](expectation-guide.md) - Run unchanged controls and real compiler rejection without confusing them with semantic detection.
- [Embed Heni in Haskell](haskell-integration.md) - Build a typed campaign, run it with explicit options, and let the application interpret the result.
- [Moving a mutation script to Heni](migration-guide.md) - Migrate existing mutation scripts while preserving consumer-owned faults and witnesses.
- [Install named-test evidence and replay](named-test-guide.md) - Connect Tasty or Hspec reporters and verify exact named assertion failures with runnable fixtures.
- [Consume campaign results and reports in Haskell](report-consumption-guide.md) - Gate applications from RunResult, read validated StoredReport values, inspect evidence, and recover journals honestly.
- [Configure workers and consumer resources](resource-guide.md) - Introduce bounded concurrency and scoped fixtures, then opt into reuse only with complete identities.
- [Understanding results](troubleshooting.md) - Diagnose verdicts, infrastructure errors, interrupted runs, and invalid evidence.

# Navigation

- [Heni user documentation](overview.md) - Choose a tutorial, task guide, explanation, or reference for deliberate mutation testing.

# Reference

- [Named assertions, replay and native probes](adapters.md) - Look up named assertion, replay, and native crash evidence contracts.
- [Public API and ownership](api-contract.md) - Understand the public Haskell API and the ownership of definitions, hooks, execution, and evidence.
- [CLI and manifest reference](cli.md) - Look up manifest semantics, CLI commands, selection, output, and exit codes.
- [Compatibility evidence](compatibility.md) - Find recorded compiler, platform, package-bound, and archive compatibility evidence.
- [Manifest v1 through the Haskell API](manifest-reference.md) - Look up every portable manifest field, default, edit, expectation, and Haskell decoding boundary.
- [Process ownership and evidence](process-supervision.md) - Look up POSIX command supervision, output retention, timeout, and cleanup guarantees.
- [Campaign evidence and recovery](reports.md) - Look up portable report contents, journal recovery, artifact checks, and redaction.
- [Resources, workers and conservative reuse](scheduling.md) - Look up worker limits, scoped resources, baseline sharing, and verified build reuse.
- [Source capture and checked edits](workspaces.md) - Look up source capture, disposable workspace, checked edit, and patch contracts.

# Tutorial

- [First caught mutation and survivor](quickstart.md) - Run a passing baseline, a caught mutation, and a deliberate survivor.

