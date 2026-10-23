--!strict
--[[
	Global lighting, atmosphere, and sky for the apocalypse look.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local WorldTheme = {}

-- Always midday. The clock never moves and no biome changes it, so every
-- player sees the same bright sky wherever they are in a run.
local DAYLIGHT_CLOCK = 13

local DAY_AMBIENT = Color3.fromRGB(120, 118, 112)

function WorldTheme.Apply()
	Lighting.Brightness = 2.4
	Lighting.Ambient = DAY_AMBIENT
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 135, 125)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 235, 200)
	Lighting.ColorShift_Bottom = Color3.fromRGB(60, 55, 50)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.ClockTime = DAYLIGHT_CLOCK
	Lighting.GeographicLatitude = 25
	Lighting.ExposureCompensation = 0.15
	Lighting.FogColor = Color3.fromRGB(190, 175, 150)
	Lighting.FogStart = 120
	Lighting.FogEnd = 650

	for _, name in { "Atmosphere", "Sky", "Bloom", "ColorCorrection", "SunRays", "DepthOfField" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "Atmosphere"
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.3
	atmosphere.Color = Color3.fromRGB(190, 190, 200)
	atmosphere.Decay = Color3.fromRGB(150, 130, 110)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 0.9
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.Name = "Sky"
	sky.CelestialBodiesShown = true
	sky.StarCount = 2000
	sky.SunAngularSize = 21
	sky.MoonAngularSize = 9
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = 0.45
	bloom.Size = 28
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ColorCorrection"
	cc.Brightness = 0.02
	cc.Contrast = 0.18
	cc.Saturation = 0.1
	cc.TintColor = Color3.fromRGB(255, 248, 238)
	cc.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "SunRays"
	sunRays.Intensity = 0.05
	sunRays.Spread = 0.6
	sunRays.Parent = Lighting

end

-- Biomes differ by fog, haze and colour grade only; the time of day stays put.
-- The change eases in so crossing a biome border is not a sudden pop.
local BIOME_LOOK = {
	RuinedCity = { fog = Color3.fromRGB(150, 155, 165), fogEnd = 520, tint = Color3.fromRGB(235, 240, 250), haze = Color3.fromRGB(165, 172, 185), saturation = -0.05 },
	Desert = { fog = Color3.fromRGB(225, 195, 140), fogEnd = 700, tint = Color3.fromRGB(255, 238, 205), haze = Color3.fromRGB(235, 200, 150), saturation = 0.15 },
	SnowyMountains = { fog = Color3.fromRGB(200, 215, 230), fogEnd = 580, tint = Color3.fromRGB(235, 245, 255), haze = Color3.fromRGB(205, 220, 238), saturation = 0.05 },
	WastelandHighways = { fog = Color3.fromRGB(190, 175, 150), fogEnd = 650, tint = Color3.fromRGB(255, 244, 228), haze = Color3.fromRGB(195, 185, 175), saturation = 0.1 },
}

function WorldTheme.SetBiome(biome: string)
	local look = BIOME_LOOK[biome] or BIOME_LOOK.WastelandHighways
	local info = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, info, { FogColor = look.fog, FogEnd = look.fogEnd }):Play()
	local cc = Lighting:FindFirstChild("ColorCorrection")
	if cc then
		TweenService:Create(cc, info, { TintColor = look.tint, Saturation = look.saturation }):Play()
	end
	local atmosphere = Lighting:FindFirstChild("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, { Color = look.haze }):Play()
	end
end

return WorldTheme
