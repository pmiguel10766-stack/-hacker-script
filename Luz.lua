--[[
    ╔══════════════════════════════════════════════╗
    ║   LANTERNA TÁTICA HUB  (client-side / Luau)  ║
    ║   Compatível com Delta Executor (PC/Mobile)  ║
    ╚══════════════════════════════════════════════╝

    O que faz:
      • Cria uma lanterna tática amarela (Tool) e coloca-a na mochila.
      • Cria um mini painel dark mode com 3 botões:
          1. 💡 Luz On/Off   -> liga/desliga SpotLight + brilho Neon
          2. 🔦 Medium       -> modo médio (menos alcance/brilho, feixe mais largo)
          3. ⚡ Strobe       -> modo estroboscópio (pisca)
      • Painel arrastável (toque ou rato) e botão ✕ para fechar tudo.

    Nota: por ser client-side, só TU vês a lanterna e a luz.
]]

------------------------------------------------------------
-- SERVIÇOS
------------------------------------------------------------
local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local player  = Players.LocalPlayer

------------------------------------------------------------
-- CONFIGURAÇÕES
------------------------------------------------------------
local GUI_NAME  = "LanternaTaticaHub"
local TOOL_NAME = "Lanterna Tática"

-- Cores
local YELLOW     = Color3.fromRGB(255, 196, 0)    -- amarelo industrial
local DARK_GRAY  = Color3.fromRGB(35, 35, 38)
local BLACK      = Color3.fromRGB(18, 18, 20)
local LAMP_ON    = Color3.fromRGB(255, 244, 205)  -- lâmpada acesa
local LAMP_OFF   = Color3.fromRGB(150, 150, 150)  -- lâmpada apagada

-- Modos do feixe de luz
local MODES = {
    Full   = { Range = 60, Brightness = 6, Angle = 55 },
    Medium = { Range = 32, Brightness = 3, Angle = 85 },
}

-- Velocidade do strobe (segundos entre piscadas)
local STROBE_DELAY = 0.08

------------------------------------------------------------
-- LIMPEZA DE EXECUÇÕES ANTERIORES
------------------------------------------------------------
-- Escolhe o melhor local para a GUI (gethui é suportado por vários executores)
local function getGuiParent()
    local ok, result = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if ok and result then return result end
    return player:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()
local oldGui = guiParent:FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

local oldTool = player:FindFirstChildOfClass("Backpack") and player.Backpack:FindFirstChild(TOOL_NAME)
if oldTool then oldTool:Destroy() end
if player.Character then
    local held = player.Character:FindFirstChild(TOOL_NAME)
    if held then held:Destroy() end
end

------------------------------------------------------------
-- ESTADO
------------------------------------------------------------
local state = {
    alive       = true,   -- script ativo?
    lightOn     = false,  -- luz ligada?
    medium      = false,  -- modo médio?
    strobe      = false,  -- strobe ativo?
    strobePhase = true,   -- fase atual do strobe (true = aceso)
    strobeId    = 0,      -- identificador para evitar loops duplicados
}

-- Referências da ferramenta atual (reconstruída ao respawnar)
local refs = { tool = nil, light = nil, lamps = {} }

-- Botões da UI (preenchido mais abaixo)
local buttons = {}

------------------------------------------------------------
-- CONSTRUÇÃO 3D DA LANTERNA
------------------------------------------------------------
local function buildTool()
    local tool = Instance.new("Tool")
    tool.Name = TOOL_NAME
    tool.ToolTip = "Lanterna tática de mão"
    tool.RequiresHandle = true
    tool.CanBeDropped = false
    tool.GripPos = Vector3.new(0, 1.05, 0) -- segura pela pega superior

    -- Corpo principal (Handle obrigatório)
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(1.4, 1, 1.8)
    handle.Color = YELLOW
    handle.Material = Enum.Material.SmoothPlastic
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = tool

    -- Função auxiliar: cria peça soldada ao Handle
    -- offset = CFrame relativo ao Handle
    local function addPart(name, size, offset, color, material, shape)
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.Color = color
        p.Material = material or Enum.Material.SmoothPlastic
        if shape then p.Shape = shape end
        p.CanCollide = false
        p.Massless = true
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth

        local weld = Instance.new("Weld")
        weld.Part0 = handle
        weld.Part1 = p
        weld.C0 = offset
        weld.Parent = p

        p.Parent = tool
        return p
    end

    -- Rotação para deitar cilindros ao longo do eixo Z (frente/trás)
    local ROT = CFrame.Angles(0, math.rad(90), 0)

    -- Pega superior (duas hastes + barra)
    addPart("PostL", Vector3.new(0.2, 0.5, 0.2), CFrame.new(0, 0.75, -0.55), BLACK)
    addPart("PostR", Vector3.new(0.2, 0.5, 0.2), CFrame.new(0, 0.75,  0.55), BLACK)
    addPart("Grip",  Vector3.new(0.28, 0.22, 1.5), CFrame.new(0, 1.05, 0), BLACK)

    -- Tampa traseira (baterias) e faixa de proteção
    addPart("BackCap", Vector3.new(1.5, 1.1, 0.2), CFrame.new(0, 0, 0.95), DARK_GRAY)
    addPart("Stripe",  Vector3.new(1.45, 0.18, 1.85), CFrame.new(0, -0.3, 0), BLACK)

    -- Refletor grande (cilindro metálico)
    addPart("Reflector", Vector3.new(0.7, 1.9, 1.9),
        CFrame.new(0, 0, -1.25) * ROT,
        Color3.fromRGB(190, 190, 195), Enum.Material.Metal, Enum.PartType.Cylinder)

    -- Aro preto ao redor do refletor
    addPart("Bezel", Vector3.new(0.18, 2.05, 2.05),
        CFrame.new(0, 0, -1.55) * ROT,
        BLACK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)

    -- Lâmpadas frontais (lente central + 4 lâmpadas em volta)
    local lamps = {}

    local lens = addPart("Lens", Vector3.new(0.1, 0.9, 0.9),
        CFrame.new(0, 0, -1.65) * ROT,
        LAMP_OFF, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
    table.insert(lamps, lens)

    local corners = { {0.5, 0.5}, {-0.5, 0.5}, {0.5, -0.5}, {-0.5, -0.5} }
    for i, c in ipairs(corners) do
        local bulb = addPart("Bulb" .. i, Vector3.new(0.12, 0.3, 0.3),
            CFrame.new(c[1], c[2], -1.65) * ROT,
            LAMP_OFF, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
        table.insert(lamps, bulb)
    end

    -- Ponto invisível de emissão da luz (sem rotação, "Front" = direção do feixe)
    local muzzle = addPart("Muzzle", Vector3.new(0.2, 0.2, 0.2),
        CFrame.new(0, 0, -1.8), LAMP_OFF)
    muzzle.Transparency = 1

    local spot = Instance.new("SpotLight")
    spot.Name = "Beam"
    spot.Face = Enum.NormalId.Front
    spot.Color = Color3.fromRGB(255, 245, 220)
    spot.Shadows = false
    spot.Enabled = false
    spot.Parent = muzzle

    refs.tool  = tool
    refs.light = spot
    refs.lamps = lamps
    return tool
end

------------------------------------------------------------
-- RENDER: aplica o estado à luz, às lâmpadas e aos botões
------------------------------------------------------------
local function paint(btn, active)
    if not btn then return end
    btn.BackgroundColor3 = active and YELLOW or Color3.fromRGB(42, 42, 48)
    btn.TextColor3       = active and Color3.fromRGB(20, 20, 20) or Color3.new(1, 1, 1)
end

local function render()
    -- A luz só está "acesa" se estiver ligada e (sem strobe ou na fase acesa)
    local lit = state.lightOn and (not state.strobe or state.strobePhase)

    if refs.light then
        local m = state.medium and MODES.Medium or MODES.Full
        refs.light.Range      = m.Range
        refs.light.Brightness = m.Brightness
        refs.light.Angle      = m.Angle
        refs.light.Enabled    = lit
    end

    for _, lamp in ipairs(refs.lamps) do
        if lamp and lamp.Parent then
            lamp.Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
            lamp.Color    = lit and LAMP_ON or LAMP_OFF
        end
    end

    paint(buttons.light,  state.lightOn)
    paint(buttons.medium, state.medium)
    paint(buttons.strobe, state.strobe)
end

------------------------------------------------------------
-- AÇÕES DOS BOTÕES
------------------------------------------------------------
-- Para o strobe (invalida o loop atual)
local function stopStrobe()
    state.strobe = false
    state.strobeId += 1
    state.strobePhase = true
end

local function toggleLight()
    state.lightOn = not state.lightOn
    if not state.lightOn then stopStrobe() end -- apagar a luz também para o strobe
    render()
end

local function toggleMedium()
    state.medium = not state.medium
    render()
end

local function toggleStrobe()
    if state.strobe then
        stopStrobe()
        render()
        return
    end

    state.strobe = true
    state.lightOn = true
    state.strobeId += 1
    local myId = state.strobeId

    task.spawn(function()
        while state.alive and state.strobe and state.strobeId == myId do
            state.strobePhase = not state.strobePhase
            render()
            task.wait(STROBE_DELAY)
        end
        -- Ao terminar (se ainda for o loop atual), volta ao estado normal
        if state.alive and state.strobeId == myId then
            state.strobePhase = true
            render()
        end
    end)
    render()
end

------------------------------------------------------------
-- ENTREGAR A FERRAMENTA AO JOGADOR
------------------------------------------------------------
local function giveTool()
    if refs.tool then refs.tool:Destroy() end
    local tool = buildTool()
    tool.Parent = player:WaitForChild("Backpack")
    render()

    -- Tenta equipar automaticamente
    pcall(function()
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            task.wait(0.1)
            hum:EquipTool(tool)
        end
    end)
end

------------------------------------------------------------
-- INTERFACE (PAINEL FLUTUANTE COMPACTO / DARK MODE)
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local frame = Instance.new("Frame")
frame.Name = "Painel"
frame.Size = UDim2.new(0, 170, 0, 0)
frame.AutomaticSize = Enum.AutomaticSize.Y
frame.Position = UDim2.new(0, 20, 0.4, 0)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
frame.BorderSizePixel = 0
frame.Parent = gui

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local frameStroke = Instance.new("UIStroke", frame)
frameStroke.Color = YELLOW
frameStroke.Thickness = 1.2

local pad = Instance.new("UIPadding", frame)
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)

local layout = Instance.new("UIListLayout", frame)
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder

-- Cabeçalho (também serve para arrastar)
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 22)
header.BackgroundTransparency = 1
header.LayoutOrder = 0
header.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -26, 1, 0)
title.BackgroundTransparency = 1
title.Text = "🔦 LANTERNA TÁTICA"
title.TextColor3 = YELLOW
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -22, 0, 0)
closeBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.AutoButtonColor = true
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Fábrica de botões pequenos
local function makeButton(text, order)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 30)
    b.BackgroundColor3 = Color3.fromRGB(42, 42, 48)
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.AutoButtonColor = true
    b.LayoutOrder = order
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke", b)
    s.Color = Color3.fromRGB(70, 70, 78)
    s.Thickness = 1
    return b
end

buttons.light  = makeButton("1. 💡 Luz On/Off", 1)
buttons.medium = makeButton("2. 🔦 Medium", 2)
buttons.strobe = makeButton("3. ⚡ Strobe", 3)

-- Ligações dos botões
buttons.light.Activated:Connect(toggleLight)
buttons.medium.Activated:Connect(toggleMedium)
buttons.strobe.Activated:Connect(toggleStrobe)

------------------------------------------------------------
-- ARRASTAR O PAINEL (toque e rato)
------------------------------------------------------------
local dragging, dragStart, startPos = false, nil, nil

header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

local dragConn = UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

------------------------------------------------------------
-- RESPAWN E FECHO
------------------------------------------------------------
-- Ao respawnar a mochila é limpa, por isso recriamos a lanterna
local charConn = player.CharacterAdded:Connect(function()
    if not state.alive then return end
    task.wait(0.5)
    giveTool()
end)

-- Botão ✕: para tudo e remove painel + lanterna
closeBtn.Activated:Connect(function()
    state.alive = false
    stopStrobe()
    charConn:Disconnect()
    dragConn:Disconnect()
    if refs.tool then refs.tool:Destroy() end
    gui:Destroy()
end)

------------------------------------------------------------
-- INÍCIO
------------------------------------------------------------
giveTool()
render()
