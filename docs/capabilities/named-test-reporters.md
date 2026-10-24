---
type: Capability
title: "Attempt-bound named assertion evidence"
description: "Connect optional Tasty or Hspec reporters to prove exact selected, executed, skipped, and failed test identities."
capabilityId: CAP-7
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni", "heni-tasty", "heni-hspec"]
interface: ["Test.Heni.Tasty.heniMain", "Test.Heni.Hspec.heniHspec", "Test.Heni.Adapter", "adapter: heni-v1"]
tags: ["mutation-testing", "haskell"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:59:21Z
reviews:
  - kind: model
    reviewer: codex/gpt-6
    reviewed_at: 2026-10-24T23:01:10Z
    document_timestamp: 2026-10-24T22:59:21Z
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
requires: ["CAP-4"]
evidence:
  - kind: test
    resource: test/adapter/Main.hs
    proves: "Exercises identity binding, incomplete/corrupt protocols, exact failure sets, and uncovered selection."
  - kind: test
    resource: adapters/heni-tasty/test/Main.hs
    proves: "Verifies Tasty reporter behavior with actual fixture execution."
  - kind: test
    resource: adapters/heni-hspec/test/Main.hs
    proves: "Verifies Hspec reporter behavior with actual fixture execution."
  - kind: example
    resource: examples/adapters/tasty.json
    proves: "Shows a portable named-test case using the dedicated protocol."
  - kind: guide
    resource: docs/user/named-test-guide.md
    proves: "Shows reporter installation and runnable Tasty/Hspec fixture campaigns."
---

# Attempt-bound named assertion evidence

Install the reporter matching your test framework and select the `heni-v1`
evidence protocol. A dedicated JSON Lines artifact binds observations to a fresh
run, case, role, stage, and attempt. A valid baseline passes intended tests; a
candidate must execute them and fail precisely the declared set. Colors and
stdout formatting are not the protocol.

Use either optional reporter package, not both unless your application needs
both frameworks. Direct execution outside Heni keeps native framework behavior.
Unfiltered discovery is unknown, and fail-fast/incomplete execution cannot prove
a complete named detection. The protocol assumes cooperating programs; it is not
attestation against a malicious executable.

Builds on [evidence-owned verdicts](attributable-verdicts.md) (CAP-4).
Follow the [reporter guide](../user/named-test-guide.md) and
[adapter reference](../user/adapters.md).
