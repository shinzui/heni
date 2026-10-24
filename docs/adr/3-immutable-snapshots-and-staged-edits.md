# Immutable snapshots and staged edits

Status: accepted. Date: 2026-10-24.

The selected working tree is the source of truth. Capture names, bytes,
executable bits and policy into an immutable content-identified value, then
materialize exclusive disposable workspaces. Never back up and restore over
the active checkout. Snapshot identity covers policy as well as bytes, and
double capture rejects observed concurrent changes without claiming an atomic
filesystem snapshot.

Apply an entire edit sequence before publishing a candidate to the runner.
Recompute the actual final inventory; hook declarations are not proof of byte
changes. Reject no-op mutations, changed controls, symlinks, special files and
edits to runner-owned metadata. Keep stale mutation errors distinct from IO or
cleanup infrastructure errors. Optional patch subprocesses use the shared
supervisor; Git is not a core runtime requirement for other edits.

The first implementation stores immutable bytes in memory and rejects source
symlinks. These deliberate limits simplify ownership and make active-checkout
preservation independently verifiable. A capability API constrains ordinary
hooks but is not a security sandbox for arbitrary IO. Reset failure invalidates
worker reuse, and fresh workspaces remain the default.
