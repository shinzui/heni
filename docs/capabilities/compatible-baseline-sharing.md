---
type: Capability
title: "Conservative campaign-local baseline sharing"
description: "Share only successful baselines whose complete source, command, selection, environment, resource, and toolchain identities agree."
capabilityId: CAP-11
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni"]
interface: ["Test.Heni.Runner.ReuseBaselines", "RunOptions.reusePolicy", "execution.baselineReuse"]
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
requires: ["CAP-1"]
evidence:
  - kind: test
    resource: test/scheduler/Main.hs
    proves: "Proves 3-to-1 compatible baseline execution and selector/command/epoch/environment invalidation."
  - kind: module
    resource: src/Test/Heni/Internal/Baseline.hs
    proves: "Coordinates single-producer baseline publication and cancellation-aware waiters."
  - kind: guide
    resource: docs/user/scheduling.md
    proves: "Lists identity requirements, unknown-state refusal, provenance, and measured fixture limits."
---

# Conservative campaign-local baseline sharing

Opt in through `ReuseBaselines` or manifest `execution.baselineReuse` with a
nonsecret toolchain contract and, for structured suites, the exact producer.
Successful matching baselines can serve multiple cases/workers within one campaign.
The key includes snapshot/policy, commands, arguments, inherited/override environment,
selector, expectation/evidence mode, and resource identity/version/epoch.

Unknown resource epochs and unidentifiable custom hooks disable sharing. Consumers
assert external inputs are represented and tests do not semantically depend on
fresh run/case/attempt IDs. Secret comparisons stay in memory. Failures and cleanup
errors cannot publish success. This is not persistent cross-run verdict caching.
Reported fixture timings combine reuse and concurrency and imply no universal
consumer speedup.

Builds on [typed campaigns](typed-campaigns.md) (CAP-1).
Follow the [resource/reuse guide](../user/resource-guide.md) and
[sharing contract](../user/scheduling.md).
