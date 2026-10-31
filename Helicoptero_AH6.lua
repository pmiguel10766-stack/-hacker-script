--[[
    Helicoptero_AH6_Tradicional.lua  (v1.2 - Ajustes visuais, painel e cockpit otimizados)
    AH-6 Little Bird armado | física tradicional | HUD tátil (mobile/PC)
    Executar: loadstring(game:HttpGet("SEU_LINK"))()  ou colar direto no Delta
]]

-- ============================================================
-- 0. SERVIÇOS E LIMPEZA DE EXECUÇÕES ANTERIORES
-- ============================================================
local Players   = game:GetService("Players")
local RunService= game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

if _G.AH6_Cleanup then pcall(_G.AH6_Cleanup) end

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local char   = player.Character or player.CharacterAdded:Wait()
local hum    = char:WaitForChild("Humanoid")
local hrp    = char:WaitForChild("HumanoidRootPart")

-- ============================================================
-- 1. CONFIGURAÇÃO (ajuste à vontade)
-- ============================================================
local CFG = {
    MAX_SPEED   = 90,    -- velocidade horizontal máx (studs/s)
    CLIMB       = 28,    -- velocidade vertical (studs/s)
    YAW_RATE    = 1.5,   -- rotação do rotor de cauda (rad/s)
    TILT_P      = 0.32,  -- inclinação do nariz (rad)
    TILT_R      = 0.30,  -- inclinação lateral (rad)
    RPM_UP      = 22,    -- % de RPM ganho por segundo ao ligar
    RPM_DOWN    = 12,    -- % de RPM perdido por segundo ao desligar
    FIRE_RATE   = 16,    -- tiros por segundo (somando as 2 miniguns)
    RANGE       = 500,   -- alcance dos tiros
    SPREAD      = 0.012, -- dispersão
    RADAR_RANGE = 300,   -- alcance do radar (studs)
    COCKPIT_CAM = CFrame.new(0, 2.3, 1.2) * CFrame.Angles(-0.05, 0, 0), -- cockpit refinado e limpo
}

local conns = {}
local function connect(sig, fn)
    local c = sig:Connect(fn)
    conns[#conns + 1] = c
    return c
end

-- ============================================================
-- 2. CONSTRUÇÃO PROCEDURAL DO AH-6
-- ============================================================
local OLIVE   = Color3.fromRGB(64, 70, 54)
local DARK    = Color3.fromRGB(28, 30, 28)
local GLASS   = Color3.fromRGB(130, 175, 205)
local METAL   = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic

local model = Instance.new("Model")
model.Name = "AH6_LittleBird"
model.Parent = Workspace

local root -- peça raiz (piso da cabine)

local function mk(name, size, off, color, mat, transp, collide, shape)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.Color = color
    p.Material = mat or PLASTIC
    p.Transparency = transp or 0
    p.CanCollide = collide or false
    p.CanQuery = false
    p.CanTouch = false
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    if shape then p.Shape = shape end
    if root then
        p.Massless = true
        p.CFrame = root.CFrame * off
    else
        p.CFrame = off
    end
    p.Parent = model
    if root then
        local w = Instance.new("WeldConstraint")
        w.Part0 = root
        w.Part1 = p
        w.Parent = p
    end
    return p
end

local look  = hrp.CFrame.LookVector
local yaw0  = math.atan2(-look.X, -look.Z)
local ahead = hrp.Position + Vector3.new(look.X, 0, look.Z).Unit * 22

local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Exclude
rp.FilterDescendantsInstances = { char, model }
rp.IgnoreWater = true

local g  = Workspace:Raycast(ahead + Vector3.new(0, 60, 0), Vector3.new(0, -300, 0), rp)
local gy = g and g.Position.Y or (hrp.Position.Y - 3)
local spawnCF = CFrame.new(ahead.X, gy + 3.9, ahead.Z) * CFrame.Angles(0, yaw0, 0)

root = mk("Piso", Vector3.new(5, 0.4, 7), spawnCF, OLIVE, METAL, 0, true)
root.Anchored = true

-- --- Cabine ---
mk("SoleiraE",  Vector3.new(0.3, 0.8, 6), CFrame.new(-2.4, -1.2, 0), OLIVE, METAL)
mk("SoleiraD",  Vector3.new(0.3, 0.8, 6), CFrame.new( 2.4, -1.2, 0), OLIVE, METAL)
mk("Antepara",  Vector3.new(5, 3, 0.3),   CFrame.new(0, 0, 3.4),     OLIVE, METAL)
mk("Teto",      Vector3.new(5, 0.3, 5),   CFrame.new(0, 2.8, 0.9),   OLIVE, METAL)
mk("Bolha",     Vector3.new(7.4, 7.4, 7.4), CFrame.new(0, 0.9, -1.5), GLASS, Enum.Material.Glass, 0.75, false, Enum.PartType.Ball)
-- Console ajustado para não tapar a visão
mk("Console",   Vector3.new(4.8, 0.4, 1.0), CFrame.new(0, -1.3, -2.2), DARK, PLASTIC)

-- --- Banco do piloto ---
local seat = mk("Banco", Vector3.new(2, 0.3, 2), CFrame.new(0, -1.2, 0.9), DARK, PLASTIC)
mk("EncostoBanco", Vector3.new(2, 2, 0.3), CFrame.new(0, -0.1, 1.9), DARK, PLASTIC)
mk("Cíclico", Vector3.new(0.2, 1.3, 0.2), CFrame.new(0, -0.9, -0.9), DARK, METAL)
mk("PunhoCíclico", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, -0.2, -0.9), DARK, PLASTIC, 0, false, Enum.PartType.Ball)

-- --- Motor, mastro e cubo ---
mk("Motor",  Vector3.new(3, 1.4, 3.6),   CFrame.new(0, 3.8, 1.4), OLIVE, METAL)
mk("Mastro", Vector3.new(0.7, 1.2, 0.7), CFrame.new(0, 4.9, 1.4), DARK, METAL)
mk("Cubo",   Vector3.new(1, 0.4, 1),     CFrame.new(0, 5.5, 1.4), DARK, METAL)

-- --- Cauda ---
mk("Transicao", Vector3.new(2.4, 2, 2),    CFrame.new(0, 1.4, 4.4),  OLIVE, METAL)
mk("Lanca",     Vector3.new(0.9, 0.9, 9),  CFrame.new(0, 1.6, 8),    OLIVE, METAL)
mk("Deriva",    Vector3.new(0.25, 3.2, 1.8), CFrame.new(0, 3.0, 12), OLIVE, METAL)
mk("Estabilizador", Vector3.new(4.4, 0.2, 1.2), CFrame.new(0, 4.6, 12), OLIVE, METAL)

-- --- Patins ---
for _, sx in ipairs({ -1, 1 }) do
    mk("Patim", Vector3.new(0.35, 0.35, 7.5), CFrame.new(sx * 2.3, -3.6, -0.2), DARK, METAL, 0, true)
    mk("SuporteF", Vector3.new(0.22, 1.95, 0.22), CFrame.new(sx * 2.3, -2.5, -1.6), DARK, METAL)
    mk("SuporteT", Vector3.new(0.22, 1.95, 0.22), CFrame.new(sx * 2.3, -2.5,  1.8), DARK, METAL)
end

-- --- Rotores ---
local spinners = {}
local function mkSpinner(name, size, pivot, localCF, axis, isTail)
    local p = mk(name, size, pivot * localCF, DARK, METAL)
    local old = p:FindFirstChildOfClass("WeldConstraint")
    if old then old:Destroy() end
    local w = Instance.new("Weld")
    w.Part0 = root
    w.Part1 = p
    w.C0 = pivot * localCF
    w.Parent = p
    spinners[#spinners + 1] = { w = w, p = p, pivot = pivot, loc = localCF, axis = axis, tail = isTail }
end

local mainPivot = CFrame.new(0, 5.8, 1.4)
for i = 0, 2 do
    mkSpinner("PaPrincipal" .. i, Vector3.new(21, 0.12, 0.8), mainPivot, CFrame.Angles(0, math.rad(60 * i), 0), "Y", false)
end
local tailPivot = CFrame.new(0.55, 2.9, 12.4)
mkSpinner("PaCauda0", Vector3.new(0.12, 3.4, 0.35), tailPivot, CFrame.new(), "X", true)
mkSpinner("PaCauda1", Vector3.new(0.12, 0.35, 3.4), tailPivot, CFrame.new(), "X", true)

-- --- Miniguns ---
local guns = {}
local function mkGun(sx)
    mk("PilarArma", Vector3.new(2.2, 0.25, 1.4), CFrame.new(sx * 3.6, -0.6, -0.6), OLIVE, METAL)
    mk("PodMinigun", Vector3.new(0.8, 0.8, 2.6), CFrame.new(sx * 4.4, -1.0, -0.9), DARK, METAL)
    local barrel = mk("CanoMinigun", Vector3.new(0.28, 0.28, 2.2), CFrame.new(sx * 4.4, -1.0, -3.2), Color3.fromRGB(70, 70, 70), METAL)

    local att = Instance.new("Attachment")
    att.Name = "Muzzle"
    att.Position = Vector3.new(0, 0, -1.15)
    att.Parent = barrel

    local flash = mk("Clarao", Vector3.new(0.9, 0.9, 0.9), CFrame.new(sx * 4.4, -1.0, -4.5), Color3.fromRGB(255, 200, 90), Enum.Material.Neon, 1, false, Enum.PartType.Ball)
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 170, 60)
    light.Range = 12
    light.Brightness = 3
    light.Enabled = false
    light.Parent = flash

    local em = Instance.new("ParticleEmitter")
    em.Rate = 0
    em.Lifetime = NumberRange.new(0.1, 0.25)
    em.Speed = NumberRange.new(10, 25)
    em.SpreadAngle = Vector2.new(25, 25)
    em.EmissionDirection = Enum.NormalId.Front
    em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
    em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
    em.Color = ColorSequence.new(Color3.fromRGB(255, 190, 70), Color3.fromRGB(120, 120, 120))
    em.LightEmission = 1
    em.Parent = att

    guns[#guns + 1] = { muzzle = att, flash = flash, light = light, em = em, off = nil }
end
mkGun(-1)
mkGun(1)

-- --- Holofote ---
local lamp = mk("Holofote", Vector3.new(0.7, 0.7, 0.9), CFrame.new(0, -2.4, -4.4), DARK, PLASTIC)
local spot = Instance.new("SpotLight")
spot.Face = Enum.NormalId.Front
spot.Range = 130
spot.Angle = 55
spot.Brightness = 4
spot.Enabled = false
spot.Parent = lamp
mk("SensorEO", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0.9, -2.4, -4.2), DARK, METAL, 0, false, Enum.PartType.Ball)

-- --- Painel de instrumentos ---
local panel = mk("PainelInstrumentos", Vector3.new(4.8, 1.3, 0.25), CFrame.new(0, -0.15, -2.1), Color3.fromRGB(18, 18, 18), PLASTIC)
local sg = Instance.new("SurfaceGui")
sg.Face = Enum.NormalId.Back
sg.CanvasSize = Vector2.new(480, 150)
sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
sg.LightInfluence = 0
sg.Brightness = 1.2
sg.Parent = panel

-- ============================================================
-- 3. FÍSICA
-- ============================================================
local att0 = Instance.new("Attachment")
att0.Parent = root

local lv = Instance.new("LinearVelocity")
lv.Attachment0 = att0
lv.MaxForce = 1e7
lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
lv.RelativeTo = Enum.ActuatorRelativeTo.World
lv.VectorVelocity = Vector3.zero
lv.Enabled = false
lv.Parent = root

local ao = Instance.new("AlignOrientation")
ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
ao.Attachment0 = att0
ao.RigidityEnabled = true
ao.CFrame = root.CFrame
ao.Parent = root

local oldWS = hum.WalkSpeed
hrp.CFrame = seat.CFrame * CFrame.new(0, 1.5, 0)
local seatWeld = Instance.new("WeldConstraint")
seatWeld.Part0 = seat
seatWeld.Part1 = hrp
seatWeld.Parent = hrp
hum.WalkSpeed = 0
hum.Sit = true

pcall(function()
    require(player.PlayerScripts:WaitForChild("PlayerModule")):GetControls():Disable()
end)

root.Anchored = false

-- ============================================================
-- 4. ESTADO DE VOO
-- ============================================================
local yaw, vel = yaw0, Vector3.zero
local tp, tr = 0, 0
local rpm, engine = 0, false
local mainA, tailA = 0, 0
local fireT, gunIdx = 0, 1
local gd, groundT = 0, 0
local airborne = false
local blurOn = false
local lightOn = false
local camMode = 1
local radarObjs = {}
local uiT, radarT, scanT, statusT = 0, 0, 0, 0

-- ============================================================
-- 5. EFEITOS DE TIRO
-- ============================================================
local tracers, impacts = {}, {}
for i = 1, 14 do
    local t = Instance.new("Part")
    t.Anchored = true; t.CanCollide = false; t.CanQuery = false; t.CanTouch = false
    t.Material = Enum.Material.Neon; t.Color = Color3.fromRGB(255, 170, 60)
    t.Size = Vector3.new(0.14, 0.14, 1); t.Transparency = 1
    t.Parent = model
    tracers[i] = { p = t, off = nil }
end
for i = 1, 6 do
    local t = Instance.new("Part")
    t.Shape = Enum.PartType.Ball
    t.Anchored = true; t.CanCollide = false; t.CanQuery = false; t.CanTouch = false
    t.Material = Enum.Material.Neon; t.Color = Color3.fromRGB(255, 220, 120)
    t.Size = Vector3.new(0.9, 0.9, 0.9); t.Transparency = 1
    t.Parent = model
    impacts[i] = { p = t, off = nil }
end
local tIdx, iIdx = 1, 1

local function shoot()
    local gun = guns[gunIdx]
    gunIdx = gunIdx % #guns + 1

    local now = os.clock()
    local origin = gun.muzzle.WorldPosition
    local aim = root.Position + root.CFrame.LookVector * 300
    local dir = (aim - origin).Unit
    dir = (dir + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * CFG.SPREAD * 2).Unit

    local res = Workspace:Raycast(origin, dir * CFG.RANGE, rp)
    local hitPos = res and res.Position or (origin + dir * CFG.RANGE)
    local len = math.max((hitPos - origin).Magnitude, 1)

    local tr_ = tracers[tIdx]; tIdx = tIdx % #tracers + 1
    tr_.p.Size = Vector3.new(0.14, 0.14, len)
    tr_.p.CFrame = CFrame.lookAt(origin, hitPos) * CFrame.new(0, 0, -len / 2)
    tr_.p.Transparency = 0
    tr_.off = now + 0.06

    if res then
        local im = impacts[iIdx]; iIdx = iIdx % #impacts + 1
        im.p.Position = hitPos
        im.p.Transparency = 0.2
        im.off = now + 0.08
    end

    gun.flash.Transparency = 0.1
    gun.light.Enabled = true
    gun.off = now + 0.045
    gun.em:Emit(2)
end

-- ============================================================
-- 6. HUD TÁTIL
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "AH6_HUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
local okp = pcall(function()
    gui.Parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
end)
if not okp or not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end

local uiIn, kbIn, held = {}, {}, {}
local function mkBtn(txt, anchor, pos, size, color)
    local b = Instance.new("TextButton")
    b.AnchorPoint = anchor
    b.Position = pos
    b.Size = size
    b.BackgroundColor3 = color
    b.BackgroundTransparency = 0.35
    b.AutoButtonColor = false
    b.Text = txt
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextScaled = true
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.2, 0); c.Parent = b
    local s = Instance.new("UIStroke"); s.Color = Color3.new(1, 1, 1); s.Transparency = 0.6; s.Parent = b
    local pd = Instance.new("UIPadding")
    pd.PaddingTop = UDim.new(0, 6); pd.PaddingBottom = UDim.new(0, 6)
    pd.PaddingLeft = UDim.new(0, 6); pd.PaddingRight = UDim.new(0, 6)
    pd.Parent = b
    b.Parent = gui
    return b
end

local function holdBtn(txt, key, anchor, pos, size, color)
    local b = mkBtn(txt, anchor, pos, size, color)
    connect(b.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            uiIn[key] = true
            held[i] = { key = key, b = b }
            b.BackgroundTransparency = 0.05
        end
    end)
    return b
end
connect(UIS.InputEnded, function(i)
    local h = held[i]
    if h then
        uiIn[h.key] = false
        h.b.BackgroundTransparency = 0.35
        held[i] = nil
    end
end)

local A11, A55 = Vector2.new(0, 1), Vector2.new(0.5, 0.5)
local GREEN, BLUE, GREY, RED = Color3.fromRGB(40, 140, 70), Color3.fromRGB(40, 90, 160), Color3.fromRGB(60, 60, 60), Color3.fromRGB(170, 40, 40)

holdBtn("▲ SUBIR",  "up",   A11, UDim2.new(0, 16, 1, -90),  UDim2.fromOffset(110, 56), GREEN)
holdBtn("▼ DESCER", "down", A11, UDim2.new(0, 16, 1, -24),  UDim2.fromOffset(110, 56), GREEN)
holdBtn("↺",        "yl",   A11, UDim2.new(0, 136, 1, -24), UDim2.fromOffset(56, 56),   GREY)
holdBtn("↻",        "yr",   A11, UDim2.new(0, 198, 1, -24), UDim2.fromOffset(56, 56),   GREY)

holdBtn("▲", "fwd",   A55, UDim2.new(1, -110, 1, -165), UDim2.fromOffset(60, 60), BLUE)
holdBtn("▼", "back",  A55, UDim2.new(1, -110, 1, -35),  UDim2.fromOffset(60, 60), BLUE)
holdBtn("◀", "left",  A55, UDim2.new(1, -175, 1, -100), UDim2.fromOffset(60, 60), BLUE)
holdBtn("▶", "right", A55, UDim2.new(1, -45,  1, -100), UDim2.fromOffset(60, 60), BLUE)

holdBtn("🔫 FOGO", "fire", A55, UDim2.new(1, -290, 1, -75), UDim2.fromOffset(86, 86), RED)

local bEngine = mkBtn("🚁 MOTOR", Vector2.new(0.5, 0), UDim2.new(0.5, -111, 0, 12), UDim2.fromOffset(70, 34), GREY)
local bLight  = mkBtn("💡 LUZ",   Vector2.new(0.5, 0), UDim2.new(0.5, -37,  0, 12), UDim2.fromOffset(70, 34), GREY)
local bCam    = mkBtn("🎥 CAM",   Vector2.new(0.5, 0), UDim2.new(0.5, 37,   0, 12), UDim2.fromOffset(70, 34), GREY)
local bExit   = mkBtn("✖ SAIR",   Vector2.new(0.5, 0), UDim2.new(0.5, 111,  0, 12), UDim2.fromOffset(70, 34), RED)

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.new(0.5, 0, 0, 52)
status.Size = UDim2.fromOffset(340, 22)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamBold
status.TextSize = 14
status.TextColor3 = Color3.new(1, 1, 1)
status.TextStrokeTransparency = 0.4
status.Text = "MOTOR DESLIGADO - toque em MOTOR"
status.Parent = gui

-- ============================================================
-- 7. PAINEL DO COCKPIT
-- ============================================================
local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(r, 0); c.Parent = o end
local function stroke(o, t, col) local s = Instance.new("UIStroke"); s.Thickness = t; s.Color = col; s.Parent = o end
local function label(parent, txt, pos, size, col, ts)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1; l.Position = pos; l.Size = size
    l.Font = Enum.Font.GothamBold; l.TextSize = ts; l.TextColor3 = col; l.Text = txt
    l.Parent = parent
    return l
end

local bgPanel = Instance.new("Frame")
bgPanel.Size = UDim2.fromScale(1, 1)
bgPanel.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
bgPanel.BorderSizePixel = 0
bgPanel.Parent = sg

local function makeDial(x, name, maxV, needleCol)
    local d = Instance.new("Frame")
    d.Size = UDim2.fromOffset(100, 100)
    d.Position = UDim2.fromOffset(x, 6)
    d.BackgroundColor3 = Color3.fromRGB(14, 16, 14)
    d.BorderSizePixel = 0
    d.Parent = bgPanel
    corner(d, 1); stroke(d, 3, Color3.fromRGB(190, 190, 190))

    for i = 0, 8 do
        local c = Instance.new("Frame")
        c.Size = UDim2.fromScale(1, 1); c.BackgroundTransparency = 1
        c.Rotation = -135 + i * 33.75; c.Parent = d
        local t = Instance.new("Frame")
        t.Size = UDim2.fromOffset(2, i % 2 == 0 and 9 or 5)
        t.Position = UDim2.new(0.5, 0, 0, 3); t.AnchorPoint = Vector2.new(0.5, 0)
        t.BackgroundColor3 = Color3.new(1, 1, 1); t.BorderSizePixel = 0; t.Parent = c
    end

    label(d, name, UDim2.new(0, 0, 0.62, 0), UDim2.new(1, 0, 0, 14), Color3.fromRGB(200, 200, 200), 11)

    local nc = Instance.new("Frame")
    nc.Size = UDim2.fromScale(1, 1); nc.BackgroundTransparency = 1; nc.Parent = d
    local n = Instance.new("Frame")
    n.Size = UDim2.fromOffset(3, 38); n.Position = UDim2.new(0.5, 0, 0, 10)
    n.AnchorPoint = Vector2.new(0.5, 0); n.BackgroundColor3 = needleCol
    n.BorderSizePixel = 0; n.Parent = nc
    local cap = Instance.new("Frame")
    cap.Size = UDim2.fromOffset(9, 9); cap.AnchorPoint = A55; cap.Position = UDim2.fromScale(0.5, 0.5)
    cap.BackgroundColor3 = Color3.fromRGB(220, 220, 220); cap.BorderSizePixel = 0; cap.Parent = d
    corner(cap, 1)

    local v = label(bgPanel, "0", UDim2.fromOffset(x, 108), UDim2.fromOffset(100, 30), Color3.fromRGB(120, 255, 140), 15)
    return function(val, txt)
        nc.Rotation = -135 + 270 * math.clamp(val / maxV, 0, 1)
        v.Text = txt
    end
end

local setRPM = makeDial(6,   "RPM",  100, Color3.fromRGB(255, 140, 40))
local setALT = makeDial(112, "ALT",  300, Color3.fromRGB(255, 255, 255))
local setSPD = makeDial(218, "KM/H", 160, Color3.fromRGB(90, 255, 120))

local radar = Instance.new("Frame")
radar.Size = UDim2.fromOffset(140, 140)
radar.Position = UDim2.fromOffset(330, 5)
radar.BackgroundColor3 = Color3.fromRGB(0, 22, 0)
radar.BorderSizePixel = 0
radar.ClipsDescendants = true
radar.Parent = bgPanel
corner(radar, 1); stroke(radar, 3, Color3.fromRGB(0, 200, 80))

local ring = Instance.new("Frame")
ring.AnchorPoint = A55; ring.Position = UDim2.fromScale(0.5, 0.5); ring.Size = UDim2.fromScale(0.5, 0.5)
ring.BackgroundTransparency = 1; ring.Parent = radar
corner(ring, 1); stroke(ring, 1, Color3.fromRGB(0, 160, 70))

for _, sz in ipairs({ UDim2.new(1, 0, 0, 1), UDim2.new(0, 1, 1, 0) }) do
    local l = Instance.new("Frame")
    l.AnchorPoint = A55; l.Position = UDim2.fromScale(0.5, 0.5); l.Size = sz
    l.BackgroundColor3 = Color3.fromRGB(0, 140, 60); l.BorderSizePixel = 0; l.Parent = radar
end

local sweepC = Instance.new("Frame")
sweepC.Size = UDim2.fromScale(1, 1); sweepC.BackgroundTransparency = 1; sweepC.Parent = radar
local sweep = Instance.new("Frame")
sweep.AnchorPoint = Vector2.new(0.5, 0); sweep.Position = UDim2.new(0.5, 0, 0, 0)
sweep.Size = UDim2.fromOffset(2, 70); sweep.BackgroundColor3 = Color3.fromRGB(80, 255, 140)
sweep.BackgroundTransparency = 0.3; sweep.BorderSizePixel = 0; sweep.Parent = sweepC

local me = Instance.new("Frame")
me.AnchorPoint = A55; me.Position = UDim2.fromScale(0.5, 0.5); me.Size = UDim2.fromOffset(7, 7)
me.BackgroundColor3 = Color3.new(1, 1, 1); me.BorderSizePixel = 0; me.Parent = radar
corner(me, 1)

local dots = {}
for i = 1, 32 do
    local d = Instance.new("Frame")
    d.AnchorPoint = A55; d.Size = UDim2.fromOffset(6, 6); d.BorderSizePixel = 0
    d.Visible = false; d.Parent = radar
    corner(d, 1)
    dots[i] = d
end
local contactLbl = label(bgPanel, "RADAR 0", UDim2.fromOffset(330, 0), UDim2.fromOffset(140, 8), Color3.fromRGB(0, 200, 80), 9)

local op = OverlapParams.new()
op.FilterType = Enum.RaycastFilterType.Exclude
op.FilterDescendantsInstances = { model, char }
op.MaxParts = 120
local function scanRadar()
    local parts = Workspace:GetPartBoundsInRadius(root.Position, CFG.RADAR_RANGE, op)
    local seen, list = {}, {}
    for _, p in ipairs(parts) do
        if #list >= 28 then break end
        if p.Size.Magnitude > 6 and p.Size.X < 200 and p.Size.Z < 200 then
            local m = p:FindFirstAncestorOfClass("Model")
            local key = m or p
            if not seen[key] then
                seen[key] = true
                if not (m and Players:GetPlayerFromCharacter(m)) then
                    list[#list + 1] = m and m:GetPivot().Position or p.Position
                end
            end
        end
    end
    radarObjs = list
end

local function drawRadar()
    local base = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
    local n = 0
    local function plot(pos, color)
        if n >= #dots then return end
        local rel = base:PointToObjectSpace(pos)
        local dx, dz = rel.X / CFG.RADAR_RANGE, rel.Z / CFG.RADAR_RANGE
        if dx * dx + dz * dz > 1 then return end
        n += 1
        local d = dots[n]
        d.Position = UDim2.fromOffset(70 + dx * 68, 70 + dz * 68)
        d.BackgroundColor3 = color
        d.Visible = true
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local h = p.Character:FindFirstChild("HumanoidRootPart")
            if h then plot(h.Position, Color3.fromRGB(255, 60, 60)) end
        end
    end
    for _, pos in ipairs(radarObjs) do plot(pos, Color3.fromRGB(255, 210, 60)) end
    for i = n + 1, #dots do dots[i].Visible = false end
    sweepC.Rotation = (sweepC.Rotation + 28) % 360
    contactLbl.Text = "RADAR " .. n
end

local function updateDials()
    local spd = root.AssemblyLinearVelocity.Magnitude * 1.008
    local alt = math.max(0, root.Position.Y * 0.28)
    setRPM(rpm, string.format("%.0f%%", rpm))
    setALT(alt, string.format("%.0f m", alt))
    setSPD(spd, string.format("%.0f", spd))
end

-- ============================================================
-- 8. AÇÕES
-- ============================================================
local function setCharVisible(v)
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then pcall(function() d.LocalTransparencyModifier = v and 0 or 1 end) end
    end
end

local function setCam(mode)
    camMode = mode
    pcall(function() RunService:UnbindFromRenderStep("AH6Cam") end)
    if mode == 2 then
        camera.CameraType = Enum.CameraType.Scriptable
        camera.FieldOfView = 80
        setCharVisible(false)
        RunService:BindToRenderStep("AH6Cam", Enum.RenderPriority.Camera.Value + 1, function()
            camera.CFrame = root.CFrame * CFG.COCKPIT_CAM
        end)
    else
        camera.CameraType = Enum.CameraType.Custom
        camera.FieldOfView = 70
        setCharVisible(true)
    end
end

local function toggleEngine()
    engine = not engine
    bEngine.BackgroundColor3 = engine and GREEN or GREY
end
local function toggleLight()
    lightOn = not lightOn
    spot.Enabled = lightOn
    lamp.Material = lightOn and Enum.Material.Neon or PLASTIC
    lamp.Color = lightOn and Color3.fromRGB(255, 244, 200) or DARK
    bLight.BackgroundColor3 = lightOn and Color3.fromRGB(200, 170, 40) or GREY
end

local function cleanup()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep("AH6Cam") end)
    pcall(function()
        camera.CameraType = Enum.CameraType.Custom
        camera.FieldOfView = 70
    end)
    pcall(setCharVisible, true)
    pcall(function()
        local exitPos = root.Position + CFrame.Angles(0, yaw, 0).RightVector * 7 + Vector3.new(0, 1, 0)
        if seatWeld then seatWeld:Destroy() end
        hum.Sit = false
        hum.WalkSpeed = oldWS
        hrp.CFrame = CFrame.new(exitPos)
    end)
    pcall(function() require(player.PlayerScripts:WaitForChild("PlayerModule")):GetControls():Enable() end)
    pcall(function() gui:Destroy() end)
    pcall(function() model:Destroy() end)
    _G.AH6_Cleanup = nil
end
_G.AH6_Cleanup = cleanup

connect(bEngine.Activated, toggleEngine)
connect(bLight.Activated, toggleLight)
connect(bCam.Activated, function() setCam(camMode == 1 and 2 or 1) end)
connect(bExit.Activated, cleanup)
connect(hum.Died, cleanup)

local keymap = {
    [Enum.KeyCode.Space] = "up", [Enum.KeyCode.LeftShift] = "down",
    [Enum.KeyCode.W] = "fwd",    [Enum.KeyCode.S] = "back",
    [Enum.KeyCode.A] = "left",   [Enum.KeyCode.D] = "right",
    [Enum.KeyCode.Q] = "yl",     [Enum.KeyCode.E] = "yr",
    [Enum.KeyCode.F] = "fire",
}
connect(UIS.InputBegan, function(i, gp)
    if gp then return end
    local k = keymap[i.KeyCode]
    if k then kbIn[k] = true end
    if i.KeyCode == Enum.KeyCode.R then toggleEngine()
    elseif i.KeyCode == Enum.KeyCode.L then toggleLight()
    elseif i.KeyCode == Enum.KeyCode.C then setCam(camMode == 1 and 2 or 1) end
end)
connect(UIS.InputEnded, function(i)
    local k = keymap[i.KeyCode]
    if k then kbIn[k] = false end
end)

-- ============================================================
-- 9. LOOP PRINCIPAL
-- ============================================================
connect(RunService.Heartbeat, function(dt)
    dt = math.min(dt, 0.1)
    if not root or not root.Parent then return end
    if not hum.Sit then hum.Sit = true end

    if engine then rpm = math.min(100, rpm + CFG.RPM_UP * dt)
    else rpm = math.max(0, rpm - CFG.RPM_DOWN * dt) end
    local canFly = rpm >= 85

    groundT -= dt
    if groundT <= 0 then
        groundT = 0.1
        local r = Workspace:Raycast(root.Position, Vector3.new(0, -60, 0), rp)
        gd = r and (root.Position.Y - r.Position.Y) or 99
        airborne = gd > 5
    end

    local vIn = (get("up") and 1 or 0) - (get("down") and 1 or 0)
    local pIn = (get("fwd") and 1 or 0) - (get("back") and 1 or 0)
    local rIn = (get("right") and 1 or 0) - (get("left") and 1 or 0)
    local yIn = (get("yr") and 1 or 0) - (get("yl") and 1 or 0)
    if not canFly then vIn, pIn, rIn, yIn = 0, 0, 0, 0 end
    if not airborne and vIn <= 0 then pIn, rIn = 0, 0 end

    yaw -= yIn * CFG.YAW_RATE * dt
    local yawCF = CFrame.Angles(0, yaw, 0)
    local k3 = math.min(1, dt * 2.5)
    tp += (-pIn * CFG.TILT_P - tp) * k3
    tr += (-rIn * CFG.TILT_R - tr) * k3
    ao.CFrame = yawCF * CFrame.Angles(tp, 0, tr)

    local tgt = yawCF.LookVector * (pIn * CFG.MAX_SPEED)
              + yawCF.RightVector * (rIn * CFG.MAX_SPEED * 0.45)
              + Vector3.new(0, vIn * CFG.CLIMB, 0)
    local kH, kV = math.min(1, dt * 1.1), math.min(1, dt * 3)
    vel = Vector3.new(vel.X + (tgt.X - vel.X) * kH, vel.Y + (tgt.Y - vel.Y) * kV, vel.Z + (tgt.Z - vel.Z) * kH)
    if canFly then
        lv.Enabled = true
        lv.VectorVelocity = vel
    else
        lv.Enabled = false
        vel = Vector3.zero
    end

    mainA += rpm / 100 * 28 * dt
    tailA += rpm / 100 * 45 * dt
    for _, s in ipairs(spinners) do
        local a = s.tail and tailA or mainA
        local rot = (s.axis == "Y") and CFrame.Angles(0, a, 0) or CFrame.Angles(a, 0, 0)
        s.w.C0 = s.pivot * rot * s.loc
    end
    local wantBlur = rpm > 75
    if wantBlur ~= blurOn then
        blurOn = wantBlur
        for _, s in ipairs(spinners) do s.p.Transparency = blurOn and 0.4 or 0 end
    end

    if get("fire") and rpm >= 40 then
        fireT += dt
        local step, n = 1 / CFG.FIRE_RATE, 0
        while fireT >= step and n < 3 do
            fireT -= step
            n += 1
            shoot()
        end
    else
        fireT = 0
    end

    local now = os.clock()
    for _, gun in ipairs(guns) do
        if gun.off and now > gun.off then
            gun.flash.Transparency = 1
            gun.light.Enabled = false
            gun.off = nil
        end
    end
    for _, t in ipairs(tracers) do
        if t.off and now > t.off then t.p.Transparency = 1; t.off = nil end
    end
    for _, t in ipairs(impacts) do
        if t.off and now > t.off then t.p.Transparency = 1; t.off = nil end
    end

    uiT += dt
    if uiT >= 0.1 then uiT = 0; updateDials() end
    radarT += dt
    if radarT >= 0.15 then radarT = 0; drawRadar() end
    scanT += dt
    if scanT >= 0.6 then scanT = 0; scanRadar() end
    statusT += dt
    if statusT >= 0.25 then
        statusT = 0
        if not engine and rpm < 1 then status.Text = "MOTOR DESLIGADO - toque em MOTOR"
        elseif rpm < 85 then status.Text = "ACELERANDO ROTOR... " .. string.format("%.0f%%", rpm)
        else status.Text = airborne and "EM VOO" or "PRONTO - toque em SUBIR" end
    end
end)

scanRadar()
print("[AH-6 v1.2] Pronto! Câmera do cockpit ajustada com sucesso.")
