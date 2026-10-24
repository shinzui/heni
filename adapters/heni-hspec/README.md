# heni-hspec

Replace Hspec.hspec with heniHspec. Use heniProperty for native QuickCheck counterexample replay; its ID must match the enclosing full example ID. Outside Heni, normal framework behavior is preserved.

Add `heni-hspec ==0.1.0.0` to the test component and select `"adapter": "heni-v1"` in the Heni case. Complete attempt-bound records prove selected/executed IDs and named failures. Missing, stale or partial evidence cannot count as detection.

See the [adapter guide](https://github.com/shinzui/heni/blob/master/docs/design/adapters.md) and packaged test fixture for runnable examples.
