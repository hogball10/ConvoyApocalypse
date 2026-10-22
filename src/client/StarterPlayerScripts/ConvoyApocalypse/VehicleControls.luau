--!strict
--[[
	Drives the run car. The server owns the car's physics, so the seat's own
	throttle/steer input is not reliably delivered to it; send what the player is
	pressing (WASD, arrows, gamepad stick or mobile thumbstick) explicitly.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local SEND_INTERVAL = 1 / 20
-- Resend even if nothing changed, so the server never mistakes a held key for
-- a dropped connection.
local KEEPALIVE = 0.25

local VehicleControls = {}
VehicleControls._active = false
VehicleControls._controls = nil :: any
VehicleControls._lastThrottle = 0
VehicleControls._lastSteer = 0
VehicleControls._lastSent = 0

local function keyAxis(positive: { Enum.KeyCode }, negative: { Enum.KeyCode }): number
	local value = 0
	for _, key in positive do
		if UserInputService:IsKeyDown(key) then
			value += 1
			break
		end
	end
	for _, key in negative do
		if UserInputService:IsKeyDown(key) then
			value -= 1
			break
		end
	end
	return value
end

-- (throttle, steer), each in -1..1. Forward and right are positive.
local function readInput(): (number, number)
	if UserInputService:GetFocusedTextBox() then
		return 0, 0
	end
	local throttle = keyAxis({ Enum.KeyCode.W, Enum.KeyCode.Up }, { Enum.KeyCode.S, Enum.KeyCode.Down })
	local steer = keyAxis({ Enum.KeyCode.D, Enum.KeyCode.Right }, { Enum.KeyCode.A, Enum.KeyCode.Left })

	-- The default controls also cover gamepad and touch.
	if VehicleControls._controls == nil then
		local ok, controls = pcall(function()
			local scripts = player:FindFirstChild("PlayerScripts")
			local module = scripts and scripts:FindFirstChild("PlayerModule")
			return module and require(module):GetControls()
		end)
		VehicleControls._controls = if ok and controls then controls else false
	end
	local controls = VehicleControls._controls
	if controls then
		local ok, move = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(move) == "Vector3" then
			if throttle == 0 and math.abs(move.Z) > 0.05 then
				throttle = -move.Z
			end
			if steer == 0 and math.abs(move.X) > 0.05 then
				steer = move.X
			end
		end
	end
	return math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1)
end

function VehicleControls.SetActive(active: boolean)
	VehicleControls._active = active
	if not active then
		VehicleControls._lastThrottle = 0
		VehicleControls._lastSteer = 0
	end
end

function VehicleControls.Init()
	local remote = Remotes.Event("VehicleInput")
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		if not VehicleControls._active then
			return
		end
		accum += dt
		if accum < SEND_INTERVAL then
			return
		end
		accum = 0
		local throttle, steer = readInput()
		local now = os.clock()
		local changed = throttle ~= VehicleControls._lastThrottle or steer ~= VehicleControls._lastSteer
		if changed or now - VehicleControls._lastSent >= KEEPALIVE then
			VehicleControls._lastThrottle = throttle
			VehicleControls._lastSteer = steer
			VehicleControls._lastSent = now
			remote:FireServer(throttle, steer)
		end
	end)
end

return VehicleControls
