---
type: Guide
title: "Embed Heni in Haskell"
description: "Build a typed campaign, run it with explicit options, and let the application interpret the result."
docId: DOC-15
tags: ["haskell", "library", "integration"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: examples/library/Definitions.hs
  - resource: examples/library/Main.hs
  - resource: examples/standalone/Main.hs
  - resource: src/Test/Heni/Runner.hs
---

# Embed Heni in Haskell

Depend on the core `heni` library in the executable that owns mutation campaigns.
The current packages are unreleased; the checkout's `cabal.project` and
[independent consumer](../../examples/standalone/consumer.cabal) demonstrate local
package wiring. Follow the package's [compatibility bounds](compatibility.md).
Enable the threaded runtime (`ghc-options: -threaded`) in an embedding executable
because the supervisor drains output concurrently.

Use [Definitions.hs](../../examples/library/Definitions.hs) as a complete typed
campaign. Its construction sequence is:

1. Use smart constructors for case/command IDs, relative targets, and stage budgets.
2. Define build/test `Command` values and put them in a map keyed by command IDs.
3. Construct `CaseDefinition` values with edits, references, an expectation, and
   an evidence mode. Pair ordinary definitions with `noHooks`.
4. Pass the map and definitions to `mkCampaign`; handle `Left ConfigError` before
   execution. The fixture's `checked` helper is for fixed example definitions.
5. Call `runCampaign` with options based on `defaultRunOptions`, then interpret
   the returned `RunResult` in the application.

The [complete example main](../../examples/library/Main.hs) imports the validated
campaign and runs:

```haskell
result <- runCampaign
  (defaultRunOptions "examples/minimal" ".heni-runs/library-guide")
  exampleCampaign
print result
```

Run that example from this checkout:

```sh
cabal run heni:exe:heni-library-example -- --output .heni-runs/library-guide
```

Its three cases deliberately produce caught, survived, and unrelated build
failure evidence. The example prints the result; it does not implement a CI exit
gate. Production callers should handle `RunResult.status`, run failures, and case
results explicitly, or use the [CLI CI gate](ci-guide.md).

Update named fields on `defaultRunOptions` to choose selection, workers, progress,
and resources. A progress callback observes events; it does not own verdicts, and
its exceptions can invalidate a run. The source path and output path are explicit
library arguments. Put outputs outside captured inputs or exclude them through
`sourcePolicy`.

Keep serializable case data separate from trusted `CaseHooks`. Register each
`CustomEdit` key with its matching hook, use checked `WorkspaceOps`, and leave
snapshotting, lifecycle, classification, and reports to Heni. Hooks can perform
arbitrary IO and must cooperate with cancellation. They are not a containment
boundary. [API contracts](api-contract.md), [resource/reuse contracts](scheduling.md),
and the [standalone main](../../examples/standalone/Main.hs) cover the next steps.

For worked Haskell integrations, use the [manifest reference](manifest-reference.md),
[controls and compiler rejection](expectation-guide.md),
[custom edit hooks](custom-edit-guide.md), [native crash probes](crash-guide.md),
[verified build reuse](build-reuse-guide.md), and
[typed report consumption](report-consumption-guide.md). Their compiled source is
in [examples/haskell-guides/](../../examples/haskell-guides/).
