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

Workspace dependencies were checked on 2026-10-24. Hackage reports directory
1.3.11.0 (upstream `v1.3.11.0`, `bf2afc2ddf9d3bcf360ba2eec08d3deb70874c3a`),
process 1.6.30.0 (`v1.6.30.0`, `11fd247ad33208da7a914acf15d4a09d64a6a4c4`),
crypton 2.2.5 (`crypton-v2.2.5`, `74738d1c8da69649f3e629f49a964fe942a9e79a`),
bytestring 0.12.2.0 (`0.12.2.0`, `d984ad00644c0157bad04900434b9d36f23633c5`),
unix 2.8.8.0 (`v2.8.8.0`) and filepath 1.5.5.0. The locally tested workspace
set uses directory 1.3.10.1, bytestring 0.12.2.0, unix 2.8.8.0, filepath
1.5.5.0, process 1.6.26.1 (test helper) and released crypton 2.2.5. Latest
versions and tested versions are deliberately recorded separately.

Mori located source and hashing guidance at mori://kazu-yamamoto/crypton,
mori://haskell/bytestring and mori://haskell/process. The registered
mori://haskell/directory source was absent (FRIC-1 in docs/friction-log), so
System.Directory was inspected from the official v1.3.10.1 tag. Unix and
filepath had no owning registry entries; official tagged source was used for
POSIX file status, temporary directories, signal groups and path operations.
