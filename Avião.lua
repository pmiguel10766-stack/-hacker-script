--[[
    ✈ HANGAR DE AVIÕES v8 — Delta Executor (Mobile/PC)
    Botões: Criar Avião | Editor Cor | Excluir Avião
    ProximityPrompt: Entrar / Sair do Avião (inclusive em pleno voo)
    VOO: joystick (acelera/freia/vira) + botões ⬆️ ⬇️ ⚙️ (trem de pouso)
    Hélices e motores matam quem encostar
    NOVO: colisão com estruturas, avião destruído inutilizável com fumaça
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local player = Players.LocalPlayer

------------------------------------------------------------
-- ESTADO
------------------------------------------------------------
local currentPlane   = nil
local spinConnection = nil
local spinners       = {}
local paletteIndex   = 0
local seated         = false
local seatWeld       = nil
local prompt         = nil

-- voo
local MAX_SPEED  = 150
local flightPos  = Vector3.zero
local yaw, pitch, roll, speed = 0, 0, 0, 0
local onGround   = true
local hudTimer   = 0
local flashUntil = 0
local upHeld, downHeld = false, false
local flightUI   = nil

-- trem de pouso
local gearT      = 1       -- 1 = baixado, 0 = recolhido
local gearDown   = true
local gearParts  = {}
local refreshGearBtn = function() end

-- queda do avião
local falling    = false
local fallVel    = Vector3.zero

-- acidentes
local destroyed   = false
local CRASH_SPEED = 30     -- acima disso, bater em estrutura = acidente
local CRASH_POINTS = {     -- pontos do avião que "sentem" a colisão
    Vector3.new(0, 0, -13.5),    -- nariz
    Vector3.new(0, 1.5, -6),     -- cabine
    Vector3.new(-21.5, -1.5, 2), -- ponta da asa esquerda
    Vector3.new(21.5, -1.5, 2),  -- ponta da asa direita
}

-- imunidade às hélices (ao entrar/sair)
local killImmune = 0

local PALETTES = {
    { "Clássico",  Color3.fromRGB(240,240,245), Color3.fromRGB(190,40,50),  Color3.fromRGB(215,175,70)  },
    { "Oceano",    Color3.fromRGB(225,235,245), Color3.fromRGB(30,90,200),  Color3.fromRGB(0,200,230)   },
    { "Floresta",  Color3.fromRGB(235,230,210), Color3.fromRGB(30,140,80),  Color3.fromRGB(170,220,80)  },
    { "Executivo", Color3.fromRGB(45,47,55),    Color3.fromRGB(215,175,70), Color3.fromRGB(190,195,205) },
    { "Pôr do Sol",Color3.fromRGB(250,240,230), Color3.fromRGB(240,110,40), Color3.fromRGB(250,200,60)  },
    { "Royal",     Color3.fromRGB(240,235,250), Color3.fromRGB(110,50,190), Color3.fromRGB(240,90,170)  },
}

------------------------------------------------------------
-- PARENT SEGURO
------------------------------------------------------------
local function getGuiParent()
    local ok, res = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if ok and res then return res end
    return player:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()
pcall(function()
    local old = guiParent:FindFirstChild("HangarAvioesGUI")
    if old then old:Destroy() end
end)

------------------------------------------------------------
-- UTILIDADES
------------------------------------------------------------
local controls
pcall(function()
    local pm = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 3)
    controls = require(pm):GetControls()
end)

local function getChar()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

local function planeExists()
    return currentPlane ~= nil and currentPlane.Parent ~= nil
end

-- vetor do joystick: X = direita, Z = trás (frente = -1)
local function getMove(hum)
    local v
    if controls then
        local ok, r = pcall(function() return controls:GetMoveVector() end)
        if ok then v = r end
    end
    if (not v or v.Magnitude < 0.01) and hum and hum.MoveDirection.Magnitude > 0.01 then
        local rel = workspace.CurrentCamera.CFrame:VectorToObjectSpace(hum.MoveDirection)
        v = Vector3.new(rel.X, 0, rel.Z)
    end
    return v or Vector3.zero
end

local function setFlightUI(visible)
    if flightUI then flightUI.Visible = visible end
    if not visible then upHeld, downHeld = false, false end
end

local function flash(text)
    flashUntil = os.clock() + 2
    if prompt and prompt.Parent then prompt.ObjectText = text end
end

-- altura do chão abaixo de uma posição
local function getGroundY(pos)
    local list = { currentPlane }
    if player.Character then table.insert(list, player.Character) end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = list
    local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -500, 0), params)
    return hit and hit.Position.Y or -1e6
end

-- hélices/motores perigosos (só afeta o seu personagem)
local function onDeadlyTouch(hit)
    if destroyed or seated or os.clock() < killImmune then return end
    local char, _, hum = getChar()
    if not char or not hit:IsDescendantOf(char) then return end
    if hum and hum.Health > 0 then hum.Health = 0 end
end

------------------------------------------------------------
-- ENTRAR / SAIR DO AVIÃO
------------------------------------------------------------
local function leavePlane()
    if seatWeld then
        pcall(function() seatWeld:Destroy() end)
        seatWeld = nil
    end
    local _, hrp, hum = getChar()
    if hum then
        hum.Sit = false
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
    end

    if seated and hrp and planeExists() then
        local pv = currentPlane:GetPivot()
        if onGround and speed < 8 then
            -- saída normal: na frente do nariz
            hrp.CFrame = pv * CFrame.new(0, -1.4, -17)
        else
            -- saída em pleno voo: ejeta pra cima e o avião cai
            hrp.CFrame = pv * CFrame.new(0, 5, -4)
            hrp.AssemblyLinearVelocity = pv.LookVector * speed * 0.6 + Vector3.new(0, 12, 0)
            local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
            fallVel = rot.LookVector * speed
            falling = true
        end
    end

    killImmune = os.clock() + 2.5
    seated = false
    speed = 0
    setFlightUI(false)
    if prompt and prompt.Parent then
        prompt.ActionText = "Entrar em Avião"
        prompt.ObjectText = "Bimotor"
    end
end

local function enterPlane()
    if not planeExists() or falling or destroyed then return end
    local _, hrp, hum = getChar()
    if not hrp or not hum then return end
    local cockpit = currentPlane:FindFirstChild("Cockpit")
    if not cockpit then return end

    killImmune = os.clock() + 1.5

    hrp.CFrame = cockpit.CFrame
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = cockpit
    weld.Part1 = hrp
    weld.Parent = cockpit
    seatWeld = weld

    hum.Sit = true
    seated = true

    local pv = currentPlane:GetPivot()
    flightPos = pv.Position
    local look = pv.LookVector
    yaw = math.atan2(-look.X, -look.Z)
    pitch, roll, speed = 0, 0, 0
    onGround = true
    gearDown, gearT = true, 1
    refreshGearBtn()

    setFlightUI(true)
    if prompt and prompt.Parent then prompt.ActionText = "Sair do Avião" end
end

player.CharacterAdded:Connect(function()
    seated = false
    seatWeld = nil
    speed = 0
    setFlightUI(false)
    if prompt and prompt.Parent then
        prompt.ActionText = "Entrar em Avião"
        prompt.ObjectText = "Bimotor"
    end
end)

------------------------------------------------------------
-- CONSTRUÇÃO DO AVIÃO
------------------------------------------------------------
local ZCYL = CFrame.Angles(0, math.rad(90), 0) -- cilindro alinhado ao eixo Z

local function buildPlane(origin)
    local model = Instance.new("Model")
    model.Name = "AviaoBimotor"
    gearParts = {}

    local function add(name, shape, size, cf, color, material, role, transparency, collide)
        local p = Instance.new("Part")
        p.Name = name
        p.Shape = shape
        p.Size = size
        p.CFrame = origin * cf
        p.Anchored = true
        p.CanCollide = collide ~= false
        p.Color = color
        p.Material = material or Enum.Material.SmoothPlastic
        p.Transparency = transparency or 0
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        p:SetAttribute("Role", role)
        p.Parent = model
        return p
    end

    -- parte que mata ao encostar
    local function deadly(p)
        p.Touched:Connect(onDeadlyTouch)
        return p
    end

    -- peça do trem de pouso (recolhível)
    local function addGear(name, shape, size, cf, color, material, role)
        local p = add(name, shape, size, cf, color, material, role)
        table.insert(gearParts, { part = p, cf = cf })
        return p
    end

    local P = PALETTES[1]
    local BODY, STRIPE, ACCENT = P[2], P[3], P[4]
    local Cyl, Blk, Ball = Enum.PartType.Cylinder, Enum.PartType.Block, Enum.PartType.Ball
    local METAL = Color3.fromRGB(150,155,165)
    local GLASS = Color3.fromRGB(40,70,110)
    local TIRE  = Color3.fromRGB(25,25,28)
    local DARK  = Color3.fromRGB(28,28,32)

    -- Fuselagem
    local fuselage = add("Fuselagem", Cyl, Vector3.new(18,3.8,3.8), CFrame.new(0,0,0) * ZCYL, BODY, nil, "Body")
    model.PrimaryPart = fuselage
    fuselage.PivotOffset = ZCYL:Inverse() -- pivô do modelo = origem do avião (nariz em -Z)
    add("Nariz1", Cyl, Vector3.new(2.5,3.4,3.4), CFrame.new(0,-0.05,-10.25) * ZCYL, BODY, nil, "Body")
    add("Nariz2", Cyl, Vector3.new(2,2.8,2.8),   CFrame.new(0,-0.15,-12.5) * ZCYL, BODY, nil, "Body")
    add("Nariz3", Ball, Vector3.new(2.2,2.2,2.2), CFrame.new(0,-0.2,-13.5), STRIPE, nil, "Stripe")
    add("Cauda1", Cyl, Vector3.new(3,3.2,3.2), CFrame.new(0,0.1,10.5) * ZCYL, BODY, nil, "Body")
    add("Cauda2", Cyl, Vector3.new(4,2.5,2.5), CFrame.new(0,0.25,14) * ZCYL, BODY, nil, "Body")
    add("Cauda3", Cyl, Vector3.new(4,1.8,1.8), CFrame.new(0,0.4,18) * ZCYL, BODY, nil, "Body")
    add("PontaCauda", Ball, Vector3.new(1.8,1.8,1.8), CFrame.new(0,0.4,20), STRIPE, nil, "Stripe")

    -- Para-brisa e janelas
    add("ParaBrisa", Blk, Vector3.new(2.4,1,0.2), CFrame.new(0,1.2,-9.6) * CFrame.Angles(math.rad(-40),0,0),
        GLASS, Enum.Material.Glass, "Glass", 0.15, false)
    for i = 0, 4 do
        local z = -6 + i * 2.6
        add("JanelaE"..i, Blk, Vector3.new(0.12,1,1.3), CFrame.new(-1.88,0.6,z), GLASS, Enum.Material.Glass, "Glass", 0.1, false)
        add("JanelaD"..i, Blk, Vector3.new(0.12,1,1.3), CFrame.new( 1.88,0.6,z), GLASS, Enum.Material.Glass, "Glass", 0.1, false)
    end

    -- Faixas laterais
    for _, s in ipairs({-1, 1}) do
        add("Faixa"..s, Blk, Vector3.new(0.1,0.4,18), CFrame.new(s*1.9,-0.3,0), STRIPE, nil, "Stripe", 0, false)
        add("FaixaFina"..s, Blk, Vector3.new(0.1,0.15,18), CFrame.new(s*1.86,-0.85,0), ACCENT, nil, "Accent", 0, false)
    end

    -- Asas
    add("AsaRaiz", Blk, Vector3.new(9,0.9,6.8), CFrame.new(0,-1.4,1.2), BODY, nil, "Body")
    for _, s in ipairs({-1, 1}) do
        add("AsaMeio"..s,  Blk, Vector3.new(10,0.65,5.6), CFrame.new(s*9.5,-1.45,1.5), BODY, nil, "Body")
        add("AsaPonta"..s, Blk, Vector3.new(5,0.45,4),    CFrame.new(s*17,-1.5,2),   BODY, nil, "Body")
        add("BordaAsa"..s, Blk, Vector3.new(15,0.7,0.35), CFrame.new(s*12,-1.45,-1.3), STRIPE, nil, "Stripe", 0, false)
        add("TanqueAsa"..s, Cyl, Vector3.new(4,1,1), CFrame.new(s*19.8,-1.5,2) * ZCYL, ACCENT, nil, "Accent")
    end
    add("LuzVermelha", Ball, Vector3.new(0.6,0.6,0.6), CFrame.new(-21.9,-1.5,2), Color3.fromRGB(255,40,40), Enum.Material.Neon, "Light", 0, false)
    add("LuzVerde",    Ball, Vector3.new(0.6,0.6,0.6), CFrame.new( 21.9,-1.5,2), Color3.fromRGB(40,255,90), Enum.Material.Neon, "Light", 0, false)

    -- Cauda
    add("Leme", Blk, Vector3.new(0.4,6,4.5), CFrame.new(0,3.4,17.5) * CFrame.Angles(math.rad(18),0,0), STRIPE, nil, "Stripe")
    add("EstabilizadorH", Blk, Vector3.new(11,0.35,3), CFrame.new(0,0.5,18.2), BODY, nil, "Body")

    -- Motores + hélices de 3 pás (PERIGOSOS)
    spinners = {}
    for _, s in ipairs({-1, 1}) do
        local x = s * 8
        deadly(add("Nacela"..s,  Cyl, Vector3.new(7,2.2,2.2), CFrame.new(x,-1,-1.5) * ZCYL, BODY, nil, "Body"))
        deadly(add("Entrada"..s, Cyl, Vector3.new(0.5,1.8,1.8), CFrame.new(x,-1,-5.1) * ZCYL, DARK, nil, "Tire", 0, false))
        deadly(add("Spinner"..s, Ball, Vector3.new(1.4,1.4,1.4), CFrame.new(x,-1,-5.4), ACCENT, nil, "Accent"))

        local hubCF  = CFrame.new(x,-1,-5.7)
        local hubRel = fuselage.CFrame:ToObjectSpace(origin * hubCF)
        for k = 0, 2 do
            local loc = CFrame.Angles(0, 0, math.rad(k * 120)) * CFrame.new(0, 2.2, 0)
            local blade = deadly(add("Helice"..s.."_"..k, Blk, Vector3.new(0.6,4.4,0.15), hubCF * loc, DARK, nil, "Prop", 0, false))
            table.insert(spinners, { part = blade, hub = hubRel, loc = loc })
        end
        deadly(add("DiscoHelice"..s, Cyl, Vector3.new(0.05,8.8,8.8), hubCF * ZCYL, Color3.fromRGB(200,200,210),
            Enum.Material.SmoothPlastic, "Disc", 0.9, false))
    end

    -- Trem de aterragem triciclo (recolhível)
    addGear("HasteNariz", Blk, Vector3.new(0.3,1.7,0.3), CFrame.new(0,-2.75,-8), METAL, Enum.Material.Metal, "Metal")
    addGear("RodaNariz", Cyl, Vector3.new(0.5,1.8,1.8), CFrame.new(0,-3.5,-8), TIRE, nil, "Tire")
    for _, s in ipairs({-1, 1}) do
        addGear("HastePrincipal"..s, Blk, Vector3.new(0.4,2,0.4), CFrame.new(s*8,-2.7,-0.5), METAL, Enum.Material.Metal, "Metal")
        addGear("RodaPrincipal"..s, Cyl, Vector3.new(0.6,1.8,1.8), CFrame.new(s*8,-3.5,-0.5), TIRE, nil, "Tire")
    end

    -- Assento invisível do cockpit
    add("Cockpit", Blk, Vector3.new(1,1,1), CFrame.new(0,0.6,-5), Color3.new(1,1,1), nil, "Cockpit", 1, false)

    -- ProximityPrompt
    prompt = Instance.new("ProximityPrompt")
    prompt.Name = "PromptAviao"
    prompt.ActionText = "Entrar em Avião"
    prompt.ObjectText = "Bimotor"
    prompt.HoldDuration = 0.3
    prompt.MaxActivationDistance = 16
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.Parent = fuselage
    prompt.Triggered:Connect(function(who)
        if who ~= player then return end
        if destroyed then return end
        if seated then
            leavePlane()                    -- pode sair até em pleno voo
        elseif falling then
            flash("Avião em queda!")
        else
            enterPlane()
        end
    end)

    return model
end

------------------------------------------------------------
-- ACIDENTES
------------------------------------------------------------
-- fumaça e fogo no avião destruído
local function addSmoke()
    for _, n in ipairs({ "Nacela-1", "Nacela1", "Fuselagem" }) do
        local part = currentPlane:FindFirstChild(n)
        if part then
            local pe = Instance.new("ParticleEmitter")
            pe.Color = ColorSequence.new(Color3.fromRGB(30, 30, 30), Color3.fromRGB(120, 120, 120))
            pe.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 2),
                NumberSequenceKeypoint.new(1, 10),
            })
            pe.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.3),
                NumberSequenceKeypoint.new(1, 1),
            })
            pe.Lifetime = NumberRange.new(2.5, 4)
            pe.Rate = 25
            pe.Speed = NumberRange.new(4, 8)
            pe.SpreadAngle = Vector2.new(25, 25)
            pe.Acceleration = Vector3.new(0, 6, 0)
            pe.Parent = part

            if n ~= "Fuselagem" then
                local fire = Instance.new("Fire")
                fire.Size = 7
                fire.Heat = 8
                fire.Parent = part
                task.delay(15, function()
                    if fire and fire.Parent then fire:Destroy() end
                end)
            end
        end
    end
end

-- bate, explode, escurece, solta fumaça e mata o piloto
local function crashPlane(pos, vel)
    if destroyed or not planeExists() then return end
    destroyed = true

    pcall(function()
        local ex = Instance.new("Explosion")
        ex.Position = pos
        ex.BlastRadius = 14
        ex.BlastPressure = 0
        ex.DestroyJointRadiusPercent = 0
        ex.ExplosionType = Enum.ExplosionType.NoCraters
        ex.Parent = workspace
        for _, part in ipairs(currentPlane:GetDescendants()) do
            if part:IsA("BasePart") then
                local r = part:GetAttribute("Role")
                if r == "Body" or r == "Stripe" or r == "Accent" then
                    TweenService:Create(part, TweenInfo.new(0.6), { Color = Color3.fromRGB(38, 35, 34) }):Play()
                end
            end
        end
    end)
    pcall(addSmoke)

    if seated then
        seated = false
        if seatWeld then
            pcall(function() seatWeld:Destroy() end)
            seatWeld = nil
        end
        local _, _, hum = getChar()
        if hum then
            hum.Sit = false
            hum.Health = 0
        end
        setFlightUI(false)
    end

    speed = 0
    falling = true
    fallVel = vel or Vector3.zero
    if prompt and prompt.Parent then
        prompt.ObjectText = "Destruído"
        prompt.Enabled = false
    end
end

-- raios nos pontos do avião: acha parede/estrutura no caminho
local function checkObstacle(fromPos, toPos, poseCF)
    local delta = toPos - fromPos
    local dist = delta.Magnitude
    if dist < 0.01 then return nil end
    local dir = delta.Unit

    local list = { currentPlane }
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then table.insert(list, pl.Character) end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = list
    params.IgnoreWater = true
    pcall(function() params.RespectCanCollide = true end)

    for _, off in ipairs(CRASH_POINTS) do
        local origin = poseCF:PointToWorldSpace(off)
        local hit = workspace:Raycast(origin, dir * (dist + 1.5), params)
        -- normal quase horizontal = parede/lateral; chão plano é tratado à parte
        if hit and hit.Normal.Y < 0.65 then
            return hit
        end
    end
    return nil
end

------------------------------------------------------------
-- VOO (roda a cada frame enquanto o jogador está sentado)
------------------------------------------------------------
local function flightStep(dt)
    if not seated or not planeExists() then return end
    local char, hrp, hum = getChar()
    if not hrp or not hum then return end
    local cockpit = currentPlane:FindFirstChild("Cockpit")
    if not cockpit then return end

    -- mantém sentado (o pulo do jogo não tira você do avião)
    if not hum.Sit then hum.Sit = true end
    if hum:GetState() == Enum.HumanoidStateType.Jumping then
        hum:ChangeState(Enum.HumanoidStateType.Seated)
    end

    local mv = getMove(hum)
    local fwd, side = -mv.Z, mv.X
    if math.abs(fwd) < 0.15 then fwd = 0 end
    if math.abs(side) < 0.15 then side = 0 end

    -- velocidade
    if fwd > 0 then
        speed = math.min(MAX_SPEED, speed + fwd * 35 * dt)
    elseif fwd < 0 then
        speed = math.max(0, speed + fwd * 55 * dt)
    elseif onGround then
        speed = math.max(0, speed - 6 * dt)
    end
    -- pouso de barriga (trem recolhido) freia forte
    if onGround and gearT < 0.5 then
        speed = math.max(0, speed - 45 * dt)
    end

    -- curva (só funciona com velocidade)
    local turn = math.clamp(speed / 25, 0, 1)
    yaw = yaw - side * 1.0 * turn * dt

    -- subir / descer com os botões ⬆️ ⬇️
    local target = 0
    if not onGround and speed < 22 then
        target = math.rad(-22)          -- estol
    elseif upHeld and speed > 28 then
        target = math.rad(22)
    elseif downHeld and not onGround then
        target = math.rad(-25)
    end
    pitch = pitch + (target - pitch) * math.min(1, dt * 3)
    roll  = roll + ((-side * math.rad(28) * turn) - roll) * math.min(1, dt * 4)

    local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
    local newPos = flightPos + rot.LookVector * speed * dt

    -- colisão com estruturas
    if speed > 1 then
        local poseCF = CFrame.new(flightPos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
        local hit = checkObstacle(flightPos, newPos, poseCF)
        if hit then
            if speed > CRASH_SPEED then
                crashPlane(hit.Position, hit.Normal * 12)
                return
            else
                speed = 0
                newPos = flightPos
            end
        end
    end

    -- chão (a altura depende do trem de pouso)
    local groundY = getGroundY(newPos)
    local clearance = 2.2 + 2.2 * gearT
    local minY = groundY + clearance
    if newPos.Y <= minY + 0.05 then
        -- mergulho forte demais no chão = acidente
        local sink = (flightPos.Y - newPos.Y) / math.max(dt, 1e-3)
        if not onGround and sink > 55 then
            crashPlane(Vector3.new(newPos.X, groundY, newPos.Z), rot.LookVector * speed * 0.2)
            return
        end
        newPos = Vector3.new(newPos.X, minY, newPos.Z)
        onGround = true
        if pitch < 0 then pitch = 0 end
    else
        onGround = false
    end

    flightPos = newPos
    currentPlane:PivotTo(CFrame.new(newPos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll))

    hrp.CFrame = cockpit.CFrame
    hrp.AssemblyLinearVelocity = Vector3.zero

    -- velocidade, altitude e trem no texto do prompt
    hudTimer = hudTimer + dt
    if hudTimer > 0.25 and prompt and prompt.Parent then
        hudTimer = 0
        if os.clock() > flashUntil then
            local alt = math.max(0, math.floor(newPos.Y - groundY - clearance))
            prompt.ObjectText = string.format("%d km/h | alt %d | trem %s",
                math.floor(speed * 1.2), alt, gearDown and "baixo" or "recolhido")
        end
    end
end

-- avião sem piloto / destruído: cai, bate e explode
local function fallStep(dt)
    if not falling or not planeExists() then return end

    if not onGround then
        fallVel = fallVel + Vector3.new(0, -70, 0) * dt
    end
    pitch = pitch + (math.rad(-55) - pitch) * math.min(1, dt * 1.5)
    roll  = roll + dt * 1.2

    local newPos = flightPos + fallVel * dt

    -- avião em queda bate em estrutura
    if not destroyed and fallVel.Magnitude > 5 then
        local poseCF = CFrame.new(flightPos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
        local hit = checkObstacle(flightPos, newPos, poseCF)
        if hit then
            crashPlane(hit.Position, hit.Normal * 10)
            return
        end
    end

    local groundY = getGroundY(newPos)
    local minY = groundY + 2.2 + 2.2 * gearT

    if newPos.Y <= minY + 0.05 then
        newPos = Vector3.new(newPos.X, minY, newPos.Z)
        if not onGround and not destroyed and fallVel.Magnitude > 30 then
            crashPlane(newPos, Vector3.zero)       -- impacto forte = explosão
        end
        onGround = true
        local f = 1 - math.min(1, 3 * dt)
        fallVel = Vector3.new(fallVel.X * f, 0, fallVel.Z * f)
        pitch = pitch + (0 - pitch) * math.min(1, dt * 4)
        if fallVel.Magnitude < 1.5 then
            falling = false
            fallVel = Vector3.zero
            speed, pitch, roll = 0, 0, 0
        end
    else
        onGround = false
    end

    flightPos = newPos
    currentPlane:PivotTo(CFrame.new(newPos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll))
end

-- animação do trem de pouso
local function gearStep(dt)
    if not planeExists() then return end
    local target = gearDown and 1 or 0
    if gearT < target then
        gearT = math.min(target, gearT + dt * 1.2)
    elseif gearT > target then
        gearT = math.max(target, gearT - dt * 1.2)
    end
    local pv = currentPlane:GetPivot()
    local lift = CFrame.new(0, (1 - gearT) * 2.3, 0)
    for _, g in ipairs(gearParts) do
        if g.part and g.part.Parent then
            g.part.CFrame = pv * lift * g.cf
            g.part.CanCollide = gearT > 0.5
        end
    end
end

local function toggleGear()
    if not seated then return end
    if onGround and gearDown then
        flash("Trem só recolhe no ar")
        return
    end
    gearDown = not gearDown
    refreshGearBtn()
end

------------------------------------------------------------
-- AÇÕES
------------------------------------------------------------
local function stopSpin()
    if spinConnection then spinConnection:Disconnect() spinConnection = nil end
    spinners = {}
end

local function deletePlane()
    if seated then leavePlane() end
    stopSpin()
    falling = false
    fallVel = Vector3.zero
    destroyed = false
    if currentPlane then
        pcall(function() currentPlane:Destroy() end)
        currentPlane = nil
    end
    prompt = nil
end

local function spawnPlane()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "Personagem não encontrado!" end

    deletePlane()

    local flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
    if flat.Magnitude < 0.01 then flat = Vector3.new(0,0,-1) end
    flat = flat.Unit
    local pos = hrp.Position + flat * 45
    local groundY = hrp.Position.Y - 3
    local p = Vector3.new(pos.X, groundY + 4.4, pos.Z)
    local origin = CFrame.lookAt(p, p + flat)

    gearDown, gearT = true, 1
    destroyed = false
    local ok, model = pcall(buildPlane, origin)
    if not ok then return false, "Erro: " .. tostring(model):sub(1, 40) end

    model.Parent = workspace
    currentPlane = model
    paletteIndex = 0

    -- loop único: voo + queda + trem + hélices
    local angle = 0
    local root = model.PrimaryPart
    spinConnection = RunService.Heartbeat:Connect(function(dt)
        if not planeExists() or not root or not root.Parent then return stopSpin() end
        flightStep(dt)
        fallStep(dt)
        gearStep(dt)
        if not destroyed then
            angle = angle + dt * (18 + speed * 0.4)
        end
        for _, s in ipairs(spinners) do
            if s.part and s.part.Parent then
                s.part.CFrame = root.CFrame * s.hub * CFrame.Angles(0, 0, angle) * s.loc
            end
        end
        -- volta o texto normal do prompt depois de um aviso
        if not destroyed and not seated and prompt and prompt.Parent and os.clock() > flashUntil
            and prompt.ObjectText ~= "Bimotor" then
            prompt.ObjectText = "Bimotor"
        end
    end)
    return true, "Avião criado!"
end

local function recolorPlane()
    if not planeExists() then return false, "Crie um avião primeiro!" end
    if destroyed then return false, "Avião destruído!" end
    paletteIndex = paletteIndex % #PALETTES + 1
    local pal = PALETTES[paletteIndex]
    local map = { Body = pal[2], Stripe = pal[3], Accent = pal[4] }
    local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    for _, part in ipairs(currentPlane:GetDescendants()) do
        if part:IsA("BasePart") then
            local c = map[part:GetAttribute("Role")]
            if c then pcall(function() TweenService:Create(part, info, { Color = c }):Play() end) end
        end
    end
    return true, "Tema: " .. pal[1]
end

local function removePlane()
    if not planeExists() then return false, "Nenhum avião para excluir!" end
    deletePlane()
    return true, "Avião removido!"
end

------------------------------------------------------------
-- INTERFACE
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HangarAvioesGUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local main = Instance.new("Frame")
main.Name = "Painel"
main.Size = UDim2.new(0, 270, 0, 292)
main.Position = UDim2.new(0.5, -135, 0.5, -146)
main.BackgroundColor3 = Color3.fromRGB(18, 19, 26)
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)

local mainGrad = Instance.new("UIGradient", main)
mainGrad.Rotation = 90
mainGrad.Color = ColorSequence.new(Color3.fromRGB(28, 30, 42), Color3.fromRGB(14, 15, 20))

local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = Color3.fromRGB(70, 75, 100)
mainStroke.Thickness = 1.5
mainStroke.Transparency = 0.2

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 46)
titleBar.BackgroundTransparency = 1
titleBar.Parent = main

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 1, 0)
title.Position = UDim2.new(0, 16, 0, 0)
title.BackgroundTransparency = 1
title.Text = "✈  Hangar de Aviões"
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.TextColor3 = Color3.fromRGB(240, 242, 250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local function smallBtn(text, xOff, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 28, 0, 28)
    b.Position = UDim2.new(1, xOff, 0.5, -14)
    b.BackgroundColor3 = color
    b.BackgroundTransparency = 0.15
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 16
    b.TextColor3 = Color3.new(1, 1, 1)
    b.AutoButtonColor = false
    b.Parent = titleBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end
local minBtn   = smallBtn("–", -70, Color3.fromRGB(60, 64, 85))
local closeBtn = smallBtn("×", -36, Color3.fromRGB(170, 50, 60))

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -32, 0, 1)
divider.Position = UDim2.new(0, 16, 0, 46)
divider.BackgroundColor3 = Color3.fromRGB(60, 64, 85)
divider.BorderSizePixel = 0
divider.Parent = main

local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 1, -48)
content.Position = UDim2.new(0, 0, 0, 48)
content.BackgroundTransparency = 1
content.Parent = main

local layout = Instance.new("UIListLayout", content)
layout.Padding = UDim.new(0, 10)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new("UIPadding", content)
pad.PaddingTop = UDim.new(0, 14)

local status = Instance.new("TextLabel")
status.LayoutOrder = 10
status.Size = UDim2.new(1, -32, 0, 24)
status.BackgroundTransparency = 1
status.Text = "Pronto para decolar"
status.Font = Enum.Font.GothamMedium
status.TextSize = 13
status.TextColor3 = Color3.fromRGB(140, 145, 170)
status.Parent = content

local statusToken = 0
local function setStatus(text, ok)
    statusToken += 1
    local my = statusToken
    status.Text = text
    status.TextColor3 = ok and Color3.fromRGB(110, 230, 150) or Color3.fromRGB(255, 120, 120)
    task.delay(4, function()
        if my == statusToken and status.Parent then
            status.Text = "Pronto para decolar"
            status.TextColor3 = Color3.fromRGB(140, 145, 170)
        end
    end)
end

local function makeButton(order, icon, text, color, callback)
    local btn = Instance.new("TextButton")
    btn.LayoutOrder = order
    btn.Size = UDim2.new(1, -32, 0, 46)
    btn.BackgroundColor3 = color
    btn.AutoButtonColor = false
    btn.Text = icon .. "   " .. text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 16
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Parent = content
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)

    local grad = Instance.new("UIGradient", btn)
    grad.Rotation = 90
    grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))

    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
    stroke.Thickness = 1.2
    stroke.Transparency = 0.4

    local t = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
    local base = btn.Size
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, t, { BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.15) }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, t, { BackgroundColor3 = color, Size = base }):Play()
    end)
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, t, { Size = UDim2.new(1, -40, 0, 42) }):Play()
    end)
    btn.Activated:Connect(function()
        TweenService:Create(btn, t, { Size = base }):Play()
        local ok, a, b = pcall(callback)
        if ok then
            setStatus(b or "", a)
        else
            setStatus("Erro: " .. tostring(a):sub(1, 40), false)
        end
    end)
    return btn
end

makeButton(1, "🛫", "Criar Avião",   Color3.fromRGB(40, 175, 95),  spawnPlane)
makeButton(2, "🎨", "Editor Cor",    Color3.fromRGB(50, 120, 220), recolorPlane)
makeButton(3, "🗑", "Excluir Avião", Color3.fromRGB(215, 60, 70),  removePlane)

------------------------------------------------------------
-- BOTÕES DE VOO ⬆️ ⬇️ ⚙️ (só aparecem sentado no avião)
------------------------------------------------------------
flightUI = Instance.new("Frame")
flightUI.Name = "BotoesVoo"
flightUI.AnchorPoint = Vector2.new(1, 1)
flightUI.Position = UDim2.new(1, -24, 1, -150) -- acima do botão de pulo; ajuste aqui se quiser mover
flightUI.Size = UDim2.new(0, 68, 0, 224)
flightUI.BackgroundTransparency = 1
flightUI.Visible = false
flightUI.Parent = gui

local function makeFlightBtn(icon, yPos, onChange)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 68, 0, 68)
    b.Position = UDim2.new(0, 0, 0, yPos)
    b.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
    b.BackgroundTransparency = 0.1
    b.AutoButtonColor = false
    b.Text = icon
    b.Font = Enum.Font.GothamBold
    b.TextSize = 30
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Parent = flightUI
    Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
    local st = Instance.new("UIStroke", b)
    st.Color = Color3.fromRGB(110, 120, 170)
    st.Thickness = 2
    st.Transparency = 0.2

    local tw = TweenInfo.new(0.1, Enum.EasingStyle.Quad)
    local function press(down)
        onChange(down)
        TweenService:Create(b, tw, {
            BackgroundColor3 = down and Color3.fromRGB(60, 130, 230) or Color3.fromRGB(28, 30, 42)
        }):Play()
    end
    b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            press(true)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then press(false) end
            end)
        end
    end)
    b.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then press(false) end
    end)
    return b, st
end

makeFlightBtn("⬆️", 0,  function(d) upHeld = d end)
makeFlightBtn("⬇️", 78, function(d) downHeld = d end)

-- botão do trem de pouso (contorno verde = baixo, laranja = recolhido)
local _, gearStroke = makeFlightBtn("⚙️", 156, function(d)
    if d then toggleGear() end
end)
refreshGearBtn = function()
    gearStroke.Color = gearDown and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(255, 160, 50)
end
refreshGearBtn()

------------------------------------------------------------
-- ARRASTAR (mouse e toque)
------------------------------------------------------------
local dragging, dragStart, startPos
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, input.Position, main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                  startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

------------------------------------------------------------
-- MINIMIZAR / FECHAR
------------------------------------------------------------
local minimized = false
minBtn.Activated:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    TweenService:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
        { Size = UDim2.new(0, 270, 0, minimized and 47 or 292) }):Play()
    minBtn.Text = minimized and "+" or "–"
end)

closeBtn.Activated:Connect(function()
    deletePlane()
    gui:Destroy()
end)

main.Size = UDim2.new(0, 270, 0, 0)
TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Size = UDim2.new(0, 270, 0, 292) }):Play()
