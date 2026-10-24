---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Friction Entry

- [Registered directory source is absent](1-registered-directory-source-is-absent.md) - The Mori directory entry lacked source files, requiring an upstream source fetch before API inspection.
- [Fourmolu rejects nested explicit case braces](2-fourmolu-rejects-nested-explicit-case-braces.md) - Fourmolu refused a compiling nested case expression because its formatted output changed the AST.
- [Cross-package CLI test tools create a Cabal dependency cycle](3-cross-package-cli-test-tools-create-a-cabal-dependency-cycle.md) - Cabal rejected the core migration test when its CLI build tool depended back on the core package.

