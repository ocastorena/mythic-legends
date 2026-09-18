# Mythic Legends — UI Guidelines

This document owns player-facing menu behavior, visual conventions, accessibility, empty states, and
feedback. Follow the [GDD](GDD.md) for gameplay and launch scope and [Technical
Design](TECHNICAL_DESIGN.md#ui-composition-and-ownership) for UI architecture and code ownership.
Keep presentation consistent across Inventory, Shop, Shrine, Crafting Station, and future panels
unless a feature-specific design explicitly overrides these conventions.

## Launch scope

- Launch Inventory tabs are Materials, Mythlings, and Equipment. The Consumables tab and six-slot
  Hotbar are introduced with the future Consumables update; do not show empty or disabled
  placeholders for these deferred systems in the launch UI.
- Launch Equipment types are swords and separate Shields. Show no additional-archetype catalogue
  entries, filters, controls, or placeholders; two-handed Equipment arrives in future updates.
- Luck, Lucky Yield, and Passive Traits are deferred. Show no launch Luck or Trait statistics,
  acquisition rolls, bonus indicators, filters, controls, or locked placeholders. Mythling production
  follows its named form and XP level, with the same rate online and offline.
- Mythling and Equipment stage numbers are internal design/configuration shorthand. Do not expose
  them as badges, filters, or numbered suffixes in item/form names. Show actual names, rarity,
  elements, and relevant statistics. Evolution and future Equipment-upgrade previews identify the
  named result and its changes. Mythling XP levels and Shrine levels remain visible.
- Launch Equipment includes the wooden starter pair and first crafted element variants. Show no
  Equipment Upgrade action, later-upgrade recipes, or locked upgrade placeholders; Equipment
  upgrades arrive in future updates.
- Equipment rarity is included in the launch UI. Show the item's confirmed rarity as a labeled value
  alongside its name, type, and element, keeping rarity distinct from element color.
  Each named item has one fixed rarity; resolve it from that item's metadata in recipe previews,
  Shop offers, active jobs, completion feedback, and Inventory. Identify the wooden starter pair as
  plain starter gear with Common rarity; all first-crafted elemental swords and Shields have Rare rarity. Use the
  same rarity names as Mythlings. Epic, Legendary, and Mythical Equipment have no launch catalogue entries
  or placeholders. Show no random
  rarity outcome or separate rarity choice when crafting, and do not derive rarity from stage.
  Equipment rarity describes quality; statistics and prices show the configured item values without
  an additional rarity bonus.
- Mythling Inventory and evolution details show the current form's name, appearance, element,
  rarity, and XP level/progress. Evolution previews show the named next form, required XP level,
  rarity, and statistics before/after. Offer the configured next form through the existing Evolve
  action when eligible; a form with no next target has no Evolve action. All three forms of each
  launch chain belong to the MVP, independently of the deferred Equipment upgrades.
  Evolution remains a player action after offline progress. If the next evolution is also eligible
  after a confirmed form change, show that next action without a new training timer.
- Read Mythling rarity from the confirmed form's metadata, independently of its position in the
  evolution chain. Evolution displays the target form and its own rarity while retaining displayed
  earned level/XP. Explain that launch Rare/Epic forms can be evolved or captured; copies of the
  same form at the same XP level have the same Yield, regardless of acquisition route.
  Legendary and Mythical Mythling content has no launch catalogue entries or locked placeholders.
- Capture feedback shows the form actually caught alongside **Level 1** and **0 XP**, including
  Rare and Epic captures. An evolved form does not imply an earned XP level. Do not reset displayed
  progression on evolution/reconnect. Mythlings without a next evolution retain their level/XP display.
- Show the Mythling's current Yield and XP progress. Level-up and evolution previews show the
  resulting Yield from its form and level, following the
  [GDD progression rules](GDD.md#mythling-progression). Use the same production rate for online
  and offline estimates.
- Mythling sale details identify the selected individual and show its current form's fixed Gold
  value. XP level and whether the form was evolved or captured do not change this payout.
  Evolution previews show the target form's sell value alongside its other changes. If
  the selected form or quoted value becomes stale, refresh the details before another Sell action;
  never silently sell a replacement instance or show an unconfirmed payout as earned.
- The originally granted sword and shield allow Equip/Unequip but show no Sell or Discard action.
  Clearly identify them as retained starter gear. Unequip puts the item away without removing
  ownership or freeing an Equipment slot. Launch uses the existing Equipment inventory; do not show
  a storage-box interface or placeholder before its future update.
- Crafting Station menus show recipes and one active Equipment job. Jobs are not a separate
  Inventory tab. Waiting queues and station upgrades arrive in future updates.
- The Base menu builds only Shrines and shows Gold plus fixed Material-mix costs for additional build slots. Count
  only constructed Shrines in the build-space display: a fresh Base shows **0 / 2** used even with
  its included Crafting Station. Keep this distinct from a Shrine's Mythling assignment slots.
- Each expansion preview shows **+1 Shrine slot**, its Gold and required Material amounts, and the resulting unlocked
  capacity, up to **6 slots**. Keep used/unlocked capacity separate from this maximum. Once all six
  are unlocked, show **Maximum build slots unlocked** with no further purchase action or price.
  Dismantling reduces occupied slots without reducing the displayed unlocked capacity.
  Show each required element and owned/needed quantity; do not offer substitute-Material choices.
- Each Shrine has one **Upgrade** action for its next level, with a preview of assignment slots
  and storage before/after plus its Gold and matching-Material costs. Levels 1/2/3 offer 1/2/3
  Mythling slots; show **Maximum Shrine level** at level 3 without another purchase action.
  Keep Shrine levels distinct from Mythling XP levels and Base build slots. Do not show
  separate worker-slot/storage upgrades or promise an immediate production increase from an empty
  new slot.
  Read storage capacity from the confirmed Shrine level. The daily collection target is a tuning
  reference, not a guaranteed 24-hour countdown or a capacity that changes with assignments.
- The permanent Station's Proximity Prompt opens crafting from the first join. Show no Station
  purchase, construction, unlock, Sell, or Dismantle action. Equipment recipe details retain their
  own Gold and Material requirements; an included Station does not waive crafting costs.
  Read recipe duration from configuration (initially one minute); an active job's countdown follows
  its recorded server deadline, including after reconnect or a later recipe change.
- Group launch craftable Equipment variants under **Swords** and **Shields**. Each entry's details
  show six labeled element choices. Selecting one updates the variant name, fixed rarity, preview, matching
  Material requirement, owned quantity, Gold cost, and craft time. Use the approved name for each
  element's Sword and Shield: **Vulcan** (Fire), **Triton** (Water), **Atlas** (Earth), **Aura** (Air),
  **Sol** (Light), and **Nyx** (Dark). The plain starter pair remains **Wooden Sword** and
  **Wooden Shield**.
- Show that all launch swords share the wooden sword's base statistics, with each crafted sword
  adding its element's automatic effect. Crafting, Shop, and Inventory previews briefly describe
  that effect, following the [GDD effect definitions](GDD.md#elemental-sword-effects): Fire drains
  Stamina, Water slows walking, Earth roots movement after landing, Air increases horizontal push,
  Light weakens outgoing horizontal push, and Dark returns some attacker Stamina on an accepted,
  unblocked hit. Use configured values when showing magnitudes or durations. The wooden sword has
  no elemental effect. All crafted Shield variants share gameplay values and have no elemental
  abilities; their improvement over the wooden Shield is Stamina efficiency. Future upgrades may
  develop different base statistics; their detailed UI remains to be designed.
- Variant choices remain inspectable when unaffordable; disable Craft with the specific shortage
  or capacity reason. Spend only the selected variant recipe's listed inputs. A change in Inventory
  must not silently select another variant or substitute its Materials.
- Use element names alongside variant colors, retain the Equipment category's action color, and
  show the item's name, element, and fixed rarity in Inventory, active jobs, and completion feedback.
  Grouping the crafting catalogue does not merge owned Equipment copies or their capacity use.
  Plain starter gear has no element selector; an owned item's element cannot be changed through its
  detail view.
- Show job completion as a confirmed grant to Equipment, with the station ready for another recipe.
  Do not add a Claim button or an awaiting-claim slot.
- Where capacity is shown or blocks collection, distinguish owned items from space reserved for the
  active Crafting Job's output/refund. Identify the job holding that space and explain that it is
  released when the job resolves; spending Materials does not necessarily free their capacity.
- Shrine Collect shows the amount actually transferred and any output left in storage. Show a
  capacity warning when nothing fits; a partial transfer must not appear to have collected all.
- Show ready Materials as whole quantities. Represent unfinished production separately as progress
  or time until the next item, never as a fractional Material count. Collecting ready items must not
  reset that progress display. Swaps and evolution retain progress while the estimate reflects the
  new production speed. When no workers remain, show production as paused and retain its progress;
  resume the display when workers return.
- Derive the next-item estimate from server-confirmed progress and current total Yield. Reflect
  worker assignments and level/evolution changes instead of presenting a fixed timer for every
  Shrine. Online and offline estimates follow the same production rules. Keep ingredient-production
  estimates separate from the recipe's crafting time, and show XP progress even when no whole
  Material has finished yet.
- Material entries offer **Sell** as their primary action. Let players choose a whole quantity and
  preview the configured unit price and total Gold before submitting. Use owned Inventory amounts;
  output still in Shrine storage and crafting refund reservations are not sellable quantities.
  Confirm the actual sold amount and Gold from the server response. Rejected or stale quantities
  refresh the available amount without silently selling a different quantity.
- Put Material Discard in the entry's secondary/overflow actions. Its confirmation identifies the
  Material and quantity, states that removal is permanent, and uses the destructive treatment.
  Distinguish Discard, which gives no Gold, from Sell.
- Put Dismantle in the Shrine menu's secondary actions. Explain that assigned Mythlings and stored
  Materials must be removed first. Its confirmation states that the building and its upgrades are
  lost without a refund; display no implied refund or reusable-building reward.
- Clearly distinguish offline Materials waiting in Shrine storage from collected Inventory
  Materials. A full Shrine shows that production and XP have paused until storage space is freed.
- When showing XP rates, identify the shared Shrine-work rate per working Mythling. Show each
  Mythling's own confirmed XP as whole amounts; swaps do not transfer earned XP to the replacement.
  Material output and storage overflow do not multiply or reduce the final batch's earned XP.
- Above a Mythling, emphasize the player's own capture meter and label it **You**. When contested,
  show the leading rival's progress separately with a clear rival label; neither meter implies
  ownership before the server confirms a capture.
- Normal jumps within the Capture Ring retain server-confirmed progress and occupancy. Do not pause
  or reset the meter, remove the player from the contest, or end overtime merely because they are
  airborne within the server's horizontal bounds and finite vertical allowance. Reflect normal
  decay and the end of that visit when the player crosses either bound, including a high launch.
- Show the spawn lifetime countdown from the server's resolved expiry deadline, including any
  named-form override. Keep it distinct from capture progress; do not infer it from rarity or
  restart it when the player enters a ring or the display reloads.
  When the server enters overtime, replace it with **Overtime**
  and retain the progress meters. Explain that the contest ends when someone captures the Mythling
  or everyone leaves the ring. Do not show negative time or invent another countdown; follow the
  server's contest state when removing the display.
- The Shield control indicates when Stamina is below the configured guard minimum. A depleted Shield
  must lose its protective presentation immediately when the server removes protection.
- Ordinary player-body collisions use Roblox's normal physics response. Do not present them as
  sword hits or Shield blocks, or show a contact Stamina cost or immunity activation.
- Attack and Shield controls reflect mutually exclusive actions: raising, holding, and lowering the
  Shield block attacks, and an active swing blocks Shield activation. Ending protection early must
  not make Attack appear available before lowering finishes.
- Attack and Shield controls are available only in the Arena; new hits require both players to be
  inside. Leaving sheathes equipped items without changing the saved Loadout. Existing active or
  pending elemental effects remain readable outside the Arena, and Stamina stays visible while
  Fire continues there. Crossing the boundary or changing Equipment must not visually clear,
  pause, or restart those effects or their timers.
- Elemental effects use the existing Attack control, with no extra ability buttons. Clearly
  distinguish Earth's pending root from its active movement restriction and its post-root recovery
  window. Follow confirmed effect state and timing; visuals do not establish hit eligibility,
  duration, or capture membership. Earth restricts walking/jumping, not attacks or guard when
  otherwise available. All elemental feedback remains non-lethal.
- Present only the accepted lingering negative effect: later Fire, Water, Earth, or Light effects
  cannot replace, extend, or queue behind it. An ignored effect must not appear to activate or
  refresh, although the accepted hit still has normal knockback feedback. Air and Dark retain
  their immediate feedback when eligible. A Shield block prevents a new effect, including Dark's
  return, without clearing an existing effect; misses and rejected hits show no granted benefit.
- Following the [GDD Shield rules](GDD.md#shield-actions), the Stamina display must not animate
  regeneration while the Shield is raising, raised, or lowering. Lowering must not visually credit
  time spent guarding as recovered Stamina. Reflect server-confirmed recovery from the fully lowered transition without
  adding a visual waiting period after release or guard break. Recovery continues during sword
  attacks and cooldowns while the Shield is fully lowered; do not pause the display for those
  actions or refill it on Equipment changes or Arena entry/re-entry.
- These are target launch rules; existing prototype screens must be aligned during implementation.

## Shop presentation

- Show **Materials**, **Featured**, and **Upgrades**. Materials lists all six normal elemental
  Materials; Featured rotates existing first-crafted swords and Shields; Upgrades retains eligible
  Inventory-capacity purchases. Keep Shrine construction and structure upgrades in their world menus.
- Inventory upgrade details show capacity before/after, Gold cost, and all six normal Materials in
  the fixed recipe with individual owned/needed quantities. Explain specific shortages and protect
  crafting reservations;
  no element substitution or payment-Material selector is offered. A full Inventory does not block
  an upgrade when all costs are already owned. Confirm the resource deductions and capacity grant
  together from the server; upgrades have no Material/Featured restock allowance. Show only the
  next sequential upgrade for each category. Once its two upgrades are owned, show **Maximum
  capacity** for that category with no purchase action; do not imply a refresh will unlock more.
- Material details show name, element, owned quantity, unit Gold price, selected whole quantity,
  total Gold cost, and **Your stock remaining**. A missing elemental Shrine does not disable Buy.
  Limit the quantity selector to current stock, affordability, and unreserved Inventory capacity;
  server validation still decides the purchase. Never silently reduce a submitted quantity. The
  initial allowance is 10 of each Material per player per refresh, independent of Base size.
- Featured details identify the exact named Equipment, element, fixed rarity, statistics, sword
  effect where applicable, Gold price, and personal stock. Make clear that it is a finished item
  delivered to Equipment Inventory. Retain the same item identity, statistics, and effect as its
  crafting entry; buying does not auto-equip it or start a Crafting Job. Do not show later Equipment
  tiers or deferred archetypes.
- Show one server-derived **Refreshes in** countdown for Materials and Featured. At zero, request
  the current authoritative view; the timer alone cannot replenish displayed purchasable stock.
  The initial interval is one hour (60 minutes), resolved from server configuration. Featured
  rotates one matching sword-and-Shield pair through **Fire → Water → Earth → Air → Light → Dark**,
  then repeats after six hours. All servers follow the same hourly period and Featured element;
  rejoining, resetting, or changing servers cannot restart the countdown, cycle, or personal
  allowance. Unused stock and missed refreshes do not accumulate. Upgrades have no restock countdown
  and retain their purchased state.
- Keep exhausted offer cards visible with **Sold out for you** and the next refresh time; all six
  Materials remain inspectable. Exhausted personal stock is distinct from a genuinely empty Featured
  selection. Explain blocked purchases with the specific Gold, stock, eligibility, or Inventory
  reason, including space held by an active Crafting Job.
  Exhausting an allowance is a normal waiting state: use **Restocks at the next refresh** and keep
  the countdown visible. The player can close the Shop and return later; staying online is not
  required for restocking. Initially, Featured shows one matching sword and Shield with one copy
  of each per player.
- Buy uses the selected offer, quantity, and displayed price. Show pending feedback and confirm
  delivery, Gold, and stock from the server result. If an offer expires or changes while selected,
  update the view and require a fresh Buy action; do not apply the previous action to its replacement.
  Loading or synchronization failure uses the existing distinct states, without implying empty stock.

## Equipment compatibility presentation — future updates

Follow the GDD's [Equipment compatibility rules](GDD.md#equipment-compatibility). These conventions
apply when two-handed archetypes are introduced after launch. Their selection and update order
remain undecided; these controls are not MVP requirements.

- Label weapon details **One-handed** or **Two-handed**. Two-handed details explain **Equipping
  this weapon puts your Shield away** before Equip. Confirm the resulting Loadout from the server;
  the Shield remains in Equipment inventory and still occupies capacity.
- Describe the two-handed benefit as **Stronger knockback**, alongside its lack of Shield access.
  Use configured values in comparisons; do not label attack force as health damage or imply that
  two-handed attacks automatically break Shields.
- While a two-handed weapon is equipped, disable Shield Equip with **Unavailable with a two-handed
  weapon**. Keep the Arena Shield control in its usual position but disabled; distinguish this
  Loadout restriction from low Stamina. Do not offer guard by sheathing the weapon.
- After switching to a compatible Loadout, show the Shield slot as empty until the player equips
  one. Guard remains unavailable without an equipped Shield; do not imply automatic restoration.

## Accessibility and feedback

- Keep panels and interactive controls inside mobile safe areas, with reachable touch targets,
  flexible layouts, legible text, and device-safe clipping.
- Communicate important capture, ownership, capacity, and action states through text, shape, icons,
  or other cues as well as color.
- Respect Reduce Motion and sound settings. Replace screen shake and flashing with static,
  non-flashing feedback when Reduce Motion is enabled.
- Distinguish pending requests from confirmed results and explain actionable failures. Feedback may
  acknowledge input immediately, but menus cannot present unconfirmed purchases or rewards as owned.
  Responsive combat presentation follows the exception in Technical Design.

## Category color and actions

- A category's tab icon and enabled primary action use the same semantic color.
- Launch Inventory mappings are Mythlings/gold, Equipment/blue, and Materials/amber. Material Sell
  uses the amber primary-action treatment. Consumables/green is retained for its future update.
- Shop mappings are Materials/amber, Featured/pink, and Upgrades/violet. Purchase actions inherit
  the active Shop category color when an eligible offer exists.
- Disabled actions use the neutral disabled treatment, not a faded category fill.
- Inventory entries that are not sellable show no Sell action.
- Overflow buttons remain neutral so they read as menu controls rather than primary actions.
- Destructive confirmation actions remain red regardless of category.
- Client UI may present planned action placement before its server endpoint exists, but the action
  must remain disabled and must never fake an authoritative mutation. This applies to included
  launch features; it does not override the requirement to hide deferred systems.

## Menu empty states

- When a tab has no items or offers, replace the grid/details composition with one centered,
  full-body empty state. Do not leave blank artwork, placeholder statistics, or action controls
  visible.
- Use the category's icon and semantic color, a direct title, and one concise acquisition hint.
- Do not add a call-to-action button when acquisition requires returning to world gameplay.
- Preserve the panel dimensions so switching between empty and populated tabs does not move the
  menu.
- Use the same directional page transition for every tab change, whether either tab is empty or
  populated. Empty-state content must not appear only after the page transition starts.
- Treat loading, synchronization failure, and confirmed empty results as different states. Do not
  flash the empty state before the first authoritative snapshot resolves. After a failure, retain
  any last confirmed view and show that it is unavailable or awaiting synchronization.

Approved Inventory copy:

- Mythlings: **No Mythlings yet** — Capture Mythlings in the Arena.
- Equipment: **No Equipment yet** — Craft Equipment at your Station or buy a Featured Shop offer.
- Materials: **No Materials yet** — Collect Materials from Shrines or buy them in the Shop.

Retained copy for the future Consumables update:

- Consumables: **No Consumables yet** — Craft Consumables at a Crafting Station.

Approved Shop copy:

- Featured: **No Featured offers this refresh** — New offers arrive at the next refresh.
- Upgrades, once all three categories are fully upgraded: **Maximum Inventory capacity** — All
  Inventory upgrades purchased.

Materials has no normal empty catalogue state: all six are listed, including sold-out entries.
Missing catalogue data uses the loading or synchronization-failure treatment, including missing
upgrade definitions when the player has not purchased every upgrade.
