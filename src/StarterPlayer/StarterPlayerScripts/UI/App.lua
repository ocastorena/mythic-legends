-- StarterPlayer/StarterPlayerScripts/UI/App

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local HUD = require(script.Parent:WaitForChild("Screens"):WaitForChild("HUD"))
local Hotbar = require(script.Parent:WaitForChild("Screens"):WaitForChild("Hotbar"))
local CombatActions = require(script.Parent:WaitForChild("Screens"):WaitForChild("CombatActions"))
local Inventory = require(script.Parent:WaitForChild("Screens"):WaitForChild("Inventory"))
local Shop = require(script.Parent:WaitForChild("Screens"):WaitForChild("Shop"))
local Stand = require(script.Parent:WaitForChild("Screens"):WaitForChild("Stand"))
local ModalBackdrop = require(script.Parent:WaitForChild("Overlays"):WaitForChild("ModalBackdrop"))
local Toast = require(script.Parent:WaitForChild("Overlays"):WaitForChild("Toast"))

export type Props = {
	localData: Types.LocalDataApi,
	inventoryController: Types.InventoryControllerApi,
	standController: Types.StandControllerApi,
	hotbarController: Types.HotbarControllerApi,
	combatController: Types.CombatControllerApi,
}

local function App(scope: any, props: Props): { ScreenGui }
	local modalBackdrop = ModalBackdrop(scope)
	local toast = Toast(scope)
	local inventory = Inventory(scope, props)
	local shop = Shop(scope)
	local stand = Stand(scope, props)
	local hotbar = Hotbar(scope, props)
	local combatActions = CombatActions(scope, props)
	local hud = HUD(scope, props)
	return { modalBackdrop, toast, inventory, shop, stand, hotbar, combatActions, hud }
end

return App
