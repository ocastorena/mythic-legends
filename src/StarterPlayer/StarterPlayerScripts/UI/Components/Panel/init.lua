--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel
-- Stable public facade for the menu shell and its independently owned presentation parts.

local ActionMenu = require(script.ActionMenu)
local Controls = require(script.Controls)
local Details = require(script.Details)
local EmptyState = require(script.EmptyState)
local Grid = require(script.Grid)
local Modal = require(script.Modal)
local Primitives = require(script.Primitives)
local Proximity = require(script.Proximity)
local Shell = require(script.Shell)

export type PanelConfig = Shell.PanelConfig
export type Panel = Shell.Panel
export type CellConfig = Grid.CellConfig
export type DetailsConfig = Details.DetailsConfig
export type Details = Details.Details
export type ModalConfig = Modal.ModalConfig
export type Modal = Modal.Modal
export type EmptyStateView = EmptyState.View

local Panel = {
	Create = Shell.Create,
	SetDetailsVisible = Shell.SetDetailsVisible,
	CreateGrid = Grid.CreateGrid,
	CreateCellTemplate = Grid.CreateCellTemplate,
	SetCellRing = Grid.SetCellRing,
	CreateDetails = Details.CreateDetails,
	SetHeroRarity = Details.SetHeroRarity,
	SetProgress = Details.SetProgress,
	CreateModal = Modal.CreateModal,
	CreateProximityButton = Proximity.CreateProximityButton,
	RescaleText = Primitives.RescaleText,
	ApplyTextScale = Primitives.ApplyTextScale,
	CreateActionMenu = ActionMenu.Create,
	CreateEmptyState = EmptyState.Create,
	Tab = Controls.Tab,
	SetTabActive = Controls.SetTabActive,
	PrimaryButton = Controls.PrimaryButton,
	SetButtonEnabled = Controls.SetButtonEnabled,
	SquareButton = Controls.SquareButton,
	SquareTextButton = Controls.SquareTextButton,
	MoreButton = Controls.MoreButton,
	CloseButton = Controls.CloseButton,
	CoinPill = Controls.CoinPill,
	LevelPill = Controls.LevelPill,
}

return Panel
