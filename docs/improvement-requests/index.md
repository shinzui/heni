---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Improvement Request

- [Reuse one incremental Cabal build per worker across baselines and candidates](reuse-one-incremental-cabal-build-per-worker-across-baselines-and-candidates.md) - A campaign over a large Cabal project pays a cold build for every distinct baseline, because baselines always run in a fresh workspace and the baseline key includes the case selector. Build the unchanged source once per worker in its retained build directory, run each selector's baseline tests against that build, and ship a Cabal build-reuse provider so a manifest can opt in.

