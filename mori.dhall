let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/3522f4a51181d73c9c90fc27a7c0838bd29ae95f/package.dhall
        sha256:dcb19e2312e790bad14e622cc98a1281cd2298c5b564a2f0d0534d3c718d8803

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "heni"
      , namespace = "shinzui"
      , stableId = Some "project_01m5q3ecrge5hashg8s8f77cy6"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Experimental
      , description = Some
          "Haskell library and CLI for running deliberate mutations and verifying that tests catch the intended faults. Specification stage; intended for Hackage publication."
      , domains = [ "testing", "mutation-testing", "developer-tools" ]
      , owners = [ "shinzui" ]
      }
    , repos =
      [ Schema.Repo::{
        , name = "heni"
        , github = Some "shinzui/heni"
        , localPath = Some "."
        }
      ]
    , -- Planned public package identities; source/build definitions follow
      -- implementation. No source directories or released versions are claimed.
      packages =
      [ Schema.Package::{
        , name = "heni"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , visibility = Schema.Visibility.Public
        , description = Some
            "Planned public Test.Heni library: mutation cases, isolated execution, precise verdicts, and evidence reports."
        }
      , Schema.Package::{
        , name = "heni-cli"
        , type = Schema.PackageType.Tool
        , language = Schema.Language.Haskell
        , visibility = Schema.Visibility.Public
        , description = Some
            "Planned Hackage CLI package providing the heni executable over the shared library."
        }
      ]
    , docs =
      [ Schema.DocRef::{
        , key = "readme"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , location = Schema.DocLocation.LocalFile "README.md"
        , description = Some
            "Purpose, name, project status, and intended public distribution."
        }
      , Schema.DocRef::{
        , key = "initial-spec"
        , kind = Schema.DocKind.Spec
        , audience = Schema.DocAudience.Module
        , location = Schema.DocLocation.LocalFile "docs/initial-spec.md"
        , description = Some
            "Proposed library, CLI, execution, reporting, and Hackage release contract."
        }
      , Schema.DocRef::{
        , key = "research"
        , kind = Schema.DocKind.Reference
        , audience = Schema.DocAudience.Module
        , location = Schema.DocLocation.LocalDir "docs/research"
        , description = Some
            "Source survey and extraction assessment with stable RES handles."
        }
      ]
    , okfBundles =
      [ Schema.OkfBundle::{
        , name = "research"
        , path = "docs/research"
        , profileBinding = Some
            ( Schema.ProfileBinding.Published
                Schema.PinnedImport::{
                , publisher = "shinzui/okf-profiles"
                , publisherRef = Some Schema.MoriRef::{
                  , namespace = "shinzui"
                  , name = "okf-profiles"
                  }
                , export = Some "documentation.researchDocuments"
                , version = Some "v0.25.0"
                , pin = Some
                    "sha256:ec74cc6f7b8ee1a5af81ee7fc8804f35cf2c9ba4010671d9e881da72eb6719d3"
                }
            )
        , okfVersion = "0.2"
        , description = Some
            "Bounded mutation-testing research with sources and explicit evidence limits."
        }
      ]
    }
