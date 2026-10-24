---
type: Friction Entry
title: "Fourmolu rejects nested explicit case braces"
description: "Fourmolu refused a compiling nested case expression because its formatted output changed the AST."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-24T15:24:25Z"
frictionId: FRIC-2
status: "accepted"
impact: detour
kind: tooling
origin: "mori://shinzui/heni"
affects: "https://github.com/fourmolu/fourmolu"
affectedVersion: "0.19.0.1"
plan: "docs/plans/3-supervise-bounded-processes-and-cancellation.md"
workaround: "Rewrote the expression as an indented local binding, preserving behavior, then formatted normally without unsafe mode."
resolution: "Use ordinary indented nested case bindings; Fourmolu then preserves the AST without unsafe formatting."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-24T15:24:36Z"
    change: "Accepted a local syntax workaround for the formatter AST mismatch."
---
# Fourmolu rejects nested explicit case braces

## Attempted

fourmolu -i test/process/Main.hs before committing the process suite

## Encountered

AST of input and AST of formatted code differ, at the nested case using explicit braces and semicolons.

## Workaround

Rewrote the expression as an indented local binding, preserving behavior, then formatted normally without unsafe mode.
