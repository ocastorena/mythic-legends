--!strict
-- ServerScriptService/Shared/GoldCreditUtil
-- Preserve exact crafting-refund headroom when crediting Gold on a transaction draft.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local GoldCreditUtil = {}
local MAX_SAFE_INTEGER = 9007199254740991

local function plain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value <= MAX_SAFE_INTEGER
		and value % 1 == 0
end

-- This validates only the known Gold claim. Crafting owns full receipt/result validation.
-- Unversioned legacy jobs without receipts retain their state without an invented refund.
function GoldCreditUtil.GetRefundReserve(data: Types.PlayerDoc): (number?, string?)
	if not plain(data) then
		return nil, "InvalidCraftingState"
	end
	local rawJobs: unknown = data.craftingJobs
	if rawJobs == nil then
		return 0, nil
	end
	if not plain(rawJobs) then
		return nil, "InvalidCraftingState"
	end
	local reserved = 0
	for _, rawJob in rawJobs :: { [unknown]: unknown } do
		if not plain(rawJob) then
			return nil, "InvalidCraftingState"
		end
		local job = rawJob :: { [string]: unknown }
		if job.status ~= "Active" and job.status ~= "Completed" and job.status ~= "Cancelled" then
			return nil, "InvalidCraftingState"
		end
		local rawReceipt = job.receipt
		if rawReceipt == nil then
			continue
		end
		if not plain(rawReceipt) then
			return nil, "InvalidCraftingState"
		end
		local receipt = rawReceipt :: { [string]: unknown }
		if receipt.version ~= 1 or not plain(receipt.paid) then
			return nil, "InvalidCraftingState"
		end
		local paid = receipt.paid :: { [string]: unknown }
		if not whole(paid.gold) then
			return nil, "InvalidCraftingState"
		end
		if job.status == "Active" then
			local gold = paid.gold :: number
			if gold > MAX_SAFE_INTEGER - reserved then
				return nil, "ArithmeticOverflow"
			end
			reserved += gold
		end
	end
	return reserved, nil
end

-- Return an error before changing the draft, or credit once while leaving every claim intact.
-- Cancellation releases its own claim in the same transaction BEFORE returning the paid Gold.
function GoldCreditUtil.CreditToDraft(draft: Types.PlayerDoc, amount: number): string?
	if
		not plain(draft)
		or not plain(draft.currency)
		or not whole(draft.currency.gold)
		or not whole(amount)
	then
		return "InvalidCurrency"
	end
	local reserved, problem = GoldCreditUtil.GetRefundReserve(draft)
	if reserved == nil then
		return problem or "InvalidCraftingState"
	end
	local room = MAX_SAFE_INTEGER - draft.currency.gold
	if reserved > room or amount > room - reserved then
		return "ArithmeticOverflow"
	end
	draft.currency.gold += amount
	return nil
end

return table.freeze(GoldCreditUtil)
