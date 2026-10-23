--!strict
--[[
	Server entry point. Initializes remotes and all services.
	Parent: ServerScriptService.ConvoyApocalypse (Script)
	Sibling ModuleScripts: DataService, VehicleFactory, ConvoyRunService, GarageService, TradeService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Remotes = require(Shared:WaitForChild("Remotes"))
Remotes.Init()

local root = script.Parent

-- The art import loads meshes over the network, which is slower on a live
-- server than in Studio. The game starts without it rather than wait forever.
local ART_TIMEOUT = 12

local WorldTheme = require(root:WaitForChild("WorldTheme"))
WorldTheme.Apply()
print("[Bootstrap] world theme applied")

-- Build the Blender kit before anything asks ArtKit for a prop.
local ArtImporter = require(root:WaitForChild("ArtImporter"))
local artDone = false
task.spawn(function()
	local ok, err = pcall(ArtImporter.Build)
	if not ok then
		warn("[Bootstrap] art import failed, continuing without it:", err)
	end
	artDone = true
end)
local waited = 0
while not artDone and waited < ART_TIMEOUT do
	task.wait(0.25)
	waited += 0.25
end
if artDone then
	print("[Bootstrap] art ready")
else
	warn(string.format("[Bootstrap] art still importing after %ds; starting the game without waiting", ART_TIMEOUT))
end

local DataService = require(root:WaitForChild("DataService"))
local ConvoyRunService = require(root:WaitForChild("ConvoyRunService"))
local GarageService = require(root:WaitForChild("GarageService"))
local TradeService = require(root:WaitForChild("TradeService"))
local GamepassService = require(root:WaitForChild("GamepassService"))
local ProgressService = require(root:WaitForChild("ProgressService"))
local LeaderboardService = require(root:WaitForChild("LeaderboardService"))

-- Data first; the rest each start on their own, so one failing service is
-- reported in the log instead of silently stopping the others.
DataService.Init()
print("[Bootstrap] data ready")

local function start(name: string, init: () -> ())
	local ok, err = pcall(init)
	if ok then
		print("[Bootstrap] " .. name .. " ready")
	else
		warn("[Bootstrap] " .. name .. " failed to start:", err)
	end
end

start("runs", ConvoyRunService.Init)
start("garages", GarageService.Init)
start("trading", TradeService.Init)
start("gamepasses", GamepassService.Init)
start("progress", ProgressService.Init)
start("leaderboards", LeaderboardService.Init)

print("[ConvoyApocalypse] Server ready")
