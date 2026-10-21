--!strict
--[[
	Garage-only trading. Both players offer unequipped parts + optional scrap.
	Both must confirm. Host/final inventory validated server-side.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local GarageService -- delayed require to avoid cycle

export type Offer = {
	parts: { string },
	scrap: number,
	confirmed: boolean,
}

export type TradeSession = {
	id: string,
	a: number, -- userId
	b: number,
	offers: { [number]: Offer },
	createdAt: number,
}

local TradeService = {}
TradeService._trades = {} :: { [string]: TradeSession }
TradeService._byPlayer = {} :: { [number]: string }

local function notify(player: Player, msg: string)
	Remotes.Event("Notification"):FireClient(player, msg)
end

local function getPlayer(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function replicate(trade: TradeSession)
	local payload = {
		id = trade.id,
		a = trade.a,
		b = trade.b,
		offers = {
			[tostring(trade.a)] = trade.offers[trade.a],
			[tostring(trade.b)] = trade.offers[trade.b],
		},
	}
	local pa, pb = getPlayer(trade.a), getPlayer(trade.b)
	if pa then
		Remotes.Event("TradeUpdate"):FireClient(pa, payload)
	end
	if pb then
		Remotes.Event("TradeUpdate"):FireClient(pb, payload)
	end
end

local function cancel(tradeId: string, reason: string?)
	local trade = TradeService._trades[tradeId]
	if not trade then
		return
	end
	TradeService._byPlayer[trade.a] = nil
	TradeService._byPlayer[trade.b] = nil
	TradeService._trades[tradeId] = nil
	for _, userId in { trade.a, trade.b } do
		local p = getPlayer(userId)
		if p then
			Remotes.Event("TradeUpdate"):FireClient(p, { id = tradeId, cancelled = true, reason = reason })
			if reason then
				notify(p, reason)
			end
		end
	end
end

function TradeService.Init()
	GarageService = require(script.Parent:WaitForChild("GarageService"))

	Remotes.Event("TradeRequest").OnServerEvent:Connect(function(player, targetUserId: number)
		if typeof(targetUserId) ~= "number" then
			return
		end
		if TradeService._byPlayer[player.UserId] then
			notify(player, "Already in a trade")
			return
		end
		local target = getPlayer(targetUserId)
		if not target then
			notify(player, "Player not found")
			return
		end
		if TradeService._byPlayer[targetUserId] then
			notify(player, "They are busy trading")
			return
		end
		-- Garage only
		if not GarageService.AreInSameGarage(player, target) then
			notify(player, "Trading only in the garage")
			return
		end

		local id = "trade_" .. tostring(player.UserId) .. "_" .. tostring(targetUserId) .. "_" .. tostring(os.time())
		local trade: TradeSession = {
			id = id,
			a = player.UserId,
			b = targetUserId,
			offers = {
				[player.UserId] = { parts = {}, scrap = 0, confirmed = false },
				[targetUserId] = { parts = {}, scrap = 0, confirmed = false },
			},
			createdAt = os.clock(),
		}
		TradeService._trades[id] = trade
		TradeService._byPlayer[player.UserId] = id
		TradeService._byPlayer[targetUserId] = id
		replicate(trade)
		notify(target, player.Name .. " wants to trade")
		notify(player, "Trade opened with " .. target.Name)
	end)

	Remotes.Event("TradeUpdate").OnServerEvent:Connect(function(player, offerParts: any, scrap: any)
		local tradeId = TradeService._byPlayer[player.UserId]
		local trade = tradeId and TradeService._trades[tradeId]
		if not trade then
			return
		end
		if typeof(offerParts) ~= "table" or typeof(scrap) ~= "number" then
			return
		end
		scrap = math.max(0, math.floor(scrap))

		-- Validate parts are unequipped owned
		local clean = {}
		local seen = {}
		for _, partId in offerParts do
			if typeof(partId) == "string" and PartsCatalog.Get(partId) and not seen[partId] then
				seen[partId] = true
				table.insert(clean, partId)
			end
		end
		-- Count duplicates properly: for prototype each partId once in offer
		for _, partId in clean do
			if DataService.GetUnequippedCount(player, partId) < 1 then
				notify(player, "Can only trade unequipped owned parts")
				return
			end
		end
		local profile = DataService.Get(player)
		if not profile or profile.scrap < scrap then
			notify(player, "Not enough scrap")
			return
		end

		local offer = trade.offers[player.UserId]
		offer.parts = clean
		offer.scrap = scrap
		offer.confirmed = false
		trade.offers[trade.a].confirmed = false
		trade.offers[trade.b].confirmed = false
		replicate(trade)
	end)

	Remotes.Event("TradeConfirm").OnServerEvent:Connect(function(player)
		local tradeId = TradeService._byPlayer[player.UserId]
		local trade = tradeId and TradeService._trades[tradeId]
		if not trade then
			return
		end
		trade.offers[player.UserId].confirmed = true
		replicate(trade)

		if trade.offers[trade.a].confirmed and trade.offers[trade.b].confirmed then
			TradeService.Execute(trade)
		end
	end)

	Remotes.Event("TradeCancel").OnServerEvent:Connect(function(player)
		local tradeId = TradeService._byPlayer[player.UserId]
		if tradeId then
			cancel(tradeId, "Trade cancelled")
		end
	end)

	-- Timeout sweeper
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for id, trade in TradeService._trades do
				if now - trade.createdAt > Constants.TRADE_TIMEOUT then
					cancel(id, "Trade timed out")
				end
			end
		end
	end)
end

function TradeService.Execute(trade: TradeSession)
	local pa, pb = getPlayer(trade.a), getPlayer(trade.b)
	if not pa or not pb then
		cancel(trade.id, "Player left")
		return
	end

	local offerA = trade.offers[trade.a]
	local offerB = trade.offers[trade.b]
	local profileA = DataService.Get(pa)
	local profileB = DataService.Get(pb)
	if not profileA or not profileB then
		cancel(trade.id, "Data missing")
		return
	end

	-- Re-validate
	if profileA.scrap < offerA.scrap or profileB.scrap < offerB.scrap then
		cancel(trade.id, "Scrap changed — cancelled")
		return
	end
	for _, partId in offerA.parts do
		if DataService.GetUnequippedCount(pa, partId) < 1 then
			cancel(trade.id, "Parts changed — cancelled")
			return
		end
	end
	for _, partId in offerB.parts do
		if DataService.GetUnequippedCount(pb, partId) < 1 then
			cancel(trade.id, "Parts changed — cancelled")
			return
		end
	end

	-- Transfer scrap
	profileA.scrap -= offerA.scrap
	profileB.scrap -= offerB.scrap
	profileA.scrap += offerB.scrap
	profileB.scrap += offerA.scrap

	-- Transfer parts
	for _, partId in offerA.parts do
		DataService.RemoveOwnedPart(pa, partId)
		DataService.AddOwnedPart(pb, partId)
	end
	for _, partId in offerB.parts do
		DataService.RemoveOwnedPart(pb, partId)
		DataService.AddOwnedPart(pa, partId)
	end

	DataService.Replicate(pa)
	DataService.Replicate(pb)
	DataService.Save(pa)
	DataService.Save(pb)

	TradeService._byPlayer[trade.a] = nil
	TradeService._byPlayer[trade.b] = nil
	TradeService._trades[trade.id] = nil

	notify(pa, "Trade complete!")
	notify(pb, "Trade complete!")
	Remotes.Event("TradeUpdate"):FireClient(pa, { id = trade.id, completed = true })
	Remotes.Event("TradeUpdate"):FireClient(pb, { id = trade.id, completed = true })
end

return TradeService
