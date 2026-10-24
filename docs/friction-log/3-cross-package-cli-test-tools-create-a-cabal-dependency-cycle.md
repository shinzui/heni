---
type: Friction Entry
title: "Cross-package CLI test tools create a Cabal dependency cycle"
description: "Cabal rejected the core migration test when its CLI build tool depended back on the core package."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-24T17:38:41Z"
frictionId: FRIC-3
status: "accepted"
impact: detour
kind: tooling
origin: "mori://shinzui/heni"
affects: "mori://haskell/cabal/packages/cabal-install"
affectedVersion: "3.16.1.0"
plan: "docs/plans/8-prove-representative-script-migration-and-usability.md"
workaround: "Keep migration trials opt-in, build the CLI separately, and supply HENI_CLI_EXE to the Haskell integration test; release CI runs the wrapper."
resolution: "Keep the cross-package migration gate explicit, supply a separately built CLI, and preserve default core archive independence; repository CI runs the gate."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-24T18:10:16Z"
    change: "Accepted the explicit integration boundary instead of a cyclic core build-tool dependency."
---
# Cross-package CLI test tools create a Cabal dependency cycle

## Attempted

cabal test heni:heni-migration --enable-tests --dry-run

## Encountered

The default diagnostic omitted the test plan; explicit enable-tests exposed a cyclic qualified build-tool dependency through heni-cli.

```text
rejecting: heni:heni-cli:exe.heni:*test (cyclic dependencies)
```

## Workaround

Keep migration trials opt-in, build the CLI separately, and supply HENI_CLI_EXE to the Haskell integration test; release CI runs the wrapper.
