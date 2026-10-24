---
type: Reference
title: "Manifest v1 through the Haskell API"
description: "Look up every portable manifest field, default, edit, expectation, and Haskell decoding boundary."
docId: DOC-19
tags: ["haskell", "manifest", "schema", "reference"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:15:20Z
sources:
  - resource: src/Test/Heni/Manifest.hs
  - resource: src/Test/Heni/Case.hs
  - resource: schemas/manifest-v1.schema.json
  - resource: examples/haskell-guides/GuideManifest.hs
---

# Manifest v1 through the Haskell API

Use `Test.Heni.Manifest` when a Haskell application wants portable case data
without owning a second runner. Construct typed cases directly when you need
custom functions; a manifest cannot serialize those functions. This reference
covers version 1 of the [manifest schema](../../schemas/manifest-v1.schema.json).
The decoder additionally validates references and semantic constraints.

## Decode, check, and run

Import `Test.Heni qualified as H`. The complete compiled
[GuideManifest.hs](../../examples/haskell-guides/GuideManifest.hs) uses:

```haskell
runManifest :: FilePath -> FilePath -> IO ()
runManifest source output = do
  decoded <- H.readManifest (source </> "heni.json")
  manifest <- either (ioError . userError . show) pure decoded
  applicable <- H.checkManifest manifest >>= either (ioError . userError . show) pure
  unless (all (\H.Applicability {H.applicable = good} -> good) applicable) (error (show applicable))
  -- Neither readManifest nor checkManifest runs builds or tests. The runner does.
  result <- H.runCampaign (H.manifestRunOptions output manifest) (H.manifestCampaign manifest)
  expectVerdicts [H.Caught] result
```

Run the example from the repository root:

```sh
cabal run heni:exe:heni-haskell-guides -- manifest .heni-runs/guide-manifest
```

Expect a single `Caught`. The [input manifest](../../examples/haskell-guides/target/heni.json)
builds and executes a real Haskell capacity assertion. Choose a fresh output path
for repeats. The example executable verifies expected outcomes and exits 0 when
those checks pass; campaign status is still a field of `RunResult`.

`readManifest :: FilePath -> IO (Either ConfigError Manifest)` reads and anchors
the source root to the manifest's directory. `decodeManifest :: ByteString ->
Either ConfigError Manifest` accepts at most 4 MiB and leaves that source root
unresolved; it has no manifest filename from which to infer a base directory.
Prefer `readManifest` for file-backed definitions. `checkManifest` checks static
validity, command availability, and edit applicability in disposable copies. It
does not run builds, test discovery, tests, or baselines.

`manifestCampaign` yields the validated `Campaign`. `manifestRunOptions output`
applies source policy, workers, resources/claims, and baseline reuse to runner
options. Pass its result to `runCampaign`; calling `defaultRunOptions` alone
would discard those manifest execution settings. A relative library output path
is relative to the calling process, independently of the manifest location.

## Root fields

Every object rejects unknown fields; duplicate JSON object keys are rejected
before map conversion. Required means no default. Optional does not imply that
explicit JSON `null` is allowed.

| Field | Required/default | Meaning |
| --- | --- | --- |
| `schemaVersion` | Required, integer `1` | Other versions are rejected. |
| `sourceRoot` | `"."` | Nonempty relative filesystem path based at the manifest directory; no NUL. This is distinct from a normalized edit target. |
| `sourcePolicy` | Default capture policy | Object with the fields below. |
| `commands` | Required object | Command definitions keyed by portable command ID. |
| `cases` | Required nonempty array | Unique case IDs, in author order. |
| `resources` | `[]` | Portable resource provider definitions. |
| `execution` | One worker, fresh baselines | Execution object described below. |

`sourcePolicy.includes` and `sourcePolicy.excludes` default to `[]`. Each is a list
of normalized relative file/subtree paths, not glob patterns. Empty includes
selects the root; exclusions and built-in excluded names still apply. Selected
regular files include dirty and untracked bytes. Symlinks and special files are
rejected. See [source capture](workspaces.md) for default exclusions and identity.

Case/command IDs are nonempty ASCII letters, digits, dots, underscores, and
hyphens. Relative edit targets, working directories, and policy paths reject
absolute paths, empty segments, `.`/`..`, backslashes, drive-colon syntax, and NUL.
Output must be outside captured inputs or explicitly excluded; source-root and
ancestor output directories are rejected. Existing output directories are refused.

## Command fields

| Field | Required/default | Meaning |
| --- | --- | --- |
| `executable` | Required string | Host executable or explicit contained `./workspace-program`; no implicit shell. |
| `arguments` | `[]` | Literal argv strings, without NUL; operators and wildcard characters are ordinary bytes. |
| `sensitiveArguments` | `[]` | Unique zero-based integer indexes into `arguments`, redacted in portable metadata. |
| `workingDirectory` | Omitted or `null` | Snapshot root; otherwise a normalized relative directory. |
| `environment` | `{}` | String-valued environment overrides with unique nonempty names excluding `=` and NUL. Other environment entries are inherited. |
| `timeoutSeconds` | `30` | Positive finite number, at most `86400`, rounded up to whole microseconds. |
| `outputLimitBytes` | `1048576` | Positive integer retained-byte limit per stdout/stderr stream. |

Environment values cannot be `null` to request removal. Values are redacted from
portable configuration; raw command output is retained as emitted. The Haskell
`Command` budget uses `StageBudget` microseconds, while the manifest uses seconds.
Reports record the effective microsecond budget. Host tools are checked before
execution. Workspace executables are checked structurally during applicability
and must exist after the build; symlink/traversal escapes fail at launch.

## Case fields

| Field | Required/default | Meaning |
| --- | --- | --- |
| `id` | Required | Unique portable case ID. |
| `description` | Required | Non-whitespace explanation of the intended fault. |
| `tags` | `[]` | Unique strings for consumer selection. |
| `edits` | `[]` | Ordered edits; must be nonempty unless the expectation is `control`. |
| `build` | Required | Reference to a defined command ID. |
| `test` | Omitted or `null` | Command reference; required for every expectation except `build-rejection` and build-stage `diagnostic`. |
| `selector` | Omitted or `null` | Non-whitespace selector passed as `HENI_SELECTOR`. Generic commands must implement their own selection. |
| `expect` | Required | Exactly one expectation variant from the table below. |
| `adapter` | Omitted or `null` | Generic commands; `"heni-v1"` selects the structured evidence protocol. |
| `resources` | `[]` | Unique names of declared resource providers claimed by this case. |

Library selection belongs to `RunOptions.selectedCases`; use `mkSelectedCases`
with known IDs. The manifest does not contain the CLI's `--case` or `--tag` flags.
Explicit selections must be nonempty, duplicate-free, and refer to campaign cases.

## Edit variants

Each variant requires its `kind` and the other listed fields. These are manifest
field names; the Haskell column names the matching public constructor.

| `kind` | Fields | Haskell and preconditions |
| --- | --- | --- |
| `replace` | `path`, `old`, `new`, optional `occurrences` default `1` | `Replace target old new count`: strict UTF-8, nonempty old text, different replacement, positive exact non-overlapping count. |
| `create` | `path`, `content` | `Create target contents`: target must be absent. |
| `delete` | `path`, `expected` | `Delete target expected`: target must contain exactly the declared UTF-8 text. |
| `patch` | `content` | `Patch patchText`: literal textual patch content, not a patch filename. Optional Git and the documented textual subset are required. |

Each edit sees prior edits. The final inventory must contain a real change;
a sequence that undoes itself is invalid. A control must declare no edits.
`CustomEdit key` is Haskell-only and rejected in manifests; see the
[custom hook guide](custom-edit-guide.md). [Workspace contracts](workspaces.md)
define the supported patch headers, path checks, and binary-file limits.

## Expectation variants

| `kind` | Fields/defaults | Haskell constructor and evidence |
| --- | --- | --- |
| `diagnostic` | `stage` is `build` or `test`; positive `exitCode`; nonempty `outputContains` | `Diagnostic stage code witness`: exact exit plus literal byte witness. Test-stage detection also requires a successful candidate build. Counts stay unknown. |
| `build-rejection` | Positive `exitCode`; nonempty `outputContains` | `BuildRejection code witness`: unchanged build succeeds; candidate compiler rejection must match. Test command may be absent. |
| `named-tests` | Unique nonempty `failures` IDs; `replayRequired` defaults `false` | `NamedTests ids NoReplay` or `RequireReplay`: requires `adapter: "heni-v1"`, complete attempt-bound execution, and the exact declared failure set. |
| `crash` | Positive integer `signal`; nonempty `probe` | `CrashProbe signal probe`: actual signal plus fresh probe identity; cannot use the structured test adapter. |
| `control` | No additional fields | `Control`: unchanged source, successful build and test. |

Build-stage diagnostics and explicit build rejection are counted separately from
semantic detections. A passing control is also a distinct detection kind. The
[expectation guide](expectation-guide.md) demonstrates the difference. Replay and
crash guides explain [native property replay](named-test-guide.md) and
[native signal evidence](crash-guide.md).

## Resource fields

| Field | Required/default | Meaning |
| --- | --- | --- |
| `name` | Required | Uppercase ASCII initial letter followed by uppercase letters, digits, or underscores; unique provider name. |
| `scope` | `"case"` | `"case"`, `"worker"`, or `"campaign"`. |
| `capacity` | `1` | Positive integer capacity for claims in this Heni process. |
| `identity`, `version` | Required strings | Nonempty consumer-owned fixture and version identities. |
| `epoch` | Omitted or `null` | Unknown external state; a known epoch must be nonempty. Unknown disables compatible baseline sharing. |
| `environment` | `{}` | String bindings whose names begin `HENI_RESOURCE_<NAME>_`; values are redacted in metadata. |
| `setup`, `reset`, `teardown` | Required | References to defined commands, each with its own budgets and output policy. |

Resource names are claimed through case `resources`. Only selected claims are
acquired. Consumer commands own real fixture allocation, partial-acquire cleanup,
reset semantics, and teardown. A directory copy does not roll back a service.
For typed callbacks, use `Test.Heni.Resource.managedResource` directly; a manifest
only carries the command-backed provider contract. See [resources](resource-guide.md).

## Execution fields

| Field | Default | Meaning |
| --- | --- | --- |
| `workers` | `1` | Integer `1` through `256`. The Haskell caller may explicitly update the lowered `RunOptions.workers`. |
| `baselineReuse` | Omitted or `null` | Fresh baselines. Otherwise an object with the following fields. |
| `baselineReuse.toolchain` | Required when opting in | Non-whitespace compiler/dependency/build contract identity. |
| `baselineReuse.adapter` | Omitted or `null` | Exact structured producer identity, required for structured-suite sharing. |

Sharing remains campaign-local and compares complete compatible identities.
Unknown resource epochs and unidentifiable hooks disable it. Retaining build
artifacts is a separate Haskell-only `RunOptions.buildReuse` provider, described
in the [verified build reuse guide](build-reuse-guide.md). No manifest field enables
that provider. After lowering, do not overwrite these execution options by
accident; update only the named `RunOptions` fields your application owns.

Explicit `null` is supported only for nullable fields: `test`, `selector`,
`adapter`, `workingDirectory`, resource `epoch`, `baselineReuse`, and its `adapter`.
All other optional fields use omission for defaults. Consume the eventual
`RunResult` through the [Haskell report guide](report-consumption-guide.md).
