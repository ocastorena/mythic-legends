# Mythic Legends — Game Design & Implementation Specification

## 1. Product vision

**Mythic Legends** is a mobile-first Roblox creature-collection and base-progression game where players compete in a shared arena to capture mythological companions called Mythlings, assign them to elemental shrines, and grow their base and roster through crafting and evolution.

The game is designed first for landscape mobile play, with keyboard and gamepad support. Its intended audience is family-friendly Roblox Kids/Select players. The visual direction is bright, readable, low-poly fantasy: a circular public arena sits at the center of a sky-island world, surrounded by highly distinct elemental landmarks. The supplied concept art is visual direction, not a requirement to reproduce every depicted creature or structure.

## 2. Launch scope

### Included in the current MVP

- Central-arena Mythling capture through king-of-the-hill contests.
- Non-lethal positional player combat using weapons, shields, Stamina, knockback, and temporary knockback immunity.
- Elemental player bases and upgradeable shrines.
- Online and offline shrine production.
- Material collection, inventory capacity, duplicate Mythling selling, Gold, and Base/Shrine upgrades.
- Mythling levels, evolutions, and one rolled Passive Trait per acquired Mythling.
- Crafting Stations with queued, time-based recipes for Equipment and Consumables.
- Shop purchases and shrine upgrades paid for with Gold and required Materials.

### Not part of the game

- Eggs, summoning, gacha, and Elemental Prism capture devices.

### Post-launch concepts

- Divine Intervention live events.
- Rare-Material Lucky Yield outcomes.
- A separate health/damage-based PvP brawl mode, matchmaking, rankings, and ranked rewards.
- Mythling treats, health, and attack until a separate progression design is approved.

Arena capture is launch PvP, but it is **non-lethal positional PvP**: the goal is to control a capture ring through knockback and defense, not to defeat another player through health damage.

## 3. Canonical terminology

| Term | Meaning |
| --- | --- |
| Mythling | A collectable mythological creature that can be captured and assigned to a shrine. |
| Arena | The central public location where wild Mythlings spawn and players compete to capture them. |
| Capture Ring | The circular king-of-the-hill area surrounding one spawned Mythling. |
| Base | A player-owned area containing their shrines. |
| Shrine | An element-specific production building at a base. It has upgradeable slots and shared storage. |
| Shrine Slot | One assignment space in a shrine. It holds one matching-element Mythling. |
| Yield | A Mythling stat that contributes normal Material output per hour while assigned to a Shrine. |
| Luck | A Mythling stat that contributes to a shrine's combined Lucky Yield chance. |
| Passive Trait | One random, persistent passive assigned when a Mythling is acquired. |
| Evolution | Replacing a Mythling's current form with a new Mythling definition that has its own base statistics. |
| Material | A crafting and upgrade input produced by a Shrine. |
| Gold | The primary currency, earned principally from selling duplicate Mythlings and spent in shops and upgrades. |
| Primary Weapon | Equipment used to apply positional knockback in the Arena. |
| Shield | Equipment used to protect against or reduce positional knockback in the Arena. |
| Equipment | The inventory category containing Primary Weapons and Shields. |
| Consumable | A stackable Hotbar entry that grants a temporary Arena combat buff when consumed. |
| Crafting Station | A base building that runs a level-limited queue of time-based crafting jobs. |
| Combat Loadout | The player's separately equipped Primary Weapon and Shield. |
| Hotbar | The player's six slots for Consumables and future approved Hotbar entries; it does not hold Equipment. |
| Stamina | A player resource consumed by arena weapon actions and by shield impacts; it recovers gradually over time. |

Do not use *forge*, *altar*, or *pet* as alternative names for shrines or Mythlings in player-facing text.

## 4. Elements and rarity

### Elements

The only launch elements are **Fire, Water, Earth, Air, Light, and Dark**. Every Mythling and Shrine has exactly one element. A Mythling can be assigned only to a shrine with the same element.

Mythling Fusion is a post-launch system. It may create dual-element Mythlings, but it does not change the one-element rule for the first release.

### Rarities

Rarities are ordered from lowest to highest:

1. Common
2. Rare
3. Epic
4. Mythical
5. Divine

Rarity affects capture and spawn odds, configured base Yield and Luck ranges, visual presentation, and the weighted Passive Trait pool. It does not imply a different element.

The first release has no cosmetic Mythling variants. Every gameplay-relevant or visual transformation is represented by a distinct evolved Mythling form.

### Mythling concept principle

Every Mythling evolution line is a hybrid of two recognizable mythological creatures from distinct traditions. Both source creatures must be visually legible in the first form and remain part of the line through both evolutions. Mythling concepts must not use figures from living religions.

### Visual language

- Fire: orange/red, lava, embers.
- Water: blue, ice, crystal, flowing water.
- Earth: green, wood, stone, foliage.
- Air: pale cyan, clouds, wind, floating rock.
- Light: white/gold, beams, wings, radiant stone.
- Dark: black/purple, shadow, violet crystals.

The central arena must remain visually readable on mobile. Launch tuning should keep only a small number of simultaneous contested Mythlings active, even if the environment contains many decorative Mythlings or landmarks.

## 5. Mobile controls and accessibility

### Player start and flow

Players spawn at their own Base. From there, they may immediately enter the Arena to capture Mythlings or manage their Base, Shrines, and Crafting Stations through nearby Proximity Prompts. The first-release player flow does not require a fixed tutorial sequence.

### Controls

- Launch movement uses only Roblox's standard walking and jumping. There is no sprint, dash, crouch, climbing ability, or other movement action.
- The game uses Roblox's default third-person follow camera. There is no camera lock or aim mode at launch.
- **Mobile:** the left thumb controls movement; the right side controls camera drag, a dedicated Attack button, and a dedicated Shield button.
- **Keyboard/mouse:** left click uses the equipped Primary Weapon; holding right click holds the equipped Shield active. Number keys `1` through `6` select the corresponding Hotbar slot.
- **Gamepad (later):** right-trigger attack, left-trigger Shield hold, and D-pad Hotbar cycling are planned after the current MVP implementation.
- The Combat Loadout has one Primary Weapon slot and one Shield slot. Players choose these in the Inventory menu; Equipment never occupies a Hotbar slot.
- Both pieces of Equipment use character-mounted Models rather than Roblox `Tool` instances. In the Arena, the Primary Weapon is held in the right hand and the Shield in the left hand. Outside the Arena, both remain visibly sheathed on the character and equipped in saved state, but their combat actions are unavailable.
- Players may leave every Hotbar slot empty or equip up to six Consumables or future approved Hotbar entries. Hotbar selection never changes the equipped Primary Weapon or Shield.

- Every new player receives a plain wooden sword and wooden shield in their Combat Loadout. The Hotbar has six Consumable slots.
- The Hotbar is displayed along the bottom of the screen, consistent with familiar Roblox inventory placement.
- The HUD provides Inventory and Shop buttons. Players access Base, Shrine, and Crafting Station interactions through nearby Proximity Prompts.
- Gold, the six-slot Hotbar, Inventory button, and Shop button are always visible. Arena UI also exposes the dedicated Attack and Shield controls; Stamina is visible only while the player is in the Arena.
- Capture progress is displayed as a world-space meter above the contested Mythling. Arena actions must be reachable while moving and must not require precise taps on a Mythling.
- All important capture state is communicated through legible ring, progress, and ownership indicators; color is never the only signal.
- Live events must respect Reduce Motion and sound settings. Reduce Motion replaces screen shake and flashing with static, non-flashing notifications.

## 6. Arena capture

### Capture flow

1. Wild Mythlings spawn in the central Arena as stationary idle targets. They play configured idle animation but do not roam or move their Capture Ring at launch.
2. Each spawned Mythling creates one visible Capture Ring around itself. Capture Rings must never overlap.
3. A player whose Mythling inventory has available space may build their own capture meter while inside the Capture Ring. A player with full Mythling inventory cannot begin or gain capture progress for that Mythling.
4. A player's meter increases at the spawned Mythling's configured `captureProgressPerSecond` while that player is inside the ring.
5. A player's meter decays at the spawned Mythling's configured `captureDecayPerSecond` while that player is outside the ring.
6. Arena weapons consume Stamina and can knock competing players out of a Capture Ring. An active Shield absorbs a hit by consuming Stamina, sliding its user back slightly, and granting temporary knockback immunity.
7. The first player whose meter reaches 100% captures the Mythling. The server grants that Mythling to the winner, removes the contested spawn, and clears all other progress for that contest.
8. An unclaimed Mythling despawns after its configured lifetime. Its despawn clears every player's capture progress for that contest.
9. After a Mythling is captured or despawns, the Arena spawn system creates a replacement as needed to maintain its configured active-spawn cap.

### Arena rules

- Each Mythling is an independent contest; capture progress is never shared between players or between Mythlings.
- Capture progress and decay are defined per Mythling in metadata, allowing each Mythling to have its own capture difficulty. Rarity may inform that tuning but does not prescribe a universal formula.
- The Arena chooses replacement Mythlings from a rarity-weighted metadata pool; rarity is the primary spawn-selection weight.
- A player who disconnects during a contest immediately loses all of their progress for every active Capture Ring.
- If a player reaches Mythling capacity while they have active capture progress, the server immediately clears that progress and displays the inventory-capacity warning.
- The Arena spawn system must select a different valid position or delay a spawn rather than create an overlapping Capture Ring.
- Mythling inventory capacity is checked by the server before capture progress begins and again before capture is awarded.
- The server is authoritative for Capture Ring membership, capture progress, winner selection, inventory changes, and rewards. MVP sword contact uses the client-reported architecture defined below.
- Arena combat does not deal damage or cause player death. Knockback, Shield behavior, and temporary knockback immunity create the positional disruption used in Capture Ring contests.
- A combat client may report a sword target and present immediate feedback, but it may never change capture progress, award a Mythling, determine a winner, or grant any inventory or economy result.
- Capture rates, ring radius, spawn frequency, active-spawn cap, despawn time, knockback strength, Shield behavior, and Equipment cooldowns are shared balance configuration—not independently hard-coded in client controllers.

### MVP player combat system

Launch combat is Arena-only and non-lethal. A player attacks with their equipped Primary Weapon and may independently hold their equipped Shield active; neither occupies a Hotbar slot. Launch weapons and Shields are non-elemental material tiers, including wood, copper, steel, and future configured material tiers. Elemental weapons and effects are post-launch content.

Entering the Arena moves the player's equipped Primary Weapon and Shield from their authored sheath attachments to their R15 hand attachments and enables Arena actions. Leaving the Arena returns both Models to their authored sheath attachments and disables attack and Shield holding without changing the saved Combat Loadout.

The launch sword uses a deliberately client-reported melee architecture. This is an accepted MVP tradeoff: responsive, visually accurate combat in live servers is more important than making sword contact fully exploit-resistant. The server validates the report before relaying the reaction and remains authoritative wherever combat affects capture state, ownership, rewards, inventory, or the economy.

#### Attacking client

1. One shared client attack function is the only source of a sword swing. Left click and the dedicated mobile Attack button may call that function, but they must not create duplicate activations for one input.
2. The client sends one `MeleeSwing` activation with a monotonically increasing sequence, immediately plays the visible swing animation, and opens its contact window from animation markers, with a configured timing fallback when an animation lacks those markers. A player with insufficient Stamina cannot begin a weapon action.
3. During that window, the client sweeps the visible sword blade through interpolated positions between rendered frames. Contact is based on the blade geometry, not a large character-centered cone.
4. The client excludes its own character and selects at most one eligible target: the target with the closest valid blade contact. Optional line-of-sight filtering may reject contact through solid geometry.
5. On first valid contact, the attacker immediately presents the configured hit effect, sound, trail, and brief animation hit-stop. It then sends exactly one `HitReport` containing the activation's swing sequence and the selected target's user ID.
6. A swing that finds no blade contact sends no hit report, but its activation still consumes the weapon's configured Stamina cost. Walking near another player without activating the sword must never produce a hit.

#### Server validation and relay

The server does not independently scan an arc, rewind player positions, replace the reported target, or manufacture an alternative hit. It first validates each `MeleeSwing`, deducts its configured Stamina cost whether the swing later hits or misses, starts the weapon cooldown, and records a short-lived authorization for that sequence. It then either accepts a matching reported attacker-target pair or rejects it.

Before accepting a `HitReport`, the server verifies:

- The attacker owns the reported supported melee weapon and has it equipped as their Primary Weapon in the Combat Loadout.
- The attacker and reported target are distinct playable characters.
- Both characters satisfy the Arena-only rule for that weapon.
- The swing sequence matches the attacker's latest unconsumed server-authorized activation.
- The authorization has not expired and the target is not temporarily knockback-immune.
- The reported characters are within the weapon's configured reach plus a bounded server-tolerance distance.

On acceptance, the server consumes the authorization without deducting Stamina a second time, assigns an idempotent hit ID, resolves the configured launch values, records the target's temporary knockback immunity, relays the launch to the target client, and broadcasts the confirmed impact presentation. The server never applies health damage.

#### Target client and presentation

- The target client applies the relayed launch with a short eased force curve rather than a delayed velocity spike. Hit IDs prevent the same launch from being applied twice.
- Temporary knockback immunity starts after an accepted hit and prevents further knockback until its configured duration ends.
- The attacker's locally rendered impact suppresses its duplicate server broadcast. Other clients render the server-confirmed impact.
- Visual and audio presentation is cosmetic. Failure to render an effect must not change hit validation, capture progress, or temporary knockback immunity.

#### Shield actions

- A Shield is separately equipped in the Shield slot of the Combat Loadout and may be held active without changing Hotbar selection.
- Pressing and holding the Shield action activates the Shield; releasing the action deactivates it.
- Shield protection begins at the authored `GuardRaised` marker in the raise animation and ends at `GuardLowered` in the lower animation. The protective bubble follows those same marker transitions.
- While a Shield is active, its player cannot move.
- With sufficient Stamina, the active bubble absorbs an incoming weapon hit from any direction. It drains Stamina, slides the Shield user away from the hit direction, grants temporary knockback immunity, and displays a spark effect on the struck bubble.
- If a bubble has less than the full impact cost remaining, it still absorbs that final hit, spends the remaining Stamina, displays its bubble impact, and then lowers automatically.

#### Security boundary

Because the attacking client chooses the target, an exploit can fabricate plausible sword reports within the server's distance, cooldown, Combat Loadout, Stamina, immunity, and Arena checks. This risk is accepted for the MVP and must be revisited if competitive stakes increase. Lightweight rate monitoring and server telemetry may be added without restoring an independent server hit scan.

The client-reported exception ends at the positional combat reaction. Capture Ring membership, capture meters, contest resolution, Mythling awards, Stamina consumption, shield eligibility, persistent progression, and all rewards remain server-authoritative.

## 7. Bases, shrines, and production

### Shrine rules

- A Shrine has one `elementId` and one assigned `materialId`.
- A Shrine accepts only Mythlings with the same `elementId`.
- A Shrine has an upgradeable level, a maximum number of slots, and one shared storage capacity.
- Each occupied Shrine Slot adds the assigned Mythling's Yield and Luck to that Shrine.
- A Shrine upgrade may increase its slot count, shared storage capacity, and configured production multiplier.
- Players choose which element Shrine(s) to build. There is no one-Shrine-per-element rule; duplicate-element Shrines are allowed when the player's configured Base/build capacity permits them.
- A Shrine's Proximity Prompt opens its Shrine menu. Players use that menu to assign eligible Mythlings to open slots or remove assigned Mythlings.

Every new player starts with a Base, no Shrines, no Mythlings, no Materials, and a configured amount of Gold. The Base's Proximity Prompt opens its build/upgrade menu, where players buy Shrines and Crafting Stations. Base upgrades grant additional configured build slots for Shrines or Crafting Stations. The player must be able to buy or unlock their first Shrine using the starting state.

The Shrine owns the produced Material. Mythlings provide the speed and Lucky Yield chance; they do not independently decide which Material the Shrine produces.

### Production calculation

```text
Total Yield Per Hour = sum(assigned Mythling Effective Yield) × Shrine Production Multiplier
Total Luck Chance = min(sum(assigned Mythling Effective Luck), Shrine Luck Cap)
```

Production is calculated in fixed, server-authoritative batches. While a shrine has available storage capacity, each batch adds its normal output. The shrine makes one Lucky Yield roll per batch using `Total Luck Chance`. The Shrine menu is also the player-facing place to inspect its stored output and use an explicit Collect action.

- At launch, a successful Lucky Yield roll doubles that batch's normal Material output.
- Production accrues while the player is offline.
- On join or collection, the server calculates elapsed batches from the saved accrual time, applies production and Lucky Yield rolls, clamps the result to shared Shrine capacity, and updates the saved state.
- Output never exceeds capacity. A full shrine stops accruing until the player collects output or increases capacity.

### Planned rare-Material extension

The launch implementation must preserve a configurable future outcome for a successful Lucky Yield roll. A later update may let the roll award a rare version of the Shrine's elemental Material instead of double normal output. For example, a Fire Shrine could produce a rare Fire-aligned Material such as `Prismatic Ember`.

This is a **rare Material variant**, not a new element. It must use the Shrine's shared storage according to a configured storage-unit cost and must not bypass the capacity limit.

### Mythling progression and Passive Traits

Each Mythling has a current form, a level, XP, an individually saved Luck value, and exactly one Passive Trait rolled when it is acquired. The current form's immutable base statistics come from Mythling metadata; only the Mythling's lightweight mutable state is saved to the player document.

- **Yield** starts from the current form's configured base Yield and increases through level-based configuration.
- **XP** is earned while a Mythling is assigned to and working in a Shrine. Each completed server-authoritative production batch awards a separately configured XP amount; XP is not calculated from the Materials produced.
- The level cap is 100. Each level applies the same small, configurable Yield percentage increase to that Mythling's current form base Yield.
- **Evolution** replaces the Mythling's current form with its one configured evolution-target Mythling definition. The evolved form has its own configured base Yield and other base statistics.
- Evolution requires reaching that Mythling form's configured target level. It is free and immediate, never changes the Mythling's element, and preserves its Passive Trait.
- A player initiates an eligible evolution from that Mythling's Inventory-menu entry. The server validates ownership, target level, and the form's single configured evolution target before changing `mythlingId`.
- **Luck** is an individually saved Mythling stat. Trait and level effects modify it into Effective Luck before the Shrine combines it with the other assigned Mythlings' Luck.
- A Mythling's Passive Trait applies only while the Mythling is assigned to an eligible Shrine, unless the Trait definition explicitly says otherwise.

Traits are production-focused only. Trait effects must be server-authoritative and data-driven. Launch examples:

| Trait | Effect |
| --- | --- |
| Insomniac | This Mythling contributes 20% more Yield while its owner is offline. |
| Lucky | Adds 3 percentage points to this Mythling's base Luck before combined Shrine Luck is calculated. |

Traits are selected from universal, element-agnostic weighted pools. The selected pool and its weights are determined by Mythling rarity. Traits must define their trigger, eligibility, and numerical effect. Do not let client-side code select, roll, or apply a trait.

## 8. Crafting, shop, and economy

### Crafting

Crafting Stations are not owned at the start of the game; a player must build one through the Base build/upgrade menu before starting recipes. A Crafting Station's Proximity Prompt opens its crafting menu. Crafting Stations use Shrine Materials to create approved Equipment and Consumables. All recipes are time-based Crafting Jobs. A Crafting Station's level determines its maximum job-queue capacity. Every recipe must define:

- Result definition ID and category.
- Required Material quantities and required Gold, if any.
- Unlock requirement.
- Stack or ownership behavior.
- Craft duration, eligible Crafting Station, and queue behavior.
- Arena effect, cooldown, and numerical tuning for Equipment or Consumables.

Players may cancel a Crafting Job at any time for a full refund of every Material and Gold amount spent to start that job. Crafting is server-authoritative: the server verifies the recipe, affordability, unlock state, inventory capacity, queue capacity, cancellation/refund behavior, and result before deducting costs or granting Equipment or a Consumable.

Crafting Jobs continue and complete while their owner is offline. The server records the job timing and resolves completion on a server tick, player join, or Crafting Station interaction; the output space reserved when the job began remains reserved until the job is completed or cancelled.

### Consumables

First-release Consumables are temporary combat buffs only. A player must equip a Consumable to a Hotbar slot and activate it in the Arena to consume it. Consumables may provide configured combat-stat boosts and their timed effects stack. Each Consumable definition must provide a duration and configurable stack cap. The server validates the selected inventory entry, Arena eligibility, and stack cap; it consumes the Consumable and owns the active-buff and expiry state. Production and crafting consumables are not part of the first release.

### Gold and duplication

- Selling duplicate Mythlings is the main early-game source of Gold.
- Selling is initiated from a selected Inventory-menu entry, not from the Shop. The Shop is for purchases and upgrades.
- Every sellable inventory definition declares its sell eligibility and Gold value in metadata. Entries not marked sellable have no Sell action.
- A player may choose the quantity to sell from a stackable entry. An entry equipped in the Combat Loadout or Hotbar, assigned to a Shrine, or queued in crafting must be unequipped, unassigned, or cancelled before it can be sold.
- Mythlings may be sold even when they are the player's last owned copy of that Mythling; there is no automatic final-copy protection.
- The server validates ownership, sell eligibility, stack quantity, and dependency state, then removes the entry and grants Gold as one atomic transaction.
- Gold is spent in the Shop and as part of Shrine upgrades.
- Shrine upgrades also require the relevant configured Materials.
- The Shop sells upgrades that increase the maximum slot count of individual inventory tabs.
- A player must be able to capture a first Mythling without Gold.

### Inventory capacity and overflow

The first-release inventory tabs are Materials, Consumables, Mythlings, Equipment, and Crafting Jobs. Each tab has a configured maximum number of inventory slots. Materials and Consumables combine into stacks by type; each metadata definition supplies that stack's maximum quantity. Gold is a separate, uncapped balance and does not occupy an inventory slot. A player cannot receive an entry when its destination tab has no available slot or compatible stack space.

- A player at Mythling capacity cannot begin or gain Capture Ring progress. The server sends an `InventoryFull` warning that identifies Mythlings as the blocked inventory category.
- A proximity pickup is not collected when the recipient's relevant inventory is full. It remains available according to that pickup's normal despawn and claim rules.
- Crafting checks and reserves output inventory space when a Crafting Job begins. A player cannot start a job if its output cannot be received.
- Shrine collection is rejected when the destination Material inventory is full; the Shrine retains its stored output.
- Every blocked acquisition produces a clear, server-authoritative warning that identifies the full inventory category and, when possible, the action needed to create space.

## 9. Live events

### Divine Intervention

**Divine Intervention** is the working name for post-launch, mythology-themed live events in which gods or mythological forces visibly affect a server. Examples may include *Thor's Tempest*, *Poseidon's Deluge*, or *Hades' Eclipse*.

This system is **not part of the first release and is not ready for implementation**. Its event types, scheduling, permissions, monetization, rewards, server scope, Mythling-spawn controls, pickup behavior, presentation, and accessibility rules must be designed and approved in a later GDD revision. First-release systems must not depend on Divine Intervention or reserve implementation work for it beyond using data-driven content patterns.

## 10. Content and technical contracts

### Runtime architecture

The first release uses the approved Rojo Bootstrap architecture and ProfileStore-backed player persistence. `default.project.json` defines the canonical Roblox Explorer hierarchy; Studio-authored descendants are preserved only at explicitly mixed-ownership containers.

- **MainServer** is the only server bootstrap. It initializes modules under `ServerScriptService.Services` in deterministic lifecycle order and owns the player join/leave wiring.
- **Server services** own validation, authoritative simulation, mutations, persistence requests, and grants. No domain service independently loads a profile or writes a Roblox DataStore.
- **MainClient** is the only client bootstrap. It initializes state/networking before feature controllers under `StarterPlayerScripts.Controllers`.
- **Client controllers** own input, UI, local animation, sound, VFX, and rendering of server-confirmed state. They cannot mutate persistent player data, Arena ownership, capture state, or economy state.
- **Shared configuration** is version-controlled Luau content under `ReplicatedStorage.Shared.Configurations`. It contains static definitions and balance values only; it must never be written at runtime.
- **DataService** owns one versioned ProfileStore session per Roblox user ID using `MythicLegends_PlayerData_v1`. It reconciles the schema, associates the user ID, handles session termination, and ends the session when the player leaves. Studio uses an isolated mock store by default.
- **Combat is the stated exception.** Its client-reported, server-validated relay and immediate local presentation remain exactly as defined in [MVP player combat system](#mvp-player-combat-system). This architecture must not be changed by the general UI synchronization rule below.

### Client/server state synchronization

For every system other than the documented combat exception, clients send an intent request and wait for a server-confirmed result before changing authoritative UI state.

1. The client may immediately show input feedback and a pending/loading state.
2. The server validates the request against the cached player document, metadata, runtime eligibility, capacity, affordability, and permissions.
3. The server performs the mutation as a duplicate-safe DataService transaction while the ProfileStore session is active, then returns or replicates the authoritative result.
4. The client updates inventory, Gold, Shrine output, Crafting Jobs, capture state, Equipment, Stamina, and buffs only from that confirmed result.
5. A rejection leaves the authoritative state unchanged and supplies a player-facing reason when appropriate, such as `InventoryFull`, insufficient Gold/Materials, invalid selection, unavailable capacity, or not-in-Arena.

Capture meters, Stamina, active Shield state, temporary knockback immunity, active combat buffs, and active Arena contests are server-owned runtime state. They are not persistent; they clear on disconnect or server shutdown unless a later approved design explicitly changes that rule.

Private player UI state uses a client-ready `Network.State.Request` snapshot followed by revisioned incremental `Network.State.Update` packets. Only an explicit client-safe projection may be replicated; the complete ProfileStore document, permissions, internal flags, and server-only state must never be sent to the client. `LocalData` owns the client cache and change signal. A missed or out-of-order revision triggers a bounded snapshot resynchronization instead of polling.

Rojo declares the production network contract and groups single-purpose endpoints by domain (`State`, `Inventory`, `Production`, `Base`, `Combat`, and `World`). Every client-triggered endpoint is treated as untrusted, validates its complete payload and current server state, and has a server-side rate limit. Use `RemoteFunction` only when the caller requires an immediate result; never synchronously invoke a client from the server. Reliable gameplay state stays on `RemoteEvent`, while an `UnreliableRemoteEvent` is reserved for disposable cosmetic traffic where loss and reordering are acceptable.

### UI composition and ownership

- Production application UI is Rojo-owned and declaratively composed with the Wally-pinned Fusion package. `UIController` owns one cleanup scope and mounts one `StarterPlayerScripts.UI.App` root; requiring a UI module must not start work.
- Feature `ScreenGui` roots are created by `UI/Screens` directly under the local player's `PlayerGui`. Roots explicitly define respawn, inset, display-order, and Z-index behavior. Stable semantic descendants use `PascalCase` names.
- Interactive application panels use Roblox's `CoreUISafeInsets`, device-safe clipping, and no legacy fullscreen-extension transform. The persistent HUD may use a full-screen canvas only for its deliberately top-bar-aligned chrome.
- Reusable presentation belongs in `UI/Components`; feature-level composition belongs in `UI/Screens`; cross-screen backdrops and transient notifications belong in `UI/Overlays`; genuinely shared visual tokens and responsive metrics belong in `UI/ThemeUtil`. `ReplicatedStorage.Assets.UI` holds client-visible art assets, not executable UI composition.
- Studio is used to preview, tune, and test the runtime result. Accepted application UI must be represented in Rojo source so a clean build reproduces it; Studio-only production GUI is architectural drift.
- Controllers own feature input and server-authoritative domain interactions rather than constructing visual hierarchies. They react to `LocalData` or server-confirmed domain events and must not poll, duplicate remote subscriptions, or treat displayed values as authoritative.
- `UI/State` adapters expose focused Fusion values from `LocalData.OnStateChanged` without duplicating the private client cache. The UI never reads ProfileStore state or offers a generic server mutation interface.
- Keep the hierarchy simple: one application root, one shared scope, focused screens, and components only where reuse or isolation is valuable. Avoid both a monolithic router and controller-per-widget fragmentation.
- Bootstrapped server services and client controllers use `Init(context)`, `Start()`, and `Stop()`. Runtime logs are failure-only and must never contain complete profiles or sensitive remote payloads.
- UI must support mobile safe areas, reachable touch targets, flexible layouts, legible text, non-color-only state communication, and Reduce Motion behavior.

### Content configuration

Content and balance data must be separate from game logic and versioned. At minimum, configuration defines:

- Mythling: `id`, display name, element, rarity, visual assets, form-specific base Yield, level-scaling data, one optional evolution target, lore, and sell eligibility/value.
- Trait: `id`, acquisition weight, trigger, eligibility, numerical effect, and evolution-persistence behavior.
- Shrine: element, output Material, base storage, slot count by level, production multiplier by level, Luck cap, upgrade costs.
- Base: build-slot grants by upgrade, eligible structures, and upgrade costs.
- Crafting Station: queue capacity by level, eligible recipe groups, and upgrade/build costs.
- Material: id, element, display information, crafting uses, sell eligibility/value, buy value, stack limit, and optional rare variant.
- Arena spawn: eligible stationary Mythlings, rarity-weighted selection pool, ring radius, active cap, lifetime, and per-Mythling capture-progress and decay rates.
- Equipment: id, category, visuals, knockback/protection behavior, cooldown, Stamina costs, and sell eligibility/value.
- Consumable: id, visuals, temporary combat-buff effect, duration, stack cap, stack limit, and sell eligibility/value.
- Recipe: input Materials and Gold, result definition, duration, eligible Crafting Station, unlocks, and queue behavior.
- Inventory upgrade: tab affected, slot increase, price, and eligibility.

### Player save data

The persistent player document stores lightweight, mutable player state. It references static metadata by ID rather than duplicating names, descriptions, models, recipes, visual assets, or immutable base statistics.

At minimum, the target document shape is:

```text
version
profile                 -- user/profile timestamps and approved flags only
currency.gold           -- uncapped mutable Gold balance
materials[materialId]   -- quantity only; stack rules come from Material metadata
consumables[consumableIdOrInstanceId] -- consumableId, quantity, or approved unique mutable state
equipment[instanceId]   -- equipmentId and approved unique mutable state
combatLoadout           -- optional primaryWeaponInstanceId and shieldInstanceId
hotbar[1..6]            -- optional references to owned Consumables or future approved Hotbar entries
mythlings[instanceId]   -- owned Mythling schema below
base                    -- Base upgrade state and built-structure records
craftingJobs[jobId]     -- active/queued Crafting Job schema below
unlocks                 -- approved progression/unlock flags
```

`base` saves only player-specific state. Each built Shrine record contains a unique `id`, its static `shrineId`, current level, stored output quantity, last production-accrual time, and assigned Mythling instance IDs by slot. Each built Crafting Station record contains a unique `id`, its static `craftingStationId`, and current level. Its element, Material output, capacities, slot grants, and costs are resolved from metadata.

Each active or queued Crafting Job contains a unique `id`, `recipeId`, `craftingStationId`, `resultDefinitionId`, status, start time, completion time, and the reserved output destination. Costs are deducted only once at job start; result and timing IDs/timestamps are stored so a later metadata balance change cannot alter a job already in progress.

An owned Mythling entry must contain at least:

```text
id                 -- unique owned-Mythling instance ID
mythlingId         -- current Mythling-form metadata ID
level
xp
luck               -- individually rolled, mutable Luck value
traitId            -- Passive Trait metadata ID
acquiredAt
assignedShrineId   -- optional
assignedSlotId     -- optional
```

Evolution updates `mythlingId` to the evolved form's metadata ID. The saved entry stays small while the game resolves the current form's base Yield and other immutable data from metadata.

### Data ownership matrix

| Game data | Metadata (static, version-controlled) | DataService player document (mutable) | Runtime-only server state |
| --- | --- | --- | --- |
| Mythling form | `mythlingId`, name, element, rarity, visuals, base Yield/Luck ranges, level scaling, Trait weights, fixed evolution target, Arena eligibility and capture tuning | Owned instance ID, current `mythlingId`, level, XP, rolled Luck, `traitId`, acquisition/assignment data | Spawned contest, per-player capture meters, despawn timing |
| Passive Trait | `traitId`, eligibility, rarity-pool weight, trigger, numerical effect | Owned Mythling's `traitId` only | Applied production modifier when eligible |
| Material | `materialId`, element, display data, stack limit, sell value, crafting use | Quantity by `materialId` | World pickup/claim state, if introduced in an approved system |
| Equipment and Consumable | Definition ID, category, visuals, effect, stack limit, sell eligibility/value, recipe, cooldown, buff duration/stack cap | Stack or owned-instance quantity; Combat Loadout and Hotbar references; approved unique mutable state | Equipped selection, cooldowns, active temporary buffs, Shield state |
| Gold | None beyond balance presentation/configuration | Uncapped `currency.gold` balance | None |
| Base | Upgrade definitions, build-slot grants, costs, eligible structures | Base upgrade state and constructed-structure records | Spawned Base model references |
| Shrine | `shrineId`, element, output Material, capacities, slots, multipliers, upgrade costs | Instance ID, level, stored output, last accrual time, assigned Mythling IDs | Current production resolution during accrual/collection |
| Crafting Station | `craftingStationId`, queue capacity by level, costs, eligible recipes | Instance ID and level | Current menu/session references |
| Recipe and Crafting Job | `recipeId`, inputs, Gold cost, result, duration, unlock requirement | Job ID, recipe/station IDs, status, start/completion time, reserved output | Completion scheduling while a server is live |
| Arena spawn rules | Rarity-weighted pool, active cap, positions, lifetime, capture rates | None | Active spawned Mythlings and Capture Rings |
| Player combat | Equipment/Consumable tuning and animation/VFX references | Equipment ownership, Combat Loadout, and Hotbar assignment | Stamina, hit sequence/recent hit IDs, immunity, cooldowns, active Shield, knockback and combat buffs |

Other inventory entries follow the same rule: store an instance ID, a metadata ID, and only mutable state such as quantity, durability, acquisition data, equipped state, or unique rolled values.

The player document must also contain:
- Base and Shrine state, including levels, slots, stored Materials, and last production-accrual time.
- Material and Gold balances.
- Crafted Equipment and Consumables.
- Unlock and tutorial flags.
- A schema version and forward-only migrations.

The server validates every client request that changes inventory, currency, Equipment, production, or capture. Persistence must use bounded document sizes, retry handling, periodic saves, safe failure behavior, and schema migrations; it cannot assume DataStore limits or network calls never fail.

## 11. Acceptance criteria

1. A player standing in a stationary Mythling's Capture Ring gains only their own Mythling-configured capture progress; leaving the ring causes that progress to decay, while disconnecting or reaching Mythling capacity resets it immediately.
2. The server awards exactly one Mythling to the first verified player to reach 100% capture progress, clears progress when a contest expires, and replenishes captured or expired Mythlings to the configured active-spawn cap.
3. A Mythling cannot be assigned to a Shrine with a different element.
4. Multiple matching Mythlings in one Shrine increase its combined Effective Yield and combined Effective Luck.
5. Production continues while the player is offline, cannot exceed Shrine capacity, and produces the same result regardless of client device or frame rate.
6. A Lucky Yield roll doubles normal output at launch and is calculated by the server.
7. Crafting, selling, and upgrades cannot be granted by a client without a valid server-side affordability and eligibility check.
8. No launch UI or game system offers eggs, summons, gacha, or Elemental Prisms.
9. An acquired Mythling has one server-rolled Passive Trait, and that Trait cannot be supplied or changed by a client request.
10. A Mythling evolution resolves its new base statistics through its evolved Mythling metadata ID rather than duplicating those base statistics into the player save.
11. A new player has a Base, no Shrine/Mythling/Materials, a configured Gold grant, a wooden sword, and a wooden shield.
12. Capture Rings do not overlap, and the Arena spawn system does not create an overlapping contest.
13. A Mythling earns separately configured XP only from verified Shrine production, caps at level 100, and retains its Passive Trait and element after an Inventory-menu evolution validated by the server.
14. A player at Mythling capacity cannot gain Capture Ring progress, and any blocked pickup, collection, or crafting start produces an inventory-capacity warning without granting the entry.
15. Every activated Arena weapon attack consumes its configured Stamina cost even when it misses, while shield impacts consume up to their configured Stamina cost and allow one final partial-cost block before depletion; Arena combat uses knockback, Shield behavior, and temporary knockback immunity, but never player health or death. Elemental weapon effects are post-launch.
16. All Passive Traits affect production only, and cancelling a Crafting Job refunds all of its spent Materials and Gold.
17. A sword swing can report at most one target selected deterministically by closest visible blade contact, then attacker-to-target distance, then player user ID; proximity without attack activation cannot produce a hit, and the server cannot substitute an independently selected target.
18. An accepted sword report produces immediate attacker feedback and one idempotent target-client launch while capture progress, contest resolution, and rewards remain server-authoritative.
19. An Inventory sale validates the selected entry's ownership, metadata eligibility, quantity, and dependency state before atomically removing it and granting Gold; Mythling sales have no automatic final-copy protection.
20. A Consumable can be consumed only from a selected Hotbar slot in the Arena; the server applies and expires its temporary stacked effect.
21. A player can attack with their equipped Primary Weapon and hold their equipped Shield active without changing Hotbar selection; Equipment never occupies Hotbar slots.
22. Combat Loadout Models move to their authored R15 hand attachments and become usable only in the Arena; leaving the Arena returns them to their authored sheath attachments and disables them without unequipping them.

## 12. Open decisions for later design passes

- Exact starting-Gold amount, first-Shrine cost/unlock, Base-upgrade costs, and Crafting Station build costs/unlocks.
- Numerical balance for spawn rates, capture/decay rates, Yield, Luck, capacities, upgrades, prices, and recipes.
- Equipment catalogue, effects, cooldowns, exact Consumable activation bindings, Stamina costs, regeneration rate, and maximum Stamina.
- Exact shop inventory and non-duplicate Gold sources, if needed after playtesting.
- XP requirements, exact per-level Yield percentage, evolution target levels, and trait acquisition weights.
- Mythling treats, combat health/attack, and a separate brawl/PvP mode.
- Rare-Material recipes, scarcity, storage-unit costs, and enabled Lucky Yield outcome when that extension ships.
- Inventory capacity values by category and the permitted player actions for creating space.
