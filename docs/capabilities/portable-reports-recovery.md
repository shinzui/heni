---
type: Capability
title: "Portable reports and explicit journal recovery"
description: "Retain versioned reports with relative artifacts and recover an explicitly untrustworthy snapshot without executing commands."
capabilityId: CAP-6
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni"]
interface: ["Test.Heni.Report.readReport", "Test.Heni.Report.recoverReport", "heni report"]
tags: ["mutation-testing", "haskell"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:16:53Z
reviews:
  - kind: model
    reviewer: codex/gpt-6
    reviewed_at: 2026-10-24T23:16:53Z
    document_timestamp: 2026-10-24T23:16:53Z
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: gpt-6
    effort: unspecified
    context: >-
      Author self-review against the listed local source, test definitions, and
      examples, including evidence-path and dependency-link checks. Availability
      means implemented on the default branch, not a Hackage release. No
      independent approval or new execution of every cited test is claimed.
evidence:
  - kind: module
    resource: src/Test/Heni/Report.hs
    proves: "Checks report versions, accounting, artifact containment, and journal recovery."
  - kind: test
    resource: test/runner/Main.hs
    proves: "Exercises portable moved reports, recovery, truncated tails, corruption, missing artifacts, and reporting failures."
  - kind: guide
    resource: docs/user/reports.md
    proves: "Describes retained evidence, relative artifacts, atomic final writing, and recovery limits."
  - kind: guide
    resource: docs/user/report-consumption-guide.md
    proves: Worked Haskell adoption with compiled example source.
  - kind: example
    resource: examples/haskell-guides/GuideReports.hs
    proves: Runnable public-API recipe with checked expected outcomes.
---

# Portable reports and explicit journal recovery

Retain a report envelope and append-only sequenced journal with definitions,
source identity, observations, witnesses, durations, changes, effective budgets,
and relative log references. Readers validate versions, summary accounting,
containment, and artifact existence. Move the whole output directory to inspect
it elsewhere.

Recovery reads existing journal snapshots and never resumes commands. It tolerates
only an incomplete final record and rejects interior corruption; recovered results
are explicitly untrustworthy. Atomic final rename does not guarantee durability
through disk refusal or power loss. Metadata redacts environment values and
marked argv, while consumer-emitted logs can still contain sensitive data.

See the [report reference](../user/reports.md) and [CI guide](../user/ci-guide.md).
The optional `heni report` rendering surface is delivered by `heni-cli`.

See the [worked Haskell guide](../user/report-consumption-guide.md) and its compiled example.
