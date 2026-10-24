# POSIX process groups own command lifetimes

Status: accepted. Date: 2026-10-24.

All external commands, including Git patch checks, setup, teardown and replay,
use the same supervisor. It owns a POSIX group, drains both pipes, enforces a
monotonic budget, terminates remaining group members even after the leader
exits, and bounds escalation, direct-child reaping and reader joins. Structured
exit/signal/timeout evidence takes precedence over terminal text. Cancellation
retains process evidence while preserving the original exception for the caller.

Bounded raw logs are presentation artifacts. Exact diagnostic witnesses are
scanned through all bytes and retained separately; invalid UTF-8 display
decoding must never create detection evidence. Observation failures and cleanup
failures remain infrastructure information, not successful detections.

Linux and macOS are the first target platforms; Windows is deliberately
unsupported. Ordinary POSIX groups do not contain detached descendants or
recover from runner SIGKILL. Document and test this boundary instead of
promising an OS sandbox. Consumers requiring stronger containment supply one.

Host executable availability is checked before a campaign. Explicit `./...`
programs are workspace-local build products: validate their contained relative
syntax at preflight and resolve them in the stage's checked cwd after build.
Reject runtime symlink escapes. Applicability checking can defer their existence
without running a build; this must not be presented as proof they already exist.
