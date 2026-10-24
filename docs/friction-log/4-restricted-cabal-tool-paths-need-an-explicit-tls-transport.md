---
type: Friction Entry
title: "Restricted Cabal tool paths need an explicit TLS transport"
description: "Cabal transport auto-selection hid the missing curl capability behind failing HTTP mirrors during isolated archive validation."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-24T18:51:06Z"
frictionId: FRIC-4
status: "accepted"
impact: detour
kind: tooling
origin: "mori://shinzui/heni"
affects: "mori://haskell/cabal/packages/cabal-install"
affectedVersion: "3.14.1.1"
plan: "docs/plans/9-validate-portable-packages-and-prepare-the-hackage-release.md"
workaround: "Retain curl as a build/package transport tool in the restricted PATH while excluding Git, Nix, Mori, OKF and Python."
resolution: "The isolated build tool path must retain curl for TLS downloads; Heni runtime and core tests still exclude Git, Nix, Mori, OKF and Python."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-24T18:52:29Z"
    change: "Confirmed Cabal source transport selection and verbose HTTPS failure; retain a TLS-capable package transport."
---
# Restricted Cabal tool paths need an explicit TLS transport

## Attempted

Run core archive tests with a minimal executable PATH using cabal-install 3.14.1.1.

## Encountered

Without curl in PATH, the HTTPS origin failed with https not supported and fallback HTTP mirrors failed with 403.

```text
Exception user error (https not supported) when using mirror https://hackage.haskell.org/; Unexpected response 403 for http://objects-us-east-1.dream.io/hackage-mirror/package/directory-1.3.11.0.tar.gz
```

## Workaround

Retain curl as a build/package transport tool in the restricted PATH while excluding Git, Nix, Mori, OKF and Python.
