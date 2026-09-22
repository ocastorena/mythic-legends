# Codebase consistency audit and resolution

Updated 2026-09-21 against [Coding Conventions](CONVENTIONS.md). The original audit used commit
`68ff0a7` plus existing documentation changes. This report records the authorized cleanup that
followed; `CONVENTIONS.md` remains the source of conventions.

## Scope and outcome

All eleven groups of confirmed convention findings have source fixes. The original scope contained
93 first-party Luau files. After responsibility extractions, obsolete-code removal, and added
regression tests, the scope contains **112 files: 99 under `src` and 13 under `tests`**, including
inactive `PostLaunch` code. All are strict and have the correct mapped-path header.

Vendored/generated packages, generated sourcemaps, built places, and authored asset internals are
excluded from first-party style requirements. Existing gameplay values, saved field names, metadata
IDs, remote instance paths, and authored asset contracts were preserved. Deferred systems remain
inactive. This cleanup does not establish launch readiness.

## Confirmed findings resolved

| Finding | Implemented correction |
| --- | --- |
| C01 — Strict checking and canonical contracts | Converted all first-party files with actual strict analysis. Shared payload/save/configuration types remain in [Shared/Types](../src/ReplicatedStorage/Shared/Types.lua); server protocols live in [Domain/Types](../src/ServerScriptService/Domain/Types.lua), and client/controller/view contracts in [client Types](../src/StarterPlayer/StarterPlayerScripts/Types.lua). DataService exposes typed loaded documents. Dynamic typing is localized to legacy migrations, serialized projection/cache, or documented library boundaries. |
| C02 — Formatting and tooling | Added pinned formatter/editor settings, `.editorconfig`, `.gitattributes`, strict `.luaurc`, repeatable [type checking](../tools/Typecheck.ps1), and [CI](../.github/workflows/verify.yml). Normalized first-party text to LF and corrected path headers. |
| C03 — Repeated lifecycle calls | Services/controllers guard duplicate Start/Stop. [ServiceLifecycle](../src/ServerScriptService/Infrastructure/ServiceLifecycle.lua) enforces terminal server lifetimes; unsupported restarts fail clearly. |
| C04 — Escaped listeners and asynchronous work | Added lifetime ownership and cancellation/generation guards for profile/base/character initialization, escorts, combat effects, loading completion, UI transitions, viewport listeners, and controller-owned requests. Closing or replacing a view invalidates late responses. |
| C05 — Incomplete restoration | Cleanup releases equipped presentation, guard effects/attributes, reactions/animations, claim tweens, environment effects, prompt overrides, and loading/input/camera overrides. Restoration checks the state still owned by the feature. |
| C06 — Inconsistent cleanup tools | Service/controller resources use Trove; declarative UI uses Fusion scopes; imperative GUI factories release external listeners on destruction. Completed recurring tasks and removed prompt records no longer accumulate until shutdown. |
| C07 — Configuration casing, immutability, and tuning | Recursively froze all five configurations and Theme token data through [FreezeUtil](../src/ReplicatedStorage/Shared/FreezeUtil.lua), including shared references, frozen parents, and cycles. Migrated record/group keys and consumers to camelCase. Centralized unchanged combat presentation defaults and renamed rates to `materialsPerMinute`. |
| C08 — Naming drift | Normalized public UI APIs, local/module references, exported types, and scalar/data fields. Retained documented constructor, logger, framework, stable-ID, and input-prop exceptions. |
| C09 — Incorrect ownership/location | Moved ArenaBounds and CombatMath under CombatService, and shared server accounting into [Domain/Production](../src/ServerScriptService/Domain/Production/ProductionLedger.lua). Inventory/Stand controllers own requests, pending state, refreshes, and action orchestration. |
| C10 — Diagnostics | Corrected owner tags and removed warnings for expected placement rejection while retaining abnormal asset/runtime diagnostics. |
| C11 — Obsolete comments/documentation | Updated version-3 persistence/accounting alignment, deferred Consumables wording, API examples, helper ownership, timer/climbing explanations, and asynchronous-save comments. Removed abandoned commented implementations. |

## Maintainability decisions

- Split [Panel](../src/StarterPlayer/StarterPlayerScripts/UI/Components/Panel/init.lua) into private
  shell, grid, details, modal, and proximity modules while preserving its public instance path.
- Split [Inventory](../src/StarterPlayer/StarterPlayerScripts/UI/Screens/Inventory/init.lua) into its
  screen shell and private category presenters. Its controller owns domain requests.
- Extracted [EquipmentPresentation](../src/ServerScriptService/Services/CombatService/EquipmentPresentation.lua)
  and [ClaimEscort](../src/ServerScriptService/Services/MythlingSpawnService/ClaimEscort.lua), each
  with ownership of its distinct resources.
- Removed unused ProductionMath and its obsolete suite, preserving useful edge coverage in ledger
  tests. Removed the empty Inventory Consumables wrapper and unimplemented optional removal hook
  after checking consumers; retained legacy saved data.
- Standardized presentation subscriptions with
  [SubscriptionList](../src/StarterPlayer/StarterPlayerScripts/UI/State/SubscriptionList.lua).
  [Technical Design](TECHNICAL_DESIGN.md#behavior-ownership) records initial delivery, error isolation,
  duplicate registration, unsubscribe, and native-signal differences.
- Added terminal client bootstrap cleanup so controllers, the application scope, private signals,
  and LocalData have explicit owners.
- Retained Stand/Shrine compatibility names, camelCase view-binding props, saved fields, metadata
  IDs, and framework filenames. These do not warrant a blanket rename.

## Verification

| Check | Result |
| --- | --- |
| Strict Luau analysis | Pass for all 112 first-party files using luau-lsp 1.70.0, SolverV2, strict DataModel resolution, current Rojo mapping, generated Wally type exports, and the SHA-256-verified API snapshot. No unresolved type errors. The complete type-check script also passed on two consecutive invocations. |
| Selene 0.31.0 | Pass: zero errors, warnings, and parse errors across `src tests`. API refresh was unavailable; Selene used its cached Roblox standard library. |
| StyLua 2.5.2 | Pass: `--check --column-width 100 src tests`, using repository configuration. |
| Headers and encoding | All 112 mapped/physical files: strict first line, correct mapped path second line, valid UTF-8 without BOM, only LF, exactly one final newline. No unmapped first-party Luau files. |
| Rojo 7.7.0 | Pass: `default.project.json` builds into ignored verification output. This verifies source mappings, not authored asset completeness. |
| Git whitespace | `git diff --check` passes. |
| Jest Roblox | Pass: 11 suites, 62 tests, zero failed or pending tests. Includes migrations/accounting, placement, combat math/bounds, player template, recursive freezing, lifecycle cleanup, subscriptions, and LocalData. |
| UI smoke check | Detail and modal factories construct 91 temporary descendants, support modal open/close, and destroy successfully. This is not a visual/device acceptance test. |
| Authored-place Studio verification | Synced all 112 first-party sources; all 11 Jest suites and 62 tests also passed against the actual Studio hierarchy. Two single-player Play sessions exercised the runtime checks below. |
| Documentation references | 157 local links across eight Markdown files, including 95 anchor targets; no missing paths or anchors. |

Jest and the UI smoke check ran in Studio `0.739.19.7390691` using an unparented throwaway clone of
current mapped source and installed dependencies. A fixture-local service proxy redirected source
lookups while engine services remained real. The initial Accrual fixture's restricted Player
construction was replaced with a documented opaque identity mock before the successful rerun.
That initial fixture run did not replace authored-place scripts, start gameplay, or use live
DataStores or production remotes. Temporary test objects were destroyed after verification.
All 112 fixture sources matched the final checkout by checksum after removing the isolation binding.

The subsequent user-authorized Studio verification synced three missing and three stale first-party
modules, then ran Jest directly against the actual place hierarchy. Play probes ran as temporary
Scripts/LocalScripts so they shared the running application's module cache. Direct MCP `require`
results were not used as evidence of live service/controller state. The configured Studio mock
profile store was used; no live player saves were changed. Authored map/assets were preserved.

### Studio Play results

- Startup loaded the player profile, private client state, character, base, and Arena Mythlings.
  Repeated Start calls on all eight server services preserved the same profile/base and did not
  deliver duplicate profile-loaded callbacks.
- Repeated server Stop calls succeeded. Terminal services rejected restart. Stopping combat during
  active Shield guard removed equipped presentation, guard/immunity attributes, and restored the
  character's recorded movement settings. Stopping an active escort destroyed its model and emptied
  the spawn registry without later replacement. No capture reward was granted by that probe.
- Profile release was idempotent; reloading preserved the mock balance. Stopping during a pending
  profile load prevented the load from completing or leaving a loaded document.
- Unsubscribing a yielding character callback prevented it from resuming and ran its cleanup once.
  Viewport observation followed camera changes and stopped notifying after its GUI owner was
  destroyed. Inventory and Stand sessions suppressed queued refresh callbacks after Close, then
  delivered one valid callback for a fresh session.
- Hotbar Stop restored Roblox's Backpack flag and Start disabled it again. Combat, environment,
  and climbing controllers tolerated repeated lifecycle calls; climbing restored its prior state.
  UI Stop destroyed application roots and released modal/menu state. Two subsequent application
  scope mount/destroy cycles, including Inventory-to-Shop switching during an unfinished transition,
  left no application roots or registrations and restored input/camera state. Terminal client
  controllers rejected restart, and repeated LocalData destruction succeeded.
- Found and fixed an additional InputGuard issue: Roblox's PlayerModule exposes `controlsEnabled`,
  not `enabled`. Direct runtime checks now pass for enabled/disabled initial controls, nested guards,
  repeated Close, released input bindings, and camera restoration. The fix was synced before the
  second Play session and passed all final static checks.
- The final Play console contained only Roblox's startup `Player:Move` warning while no character
  existed; no project runtime errors were reported. Play was stopped, temporary probes were removed,
  and all 112 Edit-mode script/editor sources matched the checkout by checksum.

Client rendering remained unavailable during these probes: a one-second sample recorded zero
PreRender events and 60 Heartbeats, and an independent short Tween remained Playing without
advancing. Loading and menu exit animations therefore could not be accepted visually. An attempt
to bring Studio forward through computer use ended in an app-approval timeout. This is an
environmental validation limit, not evidence that those animations work or that their source is
defective.

The user subsequently confirmed that the game ran successfully in a manual Studio test. Specific
menu animations, multiplayer interactions, and device layouts were not individually confirmed by
that report. Studio was back in Edit mode when MCP reconnected; no additional Play session was
started.

Pinned executables were invoked directly because Aftman shims cannot resolve their home in this
tool environment. The README documents ordinary developer commands and executable overrides. CI
configuration is added; its hosted run has not been observed in this local task.

## Remaining runtime validation

The completed single-player checks do not replace multiplayer/device playtesting. These scenarios
remain unverified:

- Visually complete loading/menu animations and normal mouse/keyboard interactions in a rendering
  viewport; resize/rotate and verify responsive layout on desktop and touch devices.
- Stop during base initialization or a missing-Humanoid wait; exercise sustained pathfinding delays.
- Use multiple players to stop combat during knockback, sliding, animation, and pooled sounds.
- Suspend an already in-flight server reply while closing/replacing Inventory or Stand; the Play
  probes covered queued cancellation and successful fresh requests, not forced network latency.
- Force loading timeout during asset preloading and test overlapping loading/menu input owners.
- Verify visible environment/claim transitions and cleanup on desktop and touch devices.

## Separate gameplay backlog

[Implementation alignment](TECHNICAL_DESIGN.md#implementation-alignment) remains the owner of
prototype-to-launch work: target Shrine production/XP and transactions, Arena spawning/capture and
combat accounting, launch catalogue/Shop/menu scope, and authored assets. Existing Hotbar/Consumables
presentation, prototype rarity labels/spawn settings, and Stand terminology require coordinated
feature/compatibility changes. They were not reinterpreted as cosmetic cleanup or silently removed.
