---
type: Guide
title: "Author a precise manifest case"
description: "Define a checked mutation, prove its baseline, and distinguish a caught fault from a false positive."
docId: DOC-14
tags: ["manifest", "authoring", "diagnostics"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: examples/minimal/heni.json
  - resource: schemas/manifest-v1.schema.json
  - resource: src/Test/Heni/Manifest.hs
---

# Author a precise manifest case

Start with the [minimal manifest](../../examples/minimal/heni.json). Put your own
manifest beside the target project, or set `sourceRoot` relative to the manifest
file. Keep build/test working directories and edit paths relative to that source
root. Commands contain an executable and literal arguments; shell operators in
an argument have no special meaning.

1. Run the unchanged project's build and selected test directly. It must pass.
2. Choose one fault whose meaning you can explain and a diagnostic unique to the
   intended assertion. Keep a stable case ID when its definition evolves.
3. Declare the edit's exact precondition and the expected stage, exit, and witness.
   A semantic test expectation still requires a successful candidate build.
4. Check applicability, then execute the selected case in a new output directory.
5. Inspect its verdict and retained witness. Add a harmless survivor to make sure
   the runner does not accept every changed file as detection.

The minimal fixture's case has this shape inside the root `cases` array:

```json
{
  "id": "guard-bypass",
  "description": "The capacity assertion must detect removal of the guard.",
  "tags": ["regression"],
  "edits": [{
    "kind": "replace", "path": "src/Capacity.hs",
    "old": "used < limit", "new": "True", "occurrences": 1
  }],
  "build": "build",
  "test": "test",
  "expect": {
    "kind": "diagnostic", "stage": "test", "exitCode": 1,
    "outputContains": "rejects full capacity: FAIL"
  }
}
```

`build` and `test` refer to root `commands` entries, as shown in the full fixture.
They are required definitions, so this fragment alone is not a manifest. An exact
one-occurrence replacement is the default. Ordered edits see earlier edits; the
final bytes must differ. Create requires an absent path; delete requires exact
old contents. [Source/edit contracts](workspaces.md) describe the supported Git
patch subset and trusted custom Haskell hooks.

```sh
cabal run heni-cli:exe:heni -- check examples/minimal/heni.json
cabal run heni-cli:exe:heni -- run examples/minimal/heni.json --case guard-bypass --output .heni-runs/author-caught
cabal run heni-cli:exe:heni -- run examples/minimal/heni.json --case survivor --output .heni-runs/author-survivor
cabal run heni-cli:exe:heni -- run examples/minimal/heni.json --case compile-error --output .heni-runs/author-build-error
```

Expect `caught`/exit 0, `survived`/exit 1, and `unexpected-build-failure`/exit 1,
respectively. `check` verifies structure, host tools, and edits in disposable
copies; it does not prove builds, tests, or baselines pass. Refresh stale anchors
instead of relaxing their counts. If compiler rejection is the intended outcome,
use its explicit expectation with a precise compiler diagnostic.

Use [named-test reporters](named-test-guide.md) when you need exact executed IDs.
Generic diagnostics retain unknown test counts. For generated code, mutate its
input before generation or use an explicitly verified consumer workflow; see the
[migration guide](migration-guide.md). Use the [CLI reference](cli.md) and
[manifest schema](../../schemas/manifest-v1.schema.json) for complete fields.
The [manifest reference for Haskell callers](manifest-reference.md) documents all
defaults and variants, including [controls and compiler rejection](expectation-guide.md).
