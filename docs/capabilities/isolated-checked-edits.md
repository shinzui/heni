---
type: Capability
title: "Isolated source capture and checked mutations"
description: "Capture selected working-tree bytes and apply exact checked edits in disposable private workspaces."
capabilityId: CAP-2
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni"]
interface: ["Test.Heni.Workspace.withSnapshot", "Test.Heni.Workspace.withWorkspace", "Test.Heni.Edit.withEditedWorkspace"]
tags: ["mutation-testing", "haskell"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:16:53Z
reviews:
  - kind: model
    reviewer: codex/gpt-6
    reviewed_at: 2026-10-24T23:16:53Z
    document_timestamp: 2026-10-24T23:16:53Z
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: gpt-6
    effort: unspecified
    context: >-
      Author self-review against the listed local source, test definitions, and
      examples, including evidence-path and dependency-link checks. Availability
      means implemented on the default branch, not a Hackage release. No
      independent approval or new execution of every cited test is claimed.
evidence:
  - kind: module
    resource: src/Test/Heni/Workspace.hs
    proves: "Captures immutable selected bytes and creates owned writable copies."
  - kind: test
    resource: test/workspace/Main.hs
    proves: "Exercises capture policies, dirty inputs, path checks, staged edits, reset, cleanup, and optional patches."
  - kind: example
    resource: examples/migrations/patch-catalogue/heni.json
    proves: "Shows portable checked textual patch definitions."
  - kind: guide
    resource: docs/user/workspaces.md
    proves: "Defines source identity, edit preconditions, path restrictions, and supported patch boundaries."
  - kind: guide
    resource: docs/user/custom-edit-guide.md
    proves: Worked Haskell adoption with compiled example source.
  - kind: example
    resource: examples/haskell-guides/GuideCases.hs
    proves: Runnable public-API recipe with checked expected outcomes.
---

# Isolated source capture and checked mutations

Capture dirty and untracked regular files selected by the snapshot policy,
then run checked UTF-8 replacement, create/delete, textual patches, or registered
Haskell transformations in owned copies. Replacements check exact anchor counts;
ordered edits must leave a real final change. Explicit unchanged controls obey a
separate no-change contract. The active source checkout is never the edit target.

Snapshots preserve binary bytes but the first release has no binary edit
vocabulary. Symlinks and special files are rejected. Textual Git patches are
optional and restricted to the documented subset. Two capture reads detect
ordinary inventory changes; they do not create an atomic OS snapshot. Trusted
hooks and subprocesses can perform external IO.

Use the [case-authoring guide](../user/authoring-cases.md) and
[source/edit reference](../user/workspaces.md) to choose preconditions and inputs.

See the [worked Haskell guide](../user/custom-edit-guide.md) and its compiled example.
