# Local release readiness

Local source/archive readiness passed on 2026-10-24. The four packages have
validated source and documentation archives for a later Hackage candidate
review. No candidate upload, rendered Hackage review or publication occurred.

The source candidate is commit `bc25243d6fd84eb35aa444e407cce8ed86c69b3f`.
Readiness/plan/friction updates are excluded from the source archive input;
subsequent evidence-only commits do not change these candidate bytes. All four
packages are 0.1.0.0, BSD-3-Clause, author/copyright Nadeem Bitar (2026), maintainer
nadeem@gmail.com. The source repository URL matches the configured Git origin.

Source archives are retained locally in `dist-release/candidate-bc25243/`:

| Archive | SHA-256 |
| --- | --- |
| heni-0.1.0.0.tar.gz | `508295233e8f4606a01bdd1b617fcded775015d04006ced4956ebcf9a263731c` |
| heni-cli-0.1.0.0.tar.gz | `1f1a39e1b7805713d58d62e3b4af80a984b61b6d0120f92add64b6ecda661e86` |
| heni-tasty-0.1.0.0.tar.gz | `ec84fc2374de0665dfca77dcdebf8e1c4ee3518e67e0dc5bd5c8c07761e3a5b5` |
| heni-hspec-0.1.0.0.tar.gz | `cec31f9fa415906b1214bb43c55bd3c11ff4defb9026721fbe928858d33af6bc` |

Both fresh archive runs completed all 21 checks with their expected exits.
[Machine-readable evidence](release-validation.json) records every check,
duration, documentation hash, dependency version and solver-plan hash. Raw logs,
plans, emitted schema fixtures and portable campaign reports are retained in
`dist-release/accepted-macos-lower/evidence/` and
`dist-release/accepted-linux-newest/evidence/`. Failed/trial attempts are separate
and do not count toward acceptance.

| Accepted archive condition | Platform | GHC | cabal-install | Result |
| --- | --- | --- | --- | --- |
| Explicit direct lower bounds | aarch64 macOS 26.7 / Apple M1 Max | 9.12.4 | 3.16.1.0 | 21/21 passed |
| Explicit direct newest admitted versions | aarch64 Debian 12 / Linux 6.8.0 | 9.12.4 | 3.18.2.0 | 21/21 passed |

The newest set uses containers 0.8.1, directory 1.3.11.0 and process 1.6.30.0;
the lower set uses 0.7, 1.3.10.1 and 1.6.26.1 respectively. Other direct lower
bounds equal the latest admitted releases checked at preparation time. Exact
transitive package versions and Hackage source/Cabal hashes are in the evidence.
These runs do not claim every possible dependency combination.

Each run passed warning-free `cabal check` for all four packages; core-only
build/tests without Git, Nix, Mori, OKF or Python in executable search; a separate
required positive Git patch gate; CLI resolution against the matching core
archive; optional Tasty/Hspec suites; and all three packaged framework manifests.
The standalone consumer produced Caught, Survived and WrongFailure through the
library and CLI; CLI exit 2 was also checked for invalid selection. `--version`
worked without Git. The four migration families and richer adversarial cases
passed again from these archives.

All 17 exposed core modules and both optional reporter modules have 100%
Haddock coverage. Two non-exposed definition pages also have complete coverage;
all 21 generated Heni module/definition pages passed local module/source-file
link checks. Their docs archives are retained per platform with hashes in the
JSON evidence. CLI help, schemas, shared corpus and emitted report/protocol
fixtures passed. A copied Linux campaign report rendered successfully on macOS.

Archive projects contain only extracted Heni source packages and released
non-Heni dependencies. No checkout symlinks, absolute checkout backreferences,
source-repository pins or private packages are required. The core's reachable
component graph excludes CLI/Tasty/Hspec/reporter packages; Aeson brings
QuickCheck transitively. Owned-package `-Werror` passed in both archive runs.

The Linux environment used the official arm64 GHC image at
`sha256:a017c85d1557f6098cfb6356e13a4b9ef16dfd89010cd1708ac4e01251c95402`
with container init, in the task-owned `heni-release` profile. Its accepted
artifacts were copied back and the task container/VM stopped. Other running
profiles were left untouched.

Hackage preferred-version endpoints returned 404 for heni, heni-cli, heni-tasty
and heni-hspec on 2026-10-24. This does not reserve names or establish account
upload permissions; repeat the check and confirm permissions before upload.
Registry releases and upstream tags were checked independently from Mori's
local source corpus; see [compatibility](../user/compatibility.md).

Only GHC 9.12.4/base 4.21.2.0 is admitted. GHC 9.14/base 4.22, Windows and other
architectures are outside this release's validated claims. Tasty/Hspec remain
optional; released Aeson brings a transitive QuickCheck dependency. No generic
incremental build guarantee, detached-process sandbox, database rollback,
distributed execution or cross-run verdict cache is claimed.

Later release actions are account authorization, fresh name checks, candidate
source/docs uploads, rendered Hackage review, candidate installability review,
publication in dependency order and release tagging. Follow
[release preparation](../releasing.md). Actual consumer migrations and live
service acceptance remain a separate [roadmap](../user/migration-guide.md).

The remote workflow is configured, not locally executed as GitHub Actions. Its
current upstream action releases were verified against release metadata, tags
and input definitions: mori://actions/checkout at v7.0.1,
mori://actions/upload-artifact at v7.0.2 and mori://haskell-actions/setup at
v2.12.1. These are intended canonical owners; registry entries and tag-artifact
URI coverage are pending, so official upstream source was the fallback. Workflow-only
updates are outside the Cabal source archives.

Linux archive validation uses released cabal-install 3.18.2.0. Its official
aarch64 Linux binary archive was checked against SHA-256
`e4d940131ab0b78943a4b5ce64a9ef5acc452ea849df197787eaeecb1c3bf276`.
Cabal 3.14.1.1 passed core/runtime suites, but its selective Haddock options did
not produce the required pages (FRIC-6); it is not an accepted documentation
tool for this release gate. The checked script requires Cabal >=3.16.1.0.


GitHub Actions execution, the macOS newest-set archive run, the Linux lower-set
archive run, GHC 9.14, Windows and other architectures are not accepted matrix
results here. Earlier ordinary Linux lower-set suites passed, separately from
these immutable archive gates. Some external dependency Haddock interfaces were
unavailable locally; rendered Hackage dependency links remain part of later
candidate review. The successful local file-link checks do not claim that review.

The ADR distillation covers all nine child decision/discovery/outcome sections
in ADRs 1–10. All six friction entries are triaged accepted with concrete
mitigations. Recurring Cabal issues (FRIC-3, FRIC-4 and FRIC-6) resulted in an
explicit integration boundary, retained TLS/native build tools and an early
release-tool version check. No upstream messages or issues were sent.

After the evidence-only plan/readiness updates, `cabal sdist all` regenerated
all four source archives with byte-identical hashes. Strict friction validation
(6 entries), Mori configuration/sealed-Dhall validation and `git diff --check`
also passed. No further application changes followed the accepted archive runs.
