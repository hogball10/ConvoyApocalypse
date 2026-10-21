--!strict
--[[
	Global lighting, atmosphere, and sky for the apocalypse look.
]]

local Lighting = game:GetService("Lighting")

local WorldTheme = {}

function WorldTheme.Apply()
	Lighting.Brightness = 1.6
	Lighting.Ambient = Color3.fromRGB(55, 48, 42)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 58, 48)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 160, 90)
	Lighting.ColorShift_Bottom = Color3.fromRGB(40, 30, 25)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.ClockTime = 17.4
	Lighting.GeographicLatitude = 25
	Lighting.ExposureCompensation = 0.15
	Lighting.FogColor = Color3.fromRGB(120, 95, 70)
	Lighting.FogStart = 80
	Lighting.FogEnd = 520

	for _, name in { "Atmosphere", "Sky", "Bloom", "ColorCorrection", "SunRays", "DepthOfField" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "Atmosphere"
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(160, 120, 90)
	atmosphere.Decay = Color3.fromRGB(90, 55, 35)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.8
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
	cc.Saturation = 0.05
	cc.TintColor = Color3.fromRGB(255, 235, 210)
	cc.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "SunRays"
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.6
	sunRays.Parent = Lighting

end

function WorldTheme.SetBiome(biome: string)
	if biome == "RuinedCity" then
		Lighting.FogColor = Color3.fromRGB(70, 75, 85)
		Lighting.FogEnd = 420
		Lighting.ClockTime = 18.2
	elseif biome == "Desert" then
		Lighting.FogColor = Color3.fromRGB(210, 180, 120)
		Lighting.FogEnd = 600
		Lighting.ClockTime = 15.5
	elseif biome == "SnowyMountains" then
		Lighting.FogColor = Color3.fromRGB(180, 200, 220)
		Lighting.FogEnd = 480
		Lighting.ClockTime = 14
		Lighting.Ambient = Color3.fromRGB(70, 80, 95)
	else -- WastelandHighways
		Lighting.FogColor = Color3.fromRGB(120, 95, 70)
		Lighting.FogEnd = 520
		Lighting.ClockTime = 17.4
		Lighting.Ambient = Color3.fromRGB(55, 48, 42)
	end
end

return WorldTheme
