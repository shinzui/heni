---
type: Capability
title: "Strict manifests and shared command-line execution"
description: "Validate portable versioned manifests and use one CLI to check, select, run, and inspect shared-library campaigns."
capabilityId: CAP-5
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni", "heni-cli"]
interface: ["heni check", "heni list", "heni run", "heni report", "Test.Heni.Manifest"]
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
requires: ["CAP-1", "CAP-4"]
evidence:
  - kind: module
    resource: src/Test/Heni/Manifest.hs
    proves: "Strictly decodes versioned manifests and lowers definitions into the library."
  - kind: test
    resource: heni-cli/test/Main.hs
    proves: "Exercises library/CLI parity, exits, selection, machine output, check/list non-execution, moved reports, and SIGINT."
  - kind: example
    resource: examples/minimal/heni.json
    proves: "Provides caught, survivor, and unrelated compiler-error definitions."
  - kind: guide
    resource: docs/user/cli.md
    proves: "Specifies commands, path bases, defaults, selection rules, and exit meanings."
  - kind: guide
    resource: docs/user/manifest-reference.md
    proves: Worked Haskell adoption with compiled example source.
  - kind: example
    resource: examples/haskell-guides/GuideManifest.hs
    proves: Runnable public-API recipe with checked expected outcomes.
---

# Strict manifests and shared command-line execution

Use the `heni` executable from `heni-cli` for literal command definitions,
checked edits, and the same classifier as the Haskell API. Repeated case/tag
selection preserves definition order; bounded workers override manifest settings.
`run` exits 0 for a trustworthy met contract, 1 for contract failure, 2 for
configuration/infrastructure failure, and 130 for handled SIGINT.

Manifests reject unknown and duplicate keys, invalid references, and unsupported
versions. `check` tests structure, tools, and edit applicability without running
builds/tests; `list` reads definitions. Stored report rendering never reruns the
campaign. Arbitrary Haskell callbacks and build observation verifiers are not
serializable manifest features.

Builds on [typed campaigns](typed-campaigns.md) (CAP-1) and
[evidence-owned verdicts](attributable-verdicts.md) (CAP-4).
Follow the [quickstart](../user/quickstart.md) or [CLI reference](../user/cli.md).

See the [worked Haskell reference](../user/manifest-reference.md) and its compiled example.
