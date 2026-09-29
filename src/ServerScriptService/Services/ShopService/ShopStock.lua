--!strict
-- ServerScriptService/Services/ShopService/ShopStock
-- Read a detached current-period allowance without resetting saved state on a view or failure.

local ShopStock = {}

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

function ShopStock.Read(rawShop: unknown, currentPeriod: number): ({ [string]: number }?, string?)
	if not whole(currentPeriod) then
		return nil, "InvalidShopState"
	end
	if rawShop == nil then
		return {}, nil
	end
	if type(rawShop) ~= "table" or getmetatable(rawShop) ~= nil then
		return nil, "InvalidShopState"
	end
	local shop = rawShop :: { [unknown]: unknown }
	for key in shop do
		if key ~= "periodId" and key ~= "purchased" then
			return nil, "InvalidShopState"
		end
	end
	if
		not whole(shop.periodId)
		or type(shop.purchased) ~= "table"
		or getmetatable(shop.purchased) ~= nil
	then
		return nil, "InvalidShopState"
	end
	local purchased: { [string]: number } = {}
	for key, value in shop.purchased :: { [unknown]: unknown } do
		if type(key) ~= "string" or #key == 0 or #key > 128 or not whole(value) then
			return nil, "InvalidShopState"
		end
		purchased[key] = value :: number
	end
	-- Validate historical state before rollover. Unknown usage keys survive the same period;
	-- catalogue changes cannot clear them, and a clock rollback cannot restore an allowance.
	local savedPeriod = shop.periodId :: number
	if savedPeriod > currentPeriod then
		return nil, "ShopClockBehind"
	end
	return if savedPeriod == currentPeriod then purchased else {}, nil
end

return table.freeze(ShopStock)
