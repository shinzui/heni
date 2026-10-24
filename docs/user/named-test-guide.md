---
type: Guide
title: "Install named-test evidence and replay"
description: "Connect Tasty or Hspec reporters and verify exact named assertion failures with runnable fixtures."
docId: DOC-16
tags: ["tasty", "hspec", "named-tests", "quickcheck", "replay"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: adapters/heni-tasty/test/fixture/Main.hs
  - resource: adapters/heni-hspec/test/fixture/Main.hs
  - resource: examples/adapters/tasty.json
  - resource: examples/adapters/property.json
---

# Install named-test evidence and replay

Use a reporter when the contract must prove exactly which tests executed and
failed. Add the matching local `heni-tasty` or `heni-hspec` package to the test
component while these packages are unreleased. Replace Tasty's `defaultMain` with
`Test.Heni.Tasty.heniMain`, or Hspec's `hspec` with `Test.Heni.Hspec.heniHspec`.
Outside an attempt those functions preserve ordinary framework execution.

Use `"adapter": "heni-v1"` on the case and declare:

```json
"expect": {
  "kind": "named-tests",
  "failures": ["suite/intended"],
  "replayRequired": false
}
```

That is a case-field fragment. Keep the existing edit and build/test command
references. Stable IDs join nested names with `/`; literal `~` and `/` inside a
name are escaped as `~0` and `~1`. Check the full IDs emitted by your test tree.
Selectors intersect with native test-command filters. The unchanged baseline
must execute and pass the intended tests; the candidate must fail exactly the
allowed set. Skipped or additional failed tests cannot satisfy the contract.

Run the repository fixtures from the root with these commands:

```sh
cabal build heni-cli:exe:heni heni-tasty:exe:heni-tasty-fixture heni-hspec:exe:heni-hspec-fixture
TASTY_FIXTURE=$(cabal list-bin heni-tasty:exe:heni-tasty-fixture)
HSPEC_FIXTURE=$(cabal list-bin heni-hspec:exe:heni-hspec-fixture)
export PATH="$(dirname "$TASTY_FIXTURE"):$(dirname "$HSPEC_FIXTURE"):$PATH"
cabal run heni-cli:exe:heni -- run examples/adapters/tasty.json --output .heni-runs/named-tasty
cabal run heni-cli:exe:heni -- run examples/adapters/hspec.json --output .heni-runs/named-hspec
cabal run heni-cli:exe:heni -- run examples/adapters/property.json --output .heni-runs/named-property
```

Each is expected to be caught with exit 0. The manifests invoke these fixture
executables by name, so their directories must be on PATH. They illustrate the
same reporter installation as a consumer test main.

For native Hspec/QuickCheck reproduction, wrap one selected property in
`heniProperty` with the enclosing full example ID, as in the
[Hspec fixture](https://github.com/shinzui/heni/blob/master/adapters/heni-hspec/test/fixture/Main.hs), and set
`replayRequired` to true. Heni reruns the native seed/size and generator contract
in a separate Replay stage on the candidate. Inspect both the original and
Replay observations. A missing token, changed configuration, wrong assertion, or
replay timeout rejects reproduction. The initial helper supports one selected
replay property per attempt.

If a reporter is missing, check executable wiring and the dedicated protocol
artifact. Parsing colored stdout cannot replace complete attempt-bound records.
See the [adapter reference](adapters.md) for protocol rules, custom replay builders,
and the separate native crash-probe contract.
