# Source capture and checked edits

`withSnapshot` reads selected working-tree files twice and rejects an observed
inventory change. This includes dirty edits and untracked regular files; it
does not read Git HEAD. Default exclusions at every depth are `.git`, `dist`,
`dist-newstyle`, `cabal-dev`, `.direnv`, `result`, `result-*`,
`mutation-results`, `.heni`, `.heni-*` and `.DS_Store`. Explicit relative
inclusion subtrees and exclusion subtrees are recorded in SnapshotPolicy.
Included names must use normalized relative paths. Symlinks and special files
are rejected, including a symlink source root. Select a smaller source root or
explicitly exclude unsupported inputs. Binary files are preserved unchanged.

Snapshot bytes are immutable in-memory ByteStrings. SHA-256 covers sorted,
length-framed relative names, executable bits, contents and policy metadata.
No later operation can mutate a snapshot through a filesystem path. Capturing
twice detects ordinary changes; it is not an atomic OS snapshot against
adversarial concurrent writers. Large source trees currently cost memory
proportional to their selected bytes. Streaming/disk-backed snapshots are a
future optimization, not a different identity contract.

`withWorkspace` creates a unique private POSIX temporary directory, materializes
fresh writable files, and removes only that owned directory on exit. Copies
are never hard links. Build directories are independent. An output directory
must be outside the source root or excluded by the effective policy; ancestors
and the source root itself are never valid output locations. Canonical paths
are checked before accepting this relationship.

`withEditedWorkspace` applies the complete ordered edit sequence to one private
candidate. Its callback is invoked only after all edits and an independent
full inventory succeed. A replacement decodes strict UTF-8, checks the exact
non-overlapping anchor count, and preserves all other bytes. Create requires
absence; Delete requires exact old UTF-8 contents. A mutation must change final
bytes or executable bits. A sequence that undoes itself is invalid. An explicit
Control must remain unchanged. FileChange records actual before/after contents
and executable bits, including additions and removals.

Custom edit hooks receive checked read/write/create/delete operations. Every
existing path component is checked without following symlinks before an
operation; the final inventory rejects links introduced by hooks. Mutations of
runner-owned build/evidence paths are rejected. Trusted arbitrary Haskell IO
or consumer subprocesses can escape these capabilities. This API is not an OS
sandbox and does not defend against hostile concurrent link replacement.

Optional Git patches use a supplied bounded PatchRunner: the process owner
provides the production implementation. EP-2 tests use a timeout-bounded helper.
Git is unnecessary for replacement, create/delete or custom edits. The accepted
subset is unquoted `diff --git a/path b/path` textual patches, with matching
names, normal headers and ordinary file creation/deletion. Binary, rename,
copy, symlink and mode-change patches are rejected. All diff and old/new header
paths are checked, including `/dev/null` only as the absent file header. Git
checks before applying; failure discards the entire candidate even if a tool
partially wrote it. Patch content lives in a separate owned temporary directory.

EditError distinguishes InvalidEdit from EditInfrastructure. Stale anchors and
unsafe patch definitions are invalid; ordinary permission and missing-tool IO
failures are infrastructure. Cleanup exceptions remain observable. Reset only
operates on an opaque owned Workspace and independently verifies pristine
bytes; any failure invalidates reuse. Initial campaigns use fresh copies.
