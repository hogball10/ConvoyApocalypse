--!strict
--[[
	Garage-only trading. One player asks, the other accepts; then both put
	unplaced parts (several copies allowed) and scrap on the table and both
	confirm. Changing an offer un-confirms both sides. Everything is
	re-validated server-side the moment the swap happens.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local ConvoyRunService = require(script.Parent:WaitForChild("ConvoyRunService"))
local GarageService -- delayed require to avoid cycle

export type Offer = {
	parts: { string }, -- one entry per copy, so duplicates repeat
	scrap: number,
	confirmed: boolean,
}

export type TradeSession = {
	id: string,
	a: number, -- userId
	b: number,
	offers: { [number]: Offer },
	lastActive: number,
}

export type Request = {
	from: number,
	at: number,
}

local TradeService = {}
TradeService._trades = {} :: { [string]: TradeSession }
TradeService._byPlayer = {} :: { [number]: string }
-- A request waits here, keyed by the player being asked, until they answer.
TradeService._pending = {} :: { [number]: Request }

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

-- Drops a waiting request and tells the asked player to close the popup.
local function clearRequest(targetUserId: number)
	if not TradeService._pending[targetUserId] then
		return
	end
	TradeService._pending[targetUserId] = nil
	local target = getPlayer(targetUserId)
	if target then
		Remotes.Event("TradeUpdate"):FireClient(target, { requestEnded = true })
	end
end

local function tally(list: { string }): { [string]: number }
	local counts = {}
	for _, partId in list do
		counts[partId] = (counts[partId] or 0) + 1
	end
	return counts
end

-- Can this player really hand over these parts and this much scrap right now?
local function canCover(player: Player, offer: Offer): boolean
	local profile = DataService.Get(player)
	if not profile or profile.scrap < offer.scrap then
		return false
	end
	for partId, count in tally(offer.parts) do
		if DataService.GetUnequippedCount(player, partId) < count then
			return false
		end
	end
	return true
end

-- Trading only works while both are in the same garage and not out on a run.
local function stillTogether(a: Player, b: Player): boolean
	return not ConvoyRunService.IsInRun(a)
		and not ConvoyRunService.IsInRun(b)
		and GarageService.AreInSameGarage(a, b)
end

local function bothFree(a: Player, b: Player): boolean
	return not TradeService._byPlayer[a.UserId] and not TradeService._byPlayer[b.UserId] and stillTogether(a, b)
end

local function open(a: Player, b: Player)
	local id = "trade_" .. tostring(a.UserId) .. "_" .. tostring(b.UserId) .. "_" .. tostring(os.time())
	local trade: TradeSession = {
		id = id,
		a = a.UserId,
		b = b.UserId,
		offers = {
			[a.UserId] = { parts = {}, scrap = 0, confirmed = false },
			[b.UserId] = { parts = {}, scrap = 0, confirmed = false },
		},
		lastActive = os.clock(),
	}
	TradeService._trades[id] = trade
	TradeService._byPlayer[a.UserId] = id
	TradeService._byPlayer[b.UserId] = id
	replicate(trade)
end

function TradeService.Execute(trade: TradeSession)
	local pa, pb = getPlayer(trade.a), getPlayer(trade.b)
	if not pa or not pb then
		cancel(trade.id, "Player left")
		return
	end
	if not stillTogether(pa, pb) then
		cancel(trade.id, "Trade cancelled: you must both stay in the garage")
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

	-- Re-validate: anything could have changed since the offers were made.
	if not canCover(pa, offerA) or not canCover(pb, offerB) then
		cancel(trade.id, "Something changed, so the trade was cancelled")
		return
	end

	-- Transfer scrap
	profileA.scrap += offerB.scrap - offerA.scrap
	profileB.scrap += offerA.scrap - offerB.scrap

	-- Transfer parts
	for _, partId in offerA.parts do
		DataService.RemoveOwnedPart(pa, partId)
		DataService.AddOwnedPart(pb, partId)
	end
	for _, partId in offerB.parts do
		DataService.RemoveOwnedPart(pb, partId)
		DataService.AddOwnedPart(pa, partId)
	end

	TradeService._byPlayer[trade.a] = nil
	TradeService._byPlayer[trade.b] = nil
	TradeService._trades[trade.id] = nil

	DataService.Replicate(pa)
	DataService.Replicate(pb)
	DataService.Save(pa)
	DataService.Save(pb)

	notify(pa, "Trade complete!")
	notify(pb, "Trade complete!")
	Remotes.Event("TradeUpdate"):FireClient(pa, { id = trade.id, completed = true })
	Remotes.Event("TradeUpdate"):FireClient(pb, { id = trade.id, completed = true })
end

function TradeService.Init()
	GarageService = require(script.Parent:WaitForChild("GarageService"))

	-- Step 1: ask. Nothing opens until the other player says yes.
	Remotes.Event("TradeRequest").OnServerEvent:Connect(function(player, targetUserId: any)
		if typeof(targetUserId) ~= "number" or targetUserId == player.UserId then
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
		if ConvoyRunService.IsInRun(player) or ConvoyRunService.IsInRun(target) then
			notify(player, "Trading only in the garage")
			return
		end
		if not GarageService.AreInSameGarage(player, target) then
			notify(player, "Trading only in the garage")
			return
		end
		local waiting = TradeService._pending[targetUserId]
		if waiting and waiting.from ~= player.UserId then
			notify(player, target.Name .. " already has a trade request")
			return
		end
		-- One open request per player: a new one replaces any earlier one.
		for askedId, request in TradeService._pending do
			if request.from == player.UserId and askedId ~= targetUserId then
				clearRequest(askedId)
			end
		end

		TradeService._pending[targetUserId] = { from = player.UserId, at = os.clock() }
		Remotes.Event("TradeUpdate"):FireClient(target, { request = { fromUserId = player.UserId, fromName = player.Name } })
		notify(player, "Trade request sent to " .. target.Name)
	end)

	-- Step 2: answer.
	Remotes.Event("TradeRespond").OnServerEvent:Connect(function(player, fromUserId: any, accept: any)
		if typeof(fromUserId) ~= "number" or typeof(accept) ~= "boolean" then
			return
		end
		local request = TradeService._pending[player.UserId]
		if not request or request.from ~= fromUserId then
			return
		end
		clearRequest(player.UserId)

		local asker = getPlayer(fromUserId)
		if not asker then
			return
		end
		if not accept then
			notify(asker, player.Name .. " declined the trade")
			return
		end
		if not bothFree(asker, player) then
			notify(asker, "Trade could not start")
			notify(player, "Trade could not start")
			return
		end
		open(asker, player)
		notify(asker, player.Name .. " accepted. Choose what to offer")
	end)

	-- Setting your side of the table. Every change un-confirms both players.
	Remotes.Event("TradeUpdate").OnServerEvent:Connect(function(player, offerParts: any, scrap: any)
		local tradeId = TradeService._byPlayer[player.UserId]
		local trade = tradeId and TradeService._trades[tradeId]
		if not trade then
			return
		end
		if typeof(offerParts) ~= "table" or typeof(scrap) ~= "number" or scrap ~= scrap or scrap == math.huge then
			return
		end
		scrap = math.max(0, math.floor(scrap))

		local clean: { string } = {}
		for _, partId in offerParts do
			if typeof(partId) == "string" and PartsCatalog.Get(partId) then
				table.insert(clean, partId)
				if #clean > Constants.TRADE_MAX_PARTS then
					notify(player, "You can offer up to " .. tostring(Constants.TRADE_MAX_PARTS) .. " parts")
					return
				end
			end
		end

		local offer: Offer = { parts = clean, scrap = scrap, confirmed = false }
		if not canCover(player, offer) then
			notify(player, "You can only offer parts and scrap you have free")
			replicate(trade)
			return
		end

		trade.offers[player.UserId] = offer
		trade.offers[trade.a].confirmed = false
		trade.offers[trade.b].confirmed = false
		trade.lastActive = os.clock()
		replicate(trade)
	end)

	Remotes.Event("TradeConfirm").OnServerEvent:Connect(function(player)
		local tradeId = TradeService._byPlayer[player.UserId]
		local trade = tradeId and TradeService._trades[tradeId]
		if not trade then
			return
		end
		local offerA, offerB = trade.offers[trade.a], trade.offers[trade.b]
		if #offerA.parts + #offerB.parts == 0 and offerA.scrap + offerB.scrap == 0 then
			notify(player, "Put something on the table first")
			return
		end
		trade.offers[player.UserId].confirmed = true
		trade.lastActive = os.clock()
		replicate(trade)

		if offerA.confirmed and offerB.confirmed then
			TradeService.Execute(trade)
		end
	end)

	Remotes.Event("TradeCancel").OnServerEvent:Connect(function(player)
		local tradeId = TradeService._byPlayer[player.UserId]
		if tradeId then
			cancel(tradeId, "Trade cancelled")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local tradeId = TradeService._byPlayer[player.UserId]
		if tradeId then
			cancel(tradeId, player.Name .. " left the game")
		end
		clearRequest(player.UserId)
		for askedId, request in TradeService._pending do
			if request.from == player.UserId then
				clearRequest(askedId)
			end
		end
	end)

	-- Sweeper: stale requests, idle trades, and anyone who wandered off.
	task.spawn(function()
		while true do
			task.wait(2)
			local now = os.clock()
			for askedId, request in TradeService._pending do
				if now - request.at > Constants.TRADE_REQUEST_TIMEOUT then
					local asker = getPlayer(request.from)
					if asker then
						notify(asker, "No answer to your trade request")
					end
					clearRequest(askedId)
				end
			end
			for id, trade in TradeService._trades do
				local pa, pb = getPlayer(trade.a), getPlayer(trade.b)
				if now - trade.lastActive > Constants.TRADE_TIMEOUT then
					cancel(id, "Trade timed out")
				elseif pa and pb and not stillTogether(pa, pb) then
					cancel(id, "Trade cancelled: you must both stay in the garage")
				end
			end
		end
	end)
end

return TradeService
