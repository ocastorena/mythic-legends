--!strict
-- ReplicatedStorage/Shared/Configurations/Consumables

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)
--
-- Consumables are deferred. Preserve legacy ownership; definitions belong here once
-- their effects and tuning are approved; health-restoring Consumables are intentionally absent.

local Consumables: { [string]: Types.ConsumableDef } = {}

return FreezeUtil.DeepFreeze(Consumables)
