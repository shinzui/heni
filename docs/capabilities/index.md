---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Capability

- [Evidence-owned verdicts and campaign accounting](attributable-verdicts.md) - Require valid baselines and precise attributable failures before accepting detection, and account for every selected case.
- [Bounded POSIX command supervision](bounded-posix-processes.md) - Run literal argv with wall-clock budgets, bounded retained output, exact diagnostic witnesses, and owned process-group cleanup.
- [Conservative campaign-local baseline sharing](compatible-baseline-sharing.md) - Share only successful baselines whose complete source, command, selection, environment, resource, and toolchain identities agree.
- [Fresh native crash-probe attribution](fresh-native-crash-probes.md) - Accept an explicitly declared native signal only with a fresh case-specific reachability probe and valid execution evidence.
- [Isolated source capture and checked mutations](isolated-checked-edits.md) - Capture selected working-tree bytes and apply exact checked edits in disposable private workspaces.
- [Attempt-bound named assertion evidence](named-test-reporters.md) - Connect optional Tasty or Hspec reporters to prove exact selected, executed, skipped, and failed test identities.
- [Strict manifests and shared command-line execution](portable-manifests-cli.md) - Validate portable versioned manifests and use one CLI to check, select, run, and inspect shared-library campaigns.
- [Portable reports and explicit journal recovery](portable-reports-recovery.md) - Retain versioned reports with relative artifacts and recover an explicitly untrustworthy snapshot without executing commands.
- [Required native property reproduction](required-property-replay.md) - Require a separate property replay to reproduce the original token, generator contract, and named failure set.
- [Scoped resources and bounded parallel cases](resources-and-workers.md) - Schedule private case workspaces under worker and resource capacities with consumer-owned acquire, reset, and release semantics.
- [Typed Haskell mutation campaigns](typed-campaigns.md) - Construct validated typed campaigns and execute a complete baseline-to-result lifecycle through the core library.
- [Verified private incremental build reuse](verified-build-reuse.md) - Retain private worker build artifacts only under a Haskell provider that verifies the build observed the exact staged input identity.

