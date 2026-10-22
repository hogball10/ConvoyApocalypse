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

local WorldTheme = require(root:WaitForChild("WorldTheme"))
WorldTheme.Apply()

-- Build the Blender kit before anything asks ArtKit for a prop.
local ArtImporter = require(root:WaitForChild("ArtImporter"))
ArtImporter.Build()

local DataService = require(root:WaitForChild("DataService"))
local ConvoyRunService = require(root:WaitForChild("ConvoyRunService"))
local GarageService = require(root:WaitForChild("GarageService"))
local TradeService = require(root:WaitForChild("TradeService"))
local GamepassService = require(root:WaitForChild("GamepassService"))

DataService.Init()
ConvoyRunService.Init()
GarageService.Init()
TradeService.Init()
GamepassService.Init()

print("[ConvoyApocalypse] Server ready")
