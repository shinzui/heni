---
type: Guide
title: "Register checked custom edits in Haskell"
description: "Implement a trusted WorkspaceOps transformation and register it with its matching CustomEdit key."
docId: DOC-21
tags: ["haskell", "custom-edits", "hooks", "workspace"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:15:20Z
sources:
  - resource: examples/haskell-guides/GuideCases.hs
  - resource: src/Test/Heni/Edit.hs
  - resource: src/Test/Heni/Runner.hs
---

# Register checked custom edits in Haskell

Use declarative `Replace`, `Create`, `Delete`, or `Patch` when those describe the
fault. Use `CustomEdit key` for a consumer-owned transformation that needs Haskell
logic, such as changing generator input or validating several related anchors.
Keep snapshotting, subprocess supervision, verdicts, and reports with Heni.

A hook takes `WorkspaceOps`, checks its own semantic preconditions, then performs
checked reads/writes. This example requires exactly one guard, replaces it, and
shows creation/deletion with an exact deletion precondition:

```haskell
removeGuard :: H.WorkspaceOps -> IO ()
removeGuard ops = do
  let path = target "Subject.hs"
  original <- H.readTarget ops path
  unless (Text.count "used < limit" original == 1) (ioError (userError "expected one capacity guard"))
  H.writeTarget ops path (Text.replace "used < limit" "True" original)
  H.createTarget ops (target "hook-note.txt") "The consumer removed its capacity guard.\n"
  H.deleteTarget ops (target "hook-note.txt") "The consumer removed its capacity guard.\n"

runHooks :: FilePath -> FilePath -> FilePath -> FilePath -> IO ()
runHooks self ghc source output = do
  let d = definition "custom-guard" [H.CustomEdit "remove-guard"] diagnostic
      hooks = H.noHooks {H.customEdits = [("remove-guard", removeGuard)]}
      cs = commands self ghc "normal"
  -- A missing registration is rejected before any workspace or command exists.
  case H.mkCampaign cs [(d, H.noHooks)] of
    Left _ -> putStrLn "Missing custom hook rejected before execution."
    Right _ -> error "unregistered custom edit was accepted"
  result <- H.runCampaign (H.defaultRunOptions source output) (campaign cs [(d, hooks)])
  expectVerdicts [H.Caught] result
```

These functions use `import Test.Heni qualified as H`, `Data.Text qualified as
Text`, and the `target`, `definition`, and `campaign` helpers in
[GuideSupport.hs](../../examples/haskell-guides/GuideSupport.hs). See the complete
[GuideCases.hs](../../examples/haskell-guides/GuideCases.hs) for all imports.

```sh
cabal run heni:exe:heni-haskell-guides -- hooks .heni-runs/guide-hooks
```

The example first confirms `mkCampaign` rejects an unregistered key before any
command runs. The registered hook then produces `Caught` from the compiled
capacity assertion. The temporary note cancels its own creation, while the guard
change remains in the final inventory. A hook that leaves no final source change
is invalid for a mutation, regardless of any intermediate writes.

## Respect each operation's precondition

| Operation | Contract |
| --- | --- |
| `readTarget target` | Read an existing contained strict UTF-8 file. |
| `writeTarget target text` | Write an existing checked file; explicitly check old contents or anchors in the hook. |
| `createTarget target text` | Target must be absent. |
| `deleteTarget target expected` | Existing bytes must equal the declared old UTF-8 contents. |

Register the exact key once in `noHooks {customEdits = [(key, function)]}`. Duplicate
registrations and missing referenced keys fail during campaign construction.
`CaseDefinition` contains data; `CaseHooks` contains functions. `CustomEdit` cannot
be serialized into a portable manifest.

The final independent inventory, not a hook's claims, determines `FileChange`
evidence and whether bytes changed. Path checks reject links and reserved runner
paths. Throwing an ordinary IO exception from this hook is infrastructure failure;
it does not turn a rejected semantic precondition into a caught mutation. Prefer
a declarative edit when its built-in applicability diagnostics are sufficient.

Hooks are trusted cooperative IO. Using `WorkspaceOps` keeps these operations
checked, while arbitrary IO elsewhere in the hook can affect external state.
Do not copy backups over the source checkout or supply a verdict. For generated
artifacts, change input before generation or define a verified ordering that
preserves the intended artifact; see [migration patterns](migration-guide.md).
Hooks without a reusable identity disable compatible baseline sharing. Keep
fresh execution as the reference while introducing custom behavior.
