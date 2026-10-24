---
type: Friction Entry
title: "Haddock instance origins link to hidden module pages"
description: "Haddock generated broken local links for public instances defined in non-exposed modules, requiring selective implementation documentation."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-24T19:03:48Z"
frictionId: FRIC-5
status: "accepted"
impact: detour
kind: tooling
origin: "mori://shinzui/heni"
affects: "https://github.com/ghc/ghc/tree/ghc-9.12.4-release/utils/haddock"
affectedVersion: "2.32.0"
plan: "docs/plans/9-validate-portable-packages-and-prepare-the-hackage-release.md"
workaround: "Generate only the two non-exposed definition pages via --show, mark them not-home and explicitly document their unsupported implementation status; keep Cabal exports unchanged."
resolution: "Selectively generate the two non-exposed definition pages, mark them not-home and keep installed module exports unchanged; all 19 core module/source link checks now pass."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-24T19:05:03Z"
    change: "Verified public API coverage and local links after the supported Haddock --show workaround."
---
# Haddock instance origins link to hidden module pages

## Attempted

Build Hackage documentation from extracted archives and check local module/source links.

## Encountered

Public CommandId instances linked to Test-Heni-Internal-Model.html even though Cabal hid that module page.

```text
AssertionError: Test-Heni-Command.html -> Test-Heni-Internal-Model.html; Haddock instance-origin rendering calls ppModule unconditionally.
```

## Workaround

Generate only the two non-exposed definition pages via --show, mark them not-home and explicitly document their unsupported implementation status; keep Cabal exports unchanged.
