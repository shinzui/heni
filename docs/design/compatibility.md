# Compatibility evidence

Initial local validation uses GHC 9.12.4 and cabal-install 3.16.1.0 on
aarch64 macOS. The [official GHC release](https://www.haskell.org/ghc/blog/20260327-ghc-9.12.4-released.html)
confirms this is a released compiler. The initial CI matrix requests Linux and
macOS with this compiler; writing that job is not evidence it ran remotely.
GHC2024 and the GHC 9.12 minimum follow the project standard at
mori://shinzui/haskell-jitsurei/docs/core-standards.

Dependency lookup on 2026-10-24 used `mori registry list`, `registry search`,
`registry show --full` and `registry docs`. Source exports were inspected in
mori://haskell/text and mori://haskell/containers (Data.Text and Data.Set;
file-level artifact URIs pending). Their registry records have no curated
guides. Authoritative Hackage preferred-version JSON reports text 2.1.4 and
containers 0.8.1 as the latest normal releases. Upstream Git tags confirm
text `2.1.4` at `423fd981e576bd17a8b5fa48d0ad6b9a0c370e77` and containers
`v0.8.1` dereferenced at `953428ad079d5708df696442f9bdeaccd1acfc6c`.

The initial locally tested dependency set is base 4.21.2.0, text 2.1.4 and
containers 0.7. Bounds admit base 4.21.2 only within its major release,
text 2.1.4 within 2.1, and containers 0.7–0.8. Broader containers bounds use
stable shared operations; they are not a claim that all admitted versions have
been tested. EP-9 owns final bound testing and the advertised release matrix.
No local checkout pin or unreleased dependency is required by Cabal.
