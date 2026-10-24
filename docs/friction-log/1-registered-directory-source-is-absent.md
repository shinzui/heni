---
type: Friction Entry
title: "Registered directory source is absent"
description: "The Mori directory entry lacked source files, requiring an upstream source fetch before API inspection."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-24T15:14:31Z"
frictionId: FRIC-1
status: "accepted"
impact: detour
kind: environment
origin: "mori://shinzui/heni"
affects: "mori://haskell/directory"
affectedVersion: "unknown"
plan: "docs/plans/2-implement-isolated-snapshots-and-checked-mutations.md"
workaround: "Fetched System.Directory.hs from the official v1.3.10.1 tag into a temporary inspection file; verified current Hackage releases and upstream tags separately."
resolution: "Use authoritative upstream tagged source when a registered corpus checkout is absent; the dependency API and released version were verified."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-24T15:17:15Z"
    change: "Accepted documented upstream fallback for an absent corpus checkout."
---
# Registered directory source is absent

## Attempted

mori registry show haskell/directory --full followed by a scoped source file inventory

## Encountered

The registered path had no Haskell source files or curated documentation.

## Workaround

Fetched System.Directory.hs from the official v1.3.10.1 tag into a temporary inspection file; verified current Hackage releases and upstream tags separately.
