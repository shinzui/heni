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

Report support uses released aeson 2.3.2.0, verified against Hackage preferred
versions and upstream tag `v2.3.2.0` at
`682162c66d26a770fbfb6271c797e646bc5c4f2e`. Mori source inspection at
mori://haskell/aeson covered explicit object codecs and the exposed JSON token
stream; token validation rejects duplicate keys before map conversion. The
development-only schema checker uses jsonschema 4.26.0, verified against PyPI
and upstream `v4.26.0` at `c87a92202e986be7e3ae0db992cdc2608bbfd815`.
The Haskell runtime does not depend on that Python tooling.

Optional reporters were checked against released Tasty 1.5.5, tasty-hunit
0.10.2, Hspec/hspec-core/hspec-api 2.11.18 and QuickCheck 2.19.0.0. Mori's
mori://UnkindPartition/tasty source supplied public runner/fold/ingredient APIs.
Its newest core tag is `core-1.5.4` (`0394c73e647834829e7f500c9dab0be3ff9e4f11`),
so the actual Hackage 1.5.5 archive was also inspected rather than assuming tag
parity. `hunit-0.10.2` is `298f69b99b7f1561c93e0eff87dde57be5bbb079`.
Hspec and QuickCheck had no owning Mori corpus entries; authoritative source
at Hspec `2.11.18` (`96242bf996b3eccc10cfe3406c16ffcb519b422d`) and
QuickCheck `2.19` (`3d8fe8686024760006ca1ca656cbdd82cd71f11e`) supplied
the stable V2 formatter and native replay APIs. Hackage preferred versions
were checked separately. STM 2.5.3.1 was inspected at mori://haskell/stm and
verified against `v2.5.3.1` (`48bfb8812633e9b9d4fd1cdeb4c795cefb8f8014`).

The core scheduler now uses the same verified released STM 2.5.3.1 API for
atomic queue/claim transitions; no async framework or application effect stack
is required. Worker processes and resource commands retain the shared POSIX
supervisor. Timing observations and explicit per-build job limits are recorded
in [scheduling](scheduling.md), separately from compatibility claims.

Cabal's current normal Hackage release was independently checked as 3.18.2.0
(upstream `cabal-install-v3.18.2.0`, dereferenced
`45f982c12ef78ea8ec5beb43cb8c71c8e8f237c1`). Local measurements still use
3.16.1.0 (`cabal-install-v3.16.1.0`, dereferenced
`8d1f5a33662be0db0654061fb53fb00e3f4417e0`). The qualified build-tool test
cycle was observed on 3.16.1.0, not asserted to have been reproduced on 3.18.2.0.
Mori supplied solver source at mori://haskell/cabal/packages/cabal-install-solver;
the optional integration boundary also preserves standalone core tests regardless
of the solver version.
