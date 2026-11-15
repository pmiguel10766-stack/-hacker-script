-- TIV_Tornado_Spawner.lua v5 | Roblox / Delta Executor
-- Teclas PC: F ancoragem | L luzes | T tornado | E entrar | C câmera | R chuva | H caçador | X arrancar | Z restaurar | Shift nitro
-- v5: realismo (ciclo de vida, Terrain.Clouds, Atmosphere, vento global, céu escurecido), mapa meteorológico no HUD

task.spawn(function()
local ok0, e0 = pcall(function()
local Players, RS, TS, UIS, WS, CG, LT = game:GetService("Players"), game:GetService("RunService"), game:GetService("TweenService"), game:GetService("UserInputService"), game:GetService("Workspace"), game:GetService("CoreGui"), game:GetService("Lighting")
local plr = Players.LocalPlayer
local V3, CF, M = Vector3.new, CFrame.new, Enum.Material
local TAG, GUI, MDL, TOR = "TIV_Generated", "TIV_HUD", "TIV_Dominator", "TIV_Tornado"
local IDLE, MAXR, TH = 850, 8200, 130
local tiv, tor, rainP, rainE
local SKY, mapHist, mapLast, cloudP, cloudE = {}, {}, 0, nil, nil
local S = {anch = false, lights = false, rpm = IDLE, shown = IDLE, speed = 0, yaw = 0, spin = 0, steer = 0, ext = V3(), tr = 40, an = 0,
	fuel = 1, nit = false, nb = false, cam = true, rain = false, hunt = false, k = 0, ft = false, fov = 70, lt = 4, grab = true, gc = 0, gmax = 500, fly = false, lf = 0, gh = 3, gt = 0}
local conns, ui = {}, {}
local baseB
local G = {} -- pecas arrancadas {parte = CFrame original}

local function new(c, p, par) local i = Instance.new(c) for k, v in pairs(p or {}) do i[k] = v end if par then i.Parent = par end return i end
local function safe(f) return function(...) pcall(f, ...) end end
local function track(c) conns[#conns + 1] = c return c end

-- LIMPEZA AUTOMÁTICA
local env = (pcall(getgenv) and getgenv()) or _G
local function wipe()
	for _, i in ipairs(WS:GetChildren()) do
		if i:GetAttribute(TAG) or i.Name == MDL or i.Name == TOR then pcall(i.Destroy, i) end
	end
	local cs = {CG, plr:FindFirstChildOfClass("PlayerGui")}
	pcall(function() if gethui then cs[#cs + 1] = gethui() end end)
	for _, c in ipairs(cs) do pcall(function()
		for _, i in ipairs(c:GetChildren()) do
			if i:IsA("ScreenGui") and (i.Name == GUI or i:GetAttribute(TAG)) then i:Destroy() end
		end
	end) end
end
if env.TIV_CLEANUP then pcall(env.TIV_CLEANUP) end
baseB = LT.Brightness
env.TIV_CLEANUP = function()
	for _, c in ipairs(conns) do pcall(c.Disconnect, c) end
	table.clear(conns)
	pcall(RS.UnbindFromRenderStep, RS, "TIV_Cam")
	pcall(function()
		local c = WS.CurrentCamera
		if c and S.ft then c.FieldOfView = S.fov end
		LT.Brightness = baseB
	end)
	for p, cf in pairs(G) do pcall(function() p.Anchored = true p.AssemblyLinearVelocity = V3() p.AssemblyAngularVelocity = V3() p.CFrame = cf end) end
	table.clear(G)
	if tor and tor.hums then for hm in pairs(tor.hums) do pcall(function() hm.PlatformStand = false end) end end
	if SKY.atm and SKY.atm.Parent then
		pcall(function()
			SKY.atm.Density, SKY.atm.Haze, SKY.atm.Color, SKY.atm.Glare = SKY.d0, SKY.h0, SKY.c0, SKY.g0
			if SKY.created then SKY.atm:Destroy() end
		end)
	end
	pcall(function()
		LT.Ambient, LT.OutdoorAmbient = SKY.amb, SKY.oamb
		WS.GlobalWind = SKY.wind
		local cl = SKY.cl_obj
		if cl and cl.Parent then
			cl.Cover, cl.Density, cl.Color, cl.Enabled = SKY.cov0, SKY.den0, SKY.ccol0, SKY.cen0
			if SKY.cloudsCreated then cl:Destroy() end
		end
	end)
	SKY = {}
	tiv, tor = nil, nil wipe()
end
wipe()

local function groundY(p, fb)
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {tiv and tiv.model or nil, tor and tor.model or nil, plr.Character}
	local r = WS:Raycast(V3(p.X, p.Y + 120, p.Z), V3(0, -400, 0), rp)
	return r and r.Position.Y or fb
end

-- VEÍCULO
local function buildTIV()
	local model = new("Model", {Name = MDL}) model:SetAttribute(TAG, true)
	local core = new("Part", {Name = "Core", Size = V3(1, 1, 1), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false}, model)
	model.PrimaryPart = core
	local ST, SL, BK, GL, AM = Color3.fromRGB(36, 38, 43), Color3.fromRGB(60, 64, 72), Color3.fromRGB(14, 15, 18), Color3.fromRGB(24, 44, 58), Color3.fromRGB(230, 150, 20)
	local CYL, VERT = Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.rad(90))
	local function P(n, sz, rel, col, mat, o)
		o = o or {}
		local p = Instance.new(o.class or "Part")
		p.Name, p.Size, p.Color, p.Material, p.Transparency = n, sz, col, mat or M.Metal, o.tr or 0
		if o.shape then p.Shape = o.shape end
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, o.col or false, false, o.col or false, not o.heavy
		local base = o.to or core
		p.CFrame = base.CFrame * rel p.Parent = model
		local w = new("Weld", {Part0 = base, Part1 = p, C0 = rel}, p)
		return p, w
	end
	-- colisão
	P("Chassis", V3(8, 0.4, 18), CF(0, -2, 0), BK, nil, {col = true, heavy = true, tr = 1}).CustomPhysicalProperties = PhysicalProperties.new(1.5, 0.05, 0, 1, 1)
	P("Hull", V3(9.4, 2.7, 19), CF(0, -0.35, 0), ST, nil, {col = true, heavy = true}).CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.05, 0, 1, 1)
	-- blindagem inclinada
	P("Hood", V3(9.2, 1, 4), CF(0, 1.5, -7.5), ST) P("HoodPlate", V3(8.4, 0.2, 3.4), CF(0, 2.05, -7.5), SL, M.DiamondPlate)
	P("Plow", V3(9.6, 2.79, 0.3), CF(0, -0.3, -10) * CFrame.Angles(math.rad(21), 0, 0), SL)
	P("Grille", V3(4.2, 0.8, 0.2), CF(0, 1.5, -9.55), BK)
	local wa = math.rad(52.4)
	P("Windshield", V3(7.9, 0.15, 3.28), CF(0, 3.3, -4.5) * CFrame.Angles(-wa, 0, 0), GL, M.Glass, {tr = 0.35})
	P("Roof", V3(8.8, 0.35, 9.8), CF(0, 4.775, 1.25), SL) P("RoofPlate", V3(7.6, 0.1, 8.4), CF(0, 4.99, 1.25), ST, M.DiamondPlate)
	P("BackWall", V3(8.6, 3.6, 0.35), CF(0, 2.8, 6), ST)
	P("RearSlab", V3(9, 0.35, 4.6), CF(0, 2.8, 7.65) * CFrame.Angles(math.rad(44.1), 0, 0), SL) P("RearFill", V3(9, 1, 2.4), CF(0, 1.5, 7.2), ST)
	for _, sx in ipairs({-1, 1}) do
		P("Wall", V3(0.35, 1.4, 9.5), CF(sx * 4.15, 1.7, 1.25), ST)
		P("APillar", V3(0.35, 3.28, 0.35), CF(sx * 4.2, 3.3, -4.5) * CFrame.Angles(math.rad(37.6), 0, 0), SL)
		P("WinA", V3(0.15, 2, 3.2), CF(sx * 4.2, 3.5, -1.5), GL, M.Glass, {tr = 0.35})
		P("WinB", V3(0.15, 2, 3.4), CF(sx * 4.2, 3.5, 2.6), GL, M.Glass, {tr = 0.35})
		P("BPillar", V3(0.5, 2.2, 0.6), CF(sx * 4.2, 3.5, 0.5), SL) P("CPillar", V3(0.4, 2.2, 1.7), CF(sx * 4.2, 3.5, 5.15), SL, M.DiamondPlate)
		P("Rail", V3(0.5, 0.25, 10), CF(sx * 4.2, 4.6, 1.25), SL)
		for k = 0, 2 do P("Bar", V3(0.2, 2, 0.12), CF(sx * 4.3, 3.5, -2.6 + k), BK) end
		local pn = P("SidePanel", V3(0.3, 2.7, 8), CF(sx * 4.85, -0.35, 0) * CFrame.Angles(0, 0, -sx * math.rad(8)), SL)
		local sg = new("SurfaceGui", {Face = sx == 1 and Enum.NormalId.Right or Enum.NormalId.Left, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = Vector2.new(480, 162), LightInfluence = 0}, pn)
		new("TextLabel", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "DOMINATOR 3", TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(215, 120, 50)}, sg)
		P("Tail", V3(1.2, 0.6, 0.2), CF(sx * 3.5, -0.2, 9.6), Color3.fromRGB(190, 20, 20), M.Neon)
	end
	-- interior / bancos
	P("Dash", V3(7.6, 1.2, 1.4), CF(0, 1.6, -3.5), BK, M.SmoothPlastic)
	local seat = P("DriverSeat", V3(2, 0.4, 2), CF(-2, 1.2, 0.8), BK, M.Fabric, {class = "VehicleSeat"})
	seat.MaxSpeed, seat.Torque, seat.TurnSpeed, seat.HeadsUpDisplay = 0, 0, 0, false
	seat.CanTouch, seat.CanCollide = true, true -- CORREÇÃO: sem CanTouch o jogador não senta
	P("SeatBack", V3(2, 2, 0.3), CF(-2, 2.3, 1.7), BK, M.Fabric)
	-- luzes
	local heads = {}
	for _, sx in ipairs({-1, 1}) do
		local h = P("Headlight", V3(1.4, 0.6, 0.25), CF(sx * 3.4, 1.5, -9.62), Color3.fromRGB(120, 120, 110), M.SmoothPlastic)
		heads[#heads + 1] = {h, new("SpotLight", {Face = Enum.NormalId.Front, Range = 60, Angle = 75, Brightness = 6, Enabled = false}, h)}
		local r = P("RoofSpot", V3(1, 0.8, 1), CF(sx * 3, 5.4, -2.8), Color3.fromRGB(120, 120, 110), M.SmoothPlastic)
		heads[#heads + 1] = {r, new("SpotLight", {Face = Enum.NormalId.Front, Range = 60, Angle = 45, Brightness = 8, Enabled = false}, r)}
	end
	local lamp = P("CabinLamp", V3(0.8, 0.15, 0.8), CF(0, 4.55, 1), Color3.fromRGB(110, 110, 100), M.SmoothPlastic)
	local cabin = new("PointLight", {Range = 18, Brightness = 1.6, Color = Color3.fromRGB(255, 225, 170), Enabled = false}, lamp)
	P("LedBar", V3(8.6, 0.25, 0.6), CF(0, 4.98, -3.6), BK)
	local leds = {}
	for i = 0, 5 do leds[#leds + 1] = P("LED", V3(1.1, 0.3, 0.4), CF(-3.5 + i * 1.4, 5.2, -3.6), Color3.fromRGB(40, 40, 46), M.SmoothPlastic) end
	-- mastros de telemetria
	P("Mast", V3(5, 0.25, 0.25), CF(2.8, 7.45, 4.2) * VERT, SL, nil, {shape = CYL})
	for i = 0, 3 do P("Shield", V3(0.12, 1, 1), CF(2.8, 8.3 + i * 0.2, 4.2) * VERT, Color3.fromRGB(235, 235, 235), M.SmoothPlastic, {shape = CYL}) end
	local abase = CF(2.8, 10.15, 4.2)
	local hub, aw = P("AnemoHub", V3(0.4, 0.4, 0.4), abase, AM)
	P("ArmX", V3(2.4, 0.12, 0.12), CF(), AM, nil, {to = hub}) P("ArmZ", V3(0.12, 0.12, 2.4), CF(), AM, nil, {to = hub})
	P("Antenna", V3(7, 0.12, 0.12), CF(-3.6, 8.45, 5) * VERT, BK, nil, {shape = CYL})
	local beacon = P("Beacon", V3(0.4, 0.4, 0.4), CF(-3.6, 12.1, 5), Color3.fromRGB(60, 10, 10), M.Neon, {shape = Enum.PartType.Ball})
	P("Dish", V3(0.2, 1.8, 1.8), CF(-2.2, 5.3, -0.5) * CFrame.Angles(math.rad(-35), 0, 0) * VERT, Color3.fromRGB(235, 235, 235), nil, {shape = CYL})
	-- escapes: fumaça + faíscas
	local smoke, spark = {}, {}
	for _, sx in ipairs({-1, 1}) do
		P("Pipe", V3(1.6, 0.45, 0.45), CF(sx * 3.4, 4.6, 6.6) * VERT, SL, nil, {shape = CYL})
		local ex = P("Exhaust", V3(0.2, 0.2, 0.2), CF(sx * 3.4, 5.5, 6.6), BK, nil, {tr = 1})
		smoke[#smoke + 1] = new("ParticleEmitter", {Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(110, 110, 115), Color3.fromRGB(35, 35, 38)),
			Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.5)}), Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)}),
			Lifetime = NumberRange.new(1.2, 2.2), Speed = NumberRange.new(5, 9), SpreadAngle = Vector2.new(12, 12), Acceleration = V3(0, 3, 0), Rotation = NumberRange.new(0, 360), Rate = 0}, ex)
		spark[#spark + 1] = new("ParticleEmitter", {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 190, 60), Color3.fromRGB(255, 70, 20)),
			Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.05)}), Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)}),
			Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(14, 24), SpreadAngle = Vector2.new(35, 35), Acceleration = V3(0, -60, 0), LightEmission = 1, Rate = 0}, ex)
	end
	-- rodas + garras
	local wheels, claws = {}, {}
	for _, sx in ipairs({-1, 1}) do for _, sz in ipairs({-1, 1}) do
		local base = CF(sx * 5, -0.2, sz * 6.2)
		local t, w = P("Tire", V3(1.6, 4, 4), base, Color3.fromRGB(20, 20, 22), M.Slate, {shape = CYL})
		P("Hub", V3(1.7, 2.2, 2.2), CF(), SL, nil, {to = t, shape = CYL}) P("Cap", V3(1.75, 1, 1), CF(), AM, nil, {to = t, shape = CYL})
		P("Spoke", V3(1.78, 0.3, 2.2), CF(), BK, nil, {to = t}) P("Spoke", V3(1.78, 2.2, 0.3), CF(), BK, nil, {to = t})
		P("Fender", V3(2.2, 0.3, 5.4), CF(sx * 5, 2.05, sz * 6.2), ST)
		wheels[#wheels + 1] = {w, base, sz == -1}
		local r = CF(sx * 3.6, -0.4, sz * 2.8)
		local sp, sw = P("Claw", V3(0.5, 3, 0.5), r, AM)
		P("Foot", V3(1.8, 0.25, 1.8), CF(0, -1.5, 0), SL, nil, {to = sp})
		claws[#claws + 1] = {sw, r, CF(sx * 3.6, -3.2, sz * 2.8)}
	end end
	local att = new("Attachment", {}, core)
	local ao = new("AlignOrientation", {Mode = Enum.OrientationAlignmentMode.OneAttachment, Attachment0 = att, RigidityEnabled = false, MaxTorque = 1e8, MaxAngularVelocity = math.huge, Responsiveness = 40}, core)
	return {model = model, core = core, seat = seat, ao = ao, heads = heads, cabin = cabin, leds = leds, ls = {}, beacon = beacon, smoke = smoke, spark = spark, wheels = wheels, claws = claws, aw = aw, abase = abase}
end

-- AÇÕES
local function setLights(on)
	S.lights = on
	for _, h in ipairs(tiv.heads) do
		h[2].Enabled = on h[1].Material = on and M.Neon or M.SmoothPlastic
		h[1].Color = on and Color3.fromRGB(255, 244, 214) or Color3.fromRGB(120, 120, 110)
	end
	tiv.cabin.Enabled = on
end
local function setAnchor(on)
	S.anch = on
	if on then S.speed = 0 S.ext = V3() tiv.core.AssemblyLinearVelocity = V3() tiv.core.AssemblyAngularVelocity = V3() end
	tiv.core.Anchored = on
	for _, c in ipairs(tiv.claws) do TS:Create(c[1], TweenInfo.new(0.55, Enum.EasingStyle.Quad), {C0 = on and c[3] or c[2]}):Play() end
end
local function restoreAll()
	for p, cf in pairs(G) do
		pcall(function() p.Anchored = true p.AssemblyLinearVelocity = V3() p.AssemblyAngularVelocity = V3() p.CFrame = cf end)
		G[p] = nil
	end
	S.gc = 0
end
local function seatPlayer()
	local ch = plr.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if not (h and r and tiv) or h.Health <= 0 or tiv.seat.Occupant == h then return end
	local seat = tiv.seat
	r.AssemblyLinearVelocity = V3()
	r.CFrame = seat.CFrame * CF(0, 1.4, 0)
	task.wait(0.15)
	if seat.Occupant == h then return end
	pcall(function() seat:Sit(h) end)
	h.Sit = true
	task.wait(0.25)
	if seat.Occupant ~= h and not seat:FindFirstChild("SeatWeld") then
		local w = Instance.new("Weld")
		w.Name = "SeatWeld"
		w.Part0, w.Part1 = seat, r
		w.C0 = CF(0, seat.Size.Y / 2 + h.HipHeight + r.Size.Y / 2, 0)
		w.Parent = seat
		h.Sit = true
		local c
		c = h:GetPropertyChangedSignal("Jump"):Connect(function()
			if h.Jump then pcall(w.Destroy, w) h.Sit = false c:Disconnect() end
		end)
	end
end

-- SAIR DO TIV: solta o assento, remove a solda e joga o jogador ao lado
local function isSeated()
	local h = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if not (h and tiv) then return false end
	return tiv.seat.Occupant == h or tiv.seat:FindFirstChild("SeatWeld") ~= nil
end
local function leaveTIV()
	local ch = plr.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if not (h and r and tiv) or not isSeated() then return end
	local seat = tiv.seat
	local w = seat:FindFirstChild("SeatWeld")
	if w then w:Destroy() end
	h.Sit = false
	pcall(function() h.Jump = true end)
	r.AssemblyLinearVelocity = V3()
	r.CFrame = seat.CFrame * CF(-4.5, 1.5, 0)
end

-- CHUVA + RAIOS
local function buildRain()
	rainP = new("Part", {Name = "TIV_Rain", Size = V3(90, 1, 90), Transparency = 1, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false}, WS)
	rainP:SetAttribute(TAG, true)
	rainE = new("ParticleEmitter", {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(170, 190, 220)),
		Size = NumberSequence.new(0.25), Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.8)}),
		Lifetime = NumberRange.new(1.1, 1.4), Speed = NumberRange.new(70, 90), Acceleration = V3(0, -40, 0), Rate = 0, LightEmission = 0.2}, rainP)
	SKY.rsnd = new("Sound", {Name = "TIV_RainSnd", SoundId = "rbxassetid://1516791621", Looped = true, Volume = 0}, WS)
	SKY.rsnd:SetAttribute(TAG, true)
	SKY.rsnd:Play()
	pcall(function() rainE.EmissionDirection = Enum.NormalId.Bottom end)
	pcall(function() rainE.Orientation = Enum.ParticleOrientation.VelocityParallel end)
end
local function setRain(on)
	S.rain = on S.lt = 2
	if rainE then rainE.Rate = on and 450 or 0 end
end
local function flash(k)
	LT.Brightness = baseB + 3 * (k or 1)
	TS:Create(LT, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Brightness = baseB}):Play()
	task.delay(0.18, safe(function()
		if S.rain then
			LT.Brightness = baseB + 2.5
			TS:Create(LT, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Brightness = baseB}):Play()
		end
	end))
end

-- CÂMERA DE TEMPESTADE (treme + FOV) e chuva seguindo a câmera
local function camStep()
	local cam = WS.CurrentCamera
	if not cam then return end
	local k = 0
	if S.cam and tor then
		local I = S.tr / 60
		local d = tor.pos - cam.CFrame.Position
		d = V3(d.X, 0, d.Z).Magnitude
		k = math.clamp(1 - d / (130 + 80 * I), 0, 1)
	end
	if S.fly then k = math.max(k, 0.6) end
	S.k += (k - S.k) * 0.1
	if S.k > 0.01 then
		if not S.ft then S.ft = true S.fov = cam.FieldOfView end
		cam.FieldOfView = S.fov + 22 * S.k
		local t = os.clock()
		cam.CFrame = cam.CFrame * CFrame.Angles(math.noise(t * 25, 0.5) * 0.035 * S.k, math.noise(t * 25, 1.5) * 0.035 * S.k, math.noise(t * 20, 2.5) * 0.05 * S.k)
	elseif S.ft then
		S.ft = false cam.FieldOfView = S.fov
	end
	if rainP then rainP.CFrame = CF(cam.CFrame.Position + V3(0, 35, 0)) end
end

-- TORNADO
local SMK = "rbxasset://textures/particles/smoke_main.dds"
local function tparams()
	if tor then
		local I = S.tr / 60
		tor.dust.Rate = 80 * I tor.fun.Rate = 38 * I tor.fun2.Rate = 26 * I tor.cloud.Rate = 9 + 6 * I
		local fx = tor.fx
		fx.wall.Rate = 10 * I fx.anvE.Rate = 8 + 10 * I fx.ring.Rate = 50 * I fx.fogE.Rate = 6 * I fx.rcE.Rate = 160 * I
		for _, s in ipairs(fx.subs) do s.e.Rate = 25 * I end
	end
end
local function emitter(par, col, sz, tr, life, spd, extra)
	local e = new("ParticleEmitter", {Texture = SMK, Color = col, Size = sz, Transparency = tr, Lifetime = life, Speed = spd, Rate = 0}, par)
	for k, v in pairs(extra or {}) do pcall(function() e[k] = v end) end
	return e
end
local function spawnTornado()
	if tor or not tiv then return end
	local l = tiv.core.CFrame.LookVector l = V3(l.X, 0, l.Z).Unit
	local p = tiv.core.Position + l * 110
	local c = V3(p.X, groundY(p, tiv.core.Position.Y - 2.2), p.Z)
	local m = new("Model", {Name = TOR}) m:SetAttribute(TAG, true)
	local function anc(sz, pos) return new("Part", {Size = sz, Transparency = 1, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Position = pos}, m) end
	local core = anc(V3(1, 1, 1), c)
	m.PrimaryPart = core
	local rng, el, parts, cfs = Random.new(), {}, {}, {}
	local NS, NK = 170, 60
	for i = 1, NS + NK do
		local deb = i > NS
		local t, p2 = nil, Instance.new("Part")
		if deb then
			t = rng:NextNumber(0.02, 0.75)
			local s, k = rng:NextNumber(0.8, 2.8), rng:NextNumber()
			if k < 0.4 then
				p2.Size, p2.Material, p2.Color = V3(0.5, 0.4, s * 2.6), M.WoodPlanks, Color3.fromRGB(rng:NextInteger(95, 140), rng:NextInteger(65, 90), rng:NextInteger(35, 55))
			elseif k < 0.75 then
				local g = rng:NextNumber(55, 95)
				p2.Size, p2.Material, p2.Color = V3(s, s * 0.7, s), M.Slate, Color3.fromRGB(g, g * 0.92, g * 0.8)
			else
				local g = rng:NextNumber(150, 200)
				p2.Size, p2.Material, p2.Color = V3(s * 1.6, 0.12, s), M.Metal, Color3.fromRGB(g, g, g + 8)
			end
		else
			t = (i - 1 + rng:NextNumber()) / NS
			local col = Color3.fromRGB(165, 142, 112):Lerp(Color3.fromRGB(92, 96, 108), math.clamp(t * 1.15, 0, 1)):Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.12))
			p2.Size, p2.Color, p2.Material = V3(rng:NextNumber(3, 8) * (0.6 + t), rng:NextNumber(0.25, 0.7), rng:NextNumber(1.2, 3.2)), col, M.SmoothPlastic
			p2.Transparency = math.clamp(0.5 + rng:NextNumber(0, 0.32) + (t > 0.85 and (t - 0.85) * 1.2 or 0), 0, 1)
		end
		p2.Anchored, p2.CanCollide, p2.CanTouch, p2.CanQuery, p2.CastShadow = true, false, false, false, false
		p2.CFrame = CF(c) p2.Parent = m
		el[i] = {t = t, th = rng:NextNumber(0, 6.283), spd = deb and rng:NextNumber(1.1, 1.5) or rng:NextNumber(0.85, 1.2), lean = rng:NextNumber(-0.5, 0.5), rj = rng:NextNumber(-0.12, 0.12), deb = deb, tw = rng:NextNumber(1, 4)}
		parts[i], cfs[i] = p2, p2.CFrame
	end
	local TR = NumberSequence.new
	local KP = NumberSequenceKeypoint.new
	local dp = anc(V3(34, 1, 34), c + V3(0, 1, 0))
	local dust = emitter(dp, ColorSequence.new(Color3.fromRGB(118, 100, 78), Color3.fromRGB(90, 80, 66)), TR({KP(0, 8), KP(1, 30)}), TR({KP(0, 0.5), KP(1, 1)}),
		NumberRange.new(2.5, 4.5), NumberRange.new(16, 30), {SpreadAngle = Vector2.new(70, 70), Acceleration = V3(0, 12, 0), Shape = Enum.ParticleEmitterShape.Cylinder, RotSpeed = NumberRange.new(-60, 60), Rotation = NumberRange.new(0, 360)})
	local fp = anc(V3(50, TH, 50), c + V3(0, TH / 2, 0))
	local fun = emitter(fp, ColorSequence.new(Color3.fromRGB(120, 112, 100), Color3.fromRGB(88, 90, 98)), TR({KP(0, 10), KP(1, 28)}), TR({KP(0, 0.65), KP(1, 1)}),
		NumberRange.new(3, 5), NumberRange.new(2, 6), {Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, RotSpeed = NumberRange.new(-30, 30), Rotation = NumberRange.new(0, 360)})
	local fun2 = emitter(fp, ColorSequence.new(Color3.fromRGB(55, 55, 62)), TR({KP(0, 6), KP(1, 16)}), TR({KP(0, 0.6), KP(1, 1)}),
		NumberRange.new(3, 5), NumberRange.new(1, 3), {Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, RotSpeed = NumberRange.new(-80, 80), Rotation = NumberRange.new(0, 360)})
	local cp = anc(V3(70, 4, 70), c + V3(0, TH, 0))
	local cloud = emitter(cp, ColorSequence.new(Color3.fromRGB(48, 50, 58), Color3.fromRGB(80, 82, 92)), TR({KP(0, 50), KP(1, 120)}), TR({KP(0, 0.55), KP(1, 1)}),
		NumberRange.new(6, 9), NumberRange.new(4, 10), {Shape = Enum.ParticleEmitterShape.Disc, RotSpeed = NumberRange.new(-10, 10), Rotation = NumberRange.new(0, 360), SpreadAngle = Vector2.new(90, 90)})
	-- funil de condensação: vapor translúcido, fino no chão e largo no topo
	local funnel = {}
	for i = 1, 6 do
		local f = anc(V3(TH / 6, 2, 2), c)
		f.Shape = Enum.PartType.Cylinder
		f.Transparency = 0.82 f.Color = Color3.fromRGB(215, 218, 225) f.Material = M.SmoothPlastic
		funnel[i] = f
	end
	-- nuvem de parede (wall cloud) na base da nuvem de tempestade
	local wc = anc(V3(1, 1, 1), c + V3(0, TH * 0.75, 0))
	local wall = emitter(wc, ColorSequence.new(Color3.fromRGB(42, 44, 50), Color3.fromRGB(24, 25, 30)), TR({KP(0, 14), KP(1, 30)}), TR({KP(0, 0.4), KP(1, 1)}),
		NumberRange.new(4, 6), NumberRange.new(0.5, 2), {Shape = Enum.ParticleEmitterShape.Disc, RotSpeed = NumberRange.new(-120, 120), Rotation = NumberRange.new(0, 360), SpreadAngle = Vector2.new(90, 90)})
	-- bigorna: topo da nuvem se espalhando
	local anv = anc(V3(1, 1, 1), c + V3(0, TH + 6, 0))
	local anvE = emitter(anv, ColorSequence.new(Color3.fromRGB(55, 57, 66), Color3.fromRGB(30, 31, 38)), TR({KP(0, 40), KP(1, 110)}), TR({KP(0, 0.5), KP(1, 1)}),
		NumberRange.new(6, 9), NumberRange.new(8, 14), {Shape = Enum.ParticleEmitterShape.Disc, SpreadAngle = Vector2.new(90, 90), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-5, 5)})
	-- anel de poeira escura e densa na base
	local ring = emitter(dp, ColorSequence.new(Color3.fromRGB(96, 84, 68), Color3.fromRGB(70, 62, 52)), TR({KP(0, 12), KP(1, 40)}), TR({KP(0, 0.35), KP(1, 1)}),
		NumberRange.new(3, 5), NumberRange.new(24, 40), {SpreadAngle = Vector2.new(80, 80), Acceleration = V3(0, 6, 0), Shape = Enum.ParticleEmitterShape.Cylinder, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40)})
	-- sub-vórtices girando dentro do principal
	local subs = {}
	for i = 1, 2 do
		local sp = anc(V3(1, 1, 1), c)
		local se = emitter(sp, ColorSequence.new(Color3.fromRGB(128, 120, 108), Color3.fromRGB(72, 74, 82)), TR({KP(0, 8), KP(1, 18)}), TR({KP(0, 0.5), KP(1, 1)}),
			NumberRange.new(2, 3.5), NumberRange.new(2, 6), {Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60)})
		subs[i] = {p = sp, e = se, ph = i * 2.6}
	end
	-- névoa baixa envolvendo a base
	local fog = anc(V3(170, 1, 170), c + V3(0, 3, 0))
	local fogE = emitter(fog, ColorSequence.new(Color3.fromRGB(190, 195, 200)), TR({KP(0, 40), KP(1, 70)}), TR({KP(0, 0.85), KP(1, 1)}),
		NumberRange.new(5, 8), NumberRange.new(1, 3), {Shape = Enum.ParticleEmitterShape.Box, SpreadAngle = Vector2.new(0, 0)})
	-- cortina de chuva na frente da tempestade
	local rc = anc(V3(50, TH, 2), c)
	local rcE = emitter(rc, ColorSequence.new(Color3.fromRGB(170, 190, 220)), TR({KP(0, 0.3), KP(1, 0.3)}), TR({KP(0, 0.5), KP(1, 0.8)}),
		NumberRange.new(0.8, 1.1), NumberRange.new(20, 30), {Shape = Enum.ParticleEmitterShape.Box, EmissionDirection = Enum.NormalId.Bottom, Acceleration = V3(0, -40, 0), LightEmission = 0.2, Orientation = Enum.ParticleOrientation.VelocityParallel})
	local fx = {funnel = funnel, wc = wc, wall = wall, anv = anv, anvE = anvE, ring = ring, subs = subs, fog = fog, fogE = fogE, rc = rc, rcE = rcE}
	m.Parent = WS
	tor = {model = m, core = core, el = el, parts = parts, cfs = cfs, dust = dust, fun = fun, fun2 = fun2, cloud = cloud, dp = dp, fp = fp, cp = cp, ph = 0, t = 0, pos = c, ty = c.Y, seed = rng:NextNumber(0, 100), scan = 0, gt = 0, acc = 0, cache = {}, hums = {}, bt = rng:NextNumber(2, 5), fx = fx}
	tparams()
end
local function killTornado()
	if tor then
		for hm in pairs(tor.hums) do pcall(function() hm.PlatformStand = false end) end
		pcall(tor.model.Destroy, tor.model) tor = nil
	end
end

-- raios: nuvem-nuvem (horizontal) e nuvem-chão, com brilho e duração variados
local function bolt(T)
	local rng = Random.new()
	local cloud = rng:NextNumber() < 0.45
	local a = T.pos + V3(rng:NextNumber(-25, 25), TH, rng:NextNumber(-25, 25))
	local b
	if cloud then
		b = a + V3(rng:NextNumber(-130, 130), rng:NextNumber(-8, 8), rng:NextNumber(-130, 130))
	else
		b = T.pos + V3(rng:NextNumber(-90, 90), 0, rng:NextNumber(-90, 90))
		b = V3(b.X, groundY(b, T.pos.Y), b.Z)
	end
	local col = cloud and Color3.fromRGB(190, 200, 255) or Color3.fromRGB(230, 236, 255)
	local thick = cloud and 0.4 or 0.7
	local dur = rng:NextNumber(0.08, 0.3)
	local bright = cloud and rng:NextNumber(0.6, 1.0) or rng:NextNumber(1.0, 1.6)
	local steps = cloud and 14 or 9
	local prev, list = a, {}
	for i = 1, steps do
		local pt = a:Lerp(b, i / steps)
		if i < steps then pt += V3(rng:NextNumber(-9, 9), rng:NextNumber(-3, 3), rng:NextNumber(-9, 9)) end
		local len = (pt - prev).Magnitude
		if len > 0.1 then
			list[#list + 1] = new("Part", {Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Material = M.Neon,
				Color = col, Size = V3(thick, thick, len), CFrame = CFrame.lookAt(prev:Lerp(pt, 0.5), pt)}, T.model)
		end
		prev = pt
	end
	task.delay(dur, safe(function() for _, p in ipairs(list) do p:Destroy() end end))
	pcall(flash, bright)
end

local function stepTornado(dt)
	local T = tor if not T then return end
	-- ciclo de vida: a intensidade oscila (fortalece/enfraquece) como num tornado real
	local I = S.tr / 60 * (0.9 + 0.1 * math.sin(T.t * 0.23) + 0.05 * math.sin(T.t * 0.71))
	T.ph += S.tr * 6.283 / 60 * dt T.t += dt
	local hd = math.noise(T.t * 0.06, T.seed) * 12.566 + math.noise(T.t * 0.3, T.seed + 9) * 1.2
	local pause = math.noise(T.t * 0.12, T.seed + 4)
	local mv = (3 + 3 * I) * math.clamp(pause * 2.2, 0, 1)
	if S.hunt then
		local tp = tiv.core.Position
		hd = math.atan2(tp.Z - T.pos.Z, tp.X - T.pos.X)
		mv = mv * 2.5
	end
	T.pos += V3(math.cos(hd), 0, math.sin(hd)) * mv * dt
	T.gt -= dt if T.gt <= 0 then T.gt = 0.35 T.ty = groundY(T.pos, T.pos.Y) end
	T.pos = V3(T.pos.X, T.pos.Y + (T.ty - T.pos.Y) * math.min(1, dt * 3), T.pos.Z)
	T.acc += dt
	if T.acc >= 1 / 30 then
		T.acc = 0 local c, tm = T.pos, T.t
		local sw = 0.75 + 0.5 * I
		for i, e in ipairs(T.el) do
			local t = e.t
			local r = (3.5 + 29 * t ^ 1.6) * (1 + e.rj) * (e.deb and 1.15 or 1) * sw + (e.deb and math.sin(tm * 3 + e.th * 5) * 4 * t or 0)
			local th = e.th + T.ph * e.spd * (1.3 - 0.55 * t) + t * 2.2
			local cf = CF(c.X + math.cos(th) * r + math.sin(tm * 0.7 + t * 3) * 7 * t, c.Y + t * TH + (e.deb and math.sin(tm * 2 + e.th) * 2 or 0), c.Z + math.sin(th) * r + math.cos(tm * 0.5 + t * 2.4) * 7 * t)
				* CFrame.Angles(0, 1.5708 - th, 0) * CFrame.Angles(0, 0, e.lean + t * 0.5)
			if e.deb then cf = cf * CFrame.Angles(tm * e.tw, tm * e.tw * 0.7, 0) end
			T.cfs[i] = cf
		end
		WS:BulkMoveTo(T.parts, T.cfs, Enum.BulkMoveMode.FireCFrameChanged)
		T.core.CFrame = CF(c) T.dp.CFrame = CF(c + V3(0, 1, 0)) T.fp.CFrame = CF(c + V3(0, TH / 2, 0)) T.cp.CFrame = CF(c + V3(0, TH, 0))
	end
	-- funil, nuvem de parede, bigorna, névoa, sub-vórtices e cortina de chuva acompanham o tornado
	local fx, c0 = T.fx, T.pos
	local dxh, dzh = math.cos(hd), math.sin(hd)
	local nf = #fx.funnel
	for i, f in ipairs(fx.funnel) do
		local h = (i - 0.5) / nf * TH
		local r = (2.5 + 16 * (h / TH) ^ 1.3) * (0.75 + 0.5 * I)
		local wob = 2 * (h / TH)
		f.Size = V3(TH / nf, r * 2, r * 2)
		f.CFrame = CF(c0.X + math.sin(T.t * 0.9 + h * 0.05) * wob, c0.Y + h, c0.Z + math.cos(T.t * 0.7 + h * 0.05) * wob) * CFrame.Angles(0, 0, math.rad(90))
	end
	fx.wc.Position = c0 + V3(0, TH * 0.75, 0)
	fx.anv.Position = c0 + V3(0, TH + 6, 0)
	fx.fog.Position = c0 + V3(0, 3, 0)
	fx.rc.CFrame = CFrame.lookAt(c0 + V3(dxh * 45, TH / 2, dzh * 45), c0 + V3(dxh * 46, TH / 2, dzh * 46))
	for _, s in ipairs(fx.subs) do
		local a = T.ph * 1.4 + s.ph
		local rr = (9 + 7 * I) * (1 + 0.3 * math.sin(T.t * 0.4 + s.ph))
		s.p.Position = c0 + V3(math.cos(a) * rr, 4 + s.ph * 3, math.sin(a) * rr)
	end
	T.bt -= dt
	if T.bt <= 0 then T.bt = math.random(25, 80) / 10 bolt(T) end
	-- sucção física + arrancar objetos ancorados
	local range, c = 70 + 60 * I, T.pos
	T.scan -= dt
	if T.scan <= 0 then
		T.scan = 0.3
		local op = OverlapParams.new() op.FilterType = Enum.RaycastFilterType.Exclude op.FilterDescendantsInstances = {T.model, tiv.model} op.MaxParts = 1500
		local seen, list, ng, hums = {}, {}, 0, {}
		for _, p in ipairs(WS:GetPartBoundsInBox(CF(c + V3(0, TH / 2, 0)), V3(range * 2, TH, range * 2), op)) do
			if p.Anchored and S.grab and ng < 80 and S.gc < S.gmax and not G[p] then
				local s = p.Size
				local dx, dz = p.Position.X - c.X, p.Position.Z - c.Z
				if s.X * s.Y * s.Z < 6000000 and math.max(s.X, s.Y, s.Z) < 600 and dx * dx + dz * dz < range * range and p.Position.Y < c.Y + TH then
					local mdl = p:FindFirstAncestorOfClass("Model")
					if not (mdl and mdl:FindFirstChildOfClass("Humanoid")) then
						G[p] = p.CFrame ng += 1 S.gc += 1
						local okj, js = pcall(p.GetJoints, p)
						if okj then for _, j in ipairs(js) do pcall(j.Destroy, j) end end
						pcall(p.BreakJoints, p)
						p.Anchored = false
						p.AssemblyLinearVelocity = V3(0, 25, 0)
					end
				end
			end
			local r = not p.Anchored and p.AssemblyRootPart
			if r and r ~= tiv.core and not r.Anchored and not seen[r] and r.AssemblyMass < 60000 then
				seen[r] = true list[#list + 1] = r
				local mdl = r:FindFirstAncestorOfClass("Model")
				local hm = mdl and mdl:FindFirstChildOfClass("Humanoid")
				if hm and not hm.SeatPart then hums[hm] = true end
				if #list >= 400 then break end
			end
		end
		for hm in pairs(T.hums) do if not hums[hm] then pcall(function() hm.PlatformStand = false end) end end
		for hm in pairs(hums) do pcall(function() hm.PlatformStand = true end) end
		T.hums = hums
		T.cache = list
	end
	for i = #T.cache, 1, -1 do
		local r = T.cache[i]
		if not r.Parent or r.Anchored then table.remove(T.cache, i) else
			local d = V3(c.X - r.Position.X, 0, c.Z - r.Position.Z) local dist = d.Magnitude
			if dist < range then
				local f = 1 - dist / range local din = dist > 0.1 and d / dist or V3()
				local lift = r.Position.Y < c.Y + TH and 600 * I * f ^ 0.9 or 0
				local a = (din * (40 * I * f) + V3(-din.Z, 0, din.X) * (70 * I * f)) * math.clamp(60 / (60 + r.AssemblyMass * 0.02), 0.25, 1) + V3(0, lift, 0)
				local v = r.AssemblyLinearVelocity + a * dt
				r.AssemblyLinearVelocity = v.Magnitude > 170 and v.Unit * 170 or v
			end
		end
	end
	-- TIV: sem ancoragem o tornado levanta e gira o carro
	local core = tiv.core
	S.lf = 0
	if not core.Anchored then
		local d = V3(c.X - core.Position.X, 0, c.Z - core.Position.Z) local dist = d.Magnitude
		if dist < range then
			local f = 1 - dist / range local din = dist > 0.1 and d / dist or V3()
			local tang = V3(-din.Z, 0, din.X)
			local lift = dist < range * 0.85 and 420 * I * f ^ 0.8 or 0
			S.lf = lift
			if lift > 150 and not S.fly then S.fly = true tiv.ao.Enabled = false end
			if S.fly then
				local v = core.AssemblyLinearVelocity + (din * (30 * I * f) + tang * (60 * I * f) + V3(0, lift, 0)) * dt
				local hv = V3(v.X, 0, v.Z)
				if hv.Magnitude > 90 then hv = hv.Unit * 90 end
				core.AssemblyLinearVelocity = V3(hv.X, math.min(v.Y, 70), hv.Z)
				core.AssemblyAngularVelocity = V3(0.6, 2.2, 0.9) * (I * f)
			else
				local e = S.ext + (din * (40 * I * f) + tang * (70 * I * f)) * 0.25 * dt
				S.ext = e.Magnitude > 35 and e.Unit * 35 or e
			end
		end
	end
end

-- CONDUÇÃO + MOTOR + NITRO
local function appr(c, t, d) return c < t and math.min(c + d, t) or math.max(c - d, t) end
local function stepTIV(dt)
	local core = tiv.core
	local h = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	local th, st = 0, 0
	if h and tiv.seat.Occupant == h then
		th, st = tiv.seat.ThrottleFloat, tiv.seat.SteerFloat
		if th == 0 and st == 0 and h.MoveDirection.Magnitude > 0.1 then
			th = math.clamp(h.MoveDirection:Dot(core.CFrame.LookVector), -1, 1) st = math.clamp(h.MoveDirection:Dot(core.CFrame.RightVector), -1, 1)
		end
	end
	-- nitro (Shift ou botão)
	local nit = not core.Anchored and th > 0 and S.fuel > 0.02 and (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or S.nb)
	S.fuel = math.clamp(S.fuel + (nit and -0.3 or 0.1) * dt, 0, 1)
	S.nit = nit
	if not tor then S.lf = 0 end
	S.gt -= dt
	if S.gt <= 0 then S.gt = 0.15 S.gh = core.Position.Y - groundY(core.Position, core.Position.Y - 3) end
	if S.fly and (core.Anchored or (S.gh < 3 and S.lf < 150)) then
		S.fly = false tiv.ao.Enabled = true
		local _, y = core.CFrame:ToOrientation() S.yaw = y tiv.ao.CFrame = CFrame.Angles(0, y, 0)
		core.AssemblyAngularVelocity = V3() S.speed = 0
	end
	if core.Anchored then S.speed = 0 S.ext = V3() elseif S.fly then S.speed = appr(S.speed, 0, 60 * dt) S.ext = V3() else
		local tg = th > 0 and th * (nit and 125 or 80) or th < 0 and th * 26 or 0
		local ac = (S.speed ~= 0 and math.sign(th) ~= math.sign(S.speed)) and 70 or (nit and 60 or 36)
		if th ~= 0 then S.speed = appr(S.speed, tg, ac * dt) else S.speed = appr(S.speed, 0, 14 * dt) end
		S.yaw -= st * 1.15 * dt * math.clamp(S.speed / 18, -1, 1)
		tiv.ao.CFrame = CFrame.Angles(0, S.yaw, 0)
		local v = core.AssemblyLinearVelocity
		core.AssemblyLinearVelocity = V3(-math.sin(S.yaw) * S.speed + S.ext.X, v.Y, -math.cos(S.yaw) * S.speed + S.ext.Z)
		S.ext *= math.max(0, 1 - dt * 1.5)
	end
	-- RPM
	local sn, load = math.clamp(math.abs(S.speed) / 80, 0, 1), math.abs(th)
	local w = sn >= 0.98 and 1 or (sn * 5) % 1
	local span, tg = MAXR - IDLE, nil
	if core.Anchored then tg = IDLE + load * 0.95 * span elseif load > 0 then tg = IDLE + load * span * (0.3 + 0.7 * w) else tg = IDLE + sn * 0.18 * span end
	S.rpm += (tg - S.rpm) * math.min(1, dt * (tg > S.rpm and 4.5 or 2.2))
	S.shown = S.rpm + math.sin(os.clock() * 37) * 18 + (S.rpm > 6500 and math.random() * 90 or 0)
	local sr, pr = math.clamp((S.rpm - 4200) / 3800, 0, 1) * 55 + 2, math.clamp((S.rpm - 6400) / 1700, 0, 1) * 40
	if nit then sr, pr = math.max(sr, 70), math.max(pr, 90) end
	for _, e in ipairs(tiv.smoke) do e.Rate = sr end
	for _, e in ipairs(tiv.spark) do e.Rate = pr end
	-- rodas / mastro / LEDs
	S.spin -= S.speed / 2 * dt S.steer += (-st * 0.45 - S.steer) * math.min(1, dt * 8)
	for _, wl in ipairs(tiv.wheels) do wl[1].C0 = wl[2] * (wl[3] and CFrame.Angles(0, S.steer, 0) or CF()) * CFrame.Angles(S.spin, 0, 0) end
	S.an += dt * (2 + (tor and S.tr / 6 or 0)) tiv.aw.C0 = tiv.abase * CFrame.Angles(0, S.an, 0)
	local ph = math.floor(os.clock() * 7) % 2
	for i, l in ipairs(tiv.leds) do
		local on = S.lights and (i + ph) % 2 == 0
		local k = on and (i % 2 == 0 and 1 or 2) or 0
		if tiv.ls[i] ~= k then
			tiv.ls[i] = k l.Material = on and M.Neon or M.SmoothPlastic
			l.Color = k == 1 and Color3.fromRGB(255, 40, 40) or k == 2 and Color3.fromRGB(40, 110, 255) or Color3.fromRGB(40, 40, 46)
		end
	end
	if tiv.eng then
		tiv.eng.PlaybackSpeed = 0.6 + 0.9 * math.clamp((S.rpm - IDLE) / (MAXR - IDLE), 0, 1)
		tiv.eng.Volume = 0.2 + 0.4 * math.max(load, sn)
	end
	tiv.beacon.Color = math.floor(os.clock() * 1.5) % 2 == 0 and Color3.fromRGB(255, 30, 30) or Color3.fromRGB(60, 10, 10)
end

-- CLIMA: iluminação, nuvens volumétricas (Terrain.Clouds), atmosfera, vento global e céu de supercélula
local function initSky()
	local a = LT:FindFirstChildOfClass("Atmosphere")
	if not a then a = new("Atmosphere", {}, LT) SKY.created = true end
	SKY.atm = a
	SKY.d0, SKY.h0, SKY.c0, SKY.g0 = a.Density, a.Haze, a.Color, a.Glare
	SKY.amb, SKY.oamb, SKY.wind = LT.Ambient, LT.OutdoorAmbient, WS.GlobalWind
	local terr = WS.Terrain
	local cl = terr:FindFirstChildOfClass("Clouds")
	if not cl then cl = new("Clouds", {}, terr) SKY.cloudsCreated = true end
	SKY.cl_obj = cl
	SKY.cov0, SKY.den0, SKY.ccol0, SKY.cen0 = cl.Cover, cl.Density, cl.Color, cl.Enabled
	cl.Enabled = true
	SKY.lvl = 0
	cloudP = new("Part", {Name = "TIV_Clouds", Size = V3(700, 1, 700), Transparency = 1, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false}, WS)
	cloudP:SetAttribute(TAG, true)
	cloudE = new("ParticleEmitter", {Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(78, 82, 92), Color3.fromRGB(40, 42, 50)),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 90), NumberSequenceKeypoint.new(1, 150)}),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.8, 0.4), NumberSequenceKeypoint.new(1, 1)}),
		Lifetime = NumberRange.new(40, 55), Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-2, 2), Rate = 0}, cloudP)
	pcall(function() cloudE.Shape = Enum.ParticleEmitterShape.Box end)
	SKY.wsnd = new("Sound", {Name = "TIV_Wind", SoundId = "rbxassetid://107444799838011", Looped = true, Volume = 0, RollOffMaxDistance = 400}, WS)
	SKY.wsnd:SetAttribute(TAG, true)
	SKY.wsnd:Play()
end
local function skyStep(dt)
	local a = SKY.atm
	if not a or not a.Parent then return end
	local target = tor and math.clamp(S.tr / 60, 0.4, 1) or (S.rain and 0.35 or 0)
	SKY.lvl = (SKY.lvl or 0) + (target - (SKY.lvl or 0)) * math.min(1, dt * 0.6)
	local c = SKY.lvl
	-- atmosfera e iluminação: céu sombrio e esverdeado conforme a tempestade cresce
	a.Density = SKY.d0 + 0.35 * c
	a.Haze = SKY.h0 + 1.5 * c
	a.Color = SKY.c0:Lerp(Color3.fromRGB(120, 118, 105), c * 0.7)
	a.Glare = SKY.g0 * (1 - c)
	LT.OutdoorAmbient = SKY.oamb:Lerp(Color3.fromRGB(70, 72, 78), c)
	LT.Ambient = SKY.amb:Lerp(Color3.fromRGB(40, 40, 46), c * 0.6)
	-- nuvens volumétricas
	local cl = SKY.cl_obj
	if cl and cl.Parent then
		cl.Cover = SKY.cov0 + (0.95 - SKY.cov0) * c
		cl.Density = SKY.den0 + (0.5 - SKY.den0) * c
		cl.Color = SKY.ccol0:Lerp(Color3.fromRGB(70, 72, 80), c)
	end
	-- vento global: rajadas irregulares que aumentam com a tempestade
	local t, gs = os.clock(), 4 + 22 * c
	WS.GlobalWind = V3(math.noise(t * 0.2, 1) * gs, 0, math.noise(t * 0.2, 7) * gs)
	if cloudE then cloudE.Rate = 2.5 * c end
	if cloudP and tiv then cloudP.CFrame = CF(tiv.core.Position.X, 190, tiv.core.Position.Z) end
	if SKY.wsnd then SKY.wsnd.Volume = 0.6 * c end
	if SKY.rsnd then SKY.rsnd.Volume = S.rain and 0.5 or 0 end
end

-- MAPA METEOROLÓGICO (norte para cima; ponto = tornado, rastro = trajetória, seta = direção)
local function updateMap()
	local mg = ui.mg
	if not mg then return end
	local cover = tor and 95 or (S.rain and 70 or 15)
	local function px(x, z) return math.clamp(0.5 + x / 900, 0.04, 0.96), math.clamp(0.5 + z / 900, 0.04, 0.96) end
	if tor and tiv then
		local cp, tp = tiv.core.Position, tor.pos
		local now = os.clock()
		if now - mapLast > 0.5 then
			mapLast = now
			table.insert(mapHist, 1, tp)
			if #mapHist > #ui.mtrail then table.remove(mapHist) end
		end
		for i, f in ipairs(ui.mtrail) do
			local h = mapHist[i]
			f.Visible = h ~= nil
			if h then
				local x, z = px(h.X - cp.X, h.Z - cp.Z)
				f.Position = UDim2.new(x, 0, z, 0)
				f.BackgroundTransparency = 0.1 + 0.85 * (i / #ui.mtrail)
			end
		end
		local x, z = px(tp.X - cp.X, tp.Z - cp.Z)
		ui.mdot.Position = UDim2.new(x, 0, z, 0) ui.mdot.Visible = true
		ui.mwind.Position = UDim2.new(x, 0, z, 0) ui.mwind.Visible = true
		local prev = mapHist[2] or tp
		local mx, mz = tp.X - prev.X, tp.Z - prev.Z
		if mx * mx + mz * mz > 0.01 then ui.mwind.Rotation = math.deg(math.atan2(mx, -mz)) end
		ui.mstat.Text = string.format("P %d hPa  NUV %d%%", 1013 - math.floor(S.tr * 0.9), cover)
	else
		table.clear(mapHist)
		for _, f in ipairs(ui.mtrail) do f.Visible = false end
		ui.mdot.Visible = false ui.mwind.Visible = false
		ui.mstat.Text = string.format("P 1013 hPa  NUV %d%%", cover)
	end
end

-- HUD COMPACTO
local BG, CARD, OFF = Color3.fromRGB(14, 16, 20), Color3.fromRGB(24, 27, 33), Color3.fromRGB(38, 42, 50)
local AMB, CYA, GRN, RED, TXT = Color3.fromRGB(255, 176, 0), Color3.fromRGB(0, 200, 255), Color3.fromRGB(60, 220, 120), Color3.fromRGB(255, 70, 60), Color3.fromRGB(235, 238, 242)
local GRY, EDGE = Color3.fromRGB(140, 148, 160), Color3.fromRGB(70, 76, 88)
local function rc(p) return p < 0.6 and GRN:Lerp(AMB, p / 0.6) or AMB:Lerp(RED, math.clamp((p - 0.6) / 0.4, 0, 1)) end
local function round(o, r) new("UICorner", {CornerRadius = UDim.new(0, r or 5)}, o) end
local function label(par, txt, pos, size, col, font, ts, al, anc)
	return new("TextLabel", {BackgroundTransparency = 1, Text = txt, Position = pos, Size = size, TextColor3 = col, Font = font, TextSize = ts, TextXAlignment = al or Enum.TextXAlignment.Left, AnchorPoint = anc or Vector2.new()}, par)
end
local function bar(par, y) local b = new("Frame", {Position = UDim2.new(0, 6, 0, y), Size = UDim2.new(1, -12, 0, 6), BackgroundColor3 = Color3.fromRGB(10, 11, 14), BorderSizePixel = 0}, par) round(b, 3)
	local f = new("Frame", {Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0}, b) round(f, 3) return f end
local function btn(par, txt, order)
	local b = new("TextButton", {BackgroundColor3 = OFF, Text = "", AutoButtonColor = false, LayoutOrder = order}, par) round(b)
	local s = new("UIStroke", {Color = EDGE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, b)
	local l = label(b, txt, UDim2.new(0, 3, 0, 0), UDim2.new(1, -6, 1, 0), TXT, Enum.Font.GothamBold, 11, Enum.TextXAlignment.Center)
	l.TextScaled = true
	new("UITextSizeConstraint", {MaxTextSize = 11, MinTextSize = 6}, l)
	return {b = b, s = s, l = l}
end
local function paint(b, on, col)
	b.b.BackgroundColor3 = on and col:Lerp(Color3.new(), 0.6) or OFF
	b.s.Color = on and col or EDGE
end

local function buildHUD()
	local g = new("ScreenGui", {Name = GUI, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50}) g:SetAttribute(TAG, true)
	local ok = pcall(function() g.Parent = (gethui and gethui()) or CG end)
	if not ok or not g.Parent then g.Parent = plr:WaitForChild("PlayerGui") end
	local pn = new("Frame", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.new(0, 160, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = BG, BackgroundTransparency = 0.1, BorderSizePixel = 0}, g)
	round(pn, 7) new("UIStroke", {Color = AMB, Thickness = 1, Transparency = 0.3}, pn)
	new("UIPadding", {PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5)}, pn)
	new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, pn)
	local sc = new("UIScale", {}, pn)
	local cam = WS.CurrentCamera
	local function rs() if cam then sc.Scale = math.clamp(cam.ViewportSize.Y / 560, 0.62, 1.1) end end
	rs() if cam then track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(safe(rs))) end

	local hd = new("Frame", {Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1}, pn)
	label(hd, "◢ TIV-3 v5", UDim2.new(), UDim2.new(1, -46, 1, 0), AMB, Enum.Font.GothamBlack, 11)
	local function mini(t, x) local b = new("TextButton", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.new(0, 20, 0, 18), BackgroundColor3 = OFF, Text = t, TextSize = 10, TextColor3 = AMB, Font = Enum.Font.GothamBold, AutoButtonColor = false}, hd) round(b, 4) return b end
	local sb, cb = mini("🚗", -22), mini("▼", 0)
	local body = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2}, pn)
	new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, body)

	-- motor + nitro
	local e = new("Frame", {Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = CARD, BorderSizePixel = 0, LayoutOrder = 1}, body) round(e)
	label(e, "RPM MOTOR", UDim2.new(0, 6, 0, 2), UDim2.new(0.5, 0, 0, 12), CYA, Enum.Font.GothamBold, 9)
	ui.rt = label(e, "0850", UDim2.new(1, -6, 0, 0), UDim2.new(0.5, 0, 0, 16), TXT, Enum.Font.Code, 14, Enum.TextXAlignment.Right, Vector2.new(1, 0))
	ui.rf = bar(e, 20)
	label(e, "VEL", UDim2.new(0, 6, 0, 29), UDim2.new(0.3, 0, 0, 12), GRY, Enum.Font.GothamBold, 9)
	ui.sp = label(e, "000 km/h", UDim2.new(1, -6, 0, 29), UDim2.new(0.7, 0, 0, 12), TXT, Enum.Font.Code, 10, Enum.TextXAlignment.Right, Vector2.new(1, 0))
	label(e, "NITRO", UDim2.new(0, 6, 0, 41), UDim2.new(0.5, 0, 0, 12), GRY, Enum.Font.GothamBold, 9)
	ui.nf = bar(e, 54)

	-- tornado
	local t = new("Frame", {Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = CARD, BorderSizePixel = 0, LayoutOrder = 2}, body) round(t)
	label(t, "RPM TORNADO", UDim2.new(0, 6, 0, 2), UDim2.new(0.55, 0, 0, 12), CYA, Enum.Font.GothamBold, 9)
	ui.tt = label(t, "040", UDim2.new(1, -6, 0, 0), UDim2.new(0.45, 0, 0, 16), TXT, Enum.Font.Code, 14, Enum.TextXAlignment.Right, Vector2.new(1, 0))
	ui.tf = bar(t, 20)
	local function sm(txt, ax, x) local b = new("TextButton", {AnchorPoint = Vector2.new(ax, 0), Position = UDim2.new(ax, x, 0, 32), Size = UDim2.new(0, 32, 0, 26), BackgroundColor3 = OFF, Text = txt, TextColor3 = AMB, Font = Enum.Font.GothamBlack, TextSize = 15, AutoButtonColor = false}, t) round(b, 5) return b end
	local mb, pb = sm("−", 0, 6), sm("+", 1, -6)
	ui.ef = label(t, "EF2", UDim2.new(0, 40, 0, 32), UDim2.new(1, -80, 0, 26), TXT, Enum.Font.GothamBlack, 13, Enum.TextXAlignment.Center)

	-- radar
	local rd = new("Frame", {Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = CARD, BorderSizePixel = 0, LayoutOrder = 3}, body) round(rd)
	local cir = new("Frame", {Position = UDim2.new(0, 6, 0, 6), Size = UDim2.new(0, 58, 0, 58), BackgroundColor3 = BG, BorderSizePixel = 0}, rd)
	new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, cir)
	new("UIStroke", {Color = CYA, Thickness = 1, Transparency = 0.4}, cir)
	local me = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 5, 0, 5), BackgroundColor3 = TXT, BorderSizePixel = 0}, cir)
	new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, me)
	ui.rdot = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 9, 0, 9), BackgroundColor3 = RED, BorderSizePixel = 0, Visible = false}, cir)
	new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, ui.rdot)
	label(rd, "RADAR", UDim2.new(0, 70, 0, 4), UDim2.new(1, -76, 0, 12), CYA, Enum.Font.GothamBold, 9)
	ui.rd = label(rd, "---", UDim2.new(0, 70, 0, 16), UDim2.new(1, -76, 0, 18), TXT, Enum.Font.Code, 13)
	ui.rs = label(rd, "SEM TORNADO", UDim2.new(0, 70, 0, 38), UDim2.new(1, -76, 0, 24), GRY, Enum.Font.GothamBold, 10)
	ui.rs.TextWrapped = true

	-- mapa meteorológico
	local mp = new("Frame", {Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = CARD, BorderSizePixel = 0, LayoutOrder = 3}, body) round(mp)
	label(mp, "MAPA METEO", UDim2.new(0, 6, 0, 2), UDim2.new(0.6, 0, 0, 12), CYA, Enum.Font.GothamBold, 9)
	local mg = new("Frame", {Position = UDim2.new(0, 6, 0, 16), Size = UDim2.new(1, -12, 0, 62), BackgroundColor3 = BG, BorderSizePixel = 0, ClipsDescendants = true}, mp) round(mg, 4)
	for i = 1, 3 do
		new("Frame", {Position = UDim2.new(i / 4, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = EDGE, BackgroundTransparency = 0.5, BorderSizePixel = 0}, mg)
		new("Frame", {Position = UDim2.new(0, 0, i / 4, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = EDGE, BackgroundTransparency = 0.5, BorderSizePixel = 0}, mg)
	end
	new("Frame", {Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 5, 0, 5), BackgroundColor3 = TXT, BorderSizePixel = 0}, mg)
	ui.mg, ui.mtrail = mg, {}
	for i = 1, 16 do
		local f = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 3, 0, 3), BackgroundColor3 = AMB, BorderSizePixel = 0, Visible = false}, mg)
		round(f, 2) ui.mtrail[i] = f
	end
	ui.mwind = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 2, 0, 12), BackgroundColor3 = TXT, BorderSizePixel = 0, Visible = false}, mg)
	ui.mdot = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 7, 0, 7), BackgroundColor3 = RED, BorderSizePixel = 0, Visible = false}, mg) round(ui.mdot, 4)
	ui.mstat = label(mp, "P 1013 hPa  NUV 15%", UDim2.new(0, 6, 0, 80), UDim2.new(1, -12, 0, 13), GRY, Enum.Font.Code, 9)

	-- botões (grade 2 colunas)
	local bf = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4}, body)
	new("UIGridLayout", {CellSize = UDim2.new(0.5, -2, 0, 28), CellPadding = UDim2.new(0, 4, 0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, bf)
	ui.ba, ui.bl, ui.bt = btn(bf, "⚓ LIVRE", 1), btn(bf, "💡 LUZES", 2), btn(bf, "🌪️ TORNADO", 3)
	ui.bc, ui.br, ui.bh, ui.bn = btn(bf, "🎥 CÂMERA", 4), btn(bf, "🌧️ CHUVA", 5), btn(bf, "🎯 CAÇAR", 6), btn(bf, "🔥 NITRO", 7)
	ui.bg, ui.bz = btn(bf, "💥 ARRANCA", 8), btn(bf, "♻ RESTAURAR", 9)
	ui.bx = btn(bf, "🚪 ENTRAR TIV", 10)

	local function tA() setAnchor(not S.anch) end
	local function tL() setLights(not S.lights) end
	local function tT() if tor then killTornado() else spawnTornado() end end
	local function tC() S.cam = not S.cam end
	local function tRn() setRain(not S.rain) end
	local function tH() S.hunt = not S.hunt end
	local function tG() S.grab = not S.grab end
	local function tE() if isSeated() then leaveTIV() else seatPlayer() end end
	local function tR(d) S.tr = math.clamp(S.tr + d, 10, 90) tparams() end
	track(ui.ba.b.Activated:Connect(safe(tA))) track(ui.bl.b.Activated:Connect(safe(tL))) track(ui.bt.b.Activated:Connect(safe(tT)))
	track(ui.bc.b.Activated:Connect(safe(tC))) track(ui.br.b.Activated:Connect(safe(tRn))) track(ui.bh.b.Activated:Connect(safe(tH)))
	track(ui.bg.b.Activated:Connect(safe(tG))) track(ui.bz.b.Activated:Connect(safe(restoreAll))) track(ui.bx.b.Activated:Connect(safe(tE)))
	local function press(i) return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 end
	track(ui.bn.b.InputBegan:Connect(safe(function(i) if press(i) then S.nb = true end end)))
	track(ui.bn.b.InputEnded:Connect(safe(function(i) if press(i) then S.nb = false end end)))
	track(mb.Activated:Connect(safe(function() tR(-5) end))) track(pb.Activated:Connect(safe(function() tR(5) end)))
	track(sb.Activated:Connect(safe(seatPlayer)))
	track(cb.Activated:Connect(safe(function() body.Visible = not body.Visible cb.Text = body.Visible and "▼" or "▲" end)))
	track(UIS.InputBegan:Connect(safe(function(i, gp)
		if gp then return end
		local k = i.KeyCode
		if k == Enum.KeyCode.F then tA() elseif k == Enum.KeyCode.L then tL() elseif k == Enum.KeyCode.T then tT()
		elseif k == Enum.KeyCode.E then tE() elseif k == Enum.KeyCode.C then tC() elseif k == Enum.KeyCode.R then tRn() elseif k == Enum.KeyCode.H then tH() elseif k == Enum.KeyCode.X then tG() elseif k == Enum.KeyCode.Z then restoreAll() end
	end)))
end

local function updateRadar()
	if tor and tiv then
		local rel = tiv.core.CFrame:PointToObjectSpace(tor.pos)
		local dist = V3(rel.X, 0, rel.Z).Magnitude
		local nx, nz = rel.X / 300, rel.Z / 300
		local m = math.sqrt(nx * nx + nz * nz)
		if m > 1 then nx, nz = nx / m, nz / m end
		ui.rdot.Position = UDim2.new(0.5 + nx * 0.45, 0, 0.5 + nz * 0.45, 0)
		ui.rdot.Visible = true
		ui.rd.Text = string.format("%03d m", math.floor(dist))
		local range = 70 + 60 * (S.tr / 60)
		if dist < range then
			ui.rs.Text = "⚠ PERIGO"
			ui.rs.TextColor3 = (math.floor(os.clock() * 4) % 2 == 0) and RED or TXT
		elseif dist < range * 2.5 then
			ui.rs.Text, ui.rs.TextColor3 = "ALERTA", AMB
		else
			ui.rs.Text, ui.rs.TextColor3 = "SEGURO", GRN
		end
	else
		ui.rdot.Visible = false
		ui.rd.Text = "---"
		ui.rs.Text, ui.rs.TextColor3 = "SEM TORNADO", GRY
	end
end

local function updateHUD()
	local p = math.clamp(S.shown / MAXR, 0, 1)
	ui.rt.Text = string.format("%04d", math.floor(S.shown)) ui.rf.Size = UDim2.new(p, 0, 1, 0) ui.rf.BackgroundColor3 = rc(p)
	ui.sp.Text = string.format("%03d km/h", math.floor(math.abs(S.speed)))
	ui.nf.Size = UDim2.new(S.fuel, 0, 1, 0) ui.nf.BackgroundColor3 = S.nit and AMB or CYA
	local q = S.tr / 90
	ui.tt.Text = string.format("%03d", S.tr) ui.tf.Size = UDim2.new(q, 0, 1, 0) ui.tf.BackgroundColor3 = rc(q)
	ui.ef.Text = "EF" .. math.clamp(math.floor(S.tr / 16), 0, 5)
	paint(ui.ba, S.anch, RED) paint(ui.bl, S.lights, AMB) paint(ui.bt, tor ~= nil, CYA)
	paint(ui.bc, S.cam, CYA) paint(ui.br, S.rain, CYA) paint(ui.bh, S.hunt, RED) paint(ui.bn, S.nit, AMB)
	ui.ba.l.Text = S.anch and "⚓ TRAVADO" or "⚓ LIVRE"
	ui.bl.l.Text = S.lights and "💡 LUZES ON" or "💡 LUZES OFF"
	ui.bt.l.Text = tor and "🌪️ REMOVER" or "🌪️ TORNADO"
	ui.bc.l.Text = S.cam and "🎥 CAM ON" or "🎥 CAM OFF"
	ui.br.l.Text = S.rain and "🌧️ CHUVA ON" or "🌧️ CHUVA OFF"
	ui.bh.l.Text = S.hunt and "🎯 CAÇAR ON" or "🎯 CAÇAR OFF"
	paint(ui.bg, S.grab, AMB) paint(ui.bz, false, AMB)
	ui.bg.l.Text = S.grab and "💥 ARRANCA ON" or "💥 ARRANCA OFF"
	local sea = isSeated()
	paint(ui.bx, sea, CYA) ui.bx.l.Text = sea and "🚪 SAIR TIV" or "🚪 ENTRAR TIV"
	updateRadar()
	updateMap()
	if S.fly then ui.rs.Text, ui.rs.TextColor3 = "🌪 VOANDO!", AMB end
end

-- ARRANQUE
local ch = plr.Character or plr.CharacterAdded:Wait()
local hrp = ch:WaitForChild("HumanoidRootPart", 10)
local lf = V3(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z) lf = lf.Magnitude > 0.01 and lf.Unit or V3(0, 0, -1)
local sp = hrp.Position + lf * 30
local pos = V3(sp.X, groundY(sp, hrp.Position.Y - 3) + 2.35, sp.Z)
local scf = CFrame.lookAt(pos, pos + lf)
tiv = buildTIV() tiv.model.Parent = WS tiv.model:PivotTo(scf)
tiv.eng = new("Sound", {Name = "TIV_Engine", SoundId = "rbxassetid://532147820", Looped = true, Volume = 0.3, RollOffMaxDistance = 150}, tiv.core)
tiv.eng:Play()
local _, yaw = scf:ToOrientation() S.yaw = yaw tiv.ao.CFrame = CFrame.Angles(0, yaw, 0)
buildRain()
initSky()
buildHUD() updateHUD()
pcall(function() RS:BindToRenderStep("TIV_Cam", Enum.RenderPriority.Camera.Value + 1, safe(camStep)) end)
local acc = 0
track(RS.Heartbeat:Connect(safe(function(dt)
	dt = math.min(dt, 0.1)
	if not tiv or not tiv.model.Parent then return end
	stepTIV(dt) stepTornado(dt) skyStep(dt)
	if S.rain then
		S.lt -= dt
		if S.lt <= 0 then S.lt = math.random(30, 90) / 10 flash() end
	end
	acc += dt if acc >= 0.066 then acc = 0 updateHUD() end
end)))
task.delay(0.5, safe(seatPlayer))
end)
if not ok0 then warn("[TIV] " .. tostring(e0)) end
end)
