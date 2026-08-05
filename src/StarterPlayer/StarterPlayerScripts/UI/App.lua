-- StarterPlayer/StarterPlayerScripts/UI/App

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local HUD = require(script.Parent:WaitForChild("Screens"):WaitForChild("HUD"))
local Inventory = require(script.Parent:WaitForChild("Screens"):WaitForChild("Inventory"))
local ModalBackdrop = require(script.Parent:WaitForChild("Overlays"):WaitForChild("ModalBackdrop"))
local Toast = require(script.Parent:WaitForChild("Overlays"):WaitForChild("Toast"))

export type Props = {
	localData: Types.LocalDataApi,
	inventoryController: Types.InventoryControllerApi,
}

local function App(scope: any, props: Props): { ScreenGui }
	local modalBackdrop = ModalBackdrop(scope)
	local toast = Toast(scope)
	local inventory = Inventory(scope, props)
	local hud = HUD(scope, props)
	return { modalBackdrop, toast, inventory, hud }
end

return App
