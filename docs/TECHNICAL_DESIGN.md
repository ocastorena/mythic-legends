# Mythic Legends — Technical Design

This document is the canonical implementation contract for architecture, networking, persistence,
transactions, and source ownership. The [GDD](GDD.md) owns gameplay rules, progression, launch
scope, pacing targets, and gameplay acceptance criteria. [UI guidelines](UI_GUIDELINES.md) own menu
behavior and presentation. [Conventions](Conventions.md) owns project structure and coding practices;
the [README](../README.md) owns setup and verification commands. Runtime tuning lives in
[shared configuration](../src/ReplicatedStorage/Shared/Configurations).

Requirements below describe the approved launch target unless explicitly labeled as current
implementation or a future update. Moving a contract into this document does not mean the prototype
implements it. See [implementation alignment](#implementation-alignment) before treating target schemas or transactions
as available APIs. Technical work must not add excluded or unapproved gameplay. Divine Intervention
remains inactive and requires separate design approval; launch systems must not depend on it.
Ragdoll requires explicit post-launch approval. The GDD's six [elemental sword
effects](GDD.md#elemental-sword-effects) are approved for launch: first-crafted swords share the
wooden sword's base statistics and each adds its configured effect. All first-crafted Shield
variants share gameplay values and have no elemental ability. Launch Equipment types are
one-handed swords and separate Shields, progressing from the plain wooden starter pair to Stage 1.
Additional archetypes and Stage 2 or later upgrades are future updates. Higher-stage stat divergence
still needs its detailed design and implementation contract; launch needs no Equipment-upgrade
endpoint or transaction.

## Runtime architecture

The first release uses the approved Rojo Bootstrap architecture and ProfileStore-backed player
persistence. `default.project.json` defines the canonical Roblox Explorer hierarchy; Studio-authored
descendants are preserved only at explicitly mixed-ownership containers.

- **MainServer** is the only server bootstrap. It initializes modules under
  `ServerScriptService.Services` in deterministic lifecycle order and owns the player join/leave
  wiring.
- **Server services** own validation, authoritative simulation, mutations, persistence requests, and
  grants. No domain service independently loads a profile or writes a Roblox DataStore.
- **MainClient** is the only client bootstrap. It initializes state/networking before feature
  controllers under `StarterPlayerScripts.Controllers`.
- **Client controllers** own input, UI, local animation, sound, VFX, and rendering of
  server-confirmed state. They cannot mutate persistent player data, Arena ownership, capture state,
  or economy state.
- **Shared configuration** is version-controlled Luau content under
  `ReplicatedStorage.Shared.Configurations`. It contains static definitions and balance values only;
  it must never be written at runtime.
- **DataService** owns one ProfileStore session per Roblox user ID using the current store namespace
  `MythicLegends_PlayerData_v2`. It reconciles defaults, associates the user ID, handles session
  termination, and ends the session when the player leaves. Explicit schema migrations are a target
  requirement; reconciliation alone is not a migration. Studio uses an isolated, ephemeral mock
  store by default.
- **Combat is the stated exception.** Its client-reported, server-validated relay and immediate
  local presentation remain exactly as defined in [client-reported sword
  combat](#client-reported-sword-combat). This architecture must not be changed by the general UI
  synchronization rule below.

## Project structure and coding conventions

[Conventions](Conventions.md) owns the [repository layout](Conventions.md#project-structure),
[Roblox Explorer hierarchy](Conventions.md#roblox-explorer-hierarchy), naming, file organization,
typing, lifecycle cleanup, formatting, and logging rules. `default.project.json` is the executable
source of the Rojo mapping. This document retains runtime responsibilities, network and persistence
contracts, UI ownership, and the [Studio/Rojo boundary](#roblox-studio-and-rojo-ownership).

## Network contract

Rojo is the only creator of production remotes. `RemoteUtil.Resolve` validates their classes and
returns the typed domain structure; it must not silently create or replace missing remotes.

```text
Network
  State       Update, Request
  Inventory   DeleteMythling
  Production  GetStatus, Collect
  Base        PlaceMythling, RemoveMythling
  Combat      StartAttack, ReportHit, SetShieldGuard, Reaction, Impact, GetLoadout, Equip
  World       Spawned, ClaimState
```

- Client-to-server messages are untrusted intent. The owning service validates types, lengths,
  ranges, ownership, permissions, world state, and cooldowns before mutating anything.
- Every client-triggered endpoint must have an appropriate server-side rate limit. Client-side
  debounce exists only for responsiveness and is never a security boundary.
- Use a `RemoteEvent` when no immediate response is required. Use a client-to-server
  `RemoteFunction` only when the caller needs an explicit success or error result. Never invoke a
  client synchronously from the server.
- Reliable gameplay state uses `RemoteEvent`; disposable high-frequency cosmetic telemetry may use
  `UnreliableRemoteEvent` only when loss and reordering are acceptable.
- Persistent state is confirmed through the revisioned State channel. Domain remotes do not accept
  arbitrary state keys, Instance paths, or generic mutation commands.

This endpoint inventory matches [default.project.json](../default.project.json). It does not claim
that all launch features already have endpoints: Shop views/purchases, crafting, sales, Shrine
construction, evolution, inventory upgrades, Shrine dismantling, and Material discard need
purpose-specific contracts as they are implemented. `Inventory.DeleteMythling` must not be treated
as an already implemented sale API.
Existing remote names stay unchanged unless an explicit migration updates declarations, resolver
types, server handlers, and client callers together.

## Client/server state synchronization

For every system other than the documented combat exception, clients send an intent request and wait
for a server-confirmed result before changing authoritative UI state.

1. The client may immediately show input feedback and a pending/loading state.
2. The server validates the request against the cached player document, metadata, runtime
   eligibility, capacity, affordability, and permissions.
3. For persistent mutations, the server uses a duplicate-safe DataService transaction while the
   ProfileStore session is active. The owning service applies runtime-only mutations without adding
   them to the profile. The server then returns or replicates the authoritative result.
4. The client updates inventory, Gold, Shrine output, Crafting Jobs, capture state, Equipment,
   Stamina, and elemental effect state only from that confirmed result. Future Consumable buffs
   follow the same rule.
5. A rejection does not spend costs or grant the requested result and supplies a player-facing
   reason when appropriate, such as `InventoryFull`, insufficient Gold/Materials, invalid selection,
   unavailable capacity, or not-in-Arena. Independent elapsed production, completed jobs, or Stamina
   accounting may still advance.

Capture meters, Stamina, active Shield state, temporary knockback immunity, elemental effect state
and deadlines, and active Arena contests are server-owned runtime state. They are not persistent;
they clear on disconnect or server shutdown. Reset clears the affected character's active/pending
effects and all capture progress. Arena transitions and Equipment changes preserve already-applied
effects and their deadlines. Owned Mythlings, earned Gold,
and other confirmed persistent progression are retained under the normal player-save contract.
Active Consumable buffs do not exist at launch, and their future disconnect behavior remains a
separate design decision.

Private player UI state uses a client-ready `Network.State.Request` snapshot followed by revisioned
incremental `Network.State.Update` packets. Only an explicit client-safe projection may be
replicated; the complete ProfileStore document, permissions, internal flags, and server-only state
must never be sent to the client. `LocalData` owns the client cache and change signal. A missed or
out-of-order revision triggers a bounded snapshot resynchronization instead of polling.

The [network contract](#network-contract) defines endpoint ownership and transport rules. Runtime
combat values may use an explicit server-confirmed presentation channel; they must not be added to
persistent profiles merely to display them.

### Transaction and save guarantees

- Serialize persistent mutations per active profile. Validate against the same state that will be
  committed, then atomically apply every affected field and the request's resolution record. A
  failure must not leave a deducted cost without its result, receipt, or refund guarantee.
- Keep request IDs and bounded resolution records sufficient to reject stale/replayed commands or
  return the original result. Reusing an ID with a different payload is invalid. The same
  transaction includes inventory, currency, assignment links, reservations, and production cursors
  whenever they are affected together.
- In-session atomicity and durable persistence are distinct. A confirmed runtime mutation must be
  included in the profile's save lifecycle, but requesting a save is not proof it reached durable
  storage. An operation that requires durable acknowledgement must observe its transaction ID in the
  persisted save result before claiming that guarantee.
- The current `MarkDirty` publishes state, and `SaveNow` requests an asynchronous ProfileStore save.
  Neither method supplies rollback, idempotency, migration, or durable-commit guarantees. The target
  transaction layer is still required; see [implementation alignment](#implementation-alignment).
- Keep the store name and profile-key namespace stable when increasing the document's schema
  version. Changing a namespace is a separate data migration, not a routine version increment.

## Client-reported sword combat

Gameplay behavior is defined by the GDD's [MVP player combat
system](GDD.md#mvp-player-combat-system) and [Shield actions](GDD.md#shield-actions). This protocol
preserves the approved MVP tradeoff: responsive visible-blade contact is reported by the attacker
and validated by the server. There is no independent server arc scan, position rewind, or
server-selected substitute target.

The logical message names used below are mapped to the existing endpoints:

| Logical message | Existing endpoint | Direction |
| --- | --- | --- |
| `MeleeSwing` | `Network.Combat.StartAttack` | Attacking client to server |
| `HitReport` | `Network.Combat.ReportHit` | Attacking client to server |
| Guard request/release | `Network.Combat.SetShieldGuard` | Owning client to server |
| Accepted launch | `Network.Combat.Reaction` | Server to target client |
| Confirmed impact | `Network.Combat.Impact` | Server to observing clients |

The logical names are explanatory labels, not additional remotes to create.

### Combat Loadout presentation

Primary Weapons and Shields are character-mounted Models rather than Roblox `Tool` instances.
Entering the Arena moves an equipped sword and Shield from their authored sheath attachments to the
R15 right-hand and left-hand attachments respectively and enables their actions.
Leaving returns equipped Models to their sheath attachments and disables attack/guard without
changing the saved Combat Loadout or clearing existing elemental effects and their timers.
Either slot may be empty; an empty Primary Weapon slot permits Shield equip.

#### Two-handed loadouts — future update contract

Additional archetypes are outside the MVP. When introduced, a two-handed weapon uses its authored
two-hand pose without a Shield. Enforce the GDD's [Equipment
compatibility](GDD.md#equipment-compatibility) on the server using the Primary Weapon definition's
static `handsRequired` value (`1` or `2`). Equipping a two-handed weapon
atomically clears `combatLoadout.shieldInstanceId` and removes protection without deleting the owned
Shield or changing its capacity use. Reject Shield equip while a two-handed weapon is equipped.
On load, reconcile an incompatible saved pair by retaining the Primary Weapon and clearing only
the Shield reference. Switching back does not automatically restore it; no restore record is saved.
An empty Primary Weapon slot permits Shield equip. Validate compatibility independently of whether
the weapon Model is drawn or sheathed, and preserve the action timing and Stamina rules below.
Archetype-specific attacks still need their own approved contracts; this retained design does not
require implementing two-handed Equipment for launch.

### Attacking client

1. One shared client attack function is the only source of a sword swing. Left click and the
   dedicated mobile Attack button may call that function, but they must not create duplicate
   activations for one input.
2. The client sends one `MeleeSwing` activation with a monotonically increasing sequence,
   immediately plays the visible swing animation, and opens its contact window from animation
   markers, with a configured timing fallback when an animation lacks those markers. A player with
   insufficient Stamina or an active Shield guard cannot begin a weapon action.
3. During that window, the client sweeps the visible sword blade through interpolated positions
   between rendered frames. Contact is based on the blade geometry, not a large character-centered
   cone.
4. The client excludes its own character and selects at most one eligible target: the target with
   the closest valid blade contact, breaking ties by attacker-to-target distance, then player user
   ID. Optional line-of-sight filtering may reject contact through solid geometry.
5. On first valid contact, the attacker immediately presents the configured hit effect, sound,
   trail, and brief animation hit-stop. It then sends exactly one `HitReport` containing the
   activation's swing sequence and the selected target's user ID.
6. A swing that finds no blade contact sends no hit report, but its activation still consumes the
   weapon's configured Stamina cost. Walking near another player without activating the sword must
   never produce a hit.

### Server validation and relay

The server does not independently scan an arc, rewind player positions, replace the reported target,
or manufacture an alternative hit. It first validates each `MeleeSwing`, including that the attacker
is not guarding, deducts its configured Stamina cost whether the swing later hits or misses, starts
the weapon cooldown, and records a short-lived authorization for that sequence. It then either
accepts a matching reported attacker-target pair or rejects it. The server rejects conflicting
action requests so simultaneous Attack and Shield input cannot grant both a swing and protection;
rejected swing requests do not consume Stamina.

Initial wooden and first-crafted swords cost 20 Stamina per accepted activation and have a
one-second cooldown between accepted start times. Settle eligible elapsed Stamina recovery before
checking affordability. The cooldown starts on activation, not animation completion; a new swing
must also respect any unfinished action lock. Hits and misses use the same activation cost.

Before accepting a `HitReport`, the server verifies:

- The attacker still owns and equips the supported melee weapon recorded in the server-authorized
  swing. The server resolves its definition from the Combat Loadout; `HitReport` does not supply a
  weapon definition.
- The attacker and reported target are distinct playable characters.
- Both characters satisfy the Arena-only rule for that weapon.
- The swing sequence matches the attacker's latest unconsumed server-authorized activation.
- The authorization has not expired and the target is not temporarily knockback-immune.
- The reported characters are within the weapon's configured reach plus a bounded server-tolerance
  distance.

On acceptance, the server consumes the authorization without deducting Stamina a second time,
assigns an idempotent hit ID, settles relevant combat accounting, and resolves whether the hit is
blocked. It resolves the configured launch and eligible elemental effect, records the target's
temporary knockback immunity, relays the launch to the target client, and broadcasts the confirmed
impact presentation. Each hit's launch, effect, and any Dark Stamina return resolve once. The server
never applies health damage.

Consuming the one-hit authorization does not end the swing's action lock. Guard remains unavailable
until the configured, server-owned swing duration ends. An accepted guard activation invalidates any
outstanding hit authorization from the finished swing, so a late report cannot land while the
attacker is guarding. Equipment changes, Arena exit, or character replacement also invalidate
outstanding hit authorizations and clear incompatible action state; switching Equipment cannot reuse
a previous swing's authorization.

Changing Equipment must not refund spent Stamina or reset the accepted attack's cooldown or action
lock, or skip a remaining guard transition. Clear invalid hit/visual state while retaining those
timing limits; an Equip request cannot be used to attack faster or raise a Shield before the
accepted swing ends.

### Elemental sword effects

Implement the GDD's [elemental sword effects](GDD.md#elemental-sword-effects) and
[initial effect tuning](GDD.md#initial-elemental-effect-tuning) through the existing accepted-hit
path. Resolve the effect from the authorized Equipment's definition/finish IDs, never a display
name or client-supplied effect. Keep effect parameters in configuration and snapshot the accepted
effect's parameters and server deadlines into runtime state; Equipment changes cannot rewrite them.

- A miss, rejected hit, immunity rejection, or paid Shield block applies no new elemental effect,
  including Dark's refund. A final paid block remains a block even when its cost then forces the
  Shield down. Blocking never clears a negative effect already running on the defender.
- Fire, Water, Earth, and Light share one negative-effect slot per affected character. The first
  eligible accepted effect occupies it; later timed effects are ignored without replacing,
  extending, stacking, or queuing. A pending Earth root also occupies this slot. Ignoring the new
  effect does not reject the accepted hit's normal knockback or immunity.
- Fire drains Stamina through the shared accounting path while ordinary recovery still follows
  guard state. Water modifies voluntary walking speed. Light modifies the affected attacker's
  total outgoing horizontal weapon force. Initialize their rates and durations from GDD tuning.
- Earth reserves the slot until the first server-observed landing after that hit's knockback,
  then roots voluntary walking/jumping for 0.75 seconds. Do not interpret the pre-launch grounded
  frame as that landing. Its pending deadline is three seconds after the accepted hit; no landing
  by that deadline releases the slot without granting recovery protection. Later hits do not
  extend the pending deadline or pause/extend an active root.
- When an actual Earth root ends, release the negative-effect slot and start three seconds of
  Earth-only protection. Another Earth effect cannot queue during that window; other negative
  effects may occupy the free slot. Neither Water nor Earth blocks forced knockback, changes body
  collisions, or independently prohibits attack/guard. Derive movement restrictions from current
  guard/effect state when an effect expires; do not restore stale movement values over another rule.
- Air adds 15% horizontal force to the same unblocked hit. If its attacker is affected by Light,
  multiply the entire horizontal force by 0.80 after the Air bonus: `1.15 * 0.80 = 0.92` of normal.
  Neither changes vertical launch, blocked-hit slides, or Shield costs. Air does not create a
  second hit or bypass immunity.
- Dark returns three Stamina to the attacker once per accepted unblocked hit, capped at maximum,
  after the full 20-Stamina swing payment. Air and Dark are immediate benefits and remain eligible
  against a target whose negative-effect slot is occupied.
- Both participants must be inside the Arena for a new hit. Existing effects and their landing,
  expiry, and Earth recovery deadlines continue across either player's Arena transition or
  Equipment change. Fire may drain outside and a pending Earth root may activate there. Reset or
  disconnect clears the affected character's effect state and capture progress; removing the
  original attacker does not clear effects already on another character. Bind callbacks to the
  affected character identity so an old timer cannot modify its replacement.
- Publish confirmed active/pending status and relevant deadlines for presentation. Outside the
  Arena, retain readable effect feedback and Stamina while Fire remains; attack/guard stay disabled.
  Clients may render visuals and countdowns, but cannot authorize effects or determine expiry.

### Target client and presentation

- The target client applies the relayed launch with a short eased force curve rather than a delayed
  velocity spike. Hit IDs prevent the same launch from being applied twice.
- Temporary knockback immunity starts after an accepted hit and rejects further accepted weapon
  knockback hits until its configured duration ends. It does not disable or counteract normal
  player-body collisions, and those contacts do not grant or refresh immunity.
- The attacker's locally rendered impact suppresses its duplicate server broadcast. Other clients
  render the server-confirmed impact.
- Visual and audio presentation is cosmetic. Failure to render an effect must not change hit
  validation, capture progress, temporary knockback immunity, or server-owned elemental effect state.

### Security boundary

Because the attacking client chooses the target, an exploit can fabricate plausible sword reports
within the server's distance, cooldown, Combat Loadout, Stamina, immunity, and Arena checks. This
risk is accepted for the MVP and must be revisited if competitive stakes increase. Lightweight rate
monitoring and server telemetry may be added without restoring an independent server hit scan.

The client-reported exception ends at the positional combat reaction. Capture Ring membership,
capture meters, contest resolution, Mythling awards, Stamina accounting, Shield eligibility,
elemental effect selection/limits/timing, persistent progression, and all rewards remain
server-authoritative. Approved elemental effects do not expand client authority beyond reporting
contact and applying the confirmed physical reaction.

The target client applies the relayed physical reaction; server-owned capture meters do not make
client physics tamper-proof. A client that ignores displacement can affect its position in a
contest. Do not describe this architecture as fully exploit-resistant. Any later mitigation must
preserve the approved contact-reporting boundary unless the design is explicitly revised.

## Stamina and guard accounting

The GDD's [Shield actions](GDD.md#shield-actions) define the guard threshold, full-cost defender
blocks, action exclusion, and the rule that Stamina does not regenerate while the Shield is raised.
Server runtime state owns Stamina and guard eligibility; animation, client input, and displayed
values cannot authorize protection.

- Initialize maximum Stamina and character-spawn Stamina to 100 and eligible regeneration to
  10 Stamina per second. A new character after reset receives the configured spawn value;
  entering/re-entering the Arena or changing Equipment must not refill the current character.
  Recovery continues during sword actions while the Shield is fully lowered. It stops throughout
  raising, guarding, and lowering, with no post-lowering delay or retroactive guarded-time credit.
- When processing guard requests, protection markers, and incoming hits, grant Shield protection
  only for an owned, equipped Shield and a compatible Loadout. Remove protection immediately if
  eligibility is lost, regardless of delayed callbacks. The future two-handed compatibility
  contract uses this same path; ordinary unshielded hits remain valid.
- Validate positive configured `impactStaminaCost` and `minimumGuardStamina`, with
  `impactStaminaCost <= minimumGuardStamina <= maximumStamina`. Resolve costs and the threshold from
  Equipment metadata and the maximum from combat configuration.
  Initialize the wooden Shield's cost and minimum to 30 each and the first-crafted Shield's to
  25 each, shared across all six variants and acquisition routes.
- Configure the initial full-Stamina guard targets through those existing values: three accepted
  paid blocks for the wooden starter Shield and four for the first-crafted Shield definition shared
  by all six elemental variants. Featured copies use the same definition and values. With maximum
  Stamina `M`, impact cost `C`, minimum guard threshold `G`, and target block count `N`, require
  `M - (N - 1) * C >= G` and `M - N * C < G`, alongside `C <= G <= M` and positive values.
  This permits the final full-cost block, then immediately removes protection and begins lowering.
  It does not require Stamina to reach zero. Validate using continuous guard with no recovery and
  accepted hits separated by immunity and no other drain, such as Fire; rejected hits cannot spend
  block Stamina. Do not add a
  durability field, hit allowance, or resettable block counter. Current Stamina determines every
  block's eligibility, including after re-equipping or raising from partial Stamina.
- Serialize Loadout changes, attack authorization, guard activation/release, elemental effect
  application/expiry, and incoming-hit resolution against the same combat state. Raising, raised, and lowering guard states reject
  attacks, independently of whether protection remains eligible. An active swing rejects guard
  activation until its action lock ends. An animation transition cannot leave Shield protection
  active during an attack.
- The server recognizes eligible protection at the authored `GuardRaised` marker and normally
  removes it at `GuardLowered`. A marker callback is timing input, not authority to override current
  eligibility. Insufficient Stamina, leaving the Arena, or unequipping removes protection
  immediately; delayed visuals must not extend it.
- Bound raise/lower transitions with configured server-owned timing. Missing markers, interrupted
  animations, or lost client callbacks must reach a valid lowered/cleanup state within that bound;
  they cannot leave an unprotected player permanently unable to attack or recover Stamina.
- Before reading or spending Stamina, settle elapsed recovery and active Fire drain together using
  the **previous** server-owned guard/effect state. Split accounting at effect and guard transitions,
  clamp elapsed time to nonnegative, and clamp Stamina between zero and maximum. Apply the net rate
  over each interval; separately capping recovery before subtracting Fire would produce the wrong
  result at full Stamina. Advance the last-accounted time even when no Stamina is added.
- Fire crossing the guard minimum immediately removes protection and starts normal forced lowering.
  Resolve that threshold crossing and the resulting guard transitions chronologically, including
  when settling elapsed time; Fire cannot leave an ineligible guard active until the next input.
  Dark's accepted-hit return uses this same settled balance and never refunds a miss or blocked hit.
- Before each guard-state transition, settle the interval up to the transition time under the old
  state, then change the state. Raising, raised, and lowering intervals grant zero recovery until
  the Shield is lowered; existing Fire drain still applies. Losing protection through depletion
  must not by itself classify a still-raised
  Shield as lowered for regeneration. Track raised lifecycle and protective eligibility distinctly
  when they differ. Regeneration starts at the transition into fully lowered, at the configured
  rate, with no additional recovery delay after either normal release or a guard break. Lazy updates
  must never credit time spent guarding retroactively after release, depletion, Arena exit, or
  unequip.
- An accepted Shield block deducts the complete cost from the defender after settling runtime
  accounting. Recheck eligibility immediately; remove protection if the remainder is below the
  threshold. A fresh eligible request is required to guard again. Do not use partial-cost spending
  or wait for a cosmetic effect to finish before removing an ineligible guard.
- Apply the same accounting path to regular refreshes, guard requests, incoming hits, action
  requests, effect application/expiry, and forced cleanup. Publish only the resulting server-confirmed values.

Keep the approved initial values configurable. At maximum 100, the wooden Shield leaves 10 after
three blocks and the crafted Shield leaves zero after four; both lose protection immediately.
With the Shield fully lowered and no spending or elemental Stamina changes, validate two seconds from zero to an affordable
20-Stamina attack and ten seconds from zero to full. For an action lock that permits one-second
starts, continuous eligible recovery supports attacks at seconds 0 through 8 from full Stamina,
rejects an unaffordable attack at second 9, and permits the next at second 10. Do not mistakenly
validate this as a five-attack allowance or suspend recovery during swings to force that result.
Guard transitions, attack contact/animation windows, immunity, and knockback remain to be tuned;
never shorten an active lock to satisfy the arithmetic example. These block counts describe guard
endurance, not guaranteed hits before leaving a ring; existing slide and body-collision rules apply.
Also verify Fire's fully lowered 100-to-90 reference over two seconds, forced lowering when its
drain crosses the guard minimum, and Dark charging 20 before returning three on an unblocked hit.
Neither effect may grant recovery during a guard phase or make full-rate attacks sustainable.

## Arena population lifecycle

Enforce the GDD's [population and availability
rules](GDD.md#server-population-and-spawn-availability) through server-owned contest state. The
deployed launch server limit is eight players, and shared configuration specifies a capturable
target initially set to 12 and a maximum refill delay initially set to three seconds. Use the
same target in quiet and full servers; player count does not scale availability.

- For every new contest, independently select the rarity with initial probabilities of 75% Common,
  20% Rare, and 5% Epic, then uniformly select one of its six elemental forms. Apply this to both
  initial fill and replacements; do not enforce fixed rarity counts or roll rarity onto an owned
  form. Retain the chosen form through placement retries so failed positions cannot bias selection.
- Separate capturable-contest registration from model lifetime. Only unclaimed contests with valid
  active Capture Rings contribute to availability; pending attempts, claimed/escort models,
  decoration, and ended contests do not. Overtime contests remain registered and capturable.
- Populate to all 12 before enabling capture on a fresh server. Claiming or despawning a contest
  unregisters its capturable capacity immediately and schedules replenishment; delayed model cleanup
  must not hold the slot. Reaching the countdown deadline alone does not free an overtime contest's
  slot or trigger replacement.
- Resolve each contest's spawn lifetime once: use the named form's optional override when present,
  otherwise its configured rarity's default. Initially all three launch defaults are 240 seconds
  and all 18 launch forms have no override. At the moment it becomes capturable, record the
  server start time and expiry deadline in runtime contest state. The initial population starts
  its countdowns together when capture opens; placement retries and prefill must consume no lifetime.
  Replacements start their own countdowns when registered as capturable. Entry, re-entry, and later
  configuration changes cannot reset or recompute an existing deadline. This is spawn state,
  not an owned Mythling attribute or player-save field; clients render the authoritative deadline.
- Measure each replacement deadline from the old contest's removal from capturable registration
  to the replacement's valid capturable registration, initially at most three seconds. Permit
  enough replenishment work to replace simultaneous removals within their individual deadlines;
  do not apply a three-second wait to each successive spawn in a serial queue.
  Validate non-overlap and ring placement before registering a new contest; a failed placement
  retries an alternative without counting as a spawn. Persistent placement failure is a
  map/configuration failure, not permission to overlap rings or extend the refill deadline.
- Capacity and exactly-one-award checks remain authoritative through contest resolution. Disconnect,
  reset, reaching Mythling capacity, and contest termination clear the relevant capture meters;
  entering overtime does not.
- Resolve progress, occupancy changes, countdown expiry, and awards through one ordered server
  contest lifecycle. Select the earliest eligible server-calculated completion time. For exact
  ties, use the server-recorded entry order for each player's current uninterrupted ring visit;
  leaving and re-entering starts a new visit. Record a unique entry sequence to resolve entries
  observed in the same update without using client timestamps.
- Resolve eligible completions through a lifecycle event's time before ending the contest. This
  includes a completion exactly at the countdown deadline or at the last occupant's departure.
  Award or despawn once; stale timers, entry events, and award requests cannot reopen an ended
  contest or produce a second result.
- At the countdown deadline, despawn an empty ring; otherwise enter overtime and preserve all
  meters. During overtime, continue normal capture and decay, allow new entrants, and end with
  capture or the first server-observed empty-ring state. There is no extra overtime timer.
- Track occupancy from connected players' current characters inside the ring independently of
  inventory capacity or meter existence. A full-inventory occupant keeps overtime active but
  cannot gain progress or receive an award. Reset/disconnect remove old-character occupancy; if
  this empties an overtime ring, end it. Delayed model cleanup does not preserve occupancy.
- Use one server membership test for capture progress/decay, uninterrupted visit and entry order,
  and overtime occupancy. Test the character root's horizontal position against the ring footprint,
  with a finite configured vertical allowance around the ring's floor that includes standing and
  the full normal-jump arc. A normal jump inside the footprint remains one uninterrupted visit;
  crossing the horizontal edge starts decay normally. Ground contact and airborne animation states
  do not determine membership. A character far above or below the ring must not count as inside.
- Store meters per contest and per player. Entering a different Capture Ring starts or resumes that
  contest's meter while previous meters decay normally; it does not reset them merely because the
  player's current target changed.
- Initialize every Common/Rare/Epic launch form to a 20/35/60-second uninterrupted capture
  respectively. Resolve rates from that form's configuration, not a runtime stage/rarity formula.
  For a meter normalized from zero to one, its progress rate is `1 / captureDurationSeconds` and
  its initial decay rate equals its progress rate. Scale both consistently if the representation
  uses percentages. Apply elapsed server time inside/outside the shared membership rule, clamp
  progress to its valid range, and award at completion through the ordered lifecycle above.
  Decay starts on leaving the ring, with no delay or immediate full reset; normal jumps inside
  retain progress. Re-entry retains remaining progress but receives new uninterrupted-visit priority.
- Validate authored island boundaries under walking, jumping, and configured knockback. Spawn
  placement must leave room to push players out of a Capture Ring before an outer barrier stops
  them; the population target does not justify rings pinned against boundaries.
- Wild Mythling presentation models must not physically block player movement or support standing
  on them. Keep Capture Ring membership detection independent of the model's physical collision.
  Player bodies retain [Roblox's default character collision behavior](https://create.roblox.com/docs/workspace/collisions#disable-character-collisions)
  in the Arena. Let the normal physics response handle body contact without extra push forces,
  custom contact resistance, or contact-specific Stamina costs. Do not change body-collision behavior
  when guarding or weapon-knockback-immune; the existing restriction on voluntary walking/jumping
  while guarding still applies. Ordinary contact never creates a sword-hit authorization, Shield
  block charge, combat-impact effect, or immunity event.
- A reset returns the player to the assigned Base spawn. Clear that player's capture meters and
  invalidate the old character's attack authorizations, guard state, forces, and pending reactions
  before rebuilding character presentation from the existing profile. Late messages from the old
  character must not affect its replacement. Reset is not a profile join or an online/offline
  production transition: it must not regrant starter items, replay offline accrual, or cancel Shrine
  assignments and Crafting Jobs.

## Production accrual

The [production calculation](GDD.md#production-calculation) and [Mythling
progression](GDD.md#mythling-progression) rules in the GDD own Yield, XP, storage, and evolution
behavior. The server implements those rules as fixed chronological batches on a common schedule
across a profile's Shrines, using saved accrual time and mutable state. Worker changes do not shift
that schedule.

Set each launch Common/Rare/Epic form's initial unmodified base Yield to **12/18/32 Materials/hour**
respectively in Mythling metadata, shared across the six elements. These are fixed form values,
not an additional rarity multiplier. Convert rates consistently when accruing working seconds;
one unchanged worker earns one Material's worth of progress in 300/200/112.5 seconds respectively
before level scaling. These are nominal production times, not batch intervals or separate per-item
timers. Retain the existing batch cadence for production and activity-based XP, including intervals
that advance unfinished progress without completing an item. Resolve completed whole output at the
normal batch boundary; clients cannot grant it from a displayed countdown.

Resolve level-adjusted Yield as `currentFormBaseYield * (1 + yieldGainPerLevel * (level - 1))`,
with shared initial `yieldGainPerLevel = 0.01` and a level cap of 100 across all launch forms.
Sum assigned workers' level-adjusted Yield. The same deterministic rate applies online and offline;
launch production has no Luck rolls, Lucky Yield bonus, or Passive Trait modifiers.
This is an additive base-Yield bonus, not compound growth. Derive it from current form metadata
and saved level, without persisting a copied rate or accumulated Yield bonus. Preserve fractional
rate precision until whole-output accounting. Evolution settles prior work first, then uses the
new form's base Yield at the retained level; levels gained in a batch affect later batches only.

Shrine storage and Material inventory contain non-negative whole quantities only. Track unfinished
production separately as progress toward the next completed Material; it is not a stored or
collectible item. Preserve enough progress for low Yield to eventually complete an item.

Unfinished progress belongs to the built Shrine instance. Swaps, removals, and evolution retain the
work already earned there; new Yield affects subsequent work only. A moved Mythling does not carry
production progress to another Shrine. With no assigned workers, retain progress without accruing
output or XP; resume when workers are assigned and never backfill the empty interval. Online/offline
transitions likewise retain progress and do not change production rates or worker eligibility.

The activity owns the XP earning rate. Launch has one shared Shrine-work `baseXpPerSecond = 1` in
production configuration, used across all elements and Mythlings. Shared progression metadata
sets the next-level requirement to `120 * currentLevel` XP, with cap 100; it does not set the
activity's earning rate. Cumulative XP from level 1 to level N is `60 * N * (N - 1)`.
Initial evolution links require level 6 for Common-to-Rare and level 40 for Rare-to-Epic.
At the initial activity rate, levels 6/40/100 take 1,800/93,600/594,000 eligible working seconds,
resolved at normal batch boundaries. Keep these values configurable; chronological accrual must
process every earned level before subsequent batches, including during offline settlement.
Reaching the level cap does not stop Material production when storage is available. Yield, form,
rarity, and online/offline status do not modify the activity's XP rate. No additional activity system
or player XP is needed for launch.

Luck, Lucky Yield, and Passive Traits are deferred together. New launch captures neither roll nor
require Luck or a Trait. Preserve any existing saved Luck values and Trait IDs as inactive legacy
data; they affect neither production nor XP and are not exposed in launch UI. Their future
acquisition, effects, configuration, and migration behavior need a separate approved design.
Initial Shrine capacities are 300/1,200/3,600 whole Materials at levels 1/2/3 across all elements;
derive capacity solely from Shrine level, never from assigned workers or a target fill duration.

1. Resolve the Shrine's output Material, capacity, assigned Mythlings, and current form/level
   statistics from saved IDs and the current production configuration. On join, process unresolved
   offline time with that configuration; retaining old production-rule versions per player is not
   required. Keep the configuration consistent throughout
   one accrual transaction. Never reprice already settled output or awarded XP.
   Sum eligible workers' level-adjusted Yield without a Shrine-level production multiplier. Upgrading
   capacity does not increase individual Yield or the activity's XP rate, and empty slots produce
   nothing.
2. On join, collection, and any change to production conditions, settle the preceding interval under
   its saved assignments and form/level progression, using the configuration policy above. Perform
   this settlement before assignment/removal, evolution, or a Shrine upgrade mutates those inputs.
   Preserve earned contributions to an unfinished batch under the inputs that produced them;
   do not recalculate prior work using the replacement worker's stats.
   Changes do not restart batch timing or force an extra completion. The normal accounting schedule
   continues through empty intervals, which add no work.
3. Resolve working batches in chronological order across affected Shrines. Each Mythling earns
   `baseXpPerSecond * eligibleWorkingSeconds` for its own time assigned while storage is available,
   including work toward an unfinished Material. Concurrent workers each earn independently. Retain
   earned XP contributions by owned Mythling instance ID when workers change; never calculate the
   whole batch from its final roster. Award at the normal batch boundary, including credit earned by
   removed but still-owned workers. Pending credit belongs to the owned Mythling and survives
   dismantling its former Shrine. Resolve due credits on the profile schedule, including on join
   and before level-dependent actions, even if no source Shrine remains. Empty/full intervals add no
   credit; a level gained in one batch affects later batches only.
4. For each interval with unchanged inputs, accumulate new production work as
   `newWork += summedLevelAdjustedYieldPerHour * eligibleWorkingSeconds / 3600` for the current
   batch. Empty/full-storage intervals add no work. At the normal batch boundary, add `newWork`
   to prior unfinished progress, store the completed whole Materials that fit, and retain the
   remainder only while storage has space. Clear the resolved batch's new work together with its
   result. No random roll or additional multiplier is applied to new or retained work.
   The batch that fills storage grants each worker's normal time-earned XP even when some output
   cannot fit. Discard overflow rather than banking it as output or unfinished work. Subsequent
   full-storage time produces no Materials or XP.
5. Commit stored output, unfinished production progress, any unresolved batch work,
   pending XP contributions, level/XP changes, and the accrual cursor together through DataService.
   Consume each pending credit once; moving, selling, or replacing a Mythling must not redirect its
   XP to a different instance. Retain sub-unit XP precision with the earned state instead of
   rounding each short interval independently.
   Retries and repeated collection requests must not award a resolved batch's output or XP twice.
   Full-storage time must not become deferred production or XP after space is freed.
6. Use the same accrual calculation online and offline, with server-authored timestamps; clients
   do not supply elapsed production time. Session boundaries are recovery bookkeeping, not modifiers.
   Settle online accrual before normal profile release and record `offlineSince`. At online
   checkpoints, settle each Shrine before advancing `lastOnlineCheckpointAt`; commit both together.
   After an unclean shutdown, the precise disconnect time may be unavailable: use the last persisted
   checkpoint as an estimated offline boundary. This recovery can treat unsaved online time as
   offline; it must never replay time before a Shrine's saved cursor. On join, settle the saved
   offline interval before clearing `offlineSince` and starting online accounting.
7. Collection settles accrual, computes the whole quantity that fits in destination Material
   capacity after active crafting reservations, and atomically transfers that quantity. Keep the
   uncollected Materials in the Shrine and preserve unfinished production progress and batch timing.
   Zero available space produces a capacity rejection; a positive partial transfer returns its
   actual quantity and the remaining stored output. If no completed Material is stored, return the
   empty-storage state instead of misreporting an Inventory capacity problem.

Production and XP retain their working-batch cadence; completing an individual Material does not
create an extra XP award. Future Luck, Traits, and rare-Material output must preserve whole-output,
capacity, and settlement guarantees, but need no launch configuration or runtime support.

For accounting verification, 0.8 previously retained progress plus 0.2 newly earned work gives
one whole Material and zero remaining progress, assuming storage has space. Splitting an unchanged
interval into smaller settlements, swapping workers, or reconnecting must preserve already earned
work and XP rather than rounding each interval or replaying its result.

### Space recovery transactions

- **Base expansion:** validate the configured build-slot upgrade, progression eligibility, and
  sufficient Gold plus every collected Material in its fixed elemental mix. Only owned spendable
  Inventory quantities count; Shrine output and crafting refund reservations cannot pay costs.
  Require the requested upgrade to be the next unpurchased expansion and current
  unlocked capacity to be below the configured six-slot MVP limit. Atomically spend all costs and
  persist the purchase, adding exactly one unlocked Shrine slot. Reject stale, repeated, or
  over-limit purchases without another charge or capacity grant. Derive unlocked capacity from
  the two starting slots and saved expansion purchases, independently of current Shrine occupancy;
  dismantling, reset, and reconnect cannot remove a purchased slot.
  Price changes do not revoke purchased slots or require a retroactive payment.
  Base build capacity counts constructed Shrines only; the permanent Crafting Station is outside
  that capacity. Shrine construction must validate available build space against the same count.
- **Shrine upgrade:** validate ownership, the expected current level, the next configured level,
  and sufficient Gold and collected matching normal Material. Launch permits only level 1 to 2
  and level 2 to 3. Settle production under the old level, then atomically spend the costs and
  update the saved level; derive the added assignment slot and increased storage from metadata.
  Retain the Shrine instance, existing assignments, stored Materials, unfinished production, and
  earned XP. The added slot is empty; upgrades never assign a Mythling automatically. A stale,
  duplicate, unaffordable, or level-3 upgrade request cannot spend costs or advance the level again.
  Changing storage does not backfill time previously spent full. Use one level field and one
  upgrade operation, with no independent storage or worker-slot purchase state.
- **Shrine dismantling:** validate owner and the built Shrine's instance ID, settle accrued state,
  and require no assigned Mythlings or stored whole Materials. Atomically remove that Shrine record
  and free its build slot, then remove its runtime model. Discard its unfinished production progress;
  do not issue a refund or create a stored-building record. A stale or repeated request cannot
  remove a replacement structure or generate value. The permanent Crafting Station cannot be
  sold, dismantled, or replaced through a construction request.
- **Mythling sale:** validate the selected owned instance, sell eligibility, and that it is
  unassigned. Resolve the fixed Gold value from its current form metadata; XP level, inactive legacy Luck/Traits,
  and acquisition route do not modify the payout. Do not use the originally captured form, an
  inferred rarity/stage multiplier, or a client-supplied payout as authority. If the selected form
  or quoted price changed before commit, reject the sale and refresh its details. Atomically remove
  that owned instance, grant its Gold value, and record the result. Serialize with assignment and
  evolution; retries return the recorded result without another removal or payment. Selling the
  final copy is allowed. Do not persist a second sale-price field on owned Mythlings.
- **Material sale:** validate a positive finite whole quantity, enabled Material metadata, and enough
  owned Inventory quantity. Resolve the fixed unit Gold value from server configuration and compute
  the total; the client cannot set the price or payout. Atomically remove the requested quantity,
  grant Gold, and record the request result through the existing per-profile transaction path.
  Reject stale or insufficient quantities rather than selling a different amount. Duplicate requests
  return the recorded result without repeating the sale. Shrine storage and crafting refund
  reservations are not owned Inventory quantity; the sale cannot consume either or release a job's
  reservations. Offline output must be collected before sale, using the same path as online output.
- **Material discard:** validate ownership and a positive whole quantity, then atomically remove
  only the requested owned amount. Return the actual authoritative inventory state. Do not touch job
  receipts, refund reservations, Shrine storage, or Gold. Stale quantities are rejected rather than
  silently discarding a different amount.
- Collection, sales, discard, assignment, upgrades, and dismantling share the per-profile transaction path.
  UI confirmations do not replace server validation, and retries must not repeat completed mutations.

## Crafting transactions

The GDD's [crafting rules](GDD.md#crafting) define one included permanent Station per Base, one active
Equipment job, offline completion, and exact cancellation refunds. Implement those promises through
one server-authoritative transaction path while the profile session is active.

- **Start:** validate that the recipe and result are enabled for the launch scope, then validate
  its unlocks, the player's permanent Station, idle status, affordability, and Inventory capacity.
  The Station itself has no purchase or unlock requirement.
  All launch sword and Shield recipes initially use a configured 60-second duration. Resolve the
  completion timestamp from the server start time and snapshot that deadline in the receipt.
  Resolve the result definition and optional finish from the selected recipe on the server. Finish
  recipes have fixed matching-Material inputs; reject conflicting client-supplied result/finish
  values and do not substitute another recipe or its inputs.
  Atomically deduct the actual costs, create the receipt, and reserve both promised Equipment output
  space and enough Material capacity to return the paid inputs. A rejected start changes none of
  those fields. Repeated requests cannot create duplicate jobs or charges.
- **Receipt:** record job/recipe/station IDs, result definition ID, optional finish ID, promised
  quantity, actual paid Material quantities and Gold, start/completion times, resolution status,
  and output/refund reservations. Paid costs are transaction history, not a copied recipe.
- **Capacity:** every acquisition must account for all outstanding reservations, including
  compatible Material stack space. Reservations are not owned items and cannot be spent, equipped,
  or sold. Restore them with the saved job before processing acquisitions on join.
- **Resolution:** compare the server time with the recorded completion time. A due job completes
  before a cancellation is considered; an unfinished cancelled job returns exactly its recorded paid
  costs. Output/refund grant, status transition, and reservation release are atomic. A
  completion/cancellation race or retry cannot grant both outcomes or grant either twice.
- **Delivery:** completion automatically grants the recorded result and finish into its reserved
  Equipment capacity and makes the station idle. There is no separate awaiting-claim job state.
  On join, restore receipts/reservations and resolve due jobs before accepting acquisitions or
  another job start.
- **Offline:** resolve due jobs on a server tick, profile join, or station interaction. A live timer
  is a convenience, not the source of truth for completion. Reservations remain valid while the
  player is offline and until the job resolves.
- **Metadata changes:** later recipe edits must not change existing receipt costs, output/finish, or
  completion time. Definition and capacity migrations must preserve existing promises and
  reservations; metadata changes cannot silently strand a job or make its refund impossible.
- **Bounded history:** retain enough resolution/request information for duplicate-safe behavior
  without letting completed/cancelled job records grow without a bound in player saves.

Waiting queues, station levels, additional stations, and Consumable recipes are future additions.
Their migrations must extend these guarantees while preserving existing prototype player data.

## Shop transactions

Implement the GDD's [Shop](GDD.md#shop) through the existing server-authoritative, per-profile
transaction path. The launch catalogue contains all six normal Materials, rotating first-crafted
Equipment, and eligible Inventory upgrades; purchases do not require the corresponding Shrine.
Initialize configurable schedule, stock, and pricing from the GDD's [Shop tuning](GDD.md#shop).
The initial refresh interval is one hour (60 minutes), shared by Materials and Featured. Featured
offers one matching sword and Shield pair per period, rotating Fire → Water → Earth → Air → Light
→ Dark → repeat over six hours. Clients display the server's schedule rather than hard-coding it.
Exhausted allowances remain unavailable until their scheduled restock.

- **Refresh authority:** use server time and one configured schedule to identify the current
  refresh period and its Featured selection consistently across servers. Resolve the fixed rotation
  from a shared configured epoch and period index, not from server start or player join. Opening the Shop,
  reconnecting, server hopping, and character reset do not reroll offers or restore stock. Period
  definitions and prices are stable within their window; publish changes at a scheduled boundary
  without granting an extra restock. Do not accept client time or a server-local random assortment
  as the authority. Unavailable current catalogue data blocks purchases until it can be resolved.
- **Personal stock:** save the current period ID and purchased quantities by stable stock key.
  Material stock keys identify the normal Material; Featured keys identify the configured offer.
  Derive remaining quantities from configured limits minus saved usage. When entering a newer
  period, replace previous usage with the new period's usage; do not accumulate missed allowances.
  A catalogue revision must not reset usage within a period. Inventory-upgrade ownership is separate
  and is never cleared by restocking. Persist stock usage with the same active profile session as Gold.
- **View:** return a client-safe snapshot with period/offer revision, exact item references, Gold
  prices, personal remaining stock, eligibility, and next refresh time. Material offers reference
  the Material's configured unit buy price; Featured offers own their premium Equipment price.
  Inventory upgrades include their configured Gold cost, fixed Material IDs/quantities, owned
  spendable amounts, and eligibility. The view reserves no stock, Gold, Materials, or Inventory space.
- **Purchase:** for Materials and Featured, validate a bounded request ID, current period and offer
  revision, offer ID, positive finite whole quantity, launch eligibility, remaining personal stock,
  affordability, and capacity.
  Resolve item/variant and price on the server; never accept a client-selected result or price.
  Use the shared Inventory calculation, including active crafting output/refund reservations.
  Atomically deduct the exact Gold cost, grant the exact owned quantity, increment stock usage,
  and record the result. Reject the entire request if anything is unavailable; do not silently
  reduce quantity, substitute an item, or release a Crafting Job's reservations.
- **Delivery:** purchased Materials enter ordinary Inventory stacks. Each purchased Equipment copy
  gets a unique owned instance with the offer's definition/finish IDs and normal fixed rarity;
  `isStarterGrant` is false. Delivery is immediate, uses one Equipment slot per copy, creates no
  Crafting Job, does not auto-equip, and awards no Shrine-work XP.
- **Inventory upgrades:** validate exactly one requested next upgrade, expected current level,
  eligibility, configured Gold cost, and every owned Material quantity in its fixed elemental mix;
  reject a requested quantity other than one, a skipped upgrade, or a purchase after that category's
  second upgrade. Each purchase adds 12 slots to its category only; track progression independently
  for Materials, Mythlings, and Equipment. Resolve the exact recipe on the server; do not accept
  substituted elements or silently change a quoted cost. Atomically spend Gold and collected
  Materials, grant the upgrade, and record the result. Protect crafting refund reservations.
  These purchases require no available item slot or stock period and consume no Shop restock
  allowance. A full Inventory can still upgrade when it already owns all required costs; those
  ingredients must fit before the upgrade. Preserve purchased capacity through later price changes
  without retroactive charges.
- **Races and retries:** serialize purchases with sales, crafting, and other profile mutations.
  For stock-limited offers, check the period at transaction commit, including requests arriving
  near refresh. An uncommitted expired offer is rejected with an updated view, never replaced by the
  new period's offer. A
  previously committed retry returns its recorded result without another grant or charge, including
  after refresh; do not erase its receipt merely because stock has restocked. Keep receipt history
  bounded under the existing duplicate-safe mutation rules and reject expired unresolved requests.

## Content configuration

Content and balance data must be separate from game logic and versioned. At minimum, configuration
defines:

- Mythling: `id`, display name, element, fixed form rarity, `evolutionStage` (1, 2, or 3 for the
  launch roster, internal metadata only), visual assets, form-specific base Yield, shared acquisition
  and progression settings, one optional evolution target and its required level, lore, an optional
  spawn lifetime override, sell eligibility, and a fixed Gold sell value for that named form.
  XP level, inactive legacy Luck/Traits, and acquisition route do not
  modify the sell value; evolution resolves the new current form's value. Stage describes the
  form's position in its chain, not its level or rarity. Resolve rarity directly from each form;
  do not derive it from stage or roll an owned rarity variant.
  Initialize all six Common forms at 12 Materials/hour, all six Rare forms at 18/hour, and all six
  Epic forms at 32/hour before level scaling. Keep these trial values configurable and validate
  increasing base Yield within each chain.
- Mythling progression: shared configurable `yieldGainPerLevel = 0.01`, level cap 100, and next-level
  XP coefficient 120. All launch forms use the same curves above; level 1 has no Yield bonus.
  Launch evolution links initially require levels 6 and 40, with no additional time-in-form gate.
- Production: fixed batch interval and one shared Shrine-work `baseXpPerSecond`, initially 1.
  XP earning rates belong to activity configuration, not Mythling definitions. Add rates for other activities only
  when those activities are approved.
- Mythling acquisition: starting level 1 and 0 XP for every new capture, independent of captured
  stage, rarity, or element. Keep these defaults in shared configuration and validate the launch
  values; clients cannot supply starting progression. No Luck range, Trait pool, or acquisition
  roll is required for launch. Retained legacy Luck/Trait data remains inactive and must not make
  those definitions, effects, or APIs launch dependencies.
- Shrine: element, output Material, levels 1/2/3 with 1/2/3 assignment slots and increasing shared
  storage capacities initially 300/1,200/3,600, Gold-only level-1 build
  cost, and Gold/matching normal Material upgrade costs. All six elements use the same level
  structure. No Shrine production multiplier
  is needed for the MVP; validate the three-level limit, slot counts, increasing storage, and
  matching-Material costs before enabling construction or upgrades.
- Base: two initial build slots usable only by Shrines, four sequential Gold-and-Material expansions that
  permanently grant one slot each, and a maximum of six unlocked slots for the MVP. Keep these
  values, Gold costs, and fixed mixes of multiple normal Material IDs/quantities in configuration.
  The included permanent Crafting Station uses no build slot.
- Crafting Station: default definition, Base placement, and eligible Equipment recipe groups.
  Launch includes one permanent Station per Base with one active job; no build price or Station
  unlock requirement is configured.
- Material: id, element, display information, crafting uses, sell eligibility, fixed unit Gold
  sell and buy prices, stack limit, and optional rare variant. All six normal launch Materials are
  sellable and listed for purchase, with an initial stack limit of 1,000 each. Material metadata owns
  their unit prices; Shop offers reference
  these values without a second price override. Prices are static tuning, not market prices or
  saved per-player values; tune sales as supplementary Gold under the GDD economy rules.
- Arena spawn: eligible stationary Mythlings, rarity-weighted selection pool, valid positions/ring
  spacing, ring vertical membership allowance accommodating normal jumps, capturable-population
  target initially 12 for every server population, maximum refill delay initially three seconds,
  default spawn lifetimes keyed by rarity, references to named-form lifetime overrides, and per-Mythling
  `captureProgressPerSecond` and `captureDecayPerSecond`.
  The deployed server player limit must match the eight-player launch rule.
  Initial rarity probabilities are 75% Common, 20% Rare, and 5% Epic, with equal element weights
  within each group. Initialize per-form rates for 20/35/60-second captures respectively, with
  decay equal to capture growth. Spawn lifetimes remain separate from capture durations: resolve
  the form override first, then the rarity default. Set Common, Rare, and Epic lifetime defaults
  to 240 seconds for the first trial, with no overrides on the 18 launch forms. Retain optional
  named-form override support for future content; do not use capture duration as a lifetime default.
- Equipment: id, category, visuals, knockback/protection behavior, cooldown, weapon Stamina cost or
  Shield impact cost and minimum guard Stamina, Primary Weapon `handsRequired` (`1` for launch
  swords; `2` is reserved for future two-handed archetypes), sell eligibility/value, internal stage,
  Equipment type, and supported element variants. Each Stage 1 base
  Equipment definition owns the type's shared model and base gameplay values. Its variant metadata
  defines an ID, element, full item display name, fixed rarity, recolor, and, for swords, an approved
  elemental effect reference. All six swords retain the wooden sword's base statistics, timing,
  costs, reach, and contact geometry; effects are their only gameplay difference. Shield variants
  share the crafted Shield's values and have no elemental effect. Use the GDD's named pairs:
  Fire/Vulcan, Water/Triton, Earth/Atlas, Air/Aura, Light/Sol, and Dark/Nyx, each with Sword and Shield.
  These are element-variant names, not shared progression-stage identifiers.
  Equipment rarity is fixed static metadata for each named item, independent of stage. Resolve it
  from the named variant selected by `definitionId` and `finishId`, or from the base definition for
  plain items. Display names are presentation, not lookup keys. Every copy resolves the same rarity;
  do not roll rarity, accept a client-supplied rarity, or add an owned rarity field. Equipment uses
  the GDD's shared Common/Rare/Epic/Legendary/Mythical vocabulary as quality categories. Resolve gameplay
  values, recipe costs, and sell values from their owning definitions without a separate rarity
  multiplier. Preserve existing player data when aligning the implementation. Rarity must not bypass
  the shared base statistics or add another effect multiplier across element variants.
  When two-handed archetypes arrive in a future update, their configured knockback implements the
  GDD's [stronger-force tradeoff](GDD.md#equipment-compatibility) at the same Equipment stage. Handedness
  does not itself multiply attack Stamina cost, cooldown, or the defending Shield's impact cost,
  bypass eligible protection, or force a guard break; resolve those values from their owning
  definitions under the existing combat rules.
- Player combat: maximum Stamina, regeneration rate, immunity duration, swing/guard transition
  timing and fallbacks, configured spawn Stamina, and bounded validation tolerances.
  Initially set maximum/spawn Stamina to 100 and lowered-state recovery to 10 per second. Equipment
  definitions own the initial 20-Stamina sword cost, one-second start-to-start sword cooldown,
  wooden Shield cost/minimum of 30, and crafted Shield cost/minimum of 25. Variant metadata and
  acquisition routes cannot override these shared base gameplay values. Configured elemental effects
  are applied through the accepted-hit contract, not by changing an item's base Stamina cost.
- Elemental sword effect: stable ID, role, magnitude, duration, and applicable landing/recovery
  timings. Initialize Fire/Water/Earth/Air/Light/Dark from the GDD's
  [initial effect tuning](GDD.md#initial-elemental-effect-tuning). Only the six approved roles are
  launch-enabled. The timed-negative-effect limit and immediate Air/Dark behavior follow the
  [effect contract](#elemental-sword-effects). Store no effect definition or active timer in owned
  Equipment or player saves; presentation text and visuals reference the same effect metadata.
- Recipe: input Materials and Gold, result Equipment definition, optional result finish ID,
  quantity, duration, eligible Crafting Station, and unlocks. Each Stage 1 variant has a fixed
  recipe; its Material input comes from the matching element's normal Shrine output. The UI groups
  these recipes by base Equipment definition rather than requiring six separate catalogue entries.
  Initial duration is 60 seconds for every launch sword/Shield variant; active jobs retain the
  deadline recorded at start when configuration changes.
- Inventory upgrade: tab affected, slot increase, Gold cost, fixed mix of multiple normal Material
  IDs/quantities, eligibility, and prerequisite upgrade. Configure two sequential +12-slot upgrades for each
  launch category, independently purchased. Initial limits are Materials 12 → 24 → 36,
  Mythlings 24 → 36 → 48, and Equipment 12 → 24 → 36. Each category's first upgrade costs
  20,000 Gold plus 50 of each of the six normal Materials; its final upgrade costs 300,000 Gold
  plus 200 of each. Players cannot select alternative payment Materials.
- Shop: shared refresh schedule, stable period/offer revisions, all six normal Material references
  and personal quantity limits, and the Featured rotation with offer IDs, Equipment definition/finish
  references, premium Gold prices, and personal quantity limits. Inventory upgrades reference their
  existing definitions and do not participate in stock refresh. Static offers, limits, and schedules
  belong here, not in player saves; Material unit prices remain owned by Material metadata. Start
  with a 3,600-second shared period and the GDD's fixed six-element matching-pair rotation.
- New-player defaults: starting Gold, Inventory capacities, starter Equipment definition IDs, and
  initial Base/unlock state, including the permanent Crafting Station definition.

Initialize the owning configuration modules from the GDD's
[initial economy tuning](GDD.md#initial-economy-tuning). Keep new-player Gold, Mythling and Material
sell values, Shrine costs, recipe inputs, and Shop offers consistent with that budget. Starting Gold
is a once-only new-profile grant; do not overwrite existing balances on reconnect or migration.
Price changes apply through their existing metadata/refresh rules and cannot rewrite active Crafting
Job receipts or repeat a completed transaction. UI reads confirmed configured values without its own
hard-coded price table.

Mythling `evolutionStage` and Equipment stage describe internal progression positions for content
organization and validation. Do not generate player-facing labels, filters, or item/form name suffixes
from these fields. UI resolves actual display names, rarity, and statistics; evolution previews use
the configured next-form reference. Mythling XP levels and Shrine levels remain visible under the
[UI Guidelines](UI_GUIDELINES.md).

Validate configuration references and launch invariants before enabling their systems: starter
Equipment capacity must hold both protected items plus the first recipe's output (at least three
slots for a one-item recipe), guard thresholds must be affordable at maximum Stamina, evolution
targets must retain the element and form an acyclic progression, and enabled recipes, structures,
and spawn pools must resolve to valid launch definitions. Numeric values remain configurable;
invalid metadata must not create an unfinishable job or an invalid grant.

Validate the GDD's [launch Mythling roster](GDD.md#launch-mythling-roster) as an MVP catalogue
constraint: six chains, exactly one per element, with three distinct form IDs at stages 1/2/3.
Each Stage 1 target is that element's Stage 2 form; each Stage 2 target is its Stage 3 form; Stage 3
has no target. Reject branching, skipped stages, cross-element links, and incomplete enabled launch
chains. This catalogue's rarity mapping is Stage 1/Common, Stage 2/Rare, and Stage 3/Epic; it is not
a generic evolution rule. Every form is eligible for wild spawning. Initial aggregate probabilities
are 75% Common, 20% Rare, and 5% Epic, with equal chances for the six elements within each rarity;
keep these weights configurable. Validate normalized group probabilities and uniform within-group
selection for both initial fill and replacements, not exact population counts in a small sample.
All six forms within each launch rarity initially share the 20/35/60-second capture durations
respectively and equal progress/decay rates. Validate positive finite rates, consistent meter units,
and a positive finite resolved spawn lifetime that permits each form's uninterrupted capture
without requiring overtime. Require a valid default for every enabled rarity, reject invalid
configured overrides rather than silently falling back, and validate arrival time on the actual map.
For the initial trial, validate all 18 launch forms resolve to 240 seconds from their rarity
defaults without per-form overrides. Capture times remain 20/35/60 seconds; a shared lifetime
does not make capture progress rates equal. Later configuration changes affect new spawns only,
preserving active contests' recorded deadlines.
The roster does not require every form to be present simultaneously. Legendary and Mythical content
must not enter the launch spawn pool. Retain legacy owned form references when introducing the
approved launch roster.

Validate positive whole-Gold sell values for the launch forms: one equal value across all six
Common forms, one higher equal value across the six Rare forms, and one higher equal value across
the six Epic forms. These are configured catalogue values, not runtime rarity multipliers. Preserve
existing owned levels and inactive legacy Luck/Trait data; sale valuation does not rewrite progression. Resolve any
retained legacy forms through their metadata without enabling them as new launch acquisitions.

Evolution logic follows the current form's optional target and required level. Absence of a target
means no further evolution; do not infer this from rarity or a hard-coded Stage 3 check. The target
form supplies its own rarity, which may retain or change the previous rarity. This metadata model
also supports standalone Mythlings without evolution chains and shorter, two-form chains when
those future updates ship. They are excluded from the launch catalogue; a terminal form within one
of the six complete launch chains remains valid even though it has no next-evolution target.
Evolution is a requested player action, never an automatic consequence of offline accrual. Settle
due XP before checking its required level, preserve level/XP through the form change, and resolve
the new form's next link afterward. A sufficiently leveled Common can evolve twice through two
valid sequential actions; do not reset XP or add a training requirement after the first action.

Validate increasing base Yield through each launch chain. New launch captures receive no Luck or
Trait roll, and no retained legacy value modifies launch behavior. Evolution preserves any existing
legacy values without activating them. Resolve rarity from current form metadata, without a
separate owned rarity roll or production/XP multiplier. Production is determined by assigned forms,
levels, eligible working time, and Shrine storage, equally online and offline.

On a new capture grant, retain the captured form's metadata ID and initialize `level = 1`, `xp = 0`,
and no pending earned XP. Do not derive starting level from that form's evolution threshold.
Use these defaults only when creating the newly awarded owned instance; repeated award requests,
reconnect, character reset, evolution, and migrations must not reinitialize existing progression.
Captured launch Stage 2 forms use their own next-evolution requirement, while launch Stage 3 forms continue
earning levels under the normal cap without another evolution target.

Validate that enabled launch Equipment is limited to plain wooden gear and Stage 1 swords and
Shields. Enabled launch recipes produce Stage 1 sword or Shield variants. New crafting, Shop offers,
and rewards must not introduce Stage 2 or later Equipment or depend on Equipment upgrades. Apply
these acquisition restrictions to new requests; preserve existing owned Equipment records and
resolve recorded Crafting Jobs under their original receipts.

Each Stage 1 Equipment type must have all six supported element variants and matching fixed recipes.
Recipe results must reference a finish supported by that Equipment definition; all Stage 1 variants
resolve that type's same base gameplay values. Each sword variant references exactly its approved
elemental effect, while wooden starter gear and all Shields have none. Validate effect magnitudes
and durations against the GDD's starting values, finite positive timing parameters, matching
elements, first-effect-wins behavior, and Dark's unsustainable full-rate attack budget. Crafted and
Featured copies resolve identical effects. Each enabled named item or variant must resolve one
valid configured rarity: Common for the wooden starter definitions and Rare for all six first-crafted
variants of each launch Equipment type. Epic, Legendary, and Mythical Equipment are excluded from new
launch acquisitions; preserve existing owned records. These are catalogue assignments, not a generic
stage-to-rarity formula. Crafting grants take the named item from the recipe's result references;
there is no separate rarity selection or roll. Existing plain Equipment and legacy recipes may omit
the finish ID for compatibility; this does not enable additional plain recipes for launch.

Validate Shop offers against the same launch catalogue: all six normal Materials remain listed and
every Featured item is an existing craftable Stage 1 sword or Shield variant with its fixed recipe.
Validate a positive refresh interval, coherent period/offer references, and positive finite whole
stock quantities and Gold prices. Each Material's unit buy price must exceed its unit sell price.
For every enabled Equipment recipe, total output resale value must be below the cost of buying its
Material inputs plus its Gold cost. Each Featured price must exceed that purchased-input crafting
cost for the same output quantity, and exceed the output's resale value. Validate these inequalities
together when changing recipes, buy prices, or sell values; a stock limit is not a substitute for valid prices.
Check the configured Material allowances and prices make buying missing inputs a usable alternative,
while preserving the GDD's first-craft route through any one Shrine without Shop purchases.
For the initial tuning, validate each Material allowance against the inputs for one matching sword
and one matching Shield. Configure exactly one Featured sword and one Featured Shield of the same
element per hourly period, with one copy of each per player. Validate the shared Fire → Water →
Earth → Air → Light → Dark cycle, its six-hour repeat, and unchanged offers/stock after server changes.
Use the GDD's initial economy prices and validate their ratios
and every resale inequality. The initial recipe produces one Equipment copy, uses five matching
normal Materials, and requires a 10-Material allowance for a matching sword-and-Shield pair.
Changing recipe quantities requires rechecking the corresponding allowance and Equipment price.

Reference validation is insufficient for progression. Check cost/unlock dependencies against the
GDD's [Shrine and recovery rules](GDD.md#shrine-rules): required Materials must be obtainable through
already available Shrines or approved Shop stock before their cost is charged, and required inputs must
fit the Inventory capacity reachable before the relevant upgrade. Reserved Equipment output must fit
alongside items the player cannot sell. A full launch Mythling inventory must have a valid
space-recovery action. Initial spawn countdowns must allow an uninterrupted configured capture before
overtime is needed, including the initial 60-second Epic capture. Verify these paths with actual
launch configuration; valid IDs alone do not make them reachable.

Validate that all six elements' basic level-1 Shrines use the same Gold-only price, including
rebuilds. Starting Gold must cover one without selling the first capture. Validate Gold-and-Material Base
build-slot upgrades: two starting slots, one added per purchase, and six unlocked slots at most.
Validate initial access to one permanent Station outside the Shrine-only build slots. Equipment
recipes retain their Gold/Material costs. Check the first craft and evolution against the GDD's
[early progression targets](GDD.md#early-progression-targets) using
one Shrine and the included Station, with no Station purchase cost. Also check the route with two
starting Shrines; the Station must remain usable when both build slots are occupied.
Repeat this route for each first-Shrine element and its corresponding Stage 1 variant recipe;
no route may require a second element's Material to reach that first craft.
Baseline timing must work without rare captures. Derive the first
evolution target from the shared activity XP rate and that Mythling's eligible working time across
sessions; full-storage and unassigned intervals do not contribute.
Use the revised Common production baseline when validating this route: five recipe Materials take
25 minutes of unchanged base-rate work. Distinguish
time since joining from eligible production time and ingredient readiness from job completion.
Each initial craft adds 60 seconds after its start. Shop inputs can shorten acquisition time but
cannot substitute for validating each Shrine's independent route. Keep the roughly 30-minute
first-evolution work target independent of this lower Material throughput.

Validate all upgrade recipes against the GDD's [upgrade saving targets](GDD.md#upgrade-saving-targets),
including a first Shrine upgrade taking days. Base and Inventory recipes use equal quantities of
all six normal Materials; Shrine upgrades retain matching-element inputs. Required inputs must be reachable
with pre-purchase Shrine slots, realistic limited Shop stock, and pre-purchase Material capacity.
Do not use the capacity being purchased to justify fitting its own costs. Pacing calculations must
account for Materials retained for payment instead of treating them as simultaneous Gold-sale income.
Initialize the level-1-to-2 Shrine price at 1,000 Gold plus 400 matching normal Materials for all
six elements, following the GDD's initial economy values. The starting Material Inventory must
hold this payment without a capacity upgrade. Collect and accumulate it across Shrine visits;
do not raise the level-1 Shrine's 300 storage or spend uncollected output to make the recipe fit.
Initialize the level-2-to-3 Shrine price at 15,000 Gold plus 4,000 matching normal Materials for
all six elements. At the initial 1,000-per-type stack limit, the two Shrine upgrade payments need
one and four Material slots respectively; both fit the 12-slot starting Material Inventory when
that space is available. Accumulate collected output across visits while level-2 Shrine storage
remains 1,200. Validate each Inventory-capacity upgrade's own costs against the capacity available
before that purchase, including crafting reservations. The Material category's first and final
upgrades must fit 12 and 24 Material slots respectively; Mythling and Equipment upgrade costs must
fit Material capacity reachable beforehand. Round required stack slots up separately for every Material ID.
Six different elemental stores of 3,600 each require 24 slots, not 22; verify collection into the
first upgraded bag with sufficient free capacity and partial collection when existing stock or
reservations limit space. Validate the other categories' initial limits, both +12 grants, and
independent maximums against the GDD's [Inventory limits](GDD.md#inventory-capacity-and-overflow).
Initialize the four Base expansions at 10,000/50,000/150,000/500,000 Gold plus 50/100/150/200
of each normal Material respectively. Inventory upgrades use the two per-category prices above.
Every recipe occupies six Material stacks at the initial limits, before other owned quantities
and reservations are considered. Validate every required Material ID and quantity; an equal
total quantity of substituted elements is not a valid payment. Purchases do not require owning
the matching Shrines. Test missing-element acquisition at the existing 10-per-refresh allowance,
including duplicate-element Base layouts, without scaling Shop stock or requiring dismantling.
Gold sets most Base/Inventory saving time; missing-element Shop allowances can also constrain it.
Preserve existing paid upgrades through cost changes without retroactive charges.

Luck and Passive Trait acquisition/effect definitions, Consumable definitions, buff-stack rules, and
expanded Crafting Station queue/upgrade definitions are added with their future updates. They are
not required launch configuration, and launch validation must accept records without Luck or a Trait.

## Player save data

The persistent player document stores lightweight, mutable player state. It references static
metadata by ID rather than duplicating names, descriptions, models, recipes, visual assets, or
immutable base statistics.

At minimum, the target document shape is:

```text
version
profile                 -- user/profile timestamps and approved flags only
currency.gold           -- uncapped mutable Gold balance
materials[materialId]   -- whole quantity only; stack rules come from Material metadata
inventoryUpgrades[tabId] -- purchased upgrade IDs/levels; derive capacity from configuration
shop                    -- current refresh period ID and purchased quantities by stable stock key
equipment[instanceId]   -- definitionId, optional finishId, isStarterGrant, unique mutable state
combatLoadout           -- optional primaryWeaponInstanceId and shieldInstanceId
mythlings[instanceId]   -- owned Mythling schema below
base                    -- build-slot upgrades, constructed Shrines, permanent Station record
productionClock         -- server-authored lastOnlineCheckpointAt and optional offlineSince
craftingJobs[jobId]     -- at most one active Crafting Job at launch; receipt and reservations below
unlocks                 -- approved progression/unlock flags
requestReceipts         -- bounded mutation IDs/results for duplicate-safe resolution
```

`shop` stores only mutable current-period usage. Derive offers, prices, limits, and refresh times
from configuration. Reconnects restore usage before purchases are enabled; a new profile receives
an unused current-period allowance, and an existing profile advances only when the schedule reaches
a newer period. Keep completed purchase results in bounded `requestReceipts` independently of stock
rollover. Forward-only migrations preserve Gold, Inventory, upgrades, and any existing purchase usage.

`base` saves only player-specific state. Each built Shrine record contains a unique `id`, its static
`shrineId`, current level, whole stored output quantity, unfinished production progress, unresolved
batch `newWork`, last production-accrual time, and assigned Mythling instance IDs by slot. Keep prior
unfinished progress separate from unresolved batch work so reconnects cannot replay it and worker
changes cannot recalculate work already earned. The required permanent Crafting Station record
contains a stable unique `id` and its static `craftingStationId`, independently of
Shrine build slots. Station levels are introduced with the future upgrade system. Structure
elements, Material output, capacities, slot grants, and Shrine build costs are resolved from metadata.

Initialize the permanent Station once per profile without charging currency or Materials. Base
allocation, reset, and reconnect reconstruct its world presentation from the same saved identity;
they must not create another Station or restart its job. Migrations reuse an existing Station
identity when present and preserve active-job links, promised result/finish, paid costs, deadline,
and reservations. Remove any legacy Station occupancy from the build-slot count without removing
Shrines or jobs. No separate purchased-Station flag or construction receipt is required at launch.

The Shrine slot map is the sole persisted source of assignment. An owned Mythling may appear in at
most one slot across the Base. Build reverse lookup indexes from this map on load;
`assignedShrineId` and `assignedSlotId` may be derived for a client-safe view, but are not a second
saved authority. Validate ownership, matching elements, and valid slots before counting production.
Resolve invalid legacy links without deleting the owned Mythling. Assignment or removal settles
affected production and changes the slot map in one transaction.

The originally granted sword and shield carry server-owned `isStarterGrant` identity in their
Equipment records. Initialize that pair once per profile, retain its identity through migrations,
and reject sales or destructive removals of those instances even after unequip or reconnect. Clients
cannot set or clear this flag. Other instances of the same Equipment definitions follow normal
metadata eligibility; do not make repeatedly crafted wooden gear permanently unsellable. Character
resets rebuild the saved Loadout presentation and never issue a new starter grant.

Each owned Mythling occupies one Mythling slot whether assigned or unassigned. The initial 24-slot
capacity therefore supports 18 Shrine workers and six spares; assignment grants no extra capacity.
All launch Equipment remains in `equipment[instanceId]` and counts toward Equipment capacity whether
equipped or unequipped, including both protected starter instances. Each copy uses one slot, so the
starter pair occupies two of the initial 12 Equipment slots. The deferred storage box adds no launch
container schema or transfer path.

For the Stage 1 contract, `finishId` is the saved element-variant reference; the player-facing term
is **element variant**. Save it beside the base `definitionId`; resolve the internal stage, element,
full item name, fixed rarity, colors, shared model/base statistics, and sword effect from metadata. Crafting receipts
retain the promised definition/finish IDs; do not duplicate static rarity in owned items or receipts.
Stage 2 and later upgrades are outside the MVP and require their own approved progression contract
rather than adding arbitrary base-stat overrides to Stage 1 finish metadata. The approved launch
sword effect reference is the only gameplay-specific addition to that variant metadata.
The server sets the variant from the crafting receipt or validated Shop offer and retains it through
equip/unequip, reset, and reconnect. It is fixed on that instance. Each acquired copy uses one
Equipment slot; UI grouping introduces neither stackable Equipment nor a separate
cosmetic-unlock inventory. Missing finish IDs retain the plain appearance of starter and existing
prototype Equipment without regranting items or changing `isStarterGrant`.

Material quantities are aggregated by metadata ID; occupied stack slots are derived from quantity
and configured stack size, rounding up separately per Material ID (initially 1,000 units per slot).
Capacity checks also account for active reservations and purchased
per-tab upgrades. Inventory upgrades persist as ownership/level state, never as copied static prices
or slot-grant definitions.

Use one shared server-side capacity calculation for collection, capture awards, purchases, and
crafting. Domain services supply their intended changes; they must not maintain independent copies
of stack/slot or reservation arithmetic. Likewise, online, offline, and pre-mutation production use
the same accrual path so collection timing cannot change how much work has already been earned.

Active jobs store the receipt fields and reservations defined in [crafting
transactions](#crafting-transactions). Those amounts, IDs, and timestamps preserve each agreed
result, refund, and timing across metadata changes. Resolved history must remain bounded.

Consumable ownership, Hotbar assignments, and additional Crafting Station/queue state are future
schema additions through forward-only migrations. They are not required fields for a new launch
profile. Existing prototype fields must not be destructively removed merely because their features
are deferred. Accessible progression through ordinary Arena captures uses existing Mythling
ownership, Material, and Gold state; it adds no separate participation balance or
fallback-progression record.

An owned Mythling entry must contain at least:

```text
id                 -- unique owned-Mythling instance ID
mythlingId         -- current Mythling-form metadata ID
level
xp                 -- progress toward the next level, retaining earned precision
pendingXp          -- earned credit and scheduled batch time, cleared when awarded
acquiredAt
```

Evolution updates `mythlingId` to the evolved form's metadata ID. The saved entry stays small while
the game resolves the current form's base Yield and other immutable data from metadata. Resolve
`evolutionStage` from the current form definition; do not duplicate it or the chain's static data in
the owned record. Mythling Stage 2/3 support is part of launch and is independent of the deferred
Equipment-upgrade system. New records need no Luck or Trait fields. Preserve any existing `luck`
and `traitId` values through saves, evolution, and migration as inactive legacy data; do not delete,
overwrite, reroll, display, or apply them during the MVP.

When migrating legacy production state, retain already stored Materials, awarded/pending XP,
unfinished progress, and recorded unresolved new work exactly once. These are earned state;
do not reverse an already settled bonus. A legacy `luckWeightedWork` value is not production work
and must never become an additional grant, chance, or multiplier under launch accounting. Retain
that legacy value inertly if present, without requiring it in new Shrine records. Advance production
only from the saved cursor with the deterministic launch rules; do not reroll or reprice earlier
work. Use an explicit forward-only migration before resuming accrual if a prototype schema needs
translation; do not infer a missing work quantity from its former Luck weight.

Pending XP is earned mutable credit, not a saved copy of the activity's rate. Keep it on the owned
Mythling so unassignment, moving, or Shrine dismantling cannot erase it. Clear it once awarded or
when that owned instance is retired; never transfer it to a replacement instance.

## Data ownership matrix

Equipment rarity belongs to the named item's static metadata. Owned records retain the IDs needed
to resolve it, without a separate rarity roll or saved copy of the static value.

| Game data | Metadata (static, version-controlled) | DataService player document (mutable) | Runtime-only server state |
| --- | --- | --- | --- |
| Mythling form | `mythlingId`, name, element, rarity, evolution stage, visuals, base Yield, shared acquisition defaults and progression curves, evolution target/level, Arena eligibility, capture tuning, optional spawn lifetime override, sell eligibility and fixed form Gold value | Owned instance ID, current `mythlingId`, level, XP with retained precision, acquisition data; inactive legacy Luck/Trait values only if already present | Spawned contest, occupancy/entry order, per-player capture meters, countdown/overtime state; reverse Shrine-assignment index |
| Shrine-work XP | Shared activity `baseXpPerSecond` | Pending earned credit and scheduled batch time on each owned Mythling; awarded XP stays on that instance | Per-worker eligible time and resolved activity rate |
| Luck and Passive Traits (future) | No required launch definitions; future update needs an approved design | Existing legacy `luck` and `traitId` retained unchanged; absent on new launch captures | None at launch |
| Material | `materialId`, element, display data, stack limit, fixed unit Gold sell/buy prices, crafting use | Quantity by `materialId` | World pickup/claim state, if introduced in an approved system |
| Equipment | Base definition ID, stage/type, category, model, Primary Weapon hands required, base gameplay values, sell eligibility/value, supported variant IDs/elements/item names/recolors/sword effect references, fixed rarity per named item | Owned instance ID, definition ID, optional finish ID referencing the Stage 1 variant, starter-grant identity, Combat Loadout references, approved unique mutable state | Equipped selection and variant presentation, cooldowns, Shield state |
| Gold | None beyond balance presentation/configuration | Uncapped `currency.gold` balance | None |
| Inventory capacity | Initial per-tab limits, stack rules, upgrade IDs, slot grants, Gold costs and fixed Material mixes, eligibility | Purchased per-tab upgrade IDs/levels | Derived occupied/available capacity, including job reservations |
| Shop | Refresh schedule, period/offer revisions, Material references and limits, Featured selection, Equipment references/prices/limits; Inventory-upgrade references | Current period ID and purchased quantities by stable stock key; bounded purchase results in mutation receipts | Current catalogue view, derived personal remaining stock and next refresh time |
| Base | Build-slot upgrades with Gold costs and fixed Material mixes, slot grants/limits, Shrine eligibility, included Station definition/placement | Purchased build-slot upgrade state, constructed Shrine records, permanent Station record | Spawned Base model references and Shrine-only build-slot occupancy |
| Shrine | `shrineId`, element, output Material, levels 1–3, storage capacities, 1/2/3 assignment slots, upgrade costs | Instance ID, level, whole stored output, unfinished progress, unresolved batch new work, last accrual time, assigned Mythling IDs | Current production resolution during accrual/collection |
| Production clock | Batch interval and approved accrual rules | Last online checkpoint and optional offline-start timestamp | Active session/transition accounting |
| Crafting Station | `craftingStationId`, included Base placement, eligible recipes, single-job launch limit | Stable permanent instance ID and definition ID | World presentation and current menu/session references |
| Recipe and Crafting Job | `recipeId`, fixed inputs, Gold cost, result definition/finish/quantity, duration, unlock requirement | Job ID, recipe/station instance IDs, status, start/completion time, promised result including finish, actual paid costs, output/refund reservations | Completion scheduling while a server is live |
| Arena spawn rules | Rarity-weighted pool, capturable-population target, refill window, positions, rarity-default lifetimes and optional named-form overrides, capture rates | None | Capturable Mythlings and Capture Rings including start/expiry timestamps and overtime, initial-population readiness, pending replenishment |
| Player combat | Equipment/effect tuning and animation/VFX references | Equipment ownership and Combat Loadout | Stamina, hit sequence/recent hit IDs, immunity, cooldowns, active Shield, knockback, active/pending negative effect and deadlines, Earth recovery deadline |
| Mutation resolution | Request validation and retention rules | Bounded request IDs and recorded results | Per-profile serialization and pending save tracking |

The server validates every client request that changes inventory, currency, Equipment, production,
or capture. Persistence must use bounded document sizes, retry handling, periodic saves, safe
failure behavior, and forward-only schema migrations. Reconciliation only supplies missing defaults;
it does not migrate renamed fields or reinterpret old records. Use the [transaction and save
guarantees](#transaction-and-save-guarantees) for atomicity and durability.

## UI composition and ownership

Production GUI is Rojo-owned and composed under one Fusion-managed application lifetime. Screens may
use scoped Fusion composition or focused imperative component factories such as
`UI/Components/Panel`; both must register cleanup with the owning scope. Studio is a preview and
runtime-testing surface, not the source of truth for application UI. `UIController` owns one Fusion
scope and mounts one `UI/App` root after client state/network initialization.

### ScreenGui roots

- Create production `ScreenGui` roots from `StarterPlayerScripts.UI.Screens` and parent them
  directly to the local player's `PlayerGui` from the single `UI/App` composition root.
- Use stable `PascalCase` names for semantic instances such as `MainPanel`, `ItemList`, and
  `CloseButton`; code must not depend on incidental decorative wrappers.
- Set root lifecycle properties explicitly, including `ResetOnSpawn`, `DisplayOrder`, inset
  behavior, and `ZIndexBehavior`.
- Interactive application panels use `CoreUISafeInsets`, device-safe clipping, and no legacy
  fullscreen-extension transform. The persistent HUD may use a full-screen canvas only for
  deliberately top-bar-aligned chrome.
- Do not create a controller per visual widget. Add a component when it has a reusable visual
  contract; otherwise keep the element inside its owning screen.

### Visual ownership

- Define frames, labels, buttons, constraints, layouts, padding, fonts, gradients, strokes, corners,
  responsive layout, and selection navigation in repository-owned UI modules.
- Keep component-specific visual properties with the component. Put only genuinely shared colors,
  spacing, typography, responsive metrics, layer values, and animation durations in `UI/Theme.lua`.
- Use Studio to inspect and tune the runtime result. Any accepted visual change must be made in Rojo
  source so a clean build reproduces it.

### Behavior ownership

- Keep feature input and domain behavior in bootstrapped modules under
  `StarterPlayerScripts.Controllers`. Keep visual composition in `UI/Screens` and reusable
  presentation in `UI/Components`.
- A controller captures shared dependencies through `Init(context)`, resolves required UI
  descendants and subscribes to state/domain events in `Start()`, and releases every owned
  connection or task in `Stop()`.
- Controllers must update views from `LocalData` or a server-confirmed domain event. Do not use
  polling loops, duplicate remote listeners, or UI properties as authoritative game state.
- `UIController` coordinates replication and the single Fusion scope. Focused feature controllers
  own domain interactions; they do not rebuild visual hierarchies. Avoid both a monolithic UI router
  and controller-per-widget fragmentation.
- Adapt `LocalData` keys into Fusion state through `UI/State`. Do not create a second client cache:
  the adapter subscribes to `OnStateChanged` and exposes only the reactive value needed by a screen
  or component.

### Reusable components

- Put declarative visual components under `StarterPlayerScripts.UI.Components`. Reserve
  `ReplicatedStorage.Assets.UI` for client-visible image, model, and effect assets rather than
  executable UI composition.
- Give each component a small props-and-callback contract. Components never read or mutate server
  data directly and never create their own authoritative state store.
- Store published image, font, sound, and animation IDs in metadata/configuration rather than
  scattering IDs through view controllers.

### Mythling thumbnails

- Inventory and detail views render the `thumbnail` declared by the current Mythling form; clients
  never receive cloned gameplay models solely for UI previews. Existing prototype `variants.regular`
  entries are legacy metadata to align with form definitions, not approval for launch cosmetic
  Mythling variants.
- Generate thumbnails during authoring from the canonical model in
  `ServerStorage.ServerAssets.Mythlings`, using consistent camera framing, lighting, background, and
  output dimensions.
- Upload the generated image as a Roblox Image asset and record its `rbxassetid://` value in
  `ReplicatedStorage.Shared.Configurations.Mythlings`. API keys and upload credentials remain
  outside the repository and are never available to runtime scripts.
- Adding a Mythling requires its server model, configuration entry, and thumbnail asset ID; it must
  not require changes to UI controllers or server services.

### Security and presentation boundary

- The client may present input feedback, pending states, and cosmetic prediction, but it may not
  grant currency/items, approve purchases or crafting, or mutate persistent data.
- The server validates every intent and replicates the confirmed result that drives the final UI
  state.
- Presentation, mobile safe-area behavior, touch targets, legibility, and accessibility follow [UI
  guidelines](UI_GUIDELINES.md). Technical ownership does not change the approved UI rules.

## Roblox Studio and Rojo ownership

Rojo and Studio are complementary, but a given instance must have one clear owner. Never edit the
same instance hierarchy independently in both places and expect Rojo to merge it safely.

### Keep in the Rojo repository

- All Luau source, bootstraps, services, controllers, utilities, types, tests, and vendored
  packages.
- The canonical Explorer hierarchy, instance classes, important properties, and all network
  definitions in `default.project.json`.
- Static metadata, balance values, feature configuration, schema versions, and player-data
  templates. Mutable player state never belongs in source files.
- All production application UI composition, components, responsive rules, state bindings, and
  behavior.
- Published asset IDs and their configuration. Keep editable source assets such as `.blend` files in
  the repository when practical; do not treat a published Roblox asset as the only source copy.
- Toolchain configuration, documentation, and migration notes.

### Author in Roblox Studio

- Terrain and large spatially authored map composition.
- Spawn placement, lighting composition, attachments, particle emitters, and other content whose
  authoring depends on the 3D viewport.
- Complex Roblox models, rigs, and animations. UI may be explored in Studio, but accepted
  application layouts are implemented in Fusion source rather than retained as Studio-only
  instances.
- Instance properties that cannot be represented safely or ergonomically through the current Rojo
  source format.

Studio-authored production content should still be backed up or exported into version control when
practical. Reusable models can be checked in as model artifacts; external art source files belong
under `art/`; published animations, sounds, meshes, and images must have their asset IDs recorded in
metadata.

Keep production runtime templates under `ServerStorage.ServerAssets`. Put inactive source templates,
place backups, and future Mythling models under `ServerStorage.Authoring`; runtime services must
never search that folder. Keep editor-only model data such as `InitialPoses` and `AnimSaves` under
`ServerStorage.Authoring.Mythlings.<ModelName>` so it is not cloned into the runtime world.
`ServerStorage.ServerAssets.RBX_ANIMSAVES` is retained in place as Roblox Animation Clip Editor
authoring data and is not a production asset or legacy code.

### Runtime-only content

- Objects created for a live server session belong under `Workspace.Runtime` and must never be
  authored, persisted, or synced back through Rojo.
- Player save data belongs only in the server data framework. Do not store it in replicated
  Instances, attributes, source modules, or Studio mock objects.
- Temporary combat state, cooldowns, capture progress, active effects, and spawned encounters remain
  server-owned memory unless the data contract explicitly marks a client-safe projection.

For mixed Studio/Rojo parents such as `Workspace.Map`, `Workspace.Visuals`, and
`ServerStorage.ServerAssets`, use `$ignoreUnknownInstances` deliberately so Rojo preserves
Studio-authored children. Rojo owns the mapped container and source-backed descendants; Studio owns
only the explicitly documented unknown descendants.

`ReplicatedStorage.Network`, `ReplicatedStorage.Shared`, `ReplicatedStorage.Packages`,
`ServerScriptService`, and `StarterPlayerScripts` are strict Rojo-owned code boundaries. Unknown
descendants there are architectural drift and are removed by a clean sync; Studio-authored content
belongs only in the documented mixed-ownership containers.

The generated root `Packages/` directory maps to `ReplicatedStorage.Packages` and contains shared
Wally dependencies. Server-only vendored libraries stay under `src/ServerScriptService/Packages`;
server-only Jest dependencies map under `ServerStorage.Tests`. See [dependencies](#dependencies).

## Dependencies

These facts are verified from repository manifests, lockfiles, source headers, and Rojo mappings:

| Dependency | Repository record | Ownership |
| --- | --- | --- |
| Rojo 7.7.0, Wally 0.3.2, Selene 0.31.0, StyLua 2.5.2 | [aftman.toml](../aftman.toml) | Development toolchain |
| Fusion 0.3.0 and Trove 1.8.0 | [wally.toml](../wally.toml), [wally.lock](../wally.lock) | Generated shared `Packages/` |
| Jest and JestGlobals 3.20.0 | [test manifest](../tests/wally.toml), [test lockfile](../tests/wally.lock) | Server-only test packages |
| ProfileStore | [vendored source](../src/ServerScriptService/Packages/ProfileStore.luau) | Server-only package; its header credits MAD STUDIO / loleris |

An exact upstream revision and local-change history for the vendored ProfileStore file are not
established here. Do not infer either from its credit header. Generated packages and built place
files are not hand-edited; use the installation and verification workflow in the
[README](../README.md).

## Implementation alignment

This is a bounded list of prototype differences verified against source on 2026-09-08. Update or
remove each item when the implementation is aligned; these notes do not authorize new gameplay.

| Area | Current source | Target contract / required alignment |
| --- | --- | --- |
| Player document | [PlayerDataTemplate](../src/ServerStorage/Databases/PlayerDataTemplate.lua) is version 2 with `consumables`, `base.stands`, and Equipment `definitionId` records. It does not yet include the complete target Shrine/job/finish schema. | Introduce target fields with forward-only migrations. Keep `definitionId` for base Equipment references, add optional `finishId` for Stage 1 element variants, and preserve existing player data when retiring prototype-facing features. |
| Profile transactions and durability | [DataService](../src/ServerScriptService/Services/DataService/init.lua) currently reconciles defaults and exposes direct sections, `MarkDirty`, and `SaveNow`. The vendored [ProfileStore](../src/ServerScriptService/Packages/ProfileStore.luau) schedules `Save()` asynchronously. | Implement per-profile atomic mutations, bounded request resolution, and explicit migrations. Publishing state or returning `SaveNow == true` does not prove durable persistence. Keep store/key namespaces stable during schema upgrades. |
| Mythling production | [ProductionService/Accrual](../src/ServerScriptService/Services/ProductionService/Accrual.lua) uses Mythling `typeId`, per-Mythling rate/capacity, and `lastCollectionAt`. | Migrate to deterministic Shrine-owned storage and accrual with target Mythling form IDs, levels, and assignment boundaries; Luck/Traits remain inactive. Do not present the target schema as already implemented. |
| Stamina and Shield | [CombatService](../src/ServerScriptService/Services/CombatService/init.lua) currently regenerates on refresh without excluding guarded time and uses partial-cost block spending with delayed depletion cleanup. | Apply [Stamina and guard accounting](#stamina-and-guard-accounting), full-cost eligibility, immediate protection removal, and action exclusion in both directions. |
| Arena spawning | [MythlingSpawnService](../src/ServerScriptService/Services/MythlingSpawnService/init.lua) serially spawns without initial fill, counts non-despawned claimed presentations, and despawns at the timer deadline regardless of occupancy. [MythlingSpawns](../src/ReplicatedStorage/Shared/Configurations/MythlingSpawns.lua) still contains the obsolete `Secret` rarity; its `Legendary` label is valid but refers to deferred content. | Maintain the 12-contest target in quiet and full servers, prefill before capture opens, replace each ended contest within three seconds independently of model cleanup, implement the overtime lifecycle, and align rarity IDs with the GDD's Common/Rare/Epic/Legendary/Mythical order while limiting new launch spawns to Common/Rare/Epic. A configured active cap of 12 alone does not satisfy the population contract. |
| Capture meters | [ClaimService](../src/ServerScriptService/Services/ClaimService/init.lua) currently stores one active meter per player and resets it when switching contests. | Maintain independent per-player/per-contest meters; a previous contest's progress decays when the player moves to another ring. |
| Menus and deferred features | [UI screens](../src/StarterPlayer/StarterPlayerScripts/UI/Screens) include `Stand` and `Hotbar`; the prototype inventory/data layer includes Consumables. | Launch UI follows [UI guidelines](UI_GUIDELINES.md): Shrine terminology, three Inventory categories, no Consumables/Hotbar placeholders, and jobs shown at their station. Preserve saved prototype data while deferring those surfaces. |
| Feature endpoints and transactions | [default.project.json](../default.project.json) exposes the network domains listed above, but does not declare crafting/sale/evolution/build/upgrade, Shrine dismantling, or Material discard endpoints. | Add typed, domain-specific contracts as the approved features ship; target transactional guarantees are requirements, not claims of existing implementations. |
| Authored gameplay assets | [MainServer](../src/ServerScriptService/MainServer.server.lua) requires authored Arena/BaseIslands and model templates that are not supplied by a clean source build. | Use the existing authored development place for gameplay checks. A successful Rojo build verifies source mappings, not asset completeness or playable readiness; see [README](../README.md#getting-started). |

`HUDGui`, `StaminaGui`, `InventoryGui`, `ShopGui`, `StandGui`, `HotbarGui`, `CombatActionGui`,
`ModalBackdropGui`, and `ToastGui` are current application-owned roots under `PlayerGui`.
`StaminaGui` is composed by the HUD; its display layer must not require an active Hotbar. Legacy
`StandGui`/`HotbarGui` names record prototype status rather than authorizing launch features.
`StarterGui` remains intentionally empty and strictly Rojo-owned.
