---
type: Reference
title: "Public API and ownership"
description: "Understand the public Haskell API and the ownership of definitions, hooks, execution, and evidence."
docId: DOC-6
tags: ["haskell", "api", "ownership"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: src/Test/Heni.hs
  - resource: src/Test/Heni/Runner.hs
---

# Public API and ownership

The root `heni` library exposes `Test.Heni` and focused Case, Command,
Expectation and Result modules. It has no direct test-framework dependency, mandatory
terminal output, process exit, or repository-tool requirement. IDs, relative
targets, budgets and selected ledgers have hidden constructors. Call
`validateCase` and `validateCommand` before execution; their `ConfigError`
names the rejected field. Case data and evidence use concrete strict records.

The minimal construction sequence is visible in `test/api/Consumer.hs`: create
IDs and a relative target, construct a `CaseDefinition`, validate it, then
classify evidence. That fixture uses synthetic evidence only. It covers a
replacement, textual patch catalogue, generated-code hook, and external
diagnostic. The model also expresses named tests, replay, build rejection,
unchanged controls and signal probes. The real campaign path is demonstrated in
`examples/library/` and the optional adapter packages.

`CaseDefinition` contains serializable data. `CaseHooks` holds trusted IO
functions separately. `WorkspaceOps` supplies checked reads and writes; the
workspace owner supplies checked creation/deletion. Arbitrary IO can escape
these operations: this is an API capability, not an OS sandbox. A custom
evidence callback returns evidence or a rejection; it cannot return a verdict.
The execution owner must preserve actual process outcome and all validity
gates when interpreting custom evidence.

The execution API is:

```haskell
runCampaign :: RunOptions -> Campaign -> IO RunResult
```

These argument types now live in `Test.Heni.Runner`. `mkCampaign` validates
commands, references and custom edit registrations. RunOptions includes
source/output locations, selection, an IO progress callback, and a cleanup hook
for each baseline/candidate workspace. Command.sensitiveArguments marks
zero-based argv indexes for report redaction; environment values are always
redacted from portable configuration. The workspace owner supplies scoped immutable
snapshots and independently checked changes. The process owner supplies actual
outcomes, bounded logs and durations as StageEvidence. The campaign owner
validates references, baselines and final accounting, then calls the pure
classifier and summary. The adapter owner supplies versioned selection and
replay evidence. The report owner writes explicit versioned codecs rather than
deriving a wire contract from Haskell constructor spelling. The CLI renders the
same RunResult and never classifies failures itself.

Later owners may extend these records before publication; update the model
tests and this contract together. The public import closure intentionally has
no generic-lens label orphan; `test/api/Labels.hs` compiles a consumer's own
overloaded label instance. The internal prelude exports only foundational
types, following the scoped adaptation in [the boundary ADR](../adr/1-framework-neutral-core.md).

`CaseDefinition.evidenceMode` declares generic commands or the strong v1
protocol. `CaseHooks.replayBuilder` can build a native framework replay command;
strong protocol facts remain authoritative even with a custom observer. See
[adapter contracts](adapters.md) for named identities, replay and fresh probes.

`RunOptions` also accepts bounded workers, scoped resources/claims and conservative
reuse policies. Construct from `defaultRunOptions` and update named fields; portable
callers use `manifestRunOptions`. [Scheduling contracts](scheduling.md) explain the
Haskell-only build observation provider and resource ownership boundaries.
