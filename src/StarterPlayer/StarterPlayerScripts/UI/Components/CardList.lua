--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/CardList
-- Typed selectable cards; each card owns its click connection through GUI destruction.

local ButtonUtil = require(script.Parent.Parent.ButtonUtil)

local CardList = {}

export type Config<T> = {
	template: GuiButton,
	parent: Instance,
	setHighlight: (GuiButton, boolean) -> (),
	decorate: ((GuiButton, string, T) -> ())?,
	onSelect: ((string, T, GuiButton) -> ())?,
	filter: ((string, T) -> boolean)?,
	autoSelectFirst: boolean?,
}

export type List<T> = {
	GetSelectedId: (List<T>) -> string?,
	GetSelectedCard: (List<T>) -> GuiButton?,
	GetData: (List<T>, string) -> T?,
	GetCard: (List<T>, string) -> GuiButton?,
	ClearSelection: (List<T>) -> (),
	Select: (List<T>, string) -> (),
	Add: (List<T>, string, T) -> GuiButton?,
	Remove: (List<T>, string) -> (),
	Clear: (List<T>) -> (),
	Replace: (List<T>, { [string]: T }) -> (),
	Cards: (List<T>) -> { [string]: GuiButton },
}

function CardList.new<T>(config: Config<T>): List<T>
	local cards: { [string]: GuiButton } = {}
	local data: { [string]: T } = {}
	local selectedId: string? = nil

	local function clearSelection()
		local card = if selectedId then cards[selectedId] else nil
		if card then
			config.setHighlight(card, false)
		end
		selectedId = nil
	end

	local function selectCard(id: string)
		if selectedId == id then
			return
		end
		local card = cards[id]
		if not card then
			return
		end
		clearSelection()
		config.setHighlight(card, true)
		selectedId = id
		local onSelect = config.onSelect
		if onSelect then
			onSelect(id, data[id], card)
		end
	end

	local function add(id: string, entry: T): GuiButton?
		if cards[id] then
			return cards[id]
		end
		local filter = config.filter
		if filter and not filter(id, entry) then
			return nil
		end
		local card = config.template:Clone()
		card.Name = id
		card.Visible = true
		card.LayoutOrder = 1
		card.Parent = config.parent
		local decorate = config.decorate
		if decorate then
			decorate(card, id, entry)
		end
		cards[id] = card
		data[id] = entry
		ButtonUtil.HookClick(card, function()
			selectCard(id)
		end)
		if config.autoSelectFirst ~= false and not selectedId then
			selectCard(id)
		end
		return card
	end

	local function clear()
		for _, card in cards do
			card:Destroy()
		end
		table.clear(cards)
		table.clear(data)
		selectedId = nil
	end

	return {
		GetSelectedId = function(_self)
			return selectedId
		end,
		GetSelectedCard = function(_self)
			return if selectedId then cards[selectedId] else nil
		end,
		GetData = function(_self, id)
			return data[id]
		end,
		GetCard = function(_self, id)
			return cards[id]
		end,
		ClearSelection = function(_self)
			clearSelection()
		end,
		Select = function(_self, id)
			selectCard(id)
		end,
		Add = function(_self, id, entry)
			return add(id, entry)
		end,
		Remove = function(_self, id)
			if selectedId == id then
				selectedId = nil
			end
			local card = cards[id]
			if card then
				card:Destroy()
			end
			cards[id] = nil
			data[id] = nil
		end,
		Clear = function(_self)
			clear()
		end,
		Replace = function(_self, values)
			clear()
			for id, entry in values do
				add(id, entry)
			end
		end,
		Cards = function(_self)
			return cards
		end,
	}
end

return CardList
