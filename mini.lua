--========================================================
-- DucLuongg Hybrid Shader™ | Xi Măng Reflect Edition (Cinematic)
-- Combined: FixLag optimizations + Lightweight Cinematic Shader
-- - Giữ đảo/quái/UI
-- - Giảm particle/trail/explosion heavy effects
-- - Fake soft shadow cho local player
-- - Dynamic day/night tint + auto-optimize khi FPS tụt
--========================================================

-- =========================
-- CONFIG (SỬA TẠI ĐẦU FILE NẾU MUỐN)
-- =========================
local CONFIG = {
    MODE = "Cinematic",                 -- info only
    SHOW_INTRO_NOTIFY = true,           -- notify khi load
    INTRO_DURATION = 5,                 -- giây
    AUTO_DAYNIGHT = true,               -- thay đổi tint theo ClockTime
    ENABLE_SKILL_REDUCTION = true,      -- tắt particle/trail/explosion (không ảnh hưởng nhân vật người chơi)
    AUTO_OPTIMIZE = true,               -- bật auto giảm chất lượng khi FPS thấp
    OPTIMIZE_THRESHOLD = 5,            -- nếu FPS trung bình < threshold => optimize
    OPTIMIZE_CHECK_INTERVAL = 10.0,      -- lấy sample FPS mỗi interval giây
    MIN_BLOOM = 0.2,                    -- bloom khi optimize
    NORMAL_BLOOM = 0.8,                 -- bloom mặc định
    MIN_SUN = 0.06,                     -- sunrays min
    NORMAL_SUN = 0.20,                  -- sunrays normal
    LOCK_FPS = 120,                     -- setfpscap nếu exploit hỗ trợ (nil để bỏ)
    SAFE_DISABLE_FOR_CHARACTERS = true, -- không tắt effects dính vào character của players
}
-- =========================

-- ===== services & safety
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local MaterialService = game:GetService("MaterialService")

local LocalPlayer = Players.LocalPlayer

local function safe_pcall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        -- minimal logging
        pcall(function() if CONFIG.SHOW_INTRO_NOTIFY then warn("HybridShader error: "..tostring(err)) end end)
    end
    return ok, err
end

local function Notify(text, duration)
    if not CONFIG.SHOW_INTRO_NOTIFY then return end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "DucLuongg Cinematic Shader™",
            Text = text or "",
            Duration = duration or 4
        })
    end)
end

-- Remove previously created LVM effects to avoid duplicates
safe_pcall(function()
    for _, v in pairs(Lighting:GetChildren()) do
        if v.Name:match("^DucLuongg_Hybrid") or v.Name:match("^LVM") then
            if v:IsA("PostEffect") then pcall(function() v:Destroy() end) end
        end
    end
end)

-- =========================
-- CREATE LIGHTING EFFECTS (lightweight)
-- =========================
-- ColorCorrection
local CC = Instance.new("ColorCorrectionEffect")
CC.Name = "DucLuongg_Hybrid_Color"
CC.Parent = Lighting
CC.Saturation = 0.18
CC.Contrast = 0.22
CC.Brightness = 0.04
CC.TintColor = Color3.fromRGB(255, 230, 195) -- warm default

-- Bloom (lightweight)
local Bloom = Instance.new("BloomEffect")
Bloom.Name = "DucLuongg_Hybrid_Bloom"
Bloom.Parent = Lighting
Bloom.Intensity = CONFIG.NORMAL_BLOOM
Bloom.Size = 45
Bloom.Threshold = 0.78

-- SunRays (soft)
local SunRays = Instance.new("SunRaysEffect")
SunRays.Name = "DucLuongg_Hybrid_Sun"
SunRays.Parent = Lighting
SunRays.Intensity = CONFIG.NORMAL_SUN
SunRays.Spread = 0.9

-- Soft Fog settings (not heavy)
local ORIGINAL_FOG_START = Lighting.FogStart or 0
local ORIGINAL_FOG_END = Lighting.FogEnd or 100000
local function applyCinematicFog()
    Lighting.FogStart = 200
    Lighting.FogEnd = 2000
    Lighting.FogColor = Color3.fromRGB(210, 210, 210)
end
applyCinematicFog()

-- Ambient default
local originalAmbient = Lighting.Ambient
local originalOutdoor = Lighting.OutdoorAmbient
local originalBrightness = Lighting.Brightness

-- =========================
-- Fake soft shadow (local only, nhẹ)
-- =========================
local function createLocalShadow(character)
    if not character or not character.PrimaryPart then return end
    if character:FindFirstChild("DucLuongg_SoftShadow") then return end
    local hrp = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
    if not hrp then return end

    local shadow = Instance.new("Part")
    shadow.Name = "DucLuongg_SoftShadow"
    shadow.Anchored = true
    shadow.CanCollide = false
    shadow.Size = Vector3.new(4, 0.05, 4)
    shadow.Material = Enum.Material.SmoothPlastic
    shadow.Transparency = 0.7
    shadow.CastShadow = false
    shadow.Color = Color3.fromRGB(10,10,10)
    shadow.Parent = Workspace -- keep in workspace

    -- update position cheaply (not weld, avoid heavy)
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not shadow or not hrp or not hrp.Parent then
            if conn then conn:Disconnect() end
            pcall(function() if shadow then shadow:Destroy() end end)
            return
        end
        -- place a bit below feet using raycast to ground for nicer effect
        local origin = hrp.Position
        local down = Vector3.new(0, -10, 0)
        local ray = Ray.new(origin, down)
        local hit, pos = Workspace:FindPartOnRayWithIgnoreList(ray, {character})
        if hit and pos then
            shadow.Size = Vector3.new(4, 0.05, 4)
            shadow.CFrame = CFrame.new(pos) * CFrame.Angles(-math.pi/2,0,0)
            shadow.Transparency = 0.6
        else
            -- default under hrp
            shadow.CFrame = hrp.CFrame * CFrame.new(0, -3.2, 0)
            shadow.Transparency = 0.85
        end
    end)
end

-- create shadow only for local player to save resources
if LocalPlayer and LocalPlayer.Character then
    safe_pcall(createLocalShadow, LocalPlayer.Character)
end
Players.PlayerAdded:Connect(function(plr)
    if plr == LocalPlayer then
        plr.CharacterAdded:Connect(function(char) safe_pcall(createLocalShadow, char) end)
    end
end)

-- =========================
-- Skill effect reduction (non-destructive)
-- =========================
local function isDescendantOfAPlayer(inst)
    for _,p in pairs(Players:GetPlayers()) do
        if p.Character and inst:IsDescendantOf(p.Character) then return true end
    end
    return false
end

local function reduceSkillEffectsInstance(inst)
    -- do NOT alter UI (PlayerGui/CoreGui) or toolbackpack items
    if not inst or not inst.Parent then return end
    if inst:IsDescendantOf(game:GetService("CoreGui")) then return end

    -- Particle-like
    if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
        -- keep if attached to player characters (preserve personal VFX)
        if CONFIG.SAFE_DISABLE_FOR_CHARACTERS and isDescendantOfAPlayer(inst) then
            return
        end
        pcall(function() inst.Enabled = false end)
        -- also lower rates/lifetimes if available
        pcall(function()
            if inst:IsA("ParticleEmitter") then
                inst.Rate = 0
                inst.Lifetime = NumberRange.new(0.05)
                inst.Speed = NumberRange.new(0)
            end
            if inst:IsA("Trail") then
                inst.Enabled = false
            end
        end)
    elseif inst:IsA("Explosion") then
        pcall(function()
            inst.BlastPressure = 0
            inst.BlastRadius = 0
            inst.Visible = false
        end)
    end
end

-- apply reduction to existing workspace descendants (careful)
if CONFIG.ENABLE_SKILL_REDUCTION then
    for _,v in pairs(Workspace:GetDescendants()) do
        safe_pcall(reduceSkillEffectsInstance, v)
    end
    -- connect future
    Workspace.DescendantAdded:Connect(function(v)
        task.wait(0.06)
        safe_pcall(reduceSkillEffectsInstance, v)
    end)
    Notify("Skill effects reduced (non-destructive).", 4)
end

-- =========================
-- Auto day/night + dynamic tint
-- =========================
local function applyDayTint(clock)
    -- clock: 0..24
    if clock >= 6 and clock < 12 then
        -- morning: soft warm
        CC.TintColor = Color3.fromRGB(255, 240, 220)
        Bloom.Intensity = CONFIG.NORMAL_BLOOM * 0.9
        SunRays.Intensity = CONFIG.NORMAL_SUN * 0.9
        Lighting.Brightness = math.clamp(originalBrightness * 1.0, 0.5, 3)
        Lighting.Ambient = Color3.fromRGB(200, 200, 200)
    elseif clock >= 12 and clock < 17 then
        -- noon: neutral
        CC.TintColor = Color3.fromRGB(255, 245, 235)
        Bloom.Intensity = CONFIG.NORMAL_BLOOM
        SunRays.Intensity = CONFIG.NORMAL_SUN
        Lighting.Brightness = math.clamp(originalBrightness * 1.05, 0.5, 3)
        Lighting.Ambient = Color3.fromRGB(220, 220, 220)
    elseif clock >= 17 and clock < 20 then
        -- golden hour: cinematic warm
        CC.TintColor = Color3.fromRGB(255, 225, 180)
        Bloom.Intensity = CONFIG.NORMAL_BLOOM * 1.05
        SunRays.Intensity = CONFIG.NORMAL_SUN * 1.1
        Lighting.Brightness = math.clamp(originalBrightness * 0.95, 0.3, 2)
        Lighting.Ambient = Color3.fromRGB(200, 185, 160)
    else
        -- night: cool tone
        CC.TintColor = Color3.fromRGB(180, 200, 255)
        Bloom.Intensity = CONFIG.MIN_BLOOM or 0.2
        SunRays.Intensity = CONFIG.MIN_SUN or 0.05
        Lighting.Brightness = math.clamp(originalBrightness * 0.45, 0.1, 1.5)
        Lighting.Ambient = Color3.fromRGB(120, 140, 160)
    end
end

if CONFIG.AUTO_DAYNIGHT then
    -- initial
    safe_pcall(function() applyDayTint(Lighting.ClockTime) end)
    -- update per Heartbeat (cheap)
    RunService.Heartbeat:Connect(function()
        -- only sample occasionally to save perf
        local ct = Lighting.ClockTime
        applyDayTint(ct)
    end)
end

-- =========================
-- Auto Optimize (FPS-aware)
-- =========================
local fps_samples = {}
local sample_time = 0
local function sampleFPS(dt)
    sample_time = sample_time + dt
    fps_samples[#fps_samples + 1] = 1 / math.max(dt, 1/120)
    if sample_time >= CONFIG.OPTIMIZE_CHECK_INTERVAL then
        -- compute avg
        local sum = 0
        for _,v in pairs(fps_samples) do sum = sum + v end
        local avg = sum / math.max(#fps_samples,1)
        fps_samples = {}
        sample_time = 0
        return avg
    end
    return nil
end

local optimized = false
local function applyOptimize(state)
    if state == optimized then return end
    optimized = state
    if state then
        -- enable aggressive low-quality settings
        pcall(function()
            Bloom.Intensity = CONFIG.MIN_BLOOM
            SunRays.Intensity = CONFIG.MIN_SUN
            CC.Saturation = 0.05
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            -- reduce render fidelity for meshparts
            for _, mp in pairs(Workspace:GetDescendants()) do
                if mp:IsA("MeshPart") then
                    pcall(function() mp.RenderFidelity = Enum.RenderFidelity.Performance end)
                end
            end
            -- disable global particle emitters (non-character) to save CPU/GPU
            for _,v in pairs(Workspace:GetDescendants()) do
                if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Sparkles") then
                    if CONFIG.SAFE_DISABLE_FOR_CHARACTERS and isDescendantOfAPlayer(v) then
                        -- skip
                    else
                        pcall(function() v.Enabled = false end)
                    end
                end
            end
            -- setfpscap if available
            if CONFIG.LOCK_FPS and type(CONFIG.LOCK_FPS)=="number" and setfpscap then
                pcall(function() setfpscap(CONFIG.LOCK_FPS) end)
            end
        end)
        Notify("AutoOptimize: Low FPS detected — reducing quality to keep stable.", 4)
    else
        -- restore reasonable defaults (not force too heavy)
        pcall(function()
            Bloom.Intensity = CONFIG.NORMAL_BLOOM
            SunRays.Intensity = CONFIG.NORMAL_SUN
            CC.Saturation = 0.18
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level03
            for _, mp in pairs(Workspace:GetDescendants()) do
                if mp:IsA("MeshPart") then
                    pcall(function() mp.RenderFidelity = Enum.RenderFidelity.Automatic end)
                end
            end
            -- re-enable particle emitters that are community-owned? we will attempt safe re-enable for non-sustaining emitters
            for _,v in pairs(Workspace:GetDescendants()) do
                if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Sparkles") then
                    if CONFIG.SAFE_DISABLE_FOR_CHARACTERS and isDescendantOfAPlayer(v) then
                        -- it was never disabled
                    else
                        pcall(function() v.Enabled = true end)
                    end
                end
            end
            if CONFIG.LOCK_FPS and type(CONFIG.LOCK_FPS)=="number" and setfpscap then
                pcall(function() setfpscap(CONFIG.LOCK_FPS) end)
            end
        end)
        Notify("AutoOptimize: Restored visuals.", 3)
    end
end

-- sampling via RenderStepped (cheap math)
local lastTick = tick()
RunService.RenderStepped:Connect(function(dt)
    local avg = sampleFPS(dt)
    if avg then
        if CONFIG.AUTO_OPTIMIZE then
            if avg < CONFIG.OPTIMIZE_THRESHOLD then
                applyOptimize(true)
            else
                applyOptimize(false)
            end
        end
    end
end)

-- =========================
-- final attach: small protective scan (non-destructive)
-- =========================
-- apply lightweight changes across workspace that are safe and reduce cost
local function safeGlobalTweak(inst)
    if not inst or not inst.Parent then return end
    -- skip UI
    if inst:IsDescendantOf(LocalPlayer:FindFirstChild("PlayerGui") or {}) then return end
    if inst:IsA("MeshPart") then
        pcall(function() inst.RenderFidelity = Enum.RenderFidelity.Performance end)
    elseif inst:IsA("BasePart") and not inst:IsA("MeshPart") then
        pcall(function() inst.Material = Enum.Material.Plastic; inst.Reflectance = 0 end)
    elseif inst:IsA("Decal") or inst:IsA("Texture") then
        -- lighten huge textures by decreasing transparency a bit? better to not touch
    end
end

for _,v in pairs(Workspace:GetDescendants()) do
    safe_pcall(safeGlobalTweak, v)
end
Workspace.DescendantAdded:Connect(function(v) task.wait(0.05); safe_pcall(safeGlobalTweak, v) end)

-- =========================
-- OPTIONAL: Lock FPS on start if supported
-- =========================
if CONFIG.LOCK_FPS and type(CONFIG.LOCK_FPS) == "number" and setfpscap then
    pcall(function() setfpscap(CONFIG.LOCK_FPS) end)
end

-- =========================
-- Notify intro + final message
-- =========================
if CONFIG.SHOW_INTRO_NOTIFY then
    Notify("🎬 DucLuongg Cinematic Shader™ Activated", CONFIG.INTRO_DURATION)
    -- also show small follow-up after intro
    delay(CONFIG.INTRO_DURATION + 0.1, function()
        Notify("Xi Măng Reflect v2 — cinematic + optimized", 4)
    end)
end

print("✅ DucLuongg Hybrid Shader loaded. Mode:", CONFIG.MODE)

-- End of script
