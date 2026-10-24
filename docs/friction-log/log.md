# Bundle Update Log

## 2026-10-24
* **Update**: FRIC-5 accepted: Verified public API coverage and local links after the supported Haddock --show workaround.
* **Addition**: FRIC-5 records detour tooling friction with https://github.com/ghc/ghc/tree/ghc-9.12.4-release/utils/haddock: Haddock instance origins link to hidden module pages
* **Update**: FRIC-4 accepted: Confirmed Cabal source transport selection and verbose HTTPS failure; retain a TLS-capable package transport.
* **Addition**: FRIC-4 records detour tooling friction with mori://haskell/cabal/packages/cabal-install: Restricted Cabal tool paths need an explicit TLS transport
* **Update**: FRIC-3 accepted: Accepted the explicit integration boundary instead of a cyclic core build-tool dependency.
* **Addition**: FRIC-3 records detour tooling friction with mori://haskell/cabal/packages/cabal-install: Cross-package CLI test tools create a Cabal dependency cycle
* **Update**: FRIC-2 accepted: Accepted a local syntax workaround for the formatter AST mismatch.
* **Addition**: FRIC-2 records detour tooling friction with https://github.com/fourmolu/fourmolu: Fourmolu rejects nested explicit case braces
* **Update**: FRIC-1 accepted: Accepted documented upstream fallback for an absent corpus checkout.
* **Addition**: FRIC-1 records detour environment friction with mori://haskell/directory: Registered directory source is absent
* **Adoption**: Adopt the `friction-log` profile (`coordination.frictionLog`) from https://raw.githubusercontent.com/shinzui/okf-profiles/v0.23.0/package.dhall.
