-- // Delta Executor - TuboCAM v13
-- v12 + botão ON/OFF da grade na TV (OFF = tela velha com logo quicando).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = Workspace.CurrentCamera

-- Limpar execuções anteriores
if Workspace:FindFirstChild("CCTVRetroFolder") then Workspace.CCTVRetroFolder:Destroy() end
if player.PlayerGui:FindFirstChild("RetroTVGui") then player.PlayerGui.RetroTVGui:Destroy() end
if Lighting:FindFirstChild("CCTVNightVision") then Lighting.CCTVNightVision:Destroy() end

local folder = Instance.new("Folder")
folder.Name = "CCTVRetroFolder"
folder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = {folder, character}

local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)

-- ===================== CONFIG =====================
local CFG = {
    WALL_PENALTY = 15,
    SIGNAL_LOSS = 0.25,
    BOOT_TIME = 6,
    HEIGHT_STEP = 0.5,

    MOTION_RANGE = 45,
    MOTION_HALF_FOV = 35,
    MOTION_MIN_SPEED = 2,
    DETECT_PLAYERS = true,
    DETECT_NPCS = true,
    DETECT_SELF = true,
    ALERT_HOLD = 3,
    ALARM_SOUND_ID = "",
    ICON_IMAGE_ID = "",

    GRID_MAX_CAMS = 16,
    FEED_RADIUS = 60,
    FEED_PART_BUDGET = 800,
    FEED_REFRESH = 10,
    FEED_FOV = 70,
    GRID_SHOW_NPCS = false,
    CHAR_INTERVAL = 0.25,
    MAX_CHARS = 6,
    DEBUG = true,

    TV_W = 480, TV_H = 380,
    LOGO_W = 150, LOGO_H = 44,

    RED = Color3.fromRGB(255, 30, 30),
    BLACK = Color3.fromRGB(0, 0, 0),
}

-- ===================== ESTADO =====================
local ST = {
    camIndex = 1, viewing = false, currentCamData = nil,
    activeTV = nil, activeTVScreen = nil, tvBase = nil, rcaModel = nil,
    nvrOn = true, nvrBootStart = tick(),
    nvrModel = nil, nvrBase = nil, nvrBody = nil, nvrButton = nil,
    nvrLedPower = nil, nvrLedRec = nil, ledCache = {},
    nightVision = false, motionOn = false, alertUntil = 0, lastAlarm = 0,
    camHeight = 3, panelsOpen = true, cableTarget = nil,
    tvNoiseUpdate = nil, tvLogo = nil, tvUI = nil, lastTVNoise = 0,
    logoX = 20, logoY = 20, logoVX = 110, logoVY = 90,
    lastPos = setmetatable({}, {__mode = "k"}),
    npcCache = {}, lastNpcRefresh = 0,
    lastIR = 0, lastScan = 0,
    gridMode = true,
}

local UI = {}
local FN = {}
local GRID = {cells = {}, count = 0, lastSnap = 0, lastChars = 0, lastNpc = 0, charModels = {}, lastWarn = 0}
local createdCams = {}

-- Filtro de visão noturna
do
    local e = Instance.new("ColorCorrectionEffect")
    e.Name = "CCTVNightVision"
    e.TintColor = Color3.fromRGB(110, 255, 110)
    e.Brightness = 0.12
    e.Contrast = 0.25
    e.Saturation = -0.85
    e.Enabled = false
    e.Parent = Lighting
    UI.nightEffect = e
end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

-- ===================== AJUDANTES =====================
local function floorYAt(pos)
    local hit = Workspace:Raycast(pos, Vector3.new(0, -300, 0), rayParams)
    return hit and hit.Position.Y + 0.05 or pos.Y
end

local function cableSeg(parent, a, b, color, thick)
    local d = (a - b).Magnitude
    if d < 0.05 then return end
    local t = thick or 0.06
    new("Part", {
        Size = Vector3.new(t, t, d),
        CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -d / 2),
        Color = color or Color3.fromRGB(20, 20, 20),
        Material = Enum.Material.Rubber,
        Anchored = true, CanCollide = false, CanQuery = false,
    }, parent)
end

local function nvrExists()
    return ST.nvrBody ~= nil and ST.nvrBody.Parent ~= nil
end

local function nvrReady()
    return nvrExists() and ST.nvrOn and (tick() - ST.nvrBootStart) >= CFG.BOOT_TIME
end

local function tvLinked()
    return nvrExists() and ST.rcaModel ~= nil and ST.rcaModel.Parent ~= nil
end

local function toggleNVR()
    ST.nvrOn = not ST.nvrOn
    if ST.nvrOn then ST.nvrBootStart = tick() end
    if ST.nvrButton then
        ST.nvrButton.Color = ST.nvrOn and Color3.fromRGB(170, 170, 175) or Color3.fromRGB(80, 80, 85)
    end
    if FN.toast then
        FN.toast(ST.nvrOn and "📼 NVR ligado — iniciando..." or "📼 NVR desligado")
    end
end

local function isDark()
    local t = Lighting.ClockTime
    return t < 5.5 or t > 18.5
end

-- Cor do LED de status (cinza quando a câmera está OFF)
local function baseLed(c)
    return c.enabled and c.ledColor or Color3.fromRGB(60, 60, 60)
end

-- Próxima câmera ligada a partir do índice "from" (inclusive)
local function nextEnabled(from)
    local n = #createdCams
    if n == 0 then return nil end
    for step = 0, n - 1 do
        local idx = (from - 1 + step) % n + 1
        if createdCams[idx].enabled then return idx end
    end
    return nil
end

-- Clona mesmo se o objeto estiver marcado como Archivable = false
local function safeClone(inst)
    local was = inst.Archivable
    if not was then pcall(function() inst.Archivable = true end) end
    local ok, c = pcall(function() return inst:Clone() end)
    if not was then pcall(function() inst.Archivable = false end) end
    if ok then return c end
    return nil
end

-- ===================== 1. TV ANTIGA =====================
local function createRetroTV(cframe)
    if ST.activeTV then ST.activeTV:Destroy() end

    local origin = cframe.Position + Vector3.new(0, 3, 0)
    local hit = Workspace:Raycast(origin, Vector3.new(0, -30, 0), rayParams)
    local groundY = hit and hit.Position.Y or (cframe.Position.Y - 3)
    local _, yaw, _ = cframe:ToOrientation()
    local base = CFrame.new(cframe.Position.X, groundY, cframe.Position.Z) * CFrame.Angles(0, yaw + math.pi, 0)
    ST.tvBase = base

    local tvModel = new("Model", {Name = "TV_Antiga_CCTV"}, folder)
    local woodDark = Color3.fromRGB(40, 28, 20)
    local black = Color3.fromRGB(20, 20, 20)

    for _, sx in ipairs({-1.5, 1.5}) do
        for _, sz in ipairs({-0.6, 0.6}) do
            new("Part", {
                Size = Vector3.new(0.2, 0.9, 0.2), CFrame = base * CFrame.new(sx, 0.45, sz),
                Color = woodDark, Material = Enum.Material.Wood, Anchored = true, CanCollide = false,
            }, tvModel)
        end
    end

    local body = new("Part", {
        Name = "TVBody", Size = Vector3.new(3.8, 2.6, 1.8), CFrame = base * CFrame.new(0, 2.2, 0),
        Color = Color3.fromRGB(60, 45, 35), Material = Enum.Material.Wood, Anchored = true,
    }, tvModel)

    local screen = new("Part", {
        Name = "TVScreen", Size = Vector3.new(2.4, 1.9, 0.1),
        CFrame = body.CFrame * CFrame.new(0.4, 0, -0.86),
        Color = Color3.fromRGB(20, 30, 25), Material = Enum.Material.Glass, Anchored = true,
    }, tvModel)

    for _, y in ipairs({0.5, -0.1}) do
        new("Part", {
            Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3),
            CFrame = body.CFrame * CFrame.new(-1.35, y, -0.92),
            Color = Color3.fromRGB(170, 170, 170), Material = Enum.Material.Metal,
            Anchored = true, CanCollide = false,
        }, tvModel)
    end

    for _, side in ipairs({-1, 1}) do
        new("Part", {
            Size = Vector3.new(0.06, 1.4, 0.06),
            CFrame = body.CFrame * CFrame.new(0, 1.3, 0)
                * CFrame.Angles(0, 0, math.rad(side * 25)) * CFrame.new(0, 0.7, 0),
            Color = black, Material = Enum.Material.Metal, Anchored = true, CanCollide = false,
        }, tvModel)
    end

    for _, j in ipairs({{0.4, Color3.fromRGB(255, 205, 0)}, {0.85, Color3.fromRGB(245, 245, 245)}}) do
        new("Part", {
            Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.26, 0.26),
            CFrame = base * CFrame.new(j[1], 1.7, 0.93) * ALONG_Z,
            Color = j[2], Material = Enum.Material.Metal, Anchored = true, CanCollide = false,
        }, tvModel)
    end

    new("ClickDetector", {MaxActivationDistance = 15}, screen)

    tvModel.PrimaryPart = screen
    ST.activeTV = tvModel
    ST.activeTVScreen = screen
    return tvModel
end

-- ===================== 1B. NVR =====================
local function createNVR(cframe)
    if ST.nvrModel then ST.nvrModel:Destroy() end

    local origin = cframe.Position + Vector3.new(0, 3, 0)
    local hit = Workspace:Raycast(origin, Vector3.new(0, -30, 0), rayParams)
    local groundY = hit and hit.Position.Y or (cframe.Position.Y - 3)
    local _, yaw, _ = cframe:ToOrientation()
    local base = CFrame.new(cframe.Position.X, groundY, cframe.Position.Z) * CFrame.Angles(0, yaw + math.pi, 0)

    local model = new("Model", {Name = "NVR_TuboCAM"}, folder)

    local function mkPart(size, cf, color, material, shape, collide)
        local p = Instance.new("Part")
        if shape then p.Shape = shape end
        p.Size = size
        p.CFrame = cf
        p.Color = color
        p.Material = material or Enum.Material.SmoothPlastic
        p.Anchored = true
        p.CanCollide = collide or false
        p.Parent = model
        return p
    end

    local metal = Color3.fromRGB(45, 45, 50)
    mkPart(Vector3.new(5, 0.2, 3), base * CFrame.new(0, 2.1, 0), metal, Enum.Material.Metal, nil, true)
    for _, sx in ipairs({-2.3, 2.3}) do
        for _, sz in ipairs({-1.3, 1.3}) do
            mkPart(Vector3.new(0.2, 2, 0.2), base * CFrame.new(sx, 1, sz), metal, Enum.Material.Metal)
        end
    end

    local body = mkPart(Vector3.new(4.4, 0.9, 2.6), base * CFrame.new(0, 2.65, 0), Color3.fromRGB(22, 22, 25), nil, nil, true)
    local front = mkPart(Vector3.new(4.4, 0.9, 0.05), base * CFrame.new(0, 2.65, -1.325), Color3.fromRGB(14, 14, 17))

    local sg = new("SurfaceGui", {Face = Enum.NormalId.Front, CanvasSize = Vector2.new(440, 90), LightInfluence = 0}, front)

    local function label(text, x, y, w, h, size, color)
        return new("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
            Text = text, TextSize = size, TextColor3 = color, Font = Enum.Font.GothamBold,
        }, sg)
    end

    local logo = new("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 22), Size = UDim2.fromOffset(210, 40)}, sg)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5),
    }, logo)

    local function logoText(text, order)
        new("TextLabel", {
            LayoutOrder = order, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.new(0, 0, 1, 0), Text = text, TextSize = 30,
            TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBlack,
        }, logo)
    end
    local function logoSquare(color, order)
        new("Frame", {LayoutOrder = order, Size = UDim2.fromOffset(18, 18), BackgroundColor3 = color, BorderSizePixel = 0}, logo)
    end
    logoText("Tubo", 1)
    logoSquare(Color3.fromRGB(225, 30, 30), 2)
    logoText("CAM", 3)
    logoSquare(Color3.fromRGB(245, 245, 245), 4)

    label("NETWORK VIDEO RECORDER", 24, 68, 220, 12, 9, Color3.fromRGB(140, 140, 145))
    label("POWER", 270, 44, 60, 14, 10, Color3.fromRGB(150, 150, 155))
    label("REC", 330, 44, 60, 14, 10, Color3.fromRGB(150, 150, 155))
    label("ON/OFF", 385, 72, 50, 14, 9, Color3.fromRGB(150, 150, 155))

    local ledPower = mkPart(Vector3.new(0.1, 0.1, 0.1), base * CFrame.new(-0.8, 2.8, -1.35),
        Color3.fromRGB(0, 60, 25), nil, Enum.PartType.Ball)
    local ledRec = mkPart(Vector3.new(0.1, 0.1, 0.1), base * CFrame.new(-1.4, 2.8, -1.35),
        Color3.fromRGB(70, 10, 10), nil, Enum.PartType.Ball)

    local btn = mkPart(Vector3.new(0.1, 0.45, 0.45), base * CFrame.new(-1.9, 2.65, -1.38) * ALONG_Z,
        Color3.fromRGB(170, 170, 175), Enum.Material.Metal, Enum.PartType.Cylinder)
    local cd = new("ClickDetector", {MaxActivationDistance = 15}, btn)
    cd.MouseClick:Connect(toggleNVR)

    mkPart(Vector3.new(4.2, 0.7, 0.05), base * CFrame.new(0, 2.65, 1.325), Color3.fromRGB(35, 35, 40))
    mkPart(Vector3.new(0.12, 0.26, 0.26), base * CFrame.new(1.0, 2.65, 1.36) * ALONG_Z,
        Color3.fromRGB(255, 205, 0), Enum.Material.Metal, Enum.PartType.Cylinder)
    mkPart(Vector3.new(0.12, 0.26, 0.26), base * CFrame.new(1.5, 2.65, 1.36) * ALONG_Z,
        Color3.fromRGB(245, 245, 245), Enum.Material.Metal, Enum.PartType.Cylinder)
    for i = 0, 7 do
        mkPart(Vector3.new(0.18, 0.14, 0.05), base * CFrame.new(-1.9 + i * 0.22, 2.55, 1.36), Color3.fromRGB(90, 90, 95))
    end

    ST.nvrModel, ST.nvrBase, ST.nvrBody, ST.nvrButton = model, base, body, btn
    ST.nvrLedPower, ST.nvrLedRec = ledPower, ledRec
    ST.ledCache = {}
    ST.nvrOn = true
    ST.nvrBootStart = tick()
    return model
end

local function hubPoints()
    local inPos = (ST.nvrBase * CFrame.new(-1.1, 2.55, 1.36)).Position
    local outPos = inPos - ST.nvrBase.LookVector * 0.4
    return inPos, outPos
end

-- ===================== 1C. CABOS RCA =====================
local function updateRCA()
    if ST.rcaModel then ST.rcaModel:Destroy() ST.rcaModel = nil end
    if not nvrExists() or not ST.tvBase then return end

    local nvrBase, tvBase = ST.nvrBase, ST.tvBase
    local rca = new("Model", {Name = "CaboRCA"}, folder)
    ST.rcaModel = rca

    local specs = {
        {Color3.fromRGB(255, 205, 0), 1.0, 0.4, 0.5},
        {Color3.fromRGB(245, 245, 245), 1.5, 0.85, 0.75},
    }

    for _, s in ipairs(specs) do
        local color, nx, tx, off = s[1], s[2], s[3], s[4]
        local nPort = (nvrBase * CFrame.new(nx, 2.65, 1.36)).Position
        local tPort = (tvBase * CFrame.new(tx, 1.7, 0.93)).Position
        local nOut = nPort - nvrBase.LookVector * off
        local tOut = tPort - tvBase.LookVector * off
        local nFloor = Vector3.new(nOut.X, floorYAt(nOut), nOut.Z)
        local tFloor = Vector3.new(tOut.X, floorYAt(tOut), tOut.Z)

        cableSeg(rca, nPort, nOut, color, 0.07)
        cableSeg(rca, nOut, nFloor, color, 0.07)
        cableSeg(rca, nFloor, tFloor, color, 0.07)
        cableSeg(rca, tFloor, tOut, color, 0.07)
        cableSeg(rca, tOut, tPort, color, 0.07)

        for _, plug in ipairs({
            nvrBase * CFrame.new(nx, 2.65, 1.5) * ALONG_Z,
            tvBase * CFrame.new(tx, 1.7, 1.08) * ALONG_Z,
        }) do
            new("Part", {
                Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 0.22, 0.22), CFrame = plug,
                Color = color, Material = Enum.Material.Metal,
                Anchored = true, CanCollide = false, CanQuery = false,
            }, rca)
        end
    end
end

-- ===================== 2. CABO (câmera com fio -> NVR) =====================
local function updateCable(camData)
    if camData.cable then camData.cable:Destroy() camData.cable = nil end
    if not camData.isWired or not nvrExists() then return end

    local cable = new("Model", {Name = "Cabo"}, camData.model)
    local from = (camData.lens.CFrame * CFrame.new(0, -0.55, 1.79)).Position
    local inPos, outPos = hubPoints()
    local mode = camData.cableMode

    if mode == "cima" then
        local up = Workspace:Raycast(from, Vector3.new(0, 300, 0), rayParams)
        local y = up and up.Position.Y - 0.05 or from.Y + 4
        local a = Vector3.new(from.X, y, from.Z)
        local b = Vector3.new(outPos.X, y, outPos.Z)
        cableSeg(cable, from, a)
        cableSeg(cable, a, b)
        cableSeg(cable, b, outPos)
        cableSeg(cable, outPos, inPos)
    elseif mode == "parede" then
        local b = Vector3.new(outPos.X, from.Y, outPos.Z)
        cableSeg(cable, from, b)
        cableSeg(cable, b, outPos)
        cableSeg(cable, outPos, inPos)
    else
        local a = Vector3.new(from.X, floorYAt(from), from.Z)
        local b = Vector3.new(outPos.X, floorYAt(outPos), outPos.Z)
        cableSeg(cable, from, a)
        cableSeg(cable, a, b)
        cableSeg(cable, b, outPos)
        cableSeg(cable, outPos, inPos)
    end

    camData.cable = cable
end

-- ===================== 3. CÂMERAS =====================
local function setIR(camData, on)
    if camData.irOn == on then return end
    camData.irOn = on
    for _, led in ipairs(camData.irLeds) do
        if on then
            led.Material = Enum.Material.Neon
            led.Color = Color3.fromRGB(255, 60, 60)
        else
            led.Material = Enum.Material.SmoothPlastic
            led.Color = Color3.fromRGB(90, 20, 20)
        end
    end
    camData.irLight.Enabled = on
end

local function buildPole(camData)
    if camData.pole then camData.pole:Destroy() camData.pole = nil end
    if not camData.hasPole then return end

    local base = (camData.lens.CFrame * CFrame.new(0, -0.55, 1.79)).Position
    local hit = Workspace:Raycast(base, Vector3.new(0, -300, 0), rayParams)
    local gy = hit and hit.Position.Y or (base.Y - 3)
    local h = math.max(base.Y - gy, 0.2)
    local gray = Color3.fromRGB(70, 70, 75)

    local pole = new("Model", {Name = "Poste"}, camData.model)

    local function cyl(size, cf)
        new("Part", {
            Shape = Enum.PartType.Cylinder, Size = size, CFrame = cf, Color = gray,
            Material = Enum.Material.Metal, Anchored = true, CanCollide = false,
        }, pole)
    end

    local upright = CFrame.Angles(0, 0, math.rad(90))
    cyl(Vector3.new(h, 0.3, 0.3), CFrame.new(base.X, gy + h / 2, base.Z) * upright)
    cyl(Vector3.new(0.15, 1.6, 1.6), CFrame.new(base.X, gy + 0.075, base.Z) * upright)

    camData.pole = pole
end

local function createCameraModel(name, cframe, isWired, hasPole)
    local model = new("Model", {Name = name}, folder)

    local BLOCK, BALL, CYL = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
    local bodyColor = isWired and Color3.fromRGB(55, 55, 60) or Color3.fromRGB(238, 238, 242)
    local ledColor = isWired and Color3.fromRGB(255, 170, 0) or Color3.fromRGB(0, 255, 150)
    local black = Color3.fromRGB(25, 25, 28)

    local function mk(shape, size, cf, color, material, transparency)
        return new("Part", {
            Shape = shape, Size = size, CFrame = cf, Color = color,
            Material = material or Enum.Material.SmoothPlastic,
            Transparency = transparency or 0, Anchored = true, CanCollide = false,
        }, model)
    end

    local body = mk(CYL, Vector3.new(1.8, 0.8, 0.8), cframe * ALONG_Z, bodyColor)
    mk(CYL, Vector3.new(0.08, 0.82, 0.82), cframe * CFrame.new(0, 0, -0.65) * ALONG_Z, Color3.fromRGB(30, 70, 160))
    mk(CYL, Vector3.new(0.12, 0.82, 0.82), cframe * CFrame.new(0, 0, -0.9) * ALONG_Z, black)
    mk(CYL, Vector3.new(0.08, 0.38, 0.38), cframe * CFrame.new(0, 0, -0.95) * ALONG_Z, Color3.fromRGB(10, 20, 45), Enum.Material.Glass)
    mk(BLOCK, Vector3.new(0.9, 0.08, 1.6), cframe * CFrame.new(0, 0.46, -0.2), bodyColor)

    local irLeds = {}
    for i = 0, 7 do
        local cf = cframe * CFrame.Angles(0, 0, math.rad(i * 45)) * CFrame.new(0.27, 0, -0.97)
        table.insert(irLeds, mk(BALL, Vector3.new(0.07, 0.07, 0.07), cf, Color3.fromRGB(90, 20, 20)))
    end

    local statusLed = mk(BALL, Vector3.new(0.08, 0.08, 0.08), cframe * CFrame.new(0.4, 0.1, 0.5), ledColor, Enum.Material.Neon)

    if not isWired then
        for _, side in ipairs({-1, 1}) do
            local cf = cframe * CFrame.new(side * 0.25, 0.3, 0.85)
                * CFrame.Angles(0, 0, math.rad(-side * 12))
                * CFrame.new(0, 0.5, 0)
                * CFrame.Angles(0, 0, math.rad(90))
            mk(CYL, Vector3.new(1, 0.07, 0.07), cf, black)
        end
    end

    mk(BALL, Vector3.new(0.25, 0.25, 0.25), cframe * CFrame.new(0, -0.5, 0), bodyColor)
    mk(BLOCK, Vector3.new(0.12, 0.12, 0.8), cframe * CFrame.new(0, -0.55, 0.4), bodyColor)
    mk(BLOCK, Vector3.new(0.5, 0.5, 0.06), cframe * CFrame.new(0, -0.55, 0.8), bodyColor)

    local lens = mk(BLOCK, Vector3.new(0.2, 0.2, 0.05), cframe * CFrame.new(0, 0, -0.99), black, nil, 1)

    local irLight = new("PointLight", {Color = Color3.fromRGB(255, 70, 70), Range = 16, Brightness = 1.5, Enabled = false}, lens)
    local camLight = new("SpotLight", {
        Color = Color3.fromRGB(255, 244, 214), Range = 40, Angle = 70, Brightness = 3,
        Face = Enum.NormalId.Front, Enabled = false,
    }, lens)

    model.PrimaryPart = lens
    local camData = {
        lens = lens, isWired = isWired, name = name, model = model, cable = nil,
        irLeds = irLeds, irLight = irLight, irOn = nil,
        statusLed = statusLed, ledColor = ledColor,
        motionUntil = nil, motionName = nil, motionHRP = nil,
        hasPole = hasPole, pole = nil, cableMode = "baixo",
        camLight = camLight, lightOn = false,
        enabled = true,
    }
    setIR(camData, isDark())
    buildPole(camData)
    updateCable(camData)

    if isWired then
        local cd = new("ClickDetector", {MaxActivationDistance = 20}, body)
        cd.MouseClick:Connect(function()
            if FN.openCableMenu then FN.openCableMenu(camData) end
        end)
    end

    return camData
end

-- ===================== 4. INTERFACE =====================
UI.gui = new("ScreenGui", {Name = "RetroTVGui", ResetOnSpawn = false}, player.PlayerGui)

-- ----- Sistema de chuvisco -----
local function makeNoise(parent, count, zIndex)
    local pool = {}
    for i = 1, count do
        pool[i] = new("Frame", {BorderSizePixel = 0, Visible = false, ZIndex = zIndex or 1}, parent)
    end
    local lastActive = 0

    return function(intensity, areaW, areaH, sMin, sMax, alphaMin)
        areaW, areaH = math.floor(areaW), math.floor(areaH)
        local active = math.floor(count * math.clamp(intensity, 0, 1))
        for i = 1, active do
            local f = pool[i]
            local g = math.random(80, 255)
            f.BackgroundColor3 = Color3.fromRGB(g, g, g)
            f.BackgroundTransparency = alphaMin + math.random() * (0.9 - alphaMin)
            f.Size = UDim2.fromOffset(math.random(sMin, sMax) * math.random(1, 3), math.random(sMin, sMax))
            f.Position = UDim2.fromOffset(math.random(0, areaW), math.random(0, areaH))
            f.Visible = true
        end
        for i = active + 1, lastActive do
            pool[i].Visible = false
        end
        lastActive = active
    end
end

-- Chuvisco em tela cheia + listras + SEM SINAL
do
    UI.static = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.95, BorderSizePixel = 0, ClipsDescendants = true, Visible = false,
    }, UI.gui)
    UI.screenNoise = makeNoise(UI.static, 170)

    UI.bars = {}
    for i = 1, 6 do
        UI.bars[i] = new("Frame", {BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, Visible = false}, UI.static)
    end

    UI.noSignal = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 420, 0, 80), Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundTransparency = 1, Text = "SEM SINAL", TextColor3 = Color3.fromRGB(255, 255, 255),
        TextStrokeTransparency = 0, TextSize = 54, Font = Enum.Font.Code, Visible = false,
    }, UI.static)
end

-- ----- Tela da TV no mundo -----
local function attachTVNoise(screenPart)
    local sg = new("SurfaceGui", {
        Face = Enum.NormalId.Front, CanvasSize = Vector2.new(CFG.TV_W, CFG.TV_H),
        LightInfluence = 0, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, screenPart)

    local bg = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(35, 40, 38),
        BorderSizePixel = 0, ClipsDescendants = true,
    }, sg)

    local grid = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BorderSizePixel = 0, ZIndex = 2, Visible = false,
    }, bg)

    ST.tvNoiseUpdate = makeNoise(bg, 140, 3)

    ST.logoX, ST.logoY = 20, 20
    ST.logoVX, ST.logoVY = math.abs(ST.logoVX), math.abs(ST.logoVY)
    ST.tvLogo = new("TextLabel", {
        Size = UDim2.fromOffset(CFG.LOGO_W, CFG.LOGO_H), Position = UDim2.fromOffset(ST.logoX, ST.logoY),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.25, BorderSizePixel = 0,
        Text = "📺 CCTV", TextColor3 = Color3.fromRGB(0, 255, 150), TextSize = 28,
        Font = Enum.Font.GothamBold, ZIndex = 4, Visible = false,
    }, bg)

    local roll = new("Frame", {
        Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 8, Visible = false,
    }, bg)

    local live = new("TextLabel", {
        Position = UDim2.new(0, 16, 0, 12), Size = UDim2.fromOffset(320, 28), BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(0, 255, 120), TextSize = 24, Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "● SEM CÂMERAS", ZIndex = 7, Visible = false,
    }, bg)

    local blue = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(10, 40, 200),
        BorderSizePixel = 0, ZIndex = 10,
    }, bg)

    new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 16), Size = UDim2.fromOffset(220, 52),
        BackgroundTransparency = 1, Text = "AV1 ↗", TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 44, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 11,
    }, blue)

    ST.tvUI = {bg = bg, blue = blue, roll = roll, live = live, grid = grid}
end

local function updateTVScreen()
    local tvUI = ST.tvUI
    if not tvUI or not ST.tvNoiseUpdate or not ST.activeTVScreen or not ST.activeTVScreen.Parent then return end
    local now = tick()
    local state, p = "blue", 0
    if tvLinked() and ST.nvrOn then
        p = (now - ST.nvrBootStart) / CFG.BOOT_TIME
        state = (p < 1) and "boot" or "live"
    end

    -- hasCams = tem câmeras E a grade está ligada (OFF = tela velha)
    local hasCams = #createdCams > 0 and ST.gridMode
    local showGrid = hasCams and (state == "live" or (state == "boot" and p >= 0.85))

    tvUI.blue.Visible = (state == "blue")
    tvUI.grid.Visible = showGrid
    tvUI.live.Visible = (state == "live" and not hasCams)
    tvUI.live.Text = (#createdCams > 0) and "● CCTV" or "● SEM CÂMERAS"
    ST.tvLogo.Visible = (state == "live" and not hasCams)
    tvUI.bg.BackgroundColor3 = (state == "boot" and p < 0.2)
        and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(35, 40, 38)

    if state == "blue" or not hasCams then
        if FN.gridClear then FN.gridClear() end
    elseif FN.gridUpdate and not ST.viewing then
        FN.gridUpdate(now, showGrid)
    end

    if state == "boot" and p >= 0.2 then
        tvUI.roll.Visible = true
        tvUI.roll.Position = UDim2.new(0, 0, ((now * 0.5) % 1.2) - 0.1, 0)
        tvUI.roll.BackgroundTransparency = 0.8 + (p - 0.2) * 0.2
    else
        tvUI.roll.Visible = false
    end

    if now - ST.lastTVNoise > 0.05 then
        ST.lastTVNoise = now
        local intensity = 0
        if state == "boot" then
            if p < 0.2 then
                intensity = 0
            elseif p < 0.5 then
                intensity = 0.6
            else
                intensity = 0.6 - ((p - 0.5) / 0.5) * 0.48
            end
        elseif state == "live" then
            intensity = hasCams and 0.04 or 0.06
        end
        ST.tvNoiseUpdate(intensity, CFG.TV_W, CFG.TV_H, 5, 16, 0.1)
    end
end

-- LEDs do NVR
local function setLed(led, key, on, onColor, offColor)
    if ST.ledCache[key] == on then return end
    ST.ledCache[key] = on
    led.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
    led.Color = on and onColor or offColor
end

local function updateNVRLeds()
    if not nvrExists() then return end
    local now = tick()
    local booting = ST.nvrOn and (now - ST.nvrBootStart) < CFG.BOOT_TIME
    local powerOn = ST.nvrOn and ((not booting) or (math.floor(now * 3) % 2 == 0))
    setLed(ST.nvrLedPower, "p", powerOn, Color3.fromRGB(0, 255, 90), Color3.fromRGB(0, 60, 25))
    local recOn = ST.nvrOn and (not booting) and #createdCams > 0 and (math.floor(now * 2) % 2 == 0)
    setLed(ST.nvrLedRec, "r", recOn, Color3.fromRGB(255, 30, 30), Color3.fromRGB(70, 10, 10))
end

-- REC + data/hora
UI.rec = new("TextLabel", {
    Size = UDim2.new(0, 120, 0, 28), Position = UDim2.new(1, -140, 0, 15), BackgroundTransparency = 1,
    TextColor3 = Color3.fromRGB(255, 40, 40), Text = "● REC", TextSize = 22, Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Right, Visible = false,
}, UI.gui)

UI.time = new("TextLabel", {
    Size = UDim2.new(0, 320, 0, 44), Position = UDim2.new(0, 15, 0, 15), BackgroundTransparency = 1,
    TextColor3 = Color3.fromRGB(230, 230, 230), Text = "", TextSize = 16, Font = Enum.Font.Code,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Visible = false,
}, UI.gui)

-- HUD da TV
do
    UI.hud = new("Frame", {
        Size = UDim2.new(0, 270, 0, 150), Position = UDim2.new(0.02, 0, 0.72, 0),
        BackgroundColor3 = Color3.fromRGB(25, 20, 18), BorderSizePixel = 0, Visible = false,
    }, UI.gui)
    new("UICorner", {CornerRadius = UDim.new(0, 8)}, UI.hud)

    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.fromRGB(45, 35, 30),
        TextColor3 = Color3.fromRGB(255, 180, 50), Text = "📺 TV TUBOCAM - CANAL CCTV",
        TextSize = 11, Font = Enum.Font.Code,
    }, UI.hud)

    UI.signal = new("TextLabel", {
        Size = UDim2.new(0.9, 0, 0, 24), Position = UDim2.new(0.05, 0, 0.22, 0),
        BackgroundColor3 = Color3.fromRGB(15, 15, 15), TextColor3 = Color3.fromRGB(0, 255, 100),
        Text = "📶 SINAL WI-FI: 100% (EXCELENTE)", TextSize = 10, Font = Enum.Font.Code,
    }, UI.hud)

    UI.btnNext = new("TextButton", {
        Size = UDim2.new(0.9, 0, 0, 28), Position = UDim2.new(0.05, 0, 0.42, 0),
        BackgroundColor3 = Color3.fromRGB(180, 90, 20), TextColor3 = Color3.fromRGB(255, 255, 255),
        Text = "🔄 Mudar Canal (Câmera)", TextSize = 11, Font = Enum.Font.GothamBold,
    }, UI.hud)

    UI.btnExit = new("TextButton", {
        Size = UDim2.new(0.9, 0, 0, 26), Position = UDim2.new(0.05, 0, 0.78, 0),
        BackgroundColor3 = Color3.fromRGB(150, 40, 40), TextColor3 = Color3.fromRGB(255, 255, 255),
        Text = "🔌 Desligar TV", TextSize = 11, Font = Enum.Font.GothamBold,
    }, UI.hud)
end

-- Botões acima do HUD (só enquanto assiste)
local function hudButton(text, yOffset, color)
    return new("TextButton", {
        Size = UDim2.new(0, 270, 0, 28), Position = UDim2.new(0.02, 0, 0.72, yOffset),
        BackgroundColor3 = color, TextColor3 = Color3.fromRGB(255, 255, 255),
        Text = text, TextSize = 12, Font = Enum.Font.GothamBold, Visible = false,
    }, UI.gui)
end

UI.btnNight = hudButton("🌙 Visão Noturna: OFF", -34, Color3.fromRGB(35, 50, 35))
UI.btnMotion = hudButton("🚶 Detecção de Movimento: OFF", -68, Color3.fromRGB(60, 50, 50))
UI.btnLight = hudButton("💡 Luz da Câmera: OFF", -102, Color3.fromRGB(70, 65, 30))

local function refreshLightButton()
    local c = ST.currentCamData
    local on = c and c.lightOn
    UI.btnLight.Text = on and "💡 Luz da Câmera: ON" or "💡 Luz da Câmera: OFF"
    UI.btnLight.BackgroundColor3 = on and Color3.fromRGB(190, 150, 20) or Color3.fromRGB(70, 65, 30)
end

UI.btnLight.MouseButton1Click:Connect(function()
    local c = ST.currentCamData
    if not c then return end
    c.lightOn = not c.lightOn
    c.camLight.Enabled = c.lightOn
    refreshLightButton()
end)

-- Aviso rápido (toast)
do
    UI.toast = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 330, 0, 34), Position = UDim2.new(0.5, 0, 0.12, 0),
        BackgroundColor3 = Color3.fromRGB(20, 20, 25), TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14, Font = Enum.Font.GothamBold, Visible = false, ZIndex = 20,
    }, UI.gui)
    new("UICorner", {CornerRadius = UDim.new(0, 8)}, UI.toast)

    local toastId = 0
    FN.toast = function(text)
        toastId += 1
        local my = toastId
        UI.toast.Text = text
        UI.toast.Visible = true
        task.delay(2.5, function()
            if toastId == my then UI.toast.Visible = false end
        end)
    end
end

-- Painel de instalação
UI.control = new("Frame", {
    Size = UDim2.new(0, 210, 0, 158), Position = UDim2.new(0.02, 0, 0.05, 0),
    BackgroundColor3 = Color3.fromRGB(20, 20, 25),
}, UI.gui)

local function makeButton(text, y, color)
    return new("TextButton", {
        Size = UDim2.new(0.9, 0, 0, 28), Position = UDim2.new(0.05, 0, 0, y),
        BackgroundColor3 = color, TextColor3 = Color3.fromRGB(255, 255, 255),
        Text = text, Font = Enum.Font.GothamBold,
    }, UI.control)
end

UI.btnTV = makeButton("📺 Colocar TV Antiga", 10, Color3.fromRGB(120, 70, 30))
UI.btnNVR = makeButton("🖥 Colocar NVR", 46, Color3.fromRGB(70, 70, 80))
UI.btnWifi = makeButton("📶 Instalar Cam Wi-Fi", 82, Color3.fromRGB(0, 140, 90))
UI.btnWired = makeButton("🔌 Instalar Cam com Fio", 118, Color3.fromRGB(60, 80, 110))

-- ----- Altura + posição das câmeras -----
local function getCameraSpawnCFrame()
    local feetY = rootPart.Position.Y - 3
    local y = feetY + ST.camHeight
    local look = rootPart.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
    flat = flat.Unit

    local origin = Vector3.new(rootPart.Position.X, y, rootPart.Position.Z)
    local hit = Workspace:Raycast(origin, flat * 60, rayParams)

    if hit and math.abs(hit.Normal.Y) < 0.5 then
        local pos = hit.Position + hit.Normal * 0.84
        return CFrame.lookAt(pos, pos + hit.Normal), true
    end

    -- Terreno aberto: a câmera nasce virada PARA o avatar
    local pos = origin + flat * 6
    return CFrame.lookAt(pos, pos - flat), false
end

do
    UI.height = new("Frame", {
        Size = UDim2.new(0, 210, 0, 70), Position = UDim2.new(0.02, 0, 0.05, 168),
        BackgroundColor3 = Color3.fromRGB(20, 20, 25),
    }, UI.gui)

    UI.heightLabel = new("TextLabel", {
        Size = UDim2.new(0.9, 0, 0, 24), Position = UDim2.new(0.05, 0, 0, 6), BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBold, TextSize = 12,
        Text = "📏 Altura: 3.0",
    }, UI.height)

    local function hbtn(text, x, color)
        return new("TextButton", {
            Size = UDim2.new(0.43, 0, 0, 28), Position = UDim2.new(x, 0, 0, 34), BackgroundColor3 = color,
            TextColor3 = Color3.fromRGB(255, 255, 255), Text = text, TextSize = 14, Font = Enum.Font.GothamBold,
        }, UI.height)
    end
    UI.btnHDown = hbtn("▼ Baixar", 0.05, Color3.fromRGB(90, 60, 60))
    UI.btnHUp = hbtn("▲ Subir", 0.52, Color3.fromRGB(60, 90, 60))
end

local function changeHeight(delta)
    local newH = math.clamp(ST.camHeight + delta, 1, 15)
    local real = newH - ST.camHeight
    if real == 0 then return end
    ST.camHeight = newH
    UI.heightLabel.Text = string.format("📏 Altura: %.1f", ST.camHeight)

    local last = createdCams[#createdCams]
    if last and last.model.Parent then
        last.model:PivotTo(last.model:GetPivot() + Vector3.new(0, real, 0))
        buildPole(last)
        updateCable(last)
    end
end

UI.btnHDown.MouseButton1Click:Connect(function() changeHeight(-CFG.HEIGHT_STEP) end)
UI.btnHUp.MouseButton1Click:Connect(function() changeHeight(CFG.HEIGHT_STEP) end)

-- ----- Lista de câmeras: ON/OFF + excluir -----
do
    UI.delete = new("Frame", {
        Size = UDim2.new(0, 210, 0, 150), Position = UDim2.new(0.02, 0, 0.05, 248),
        BackgroundColor3 = Color3.fromRGB(20, 20, 25),
    }, UI.gui)

    new("TextLabel", {
        Size = UDim2.new(0.9, 0, 0, 22), Position = UDim2.new(0.05, 0, 0, 4), BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(255, 200, 120), Font = Enum.Font.GothamBold, TextSize = 11,
        Text = "📹 Câmeras: ON/OFF  •  🗑 excluir",
    }, UI.delete)

    UI.deleteList = new("ScrollingFrame", {
        Size = UDim2.new(0.9, 0, 0, 114), Position = UDim2.new(0.05, 0, 0, 28), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, UI.delete)

    new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, UI.deleteList)
end

local function refreshDeleteList()
    for _, child in ipairs(UI.deleteList:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end

    if #createdCams == 0 then
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(150, 150, 150),
            Font = Enum.Font.Gotham, TextSize = 11, Text = "Nenhuma câmera instalada",
        }, UI.deleteList)
        return
    end

    for i, c in ipairs(createdCams) do
        c.name = (c.isWired and "CAM-Fio-" or "CAM-WiFi-") .. i
        c.model.Name = c.name

        local row = new("Frame", {
            LayoutOrder = i, Size = UDim2.new(1, -6, 0, 26), BackgroundTransparency = 1,
        }, UI.deleteList)

        local tog = new("TextButton", {
            Size = UDim2.new(0, 50, 1, 0),
            BackgroundColor3 = c.enabled and Color3.fromRGB(30, 130, 50) or Color3.fromRGB(120, 35, 35),
            TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBold, TextSize = 11,
            Text = c.enabled and "ON" or "OFF",
        }, row)
        tog.MouseButton1Click:Connect(function()
            if FN.setCamEnabled then FN.setCamEnabled(c, not c.enabled) end
        end)

        local del = new("TextButton", {
            Position = UDim2.new(0, 54, 0, 0), Size = UDim2.new(1, -54, 1, 0),
            BackgroundColor3 = c.isWired and Color3.fromRGB(60, 80, 110) or Color3.fromRGB(0, 110, 75),
            TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBold, TextSize = 11,
            Text = "🗑 " .. i .. " - " .. (c.isWired and "Fio" or "Wi-Fi"),
        }, row)
        del.MouseButton1Click:Connect(function() FN.deleteCamera(i) end)
    end
end

-- ===================== DETECÇÃO DE MOVIMENTO =====================
do
    UI.alarm = new("Sound", {Volume = 0.8}, UI.gui)

    UI.sign = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 300, 0, 120), Position = UDim2.new(0.5, 0, 0, 10),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, Visible = false,
    }, UI.gui)
    new("UICorner", {CornerRadius = UDim.new(0, 14)}, UI.sign)
    UI.signStroke = new("UIStroke", {Thickness = 4, Color = CFG.BLACK}, UI.sign)

    local icon = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 38), Position = UDim2.new(0, 0, 0, 6), BackgroundTransparency = 1,
        TextColor3 = CFG.BLACK, Text = "📹 )))  ❗", TextSize = 28, Font = Enum.Font.GothamBlack,
    }, UI.sign)

    if CFG.ICON_IMAGE_ID ~= "" then
        icon.Text = ""
        new("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(42, 42), Position = UDim2.new(0.5, 0, 0, 4),
            BackgroundTransparency = 1, Image = CFG.ICON_IMAGE_ID,
        }, UI.sign)
    end

    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 46), BackgroundTransparency = 1,
        TextColor3 = CFG.BLACK, Text = "MOTION DETECTION", TextSize = 25, Font = Enum.Font.GothamBlack,
    }, UI.sign)

    UI.signInfo = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 90), BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(60, 60, 60), Text = "", TextSize = 13, Font = Enum.Font.Code,
    }, UI.sign)

    UI.alertBorder = new("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false}, UI.static)
    UI.borderStroke = new("UIStroke", {Thickness = 14, Color = CFG.RED}, UI.alertBorder)

    UI.trackBox = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false}, UI.static)
    new("UIStroke", {Thickness = 2, Color = CFG.RED}, UI.trackBox)
    UI.trackLabel = new("TextLabel", {
        Size = UDim2.new(0, 200, 0, 16), Position = UDim2.new(0.5, -100, 0, -18), BackgroundTransparency = 1,
        TextColor3 = CFG.RED, TextStrokeTransparency = 0, TextSize = 12, Font = Enum.Font.Code, Text = "",
    }, UI.trackBox)

    UI.motionMenu = new("Frame", {
        Size = UDim2.new(0, 210, 0, 44), Position = UDim2.new(0.02, 0, 0.05, 408),
        BackgroundColor3 = Color3.fromRGB(20, 20, 25),
    }, UI.gui)
    UI.btnMotionPanel = new("TextButton", {
        Size = UDim2.new(0.9, 0, 0, 28), Position = UDim2.new(0.05, 0, 0, 8),
        BackgroundColor3 = Color3.fromRGB(60, 50, 50), TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold, TextSize = 10, Text = "🚶 Detecção de Movimento: OFF",
    }, UI.motionMenu)
end

local function playAlarm()
    if CFG.ALARM_SOUND_ID == "" then return end
    if tick() - ST.lastAlarm < CFG.ALERT_HOLD then return end
    ST.lastAlarm = tick()
    UI.alarm.SoundId = CFG.ALARM_SOUND_ID
    UI.alarm:Play()
end

local function refreshMotionButtons()
    local txt = ST.motionOn and "🚶 Detecção de Movimento: ON" or "🚶 Detecção de Movimento: OFF"
    local col = ST.motionOn and Color3.fromRGB(150, 40, 40) or Color3.fromRGB(60, 50, 50)
    UI.btnMotion.Text = txt
    UI.btnMotion.BackgroundColor3 = col
    UI.btnMotionPanel.Text = txt
    UI.btnMotionPanel.BackgroundColor3 = col
end

local function resetMotion()
    ST.alertUntil = 0
    UI.sign.Visible = false
    UI.alertBorder.Visible = false
    UI.trackBox.Visible = false
    for _, c in ipairs(createdCams) do
        c.motionUntil = nil
        c.motionName = nil
        c.motionHRP = nil
        c.statusLed.Color = baseLed(c)
    end
end

local function setMotion(on)
    ST.motionOn = on
    if not on then resetMotion() end
    refreshMotionButtons()
end

UI.btnMotion.MouseButton1Click:Connect(function() setMotion(not ST.motionOn) end)
UI.btnMotionPanel.MouseButton1Click:Connect(function() setMotion(not ST.motionOn) end)

-- ----- Botão: Grade na TV ON/OFF (NOVO v13) -----
do
    UI.gridMenu = new("Frame", {
        Size = UDim2.new(0, 210, 0, 44), Position = UDim2.new(0.02, 0, 0.05, 462),
        BackgroundColor3 = Color3.fromRGB(20, 20, 25),
    }, UI.gui)
    UI.btnGridMode = new("TextButton", {
        Size = UDim2.new(0.9, 0, 0, 28), Position = UDim2.new(0.05, 0, 0, 8),
        BackgroundColor3 = Color3.fromRGB(30, 130, 50), TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold, TextSize = 11, Text = "🔲 Grade na TV: ON",
    }, UI.gridMenu)
    UI.btnGridMode.MouseButton1Click:Connect(function()
        ST.gridMode = not ST.gridMode
        UI.btnGridMode.Text = ST.gridMode and "🔲 Grade na TV: ON" or "📺 Tela velha (grade OFF)"
        UI.btnGridMode.BackgroundColor3 = ST.gridMode and Color3.fromRGB(30, 130, 50) or Color3.fromRGB(120, 70, 30)
        FN.toast(ST.gridMode and "🔲 Grade ligada" or "📺 Tela velha")
    end)
end

local function refreshNpcs()
    ST.npcCache = {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Humanoid") and d.Health > 0 then
            local model = d.Parent
            if model and model:IsA("Model")
                and not Players:GetPlayerFromCharacter(model)
                and not model:IsDescendantOf(folder) then
                local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                if hrp then
                    table.insert(ST.npcCache, {model = model, hrp = hrp, name = model.Name})
                end
            end
        end
    end
end

local function getSpeed(hrp, now)
    local pos = hrp.Position
    local rec = ST.lastPos[hrp]
    ST.lastPos[hrp] = {pos, now}
    if not rec then return 0 end
    local dt = now - rec[2]
    if dt <= 0 then return 0 end
    return (pos - rec[1]).Magnitude / dt
end

local function scanMotion()
    local now = tick()
    if CFG.DETECT_NPCS and now - ST.lastNpcRefresh > 3 then
        ST.lastNpcRefresh = now
        refreshNpcs()
    end

    local targets = {}
    if CFG.DETECT_PLAYERS then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player or CFG.DETECT_SELF then
                local char = plr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    table.insert(targets, {char = char, hrp = hrp, name = plr.DisplayName, speed = getSpeed(hrp, now)})
                end
            end
        end
    end
    if CFG.DETECT_NPCS then
        for _, n in ipairs(ST.npcCache) do
            if n.model.Parent and n.hrp.Parent then
                table.insert(targets, {char = n.model, hrp = n.hrp, name = n.name, speed = getSpeed(n.hrp, now)})
            end
        end
    end

    local cosLimit = math.cos(math.rad(CFG.MOTION_HALF_FOV))

    for _, c in ipairs(createdCams) do
        if not c.enabled then continue end

        local lensCF = c.lens.CFrame
        local look = lensCF.LookVector
        local found = nil

        for _, t in ipairs(targets) do
            if t.speed > CFG.MOTION_MIN_SPEED then
                local toTarget = t.hrp.Position - lensCF.Position
                local dist = toTarget.Magnitude
                if dist > 0.5 and dist <= CFG.MOTION_RANGE and look:Dot(toTarget.Unit) >= cosLimit then
                    local hit = Workspace:Raycast(lensCF.Position, toTarget, rayParams)
                    if hit == nil or hit.Instance:IsDescendantOf(t.char) then
                        found = t
                        break
                    end
                end
            end
        end

        if found then
            local isNew = (not c.motionUntil) or c.motionUntil < now
            c.motionUntil = now + CFG.ALERT_HOLD
            c.motionName = found.name
            c.motionHRP = found.hrp
            ST.alertUntil = now + CFG.ALERT_HOLD
            UI.signInfo.Text = c.name .. "  •  " .. found.name
            if isNew then playAlarm() end
        end

        if c.motionUntil and now < c.motionUntil then
            c.statusLed.Color = (math.floor(now * 4) % 2 == 0) and CFG.RED or c.ledColor
        else
            c.statusLed.Color = c.ledColor
        end
    end
end

-- ===================== GRADE MULTI-VIEW =====================
local function layoutFor(n)
    if n <= 1 then return 1, 1 end
    if n <= 4 then return 2, 2 end
    if n <= 9 then return 3, 3 end
    return 4, 4
end

local function clearGrid()
    for _, cell in ipairs(GRID.cells) do
        if cell.frame then cell.frame:Destroy() end
    end
    GRID.cells = {}
    GRID.count = 0
end

FN.gridClear = function()
    if GRID.count == 0 and #GRID.cells == 0 then return end
    clearGrid()
end

-- Libera o mundo e os avatares clonados de um quadrado
FN.releaseCell = function(cell)
    if cell.world then
        cell.world:Destroy()
        cell.world = nil
    end
    for m, e in pairs(cell.chars) do
        e.model:Destroy()
        cell.chars[m] = nil
    end
    cell.styleKey = nil
    cell.lastRefresh = 0
    cell.dbgMsg = "aguardando..."
end

local function buildGrid()
    clearGrid()
    local frame = ST.tvUI and ST.tvUI.grid
    if not frame then return end
    local n = math.min(#createdCams, CFG.GRID_MAX_CAMS)
    if n == 0 then return end

    local cols, rows = layoutFor(n)
    local gap = 4
    local cellW = (CFG.TV_W - gap * (cols + 1)) / cols
    local cellH = (CFG.TV_H - gap * (rows + 1)) / rows
    local labelH = math.clamp(math.floor(cellH * 0.13), 12, 28)

    for idx = 1, cols * rows do
        local r = math.floor((idx - 1) / cols)
        local c = (idx - 1) % cols

        local f = new("Frame", {
            Position = UDim2.fromOffset(gap + c * (cellW + gap), gap + r * (cellH + gap)),
            Size = UDim2.fromOffset(cellW, cellH), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BorderSizePixel = 0, ClipsDescendants = true,
        }, frame)

        local stroke = new("UIStroke", {Thickness = 1.5, Color = Color3.fromRGB(70, 75, 80)}, f)

        local cell = {
            frame = f, stroke = stroke, cam = nil, vp = nil, vcam = nil, rec = nil,
            off = nil, dbg = nil, dbgMsg = "aguardando...",
            world = nil, chars = {}, lastRefresh = 0, lastChars = 0, styleKey = nil,
        }

        local cam = createdCams[idx]
        if idx <= n and cam then
            cell.cam = cam

            local vp = new("ViewportFrame", {
                Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BorderSizePixel = 0,
                Ambient = Color3.fromRGB(150, 150, 155), LightColor = Color3.fromRGB(255, 255, 255),
                LightDirection = Vector3.new(-1, -2, -1),
            }, f)

            local vcam = new("Camera", {FieldOfView = CFG.FEED_FOV, CFrame = cam.lens.CFrame}, vp)
            vp.CurrentCamera = vcam

            new("TextLabel", {
                BackgroundTransparency = 1, Position = UDim2.new(0, 5, 1, -(labelH + 3)),
                Size = UDim2.fromOffset(cellW - 10, labelH), Text = "Canal " .. idx,
                TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 0.2, TextSize = labelH,
                Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
            }, f)

            local rec = new("TextLabel", {
                BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 2),
                Size = UDim2.fromOffset(labelH + 4, labelH + 2), Text = "●",
                TextColor3 = Color3.fromRGB(255, 40, 40), TextSize = labelH, Font = Enum.Font.Code, ZIndex = 5,
            }, f)

            local off = new("TextLabel", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "⏻ OFF",
                TextColor3 = Color3.fromRGB(120, 120, 120), TextSize = math.clamp(math.floor(cellH * 0.25), 14, 40),
                Font = Enum.Font.Code, ZIndex = 6, Visible = false,
            }, f)

            local dbg = new("TextLabel", {
                BackgroundTransparency = 1, Position = UDim2.new(0, 5, 0, 2),
                Size = UDim2.fromOffset(cellW - labelH - 14, labelH * 3), Text = "",
                TextColor3 = Color3.fromRGB(255, 255, 0), TextStrokeTransparency = 0.4,
                TextSize = math.max(labelH - 2, 10), Font = Enum.Font.Code, TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                ZIndex = 7, Visible = CFG.DEBUG,
            }, f)

            cell.vp, cell.vcam, cell.rec, cell.off, cell.dbg = vp, vcam, rec, off, dbg
        end
        GRID.cells[idx] = cell
    end
    GRID.count = n
end

local function gridMatches()
    local n = math.min(#createdCams, CFG.GRID_MAX_CAMS)
    if GRID.count ~= n then return false end
    for i = 1, n do
        local cell = GRID.cells[i]
        if not cell or cell.cam ~= createdCams[i] then return false end
    end
    return true
end

-- Tira uma "foto" do mundo ao redor da câmera (peças mais próximas primeiro)
local function snapshotCell(cell, now)
    local cam = cell.cam
    if not cam or not cam.model.Parent then return end

    local n = math.max(GRID.count, 1)
    local budget = math.clamp(math.floor(CFG.FEED_PART_BUDGET / n), 150, 600)
    local camPos = cam.lens.Position

    local ignore = {folder}
    for _, m in ipairs(GRID.charModels) do table.insert(ignore, m) end

    local op = OverlapParams.new()
    op.FilterType = Enum.RaycastFilterType.Exclude
    op.FilterDescendantsInstances = ignore
    op.MaxParts = 4000

    local found = Workspace:GetPartBoundsInRadius(camPos, CFG.FEED_RADIUS, op)

    local list = {}
    for _, part in ipairs(found) do
        if part:IsA("BasePart") and not part:IsA("Terrain") and part.Transparency < 1
            and part.Size.Magnitude >= 0.35 then
            local score = (part.Position - camPos).Magnitude - part.Size.Magnitude * 0.5
            table.insert(list, {part, score})
        end
    end

    -- Busca alternativa (mais lenta) se a consulta espacial não achou nada
    if #list == 0 then
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("BasePart") and not d:IsA("Terrain") and d.Transparency < 1
                and not d:IsDescendantOf(folder) then
                local dist = (d.Position - camPos).Magnitude
                if dist <= CFG.FEED_RADIUS then
                    local isChar = false
                    for _, m in ipairs(GRID.charModels) do
                        if d:IsDescendantOf(m) then isChar = true break end
                    end
                    if not isChar then table.insert(list, {d, dist}) end
                end
            end
        end
    end

    table.sort(list, function(a, b) return a[2] < b[2] end)

    local newWorld = Instance.new("Folder")
    newWorld.Name = "Mundo"
    local count = 0
    for _, item in ipairs(list) do
        if count >= budget then break end
        local c = safeClone(item[1])
        if c then
            for _, ch in ipairs(c:GetDescendants()) do
                if ch:IsA("LuaSourceContainer") or ch:IsA("Sound") then ch:Destroy() end
            end
            c.Anchored = true
            c.Parent = newWorld
            count += 1
        end
    end

    cell.dbgMsg = "peças: " .. count .. "/" .. #list

    if count == 0 and now - GRID.lastWarn > 3 then
        GRID.lastWarn = now
        warn("[TuboCAM] nenhuma peça clonada (encontradas: " .. #found .. ")")
    end

    newWorld.Parent = cell.vp
    if cell.world then cell.world:Destroy() end
    cell.world = newWorld
    cell.lastRefresh = now
    cell.styleKey = nil
end

-- Clone de personagem SEM física: só visual
local function makeCharClone(model)
    local c = safeClone(model)
    if not c then return nil end

    local links = {}
    local od, cd = model:GetDescendants(), c:GetDescendants()
    if #od == #cd then
        for i, o in ipairs(od) do
            local k = cd[i]
            if o:IsA("BasePart") and k:IsA("BasePart") and o.Name == k.Name then
                table.insert(links, {o, k})
            end
        end
    end

    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("LuaSourceContainer") or d:IsA("Sound")
            or d:IsA("BodyMover") or d:IsA("Constraint")
            or d:IsA("Animator") or d:IsA("Humanoid")
            or d:IsA("ForceField") or d:IsA("BillboardGui") then
            d:Destroy()
        elseif d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
            d.CanTouch = false
            d.CanQuery = false
            d.Massless = true
            d.AssemblyLinearVelocity = Vector3.zero
            d.AssemblyAngularVelocity = Vector3.zero
        end
    end

    return c, links
end

local function syncChars(cell)
    local lens = cell.cam.lens
    local pos = lens.Position
    local look = lens.CFrame.LookVector
    local seen = {}
    local count = 0

    for _, model in ipairs(GRID.charModels) do
        if count >= CFG.MAX_CHARS then break end
        if model.Parent then
            local pivot = model:GetPivot()
            local d = pivot.Position - pos
            local dist = d.Magnitude
            if dist > 0.5 and dist <= CFG.FEED_RADIUS and look:Dot(d.Unit) > 0.2 then
                seen[model] = true
                count += 1
                local entry = cell.chars[model]
                if not entry then
                    local c, links = makeCharClone(model)
                    if c then
                        entry = {model = c, links = links}
                        cell.chars[model] = entry
                        c.Parent = cell.vp
                    end
                end
                if entry then
                    if #entry.links > 0 then
                        for _, pr in ipairs(entry.links) do
                            if pr[1].Parent and pr[2].Parent then pr[2].CFrame = pr[1].CFrame end
                        end
                    else
                        entry.model:PivotTo(pivot)
                    end
                end
            end
        end
    end

    for model, entry in pairs(cell.chars) do
        if not seen[model] then
            entry.model:Destroy()
            cell.chars[model] = nil
        end
    end
end

local function styleCell(cell)
    local dark = isDark() and not cell.cam.lightOn
    local key = (cell.world ~= nil and "w" or "n") .. (dark and "d" or "l")
    if cell.styleKey == key then return end
    cell.styleKey = key
    if not cell.world then
        cell.vp.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    elseif dark then
        cell.vp.BackgroundColor3 = Color3.fromRGB(20, 40, 28)
        cell.vp.Ambient = Color3.fromRGB(140, 160, 140)
        cell.vp.ImageColor3 = Color3.fromRGB(175, 255, 175)
    else
        cell.vp.BackgroundColor3 = Color3.fromRGB(135, 180, 230)
        cell.vp.Ambient = Color3.fromRGB(150, 150, 155)
        cell.vp.ImageColor3 = Color3.fromRGB(255, 255, 255)
    end
end

FN.gridUpdate = function(now, visible)
    if not ST.tvUI or not ST.tvUI.grid then return end
    if not gridMatches() then buildGrid() end
    if GRID.count == 0 then return end

    if CFG.GRID_SHOW_NPCS and now - GRID.lastNpc > 3 then
        GRID.lastNpc = now
        refreshNpcs()
    end
    if now - GRID.lastChars > 0.2 then
        GRID.lastChars = now
        local list = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then table.insert(list, plr.Character) end
        end
        if CFG.GRID_SHOW_NPCS then
            for _, n in ipairs(ST.npcCache) do
                if n.model.Parent then table.insert(list, n.model) end
            end
        end
        GRID.charModels = list
    end

    local pick, filling = nil, false
    for _, cell in ipairs(GRID.cells) do
        if cell.cam and cell.cam.enabled and not cell.world then
            pick = cell
            filling = true
            break
        end
    end
    if not pick then
        local oldest = now - CFG.FEED_REFRESH
        for _, cell in ipairs(GRID.cells) do
            if cell.cam and cell.cam.enabled and cell.lastRefresh < oldest then
                pick = cell
                oldest = cell.lastRefresh
            end
        end
    end
    if pick and now - GRID.lastSnap > (filling and 0.12 or 0.4) then
        GRID.lastSnap = now
        local ok, err = pcall(snapshotCell, pick, now)
        if not ok then
            pick.lastRefresh = now
            pick.dbgMsg = "ERRO: " .. string.sub(tostring(err), 1, 60)
            if now - GRID.lastWarn > 3 then
                GRID.lastWarn = now
                warn("[TuboCAM] erro no feed: " .. tostring(err))
            end
        end
    end

    local blink = (math.floor(now * 2) % 2 == 0)
    for _, cell in ipairs(GRID.cells) do
        local cam = cell.cam
        if cam and cam.model.Parent then
            if not cam.enabled then
                if cell.world or next(cell.chars) ~= nil then FN.releaseCell(cell) end
                cell.vp.Visible = false
                cell.off.Visible = true
                cell.rec.TextTransparency = 1
                cell.stroke.Color = Color3.fromRGB(70, 75, 80)
                cell.stroke.Thickness = 1.5
                if cell.dbg.Text ~= "OFF" then cell.dbg.Text = "OFF" end
            else
                cell.vp.Visible = true
                cell.off.Visible = false
                cell.vcam.CFrame = cam.lens.CFrame
                styleCell(cell)
                if cam.motionUntil and now < cam.motionUntil then
                    cell.stroke.Color = blink and CFG.RED or Color3.fromRGB(70, 75, 80)
                    cell.stroke.Thickness = 3
                else
                    cell.stroke.Color = Color3.fromRGB(70, 75, 80)
                    cell.stroke.Thickness = 1.5
                end
                cell.rec.TextTransparency = blink and 0 or 1
                if visible and now - cell.lastChars > CFG.CHAR_INTERVAL then
                    cell.lastChars = now
                    local ok, err = pcall(syncChars, cell)
                    if not ok and now - GRID.lastWarn > 3 then
                        GRID.lastWarn = now
                        warn("[TuboCAM] erro avatares: " .. tostring(err))
                    end
                end
                if cell.dbg.Text ~= cell.dbgMsg then cell.dbg.Text = cell.dbgMsg end
            end
        end
    end
end

-- ===================== FECHAR / ABRIR GUI =====================
UI.panels = {UI.control, UI.height, UI.delete, UI.motionMenu, UI.gridMenu}

UI.btnToggle = new("TextButton", {
    Size = UDim2.new(0, 100, 0, 28), Position = UDim2.new(0.02, 220, 0.05, 0),
    BackgroundColor3 = Color3.fromRGB(70, 70, 80), TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold, TextSize = 11, Text = "✖ Fechar GUI",
}, UI.gui)

local function applyPanels()
    for _, p in ipairs(UI.panels) do
        p.Visible = ST.panelsOpen and not ST.viewing
    end
    UI.btnToggle.Visible = not ST.viewing
    UI.btnToggle.Text = ST.panelsOpen and "✖ Fechar GUI" or "☰ Abrir GUI"
end

UI.btnToggle.MouseButton1Click:Connect(function()
    ST.panelsOpen = not ST.panelsOpen
    applyPanels()
end)

-- ===================== JANELA DO FIO =====================
do
    UI.cableMenu = new("Frame", {
        Size = UDim2.new(0, 210, 0, 175), Position = UDim2.new(0.5, -105, 0.35, 0),
        BackgroundColor3 = Color3.fromRGB(20, 20, 25), Visible = false,
    }, UI.gui)
    new("UICorner", {CornerRadius = UDim.new(0, 8)}, UI.cableMenu)

    UI.cableTitle = new("TextLabel", {
        Size = UDim2.new(0.9, 0, 0, 24), Position = UDim2.new(0.05, 0, 0, 6), BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBold, TextSize = 12,
        Text = "🔌 Qual fio?",
    }, UI.cableMenu)

    local function cableBtn(text, y, mode, color)
        local b = new("TextButton", {
            Size = UDim2.new(0.9, 0, 0, 28), Position = UDim2.new(0.05, 0, 0, y), BackgroundColor3 = color,
            TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBold, TextSize = 12, Text = text,
        }, UI.cableMenu)
        b.MouseButton1Click:Connect(function()
            if mode and ST.cableTarget and ST.cableTarget.model.Parent then
                ST.cableTarget.cableMode = mode
                updateCable(ST.cableTarget)
            end
            UI.cableMenu.Visible = false
        end)
    end

    cableBtn("⬆ Cima (teto)", 34, "cima", Color3.fromRGB(60, 80, 110))
    cableBtn("⬇ Baixo (chão)", 68, "baixo", Color3.fromRGB(60, 80, 110))
    cableBtn("🧱 Parede", 102, "parede", Color3.fromRGB(60, 80, 110))
    cableBtn("✖ Fechar", 136, nil, Color3.fromRGB(90, 60, 60))
end

FN.openCableMenu = function(c)
    ST.cableTarget = c
    UI.cableTitle.Text = "🔌 Fio da " .. c.name
    UI.cableMenu.Visible = true
end

-- ===================== LEDs IR =====================
local function updateIR()
    local dark = isDark()
    for _, c in ipairs(createdCams) do
        local forced = ST.viewing and ST.nightVision and c == ST.currentCamData
        setIR(c, c.enabled and (dark or forced))
    end
end

-- ===================== 5. VISUALIZAÇÃO =====================
local function setViewUI(on)
    UI.hud.Visible = on
    UI.btnNight.Visible = on
    UI.btnMotion.Visible = on
    UI.btnLight.Visible = on
    UI.static.Visible = on
    UI.rec.Visible = on
    UI.time.Visible = on
    if on then UI.cableMenu.Visible = false end
    applyPanels()
end

local function startViewing()
    if not ST.activeTVScreen then return end
    if not tvLinked() or not ST.nvrOn then
        FN.toast("📼 Sem sinal (AV1) — ligue o NVR e os cabos")
        return
    end
    if not nvrReady() then
        FN.toast("📼 NVR iniciando... aguarde")
        return
    end
    if #createdCams == 0 then
        FN.toast("📹 Nenhuma câmera instalada")
        return
    end
    local idx = nextEnabled(ST.camIndex)
    if not idx then
        FN.toast("📹 Todas as câmeras estão OFF")
        return
    end
    ST.camIndex = idx
    ST.viewing = true
    ST.currentCamData = createdCams[idx]
    refreshLightButton()
    camera.CameraType = Enum.CameraType.Scriptable
    UI.nightEffect.Enabled = ST.nightVision
    setViewUI(true)
    updateIR()
end

local function stopViewing()
    ST.viewing = false
    camera.CameraType = Enum.CameraType.Custom
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum then camera.CameraSubject = hum end
    UI.nightEffect.Enabled = false
    setViewUI(false)
    updateIR()
end

-- Liga/desliga uma câmera
FN.setCamEnabled = function(c, on)
    if c.enabled == on then return end
    c.enabled = on
    c.statusLed.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
    c.statusLed.Color = baseLed(c)

    if not on then
        c.motionUntil, c.motionName, c.motionHRP = nil, nil, nil
        if c.lightOn then
            c.lightOn = false
            c.camLight.Enabled = false
        end
        for _, cell in ipairs(GRID.cells) do
            if cell.cam == c then FN.releaseCell(cell) end
        end
        if ST.viewing and ST.currentCamData == c then
            local idx = nextEnabled(ST.camIndex)
            if idx then
                ST.camIndex = idx
                ST.currentCamData = createdCams[idx]
                refreshLightButton()
            else
                stopViewing()
                FN.toast("📹 Todas as câmeras estão OFF")
            end
        end
    end

    updateIR()
    refreshDeleteList()
end

FN.deleteCamera = function(i)
    local c = createdCams[i]
    if not c then return end

    local wasViewingThis = ST.viewing and ST.currentCamData == c
    if ST.cableTarget == c then
        ST.cableTarget = nil
        UI.cableMenu.Visible = false
    end
    c.model:Destroy()
    table.remove(createdCams, i)

    if ST.camIndex > i then ST.camIndex = ST.camIndex - 1 end
    if ST.camIndex > #createdCams then ST.camIndex = 1 end
    if ST.camIndex < 1 then ST.camIndex = 1 end

    if ST.viewing then
        if #createdCams == 0 then
            stopViewing()
        elseif wasViewingThis then
            local idx = nextEnabled(ST.camIndex)
            if idx then
                ST.camIndex = idx
                ST.currentCamData = createdCams[idx]
                refreshLightButton()
            else
                stopViewing()
                FN.toast("📹 Todas as câmeras estão OFF")
            end
        end
    end

    refreshDeleteList()
end

-- ===================== 6. EVENTOS =====================
UI.btnTV.MouseButton1Click:Connect(function()
    if ST.viewing then stopViewing() end
    local tv = createRetroTV(rootPart.CFrame * CFrame.new(0, -1, -5))
    attachTVNoise(tv.TVScreen)
    tv.TVScreen.ClickDetector.MouseClick:Connect(startViewing)
    updateRCA()
end)

UI.btnNVR.MouseButton1Click:Connect(function()
    if ST.viewing then stopViewing() end
    createNVR(rootPart.CFrame * CFrame.new(-6, -1, -5))
    updateRCA()
    for _, c in ipairs(createdCams) do updateCable(c) end
end)

UI.btnWifi.MouseButton1Click:Connect(function()
    local num = #createdCams + 1
    local cf, onWall = getCameraSpawnCFrame()
    table.insert(createdCams, createCameraModel("CAM-WiFi-" .. num, cf, false, not onWall))
    refreshDeleteList()
end)

UI.btnWired.MouseButton1Click:Connect(function()
    local num = #createdCams + 1
    local cf, onWall = getCameraSpawnCFrame()
    table.insert(createdCams, createCameraModel("CAM-Fio-" .. num, cf, true, not onWall))
    refreshDeleteList()
end)

UI.btnNext.MouseButton1Click:Connect(function()
    local n = #createdCams
    if n > 0 then
        local idx = nextEnabled(ST.camIndex % n + 1)
        if idx then
            ST.camIndex = idx
            ST.currentCamData = createdCams[idx]
            refreshLightButton()
            updateIR()
        end
    end
end)

UI.btnExit.MouseButton1Click:Connect(stopViewing)

UI.btnNight.MouseButton1Click:Connect(function()
    ST.nightVision = not ST.nightVision
    UI.nightEffect.Enabled = ST.viewing and ST.nightVision
    UI.btnNight.Text = ST.nightVision and "🌙 Visão Noturna: ON" or "🌙 Visão Noturna: OFF"
    UI.btnNight.BackgroundColor3 = ST.nightVision and Color3.fromRGB(30, 120, 40) or Color3.fromRGB(35, 50, 35)
    updateIR()
end)

refreshDeleteList()
refreshMotionButtons()
applyPanels()

-- ===================== 7. LOOP PRINCIPAL =====================
RunService.RenderStepped:Connect(function(dt)
    updateTVScreen()
    updateNVRLeds()

    -- Logo quicando na TV (só na tela velha)
    local logo = ST.tvLogo
    if logo and logo.Parent and logo.Visible then
        ST.logoX = ST.logoX + ST.logoVX * dt
        ST.logoY = ST.logoY + ST.logoVY * dt
        local bounced = false

        if ST.logoX <= 0 then
            ST.logoX = 0
            ST.logoVX = math.abs(ST.logoVX)
            bounced = true
        elseif ST.logoX + CFG.LOGO_W >= CFG.TV_W then
            ST.logoX = CFG.TV_W - CFG.LOGO_W
            ST.logoVX = -math.abs(ST.logoVX)
            bounced = true
        end

        if ST.logoY <= 0 then
            ST.logoY = 0
            ST.logoVY = math.abs(ST.logoVY)
            bounced = true
        elseif ST.logoY + CFG.LOGO_H >= CFG.TV_H then
            ST.logoY = CFG.TV_H - CFG.LOGO_H
            ST.logoVY = -math.abs(ST.logoVY)
            bounced = true
        end

        if bounced then logo.TextColor3 = Color3.fromHSV(math.random(), 0.8, 1) end
        logo.Position = UDim2.fromOffset(ST.logoX, ST.logoY)
    end

    if tick() - ST.lastIR > 0.25 then
        ST.lastIR = tick()
        updateIR()
    end

    if ST.motionOn and tick() - ST.lastScan > 0.2 then
        ST.lastScan = tick()
        scanMotion()
    end

    local showSign = ST.motionOn and tick() < ST.alertUntil
    UI.sign.Visible = showSign
    if showSign then
        UI.signStroke.Color = (math.floor(tick() * 3) % 2 == 0) and CFG.RED or CFG.BLACK
    end

    local cd = ST.currentCamData
    if not ST.viewing or not cd then return end

    if not ST.activeTVScreen or not ST.activeTVScreen.Parent then
        stopViewing()
        return
    end

    if not nvrReady() then
        stopViewing()
        FN.toast("📼 NVR desligado — sem sinal (AV1)")
        return
    end

    camera.CFrame = cd.lens.CFrame

    -- Borda vermelha + caixa seguindo quem se mexe
    local tracking = ST.motionOn and cd.motionUntil and tick() < cd.motionUntil
        and cd.motionHRP and cd.motionHRP.Parent
    UI.alertBorder.Visible = tracking and true or false
    UI.trackBox.Visible = false
    if tracking then
        UI.borderStroke.Transparency = (math.floor(tick() * 3) % 2 == 0) and 0 or 0.6
        local hrpPos = cd.motionHRP.Position
        local screenPos, onScreen = camera:WorldToViewportPoint(hrpPos)
        if onScreen then
            local inset = GuiService:GetGuiInset()
            local vpSize = camera.ViewportSize
            local dist = (hrpPos - camera.CFrame.Position).Magnitude
            local h = 5.5 / (2 * dist * math.tan(math.rad(camera.FieldOfView / 2))) * vpSize.Y
            h = math.clamp(h, 40, 500)
            UI.trackBox.Size = UDim2.fromOffset(h * 0.5, h)
            UI.trackBox.Position = UDim2.fromOffset(screenPos.X - inset.X, screenPos.Y - inset.Y)
            UI.trackLabel.Text = "⚠ MOVIMENTO • " .. (cd.motionName or "?")
            UI.trackBox.Visible = true
        end
    end

    UI.time.Text = cd.name .. "\n" .. os.date("%d/%m/%Y  %H:%M:%S")
    UI.time.TextColor3 = ST.nightVision and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(230, 230, 230)
    UI.rec.TextTransparency = (math.floor(tick() * 2) % 2 == 0) and 0 or 1

    local vp = camera.ViewportSize
    local intensity, bars, noSignal = 0, 0, false
    local sMin, sMax, alphaMin = 2, 6, 0.5

    if cd.isWired then
        UI.signal.Text = "🔌 CABO DE VÍDEO: 100% (ESTÁVEL)"
        UI.signal.TextColor3 = Color3.fromRGB(0, 255, 150)
        UI.static.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        UI.static.BackgroundTransparency = 0.98
    else
        local origin = cd.lens.Position
        local target = ST.nvrBody.Position
        local dist = (target - origin).Magnitude
        local signal = 100 - (dist * CFG.SIGNAL_LOSS)

        local blocked = Workspace:Raycast(origin, target - origin, rayParams) ~= nil
        if blocked then signal = signal - CFG.WALL_PENALTY end
        signal = math.clamp(signal, 0, 100)
        local wallTag = blocked and " 🧱" or ""

        if signal > 60 then
            UI.signal.Text = "📶 WI-FI: " .. math.floor(signal) .. "% (BOM)" .. wallTag
            UI.signal.TextColor3 = Color3.fromRGB(0, 255, 100)
            UI.static.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            UI.static.BackgroundTransparency = 0.97
            intensity = 0.04
        elseif signal > 25 then
            local weak = 1 - (signal - 25) / 35
            UI.signal.Text = "⚠️ WI-FI: " .. math.floor(signal) .. "% (FRACO)" .. wallTag
            UI.signal.TextColor3 = Color3.fromRGB(255, 180, 0)
            UI.static.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            UI.static.BackgroundTransparency = 0.88 - weak * 0.15
            intensity = 0.15 + weak * 0.45
            bars = math.floor(1 + weak * 2)
            sMin, sMax, alphaMin = 3, 10, 0.35
        else
            UI.signal.Text = "🚫 WI-FI: " .. math.floor(signal) .. "% (SEM SINAL)" .. wallTag
            UI.signal.TextColor3 = Color3.fromRGB(255, 50, 50)
            UI.static.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            UI.static.BackgroundTransparency = 0.1
            intensity = 1
            bars = 6
            sMin, sMax, alphaMin = 6, 22, 0.05
            noSignal = true
        end
    end

    UI.screenNoise(intensity, vp.X, vp.Y, sMin, sMax, alphaMin)

    for i, bar in ipairs(UI.bars) do
        if i <= bars then
            bar.Position = UDim2.new(0, 0, math.random(), 0)
            bar.Size = UDim2.new(1, 0, 0, math.random(2, 14))
            bar.BackgroundTransparency = 0.5 + math.random() * 0.4
            bar.Visible = true
        else
            bar.Visible = false
        end
    end

    UI.noSignal.Visible = noSignal
    if noSignal then
        UI.noSignal.Position = UDim2.new(0.5, math.random(-4, 4), 0.5, math.random(-3, 3))
        UI.noSignal.TextTransparency = (math.floor(tick() * 3) % 2 == 0) and 0 or 0.35
    end
end)

print("TuboCAM v13 ativado!")
