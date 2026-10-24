---
type: Navigation
title: "Heni user documentation"
description: "Choose a tutorial, task guide, explanation, or reference for deliberate mutation testing."
docId: DOC-1
tags: ["documentation", "navigation", "mutation-testing"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: README.md
---

# Heni user documentation

Heni checks whether your existing tests detect deliberate faults. Start with one
meaningful edit and an exact failure witness. The implementation is experimental
and unreleased; the [compatibility reference](compatibility.md) records what has
actually been exercised.

## Learn the workflow

Follow the [quickstart](quickstart.md) to see a caught capacity fault and a
surviving marker change. Read [evidence classification](classification.md) to
understand why an unrelated compiler error or timeout cannot prove detection.
The [capability catalog](../capabilities/index.md) lists independently usable
contracts and their source, test, and example evidence.

## Complete a task

- [Author your first manifest case](authoring-cases.md).
- [Embed Heni in a Haskell application](haskell-integration.md).
- [Write unchanged controls and expected compiler rejection](expectation-guide.md).
- [Register checked custom Haskell edits](custom-edit-guide.md).
- [Attribute native crashes with Haskell probes](crash-guide.md).
- [Implement verified build reuse in Haskell](build-reuse-guide.md).
- [Consume results and reports from Haskell](report-consumption-guide.md).
- [Install named-test reporters and run the examples](named-test-guide.md).
- [Configure resources, workers, and baseline reuse](resource-guide.md).
- [Gate CI and retain diagnostic evidence](ci-guide.md).
- [Move an existing mutation script](migration-guide.md).
- [Diagnose a result or recover an interrupted run](troubleshooting.md).

## Look up a contract

| Reference | What it answers |
| --- | --- |
| [CLI and manifests](cli.md) | Commands, selection, defaults, and exit codes. |
| [Manifest v1 through Haskell](manifest-reference.md) | Every portable field, default, edit/expectation variant, and decoding boundary. |
| [Public Haskell API](api-contract.md) | Definitions, hooks, options, and ownership. |
| [Source and edits](workspaces.md) | Capture policy, paths, replacements, patches, and isolation. |
| [POSIX supervision](process-supervision.md) | Budgets, signals, logs, and cleanup. |
| [Reports and recovery](reports.md) | Portable artifacts, journals, and trust. |
| [Adapters, replay, and crash probes](adapters.md) | Exact test identities and reproduction evidence. |
| [Resources and reuse](scheduling.md) | Capacities, epochs, sharing keys, and build observation. |
| [Compatibility](compatibility.md) | Recorded compiler, platform, and dependency evidence. |

All shell commands in these pages run from the repository root unless a step
explicitly changes directory. Repeating a campaign requires a fresh output path.
Schemas live in [schemas/](../../schemas/); runnable fixtures live in
[examples/](../../examples/).

Contributor material remains separate: [release preparation](../releasing.md),
[validation evidence](https://github.com/shinzui/heni/blob/master/docs/validation/release-readiness.md),
[architecture decisions](../adr/), [research](../research/index.md), and
[implementation plans](https://github.com/shinzui/heni/tree/master/docs/plans).
The generated `index.md` lists pages by reader intent. Each page carries a stable
DOC handle in its frontmatter.
