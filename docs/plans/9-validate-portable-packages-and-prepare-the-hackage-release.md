---
id: 9
slug: validate-portable-packages-and-prepare-the-hackage-release
title: "Validate portable packages and prepare the Hackage release"
kind: exec-plan
created_at: 2026-10-24T14:33:09Z
intention: "intention_01m5q57803ea88q9ts1vv62h4r"
master_plan: "docs/masterplans/1-bootstrap-heni-for-trustworthy-mutation-testing-and-hackage-release.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-24T14:33:09Z
---

# Validate portable packages and prepare the Hackage release


This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Record implementation friction with `agents/skills/exec-plan/record-friction.ts` under this plan. Follow `agents/skills/exec-plan/ADR.md` before ADR changes, and distill durable decisions before completion. All commands below run from the repository root unless stated otherwise. Paths named as new files are planned artifacts, not claims that they already exist.


## Purpose / Big Picture


A user outside this repository can build and run Heni from its source archives using Cabal and released dependencies. Maintainers receive documented compatibility, complete package metadata and examples, and a concrete release-readiness bundle suitable for a later Hackage candidate/upload review.


## Progress


- [ ] M1: Supported OS/compiler/dependency combinations and package metadata are verified.
- [ ] M2: Extracted source archives build, test, document, and run standalone consumer examples without repository-only infrastructure.
- [ ] M3: Release-readiness evidence, documentation, and local candidate artifacts are complete for a later publication action.


## Surprises & Discoveries


None yet.


## Decision Log


No implementation decisions yet; the approach below is the initial proposed contract.


## Outcomes & Retrospective


To be filled during implementation, including acceptance evidence, remaining limits, and friction triage.


## Context and Orientation


Hard prerequisite: `docs/plans/8-prove-representative-script-migration-and-usability.md` Complete. The working tree now has the root `heni` library, `heni-cli/`, optional `adapters/heni-tasty/` and `adapters/heni-hspec/`, all core tests, and accepted migration examples. Read `docs/initial-spec.md` sections 2 and 11, the research index/records, and `docs/validation/migration-results.md` produced by the prerequisite.

A source distribution is the archive produced by Cabal containing everything required to build a package. A candidate artifact here is a locally validated source/docs archive ready for a later upload; no upload is implied. The Haskell Package Versioning Policy governs public API changes independently of JSON schema versions. Published compatibility means successful recorded builds, not a version range copied from a local development shell.

No local ADR existed at plan creation; by this stage read and link the actual architecture, protocol, resource, and migration ADRs. This plan records the tested compatibility/release policy and performs final durable-decision distillation. The optional Nix scaffold remains developer tooling; Hackage users must not need it.


## Plan of Work


### M1: Compatibility and metadata


Audit every package's exposed modules, dependency closure, version, synopsis/description, category, maintainer/contact, source repository links, license, license file, changelog, and included data/fixture files. Obtain the maintainer's license choice before claiming a distributable open-source package; do not guess a legal grant. Author/maintainer details must be supplied or verified from repository metadata. Prepare everything else while that selection is pending. Verify name availability and ownership for heni, heni-cli, heni-tasty, and heni-hspec against Hackage immediately before release preparation; a lookup is not a reservation and must be repeated before upload.

Use Mori to locate all dependency sources/docs, then compare Hackage releases and upstream tags before choosing final lower/upper bounds. Compile and test with the minimum supported GHC 9.12-series release and the newest stable compiler allowed by actual dependency support, on Linux and macOS. If a newer compiler is unavailable or unsupported, state that explicitly and advertise only successful combinations; do not fake a matrix to satisfy a goal. Test lower-bound and newest-allowed dependency sets for public packages, recording solver plans and package revisions. Ordinary users must not need source-repository-package pins, private packages, vendoring, or a patched compiler. Keep `-Werror` as an owned CI policy rather than a downstream release obstacle.

Extend `.github/workflows/ci.yml` with the supported matrix and separate core, optional framework, patch, and archive checks. Core tests must pass with no Git executable, Nix, Mori, OKF, shell/Python mutation runner, or live service. Patch tests explicitly require Git; adapter tests explicitly require their released frameworks. Document Windows as untested/unsupported rather than inferring support from successful compilation.

### M2: Extracted-source proof


Create `scripts/check-sdist.sh` to build all source archives, unpack into a fresh directory outside the checkout, construct a Cabal project containing only those extracted Heni packages, and build/test/Haddock there. All non-Heni dependencies must resolve from released package repositories. Prohibit symlinks or absolute references back into the source checkout. Test each primary package as a standalone consumer would: the core library without CLI/framework dependency closure, and the CLI with released-style resolution of its matching core archive. Optional reporter archives must build and run their own fixtures in the same clean procedure.

Create a fresh standalone Cabal consumer using only exposed Test.Heni modules and a small local target fixture. Run one caught case, one survivor, and one wrong-failure through the library, then the corresponding CLI manifest. Prove `heni --version` works without Git. Ensure examples, schemas, helper executables, README/license/changelog, and fixtures survive archive inclusion. Build documentation and inspect module links, examples, command help, and troubleshooting for every outcome. Use the actual archives as the proof artifact, not a build from the working tree after running sdist.

### M3: Release readiness


Finalize `README.md`, quickstart, complete exposed-module Haddock, CLI reference, manifest/report/protocol schemas, migration guidance, compatibility table, changelogs, and `docs/releasing.md`. Document how to prepare/upload a Hackage candidate later and inspect its rendered docs/installability before public publication. Consult the official Cabal packaging/command reference and PVP at execution time; do not guess current upload flags. Keep credentials and upload steps out of automated validation.

Write `docs/validation/release-readiness.md` recording revision, archive hashes, package and dependency versions, OS/GHC results, cabal check results, archive tests, example outcomes, schema agreement, and known limits. A failing core gate, unresolved false-positive bug, incomplete docs, missing license, or untested advertised platform blocks readiness. Successful local preparation does not mean Hackage candidate review or publication occurred. Distill durable context from all child Decision Logs, discoveries, and outcomes into `docs/adr/`, triage recurring friction, and reconcile the master-plan registry. Include an explicit later-release handoff for candidate review/publication and a separate migration roadmap.


## Concrete Steps


From the repository root, after metadata and fixtures are complete:

```bash
cabal build all
cabal test all --test-show-details=direct
cabal haddock all
cabal sdist all --output-directory=dist-release
sh scripts/check-sdist.sh
```

Run `cabal check` with each package directory as the working directory: `.`, `heni-cli`, `adapters/heni-tasty`, and `adapters/heni-hspec`. Resolve actionable warnings and record any intentional exception with its publication impact. The archive script must print the fresh extraction location and fail on a missing fixture, invalid schema/example, test failure, or dependency on the original checkout. Use bounded CI jobs and save concise evidence instead of full build logs in docs.

Before choosing versions or uploading later, check the current [Cabal packaging guide](https://cabal.readthedocs.io/en/stable/how-to-package-haskell-code.html), [Cabal commands](https://cabal.readthedocs.io/en/stable/cabal-commands.html), [Hackage](https://hackage.haskell.org/), and [PVP](https://pvp.haskell.org/).


## Validation and Acceptance


All advertised Linux/macOS and compiler combinations pass ordinary Cabal builds and relevant tests. Extracted archives independently build, test, and produce usable Haddock, with only released non-Heni dependencies. A fresh consumer completes both library and CLI paths and receives the expected 0/1/2 contract distinctions. Package names, metadata, license, dependency bounds, and included artifacts are verified with evidence. Framework integrations remain optional for core installation; missing Git affects only selected patch capability.

Inspect generated Haddock for exposed-module coverage and broken links, and run documentation examples rather than merely compiling code snippets. Re-run the false-positive, cancellation, workspace, partial-report, adapter/replay, and worker-isolation gates on the release artifacts. The readiness record must distinguish passed, failed, and not-run checks; no unchecked requirement can be marked complete. Candidate upload and rendered Hackage review remain explicitly pending later release actions, while local archive readiness is the completion boundary of this bootstrap.


## Idempotence and Recovery


Use versioned output locations and preserve the accepted archives and their hashes. Rerun failed archive checks in a new temporary directory. Never patch an archive after hashing it; rebuild from the corrected source and invalidate old acceptance. Do not upload, tag, push, or overwrite a published package as an incidental validation step. Missing maintainer metadata/license selection is a concrete release blocker, not permission to invent it. Other implementation and verification work can continue independently.


## Interfaces and Dependencies


Hard prerequisite: `docs/plans/8-prove-representative-script-migration-and-usability.md`. This plan owns final package/release metadata, compatibility documentation, CI matrix, source-archive validation, and local release-readiness evidence. Implementation defects discovered here remain obligations of the relevant owner and must be fixed with regression checks before readiness. It consumes all accepted APIs, schemas, fixtures, and migration outcomes.

No mandatory build dependency may point at the user's research/source corpus. Canonical Mori references belong in internal planning and research, while public package docs must provide enough context and ordinary upstream links for outsiders. Version changes follow PVP and explicit schema compatibility policy. Publication and actual consumer migrations are subsequent authorized actions, not hidden completion claims.
