---
type: Research Document
title: Mutation-testing ecosystem lessons for Heni's API and execution model
description: Compare mutation tools across ecosystems and derive bounded, testable design choices for Heni.
generated:
  by: process:codex
  at: "2026-10-24T14:36:00Z"
researchId: RES-2
status: complete
reviews:
  - kind: model
    reviewer: process:codex
    reviewed_at: "2026-10-24T14:53:00Z"
    document_timestamp: "2026-10-24T14:36:00Z"
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: gpt-6-astra
    effort: unspecified
    context: >-
      Author self-review of primary-source comparisons, canonical references,
      adoption inferences, and prototype/evidence limits. No tool benchmarks,
      implementation verification, or independent approval is claimed.
scope: >-
  Documentation review of cargo-mutants, StrykerJS, Stryker.NET, PIT, and
  mutmut on 2026-10-24, combined with Heni RES-1 and selected local Haskell
  standards and architectural decisions. No comparative benchmarks or tool
  executions were performed. This record informs prototypes; it does not
  certify APIs, package compatibility, or productivity improvements.
sources:
  - id: cargo-baseline
    resource: https://mutants.rs/baseline.html
    title: cargo-mutants baseline tests
  - id: cargo-results
    resource: https://mutants.rs/using-results.html
    title: cargo-mutants result interpretation
  - id: cargo-timeouts
    resource: https://mutants.rs/timeouts.html
    title: cargo-mutants hangs and timeouts
  - id: stryker-states
    resource: https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/
    title: Stryker mutant states and metrics
  - id: stryker-incremental
    resource: https://stryker-mutator.io/docs/stryker-js/incremental/
    title: StrykerJS incremental execution and limitations
  - id: stryker-workers
    resource: https://stryker-mutator.io/docs/stryker-js/parallel-workers/
    title: StrykerJS worker resource conflicts
  - id: stryker-net
    resource: https://stryker-mutator.io/docs/stryker-net/configuration/
    title: Stryker.NET coverage and baseline configuration
  - id: pit-basics
    resource: https://pitest.org/quickstart/basic_concepts/
    title: PIT operators, coverage, and results
  - id: pit-incremental
    resource: https://pitest.org/quickstart/incremental_analysis/
    title: PIT incremental analysis assumptions
  - id: mutmut
    resource: https://mutmut.readthedocs.io/en/latest/
    title: mutmut usage, selection, and process isolation
  - id: haskell-standards
    resource: mori://shinzui/haskell-jitsurei/docs/core-standards
    title: Haskell core standards
  - id: records
    resource: mori://shinzui/haskell-jitsurei/docs/core-record-patterns
    title: Record conventions and transitive orphan-instance exposure
  - id: prelude
    resource: mori://shinzui/haskell-jitsurei/docs/core-custom-prelude
    title: Small project preludes and import boundaries
  - id: library-boundary
    resource: mori://shinzui/mori-app/okf/adrs/concepts/ADR-1
    title: A base library owns transport and delivery, not the domain effect stack
  - id: cli-boundary
    resource: mori://shinzui/keiro/okf/adrs/concepts/ADR-28
    title: Operator commands wrap supported library APIs and respect schema ownership
---

# Mutation-testing ecosystem lessons for Heni's API and execution model

## Question and evidence boundary

Which ideas from established mutation tools help Heni replace bespoke orchestration
without losing the precise fault expectations identified in
[RES-1](mutation-testing-survey.md)? The research index (`docs/research/index.md`) is the entry
point for both records. RES-1 supplies the local use-case evidence; this record
adds cross-ecosystem design comparisons before the public API is implemented.

The sources below are primary project documentation, consulted on 2026-10-24.
Their URLs describe evolving products rather than pinned releases. No tool was
installed or benchmarked for this comparison. Claims about speed, completeness,
or superiority are consequently not established. Dependency versions and bounds
must be checked against Hackage and upstream tags when selected, not inferred
from either these pages or the local Mori corpus.

## Observations and implications

| Tool | Documented behavior | Proposed Heni response |
| --- | --- | --- |
| cargo-mutants, Rust | Runs an unchanged baseline in a temporary copy, then distinguishes caught, missed, unviable, and timeout outcomes. Build and test timeout controls are separate. | Adopt the baseline/candidate stage boundary and explicit budgets. Require the declared witness as well as a failed command. |
| StrykerJS and shared reporting | Provides separate mutant states, partial incremental results, and reuse informed by changes to source and tests. Its score counts timeout as detection. | Adopt durable per-case evidence and distinct states; retain Heni's stricter timeout and CI semantics. |
| Stryker.NET, C# | Offers per-test coverage selection and isolated test runs; static initialization may need all tests because precise coverage is unavailable. | Model selection evidence and identity explicitly; postpone coverage selection until its provenance and fallback behavior can be proved. |
| PIT, Java | Selects tests using line coverage and timing; incremental analysis acknowledges incomplete dependency tracking. | Leave room for selection and scheduling strategies, but start with explicit selection and conservative reuse. |
| mutmut, Python | Supports focused runs and persistent progress; documents extra fixture copying, relevance filtering, and inherited-state hazards in forked workers. | Make snapshot contents explicit and start stages in supervised external processes. Provide an easy focused-case workflow. |

The cargo-mutants baseline verifies that tests still pass after copying the tree;
this matters when fixtures or location assumptions are missing. Its result model
separates inability to compile from a successful test detection. Heni should
also distinguish intentional build rejection from an accidental compiler error.
These are execution-stage lessons, not a reason to copy Rust's mutation operators.
Sources: [baseline](https://mutants.rs/baseline.html),
[results](https://mutants.rs/using-results.html), and
[timeouts](https://mutants.rs/timeouts.html).

Stryker's shared metrics explicitly include timeouts among detections. Heni's
curated cases ask whether a particular fault reached a particular assertion;
elapsed time alone cannot supply that evidence. Keep `timed-out` separate and
make unresolved cases fail the run contract. If a reporting adapter is added
later, it must disclose this semantic difference instead of mapping a timeout
to a successful Heni detection. Source:
[states and metrics](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/).

StrykerJS incremental execution retains partial results and considers source
and test changes, but documents gaps for configuration, dependencies, environment,
and incomplete test-location reporting. PIT likewise notes that changes in
dependencies can invalidate otherwise unchanged class/test results. Heni should
first reuse baselines only inside a run with an explicit identity comprising
source bytes, commands, selector, adapter, build configuration, and environment
and resource contracts. Persistent cross-run verdict reuse is outside the first
release. Sources: [StrykerJS incremental](https://stryker-mutator.io/docs/stryker-js/incremental/)
and [PIT incremental](https://pitest.org/quickstart/incremental_analysis/).

StrykerJS documents false kills caused by workers competing for the same port
or resource and offers worker identities for partitioning. Heni should give each
worker independent writable source/build directories, plus explicit resource
claims and limits. A worker identity alone does not reserve a port, isolate a
database, or undo external effects. Source:
[parallel workers](https://stryker-mutator.io/docs/stryker-js/parallel-workers/).

PIT's coverage/timing selection and Stryker.NET's conservative treatment of
static initialization show why selection belongs in an explicit adapter
contract. Named-test evidence must distinguish discovered, selected, executed,
failed, skipped, and setup-failed tests. Heni must not treat an unknown count as
zero or assume a filter actually executed its intended test. Sources:
[PIT basics](https://pitest.org/quickstart/basic_concepts/) and
[Stryker.NET configuration](https://stryker-mutator.io/docs/stryker-net/configuration/).

mutmut documents extra files needed in its working directory, relevance limits
that change which tests count, and process-state inheritance that can cause hangs
or misleading outcomes. Heni should make inclusion rules visible, preserve
selection policy in evidence, and avoid an in-process framework runner in the
initial design. This is an inference about Heni's needs, not a claim that the
same Python process mechanisms apply to Haskell. Source:
[mutmut documentation](https://mutmut.readthedocs.io/en/latest/).

## Haskell design constraints

Apply the relevant [core standards](mori://shinzui/haskell-jitsurei/docs/core-standards):
GHC2024, the GHC 9.12-or-newer policy, common extension stanzas, postpositive
qualified imports, explicit deriving strategies, and strict record fields.
The actual tested compiler matrix and dependency bounds remain release evidence,
not facts established by the policy. The existing repository scaffold names
GHC 9.12.4; this is a local development choice, not a verified compatibility range.

Use concrete values and smart constructors for IDs, relative paths, positive
budgets, and nonempty case collections. Keep wire codecs explicit rather than
allowing constructor renaming to change JSON. A small internal prelude may
reduce repetition, but do not make its convenience exports the public API.
[Record patterns](mori://shinzui/haskell-jitsurei/docs/core-record-patterns) warn
that label instances propagate transitively. Therefore the public library's
import closure must not introduce generic-lens's orphan label instance; plain
constructor matching and explicit combinators are a justified application of
the pattern's isolation concern. Optional CLI internals may use lenses without
exposing them to library consumers. Document this scoped adaptation rather than
silently importing a large application prelude. See also the
[prelude guidance](mori://shinzui/haskell-jitsurei/docs/core-custom-prelude).

Two relevant cross-repository ADRs were inspected through Mori. The
[base-library boundary decision](mori://shinzui/mori-app/okf/adrs/concepts/ADR-1)
shows why consumer hooks should discharge their own domain effects into plain
`IO`. The [CLI ownership decision](mori://shinzui/keiro/okf/adrs/concepts/ADR-28)
supports one library-owned execution/classification path with alternative
presentations. These are architectural analogies; their event stores, service
stacks, and operational authorization policies are not Heni requirements.
No local Heni ADR existed at inspection time.

## API direction to test

A caller should construct a case, validate it, run a selected campaign, and
inspect a structured report without changing test framework. Keep a short
`Test.Heni` entry path, explicit option records with safe defaults, and optional
progress callbacks. Avoid a custom effect language or a hierarchy of classes
until two consumers require the same abstraction.

Separate a portable case description from Haskell-only transformations and
expectation hooks. A custom hook returns structured evidence; it cannot bypass
baseline success, required byte changes, timeout handling, or cleanup errors.
Built-in CLI cases must lower into the same library model. Framework reporters
produce versioned evidence; the core owns the verdict. Resource providers should
have scoped lifetimes so acquisition, use, and release cannot accidentally be
separated by normal control flow. Their cancellation behavior needs executable
tests, not just a convenient type signature.

Defer automatic source/AST operators, mutation switching, compiler plugins,
distributed workers, automatic equivalence claims, and coverage-driven
selection. Keep compatible extension points, but do not pay their complexity
before curated script replacement works.

## Prototype and adoption tests

The API must express all four RES-1 extraction patterns: checked replacement,
patch catalogue, generated-code change, and external diagnostic validation.
Add named assertions, property replay, explicit crash probes, and serialized
shared-resource use to exercise the difficult extensions. Each trial needs an
unchanged baseline and an intentionally broken detector or infrastructure path.
Otherwise a successful run may merely preserve an existing false positive.

Measure consumer-owned orchestration removed separately from fault definitions,
new-case authoring time, diagnosis effort, and elapsed build/test time. Record
hardware, compiler, commands, warm/cold conditions, fixture identity, and every
unsupported pattern. A best-in-class aspiration becomes credible through these
acceptance results and portable packaging; this research alone does not establish it.

The coordinated implementation is
[MasterPlan 1](../masterplans/1-bootstrap-heni-for-trustworthy-mutation-testing-and-hackage-release.md).
The first child proves the model with executable fixtures; the first real
baseline-to-report run is required before adapters, concurrency, or migration
variants expand. Actual cross-repository migrations remain separate work;
Heni contains reproducible, independently authored conformance fixtures.
