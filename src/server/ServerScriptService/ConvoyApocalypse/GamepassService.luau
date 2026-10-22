--!strict
--[[
	Gamepasses: permanent Robux perks (2x scrap, 2x fuel...). The list lives in
	Constants.GAMEPASSES; what a pass does is applied by DataService.BoostEffect.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local GamepassService = {}

local function notify(player: Player, message: string)
	Remotes.Event("Notification"):FireClient(player, message)
end

-- Asks Roblox which passes this player already owns.
local function loadOwned(player: Player)
	for _, pass in Constants.GAMEPASSES do
		if pass.passId > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.passId)
			end)
			if ok and owns == true then
				DataService.SetPass(player, pass.id, true)
			elseif not ok then
				warn("[GamepassService] Ownership check failed for", player.Name, pass.id, owns)
			end
		end
	end
end

local function buy(player: Player, passKey: string)
	local pass = Constants.GamePass(passKey)
	if not pass then
		return
	end
	if DataService.HasPass(player, pass.id) then
		notify(player, "You already own " .. pass.name)
		return
	end
	if pass.passId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, pass.passId)
	elseif RunService:IsStudio() then
		-- No real pass behind it yet: let Studio testing switch it on for free.
		DataService.SetPass(player, pass.id, true)
		notify(player, "Studio test: " .. pass.name .. " switched on")
	else
		notify(player, pass.name .. " is not on sale yet")
	end
end

function GamepassService.Init()
	Remotes.Event("BuyGamepass").OnServerEvent:Connect(function(player, passKey)
		if typeof(passKey) ~= "string" then
			return
		end
		buy(player, passKey)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		local pass = Constants.GamePassByPassId(passId)
		if pass then
			DataService.SetPass(player, pass.id, true)
			notify(player, "Thank you! " .. pass.name .. " is yours")
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadOwned, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		DataService.ClearPasses(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadOwned, player)
	end
end

return GamepassService
