# Mythic Legends — Coding Conventions

This document owns project structure, Rojo hierarchy, first-party source naming, coding style,
resource ownership, and maintenance practices. [Technical Design](TECHNICAL_DESIGN.md) owns runtime
architecture, networking, persistence, configuration schemas, and UI ownership. The [GDD](GDD.md) owns
gameplay, [UI Guidelines](UI_GUIDELINES.md) own player-facing presentation, and the
[README](../README.md) owns setup and verification commands. Write each rule in its owning document
and link to it elsewhere.

These rules are the project's agreed conventions. Existing source may require cleanup to meet these
requirements; documenting a convention does not claim that all code or tooling already conforms to it.

## Relationship to Roblox guidance

Follow Roblox's documented [script locations](https://create.roblox.com/docs/scripting/locations),
[Luau type checking](https://create.roblox.com/docs/luau/type-checking), and
[resource cleanup guidance](https://create.roblox.com/docs/performance-optimization/improve).
The [Roblox style guide](https://roblox.github.io/lua-style-guide/) informs formatting and readability.

Project-specific choices include PascalCase public methods, Rojo source naming, service/controller
organization, strict checking throughout first-party code, and the use of Trove and Fusion. These
are deliberate conventions, not requirements imposed by Studio. In particular, this project's public
method casing differs from the Roblox style guide's general camelCase function recommendation.

## Project structure

The repository layout groups code by runtime boundary and owning feature. `default.project.json`
is the executable mapping to Roblox instances; update it and this document together when that
mapping changes. Directory organization must preserve the server/client trust boundary.

```text
mythic-legends/
  docs/
    CONVENTIONS.md                # project structure and coding conventions
    TECHNICAL_DESIGN.md            # implementation contracts and alignment notes
    GDD.md                        # approved gameplay and progression
    UI_GUIDELINES.md              # player-facing UI rules
  src/
    ReplicatedFirst/
      LoadingScreen.client.lua    # intentional early self-running entry point
    ReplicatedStorage/
      Shared/
        Configurations/           # static content and balance definitions
        Types.lua                 # contracts shared by runtime consumers
        <SharedModule>.lua        # logic needed by both server and client
    ServerScriptService/
      MainServer.server.lua
      Services/
        <Domain>Service/
          init.lua                # public API and lifecycle entry point
          <PrivateModule>.lua
      Infrastructure/             # cross-service technical support
      Domain/                     # explicitly shared server-domain contracts and pure logic
        Types.lua                 # server service protocols and injected context
        Production/ProductionLedger.lua
      Packages/                   # server-only vendored dependencies
      PostLaunch/                 # inactive, explicitly deferred modules
    ServerStorage/
      Databases/
        PlayerDataTemplate.lua
    StarterPlayer/
      StarterPlayerScripts/
        MainClient.client.lua
        Types.lua                 # client controller and view-prop contracts
        Controllers/
          <Domain>Controller.lua
          <Domain>Controller/     # alternative when private children are needed
            init.lua
            <PrivateModule>.lua
        State/                    # LocalData client cache
        Character/                # shared client character helpers
        UI/
          App.lua                 # one application composition root
          Theme.lua               # shared visual tokens
          Screens/                # screen factories, optionally with private children
          Components/             # reusable presentation components
          Overlays/               # toasts and modal backdrop
          State/                  # presentation state and cache adapters
          <PresentationModule>.lua
  tests/
    __tests__/<Subject>.spec.lua
    TestRunner.lua
    jest.config.lua
    wally.toml
    wally.lock
    DevPackages/                  # generated test dependencies; not hand-edited
  Packages/                       # generated shared Wally dependencies
  art/                            # authoring conventions and versioned source assets
  .vscode/                        # shared editor settings
  .github/workflows/verify.yml     # static checks on pushes and pull requests
  tools/Typecheck.ps1              # pinned Roblox-aware strict analysis
  AGENTS.md                       # agent guidance and required reading
  README.md                       # setup and verification commands
  default.project.json            # canonical Rojo mapping
  aftman.toml                     # pinned development tools
  wally.toml
  wally.lock
  selene.toml
  .styluaignore
  .stylua.toml
  .editorconfig
  .gitattributes
  .luaurc
  .gitignore
```

Placeholders describe permitted patterns, not files to create. A domain uses either the single-file
or folder form at a given instance path. Do not add empty feature folders or launch placeholders
for deferred systems. Generated dependencies, API definitions, and verification outputs are ignored;
follow the README to regenerate them.

`MainServer` owns server startup and shutdown. `MainClient` owns bootstrapped client features.
`LoadingScreen.client.lua` is the intentional early-loading exception. Keep service helpers private
to their service, character helpers client-side, and UI state adapters distinct from the authoritative
client cache. Runtime responsibilities follow [Technical Design](TECHNICAL_DESIGN.md#runtime-architecture).

## Roblox Explorer hierarchy

`default.project.json` produces this high-level instance hierarchy. The repository may use additional
organizational folders, but synced instance paths are public architectural contracts. Keep remotes
and detailed ownership rules in [Technical Design](TECHNICAL_DESIGN.md#network-contract).

```text
Workspace
  Map                 -- authored terrain, buildings, and static environment
  Spawns              -- authored player spawn locations
  Visuals             -- authored particles, lights, and decorations
  Runtime             -- server-created Mythlings, bases, effects, and other session state
ReplicatedFirst
  LoadingScreen       -- early loading-screen entry point
ReplicatedStorage
  Network             -- Rojo-declared RemoteEvents and RemoteFunctions
  Packages            -- generated shared Wally dependencies
  Shared              -- configurations, types, and logic needed by server and client
  Assets              -- client-visible UI, audio, VFX, and preview assets
ServerScriptService
  MainServer          -- only server bootstrap
  Services            -- authoritative domain services
  Infrastructure      -- logging, rate limits, remotes, and server utilities
  Domain              -- explicitly shared server-domain contracts and pure accounting
  Packages            -- server-only external libraries such as ProfileStore
  PostLaunch          -- inactive post-launch modules; never launch dependencies
ServerStorage
  Databases           -- player-data templates and server-only definitions
  Tests               -- isolated test source and server-only test dependencies
  ServerAssets        -- production server-only model templates
  Authoring           -- Studio-only backups, source templates, and staged content
StarterGui
  <empty>             -- production application roots are created under PlayerGui
StarterPlayer
  StarterCharacterScripts
  StarterPlayerScripts
    MainClient        -- only client bootstrap
    Controllers       -- input, UI behavior, animation, audio, and VFX controllers
    State             -- private replicated client state
    Types             -- client controller and view-prop contracts
    Character         -- shared client character helpers
    UI                -- application, screens, components, overlays, adapters, and theme
```

Keep runtime content separate from authored content. Production UI is repository-owned and composed
directly under `PlayerGui` by `UI/App`; do not add authored application roots to `StarterGui`.
The [Studio/Rojo ownership rules](TECHNICAL_DESIGN.md#roblox-studio-and-rojo-ownership) determine which
unknown authored descendants Rojo preserves. Tests remain server-only and do not run in production.

## Naming conventions

| Role | Server | Client |
| --- | --- | --- |
| Bootstrap | `MainServer.server.lua` | `MainClient.client.lua` |
| Domain module | `<Domain>Service/init.lua` | `<Domain>Controller.lua` |
| Stateless helper namespace | `<Thing>Util.lua` | `<Thing>Util.lua` |
| Constructed object or subsystem | Precise noun such as `RateLimiter.lua` | Precise noun such as `CardList.lua` |
| Shared state or event channel | Precise noun such as `<Thing>State.lua` | Precise noun such as `ModalState.lua` or `ToastBus.lua` |
| Module with private children | service folder + `init.lua` | controller folder + `init.lua` |

- Use **PascalCase** for source files, runtime folders, Roblox instances, module tables, exported
  types, services, and controllers: `DataService/init.lua`, `UIController.lua`, and `PlayerData`.
- Every server service owns a directory named `<Domain>Service`, even when it has no private child
  modules. Its public entry point is always `init.lua`.
- Reserve the `Util` suffix for stateless helper namespaces that do not own a domain lifecycle,
  shared application state, or a long-lived feature object. Name constructed objects, runtime
  subsystems, state stores, and event channels for what they are: `RateLimiter`, `BaseRuntime`,
  `CardList`, `ModalState`, and `ToastBus`.
- Use **PascalCase** for public methods and exported factories: `DataService.Load`,
  `CardList:Replace`, `UIController.Init`, and the callable `HudButton` module. A local function
  returned as the module's named public factory also uses PascalCase to match its filename.
  Established constructor `.new` and tagged logger `.warn`/`.error` methods are exceptions;
  preserve external library APIs as supplied.
- Use **PascalCase** for named UI instance handles exposed by a component, such as `panel.Header`
  or `panel.CloseButton`. Use **camelCase** for ordinary data records, props, callback fields, and
  other data values, such as `displayName`, `title`, `onSelected`, and `rootScale`. Being returned
  from a public function does not make every table field an API method or an instance handle.
  An instance-valued prop still uses camelCase (`props.parent`); a public API operation uses
  PascalCase (`handle.Destroy`), while a callback prop uses camelCase (`props.onSelected`).
- Use **PascalCase** for local references to Roblox services and required module tables or callable
  module exports: `Players`, `ReplicatedStorage`, `LogUtil`, and `HudButton`.
- Use **camelCase** for private local functions, parameters, mutable module state, and ordinary runtime
  values: `loadProfile`, `activeProfiles`, `playerData`, and `stateRevision`. An injected dependency
  assigned to a module reference still uses PascalCase, such as `DataService`.
- Use **UPPER_SNAKE_CASE** for immutable module constants: `STORE_NAME`, `PROFILE_KEY_PREFIX`, and
  `LOAD_TIMEOUT_SECONDS`. A variable that changes during initialization or runtime is not a constant
  merely because its name is uppercase.
- Name booleans as predicates: `isLoaded`, `hasInventorySpace`, `shouldReplicate`, and `canAttack`.
  Avoid ambiguous names such as `flag`, `check`, or `status` when a precise name is available.
- Name events and signals for occurrences: `OnStateChanged`, `OnProfileLoaded`, and `OnSessionEnded`.
- Group remotes by domain and give each one a single direction and responsibility. Name
  `RemoteEvent` instances as actions or notifications (`StartAttack`, `ClaimState`) and
  `RemoteFunction` instances as requests or commands that return a result (`Request`,
  `DeleteMythling`, `GetStatus`).
- Use singular nouns for data types and owned records: `PlayerData`, `StatePacket`, and
  `MythlingEntry`. Collection configuration modules are plural: `Configurations/Mythlings.lua`.
- Use **camelCase** for serialized field and remote-payload keys. Stable metadata IDs use lowercase
  `snake_case`; they are identifiers, not display names.
- Keep module-private state `local` without an underscore prefix: use `profiles` and `localCache`,
  not `_profiles` or `_localCache`. Private fields on a constructed object may use **_camelCase**,
  such as `self._cards` and `self._config`; these are distinct from module-local variables.
  An underscore prefix may also identify an intentionally unused parameter, such as `_context`.
- A named module export matches its filename: `RateLimiter.lua` returns `RateLimiter`. A folder
  entry point uses its folder name. Log/assert tags use that module name, optionally qualified by
  its owning domain for a private child: `[RateLimiter]` or `[InventoryService.Mythlings]`.
  The final tag segment must match the emitting module; do not retain a former owner's tag after
  extraction. Data-only configuration literals and type-only modules need no artificial wrapper
  solely to create a named return value.
- Prefer descriptive names over service abbreviations or generic names such as `Manager`, `Helper`,
  or `Utils` when the module's actual responsibility has a precise name.

## Files and module organization

- Keep first-party Luau source in `.lua` files, following the current Rojo convention. Use
  `.server.lua` and `.client.lua` only for executable bootstraps or intentionally self-running
  scripts. Bootstrapped controllers are ordinary ModuleScripts; do not use redundant names such as
  `CombatClient.client.lua`.
- A controller or component may begin as one file. When it needs cohesive private children, turn it
  into a same-named folder with `init.lua`, preserving its public Roblox instance path. Server
  services always use the folder form.
- Keep helpers under their owning domain and require them through `script`. Treat private children
  as implementation details; another domain consumes the public API or an explicitly shared
  contract instead of reaching into those children.
- Put a module in `ReplicatedStorage.Shared` when both client and server need it. Server-only
  helpers stay server-side; tests alone do not justify client replication. Cross-domain server
  logic needs an explicit owner or shared location consistent with Technical Design. Do not place
  gameplay logic in generic infrastructure solely to avoid a dependency decision.
- Split modules by responsibility, ownership, or independently testable behavior. There is no fixed
  line-count limit. Keep a small public entry point when extracting cohesive private modules, and
  avoid creating a service/controller for every helper or visual widget.
- Apply the [UI ownership contract](TECHNICAL_DESIGN.md#ui-composition-and-ownership): controllers
  own feature input and request orchestration; screens/components own layout and presentation;
  state adapters expose the existing client cache to views. Keep reusable component contracts
  limited to the props, confirmed view state, and callbacks they need.
- Keep new code's terminology aligned with the GDD. Rename source files, exports, imports, tags,
  tests, and documentation together. Changes to persisted fields, remotes, metadata IDs, or authored
  instance paths require the corresponding compatibility work; a terminology cleanup alone does
  not authorize changing those contracts.

## File headers and internal layout

Every first-party Luau file begins with `--!strict`; the next line is the exact mapped Roblox
instance path. Omit `src`, the `.lua` extension, script-kind suffixes (`.server` or `.client`), and
the `init` filename from that path. For example, `MainServer.server.lua` maps to
`ServerScriptService/MainServer`. Tests use their mapped `ServerStorage/Tests/...` path:

```luau
--!strict
-- ServerScriptService/Services/DataService/Migrations
```

- Follow the path with a short responsibility comment when the filename alone is insufficient.
- Prefer this reading order: Roblox services; external/shared dependencies; domain dependencies;
  types; constants and module state; private helpers; public API/lifecycle; returned export. Keep
  declarations earlier when Luau scoping or a type dependency requires it.
- Keep related functions together. Prefer `Init`, `Start`, and `Stop` in that order when grouping
  lifecycle methods. Do not reorder declarations blindly to satisfy a cosmetic preference.
- Comments explain intent, invariants, units, compatibility, or a non-obvious tradeoff. Keep API
  examples accurate and link design references to named sections.
- Remove abandoned implementations, commented-out debug code, and obsolete explanations. Git
  history preserves old implementations. A TODO should identify a concrete gap and its relevant
  contract; it must not imply that a deferred feature is approved for launch.

## Types and shared contracts

Strict type checking is required throughout first-party Luau, including existing modules, executable
scripts, configurations, and tests. Existing non-strict files must be converted as explicit cleanup
work; they are not permanent exceptions. A conversion must address type errors rather than only
adding the directive. Vendored/generated dependencies retain their upstream checking policy.

- Give public APIs, remote payloads, configuration records, and persistent data shapes clear types.
  Let Luau infer obvious local values rather than repeating annotations everywhere.
- Define each shared contract once. Import or alias the canonical type at consumers instead of
  copying declarations such as `StatePacket` or `Network` between client and server.
- Keep domain-private types with their owner; place genuinely shared types in the shared types
  module. Do not move every internal implementation detail into a global type registry.
- Type a required configuration by the table it returns, not as `ModuleScript`. Give constructed
  objects and service dependencies their actual API types.
- Use `unknown` for untrusted values where practical, then narrow them with runtime validation.
  Type annotations and casts do not validate remote input or saved data at runtime.
- Keep `any` and unchecked casts localized to unavoidable dynamic/library boundaries, with an
  explanation when the limitation is not obvious. Do not suppress a whole file merely to hide a
  known mismatch. Remove unused declarations or wire them into the intended consumers.
- Verified strict compliance requires strict analysis of the stated first-party scope with no
  unresolved type errors, using Studio Script Analysis or a pinned Roblox-aware checker configured
  with the project's instance mapping, Roblox API types, and dependencies. Merely adding
  `--!strict`, passing Selene, or building with Rojo does not satisfy this requirement.
- Follow the [README verification procedure](../README.md#verification). Report the checker/version,
  analyzed scope, unresolved diagnostics, and exclusions. Mark unavailable or incomplete checks as
  unverified rather than passing; an existing baseline error remains a finding.

## Lifecycle and resource ownership

- Use `Init(context)`, `Start()`, and `Stop()` for every bootstrapped server service and client
  controller. `Init` captures dependencies, `Start` connects events and starts tasks, and `Stop`
  releases runtime resources. Requiring a module must not connect events or start tasks.
- Reserve `Destroy()` for constructed objects that are permanently unusable afterward. Pure helpers
  and data modules do not need artificial lifecycle methods.
- Every event connection, task, input binding, temporary instance, tween, and temporary engine-state
  override has an identifiable owner and cleanup path. Register ownership when creating the
  resource, including resources created inside callbacks or delayed work.
- Connections to long-lived objects such as `Camera`, `Players`, or `RunService` must be disconnected
  when their owning feature/view ends. Destroying a GUI does not clean up a listener attached to
  the camera. Destroying the actual signal source may supply cleanup for that source's listeners.
- Prevent an old yielding request, deferred callback, or tween completion from changing a stopped
  feature or a replacement view. Use cancellation or generation checks as appropriate, combining
  them when needed. Restore only temporary state the feature still owns.

Use Trove for service/controller runtime resources, Fusion scopes for declarative UI resources, and
owning-GUI destruction for focused imperative component factories.
An imperative component may instead return a `Destroy` callback registered with the caller's scope.
Each resource has one cleanup owner; avoid parallel ad hoc lists for the same lifetime.

Repeated `Start()` while running and repeated `Stop()` after stopping are harmless. Every service
and controller must clean up safely when stopped. Support `Start → Stop → Start` only when the module
is explicitly designed and documented to restart; such modules must rebuild their runtime resources
without duplicate listeners or stale work. Document terminal lifetimes such as ended persistence
sessions or shutdown paths. A terminal module must reject an attempted restart clearly rather than
silently reusing invalid state.

## Configuration and constants

- Keep static content and balance data in the location and schemas specified by
  [Technical Design](TECHNICAL_DESIGN.md#content-configuration). Runtime code treats configuration
  as read-only; mutable player or feature state belongs outside configuration tables.
- Use unit-bearing names when a number would otherwise be ambiguous: `durationSeconds`,
  `reachStuds`, or `materialsPerHour`. Keep conversion boundaries explicit.
- Derived values come from their owning definitions and current mutable state. Do not save copies
  of static metadata merely to simplify a caller.

Use camelCase for configuration record fields and grouping properties; PascalCase remains for the
module reference. Dictionary keys retain their defined identity: stable catalogue IDs remain
lowercase snake_case, while enum values such as `Common`, `Rare`, and `Epic`
retain their canonical spelling. Existing PascalCase record/grouping properties are a migration
task, not a reason to break consumers in a documentation-only change.

Freeze plain configuration tables recursively once during module construction, following Roblox's
[table-freezing guidance](https://create.roblox.com/docs/luau/tables#freeze-tables). A shallow
`table.freeze` does not protect nested records. The recursive helper must safely handle already-frozen
tables and shared references without missing their nested values or revisiting cycles indefinitely.
Keep mutable working copies separate; do not freeze player saves or runtime state. Preserve
third-party API behavior. Freezing prevents accidental mutation; it does not replace server validation.

## Formatting and tooling

Use UTF-8 without a BOM, LF line endings, a final newline, tabs with a display width of four, a target
width of 100 columns, and double-quoted strings unless escaping is clearer with the alternative.
The tab width, code width, and quote preference follow the
[Roblox style guide](https://roblox.github.io/lua-style-guide/#general-whitespace). StyLua decides
wrapping and whitespace; do not hand-align code in ways that fight the formatter.

- Use the tool versions pinned in `aftman.toml`. Editor formatting and command-line verification
  use the same StyLua release and repository configuration; avoid a floating `latest` editor pin.
- Record formatting choices in repository tooling, including `.stylua.toml`, `.editorconfig`, and
  `.gitattributes` where applicable. A written convention alone does not configure editors or Git.
- Keep mechanical formatting/line-ending changes separate from behavior changes so diffs remain
  reviewable. Avoid formatting unrelated files during a small feature or bug fix.
- Run the relevant [README checks](../README.md#verification), and automate those same checks in
  CI. Keep the command list and setup instructions in the README rather than copying them here.
- A formatting compliance check must use the agreed 100-column baseline. Repository formatter
  configuration and the README command both specify that width; a passing run with
  different settings is not evidence of compliance. Distinguish line-ending differences from other
  formatting findings without silently ignoring either.
- Repository formatter/editor/Git settings and CI implement these rules. The pinned type-checking
  command, dependency generation, API snapshot, and analyzed scope are documented in the README.

## Logging conventions

- Project-owned runtime code logs only abnormal conditions. Successful initialization, startup,
  profile loading, saves, requests, and gameplay actions must not emit console output.
- Server code creates a tagged logger with `local log = LogUtil.For("ModuleName")`, then uses
  `log.warn` for recoverable anomalies and `log.error` for serious failures that were safely
  contained. Both log without throwing. Use `error()` or `assert()` only when continuing would leave
  the runtime invalid.
- A private child may use `LogUtil.For("Owner.Module")`, such as
  `LogUtil.For("InventoryService.Mythlings")`. Apply the same tag convention to assertions and
  client warnings; the final segment names the module that emits the diagnostic.
- Client code uses `warn` only when a required operation fails, such as controller startup or state
  synchronization.
- Invalid and rate-limited remote requests are rejected silently. Never let exploit traffic flood
  logs, and never log complete profiles or sensitive payloads.
- Include stable diagnostic context such as a service tag, `userId`, metadata ID, or error code.
  Prefer `userId` over player display names.
- Keep tags aligned with their actual module after an extraction or rename. Return expected failure
  results through the existing domain contract; do not turn normal rejection paths into exceptions.

## Tests, refactoring, and maintenance

- Keep deterministic unit tests under `tests/__tests__/<Subject>.spec.lua`, using the existing Jest
  runner. Inject time/randomness when needed; avoid live DataStores, production remotes, wall-clock
  timing, and changes to authored Studio content.
- Test behavior and important invariants, especially pure calculations, migrations, transactions,
  and lifecycle cleanup. Do not add tests that merely mirror implementation or assert superficial
  file structure for a reversible cosmetic change.
- Preserve public contracts and behavior during organizational refactors. Update consumers and
  tests with renames. Separate intentional behavior changes so reviewers can assess them clearly.
- Remove obsolete runtime code and obsolete tests together after checking callers, including
  documented authored/external integrations. Preserve tests that still cover the replacement's
  behavior; do not keep a dead implementation solely to keep its tests passing.
- Keep implementation-alignment notes and API examples current when code changes. Separate current
  implementation from approved targets and post-launch plans.
- Generated files, built places, and vendor sources are not routine cleanup targets. Preserve
  unrelated worktree changes. State the checks run and any remaining runtime-validation limits.

## Consistency scan scope and findings

Scan first-party runtime source, configurations, templates, tests, inactive `PostLaunch` source,
project/tooling definitions, and their documentation references. Include both server and client
code. Review deferred code for conventions without activating it or expanding its functionality.

Exclude vendored/generated dependencies, built places, and generated sourcemaps from first-party
style requirements. Record those exclusions explicitly. Preserve framework filename/API exceptions,
authored asset contracts, and inactive saved fields that the design requires retaining. An apparent
unused reference is not sufficient evidence to remove compatible player data or authored integrations.

Classify findings separately so a consistency review does not turn every preference into a violation:

| Classification | Required evidence |
| --- | --- |
| Convention violation | The applicable rule, concrete file/location, and the specific mismatch. Account for documented exceptions. |
| Maintainability recommendation | The responsibility, duplication, dependency, or ownership problem and the benefit of a proposed change. File length or personal taste alone is insufficient. |
| Gameplay or implementation gap | The owning GDD, Technical Design, or UI contract and the current behavior. Report it separately from mechanical cleanup. |
| Studio validation required | The behavior static inspection cannot establish and the Studio scenario needed to verify it. Do not report an unperformed check as a confirmed defect or success. |

A confirmed finding may also require a Studio regression check after its fix; identify that validation
separately. Report missing tooling or incomplete analysis as verification gaps. Summarize scope and
checks actually completed, including unresolved baseline failures, before claiming repository-wide
consistency. A scan report does not itself authorize gameplay changes or data migrations.

## Deliberate exceptions and adoption

- Existing tooling names such as `src`, `tests`, `init.lua`, `jest.config.lua`, `__tests__`, and
  `*.spec.lua` are exceptions to PascalCase filenames/folders. Documentation filenames retain their
  established links, including `CONVENTIONS.md`.
- Preserve vendored/generated package filenames, extensions, APIs, and formatting. For example,
  `ProfileStore.luau` does not require renaming to match first-party `.lua` files.
- Existing saved field names, remote contracts, and metadata IDs remain compatible until deliberately
  migrated. Correct source conventions without silently erasing or reinterpreting player data.
- Apply settled conventions to new work and the relevant portions of touched code. Schedule broad
  legacy cleanup explicitly; documenting these rules does not perform or authorize unrelated
  gameplay changes.
- Document a necessary exception beside its owner with the concrete reason. Prefer a narrow
  exception over weakening a project-wide rule.
