---
type: Friction Entry
title: "Cabal 3.14 hides requested Haddock definition pages"
description: "Cabal 3.14.1.1 omitted requested implementation documentation despite --show, blocking the archive link gate until a released newer Cabal was used."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-24T19:22:08Z"
frictionId: FRIC-6
status: "accepted"
impact: detour
kind: tooling
origin: "mori://shinzui/heni"
affects: "mori://haskell/cabal"
affectedVersion: "3.14.1.1"
plan: "docs/plans/9-validate-portable-packages-and-prepare-the-hackage-release.md"
workaround: "Use a released cabal-install >=3.16.1.0 for archive documentation; Linux validation uses the checksum-verified official 3.18.2.0 binary."
resolution: "The archive gate checks for cabal-install >=3.16.1.0 before starting. Linux uses the verified official 3.18.2.0 release; core installation retains its ordinary Cabal format requirement."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-24T19:22:08Z"
    change: "Verified selective pages with newer released Cabal without patching the compiler or changing exposed modules."
---
# Cabal 3.14 hides requested Haddock definition pages

## Attempted

Generate selective implementation Haddock pages from extracted archives with --haddock-option=--show.

## Encountered

The pages were absent under Cabal 3.14.1.1 although the same GHC/Haddock versions generated them under Cabal 3.16.1.0 and 3.18.2.0.

```text
Test-Heni-Internal-Model.html and Test-Heni-Internal-Files.html absent under Cabal 3.14.1.1; both present after a focused Cabal 3.18.2.0 documentation run on the same extracted source.
```

## Workaround

Use a released cabal-install >=3.16.1.0 for archive documentation; Linux validation uses the checksum-verified official 3.18.2.0 binary.
