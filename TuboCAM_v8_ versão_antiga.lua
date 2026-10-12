-- // Delta Executor - CCTV v9 (completo)
-- Câmera bullet, TV com logo quicando, parede + altura, chuvisco/SEM SINAL, excluir câmera,
-- GUI fecha ao clicar na TV, visão noturna, DETECÇÃO DE MOVIMENTO
-- v7: poste quando não tem parede, clicar na cam com fio escolhe o fio (cima/baixo/parede),
--     cabo corrigido, sinal Wi-Fi com mais alcance
-- v8: botão de luz da câmera (💡)
-- v9: detecção de movimento também para NPCs (configurável)

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
if Workspace:FindFirstChild("CCTVRetroFolder") then
    Workspace.CCTVRetroFolder:Destroy()
end
if player.PlayerGui:FindFirstChild("RetroTVGui") then
    player.PlayerGui.RetroTVGui:Destroy()
end
if Lighting:FindFirstChild("CCTVNightVision") then
    Lighting.CCTVNightVision:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = "CCTVRetroFolder"
folder.Parent = Workspace

local createdCams = {}
local camIndex = 1
local activeTV = nil
local activeTVScreen = nil
local currentCamData = nil
local viewing = false

-- Raycast (ignora as peças do CCTV e o jogador)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = {folder, character}

local WALL_PENALTY = 15   -- % de sinal perdido por haver parede no caminho
local SIGNAL_LOSS = 0.25  -- % de sinal perdido por stud (menor = mais alcance)

-- Filtro de visão noturna (só liga enquanto você assiste)
local nightVision = false
local nightEffect = Instance.new("ColorCorrectionEffect")
nightEffect.Name = "CCTVNightVision"
nightEffect.TintColor = Color3.fromRGB(110, 255, 110)
nightEffect.Brightness = 0.12
nightEffect.Contrast = 0.25
nightEffect.Saturation = -0.85
nightEffect.Enabled = false
nightEffect.Parent = Lighting

-- ===================== 1. TV ANTIGA =====================
local function createRetroTV(cframe)
    if activeTV then activeTV:Destroy() end

    local origin = cframe.Position + Vector3.new(0, 3, 0)
    local hit = Workspace:Raycast(origin, Vector3.new(0, -30, 0), rayParams)
    local groundY = hit and hit.Position.Y or (cframe.Position.Y - 3)
    local _, yaw, _ = cframe:ToOrientation()
    local base = CFrame.new(cframe.Position.X, groundY, cframe.Position.Z) * CFrame.Angles(0, yaw + math.pi, 0)

    local tvModel = Instance.new("Model")
    tvModel.Name = "TV_Antiga_CCTV"
    tvModel.Parent = folder

    local woodDark = Color3.fromRGB(40, 28, 20)
    local black = Color3.fromRGB(20, 20, 20)

    for _, sx in ipairs({-1.5, 1.5}) do
        for _, sz in ipairs({-0.6, 0.6}) do
            local leg = Instance.new("Part")
            leg.Size = Vector3.new(0.2, 0.9, 0.2)
            leg.CFrame = base * CFrame.new(sx, 0.45, sz)
            leg.Color = woodDark
            leg.Material = Enum.Material.Wood
            leg.Anchored = true
            leg.CanCollide = false
            leg.Parent = tvModel
        end
    end

    local body = Instance.new("Part")
    body.Name = "TVBody"
    body.Size = Vector3.new(3.8, 2.6, 1.8)
    body.CFrame = base * CFrame.new(0, 2.2, 0)
    body.Color = Color3.fromRGB(60, 45, 35)
    body.Material = Enum.Material.Wood
    body.Anchored = true
    body.Parent = tvModel

    local screen = Instance.new("Part")
    screen.Name = "TVScreen"
    screen.Size = Vector3.new(2.4, 1.9, 0.1)
    screen.CFrame = body.CFrame * CFrame.new(0.4, 0, -0.86)
    screen.Color = Color3.fromRGB(20, 30, 25)
    screen.Material = Enum.Material.Glass
    screen.Anchored = true
    screen.Parent = tvModel

    for _, y in ipairs({0.5, -0.1}) do
        local knob = Instance.new("Part")
        knob.Shape = Enum.PartType.Ball
        knob.Size = Vector3.new(0.3, 0.3, 0.3)
        knob.CFrame = body.CFrame * CFrame.new(-1.35, y, -0.92)
        knob.Color = Color3.fromRGB(170, 170, 170)
        knob.Material = Enum.Material.Metal
        knob.Anchored = true
        knob.CanCollide = false
        knob.Parent = tvModel
    end

    for _, side in ipairs({-1, 1}) do
        local ear = Instance.new("Part")
        ear.Size = Vector3.new(0.06, 1.4, 0.06)
        ear.CFrame = body.CFrame * CFrame.new(0, 1.3, 0)
            * CFrame.Angles(0, 0, math.rad(side * 25))
            * CFrame.new(0, 0.7, 0)
        ear.Color = black
        ear.Material = Enum.Material.Metal
        ear.Anchored = true
        ear.CanCollide = false
        ear.Parent = tvModel
    end

    local clicker = Instance.new("ClickDetector")
    clicker.MaxActivationDistance = 15
    clicker.Parent = screen

    tvModel.PrimaryPart = screen
    activeTV = tvModel
    activeTVScreen = screen
    return tvModel
end

-- ===================== 2. CABO (câmeras com fio) =====================
-- Modos: "baixo" (chão), "cima" (teto), "parede" (reto na altura da câmera)
local function cableSeg(parent, a, b)
    local d = (a - b).Magnitude
    if d < 0.05 then return end
    local p = Instance.new("Part")
    p.Size = Vector3.new(0.06, 0.06, d)
    p.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -d / 2)
    p.Color = Color3.fromRGB(20, 20, 20)
    p.Material = Enum.Material.Rubber
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.Parent = parent
end

local function updateCable(camData)
    if camData.cable then camData.cable:Destroy() camData.cable = nil end
    if not camData.isWired or not activeTVScreen then return end

    local cable = Instance.new("Model")
    cable.Name = "Cabo"
    cable.Parent = camData.model

    -- sai da placa de parede da câmera
    local from = (camData.lens.CFrame * CFrame.new(0, -0.55, 1.79)).Position
    local tvPos = activeTVScreen.Position
    local tvTop = tvPos + Vector3.new(0, 1.3, 0)
    local mode = camData.cableMode

    if mode == "cima" then
        local up = Workspace:Raycast(from, Vector3.new(0, 300, 0), rayParams)
        local y = up and up.Position.Y - 0.05 or from.Y + 4
        local a = Vector3.new(from.X, y, from.Z)
        local b = Vector3.new(tvPos.X, y, tvPos.Z)
        cableSeg(cable, from, a)
        cableSeg(cable, a, b)
        cableSeg(cable, b, tvTop)
    elseif mode == "parede" then
        local b = Vector3.new(tvPos.X, from.Y, tvPos.Z)
        cableSeg(cable, from, b)
        cableSeg(cable, b, tvTop)
    else -- "baixo"
        local function floorY(pos)
            local hit = Workspace:Raycast(pos, Vector3.new(0, -300, 0), rayParams)
            return hit and hit.Position.Y + 0.05 or pos.Y
        end
        local a = Vector3.new(from.X, floorY(from), from.Z)
        local b = Vector3.new(tvPos.X, floorY(tvPos), tvPos.Z)
        cableSeg(cable, from, a)
        cableSeg(cable, a, b)
        cableSeg(cable, b, tvPos - Vector3.new(0, 1, 0))
    end

    camData.cable = cable
end

-- ===================== 3. CÂMERAS (modelo bullet + LEDs IR + poste + luz) =====================
local function isDark()
    local t = Lighting.ClockTime
    return t < 5.5 or t > 18.5
end

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

-- Poste de suporte (só quando a câmera não está presa numa parede)
local function buildPole(camData)
    if camData.pole then camData.pole:Destroy() camData.pole = nil end
    if not camData.hasPole then return end

    local base = (camData.lens.CFrame * CFrame.new(0, -0.55, 1.79)).Position
    local hit = Workspace:Raycast(base, Vector3.new(0, -300, 0), rayParams)
    local gy = hit and hit.Position.Y or (base.Y - 3)
    local h = math.max(base.Y - gy, 0.2)
    local gray = Color3.fromRGB(70, 70, 75)

    local pole = Instance.new("Model")
    pole.Name = "Poste"
    pole.Parent = camData.model

    local function cyl(size, cf)
        local p = Instance.new("Part")
        p.Shape = Enum.PartType.Cylinder
        p.Size = size
        p.CFrame = cf
        p.Color = gray
        p.Material = Enum.Material.Metal
        p.Anchored = true
        p.CanCollide = false
        p.Parent = pole
    end

    local upright = CFrame.Angles(0, 0, math.rad(90)) -- cilindro em pé
    cyl(Vector3.new(h, 0.3, 0.3), CFrame.new(base.X, gy + h / 2, base.Z) * upright)
    cyl(Vector3.new(0.15, 1.6, 1.6), CFrame.new(base.X, gy + 0.075, base.Z) * upright)

    camData.pole = pole
end

local openCableMenu -- definida mais abaixo (precisa da interface)

local function createCameraModel(name, cframe, isWired, hasPole)
    local model = Instance.new("Model")
    model.Name = name
    model.Parent = folder

    local BLOCK, BALL, CYL = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
    local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)

    local bodyColor = isWired and Color3.fromRGB(55, 55, 60) or Color3.fromRGB(238, 238, 242)
    local ledColor = isWired and Color3.fromRGB(255, 170, 0) or Color3.fromRGB(0, 255, 150)
    local black = Color3.fromRGB(25, 25, 28)

    local function mk(shape, size, cf, color, material, transparency)
        local p = Instance.new("Part")
        p.Shape = shape
        p.Size = size
        p.CFrame = cf
        p.Color = color
        p.Material = material or Enum.Material.SmoothPlastic
        p.Transparency = transparency or 0
        p.Anchored = true
        p.CanCollide = false
        p.Parent = model
        return p
    end

    -- Corpo cilíndrico
    local body = mk(CYL, Vector3.new(1.8, 0.8, 0.8), cframe * ALONG_Z, bodyColor)
    -- Faixa azul
    mk(CYL, Vector3.new(0.08, 0.82, 0.82), cframe * CFrame.new(0, 0, -0.65) * ALONG_Z, Color3.fromRGB(30, 70, 160))
    -- Anel frontal escuro
    mk(CYL, Vector3.new(0.12, 0.82, 0.82), cframe * CFrame.new(0, 0, -0.9) * ALONG_Z, black)
    -- Vidro da lente
    mk(CYL, Vector3.new(0.08, 0.38, 0.38), cframe * CFrame.new(0, 0, -0.95) * ALONG_Z, Color3.fromRGB(10, 20, 45), Enum.Material.Glass)
    -- Quebra-sol
    mk(BLOCK, Vector3.new(0.9, 0.08, 1.6), cframe * CFrame.new(0, 0.46, -0.2), bodyColor)

    -- LEDs infravermelhos em volta da lente
    local irLeds = {}
    for i = 0, 7 do
        local cf = cframe * CFrame.Angles(0, 0, math.rad(i * 45)) * CFrame.new(0.27, 0, -0.97)
        table.insert(irLeds, mk(BALL, Vector3.new(0.07, 0.07, 0.07), cf, Color3.fromRGB(90, 20, 20)))
    end

    -- LED de status (verde = Wi-Fi, laranja = fio; pisca vermelho com movimento)
    local statusLed = mk(BALL, Vector3.new(0.08, 0.08, 0.08), cframe * CFrame.new(0.4, 0.1, 0.5), ledColor, Enum.Material.Neon)

    -- Antenas (só Wi-Fi)
    if not isWired then
        for _, side in ipairs({-1, 1}) do
            local cf = cframe * CFrame.new(side * 0.25, 0.3, 0.85)
                * CFrame.Angles(0, 0, math.rad(-side * 12))
                * CFrame.new(0, 0.5, 0)
                * CFrame.Angles(0, 0, math.rad(90))
            mk(CYL, Vector3.new(1, 0.07, 0.07), cf, black)
        end
    end

    -- Suporte: bola, braço e placa de parede
    mk(BALL, Vector3.new(0.25, 0.25, 0.25), cframe * CFrame.new(0, -0.5, 0), bodyColor)
    mk(BLOCK, Vector3.new(0.12, 0.12, 0.8), cframe * CFrame.new(0, -0.55, 0.4), bodyColor)
    mk(BLOCK, Vector3.new(0.5, 0.5, 0.06), cframe * CFrame.new(0, -0.55, 0.8), bodyColor)

    -- Lente invisível (usada pela visão da câmera, cabo, sinal e movimento)
    local lens = mk(BLOCK, Vector3.new(0.2, 0.2, 0.05), cframe * CFrame.new(0, 0, -0.99), black, nil, 1)

    -- Luz vermelha dos LEDs IR
    local irLight = Instance.new("PointLight")
    irLight.Color = Color3.fromRGB(255, 70, 70)
    irLight.Range = 16
    irLight.Brightness = 1.5
    irLight.Enabled = false
    irLight.Parent = lens

    -- Luz branca da câmera (botão 💡)
    local camLight = Instance.new("SpotLight")
    camLight.Color = Color3.fromRGB(255, 244, 214)
    camLight.Range = 40
    camLight.Angle = 70
    camLight.Brightness = 3
    camLight.Face = Enum.NormalId.Front
    camLight.Enabled = false
    camLight.Parent = lens

    model.PrimaryPart = lens
    local camData = {
        lens = lens, isWired = isWired, name = name, model = model, cable = nil,
        irLeds = irLeds, irLight = irLight, irOn = nil,
        statusLed = statusLed, ledColor = ledColor,
        motionUntil = nil, motionName = nil, motionHRP = nil,
        hasPole = hasPole, pole = nil, cableMode = "baixo",
        camLight = camLight, lightOn = false,
    }
    setIR(camData, isDark())
    buildPole(camData)
    updateCable(camData)

    -- Clicar na câmera com fio abre a janela para escolher o fio
    if isWired then
        local cd = Instance.new("ClickDetector")
        cd.MaxActivationDistance = 20
        cd.Parent = body
        cd.MouseClick:Connect(function()
            if openCableMenu then openCableMenu(camData) end
        end)
    end

    return camData
end

-- ===================== 4. INTERFACE =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RetroTVGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player.PlayerGui

-- Base do chuvisco (tela cheia)
local staticOverlay = Instance.new("Frame")
staticOverlay.Size = UDim2.new(1, 0, 1, 0)
staticOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
staticOverlay.BackgroundTransparency = 0.95
staticOverlay.BorderSizePixel = 0
staticOverlay.ClipsDescendants = true
staticOverlay.Visible = false
staticOverlay.Parent = screenGui

-- ----- Sistema de chuvisco -----
local function makeNoise(parent, count)
    local pool = {}
    for i = 1, count do
        local f = Instance.new("Frame")
        f.BorderSizePixel = 0
        f.Visible = false
        f.Parent = parent
        pool[i] = f
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

local updateScreenNoise = makeNoise(staticOverlay, 170)

-- Listras horizontais (glitch)
local barPool = {}
for i = 1, 6 do
    local bar = Instance.new("Frame")
    bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    bar.BorderSizePixel = 0
    bar.Visible = false
    bar.Parent = staticOverlay
    barPool[i] = bar
end

-- Texto SEM SINAL
local noSignalLabel = Instance.new("TextLabel")
noSignalLabel.AnchorPoint = Vector2.new(0.5, 0.5)
noSignalLabel.Size = UDim2.new(0, 420, 0, 80)
noSignalLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
noSignalLabel.BackgroundTransparency = 1
noSignalLabel.Text = "SEM SINAL"
noSignalLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
noSignalLabel.TextStrokeTransparency = 0
noSignalLabel.TextSize = 54
noSignalLabel.Font = Enum.Font.Code
noSignalLabel.Visible = false
noSignalLabel.Parent = staticOverlay

-- Chuvisco + logo quicando na tela da TV (no mundo)
local TV_CANVAS_W, TV_CANVAS_H = 240, 190
local LOGO_W, LOGO_H = 96, 30
local tvNoiseUpdate = nil
local tvLogo = nil
local logoX, logoY = 10, 10
local logoVX, logoVY = 55, 45

local function attachTVNoise(screenPart)
    local sg = Instance.new("SurfaceGui")
    sg.Face = Enum.NormalId.Front
    sg.CanvasSize = Vector2.new(TV_CANVAS_W, TV_CANVAS_H)
    sg.LightInfluence = 0
    sg.Parent = screenPart

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(35, 40, 38)
    bg.BorderSizePixel = 0
    bg.ClipsDescendants = true
    bg.Parent = sg

    tvNoiseUpdate = makeNoise(bg, 90)

    tvLogo = Instance.new("TextLabel")
    tvLogo.Size = UDim2.fromOffset(LOGO_W, LOGO_H)
    logoX, logoY = 10, 10
    logoVX, logoVY = math.abs(logoVX), math.abs(logoVY)
    tvLogo.Position = UDim2.fromOffset(logoX, logoY)
    tvLogo.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    tvLogo.BackgroundTransparency = 0.25
    tvLogo.BorderSizePixel = 0
    tvLogo.Text = "📺 CCTV"
    tvLogo.TextColor3 = Color3.fromRGB(0, 255, 150)
    tvLogo.TextSize = 18
    tvLogo.Font = Enum.Font.GothamBold
    tvLogo.Parent = bg
end

-- REC piscando
local recLabel = Instance.new("TextLabel")
recLabel.Size = UDim2.new(0, 120, 0, 28)
recLabel.Position = UDim2.new(1, -140, 0, 15)
recLabel.BackgroundTransparency = 1
recLabel.TextColor3 = Color3.fromRGB(255, 40, 40)
recLabel.Text = "● REC"
recLabel.TextSize = 22
recLabel.Font = Enum.Font.Code
recLabel.TextXAlignment = Enum.TextXAlignment.Right
recLabel.Visible = false
recLabel.Parent = screenGui

-- Data/hora + nome da câmera
local timeLabel = Instance.new("TextLabel")
timeLabel.Size = UDim2.new(0, 320, 0, 44)
timeLabel.Position = UDim2.new(0, 15, 0, 15)
timeLabel.BackgroundTransparency = 1
timeLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
timeLabel.Text = ""
timeLabel.TextSize = 16
timeLabel.Font = Enum.Font.Code
timeLabel.TextXAlignment = Enum.TextXAlignment.Left
timeLabel.TextYAlignment = Enum.TextYAlignment.Top
timeLabel.Visible = false
timeLabel.Parent = screenGui

-- HUD da TV
local hudFrame = Instance.new("Frame")
hudFrame.Size = UDim2.new(0, 270, 0, 150)
hudFrame.Position = UDim2.new(0.02, 0, 0.72, 0)
hudFrame.BackgroundColor3 = Color3.fromRGB(25, 20, 18)
hudFrame.BorderSizePixel = 0
hudFrame.Visible = false
hudFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = hudFrame

local tvTitle = Instance.new("TextLabel")
tvTitle.Size = UDim2.new(1, 0, 0, 28)
tvTitle.BackgroundColor3 = Color3.fromRGB(45, 35, 30)
tvTitle.TextColor3 = Color3.fromRGB(255, 180, 50)
tvTitle.Text = "📺 TV TUBOCAM - CANAL CCTV"
tvTitle.TextSize = 11
tvTitle.Font = Enum.Font.Code
tvTitle.Parent = hudFrame

local signalLabel = Instance.new("TextLabel")
signalLabel.Size = UDim2.new(0.9, 0, 0, 24)
signalLabel.Position = UDim2.new(0.05, 0, 0.22, 0)
signalLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
signalLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
signalLabel.Text = "📶 SINAL WI-FI: 100% (EXCELENTE)"
signalLabel.TextSize = 10
signalLabel.Font = Enum.Font.Code
signalLabel.Parent = hudFrame

local btnNextCam = Instance.new("TextButton")
btnNextCam.Size = UDim2.new(0.9, 0, 0, 28)
btnNextCam.Position = UDim2.new(0.05, 0, 0.42, 0)
btnNextCam.BackgroundColor3 = Color3.fromRGB(180, 90, 20)
btnNextCam.TextColor3 = Color3.fromRGB(255, 255, 255)
btnNextCam.Text = "🔄 Mudar Canal (Câmera)"
btnNextCam.TextSize = 11
btnNextCam.Font = Enum.Font.GothamBold
btnNextCam.Parent = hudFrame

local btnExit = Instance.new("TextButton")
btnExit.Size = UDim2.new(0.9, 0, 0, 26)
btnExit.Position = UDim2.new(0.05, 0, 0.78, 0)
btnExit.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
btnExit.TextColor3 = Color3.fromRGB(255, 255, 255)
btnExit.Text = "🔌 Desligar TV"
btnExit.TextSize = 11
btnExit.Font = Enum.Font.GothamBold
btnExit.Parent = hudFrame

-- Botão de visão noturna (logo acima do HUD)
local btnNight = Instance.new("TextButton")
btnNight.Size = UDim2.new(0, 270, 0, 28)
btnNight.Position = UDim2.new(0.02, 0, 0.72, -34)
btnNight.BackgroundColor3 = Color3.fromRGB(35, 50, 35)
btnNight.TextColor3 = Color3.fromRGB(255, 255, 255)
btnNight.Text = "🌙 Visão Noturna: OFF"
btnNight.TextSize = 12
btnNight.Font = Enum.Font.GothamBold
btnNight.Visible = false
btnNight.Parent = screenGui

-- Botão de detecção de movimento (acima da visão noturna, só enquanto assiste)
local btnMotion = Instance.new("TextButton")
btnMotion.Size = UDim2.new(0, 270, 0, 28)
btnMotion.Position = UDim2.new(0.02, 0, 0.72, -68)
btnMotion.BackgroundColor3 = Color3.fromRGB(60, 50, 50)
btnMotion.TextColor3 = Color3.fromRGB(255, 255, 255)
btnMotion.Text = "🚶 Detecção de Movimento: OFF"
btnMotion.TextSize = 12
btnMotion.Font = Enum.Font.GothamBold
btnMotion.Visible = false
btnMotion.Parent = screenGui

-- Botão de luz da câmera (acima da detecção de movimento, só enquanto assiste)
local btnLight = Instance.new("TextButton")
btnLight.Size = UDim2.new(0, 270, 0, 28)
btnLight.Position = UDim2.new(0.02, 0, 0.72, -102)
btnLight.BackgroundColor3 = Color3.fromRGB(70, 65, 30)
btnLight.TextColor3 = Color3.fromRGB(255, 255, 255)
btnLight.Text = "💡 Luz da Câmera: OFF"
btnLight.TextSize = 12
btnLight.Font = Enum.Font.GothamBold
btnLight.Visible = false
btnLight.Parent = screenGui

local function refreshLightButton()
    local on = currentCamData and currentCamData.lightOn
    btnLight.Text = on and "💡 Luz da Câmera: ON" or "💡 Luz da Câmera: OFF"
    btnLight.BackgroundColor3 = on and Color3.fromRGB(190, 150, 20) or Color3.fromRGB(70, 65, 30)
end

btnLight.MouseButton1Click:Connect(function()
    local c = currentCamData
    if not c then return end
    c.lightOn = not c.lightOn
    c.camLight.Enabled = c.lightOn
    refreshLightButton()
end)

-- Painel de instalação
local controlMenu = Instance.new("Frame")
controlMenu.Size = UDim2.new(0, 210, 0, 130)
controlMenu.Position = UDim2.new(0.02, 0, 0.05, 0)
controlMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
controlMenu.Parent = screenGui

local function makeButton(text, yScale, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.9, 0, 0, 28)
    b.Position = UDim2.new(0.05, 0, yScale, 0)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.Parent = controlMenu
    return b
end

local btnSpawnTV = makeButton("📺 Colocar TV Antiga", 0.08, Color3.fromRGB(120, 70, 30))
local btnSpawnWifiCam = makeButton("📶 Instalar Cam Wi-Fi", 0.38, Color3.fromRGB(0, 140, 90))
local btnSpawnWiredCam = makeButton("🔌 Instalar Cam com Fio", 0.68, Color3.fromRGB(60, 80, 110))

-- ===================== ALTURA + POSIÇÃO DAS CÂMERAS =====================
local camHeight = 3
local HEIGHT_STEP = 0.5

-- Retorna o CFrame e true se a câmera vai ficar presa numa parede
local function getCameraSpawnCFrame()
    local feetY = rootPart.Position.Y - 3
    local y = feetY + camHeight
    local look = rootPart.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
    flat = flat.Unit

    local origin = Vector3.new(rootPart.Position.X, y, rootPart.Position.Z)
    local hit = Workspace:Raycast(origin, flat * 60, rayParams)

    if hit and math.abs(hit.Normal.Y) < 0.5 then
        -- Gruda na parede, olhando para fora dela
        local pos = hit.Position + hit.Normal * 0.84
        return CFrame.lookAt(pos, pos + hit.Normal), true
    end

    -- Sem parede: fica num poste, 6 studs à frente
    local pos = origin + flat * 6
    return CFrame.lookAt(pos, pos + flat), false
end

local heightMenu = Instance.new("Frame")
heightMenu.Size = UDim2.new(0, 210, 0, 70)
heightMenu.Position = UDim2.new(0.02, 0, 0.05, 140)
heightMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
heightMenu.Parent = screenGui

local heightLabel = Instance.new("TextLabel")
heightLabel.Size = UDim2.new(0.9, 0, 0, 24)
heightLabel.Position = UDim2.new(0.05, 0, 0, 6)
heightLabel.BackgroundTransparency = 1
heightLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
heightLabel.Font = Enum.Font.GothamBold
heightLabel.TextSize = 12
heightLabel.Text = "📏 Altura: 3.0"
heightLabel.Parent = heightMenu

local function makeHeightBtn(text, xScale, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.43, 0, 0, 28)
    b.Position = UDim2.new(xScale, 0, 0, 34)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Text = text
    b.TextSize = 14
    b.Font = Enum.Font.GothamBold
    b.Parent = heightMenu
    return b
end

local btnHeightDown = makeHeightBtn("▼ Baixar", 0.05, Color3.fromRGB(90, 60, 60))
local btnHeightUp = makeHeightBtn("▲ Subir", 0.52, Color3.fromRGB(60, 90, 60))

-- Muda a altura das próximas câmeras e também move a ÚLTIMA instalada
local function changeHeight(delta)
    local newH = math.clamp(camHeight + delta, 1, 15)
    local real = newH - camHeight
    if real == 0 then return end
    camHeight = newH
    heightLabel.Text = string.format("📏 Altura: %.1f", camHeight)

    local last = createdCams[#createdCams]
    if last and last.model.Parent then
        last.model:PivotTo(last.model:GetPivot() + Vector3.new(0, real, 0))
        buildPole(last)
        updateCable(last)
    end
end

btnHeightDown.MouseButton1Click:Connect(function() changeHeight(-HEIGHT_STEP) end)
btnHeightUp.MouseButton1Click:Connect(function() changeHeight(HEIGHT_STEP) end)

-- ===================== EXCLUIR CÂMERA (por número) =====================
local deleteMenu = Instance.new("Frame")
deleteMenu.Size = UDim2.new(0, 210, 0, 150)
deleteMenu.Position = UDim2.new(0.02, 0, 0.05, 220)
deleteMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
deleteMenu.Parent = screenGui

local deleteTitle = Instance.new("TextLabel")
deleteTitle.Size = UDim2.new(0.9, 0, 0, 22)
deleteTitle.Position = UDim2.new(0.05, 0, 0, 4)
deleteTitle.BackgroundTransparency = 1
deleteTitle.TextColor3 = Color3.fromRGB(255, 120, 120)
deleteTitle.Font = Enum.Font.GothamBold
deleteTitle.TextSize = 12
deleteTitle.Text = "🗑 Excluir câmera (clique)"
deleteTitle.Parent = deleteMenu

local deleteList = Instance.new("ScrollingFrame")
deleteList.Size = UDim2.new(0.9, 0, 0, 114)
deleteList.Position = UDim2.new(0.05, 0, 0, 28)
deleteList.BackgroundTransparency = 1
deleteList.BorderSizePixel = 0
deleteList.ScrollBarThickness = 4
deleteList.CanvasSize = UDim2.new(0, 0, 0, 0)
deleteList.AutomaticCanvasSize = Enum.AutomaticSize.Y
deleteList.Parent = deleteMenu

local deleteLayout = Instance.new("UIListLayout")
deleteLayout.Padding = UDim.new(0, 4)
deleteLayout.SortOrder = Enum.SortOrder.LayoutOrder
deleteLayout.Parent = deleteList

local deleteCamera -- definida mais abaixo (precisa do stopViewing)

local function refreshDeleteList()
    for _, child in ipairs(deleteList:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end

    if #createdCams == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 24)
        empty.BackgroundTransparency = 1
        empty.TextColor3 = Color3.fromRGB(150, 150, 150)
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 11
        empty.Text = "Nenhuma câmera instalada"
        empty.Parent = deleteList
        return
    end

    for i, c in ipairs(createdCams) do
        c.name = (c.isWired and "CAM-Fio-" or "CAM-WiFi-") .. i
        c.model.Name = c.name

        local b = Instance.new("TextButton")
        b.LayoutOrder = i
        b.Size = UDim2.new(1, -6, 0, 26)
        b.BackgroundColor3 = c.isWired and Color3.fromRGB(60, 80, 110) or Color3.fromRGB(0, 110, 75)
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.Text = "🗑 " .. i .. " - " .. (c.isWired and "Fio" or "Wi-Fi")
        b.Parent = deleteList
        b.MouseButton1Click:Connect(function() deleteCamera(i) end)
    end
end

-- ===================== DETECÇÃO DE MOVIMENTO =====================
local MOTION_RANGE = 45       -- alcance (studs)
local MOTION_HALF_FOV = 35    -- metade do ângulo de visão da câmera (graus)
local MOTION_MIN_SPEED = 2    -- velocidade mínima para contar como "movimento"
local DETECT_PLAYERS = true   -- detecta jogadores
local DETECT_NPCS = true      -- detecta NPCs (modelos com Humanoid)
local DETECT_SELF = true      -- true = você também aciona (bom para testar)
local ALERT_HOLD = 3          -- segundos que o alerta fica na tela
local ALARM_SOUND_ID = ""     -- opcional: "rbxassetid://SEU_ID" (som de alarme)
local ICON_IMAGE_ID = ""      -- opcional: "rbxassetid://SEU_ID" (imagem do ícone da câmera)

local motionOn = false
local alertUntil = 0
local lastAlarm = 0
local black = Color3.fromRGB(0, 0, 0)
local alertRed = Color3.fromRGB(255, 30, 30)

local alarmSound = Instance.new("Sound")
alarmSound.Volume = 0.8
alarmSound.Parent = screenGui

local function playAlarm()
    if ALARM_SOUND_ID == "" then return end
    if tick() - lastAlarm < ALERT_HOLD then return end
    lastAlarm = tick()
    alarmSound.SoundId = ALARM_SOUND_ID
    alarmSound:Play()
end

-- Placa "MOTION DETECTION"
local motionSign = Instance.new("Frame")
motionSign.AnchorPoint = Vector2.new(0.5, 0)
motionSign.Size = UDim2.new(0, 300, 0, 120)
motionSign.Position = UDim2.new(0.5, 0, 0, 10)
motionSign.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
motionSign.BorderSizePixel = 0
motionSign.Visible = false
motionSign.Parent = screenGui

local signCorner = Instance.new("UICorner")
signCorner.CornerRadius = UDim.new(0, 14)
signCorner.Parent = motionSign

local signStroke = Instance.new("UIStroke")
signStroke.Thickness = 4
signStroke.Color = black
signStroke.Parent = motionSign

local iconLabel = Instance.new("TextLabel")
iconLabel.Size = UDim2.new(1, 0, 0, 38)
iconLabel.Position = UDim2.new(0, 0, 0, 6)
iconLabel.BackgroundTransparency = 1
iconLabel.TextColor3 = black
iconLabel.Text = "📹 )))  ❗"
iconLabel.TextSize = 28
iconLabel.Font = Enum.Font.GothamBlack
iconLabel.Parent = motionSign

if ICON_IMAGE_ID ~= "" then
    iconLabel.Text = ""
    local img = Instance.new("ImageLabel")
    img.AnchorPoint = Vector2.new(0.5, 0)
    img.Size = UDim2.fromOffset(42, 42)
    img.Position = UDim2.new(0.5, 0, 0, 4)
    img.BackgroundTransparency = 1
    img.Image = ICON_IMAGE_ID
    img.Parent = motionSign
end

local signTitle = Instance.new("TextLabel")
signTitle.Size = UDim2.new(1, 0, 0, 40)
signTitle.Position = UDim2.new(0, 0, 0, 46)
signTitle.BackgroundTransparency = 1
signTitle.TextColor3 = black
signTitle.Text = "MOTION DETECTION"
signTitle.TextSize = 25
signTitle.Font = Enum.Font.GothamBlack
signTitle.Parent = motionSign

local signInfo = Instance.new("TextLabel")
signInfo.Size = UDim2.new(1, 0, 0, 22)
signInfo.Position = UDim2.new(0, 0, 0, 90)
signInfo.BackgroundTransparency = 1
signInfo.TextColor3 = Color3.fromRGB(60, 60, 60)
signInfo.Text = ""
signInfo.TextSize = 13
signInfo.Font = Enum.Font.Code
signInfo.Parent = motionSign

-- Borda vermelha piscando e caixa de rastreio (dentro da imagem da câmera)
local alertBorder = Instance.new("Frame")
alertBorder.Size = UDim2.new(1, 0, 1, 0)
alertBorder.BackgroundTransparency = 1
alertBorder.Visible = false
alertBorder.Parent = staticOverlay

local borderStroke = Instance.new("UIStroke")
borderStroke.Thickness = 14
borderStroke.Color = alertRed
borderStroke.Parent = alertBorder

local trackBox = Instance.new("Frame")
trackBox.AnchorPoint = Vector2.new(0.5, 0.5)
trackBox.BackgroundTransparency = 1
trackBox.Visible = false
trackBox.Parent = staticOverlay

local trackStroke = Instance.new("UIStroke")
trackStroke.Thickness = 2
trackStroke.Color = alertRed
trackStroke.Parent = trackBox

local trackLabel = Instance.new("TextLabel")
trackLabel.Size = UDim2.new(0, 200, 0, 16)
trackLabel.Position = UDim2.new(0.5, -100, 0, -18)
trackLabel.BackgroundTransparency = 1
trackLabel.TextColor3 = alertRed
trackLabel.TextStrokeTransparency = 0
trackLabel.TextSize = 12
trackLabel.Font = Enum.Font.Code
trackLabel.Text = ""
trackLabel.Parent = trackBox

-- Painel com botão (para ligar/desligar fora da TV)
local motionMenu = Instance.new("Frame")
motionMenu.Size = UDim2.new(0, 210, 0, 44)
motionMenu.Position = UDim2.new(0.02, 0, 0.05, 380)
motionMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
motionMenu.Parent = screenGui

local btnMotionPanel = Instance.new("TextButton")
btnMotionPanel.Size = UDim2.new(0.9, 0, 0, 28)
btnMotionPanel.Position = UDim2.new(0.05, 0, 0, 8)
btnMotionPanel.BackgroundColor3 = Color3.fromRGB(60, 50, 50)
btnMotionPanel.TextColor3 = Color3.fromRGB(255, 255, 255)
btnMotionPanel.Font = Enum.Font.GothamBold
btnMotionPanel.TextSize = 10
btnMotionPanel.Text = "🚶 Detecção de Movimento: OFF"
btnMotionPanel.Parent = motionMenu

local function refreshMotionButtons()
    local txt = motionOn and "🚶 Detecção de Movimento: ON" or "🚶 Detecção de Movimento: OFF"
    local col = motionOn and Color3.fromRGB(150, 40, 40) or Color3.fromRGB(60, 50, 50)
    btnMotion.Text = txt
    btnMotion.BackgroundColor3 = col
    btnMotionPanel.Text = txt
    btnMotionPanel.BackgroundColor3 = col
end

-- Limpa alertas e devolve a cor normal dos LEDs de status
local function resetMotion()
    alertUntil = 0
    motionSign.Visible = false
    alertBorder.Visible = false
    trackBox.Visible = false
    for _, c in ipairs(createdCams) do
        c.motionUntil = nil
        c.motionName = nil
        c.motionHRP = nil
        c.statusLed.Color = c.ledColor
    end
end

local function setMotion(on)
    motionOn = on
    if not on then resetMotion() end
    refreshMotionButtons()
end

btnMotion.MouseButton1Click:Connect(function() setMotion(not motionOn) end)
btnMotionPanel.MouseButton1Click:Connect(function() setMotion(not motionOn) end)

-- ----- Alvos: jogadores + NPCs (modelos com Humanoid) -----
local lastPos = setmetatable({}, {__mode = "k"})
local npcCache = {}
local lastNpcRefresh = 0

local function refreshNpcs()
    npcCache = {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Humanoid") and d.Health > 0 then
            local model = d.Parent
            if model and model:IsA("Model")
                and not Players:GetPlayerFromCharacter(model)
                and not model:IsDescendantOf(folder) then
                local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                if hrp then
                    table.insert(npcCache, {model = model, hrp = hrp, name = model.Name})
                end
            end
        end
    end
end

-- velocidade real pela mudança de posição (pega NPC movido por script também)
local function getSpeed(hrp, now)
    local pos = hrp.Position
    local rec = lastPos[hrp]
    lastPos[hrp] = {pos, now}
    if not rec then return 0 end
    local dt = now - rec[2]
    if dt <= 0 then return 0 end
    return (pos - rec[1]).Magnitude / dt
end

-- Varredura: alguém (jogador ou NPC) se MEXENDO dentro do cone de visão, com linha de visão livre
local function scanMotion()
    local now = tick()
    if DETECT_NPCS and now - lastNpcRefresh > 3 then
        lastNpcRefresh = now
        refreshNpcs()
    end

    local targets = {}
    if DETECT_PLAYERS then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player or DETECT_SELF then
                local char = plr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    table.insert(targets, {char = char, hrp = hrp, name = plr.DisplayName, speed = getSpeed(hrp, now)})
                end
            end
        end
    end
    if DETECT_NPCS then
        for _, n in ipairs(npcCache) do
            if n.model.Parent and n.hrp.Parent then
                table.insert(targets, {char = n.model, hrp = n.hrp, name = n.name, speed = getSpeed(n.hrp, now)})
            end
        end
    end

    local cosLimit = math.cos(math.rad(MOTION_HALF_FOV))

    for _, c in ipairs(createdCams) do
        local lensCF = c.lens.CFrame
        local look = lensCF.LookVector
        local found = nil

        for _, t in ipairs(targets) do
            if t.speed > MOTION_MIN_SPEED then
                local toTarget = t.hrp.Position - lensCF.Position
                local dist = toTarget.Magnitude
                if dist > 0.5 and dist <= MOTION_RANGE and look:Dot(toTarget.Unit) >= cosLimit then
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
            c.motionUntil = now + ALERT_HOLD
            c.motionName = found.name
            c.motionHRP = found.hrp
            alertUntil = now + ALERT_HOLD
            signInfo.Text = c.name .. "  •  " .. found.name
            if isNew then playAlarm() end
        end

        if c.motionUntil and now < c.motionUntil then
            c.statusLed.Color = (math.floor(now * 4) % 2 == 0) and alertRed or c.ledColor
        else
            c.statusLed.Color = c.ledColor
        end
    end
end

-- ===================== FECHAR / ABRIR GUI =====================
local panelsOpen = true
local panels = {controlMenu, heightMenu, deleteMenu, motionMenu}

local btnToggleGui = Instance.new("TextButton")
btnToggleGui.Size = UDim2.new(0, 100, 0, 28)
btnToggleGui.Position = UDim2.new(0.02, 220, 0.05, 0)
btnToggleGui.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
btnToggleGui.TextColor3 = Color3.fromRGB(255, 255, 255)
btnToggleGui.Font = Enum.Font.GothamBold
btnToggleGui.TextSize = 11
btnToggleGui.Text = "✖ Fechar GUI"
btnToggleGui.Parent = screenGui

local function applyPanels()
    for _, p in ipairs(panels) do
        p.Visible = panelsOpen and not viewing
    end
    btnToggleGui.Visible = not viewing
    btnToggleGui.Text = panelsOpen and "✖ Fechar GUI" or "☰ Abrir GUI"
end

btnToggleGui.MouseButton1Click:Connect(function()
    panelsOpen = not panelsOpen
    applyPanels()
end)

-- ===================== JANELA DO FIO (clicar na câmera com fio) =====================
local cableMenu = Instance.new("Frame")
cableMenu.Size = UDim2.new(0, 210, 0, 175)
cableMenu.Position = UDim2.new(0.5, -105, 0.35, 0)
cableMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
cableMenu.Visible = false
cableMenu.Parent = screenGui

local cableCorner = Instance.new("UICorner")
cableCorner.CornerRadius = UDim.new(0, 8)
cableCorner.Parent = cableMenu

local cableTitle = Instance.new("TextLabel")
cableTitle.Size = UDim2.new(0.9, 0, 0, 24)
cableTitle.Position = UDim2.new(0.05, 0, 0, 6)
cableTitle.BackgroundTransparency = 1
cableTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
cableTitle.Font = Enum.Font.GothamBold
cableTitle.TextSize = 12
cableTitle.Text = "🔌 Qual fio?"
cableTitle.Parent = cableMenu

local cableTarget = nil

local function cableBtn(text, y, mode, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.9, 0, 0, 28)
    b.Position = UDim2.new(0.05, 0, 0, y)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Text = text
    b.Parent = cableMenu
    b.MouseButton1Click:Connect(function()
        if mode and cableTarget and cableTarget.model.Parent then
            cableTarget.cableMode = mode
            updateCable(cableTarget)
        end
        cableMenu.Visible = false
    end)
end

cableBtn("⬆ Cima (teto)", 34, "cima", Color3.fromRGB(60, 80, 110))
cableBtn("⬇ Baixo (chão)", 68, "baixo", Color3.fromRGB(60, 80, 110))
cableBtn("🧱 Parede", 102, "parede", Color3.fromRGB(60, 80, 110))
cableBtn("✖ Fechar", 136, nil, Color3.fromRGB(90, 60, 60))

openCableMenu = function(c)
    cableTarget = c
    cableTitle.Text = "🔌 Fio da " .. c.name
    cableMenu.Visible = true
end

-- ===================== LEDs IR (escuro ou visão noturna) =====================
local function updateIR()
    local dark = isDark()
    for _, c in ipairs(createdCams) do
        local forced = viewing and nightVision and c == currentCamData
        setIR(c, dark or forced)
    end
end

-- ===================== 5. CONTROLE DE VISUALIZAÇÃO =====================
local function setViewUI(on)
    hudFrame.Visible = on
    btnNight.Visible = on
    btnMotion.Visible = on
    btnLight.Visible = on
    staticOverlay.Visible = on
    recLabel.Visible = on
    timeLabel.Visible = on
    if on then cableMenu.Visible = false end
    applyPanels() -- clicar na TV fecha a GUI; desligar a TV traz de volta
end

local function startViewing()
    if #createdCams == 0 or not activeTVScreen then return end
    viewing = true
    currentCamData = createdCams[camIndex]
    refreshLightButton()
    camera.CameraType = Enum.CameraType.Scriptable
    nightEffect.Enabled = nightVision
    setViewUI(true)
    updateIR()
end

local function stopViewing()
    viewing = false
    camera.CameraType = Enum.CameraType.Custom
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum then camera.CameraSubject = hum end
    nightEffect.Enabled = false
    setViewUI(false)
    updateIR()
end

-- Excluir câmera pelo número
deleteCamera = function(i)
    local c = createdCams[i]
    if not c then return end

    local wasViewingThis = viewing and currentCamData == c
    if cableTarget == c then
        cableTarget = nil
        cableMenu.Visible = false
    end
    c.model:Destroy()
    table.remove(createdCams, i)

    if camIndex > i then camIndex = camIndex - 1 end
    if camIndex > #createdCams then camIndex = 1 end
    if camIndex < 1 then camIndex = 1 end

    if viewing then
        if #createdCams == 0 then
            stopViewing()
        elseif wasViewingThis then
            currentCamData = createdCams[camIndex]
            refreshLightButton()
        end
    end

    refreshDeleteList()
end

-- ===================== 6. EVENTOS =====================
btnSpawnTV.MouseButton1Click:Connect(function()
    if viewing then stopViewing() end
    local tv = createRetroTV(rootPart.CFrame * CFrame.new(0, -1, -5))
    attachTVNoise(tv.TVScreen)
    tv.TVScreen.ClickDetector.MouseClick:Connect(startViewing)
    for _, c in ipairs(createdCams) do updateCable(c) end
end)

btnSpawnWifiCam.MouseButton1Click:Connect(function()
    local num = #createdCams + 1
    local cf, onWall = getCameraSpawnCFrame()
    table.insert(createdCams, createCameraModel("CAM-WiFi-" .. num, cf, false, not onWall))
    refreshDeleteList()
end)

btnSpawnWiredCam.MouseButton1Click:Connect(function()
    local num = #createdCams + 1
    local cf, onWall = getCameraSpawnCFrame()
    table.insert(createdCams, createCameraModel("CAM-Fio-" .. num, cf, true, not onWall))
    refreshDeleteList()
end)

btnNextCam.MouseButton1Click:Connect(function()
    if #createdCams > 0 then
        camIndex = camIndex % #createdCams + 1
        currentCamData = createdCams[camIndex]
        refreshLightButton()
        updateIR()
    end
end)

btnExit.MouseButton1Click:Connect(stopViewing)

btnNight.MouseButton1Click:Connect(function()
    nightVision = not nightVision
    nightEffect.Enabled = viewing and nightVision
    btnNight.Text = nightVision and "🌙 Visão Noturna: ON" or "🌙 Visão Noturna: OFF"
    btnNight.BackgroundColor3 = nightVision and Color3.fromRGB(30, 120, 40) or Color3.fromRGB(35, 50, 35)
    updateIR()
end)

refreshDeleteList()
refreshMotionButtons()
applyPanels()

-- ===================== 7. LOOP PRINCIPAL =====================
local lastTVNoise = 0
local lastIR = 0
local lastScan = 0

RunService.RenderStepped:Connect(function(dt)
    -- Chuvisco na TV do mundo
    if tvNoiseUpdate and activeTVScreen and activeTVScreen.Parent
        and tick() - lastTVNoise > 0.05 then
        lastTVNoise = tick()
        tvNoiseUpdate(0.8, TV_CANVAS_W, TV_CANVAS_H, 3, 10, 0.1)
    end

    -- Logo quicando na tela da TV (muda de cor ao bater na borda)
    if tvLogo and tvLogo.Parent then
        logoX = logoX + logoVX * dt
        logoY = logoY + logoVY * dt
        local bounced = false

        if logoX <= 0 then
            logoX = 0
            logoVX = math.abs(logoVX)
            bounced = true
        elseif logoX + LOGO_W >= TV_CANVAS_W then
            logoX = TV_CANVAS_W - LOGO_W
            logoVX = -math.abs(logoVX)
            bounced = true
        end

        if logoY <= 0 then
            logoY = 0
            logoVY = math.abs(logoVY)
            bounced = true
        elseif logoY + LOGO_H >= TV_CANVAS_H then
            logoY = TV_CANVAS_H - LOGO_H
            logoVY = -math.abs(logoVY)
            bounced = true
        end

        if bounced then
            tvLogo.TextColor3 = Color3.fromHSV(math.random(), 0.8, 1)
        end
        tvLogo.Position = UDim2.fromOffset(logoX, logoY)
    end

    -- LEDs IR acendem no escuro
    if tick() - lastIR > 0.25 then
        lastIR = tick()
        updateIR()
    end

    -- Detecção de movimento (funciona mesmo sem assistir a TV)
    if motionOn and tick() - lastScan > 0.2 then
        lastScan = tick()
        scanMotion()
    end

    -- Placa "MOTION DETECTION" piscando
    local showSign = motionOn and tick() < alertUntil
    motionSign.Visible = showSign
    if showSign then
        signStroke.Color = (math.floor(tick() * 3) % 2 == 0) and alertRed or black
    end

    if not viewing or not currentCamData then return end

    -- TV removida enquanto assistia
    if not activeTVScreen or not activeTVScreen.Parent then
        stopViewing()
        return
    end

    -- Câmera acompanha a lente
    camera.CFrame = currentCamData.lens.CFrame

    -- Borda vermelha + caixa seguindo quem se mexe na câmera atual
    local cd = currentCamData
    local tracking = motionOn and cd.motionUntil and tick() < cd.motionUntil
        and cd.motionHRP and cd.motionHRP.Parent
    alertBorder.Visible = tracking and true or false
    trackBox.Visible = false
    if tracking then
        borderStroke.Transparency = (math.floor(tick() * 3) % 2 == 0) and 0 or 0.6
        local hrpPos = cd.motionHRP.Position
        local screenPos, onScreen = camera:WorldToViewportPoint(hrpPos)
        if onScreen then
            local inset = GuiService:GetGuiInset()
            local vpSize = camera.ViewportSize
            local dist = (hrpPos - camera.CFrame.Position).Magnitude
            local h = 5.5 / (2 * dist * math.tan(math.rad(camera.FieldOfView / 2))) * vpSize.Y
            h = math.clamp(h, 40, 500)
            trackBox.Size = UDim2.fromOffset(h * 0.5, h)
            trackBox.Position = UDim2.fromOffset(screenPos.X - inset.X, screenPos.Y - inset.Y)
            trackLabel.Text = "⚠ MOVIMENTO • " .. (cd.motionName or "?")
            trackBox.Visible = true
        end
    end

    -- Data/hora + nome do canal + REC piscando
    timeLabel.Text = currentCamData.name .. "\n" .. os.date("%d/%m/%Y  %H:%M:%S")
    timeLabel.TextColor3 = nightVision and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(230, 230, 230)
    recLabel.TextTransparency = (math.floor(tick() * 2) % 2 == 0) and 0 or 1

    local vp = camera.ViewportSize
    local intensity, bars, noSignal = 0, 0, false
    local sMin, sMax, alphaMin = 2, 6, 0.5

    if currentCamData.isWired then
        signalLabel.Text = "🔌 CABO DE VÍDEO: 100% (ESTÁVEL)"
        signalLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
        staticOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        staticOverlay.BackgroundTransparency = 0.98
    else
        local origin = currentCamData.lens.Position
        local target = activeTVScreen.Position
        local dist = (target - origin).Magnitude
        local signal = 100 - (dist * SIGNAL_LOSS)

        -- Parede entre a câmera e a TV?
        local blocked = Workspace:Raycast(origin, target - origin, rayParams) ~= nil
        if blocked then signal = signal - WALL_PENALTY end
        signal = math.clamp(signal, 0, 100)
        local wallTag = blocked and " 🧱" or ""

        if signal > 60 then
            signalLabel.Text = "📶 WI-FI: " .. math.floor(signal) .. "% (BOM)" .. wallTag
            signalLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
            staticOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            staticOverlay.BackgroundTransparency = 0.97
            intensity = 0.04
        elseif signal > 25 then
            local weak = 1 - (signal - 25) / 35
            signalLabel.Text = "⚠️ WI-FI: " .. math.floor(signal) .. "% (FRACO)" .. wallTag
            signalLabel.TextColor3 = Color3.fromRGB(255, 180, 0)
            staticOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            staticOverlay.BackgroundTransparency = 0.88 - weak * 0.15
            intensity = 0.15 + weak * 0.45
            bars = math.floor(1 + weak * 2)
            sMin, sMax, alphaMin = 3, 10, 0.35
        else
            signalLabel.Text = "🚫 WI-FI: " .. math.floor(signal) .. "% (SEM SINAL)" .. wallTag
            signalLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
            staticOverlay.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            staticOverlay.BackgroundTransparency = 0.1
            intensity = 1
            bars = 6
            sMin, sMax, alphaMin = 6, 22, 0.05
            noSignal = true
        end
    end

    updateScreenNoise(intensity, vp.X, vp.Y, sMin, sMax, alphaMin)

    for i, bar in ipairs(barPool) do
        if i <= bars then
            bar.Position = UDim2.new(0, 0, math.random(), 0)
            bar.Size = UDim2.new(1, 0, 0, math.random(2, 14))
            bar.BackgroundTransparency = 0.5 + math.random() * 0.4
            bar.Visible = true
        else
            bar.Visible = false
        end
    end

    noSignalLabel.Visible = noSignal
    if noSignal then
        noSignalLabel.Position = UDim2.new(0.5, math.random(-4, 4), 0.5, math.random(-3, 3))
        noSignalLabel.TextTransparency = (math.floor(tick() * 3) % 2 == 0) and 0 or 0.35
    end
end)

print("CCTV v9 ativado!")
