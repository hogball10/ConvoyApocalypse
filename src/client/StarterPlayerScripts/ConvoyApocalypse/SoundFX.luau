--!strict
--[[
	Sound for the whole game, played locally on each client: menu and run music,
	an engine that follows the car's speed, gunfire, explosions, groaning zombies
	and pickup chimes. Everything goes through one SoundGroup, so the speaker
	button in the corner mutes it all.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIUtil = require(script.Parent:WaitForChild("UIUtil"))

local player = Players.LocalPlayer

local SoundFX = {}

-- Free Creator Store / Roblox audio. Each entry: asset id, base volume.
local LIBRARY = {
	engine = { id = 80317022777602, volume = 0.3 },
	gun = { id = 88311346538102, volume = 0.18 },
	boom = { id = 140278004623742, volume = 0.5 },
	groan = { id = 109819443674858, volume = 0.3 },
	coin = { id = 76833399557686, volume = 0.5 },
	runMusic = { id = 9043276655, volume = 0.22 },
	garageMusic = { id = 9038595616, volume = 0.14 },
}

local group: SoundGroup? = nil
local looped: { [string]: Sound } = {}
local running = false
local runId = ""
local lastGun = 0
local lastGroan = 0
local muted = false

local function make(name: string, loop: boolean): Sound
	local entry = LIBRARY[name]
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. entry.id
	sound.Volume = entry.volume
	sound.Looped = loop
	sound.SoundGroup = group
	sound.Parent = SoundService
	return sound
end

-- A short effect; several can overlap.
function SoundFX.Play(name: string, pitch: number?, volumeScale: number?)
	local entry = LIBRARY[name]
	if not entry or muted then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. entry.id
	sound.Volume = entry.volume * (volumeScale or 1)
	sound.PlaybackSpeed = pitch or 1
	sound.SoundGroup = group
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function setMusic(which: string?)
	for _, name in { "runMusic", "garageMusic" } do
		local sound = looped[name]
		if sound then
			if name == which then
				if not sound.IsPlaying then
					sound:Play()
				end
			else
				sound:Stop()
			end
		end
	end
end

local function myVehicle(): Model?
	local world = Workspace:FindFirstChild("ConvoyWorld")
	local folder = world and world:FindFirstChild("Vehicles_" .. runId)
	local vehicle = folder and folder:FindFirstChild("Vehicle_" .. player.Name)
	return if vehicle and vehicle:IsA("Model") then vehicle else nil
end

local function startRun(state: any)
	running = true
	runId = state.runId or ""
	setMusic("runMusic")
	local engine = looped.engine
	if engine and not engine.IsPlaying then
		engine:Play()
	end
end

local function stopRun()
	running = false
	local engine = looped.engine
	if engine then
		engine:Stop()
	end
	setMusic("garageMusic")
end

local function onRunState(state: any)
	if state.ended or state.active == false then
		if running then
			stopRun()
		end
	elseif not running then
		startRun(state)
	end
end

local function onWorldChild(child: Instance)
	if not running or muted then
		return
	end
	-- Tracers and bolts are the neon bars the server drops into the workspace.
	if child:IsA("Part") and child.Material == Enum.Material.Neon and child.Anchored and child.Shape == Enum.PartType.Block and not child.CanCollide then
		local now = os.clock()
		if now - lastGun > 0.09 then
			lastGun = now
			SoundFX.Play("gun", 0.9 + math.random() * 0.25)
		end
	elseif child:IsA("Explosion") then
		SoundFX.Play("boom", 0.9 + math.random() * 0.2)
	end
end

local function onPickupRemoved(descendant: Instance)
	if running and descendant:IsA("BasePart") and string.sub(descendant.Name, 1, 7) == "Pickup_" then
		local vehicle = myVehicle()
		local body = vehicle and vehicle.PrimaryPart
		if body and (body.Position - descendant.Position).Magnitude < 22 then
			SoundFX.Play("coin", 1 + math.random() * 0.15)
		end
	end
end

local function buildToggle()
	local gui = UIUtil.ScreenGui("SoundToggle", player:WaitForChild("PlayerGui"))
	gui.DisplayOrder = 30
	local button = UIUtil.Button({
		Name = "Toggle",
		Text = "SOUND ON",
		Size = UDim2.fromOffset(104, 28),
		Position = UDim2.new(0, 12, 0, 12),
		BackgroundColor3 = UIUtil.Colors.PanelAlt,
		Parent = gui,
	})
	button.MouseButton1Click:Connect(function()
		muted = not muted
		if group then
			group.Volume = if muted then 0 else 1
		end
		button.Text = if muted then "SOUND OFF" else "SOUND ON"
	end)
end

function SoundFX.Init()
	local master = Instance.new("SoundGroup")
	master.Name = "ConvoyMaster"
	master.Volume = 1
	master.Parent = SoundService
	group = master

	looped.engine = make("engine", true)
	looped.runMusic = make("runMusic", true)
	looped.garageMusic = make("garageMusic", true)
	setMusic("garageMusic")
	buildToggle()

	Remotes.Event("RunState").OnClientEvent:Connect(onRunState)
	Remotes.Event("EnterGarage").OnClientEvent:Connect(function()
		if running then
			stopRun()
		else
			setMusic("garageMusic")
		end
	end)

	Workspace.ChildAdded:Connect(onWorldChild)
	task.spawn(function()
		local world = Workspace:WaitForChild("ConvoyWorld")
		world.DescendantRemoving:Connect(onPickupRemoved)
	end)

	-- The engine's pitch follows the car's speed; zombies groan now and then.
	RunService.Heartbeat:Connect(function()
		if not running then
			return
		end
		local engine = looped.engine
		local vehicle = myVehicle()
		local body = vehicle and vehicle.PrimaryPart
		if engine and body then
			local speed = body.AssemblyLinearVelocity.Magnitude
			engine.PlaybackSpeed = 0.7 + math.clamp(speed / 70, 0, 1.1)
			engine.Volume = LIBRARY.engine.volume * (if speed < 2 then 0.5 else 1)
		end
		local now = os.clock()
		if now - lastGroan > 3 + math.random() * 3 then
			lastGroan = now
			SoundFX.Play("groan", 0.8 + math.random() * 0.4)
		end
	end)
end

return SoundFX
