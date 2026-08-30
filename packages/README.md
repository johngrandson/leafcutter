# Integration Packages

This directory is the physical boundary for executable Integration Package code.

The ratified layout is:

~~~text
packages/
├── build.exs
└── <package>/
    ├── mix.exs
    ├── manifest.json
    ├── lib
    └── test
~~~

Only literal entries in `build.exs` enter the Mix dependency graph and release. Directory
scanning is forbidden. The production inventory remains empty until Slice 26C3 selects the
first real external system and Operation.

Package source, Mix metadata, in-code documentation, and tests are written in English. A
package may depend on public `leafcutter_connectors` contracts, never Core, Runtime, or API
internals.

See:

- `docs/decisions/ADR-0023-package-manifest-build-binding-module-resolution.md`
- `docs/specifications/package-manifest-v1.md`
