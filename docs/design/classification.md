# Evidence classification

`classifyCase` is the only verdict function. It retains the complete
CaseEvidence, including secondary cleanup errors. It evaluates these gates in
order: invalid definition; infrastructure, cleanup or malformed protocol;
duplicate stage; stopped execution; missing/failed baseline; rejected or
unchanged mutation (or changed control); runner timeout; cancellation; required
stage and expectation. Stage order does not affect a verdict. Duplicate stages
are invalid evidence and cannot inflate counts.

A failed baseline yields `not-run` for its candidate and a run-level
BaselineFailure with affected IDs. A failing control yields its observed
case verdict and a ControlFailure. Neither contributes to semantic scoring.
Infrastructure takes precedence over matching diagnostic output. Setup and
teardown nonzero exits are infrastructure failures. Truncated stage output is
untrustworthy, including when an apparent witness survives truncation. Timeout
and runner cancellation never prove a crash or assertion detection.

Semantic expectations require a successful Build. A build failure is
`unexpected-build-failure`. Named tests additionally require known positive
selected/executed counts and execution of every intended ID without skipping.
Absent execution is `uncovered`; missing stage evidence is infrastructure.
Exit 1 with exactly the declared failed-ID set proves detection. Extra failed
assertions are `wrong-failure`; exit 0 with no failed IDs survives. Malformed
counts, failed IDs outside execution, and simultaneous executed/skipped IDs are
protocol infrastructure failures. Unknown counts never become zero counts.

A generic diagnostic requires the declared nonzero exit code and literal
nonempty output witness. Its counts remain unknown; its evidence strength is
explicitly GenericDiagnostic. Build-stage diagnostics and BuildRejection count
as ExpectedBuildRejection, separately from semantic detections. A CrashProbe
requires the declared signal and nonempty case-specific probe. It counts as
ExplicitCrash. A normal exit cannot substitute for a signal.

RequireReplay demands an identical token, generator configuration and exact
named failure set in the original and Replay stages, plus actual replay test
execution and exit 1. Missing or mismatched replay is `wrong-failure`.

`summarizeRun` accepts a validated selected ledger. It rejects duplicate or
foreign results, preserves selection order, and fills every missing result with
`not-run`. Baseline and control failures are deduplicated and retained at run
level. RunInfrastructure or an infrastructure case gives RunUntrustworthy;
interruption next gives RunInterrupted; any unresolved case or run failure gives
RunFailed. Only all-caught, baseline/control-valid runs pass. CLI exit mapping
belongs to its presentation owner.

The score numerator is caught semantic cases and its denominator adds survived
semantic cases. Other detection kinds never enter it. Zero denominator yields
Nothing. An unresolved case or run failure marks the ratio incomplete, even if
the visible fraction is one. Scores cannot make the CI contract pass.
