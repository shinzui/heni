---
type: Guide
title: "Understanding results"
description: "Diagnose verdicts, infrastructure errors, interrupted runs, and invalid evidence."
docId: DOC-4
tags: ["diagnosis", "verdicts", "recovery"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: src/Test/Heni/Result.hs
  - resource: src/Test/Heni/Report.hs
---

# Understanding results

`caught` requires the declared exit/signal and witness after the validity gates.
Generic diagnostic evidence has weaker attribution than a framework assertion.
Inspect the case definition, exact witness and relative logs. Build rejection,
explicit crash and controls are tallied separately from semantic detections.

`survived` means the valid candidate passed without the expected detection.
Strengthen the relevant assertion or review whether the deliberate fault tests
the intended behavior. Heni does not automatically declare equivalence.

`invalid-mutation` means an anchor/count, patch, creation/deletion precondition,
or final byte-change requirement failed. Refresh the edit against the selected
working tree. Multi-edit sequences see prior edits and must not undo themselves.
Only an explicit unchanged control is allowed to change no bytes.

`uncovered` means the intended named selection did not execute. Check exact test
IDs, filter configuration and skipped tests. Unknown counts are not zero counts;
generic commands cannot manufacture named-test evidence from stdout.

`unexpected-build-failure` means a semantic candidate failed to build and never
reached its assertion. Inspect compiler logs. If rejection itself is intentional,
declare a build-rejection expectation with a precise nonempty diagnostic.

`wrong-failure` means a different assertion, diagnostic, exit, signal or replay
was observed. Fix attribution rather than accepting arbitrary command failure.
Additional undeclared named assertion failures also invalidate a named detection.

`timed-out` means a stage exceeded its wall-clock budget. Diagnose the process
and resource state before increasing the budget. Output printed before a hang
does not turn timeout into detection.

`infrastructure-error` means launch, setup, protocol, output, observation,
reporting or cleanup could not be trusted. Inspect primary and secondary errors;
a named witness cannot override them. Command/environment metadata redacts
secrets, but consumer commands should not emit credentials into retained logs.

`not-run` accounts for selected work that could not execute, including failed
baselines, cancellation and queued work. Baseline/control failures also appear
at run level with affected IDs. Every selected ID must appear exactly once.

For interrupted runs, inspect report.json or use `heni report DIRECTORY
--recover`. Recovery reads evidence and never reruns commands. A truncated last
journal record can be ignored; interior corruption, wrong sequence/schema and
missing or escaping artifacts fail clearly. Move the whole directory with its
logs to keep reports portable. Recovery is explicitly untrustworthy, so run a
new campaign before relying on a passing CI result.

Existing output directories are refused. Choose a new location. If output is
inside the source tree, exclude it explicitly or use the default
mutation-results name. Source symlinks and special files are unsupported in the
first capture policy; select/exclude inputs explicitly instead of following
them silently. Disposable workspaces protect the active checkout, while external
service state and detached processes remain consumer responsibilities.

For generated code, inspect the final build artifact and its generator input.
The migration example changes input before generation; changing output before
a regenerating build can erase the intended fault. A surviving marker change
in the trial is deliberate and verifies the distinction.

A required replay mismatch remains `wrong-failure`, including a replay timeout;
the underlying Replay outcome and original failure are retained. Invalid
QuickCheck tokens become skipped/pending reproductions and cannot count as
caught. Multiple replay properties need a consumer-specific protocol rather
than the initial one-property helper.

For resource failures, inspect acquire/reset/release records and their command
logs. Both primary and teardown errors matter. Check that baseline and candidate
have equivalent identity/version/epoch and namespaced bindings. Worker capacities
also limit fixture acquisition. Separate Heni processes require external locking.
Unknown epochs disable baseline reuse; an unverified build observation or
unexpected generated source retires retained artifacts and invalidates the case.

`check` cannot prove an explicit `./...` build product already exists. It checks
contained syntax and defers availability until after build. A missing or
symlinked workspace program is a launch/infrastructure failure. Host tools are
still checked before a campaign starts.
