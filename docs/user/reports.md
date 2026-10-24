---
type: Reference
title: "Campaign evidence and recovery"
description: "Look up portable report contents, journal recovery, artifact checks, and redaction."
docId: DOC-10
tags: ["reports", "json", "recovery"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: src/Test/Heni/Report.hs
  - resource: test/runner/Main.hs
---

# Campaign evidence and recovery

For an executable Haskell reader, application gate, and JSON export recipe, use
[Consume campaign results and reports in Haskell](report-consumption-guide.md).

`mkCampaign` checks cases, commands, references and Haskell edit registrations.
`runCampaign` validates the requested nonempty selected ledger, executable
availability and output location before execution. ConfigurationFailure is
separate from a runtime result. The output directory is exclusively created;
existing evidence is never merged or overwritten by a new run. Runtime IO,
observation and cleanup failures are retained as infrastructure information.

The serial path uses a fresh workspace for every baseline and candidate. A
baseline has the same commands, environment and selector; HENI_SELECTOR carries
the declared selector to a command or adapter. Generic commands must implement
their own selection and do not invent framework counts. Baseline failure stops
its candidate. Build rejection runs the unchanged build successfully first.
Tests run only after a successful candidate build when the expectation requires
them. Every process, including optional Git patch check/apply, uses the same
bounded supervisor. Custom evidence hooks can supply selection/replay facts but
cannot replace actual process outcome, unavailable-evidence flag, diagnostic
witness, duration or log references.

RunOptions provides an observation callback and an explicit workspace cleanup
hook invoked for both baseline and candidate before built-in disposal. Cleanup
errors retain observed candidate stages and invalidate confidence. Hooks are
trusted cooperative IO; arbitrary uninterruptible code is outside the process
supervisor's containment contract. Later resources compose their own lifetimes
with this lifecycle rather than choosing another verdict path.

The selected ledger is written before cases start. Each journal record contains
a sequenced complete ledger snapshot plus effective context, after source
capture, stage observations and case completion. Pending work is explicitly
NotRun. Cancellation finalizes interrupted and queued IDs before rethrowing its
original exception. The final JSON is written to a unique temporary file and
renamed atomically within the owned report directory. This prevents partial
JSON reads; it does not guarantee persistence through power loss or disk refusal.
Final-write failure returns an untrustworthy in-memory result with best-effort
existing journal evidence.

Version-one codecs use explicit keys and tags. Reports include tool/schema
versions, source identity and policy defaults, platform/compiler, definitions,
effective command budgets/output limits, case changes, baseline/candidate
process observations, durations, diagnostic witnesses, optional test counts and
replay, secondary errors, log byte/truncation metadata and relative references.
Source changes record before/after hashes, executable bits and UTF-8 text when
available. Baseline and patch observations live under metadata.caseDetails;
the case result's evidence contains candidate classification inputs.

Environment override values are always redacted in portable configuration;
inherited values are never recorded. Command.sensitiveArguments identifies
zero-based argument indexes whose values are replaced with `<redacted>`.
Redaction is explicit and means the report is not a complete secret-bearing
reproduction recipe. Consumer command output remains retained evidence: callers
must avoid emitting credentials in diagnostics or logs.

`readReport` checks versions, unknown fields, summary accounting, every baseline,
patch and candidate artifact's containment and existence, and symlink components.
Original JSON token streams reject duplicate keys (including escaped equal
spellings) before map conversion; nesting is bounded. `recoverReport` never
executes commands or writes over a report. It reads sequenced journal snapshots,
rejects interior corruption or semantic/schema/sequence errors, and tolerates
only an unfinished final non-newline record whose parser reaches end-of-input.
Recovered reports are explicitly untrustworthy even when their last snapshot
contained completed cases. Missing work never becomes caught. Relative artifact
references remain usable when the whole report directory moves.

The JSON Schema describes wire shape. The decoder additionally checks semantic
relationships, ledger uniqueness and recomputed summary status/score. Schema
validation is development-only Python tooling; neither the Haskell library nor
CLI requires Python. CI validates a real emitted fixture against Draft 2020-12.
