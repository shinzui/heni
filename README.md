# Heni

**Heni is a Haskell library and CLI for running deliberate mutations and verifying that tests catch the intended faults.**

A passing test tells you that the current implementation satisfies an assertion.
Heni asks the next question: would that assertion notice a particular bug?
Remove a guard, reverse an ordering rule, drop a cleanup action, or corrupt a
fixture, then require the expected test or diagnostic to detect the change.

Heni is being designed for Haskell library authors, application teams, and tool
maintainers who want repeatable mutation tests with clear evidence.

## The name

**Heni** comes from the Japanese **変異** (*hen’i*), meaning “mutation” or
“variation.” The package name drops the apostrophe for a short Haskell package
name and command: `heni`.

## Project status

Heni is in the specification stage. This repository currently contains the
initial design and research; the Haskell library and executable are planned.

The publication goal is two Hackage packages:

| Package | Purpose |
| --- | --- |
| `heni` | An embeddable mutation-testing library under `Test.Heni`. |
| `heni-cli` | The `heni` executable, using the same execution and verdict logic. |

These are intended distribution names, subject to availability before release.
Installation instructions and runnable examples will accompany the first release.

## What Heni will provide

- **Small, deliberate mutations.** Describe a known fault with a patch, checked
  text replacement, or Haskell-defined transformation.
- **Trustworthy verdicts.** Require the intended test failure or diagnostic;
  distinguish timeouts, build errors, and infrastructure failures.
- **Isolated runs.** Apply changes in disposable workspaces while preserving the
  source checkout and resetting each case to its baseline.
- **Existing test suites.** Run Cabal components and other commands, with optional
  adapters for test selection and failure attribution.
- **Reproducible evidence.** Retain source identity, commands, logs, outcomes, and
  property-test replay information in human-readable and versioned JSON reports.
- **A practical CI interface.** Check mutation definitions quickly, run selected
  cases, and fail clearly when a required mutation survives or cannot be verified.

The first release will focus on curated mutations and a dependable execution
core. Broader automatic mutation generation is a later extension point. The
library should be useful from ordinary Cabal projects, with optional Nix and
repository-tool integrations.

## Design and evidence

- [Initial specification](docs/initial-spec.md): proposed API boundaries, CLI,
  execution contract, outcome semantics, and Hackage release criteria.
- [Research](docs/research/index.md): the source survey and extraction assessment
  that motivate the design.

The research includes existing production-test patterns, the duplication in their
runners, and failure modes Heni should prevent. The initial specification turns
those findings into a public library and CLI contract.

## Working on the design

Issues and contributions should include a concrete mutation, the test or
diagnostic expected to detect it, and the evidence a runner needs to distinguish
that detection from an unrelated failure. API proposals should work for an
ordinary Haskell project as well as for the repositories in the research survey.

The research bundle follows the published OKF research-document profile. To check
the repository metadata and research:

```sh
mori validate
okf validate docs/research --strict --profile docs/research/profile.dhall --profile-enforce --log-enforce
```

OKF and Mori are documentation-maintenance tools. The public Heni library and
CLI will have no runtime requirement on either tool.
