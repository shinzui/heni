---
type: Capability
title: "Evidence-owned verdicts and campaign accounting"
description: "Require valid baselines and precise attributable failures before accepting detection, and account for every selected case."
capabilityId: CAP-4
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni"]
interface: ["Test.Heni.Result.classifyCase", "Test.Heni.Result.summarizeRun"]
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
    resource: src/Test/Heni/Result.hs
    proves: "Implements verdict precedence and complete selected-ledger summary semantics."
  - kind: test
    resource: test/unit/Main.hs
    proves: "Exercises the classification truth table, unknown counts, missing stages, controls, replay, and run summaries."
  - kind: guide
    resource: docs/user/classification.md
    proves: "Explains validity gates, separate detection kinds, unresolved cases, and score completeness."
  - kind: guide
    resource: docs/user/expectation-guide.md
    proves: Worked Haskell adoption with compiled example source.
  - kind: example
    resource: examples/haskell-guides/GuideCases.hs
    proves: Runnable public-API recipe with checked expected outcomes.
---

# Evidence-owned verdicts and campaign accounting

Classify semantic diagnostic and named-test failures, explicit build
rejections, unchanged controls, and native crash probes using typed evidence.
Infrastructure, malformed protocol, invalid edits, failed baselines, timeout,
and missing execution cannot become successful semantic detection merely because
a command failed. Generic command test counts remain unknown.

Summaries preserve author selection order, reject duplicate/foreign results, and
fill missing work as `not-run`. Baseline/control failures remain run-level
failures. Build rejection and explicit crashes are separate from semantic score
counts; an incomplete ratio cannot make the campaign pass.

Use the [classification explanation](../user/classification.md) and
[troubleshooting guide](../user/troubleshooting.md) when interpreting results.

See the [worked Haskell guide](../user/expectation-guide.md) and its compiled example.
