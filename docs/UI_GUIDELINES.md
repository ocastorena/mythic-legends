# Mythic Legends UI Guidelines

This document records approved application-menu behavior. Keep these rules consistent across
Inventory, Shop, Stand, and future panels unless a feature-specific design explicitly overrides
them.

## Category color and actions

- A category's tab icon and enabled primary action use the same semantic color.
- Inventory mappings are Mythlings/gold, Equipment/blue, Consumables/green, and
  Materials/amber. Materials currently have no primary action.
- Shop mappings are Featured/pink and Upgrades/violet. Purchase actions inherit the active
  Shop category color when an eligible offer exists.
- Disabled actions use the neutral disabled treatment, not a faded category fill.
- Overflow buttons remain neutral so they read as menu controls rather than primary actions.
- Destructive confirmation actions remain red regardless of category.
- Client UI may present planned action placement before its server endpoint exists, but the
  action must remain disabled and must never fake an authoritative mutation.

## Menu empty states

- When a tab has no items or offers, replace the grid/details composition with one centered,
  full-body empty state. Do not leave blank artwork, placeholder statistics, or action controls
  visible.
- Use the category's icon and semantic color, a direct title, and one concise acquisition hint.
- Do not add a call-to-action button when acquisition requires returning to world gameplay.
- Preserve the panel dimensions so switching between empty and populated tabs does not move
  the menu.
- Treat loading and empty as different states if inventory fetching becomes asynchronous; do
  not flash the empty state before the first authoritative snapshot resolves.

Approved Inventory copy:

- Mythlings: **No Mythlings yet** — Capture Mythlings in the Arena.
- Equipment: **No Equipment yet** — Craft Equipment at a Crafting Station.
- Consumables: **No Consumables yet** — Craft Consumables at a Crafting Station.
- Materials: **No Materials yet** — Assign Mythlings to Shrines and collect their output.

Approved Shop copy:

- Featured: **No Featured offers yet** — Check back later for new Shop offers.
- Upgrades: **No Upgrades available** — Check back later for new Inventory upgrades.
