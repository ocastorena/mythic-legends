# Mythic Legends

A mobile-first Roblox creature-collection and Base-progression game. Players capture Mythlings in a
shared Arena, assign them to elemental Shrines, and grow their roster and Base.

## Documentation

| Document | Canonical content |
| --- | --- |
| [Game Design Document](docs/GDD.md) | Player experience, gameplay rules, launch/future scope, pacing goals, and gameplay acceptance criteria. |
| [Technical Design](docs/TECHNICAL_DESIGN.md) | Rojo structure, naming, networking, combat implementation, data schemas, persistence, UI code ownership, and implementation alignment. |
| [UI Guidelines](docs/UI_GUIDELINES.md) | Menu behavior, visual conventions, accessibility, empty states, and player feedback. |
| This README | Project setup and development/verification commands. |

Write each rule in its owning document and link to it from the others. The GDD describes approved
behavior; the [implementation alignment notes](docs/TECHNICAL_DESIGN.md#implementation-alignment)
identify work needed to bring the prototype into line with it. Runtime balance values belong in
`src/ReplicatedStorage/Shared/Configurations`.

## Getting started

Use Roblox Studio with the Rojo Studio plugin and Aftman available. Install the pinned tools and
shared packages:

```bash
aftman install
wally install
wally install --project-path tests
```

For gameplay testing, open the existing Studio-authored development place. This repository does not
include the complete map and model assets: the current bootstrap requires authored
`Workspace.Map.Arena` and `Workspace.Map.BaseIslands`, along with the configured model templates. A
clean Rojo build supplies the mapped code and hierarchy, but is not a complete playable place. See
[Studio/Rojo ownership](docs/TECHNICAL_DESIGN.md#roblox-studio-and-rojo-ownership) for the authored
containers to preserve.

Start the Rojo server from the repository root, then connect to it through the Rojo Studio plugin in
that development place:

```bash
rojo serve
```

Before handing off source changes, run the static verification suite:

```bash
selene src tests
stylua --check src tests
rojo build default.project.json -o /tmp/mythic-legends-check.rbxlx
git diff --check
```

Selene checks first-party Luau under `src` and `tests`, excluding vendored/generated dependencies.
The temporary Rojo build verifies source mappings without adding a generated place file to the
repository. It cannot verify missing Studio-authored content. Gameplay and device behavior still
require a Studio playtest.

Jest Roblox tests are isolated under `ServerStorage.Tests` and do not run in production. After
installing their server-only Wally dependencies, run them from the Studio Command Bar while the
place is stopped:

```luau
require(game.ServerStorage.Tests.TestRunner).Run()
```

The runner discovers `tests/__tests__/*.spec.lua` through `tests/jest.config.lua`. Keep unit tests
deterministic: do not call live DataStores, invoke production remotes, depend on wall-clock time, or
mutate Studio-authored content.

Ordinary Studio sessions use an isolated, ephemeral ProfileStore mock. Restarting Studio does not
verify live cross-session persistence; persistence validation must explicitly exercise the intended
store and save lifecycle.

For more help, check out [the Rojo documentation](https://rojo.space/docs).

## Working in the repository

Read [AGENTS.md](AGENTS.md) before making changes. Follow the [project
structure](docs/TECHNICAL_DESIGN.md#current-project-structure), [naming
conventions](docs/TECHNICAL_DESIGN.md#naming-conventions), and [Studio/Rojo ownership
rules](docs/TECHNICAL_DESIGN.md#roblox-studio-and-rojo-ownership) in Technical Design. Art-source
conventions are in [art/README.md](art/README.md).
