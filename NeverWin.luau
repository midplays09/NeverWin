--[[
╔══════════════════════════════════════════════════════════════╗
║         NeverWin v3  ·  HvH for BloxStrike / Counter Blox    ║
║         UI: Custom ScreenGui — NeverLose-style layout        ║
╠══════════════════════════════════════════════════════════════╣
║  FIXES:                                                      ║
║    · Fixed showPage nil-value error (line 985 / 791)         ║
║    · Removed ESP Preview panel                               ║
║    · Improved glass/transparency aesthetic                   ║
║  NEW:                                                        ║
║    · Game detection (BloxStrike / Counter Blox / Unknown)    ║
║    · Skin Changer (weapon skins, knife, gloves per game)     ║
╚══════════════════════════════════════════════════════════════╝
--]]

-- ─── Services ─────────────────────────────────────────────────
local Players   = game:GetService("Players")
local RunSvc    = game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local HttpSvc   = game:GetService("HttpService")
local TxtSvc    = game:GetService("TextService")
local WS        = game:GetService("Workspace")
local TweenSvc  = game:GetService("TweenService")
local Lighting  = game:GetService("Lighting")

local lp  = Players.LocalPlayer
local cam = WS.CurrentCamera

-- ─── Game Detection ───────────────────────────────────────────
-- Detects whether we are running in BloxStrike or Counter Blox
-- by checking PlaceId and known workspace/folder signatures.
local GAME_ID   = game.PlaceId
local GAME_NAME = "Unknown"
local IS_BLOXSTRIKE   = false
local IS_COUNTERBLOX  = false

do
    -- Known PlaceIds (update if game migrates)
    local BLOXSTRIKE_IDS  = {2872932807, 3527629287}  -- main + testing
    local COUNTERBLOX_IDS = {301549746,  6456528719}   -- CB:RO main + remake

    for _, id in ipairs(BLOXSTRIKE_IDS) do
        if GAME_ID == id then IS_BLOXSTRIKE = true; break end
    end
    for _, id in ipairs(COUNTERBLOX_IDS) do
        if GAME_ID == id then IS_COUNTERBLOX = true; break end
    end

    -- Fallback: heuristic workspace signature check
    if not IS_BLOXSTRIKE and not IS_COUNTERBLOX then
        local gname = game:GetService("MarketplaceService"):GetProductInfo(GAME_ID).Name or ""
        local lower = gname:lower()
        if lower:find("bloxstrike") or lower:find("blox strike") then
            IS_BLOXSTRIKE = true
        elseif lower:find("counter blox") or lower:find("counterblox") then
            IS_COUNTERBLOX = true
        end
    end

    if IS_BLOXSTRIKE then
        GAME_NAME = "BloxStrike"
    elseif IS_COUNTERBLOX then
        GAME_NAME = "Counter Blox"
    else
        GAME_NAME = "Unknown Game"
    end
end

-- ─── isPressed ────────────────────────────────────────────────
local function isPressed(b)
    if typeof(b) ~= "EnumItem" then return false end
    if b.EnumType == Enum.UserInputType then return UIS:IsMouseButtonPressed(b)
    elseif b.EnumType == Enum.KeyCode then return UIS:IsKeyDown(b) end
    return false
end
local function mousePos() return UIS:GetMouseLocation() end

-- ─── Config ───────────────────────────────────────────────────
local cfg = {
    aim_on=true, aim_key=Enum.KeyCode.E, aim_fov=120, aim_smooth=5,
    aim_bone=1, aim_vischeck=true, aim_teamcheck=true,
    aim_predict=true, aim_lead_ms=80, aim_fov_ring=true,
    silent_on=false, silent_key=Enum.UserInputType.MouseButton2,
    silent_fov=200, silent_ring=true,
    rage_on=false, rage_key=Enum.UserInputType.MouseButton1,
    rage_hc=70, rage_mindmg=20, rage_dt=false, rage_hs=false,
    rage_baim=false, rage_strafe=false, rage_autopeak=false,
    bt_on=false, bt_ticks=12,
    trig_on=false, trig_delay=60,
    res_on=false, res_mode=1, res_confidence=true,
    aa_on=false, aa_pitch=1, aa_yaw=1, aa_freestand=false, aa_pitchfake=false,
    esp_on=false, esp_boxes=true, esp_names=true, esp_health=true,
    esp_dist=false, esp_snaplines=false, esp_skeleton=false,
    esp_arrows=true, esp_hitlog=true, esp_maxdist=500,
    wm_on=true, kb_on=true, ind_on=true,
    bhop_on=false, fakelag_on=false, fakelag_ticks=4,
    anti_untrust=false, spread_on=false, spread_groundonly=true,
    fov_on=false, fov_val=90, thirdperson=false,
    -- Skin Changer (skin selections stored in SC.selectedSkins at runtime)
    skin_on=false,
}
local BONES     = {"Head","UpperTorso","HumanoidRootPart"}
local RES_MODES = {"History","Jitter","Flip","Static"}
local PITCHES   = {"Down","Up","Zero"}
local YAWS      = {"Spin","Jitter","Back","Static"}

local CFG_FILE = "neverwin_cfg.json"
local function saveConfig()
    local t = {}
    for k,v in pairs(cfg) do if type(v) ~= "userdata" then t[k] = v end end
    return pcall(writefile, CFG_FILE, HttpSvc:JSONEncode(t))
end
local function loadConfig()
    if not isfile(CFG_FILE) then return false end
    local s,d = pcall(function() return HttpSvc:JSONDecode(readfile(CFG_FILE)) end)
    if not s or type(d) ~= "table" then return false end
    for k,v in pairs(d) do if cfg[k] ~= nil and type(cfg[k]) == type(v) then cfg[k] = v end end
    return true
end
loadConfig()

-- ─── Game helpers ─────────────────────────────────────────────
local function isEnemy(p)
    if p == lp then return false end
    if cfg.aim_teamcheck and lp.Team and p.Team and lp.Team == p.Team then return false end
    return true
end
local function isAlive(p)
    local c = p.Character; if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid"); return h and h.Health > 0
end
local function getRoot(char) return char and char:FindFirstChild("HumanoidRootPart") end
local function getBone(char, name)
    return char and (char:FindFirstChild(name) or char:FindFirstChild("HumanoidRootPart"))
end
local function toScreen(wp)
    local s = cam:WorldToViewportPoint(wp); return Vector2.new(s.X, s.Y), s.Z > 0
end
local function wallCheck(wp)
    if not cfg.aim_vischeck then return true end
    local o = cam.CFrame.Position
    local r = WS:Raycast(o, wp - o); if not r then return true end
    return Players:GetPlayerFromCharacter(r.Instance:FindFirstAncestorOfClass("Model")) ~= nil
end
local function closestTarget(origin, fovLimit)
    origin = origin or mousePos(); fovLimit = fovLimit or cfg.aim_fov
    local best, bestD, bestPos = nil, math.huge, nil
    for _,p in ipairs(Players:GetPlayers()) do
        if not isEnemy(p) or not isAlive(p) then continue end
        local bn = BONES[cfg.aim_bone] or "Head"
        if cfg.rage_baim then
            local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health < h.MaxHealth * 0.3 then bn = "UpperTorso" end
        end
        local bone = getBone(p.Character, bn); if not bone then continue end
        local pos = bone.Position
        if cfg.aim_predict then
            local r = getRoot(p.Character)
            if r then pos = pos + r.Velocity * (cfg.aim_lead_ms / 1000) end
        end
        if (pos - cam.CFrame.Position).Magnitude > cfg.esp_maxdist then continue end
        if not wallCheck(pos) then continue end
        local scr, inF = toScreen(pos); if not inF then continue end
        local d = (scr - origin).Magnitude
        if d < fovLimit and d < bestD then best, bestD, bestPos = p, d, pos end
    end
    return best, bestPos
end

-- ─── Backtrack ────────────────────────────────────────────────
local btRec = {}
RunSvc.Heartbeat:Connect(function()
    if not cfg.bt_on then return end
    local now = tick()
    for _,p in ipairs(Players:GetPlayers()) do
        if p == lp or not p.Character then continue end
        local root = getRoot(p.Character); if not root then continue end
        local id = p.UserId
        if not btRec[id] then btRec[id] = {} end
        local rec = btRec[id]
        table.insert(rec, {pos=root.Position, t=now})
        while #rec > cfg.bt_ticks do table.remove(rec, 1) end
        while rec[1] and (now - rec[1].t) > 0.20 do table.remove(rec, 1) end
    end
end)
local function btPos(player, raw)
    if not cfg.bt_on then return raw end
    local rec = btRec[player.UserId]; if not rec or #rec == 0 then return raw end
    local mp = mousePos(); local best, bd = raw, math.huge
    for _,r in ipairs(rec) do
        local s, ok = cam:WorldToViewportPoint(r.pos)
        if ok then local d = (Vector2.new(s.X, s.Y) - mp).Magnitude
            if d < bd then bd = d; best = r.pos end end
    end
    return best
end

-- ─── Resolver ─────────────────────────────────────────────────
local resD = {}
local function resolvePos(player, pos)
    if not cfg.res_on then return pos, 50 end
    local id = player.UserId
    if not resD[id] then resD[id] = {side=1, t=0, hist={}, conf=50} end
    local d, m = resD[id], cfg.res_mode
    if m == 1 then
        local last = d.hist[#d.hist]
        if last then
            if (pos - last).Magnitude > 15 then d.side = -d.side; d.conf = math.clamp(d.conf - 10, 0, 100)
            else d.conf = math.clamp(d.conf + 5, 0, 100) end
        end
        table.insert(d.hist, pos); if #d.hist > 6 then table.remove(d.hist, 1) end
        return pos + Vector3.new(d.side * 24, 0, 0), d.conf
    elseif m == 2 then
        if tick() - d.t > 0.08 then d.side = -d.side; d.t = tick() end
        return pos + Vector3.new(d.side * 28, 0, 0), 60
    elseif m == 3 then
        d.side = -d.side; return pos + Vector3.new(d.side * 28, 0, 0), 55
    else return pos, 75 end
end

-- ─── FOV Rings ────────────────────────────────────────────────
local function mkCircle(col, thick, sides)
    local c = Drawing.new("Circle"); c.Thickness = thick; c.NumSides = sides
    c.Filled = false; c.Visible = false; c.ZIndex = 10; c.Transparency = 1; c.Color = col; return c
end
local fovRing    = mkCircle(Color3.fromRGB(255,255,255), 1, 64)
local silentRing = mkCircle(Color3.fromRGB(139,139,139), 1.5, 48)
RunSvc.RenderStepped:Connect(function()
    local mp = mousePos()
    fovRing.Position = mp; fovRing.Radius = cfg.aim_fov
    fovRing.Visible = cfg.aim_on and cfg.aim_fov_ring
    silentRing.Position = mp; silentRing.Radius = cfg.silent_fov
    silentRing.Visible = cfg.silent_on and cfg.silent_ring
end)

-- ─── Aimbot ───────────────────────────────────────────────────
RunSvc.RenderStepped:Connect(function()
    local mp = mousePos()
    if cfg.aim_on and isPressed(cfg.aim_key) then
        local _, pos = closestTarget(mp, cfg.aim_fov)
        if pos then
            local scr = toScreen(pos); local delta = scr - mp
            mousemoverel(delta.X / math.max(1, cfg.aim_smooth), delta.Y / math.max(1, cfg.aim_smooth))
        end
    end
    if cfg.silent_on and isPressed(cfg.silent_key) then
        local _, pos = closestTarget(mp, cfg.silent_fov)
        if pos then
            local scr = toScreen(pos); local delta = scr - mp
            mousemoverel(delta.X, delta.Y)
            task.defer(function() mousemoverel(-delta.X, -delta.Y) end)
        end
    end
end)

-- ─── Ragebot ──────────────────────────────────────────────────
local hsBlock = false; local sDir = 1; local sCk = 0
RunSvc.Heartbeat:Connect(function()
    if not cfg.rage_on then return end
    if not isPressed(cfg.rage_key) then return end
    if math.random(100) > cfg.rage_hc then return end
    if cfg.rage_hs then hsBlock = not hsBlock; if hsBlock then return end end
    local target, raw = closestTarget(); if not target or not raw then return end
    local pos = resolvePos(target, btPos(target, raw))
    local dist = (raw - cam.CFrame.Position).Magnitude
    if math.max(1, 100 - dist * 0.15) < cfg.rage_mindmg then return end
    if cfg.rage_strafe and tick() - sCk > 0.11 then
        sDir = -sDir; sCk = tick()
        local root = getRoot(lp.Character)
        if root then pcall(function()
            local rv = root.CFrame.RightVector * sDir * 18
            root.Velocity = Vector3.new(rv.X, root.Velocity.Y, rv.Z)
        end) end
    end
    if cfg.rage_autopeak then
        local root = getRoot(lp.Character)
        if root then local dir = (raw - root.Position).Unit
            pcall(function() root.Velocity = Vector3.new(dir.X*28, root.Velocity.Y, dir.Z*28) end) end
    end
    local mp = mousePos(); local scr = toScreen(pos); local delta = scr - mp
    if cfg.rage_dt then
        mousemoverel(delta.X, delta.Y); mouse1click()
        local b = getBone(target.Character, "UpperTorso")
        if b then local bs = toScreen(b.Position); local bd = bs - mousePos()
            mousemoverel(bd.X, bd.Y); mouse1click(); mousemoverel(-bd.X, -bd.Y) end
        mousemoverel(-delta.X, -delta.Y)
    else mousemoverel(delta.X, delta.Y); mouse1click(); mousemoverel(-delta.X, -delta.Y) end
end)

-- ─── Triggerbot ───────────────────────────────────────────────
local lastTrig = 0
RunSvc.Heartbeat:Connect(function()
    if not cfg.trig_on then return end
    if tick() - lastTrig < cfg.trig_delay / 1000 then return end
    local ray = cam:ScreenPointToRay(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
    local res = WS:Raycast(ray.Origin, ray.Direction * 1000); if not res then return end
    local p = Players:GetPlayerFromCharacter(res.Instance:FindFirstAncestorOfClass("Model"))
    if not p or not isEnemy(p) or not isAlive(p) then return end
    task.delay(cfg.trig_delay/1000, function() mouse1click(); lastTrig = tick() end)
end)

-- ─── Anti-Aim ─────────────────────────────────────────────────
local spinAngle = 0; local pfTick = 0; local pfFlip = false
RunSvc.Stepped:Connect(function()
    if not cfg.aa_on then return end
    local root = getRoot(lp.Character); if not root then return end
    local yaw = 0; local y = cfg.aa_yaw
    if y == 1 then spinAngle = (spinAngle + 8) % 360; yaw = spinAngle
    elseif y == 2 then yaw = (tick() % 0.1 < 0.05) and 58 or -58
    elseif y == 3 then yaw = 180 end
    if cfg.aa_freestand then
        local near, nd = nil, math.huge
        for _,p in ipairs(Players:GetPlayers()) do
            if p == lp or not isAlive(p) then continue end
            local r = getRoot(p.Character); if not r then continue end
            local d = (r.Position - root.Position).Magnitude
            if d < nd then nd = d; near = r end
        end
        if near then local dir = root.Position - near.Position
            yaw = math.deg(math.atan2(dir.X, dir.Z)) end
    end
    local pitch = 0; local pt = cfg.aa_pitch
    if pt == 1 then pitch = 89 elseif pt == 2 then pitch = -89 end
    if cfg.aa_pitchfake then
        pfTick += 1; if pfTick % 6 == 0 then pfFlip = not pfFlip end
        if pfFlip then pitch = -pitch end
    end
    root.CFrame = CFrame.new(root.CFrame.Position)
        * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
end)

-- ─── Misc ─────────────────────────────────────────────────────
UIS.JumpRequest:Connect(function()
    if not cfg.bhop_on then return end
    local h = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if h and h.FloorMaterial ~= Enum.Material.Air then h.Jump = true end
end)
local flTick = 0
RunSvc.Heartbeat:Connect(function()
    if not cfg.fakelag_on then return end; flTick += 1
    pcall(function() lp.SimulationRadius = (flTick % cfg.fakelag_ticks ~= 0) and 0 or 1000 end)
end)
local auTime = tick()
RunSvc.Heartbeat:Connect(function()
    if not cfg.anti_untrust or cfg.fakelag_on then return end
    if tick() - auTime > 25 then auTime = tick(); pcall(function() lp.SimulationRadius = 1000 end) end
end)
RunSvc.Heartbeat:Connect(function()
    if not cfg.spread_on then return end
    local h = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local r = getRoot(lp.Character); if not h or not r then return end
    if cfg.spread_groundonly and h.FloorMaterial == Enum.Material.Air then return end
    if r.Velocity.Magnitude < 1 then pcall(function() r.Velocity = Vector3.zero end) end
end)
RunSvc.RenderStepped:Connect(function()
    cam.FieldOfView = cfg.fov_on and cfg.fov_val or 70
    if cfg.thirdperson then
        local r = getRoot(lp.Character)
        if r then cam.CameraType = Enum.CameraType.Scriptable
            cam.CFrame = CFrame.new(r.Position + Vector3.new(0, 5, 12), r.Position) end
    else cam.CameraType = Enum.CameraType.Custom end
end)

-- ─── ESP ──────────────────────────────────────────────────────
-- ─── ESP ──────────────────────────────────────────────────────
--
-- Box calculation: use only the 4 body-core parts (Head,
-- UpperTorso, LowerTorso, HumanoidRootPart) to derive a
-- stable AABB.  Accessories, tools and hat attachments are
-- intentionally excluded — they caused the box to blow up.
--
-- worldBounds() returns the world-space min/max Y of the
-- character column, then projects just those two points
-- (top-of-head and bottom-of-feet) plus a fixed half-width
-- derived from the HumanoidRootPart size.  This gives a
-- tight, stable box with no per-frame jitter.
--
-- Behind-camera guard: if the depth (Z returned by
-- WorldToViewportPoint) is ≤ 0 for the root, the player is
-- behind us — skip entirely.
--
-- Corner-bracket style box: 8 line segments instead of 4,
-- each only 25 % of the side length.  Cleaner look and the
-- math is simpler (just four corner points, no diagonal).

local SKEL = {
    {"Head","UpperTorso"},
    {"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},  {"LeftUpperArm","LeftLowerArm"},  {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},  {"LeftUpperLeg","LeftLowerLeg"},
    {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"},
}

-- Core body parts used for bounding box (stable, no accessories)
local BOX_PARTS = {"Head","UpperTorso","LowerTorso","HumanoidRootPart","LeftUpperLeg","RightUpperLeg"}

local espObjs = {}

local function mkLine(col, th)
    local l = Drawing.new("Line")
    l.Visible = false; l.Transparency = 1
    l.Color = col or Color3.new(1,1,1)
    l.Thickness = th or 1
    return l
end
local function mkText(sz, col)
    local t = Drawing.new("Text")
    t.Visible = false; t.Transparency = 1
    t.Size = sz or 11; t.Outline = true
    t.Font = Drawing.Fonts.UI
    t.Color = col or Color3.new(1,1,1)
    return t
end
local function mkTri(col)
    local t = Drawing.new("Triangle")
    t.Visible = false; t.Transparency = 1
    t.Color = col or Color3.fromRGB(82,175,255)
    t.Filled = true; t.Thickness = 1
    return t
end

local function buildESP(p)
    local t = {
        -- 8 corner-bracket segments (TL, TR, BL, BR × horizontal+vertical)
        boxLines  = {},
        skelLines = {},
    }
    for i = 1, 8  do t.boxLines[i]  = mkLine(Color3.new(1,1,1), 1.5) end
    for i = 1, #SKEL do t.skelLines[i] = mkLine(Color3.fromRGB(155,162,200), 1) end
    t.name    = mkText(11, Color3.new(1,1,1))
    t.dist    = mkText(9,  Color3.fromRGB(130,138,165))
    t.hpBg    = mkLine(Color3.fromRGB(20,20,20), 3)
    t.hpFill  = mkLine(Color3.fromRGB(70,215,120), 2)
    t.snap    = mkLine(Color3.fromRGB(255,210,55), 1)
    t.confBg  = mkLine(Color3.fromRGB(48,54,72), 2)
    t.confFill= mkLine(Color3.fromRGB(82,175,255), 2)
    t.arrow   = mkTri(Color3.fromRGB(82,175,255))
    espObjs[p] = t
end

local function hideESP(t)
    if not t then return end
    for _,l in ipairs(t.boxLines)  do l.Visible = false end
    for _,l in ipairs(t.skelLines) do l.Visible = false end
    t.name.Visible    = false; t.dist.Visible    = false
    t.hpBg.Visible    = false; t.hpFill.Visible  = false
    t.snap.Visible    = false; t.confBg.Visible  = false
    t.confFill.Visible= false; t.arrow.Visible   = false
end

local function clearESP(p)
    local t = espObjs[p]; if not t then return end
    hideESP(t)
    for _,l in ipairs(t.boxLines)  do l:Remove() end
    for _,l in ipairs(t.skelLines) do l:Remove() end
    t.name:Remove(); t.dist:Remove(); t.hpBg:Remove(); t.hpFill:Remove()
    t.snap:Remove(); t.confBg:Remove(); t.confFill:Remove(); t.arrow:Remove()
    espObjs[p] = nil
end

-- Project a world point; returns sx,sy,depth  (depth>0 = in front of cam)
-- WorldToViewportPoint returns (Vector3 screenPos, bool onScreen)
-- depth is screenPos.Z (positive = in front of camera)
local function w2s(wp)
    local sp = cam:WorldToViewportPoint(wp)
    return sp.X, sp.Y, sp.Z
end

-- Stable bounding box using only core body parts.
-- Returns sx_min, sy_min, sx_max, sy_max, ok
-- "ok" is false if any core part is behind the camera.
local function getBox(char)
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    -- Get the world-space foot position (bottom of capsule)
    -- and head top from the character's Humanoid
    local hum    = char:FindFirstChildOfClass("Humanoid")
    local hip    = root.Position
    -- HipHeight gives us the offset from root to floor
    local hipH   = hum and hum.HipHeight or 1.35
    -- Head top: root Y + hipHeight + head radius (~0.6)
    local yTop   = hip.Y + hipH + 1.4
    -- Feet: root Y - hipHeight
    local yBot   = hip.Y - hipH - 0.15

    -- Half-width: use root size X (approx shoulder width)
    local halfW  = root.Size.X * 0.5 + 0.1
    local halfD  = root.Size.Z * 0.5

    -- Project the 8 corners of the body column bounding box
    local cf = root.CFrame
    local mnX, mnY, mxX, mxY = math.huge, math.huge, -math.huge, -math.huge
    local allInFront = true

    for _, lx in ipairs({-halfW, halfW}) do
        for _, lz in ipairs({-halfD, halfD}) do
            for _, wy in ipairs({yTop, yBot}) do
                -- world position: offset in root's XZ plane, absolute Y
                local wx = hip.X + cf.RightVector.X*lx + cf.LookVector.X*lz
                local wz = hip.Z + cf.RightVector.Z*lx + cf.LookVector.Z*lz
                local sx, sy, depth = w2s(Vector3.new(wx, wy, wz))
                if depth <= 0 then
                    allInFront = false
                    break
                end
                if sx < mnX then mnX = sx end
                if sy < mnY then mnY = sy end
                if sx > mxX then mxX = sx end
                if sy > mxY then mxY = sy end
            end
            if not allInFront then break end
        end
        if not allInFront then break end
    end

    if not allInFront then return nil end
    -- Sanity: reject degenerate boxes (< 4px) that cause line explosions
    if (mxX - mnX) < 4 or (mxY - mnY) < 4 then return nil end
    return mnX, mnY, mxX, mxY
end

-- Draw 8-segment corner-bracket box
-- Each corner has a H and V segment of length = 25% of the side
local function drawBox(t, mnX, mnY, mxX, mxY, col)
    local W = mxX - mnX
    local H = mxY - mnY
    local hLen = math.max(4, math.min(W * 0.22, 20))  -- horizontal seg
    local vLen = math.max(4, math.min(H * 0.22, 20))  -- vertical seg

    -- Corners: TL, TR, BR, BL
    -- Each corner: 1 horizontal line + 1 vertical line  → 8 lines total
    local corners = {
        -- {x, y, hDir, vDir}  — hDir/vDir = ±1 for segment direction
        {mnX, mnY,  1,  1},   -- top-left
        {mxX, mnY, -1,  1},   -- top-right
        {mxX, mxY, -1, -1},   -- bottom-right
        {mnX, mxY,  1, -1},   -- bottom-left
    }
    for i, c in ipairs(corners) do
        local cx, cy, hd, vd = c[1], c[2], c[3], c[4]
        local hLine = t.boxLines[i*2-1]   -- horizontal segment
        local vLine = t.boxLines[i*2]     -- vertical segment

        hLine.From  = Vector2.new(cx, cy)
        hLine.To    = Vector2.new(cx + hd*hLen, cy)
        hLine.Color = col; hLine.Visible = cfg.esp_boxes

        vLine.From  = Vector2.new(cx, cy)
        vLine.To    = Vector2.new(cx, cy + vd*vLen)
        vLine.Color = col; vLine.Visible = cfg.esp_boxes
    end
end

-- Health colour: green → yellow → red
local function hpColor(hf)
    if hf > 0.5 then
        -- green to yellow
        return Color3.fromRGB(math.floor((1-hf)*2*255), 215, 50)
    else
        -- yellow to red
        return Color3.fromRGB(255, math.floor(hf*2*215), 50)
    end
end

-- Off-screen arrow (uses camera right/up vectors, no coord flip bug)
local function updateArrow(t, rootPos)
    local rx, ry, depth = w2s(rootPos)
    local vp   = cam.ViewportSize
    local onscreen = depth > 0
        and rx > 0 and rx < vp.X
        and ry > 0 and ry < vp.Y

    if onscreen then t.arrow.Visible = false; return end

    -- Direction from screen centre to projected point (or behind-flip)
    local cx, cy = vp.X*0.5, vp.Y*0.5
    local dx, dy
    if depth > 0 then
        dx = rx - cx; dy = ry - cy
    else
        -- Behind camera: flip direction
        dx = cx - rx; dy = cy - ry
    end

    local len = math.sqrt(dx*dx + dy*dy)
    if len < 1 then t.arrow.Visible = false; return end
    dx = dx/len; dy = dy/len

    -- Clamp tip to a ring at radius D from screen centre
    local D  = math.min(cx, cy) - 24
    local tx = cx + dx*D
    local ty = cy + dy*D

    -- Perpendicular for arrow base width
    local px, py = -dy, dx
    local S = 7
    t.arrow.PointA = Vector2.new(tx + px*S,    ty + py*S)
    t.arrow.PointB = Vector2.new(tx - px*S,    ty - py*S)
    t.arrow.PointC = Vector2.new(tx + dx*14,   ty + dy*14)
    t.arrow.Visible = cfg.esp_arrows
end

RunSvc.RenderStepped:Connect(function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == lp then continue end

        if not cfg.esp_on or not isEnemy(p) or not isAlive(p) then
            if espObjs[p] then hideESP(espObjs[p]) end
            continue
        end

        if not espObjs[p] then buildESP(p) end
        local t    = espObjs[p]
        local char = p.Character
        local root = getRoot(char)
        if not root then hideESP(t); continue end

        -- Distance cull
        local dist = (root.Position - cam.CFrame.Position).Magnitude
        if dist > cfg.esp_maxdist then hideESP(t); continue end

        -- Behind-camera fast cull (check root depth only)
        local _, _, rootDepth = w2s(root.Position)
        if rootDepth <= 0 then
            -- Still draw arrow so you know where they are
            if espObjs[p] then
                for _,l in ipairs(t.boxLines)  do l.Visible = false end
                for _,l in ipairs(t.skelLines) do l.Visible = false end
                t.name.Visible=false; t.dist.Visible=false
                t.hpBg.Visible=false; t.hpFill.Visible=false
                t.snap.Visible=false; t.confBg.Visible=false; t.confFill.Visible=false
                updateArrow(t, root.Position)
            end
            continue
        end

        -- Bounding box
        local mnX, mnY, mxX, mxY = getBox(char)
        if not mnX then hideESP(t); continue end

        -- Health
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hf  = math.clamp(
            (hum and hum.Health or 0) / math.max(1, hum and hum.MaxHealth or 100),
            0, 1
        )
        local col = hpColor(hf)

        -- Draw box (corner brackets)
        drawBox(t, mnX, mnY, mxX, mxY, col)

        -- Name tag (centred above box)
        if cfg.esp_names then
            t.name.Text     = p.Name
            t.name.Size     = math.clamp(math.floor(200 / math.max(1, dist) * 10), 9, 14)
            t.name.Position = Vector2.new(
                math.floor((mnX + mxX) * 0.5 - t.name.Text:len() * (t.name.Size * 0.32)),
                math.floor(mnY - t.name.Size - 3)
            )
        end
        t.name.Visible = cfg.esp_names

        -- Distance text (below name if both on)
        if cfg.esp_dist then
            local ds = math.floor(dist) .. "m"
            t.dist.Text     = ds
            t.dist.Size     = 9
            t.dist.Position = Vector2.new(
                math.floor((mnX + mxX) * 0.5 - #ds * 3),
                math.floor(mnY - (cfg.esp_names and t.name.Size + 14 or 12))
            )
        end
        t.dist.Visible = cfg.esp_dist

        -- HP bar (left side, vertical)
        local bH   = mxY - mnY
        local barX = math.floor(mnX - 5)
        t.hpBg.From    = Vector2.new(barX, mnY - 1)
        t.hpBg.To      = Vector2.new(barX, mxY + 1)
        t.hpBg.Visible = cfg.esp_health
        t.hpFill.From  = Vector2.new(barX, mxY - bH * hf)
        t.hpFill.To    = Vector2.new(barX, mxY)
        t.hpFill.Color = col
        t.hpFill.Visible = cfg.esp_health

        -- Resolver confidence bar (top, horizontal)
        local rd   = resD[p.UserId]
        local conf = rd and rd.conf or 50
        local bW   = mxX - mnX
        local barY = math.floor(mnY - 3)
        t.confBg.From    = Vector2.new(mnX, barY)
        t.confBg.To      = Vector2.new(mxX, barY)
        t.confBg.Visible = cfg.res_on and cfg.res_confidence
        t.confFill.From  = Vector2.new(mnX, barY)
        t.confFill.To    = Vector2.new(mnX + bW * (conf/100), barY)
        t.confFill.Color = Color3.fromRGB(
            math.floor((1 - conf/100) * 255),
            math.floor(conf/100 * 200), 60
        )
        t.confFill.Visible = cfg.res_on and cfg.res_confidence

        -- Snapline (bottom-centre of screen → head)
        local head = char:FindFirstChild("Head")
        if head then
            local hsx, hsy, hdepth = w2s(head.Position)
            t.snap.From    = Vector2.new(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y)
            t.snap.To      = Vector2.new(hsx, hsy)
            t.snap.Visible = cfg.esp_snaplines and hdepth > 0
        else
            t.snap.Visible = false
        end

        -- Skeleton
        for i, pair in ipairs(SKEL) do
            local a = char:FindFirstChild(pair[1])
            local b = char:FindFirstChild(pair[2])
            if a and b then
                local ax, ay, ad = w2s(a.Position)
                local bx, by, bd = w2s(b.Position)
                if ad > 0 and bd > 0 then
                    t.skelLines[i].From    = Vector2.new(ax, ay)
                    t.skelLines[i].To      = Vector2.new(bx, by)
                    t.skelLines[i].Visible = cfg.esp_skeleton
                else
                    t.skelLines[i].Visible = false
                end
            else
                t.skelLines[i].Visible = false
            end
        end

        -- Off-screen arrow
        updateArrow(t, root.Position)
    end
end)

Players.PlayerRemoving:Connect(function(p)
    clearESP(p); resD[p.UserId] = nil; btRec[p.UserId] = nil
end)

-- ─── Hit Log ──────────────────────────────────────────────────
local hitLog = {}; local hitLbls = {}
for i = 1, 6 do local l = Drawing.new("Text"); l.Size = 12; l.Font = Drawing.Fonts.UI; l.Outline = true; l.Transparency = 1; l.Visible = false; hitLbls[i] = l end
local function pushHit(txt, col)
    if not cfg.esp_hitlog then return end
    table.insert(hitLog, {text=txt, color=col, t=tick()}); if #hitLog > 6 then table.remove(hitLog, 1) end
end
local function hookHit(p)
    if p == lp then return end
    local function attach(char)
        local hum = char:WaitForChild("Humanoid", 5); if not hum then return end
        local prev = hum.Health
        hum.HealthChanged:Connect(function(hp)
            if not isEnemy(p) then prev = hp; return end
            local dmg = prev - hp
            if dmg > 0 then
                if hp <= 0 then pushHit("✕  KILL  "..p.Name, Color3.fromRGB(255,75,75))
                else pushHit("•  HIT   "..p.Name.."  -"..math.ceil(dmg), Color3.fromRGB(255,210,55)) end
            end; prev = hp
        end)
    end
    p.CharacterAdded:Connect(attach); if p.Character then attach(p.Character) end
end
for _,p in ipairs(Players:GetPlayers()) do hookHit(p) end
Players.PlayerAdded:Connect(hookHit)
RunSvc.RenderStepped:Connect(function()
    local now = tick(); local vp = cam.ViewportSize; local x = vp.X - 195; local y0 = vp.Y - 20 - 6*16
    for i = #hitLog, 1, -1 do if now - hitLog[i].t > 4 then table.remove(hitLog, i) end end
    for i = 1, 6 do local e = hitLog[i]; local l = hitLbls[i]
        if e then l.Text = e.text; l.Color = e.color; l.Transparency = math.clamp(1-(now-e.t)/4, 0, 1); l.Position = Vector2.new(x, y0+(i-1)*16); l.Visible = true
        else l.Visible = false end
    end
end)

-- ─── Indicators ───────────────────────────────────────────────
local IND_K = {"AA","SA","FL","DT","HS","BT","AU"}; local indLbls = {}
for _,k in ipairs(IND_K) do local l = Drawing.new("Text"); l.Size = 12; l.Font = Drawing.Fonts.UI; l.Outline = true; l.Transparency = 1; l.Visible = false; indLbls[k] = l end
RunSvc.RenderStepped:Connect(function()
    if not cfg.ind_on then for _,l in pairs(indLbls) do l.Visible = false end; return end
    local x, y0, row = 10, cam.ViewportSize.Y - 115, 0
    local function show(k, txt, col) row += 1; local l = indLbls[k]; l.Text = txt; l.Color = col; l.Position = Vector2.new(x, y0+row*14); l.Visible = true end
    local function hide(k) indLbls[k].Visible = false end
    if cfg.aa_on then show("AA","[AA] "..(PITCHES[cfg.aa_pitch] or"?").." / "..(YAWS[cfg.aa_yaw] or"?"), Color3.fromRGB(82,175,255)) else hide("AA") end
    if cfg.silent_on then show("SA","[SA] SILENT AIM", Color3.fromRGB(139,139,139)) else hide("SA") end
    if cfg.fakelag_on then show("FL","[FL] "..cfg.fakelag_ticks.."t", Color3.fromRGB(255,155,60)) else hide("FL") end
    if cfg.rage_dt then show("DT","[DT] DOUBLETAP", Color3.fromRGB(255,75,75)) else hide("DT") end
    if cfg.rage_hs then show("HS","[HS] HIDESHOTS", Color3.fromRGB(255,75,195)) else hide("HS") end
    if cfg.bt_on then show("BT","[BT] "..cfg.bt_ticks.."t", Color3.fromRGB(70,215,120)) else hide("BT") end
    if cfg.anti_untrust then show("AU","[AU] KEEPALIVE", Color3.fromRGB(130,138,165)) else hide("AU") end
end)

-- ─── Watermark ────────────────────────────────────────────────
local WH = 28; local WP = 12
local wmGui = Instance.new("ScreenGui"); wmGui.Name = "NW_WM"; wmGui.ResetOnSpawn = false; wmGui.IgnoreGuiInset = true; wmGui.DisplayOrder = 996; wmGui.Parent = lp:WaitForChild("PlayerGui")
local wmBg = Instance.new("Frame", wmGui); wmBg.BackgroundColor3 = Color3.fromRGB(14, 17, 26); wmBg.BackgroundTransparency = 0.25; wmBg.BorderSizePixel = 0; wmBg.Size = UDim2.fromOffset(460, WH)
Instance.new("UICorner", wmBg).CornerRadius = UDim.new(0, 6)
local wmStroke = Instance.new("UIStroke", wmBg); wmStroke.Color = Color3.fromRGB(48,54,72); wmStroke.Thickness = 1; wmStroke.Transparency = 0.15
local wmEdge = Instance.new("Frame", wmBg); wmEdge.BackgroundColor3 = Color3.fromRGB(30,144,255); wmEdge.BorderSizePixel = 0; wmEdge.Size = UDim2.fromOffset(3, WH); wmEdge.Position = UDim2.new(1,-3,0,0)
Instance.new("UICorner", wmEdge).CornerRadius = UDim.new(0, 6)
local wmLbl = Instance.new("TextLabel", wmBg); wmLbl.BackgroundTransparency = 1; wmLbl.Position = UDim2.fromOffset(WP, 0); wmLbl.Size = UDim2.new(1,-WP*2-4,1,0); wmLbl.Font = Enum.Font.GothamBold; wmLbl.TextSize = 12; wmLbl.TextColor3 = Color3.fromRGB(225,232,245); wmLbl.TextXAlignment = Enum.TextXAlignment.Left; wmLbl.RichText = true
local fpsBuf = {}; local fpsVal = 60
RunSvc.RenderStepped:Connect(function(dt) table.insert(fpsBuf, 1/dt); if #fpsBuf > 20 then table.remove(fpsBuf, 1) end; local s = 0; for _,v in ipairs(fpsBuf) do s += v end; fpsVal = math.floor(s/#fpsBuf) end)
local function fpsCol(f) if f >= 60 then return "rgb(70,215,120)" elseif f >= 30 then return "rgb(255,210,55)" end; return "rgb(255,75,75)" end
local function subT(t) return ('<font color="rgb(130,138,165)">%s</font>'):format(t) end
local function accT(t) return ('<font color="rgb(82,175,255)"><b>%s</b></font>'):format(t) end
local SEP = subT(" │ ")
RunSvc.RenderStepped:Connect(function()
    wmBg.Visible = cfg.wm_on; if not cfg.wm_on then return end
    local lt = os.date("*t"); local date = ("%02d/%02d/%04d"):format(lt.month, lt.day, lt.year); local time = ("%02d:%02d:%02d"):format(lt.hour, lt.min, lt.sec)
    local fps_rich = ('<font color="%s">%d fps</font>'):format(fpsCol(fpsVal), fpsVal)
    local plain = "NeverWin v3  │  "..lp.Name.."  │  "..GAME_NAME.."  │  "..date.."  │  "..time.."  │  "..fpsVal.." fps"
    local gameCol = IS_BLOXSTRIKE and "rgb(50,190,100)" or IS_COUNTERBLOX and "rgb(30,144,255)" or "rgb(255,120,50)"
    local gameTag = ('<font color="%s"><b>%s</b></font>'):format(gameCol, GAME_NAME)
    wmLbl.Text = accT("NeverWin")..subT(" v3")..SEP..subT(lp.Name)..SEP..gameTag..SEP..subT(date)..SEP..subT(time)..SEP..fps_rich
    local sz = TxtSvc:GetTextSize(plain, 12, Enum.Font.GothamBold, Vector2.new(2000,30)); local w = sz.X + WP*2 + 6
    wmBg.Size = UDim2.fromOffset(w, WH); wmBg.Position = UDim2.new(1,-(w+10), 0, 10)
end)

-- ─── Keybind HUD ──────────────────────────────────────────────
local kbGui = Instance.new("ScreenGui"); kbGui.Name = "NW_KB"; kbGui.ResetOnSpawn = false; kbGui.IgnoreGuiInset = true; kbGui.DisplayOrder = 995; kbGui.Parent = lp:WaitForChild("PlayerGui")
local kbBg = Instance.new("Frame", kbGui); kbBg.BackgroundColor3 = Color3.fromRGB(14, 17, 26); kbBg.BackgroundTransparency = 0.25; kbBg.BorderSizePixel = 0; kbBg.Size = UDim2.fromOffset(380, 22)
Instance.new("UICorner", kbBg).CornerRadius = UDim.new(0, 6)
local kbStroke = Instance.new("UIStroke", kbBg); kbStroke.Color = Color3.fromRGB(48,54,72); kbStroke.Thickness = 1; kbStroke.Transparency = 0.3
local kbLbl = Instance.new("TextLabel", kbBg); kbLbl.BackgroundTransparency = 1; kbLbl.Position = UDim2.fromOffset(10,0); kbLbl.Size = UDim2.new(1,-20,1,0); kbLbl.Font = Enum.Font.Gotham; kbLbl.TextSize = 11; kbLbl.TextColor3 = Color3.fromRGB(225,232,245); kbLbl.TextXAlignment = Enum.TextXAlignment.Left; kbLbl.RichText = true
local function bindName(b)
    if typeof(b) ~= "EnumItem" then return "?" end; local s = tostring(b)
    if b.EnumType == Enum.UserInputType then
        return ({[tostring(Enum.UserInputType.MouseButton1)]="LMB",[tostring(Enum.UserInputType.MouseButton2)]="RMB",[tostring(Enum.UserInputType.MouseButton3)]="MMB"})[s] or s:match("UserInputType%.(.+)") or "?"
    end; return s:match("KeyCode%.(.+)") or "?"
end
RunSvc.RenderStepped:Connect(function()
    kbBg.Visible = cfg.kb_on; if not cfg.kb_on then return end
    local binds = {{name="Aim",key=cfg.aim_key,active=cfg.aim_on},{name="Silent",key=cfg.silent_key,active=cfg.silent_on},{name="Rage",key=cfg.rage_key,active=cfg.rage_on},{name="Trig",key=nil,active=cfg.trig_on}}
    local parts = {}
    for _,b in ipairs(binds) do
        local pressing = b.key and isPressed(b.key) or false
        local dot = pressing and '<font color="rgb(70,215,120)">●</font>' or (b.active and '<font color="rgb(82,175,255)">○</font>' or '<font color="rgb(50,55,75)">○</font>')
        local kn = b.key and ('<font color="rgb(95,105,130)">[</font>'..bindName(b.key)..'<font color="rgb(95,105,130)">]</font> ') or ""
        table.insert(parts, kn..b.name.." "..dot)
    end
    kbLbl.Text = table.concat(parts, '<font color="rgb(40,46,64)">  │  </font>')
    local plain = "[E] Aim ●  │  [RMB] Silent ●  │  [LMB] Rage ●  │  Trig ●"
    local sz = TxtSvc:GetTextSize(plain, 11, Enum.Font.Gotham, Vector2.new(2000,30)); local w = sz.X + 22
    kbBg.Size = UDim2.fromOffset(w, 22); kbBg.Position = UDim2.new(1,-(w+10), 0, 10+WH+4)
end)

-- ═══════════════════════════════════════════════════════
-- ─── MAIN UI ─────────────────────────────────────────
-- ═══════════════════════════════════════════════════════

-- Blur effect
local blurFX = Instance.new("BlurEffect")
blurFX.Size   = 18
blurFX.Parent = Lighting

-- ─── Palette (NeverLose-accurate glass theme) ─────────
local C = {
    win      = Color3.fromRGB( 12, 15, 26),
    sidebar  = Color3.fromRGB( 10, 13, 22),
    content  = Color3.fromRGB( 15, 19, 32),
    topbar   = Color3.fromRGB( 10, 13, 22),
    row_sel  = Color3.fromRGB( 18, 42, 98),
    section_bg = Color3.fromRGB(18, 22, 38),
    border   = Color3.fromRGB( 28, 38, 66),
    blue     = Color3.fromRGB( 30,144,255),
    teal     = Color3.fromRGB( 25,175,195),
    tog_on   = Color3.fromRGB( 30,144,255),
    tog_off  = Color3.fromRGB( 38, 48, 78),
    text_w   = Color3.fromRGB(218,226,244),
    text_s   = Color3.fromRGB(100,118,158),
    text_cat = Color3.fromRGB( 68,  88,130),
    title    = Color3.fromRGB(235,241,255),
    green    = Color3.fromRGB( 45,185, 95),
    icon_c   = {
        Color3.fromRGB( 30,144,255), Color3.fromRGB( 25,175,195),
        Color3.fromRGB(140,100,255), Color3.fromRGB( 80,200, 80),
        Color3.fromRGB(220, 90, 90), Color3.fromRGB(200,160, 50),
        Color3.fromRGB(255,120, 60), Color3.fromRGB(160, 80,255),
    },
    -- glass transparency values (lower = more opaque glass)
    GLASS_WIN     = 0.45,   -- main window bg
    GLASS_SIDEBAR = 0.50,   -- sidebar slightly more transparent
    GLASS_CONTENT = 0.42,   -- content pane
    GLASS_TOPBAR  = 0.50,
    GLASS_ROW     = 0.70,   -- hover row
    GLASS_SECTION = 0.55,   -- section headers
    GLASS_BTN     = 0.30,   -- buttons (more solid)
    GLASS_STROKE  = 0.20,   -- border strokes (more visible)
}

-- ─── Helpers ──────────────────────────────────────────
local function N(cls, props, parent)
    local o = Instance.new(cls)
    for k,v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(r, p)  N("UICorner",  {CornerRadius=UDim.new(0,r)}, p) end
local function stroke(col, th, tr, p)
    -- tr = transparency (0=opaque)
    local s = N("UIStroke", {Color=col, Thickness=th}, p)
    if tr then s.Transparency = tr end
    return s
end
local function pad(t, b, l, r, p)
    N("UIPadding", {PaddingTop=UDim.new(0,t), PaddingBottom=UDim.new(0,b), PaddingLeft=UDim.new(0,l), PaddingRight=UDim.new(0,r)}, p)
end
local function listV(gap, p) N("UIListLayout",  {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,gap)}, p) end
local function listH(gap, p) N("UIListLayout",  {FillDirection=Enum.FillDirection.Horizontal, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,gap), VerticalAlignment=Enum.VerticalAlignment.Center}, p) end
local function tw(o, d, pr)  TweenSvc:Create(o, TweenInfo.new(d, Enum.EasingStyle.Quad), pr):Play() end

-- Window dimensions — no preview panel
local SB_W, CT_W, WIN_H, TB_H = 185, 490, 660, 52
local WIN_W = SB_W + CT_W

-- Main ScreenGui
local gui = N("ScreenGui", {
    Name = "NW_UI", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, lp:WaitForChild("PlayerGui"))

-- ─── Window frame ─────────────────────────────────────
local win = N("Frame", {
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    Position = UDim2.fromOffset(100, 38),
    BackgroundColor3 = C.win,
    BackgroundTransparency = C.GLASS_WIN,
    BorderSizePixel = 0,
    ClipsDescendants = false,
}, gui)
corner(10, win)
stroke(C.border, 1, C.GLASS_STROKE, win)

-- Subtle inner glow on top edge
local topGlow = N("Frame", {
    Size = UDim2.fromOffset(WIN_W, 1),
    BackgroundColor3 = Color3.fromRGB(60, 100, 200),
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
}, win)

-- ─── Drag ─────────────────────────────────────────────
local attachDrag
do
    local drag, ds, wp = false
    attachDrag = function(f)
        f.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then drag=true; ds=i.Position; wp=win.Position end
        end)
    end
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - ds
            win.Position = UDim2.fromOffset(wp.X.Offset + d.X, wp.Y.Offset + d.Y)
        end
    end)
end

local minimized = false
UIS.InputEnded:Connect(function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.Home then
        minimized = not minimized
        win.Visible = not minimized
        blurFX.Size = minimized and 0 or 18
    end
end)

-- ─── SIDEBAR ──────────────────────────────────────────
local sb = N("Frame", {
    Size = UDim2.fromOffset(SB_W, WIN_H),
    BackgroundColor3 = C.sidebar,
    BackgroundTransparency = C.GLASS_SIDEBAR,
    BorderSizePixel = 0,
}, win)
corner(10, sb)
-- Right edge divider
N("Frame", {
    Size = UDim2.fromOffset(1, WIN_H),
    Position = UDim2.fromOffset(SB_W-1, 0),
    BackgroundColor3 = C.border,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
}, win)

-- Logo area
local sbHead = N("Frame", {
    Size = UDim2.fromOffset(SB_W, 60),
    BackgroundTransparency = 1,
}, sb)
-- Blue accent bar left of logo
N("Frame", {
    Size = UDim2.fromOffset(3, 22),
    Position = UDim2.fromOffset(14, 19),
    BackgroundColor3 = C.blue,
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
}, sbHead)
N("TextLabel", {
    Size = UDim2.new(1,0,1,0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBlack,
    TextSize = 20,
    Text = "NEVERWIN",
    TextColor3 = C.title,
    TextXAlignment = Enum.TextXAlignment.Left,
}, sbHead)
pad(0, 0, 24, 0, sbHead)
attachDrag(sbHead)

N("Frame", {
    Size = UDim2.fromOffset(SB_W-20, 1),
    Position = UDim2.fromOffset(10, 60),
    BackgroundColor3 = C.border,
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
}, sb)

-- Scrollable nav
local sbScroll = N("ScrollingFrame", {
    Size = UDim2.fromOffset(SB_W, WIN_H - 120),
    Position = UDim2.fromOffset(0, 66),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, sb)
listV(2, sbScroll); pad(2, 2, 4, 4, sbScroll)

-- User strip at bottom
local uStrip = N("Frame", {
    Size = UDim2.fromOffset(SB_W, 58),
    Position = UDim2.fromOffset(0, WIN_H-58),
    BackgroundColor3 = C.sidebar,
    BackgroundTransparency = C.GLASS_SIDEBAR + 0.05,
    BorderSizePixel = 0,
}, sb)
N("Frame", {Size=UDim2.fromOffset(SB_W,1), BackgroundColor3=C.border, BackgroundTransparency=0.4, BorderSizePixel=0}, uStrip)
local uCirc = N("Frame", {
    Size = UDim2.fromOffset(34,34),
    Position = UDim2.fromOffset(10, 12),
    BackgroundColor3 = Color3.fromRGB(28, 36, 60),
    BackgroundTransparency = 0.1,
    BorderSizePixel = 0,
}, uStrip)
corner(17, uCirc); stroke(C.border, 1, 0.3, uCirc)
N("TextLabel", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Font=Enum.Font.GothamBold, TextSize=11, Text="NW", TextColor3=C.text_s}, uCirc)
N("TextLabel", {Size=UDim2.fromOffset(SB_W-54,18), Position=UDim2.fromOffset(50,8), BackgroundTransparency=1, Font=Enum.Font.GothamBold, TextSize=13, Text=lp.Name, TextColor3=C.text_w, TextXAlignment=Enum.TextXAlignment.Left}, uStrip)
local tillL = N("TextLabel", {Size=UDim2.fromOffset(SB_W-54,14), Position=UDim2.fromOffset(50,27), BackgroundTransparency=1, Font=Enum.Font.Gotham, TextSize=10, TextColor3=Color3.fromRGB(255,120,50), TextXAlignment=Enum.TextXAlignment.Left}, uStrip)
local function updTill() local t = os.date("*t"); tillL.Text = ("Till: %02d.%02d %02d:%02d"):format(t.month, t.day, t.hour, t.min) end
updTill(); RunSvc.Heartbeat:Connect(updTill)

-- ─── CONTENT PANEL ────────────────────────────────────
local ctFrame = N("Frame", {
    Size = UDim2.fromOffset(CT_W, WIN_H),
    Position = UDim2.fromOffset(SB_W, 0),
    BackgroundColor3 = C.content,
    BackgroundTransparency = C.GLASS_CONTENT,
    BorderSizePixel = 0,
    ClipsDescendants = false,
}, win)

-- ─── TOPBAR ───────────────────────────────────────────
local topBar = N("Frame", {
    Size = UDim2.fromOffset(CT_W, TB_H),
    BackgroundColor3 = C.topbar,
    BackgroundTransparency = C.GLASS_TOPBAR,
    BorderSizePixel = 0,
}, ctFrame)
attachDrag(topBar)
N("Frame", {
    Size = UDim2.fromOffset(CT_W, 1),
    Position = UDim2.fromOffset(0, TB_H),
    BackgroundColor3 = C.border,
    BackgroundTransparency = 0.3,
    BorderSizePixel = 0,
}, ctFrame)

-- Save pill button
local saveBtn = N("TextButton", {
    Size = UDim2.fromOffset(88, 30),
    Position = UDim2.fromOffset(10, 11),
    BackgroundColor3 = C.section_bg,
    BackgroundTransparency = C.GLASS_BTN,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold, TextSize = 13,
    Text = "💾  Save", TextColor3 = C.text_w,
    AutoButtonColor = false,
}, topBar)
corner(6, saveBtn); stroke(C.border, 1, C.GLASS_STROKE, saveBtn)
saveBtn.Activated:Connect(function()
    saveConfig()
    tw(saveBtn, 0.1, {BackgroundColor3 = C.green, BackgroundTransparency = 0.15})
    task.delay(0.9, function() tw(saveBtn, 0.15, {BackgroundColor3 = C.section_bg, BackgroundTransparency = C.GLASS_BTN}) end)
end)

-- Page dropdown pill
local ddBtn = N("TextButton", {
    Size = UDim2.fromOffset(128, 30),
    Position = UDim2.fromOffset(106, 11),
    BackgroundColor3 = C.section_bg,
    BackgroundTransparency = C.GLASS_BTN,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold, TextSize = 13,
    Text = "Aimbot  ▾", TextColor3 = C.text_w,
    AutoButtonColor = false,
}, topBar)
corner(6, ddBtn); stroke(C.border, 1, C.GLASS_STROKE, ddBtn)

-- Right icon buttons
for i, sym in ipairs({"⚙","🔔","🔍"}) do
    local xp = CT_W - (4-i)*38
    local ib = N("TextButton", {
        Size = UDim2.fromOffset(30, 30),
        Position = UDim2.fromOffset(xp, 11),
        BackgroundColor3 = C.section_bg,
        BackgroundTransparency = C.GLASS_BTN + 0.15,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextSize = 15,
        Text = sym, TextColor3 = C.text_s,
        AutoButtonColor = false,
    }, topBar)
    corner(6, ib)
end

-- Pages holder
local pagesHolder = N("Frame", {
    Size = UDim2.fromOffset(CT_W, WIN_H-TB_H-1),
    Position = UDim2.fromOffset(0, TB_H+1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, ctFrame)

-- ═══════════════════════════════════════════════════════
-- ─── PAGE + NAV REGISTRY  (FIX: single declaration) ───
-- ═══════════════════════════════════════════════════════
local pages     = {}
local navItems  = {}
local curPage   = nil

-- Forward-declare showPage as an upvalue, then assign immediately
local showPage
showPage = function(name)
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    for n, it in pairs(navItems) do
        local sel = (n == name)
        it.pill.BackgroundTransparency = sel and 0.55 or 1
        it.lbl.TextColor3 = sel and C.text_w or C.text_s
        it.lbl.Font = sel and Enum.Font.GothamBold or Enum.Font.Gotham
        if sel then
            tw(it.pill, 0.12, {BackgroundTransparency = 0.55, BackgroundColor3 = C.row_sel})
        end
    end
    ddBtn.Text = name:sub(1,1):upper()..name:sub(2).."  ▾"
    curPage = name
end

-- ─── Sidebar nav builders ─────────────────────────────
local navOrd = 0; local icI = 0
local function catLabel(txt)
    navOrd += 1
    local f = N("Frame", {Size=UDim2.new(1,0,0,24), BackgroundTransparency=1, LayoutOrder=navOrd}, sbScroll)
    N("TextLabel", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Font=Enum.Font.GothamBold, TextSize=10, Text=txt, TextColor3=C.text_cat, TextXAlignment=Enum.TextXAlignment.Left}, f)
    pad(4, 0, 14, 0, f)
end
local function navItem(label, pageName)
    navOrd += 1; icI = (icI % #C.icon_c) + 1; local icCol = C.icon_c[icI]
    local btn = N("TextButton", {
        Size = UDim2.new(1,0,0,36),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Text = "", AutoButtonColor = false, LayoutOrder = navOrd,
    }, sbScroll)
    local pill = N("Frame", {
        Size = UDim2.new(1,-6,1,-2),
        Position = UDim2.fromOffset(3,1),
        BackgroundColor3 = C.row_sel,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, btn); corner(6, pill)
    local icon = N("Frame", {
        Size = UDim2.fromOffset(22,22),
        Position = UDim2.fromOffset(10,7),
        BackgroundColor3 = icCol,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
    }, btn); corner(5, icon)
    N("TextLabel", {
        Size = UDim2.new(1,0,1,0), BackgroundTransparency=1,
        Font=Enum.Font.GothamBold, TextSize=11,
        Text=string.upper(string.sub(label,1,1)), TextColor3=Color3.new(1,1,1),
    }, icon)
    local lbl = N("TextLabel", {
        Size = UDim2.fromOffset(SB_W-48, 36),
        Position = UDim2.fromOffset(40, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 14,
        Text = label, TextColor3 = C.text_s,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, btn)
    btn.MouseEnter:Connect(function()
        if curPage ~= pageName then
            tw(pill, 0.1, {BackgroundTransparency=0.80})
        end
    end)
    btn.MouseLeave:Connect(function()
        if curPage ~= pageName then
            tw(pill, 0.1, {BackgroundTransparency=1})
        end
    end)
    btn.Activated:Connect(function() showPage(pageName) end)   -- FIX: showPage is now in scope
    navItems[pageName] = {pill=pill, lbl=lbl, icon=icon, iconCol=icCol}
end

-- ─── Page frame builder ───────────────────────────────
local function addPage(pageName)
    local pg = N("Frame", {
        Size = UDim2.new(1,0,1,0),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Visible = false,
    }, pagesHolder)
    pages[pageName] = pg
    local colW   = math.floor((CT_W - 2) / 2)
    local colH   = WIN_H - TB_H - 10
    local lCol = N("ScrollingFrame", {
        Size = UDim2.fromOffset(colW, colH),
        Position = UDim2.fromOffset(0, 4),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.teal,
        CanvasSize = UDim2.fromOffset(0,0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ClipsDescendants = true,
    }, pg)
    listV(0, lCol); pad(2, 6, 12, 4, lCol)
    local rCol = N("ScrollingFrame", {
        Size = UDim2.fromOffset(colW, colH),
        Position = UDim2.fromOffset(colW+2, 4),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.teal,
        CanvasSize = UDim2.fromOffset(0,0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ClipsDescendants = true,
    }, pg)
    listV(0, rCol); pad(2, 6, 12, 4, rCol)
    N("Frame", {
        Size = UDim2.fromOffset(1, colH),
        Position = UDim2.fromOffset(colW, 4),
        BackgroundColor3 = C.border,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
    }, pg)
    return lCol, rCol
end

-- ─── Widget helpers ───────────────────────────────────
local wOrd = 0
local function wo() wOrd += 1; return wOrd end
local ROW_H = 34

local function sep(parent)
    N("Frame", {
        Size = UDim2.new(1,0,0,1),
        Position = UDim2.new(0,0,1,-1),
        BackgroundColor3 = C.border,
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
    }, parent)
end

local function secHdr(parent, label)
    local f = N("Frame", {
        Size = UDim2.new(1,0,0,34),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        LayoutOrder = wo(),
    }, parent)
    -- Accent dot
    N("Frame", {
        Size = UDim2.fromOffset(3,14),
        Position = UDim2.fromOffset(0,10),
        BackgroundColor3 = C.blue,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
    }, f)
    N("TextLabel", {
        Size = UDim2.new(1,-6,1,-1),
        Position = UDim2.fromOffset(8,0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 13,
        Text = label, TextColor3 = C.text_w,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    N("Frame", {
        Size = UDim2.new(1,0,0,1),
        Position = UDim2.new(0,0,1,-1),
        BackgroundColor3 = C.border,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
    }, f)
end

local function togRow(parent, label, init, cb)
    local f = N("Frame", {
        Size = UDim2.new(1,0,0,ROW_H),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        LayoutOrder = wo(),
    }, parent)
    sep(f)
    N("TextLabel", {
        Size = UDim2.new(1,-54,1,0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 13,
        Text = label, TextColor3 = C.text_w,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    local PW, PH = 32, 16
    local pill = N("Frame", {
        Size = UDim2.fromOffset(PW, PH),
        Position = UDim2.new(1,-(PW+8), 0.5,-PH/2),
        BackgroundColor3 = init and C.tog_on or C.tog_off,
        BorderSizePixel = 0,
    }, f); corner(PH/2, pill)
    stroke(init and C.tog_on or C.tog_off, 1, 0.4, pill)
    local DS = PH - 4
    local dot = N("Frame", {
        Size = UDim2.fromOffset(DS, DS),
        Position = UDim2.fromOffset(init and PW-DS-2 or 2, 2),
        BackgroundColor3 = Color3.new(1,1,1),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
    }, pill); corner(DS/2, dot)
    local st = {v=init}
    local function set(v)
        st.v = v
        tw(pill, 0.13, {BackgroundColor3 = v and C.tog_on or C.tog_off})
        tw(dot,  0.13, {Position = UDim2.fromOffset(v and PW-DS-2 or 2, 2)})
        if cb then cb(v) end
    end
    local btn = N("TextButton", {
        Size = UDim2.new(1,0,1,0),
        BackgroundTransparency = 1, Text = "", BorderSizePixel = 0,
    }, f)
    btn.Activated:Connect(function() set(not st.v) end)
    btn.MouseEnter:Connect(function() tw(f, 0.08, {BackgroundColor3=C.section_bg, BackgroundTransparency=C.GLASS_ROW}) end)
    btn.MouseLeave:Connect(function() tw(f, 0.08, {BackgroundTransparency=1}) end)
end

local function sldRow(parent, label, mn, mx, init, cb)
    local f = N("Frame", {
        Size = UDim2.new(1,0,0,ROW_H+4),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        LayoutOrder = wo(),
    }, parent)
    sep(f)
    N("TextLabel", {
        Size = UDim2.new(0.46,0,0,ROW_H),
        Position = UDim2.fromOffset(0,2),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 13,
        Text = label, TextColor3 = C.text_w,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    local vL = N("TextLabel", {
        Size = UDim2.fromOffset(38,ROW_H),
        Position = UDim2.new(1,-42,0,2),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 13,
        Text = tostring(init), TextColor3 = C.text_w,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, f)
    local TW = math.floor(CT_W/2 * 0.50); local TH = 3
    local track = N("Frame", {
        Size = UDim2.fromOffset(TW, TH),
        Position = UDim2.new(0.46, 4, 0.5, 2),
        BackgroundColor3 = Color3.fromRGB(30, 40, 68),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
    }, f); corner(2, track)
    local pct  = (init-mn)/(mx-mn)
    local fill = N("Frame", {
        Size = UDim2.new(pct,0,1,0),
        BackgroundColor3 = C.teal,
        BorderSizePixel = 0,
    }, track); corner(2, fill)
    local knob = N("Frame", {
        Size = UDim2.fromOffset(10,10),
        Position = UDim2.new(pct,-5,-1,0),
        BackgroundColor3 = Color3.new(1,1,1),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
    }, track); corner(5, knob)
    -- knob inner
    N("Frame",{Size=UDim2.fromOffset(4,4),Position=UDim2.fromOffset(3,3),BackgroundColor3=C.teal,BorderSizePixel=0},knob); corner(2, knob:FindFirstChildOfClass("Frame"))
    local st = {v=init, d=false}
    local function sv(v)
        v = math.clamp(math.round(v), mn, mx); st.v = v
        local p = (v-mn)/(mx-mn)
        fill.Size = UDim2.new(p,0,1,0)
        knob.Position = UDim2.new(p,-5,-1,0)
        vL.Text = tostring(v)
        if cb then cb(v) end
    end
    local hb = N("TextButton", {
        Size = UDim2.fromOffset(TW+20, 22),
        Position = UDim2.new(0.46,-6,0.5,-8),
        BackgroundTransparency = 1, Text = "", BorderSizePixel = 0,
    }, f)
    hb.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then st.d=true end end)
    hb.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then st.d=false end end)
    UIS.InputChanged:Connect(function(i)
        if st.d and i.UserInputType==Enum.UserInputType.MouseMovement then
            sv(mn + math.clamp((i.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1) * (mx-mn))
        end
    end)
    f.MouseEnter:Connect(function() tw(f,0.08,{BackgroundColor3=C.section_bg, BackgroundTransparency=C.GLASS_ROW}) end)
    f.MouseLeave:Connect(function() tw(f,0.08,{BackgroundTransparency=1}) end)
end

-- ─── Dropdown side-panel ──────────────────────────────
-- Opens as a panel anchored to the right edge of the
-- content area — completely outside the scroll columns,
-- never covers other rows.  One panel is shared and
-- reused; opening a new one instantly replaces the old.

-- ─── Dropdown overlay ─────────────────────────────────
-- A single shared panel that covers the entire content
-- area (right of sidebar) at ZIndex 30. Parented to win
-- so it moves with the window automatically — no
-- position-sync heartbeat needed, never off-screen.
-- Shows the option list for whichever ddRow was clicked.

local ddOverlay = nil   -- Frame covering content area
local ddOwner   = nil   -- which ddRow currently owns it

local function closeDDOverlay()
    if ddOverlay then ddOverlay:Destroy(); ddOverlay = nil end
    ddOwner = nil
end

local function openDDOverlay(label, opts, curIdx, onSelect, ownerRef)
    closeDDOverlay()
    ddOwner = ownerRef

    -- Full-height overlay covering just the content area
    ddOverlay = N("Frame", {
        Size     = UDim2.fromOffset(CT_W, WIN_H - TB_H),
        Position = UDim2.fromOffset(SB_W, TB_H),
        BackgroundColor3     = Color3.fromRGB(11, 15, 26),
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        ZIndex = 30,
        ClipsDescendants = true,
    }, win)
    stroke(C.border, 1, 0.15, ddOverlay)

    -- Header bar
    local hdr = N("Frame", {
        Size = UDim2.new(1,0,0,42),
        BackgroundColor3 = Color3.fromRGB(16, 21, 38),
        BackgroundTransparency = 0,
        BorderSizePixel = 0, ZIndex = 31,
    }, ddOverlay)
    N("TextLabel", {
        Size = UDim2.new(1,-46,1,0),
        Position = UDim2.fromOffset(14,0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 13,
        Text = label, TextColor3 = C.text_w,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 32,
    }, hdr)
    -- Blue accent bar on left
    N("Frame",{
        Size=UDim2.fromOffset(3,24),
        Position=UDim2.fromOffset(0,9),
        BackgroundColor3=C.blue,
        BorderSizePixel=0, ZIndex=32,
    }, hdr)
    -- ✕ close button
    local xBtn = N("TextButton", {
        Size = UDim2.fromOffset(30, 30),
        Position = UDim2.fromOffset(CT_W-38, 6),
        BackgroundColor3 = Color3.fromRGB(35,22,22),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextSize = 14,
        Text = "✕", TextColor3 = Color3.fromRGB(210,70,70),
        AutoButtonColor = false, ZIndex = 32,
    }, hdr); corner(6, xBtn)
    xBtn.Activated:Connect(closeDDOverlay)

    -- Divider
    N("Frame",{
        Size=UDim2.fromOffset(CT_W,1),
        Position=UDim2.fromOffset(0,42),
        BackgroundColor3=C.border,
        BackgroundTransparency=0.25,
        BorderSizePixel=0, ZIndex=31,
    }, ddOverlay)

    -- Scrollable list of options
    local itemH = 28
    local sf = N("ScrollingFrame", {
        Size = UDim2.fromOffset(CT_W, WIN_H - TB_H - 44),
        Position = UDim2.fromOffset(0, 44),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = C.teal,
        CanvasSize = UDim2.fromOffset(0, #opts * (itemH+1) + 6),
        ZIndex = 31,
    }, ddOverlay)
    listV(2, sf); pad(4, 8, 6, 8, sf)

    for i, op in ipairs(opts) do
        local sel = (i == curIdx)
        local ob = N("TextButton", {
            Size = UDim2.new(1,0,0,itemH),
            BackgroundColor3 = sel and C.row_sel or Color3.fromRGB(18,23,40),
            BackgroundTransparency = sel and 0.15 or 0.55,
            BorderSizePixel = 0,
            Font = sel and Enum.Font.GothamBold or Enum.Font.Gotham,
            TextSize = 13,
            Text = op,
            TextColor3 = sel and C.text_w or C.text_s,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false, LayoutOrder = i, ZIndex = 32,
        }, sf); corner(5, ob)
        -- Left accent on selected
        if sel then
            N("Frame",{Size=UDim2.fromOffset(3,itemH),BackgroundColor3=C.blue,BorderSizePixel=0,ZIndex=33},ob)
        end
        -- Indent text
        N("UIPadding",{PaddingLeft=UDim.new(0,14)},ob)
        ob.MouseEnter:Connect(function()
            if not sel then ob.BackgroundTransparency=0.35 end
        end)
        ob.MouseLeave:Connect(function()
            if not sel then ob.BackgroundTransparency=0.55 end
        end)
        ob.Activated:Connect(function()
            onSelect(i, op)
            closeDDOverlay()
        end)
    end

    -- Scroll to show currently selected item
    local scrollTo = math.max(0, (curIdx-1)*(itemH+1) - 60)
    sf.CanvasPosition = Vector2.new(0, scrollTo)
end

local function ddRow(parent, label, opts, init, cb)
    local f = N("Frame", {
        Size = UDim2.new(1,0,0,ROW_H),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        LayoutOrder = wo(),
    }, parent)
    sep(f)
    N("TextLabel", {
        Size = UDim2.new(0.5,0,1,0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 13,
        Text = label, TextColor3 = C.text_w,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    local DW = 136
    local db = N("TextButton", {
        Size     = UDim2.fromOffset(DW, 24),
        Position = UDim2.new(1,-(DW+4), 0.5,-12),
        BackgroundColor3 = C.section_bg,
        BackgroundTransparency = C.GLASS_BTN,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham, TextSize = 12,
        Text = opts[init].." ▾", TextColor3 = C.text_w,
        AutoButtonColor = false, ZIndex = 5,
    }, f)
    corner(4, db); stroke(C.border, 1, C.GLASS_STROKE, db)

    local st = {v = init}

    db.Activated:Connect(function()
        -- Toggle: clicking the same row's button closes the overlay
        if ddOwner == db then closeDDOverlay(); return end
        openDDOverlay(label, opts, st.v, function(idx)
            st.v = idx
            db.Text = opts[idx].." ▾"
            if cb then cb(idx) end
        end, db)
    end)

    f.MouseEnter:Connect(function() tw(f,0.08,{BackgroundColor3=C.section_bg,BackgroundTransparency=C.GLASS_ROW}) end)
    f.MouseLeave:Connect(function() tw(f,0.08,{BackgroundTransparency=1}) end)
end

-- ═══════════════════════════════════════════════════════
-- ─── SKIN CHANGER SYSTEM (v3 — correct RS approach) ───
-- ═══════════════════════════════════════════════════════
--
-- BloxStrike stores ALL skin data in:
--   ReplicatedStorage.Assets.Skins.<WeaponName>.<SkinName>
--     .Camera.<Wear>.<PartName>  → SurfaceAppearance to clone
--
-- Weapons appear in the Camera as Models when equipped.
-- We hook camera.ChildAdded to catch each weapon switch,
-- then clone the SurfaceAppearance from the Skins folder
-- onto each matching BasePart inside the viewmodel's
-- Weapon sub-model.  Gloves live in arm sub-models.
--
-- selectedSkins[weaponName] = skin name string
-- Toggling off clears all SkinApplied attributes so
-- the periodic re-check skips them.

-- ─── Skin changer state ───────────────────────────────

local SC = {
    enabled      = false,
    selectedSkins = {},   -- [weaponName] = skinName string
    wear         = "Factory New",
    cooldown     = 0.1,
}

-- Weapon category tables (mirror the real script exactly)
local SC_KNIVES = {
    "Karambit","Butterfly Knife","M9 Bayonet","Flip Knife","Gut Knife","T Knife","CT Knife"
}
local SC_GLOVES = {"Sports Gloves"}
local SC_CT     = {"USP-S","Five-SeveN","MP9","FAMAS","M4A1-S","M4A4","AUG"}
local SC_SHARED = {
    "P250","Desert Eagle","Dual Berettas","Negev","P90",
    "Nova","XM1014","AWP","SSG 08","AK-47","MP5-SD","MAC-10","UMP-45","SG 553"
}
local SC_IGNORE = {
    ["HE Grenade"]=true,["Incendiary Grenade"]=true,["Molotov"]=true,
    ["Smoke Grenade"]=true,["Flashbang"]=true,["Decoy Grenade"]=true,
    ["C4"]=true,["CT Glove"]=true,["T Glove"]=true,
}

-- Get the Skins folder safely (only exists in BloxStrike)
local RS_SC = game:GetService("ReplicatedStorage")
local SkinsFolder = nil
pcall(function()
    SkinsFolder = RS_SC:WaitForChild("Assets", 3):WaitForChild("Skins", 3)
end)

-- Characters folder (BloxStrike keeps players here)
local Characters_SC = WS:FindFirstChild("Characters")

local function sc_isAlive()
    if not Characters_SC then return false end
    local t  = Characters_SC:FindFirstChild("Terrorists")
    local ct = Characters_SC:FindFirstChild("Counter-Terrorists")
    return (t and t:FindFirstChild(lp.Name)) or (ct and ct:FindFirstChild(lp.Name))
end

-- Returns list of skin names for a weapon (reads from RS)
local function sc_getSkinList(weaponName)
    if not SkinsFolder then return {"Default"} end
    local folder = SkinsFolder:FindFirstChild(weaponName)
    if not folder then return {"Default"} end
    local names = {"Default"}
    for _, child in ipairs(folder:GetChildren()) do
        table.insert(names, child.Name)
    end
    return names
end

-- Core: apply a weapon's selected skin onto its camera model
local function sc_applyWeaponSkin(model)
    if not SC.enabled then return end
    if not sc_isAlive() then return end
    if not SkinsFolder then return end

    local skinName = SC.selectedSkins[model.Name]
    if not skinName or skinName == "Default" then return end

    pcall(function()
        local skinFolder = SkinsFolder:FindFirstChild(model.Name)
        if not skinFolder then return end

        local skinType   = skinFolder:FindFirstChild(skinName)
        local camFolder  = skinType and skinType:FindFirstChild("Camera")
        local sourceFolder = camFolder and camFolder:FindFirstChild(SC.wear)
        if not sourceFolder then return end

        -- Apply gloves onto arm sub-models in camera children
        local gloveSkinName = SC.selectedSkins["Sports Gloves"]
        if gloveSkinName and gloveSkinName ~= "Default" then
            for _, obj in ipairs(cam:GetChildren()) do
                local leftArm  = obj:FindFirstChild("Left Arm")
                local rightArm = obj:FindFirstChild("Right Arm")
                if leftArm or rightArm then
                    local gFolder = SkinsFolder:FindFirstChild("Sports Gloves")
                    local gSkin   = gFolder and gFolder:FindFirstChild(gloveSkinName)
                    local gSrc    = gSkin and gSkin:FindFirstChild("Camera") and gSkin.Camera:FindFirstChild(SC.wear)
                    if gSrc then
                        for _, side in ipairs({"Left Arm","Right Arm"}) do
                            local arm = obj:FindFirstChild(side)
                            local src = gSrc:FindFirstChild(side)
                            if arm and src then
                                local gloveMesh = arm:FindFirstChild("Glove")
                                if gloveMesh then
                                    local existing = gloveMesh:FindFirstChildOfClass("SurfaceAppearance")
                                    if existing then existing:Destroy() end
                                    local clone = src:Clone()
                                    clone.Name = "SurfaceAppearance"
                                    clone.Parent = gloveMesh
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Apply weapon skin to the Weapon sub-model's parts
        local weaponModel = model:FindFirstChild("Weapon")
        if weaponModel then
            for _, part in ipairs(weaponModel:GetDescendants()) do
                if part:IsA("BasePart") then
                    local newSkin = sourceFolder:FindFirstChild(part.Name)
                    if newSkin then
                        local existing = part:FindFirstChildOfClass("SurfaceAppearance")
                        if existing then existing:Destroy() end
                        local clone = newSkin:Clone()
                        clone.Name = "SurfaceAppearance"
                        clone.Parent = part
                    end
                end
            end
        end

        model:SetAttribute("SkinApplied", skinName)
    end)
end

-- Clear all applied skin attributes (used on toggle-off)
local function sc_clearSkins()
    for _, obj in ipairs(cam:GetChildren()) do
        pcall(function() obj:SetAttribute("SkinApplied", nil) end)
    end
end

-- Hook: apply skin whenever a new weapon enters camera
cam.ChildAdded:Connect(function(obj)
    if not SC.enabled or not sc_isAlive() then return end
    task.wait(SC.cooldown)
    sc_applyWeaponSkin(obj)
end)

-- Periodic re-check (handles respawn, weapon swap desync)
task.spawn(function()
    while true do
        task.wait(0.5)
        if SC.enabled and sc_isAlive() then
            for _, obj in ipairs(cam:GetChildren()) do
                local sel = SC.selectedSkins[obj.Name]
                if sel and obj:GetAttribute("SkinApplied") ~= sel then
                    sc_applyWeaponSkin(obj)
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════
-- ─── COUNTER BLOX SKIN CHANGER ────────────────────────
-- ═══════════════════════════════════════════════════════
-- CB stores skins differently from BloxStrike:
--   • LocalPlayer.SkinFolder.TFolder / CTFolder contain
--     StringValues named after each weapon.  Setting
--     .Value = "SkinName" changes the skin server-side.
--   • The game sends its inventory via a FireServer call
--     where the first arg is a table of {skinId} entries.
--     We hook __namecall to append ALL skins to that table
--     so the server believes you own everything.
--   • Client.CurrentInventory is also overwritten so the
--     in-game picker UI shows all skins.
--
-- This only runs when IS_COUNTERBLOX is true.

-- Full skin list from the real CB skin changer script
local CB_ALL_SKINS = {
    {'AK47_Ace'},{'AK47_Toxic Nitro'},{'AK47_Bloodboom'},{'AK47_Clown'},
    {'AK47_Code Orange'},{'AK47_Eve'},{'AK47_Gifted'},{'AK47_Glo'},
    {'AK47_Godess'},{'AK47_Hallows'},{'AK47_Halo'},{'AK47_Hypersonic'},
    {'AK47_Inversion'},{'AK47_Jester'},{'AK47_Maker'},{'AK47_Mean Green'},
    {'AK47_Outlaws'},{'AK47_Outrunner'},{'AK47_Patch'},{'AK47_Plated'},
    {'AK47_Precision'},{'AK47_Quantum'},{'AK47_Quicktime'},{'AK47_Scapter'},
    {'AK47_Secret Santa'},{'AK47_Shooting Star'},{'AK47_Skin Committee'},
    {'AK47_Survivor'},{'AK47_Ugly Sweater'},{'AK47_VAV'},{'AK47_Variant Camo'},
    {'AK47_Yltude'},{'AK47_Scythe'},
    {'AUG_Chilly Night'},{'AUG_Mystique'},{'AUG_Dream Hound'},{'AUG_Enlisted'},
    {'AUG_Graffiti'},{'AUG_Homestead'},{'AUG_Maker'},{'AUG_NightHawk'},
    {'AUG_Phoenix'},{'AUG_Sunsthetic'},
    {'AWP_Abaddon'},{'AWP_Autumness'},{'AWP_Blastech'},{'AWP_Bloodborne'},
    {'AWP_Coffin Biter'},{'AWP_Desert Camo'},{'AWP_Difference'},{'AWP_Dragon'},
    {'AWP_Forever'},{'AWP_Grepkin'},{'AWP_Hika'},{'AWP_Illusion'},
    {'AWP_Instinct'},{'AWP_JTF2'},{'AWP_Lunar'},{'AWP_Nerf'},
    {'AWP_Northern Lights'},{'AWP_Pear Tree'},{'AWP_Pink Vision'},
    {'AWP_Toxic Nitro'},{'AWP_Pinkie'},{'AWP_Quicktime'},{'AWP_Racer'},
    {'AWP_Regina'},{'AWP_Retroactive'},{'AWP_Scapter'},{'AWP_Silence'},
    {'AWP_Venomus'},{'AWP_Weeb'},{'AWP_Darkness'},
    {'Bayonet_Decor'},{'Bayonet_Aequalis'},{'Bayonet_Banner'},{'Bayonet_Candy Cane'},
    {'Bayonet_Consumed'},{'Bayonet_Cosmos'},{'Bayonet_Crimson Tiger'},
    {'Bayonet_Crow'},{'Bayonet_Delinquent'},{'Bayonet_Digital'},
    {'Bayonet_Easy-Bake'},{'Bayonet_Egg Shell'},{'Bayonet_Festive'},
    {'Bayonet_Frozen Dream'},{'Bayonet_Geo Blade'},{'Bayonet_Ghastly'},
    {'Bayonet_Goo'},{'Bayonet_Hallows'},{'Bayonet_Intertwine'},
    {'Bayonet_Marbleized'},{'Bayonet_Mariposa'},{'Bayonet_Naval'},
    {'Bayonet_Neonic'},{'Bayonet_RSL'},{'Bayonet_Racer'},{'Bayonet_Sapphire'},
    {'Bayonet_Silent Night'},{'Bayonet_Splattered'},{'Bayonet_Stock'},
    {'Bayonet_Topaz'},{'Bayonet_Tropical'},{'Bayonet_Twitch'},
    {'Bayonet_UFO'},{'Bayonet_Wetland'},{'Bayonet_Worn'},{'Bayonet_Wrapped'},
    {'Butterfly Knife_Snowfall'},{'Butterfly Knife_Aurora'},
    {'Butterfly Knife_Bloodwidow'},{'Butterfly Knife_Consumed'},
    {'Butterfly Knife_Cosmos'},{'Butterfly Knife_Crimson Tiger'},
    {'Butterfly Knife_Crippled Fade'},{'Butterfly Knife_Digital'},
    {'Butterfly Knife_Egg Shell'},{'Butterfly Knife_Freedom'},
    {'Butterfly Knife_Frozen Dream'},{'Butterfly Knife_Goo'},
    {'Butterfly Knife_Hallows'},{'Butterfly Knife_Icicle'},
    {'Butterfly Knife_Inversion'},{'Butterfly Knife_Jade Dream'},
    {'Butterfly Knife_Marbleized'},{'Butterfly Knife_Naval'},
    {'Butterfly Knife_Neonic'},{'Butterfly Knife_Reaper'},
    {'Butterfly Knife_Ruby'},{'Butterfly Knife_Scapter'},
    {'Butterfly Knife_Splattered'},{'Butterfly Knife_Stock'},
    {'Butterfly Knife_Topaz'},{'Butterfly Knife_Tropical'},
    {'Butterfly Knife_Twitch'},{'Butterfly Knife_Wetland'},
    {'Butterfly Knife_White Boss'},{'Butterfly Knife_Worn'},
    {'Butterfly Knife_Wrapped'},{'Butterfly Knife_Argus'},
    {'CZ_Designed'},{'CZ_Festive'},{'CZ_Holidays'},{'CZ_Lightning'},
    {'CZ_Orange Web'},{'CZ_Spectre'},
    {'DesertEagle_Cold Truth'},{'DesertEagle_TC'},{'DesertEagle_Cool Blue'},
    {'DesertEagle_DropX'},{'DesertEagle_Glittery'},{'DesertEagle_Grim'},
    {'DesertEagle_Heat'},{'DesertEagle_Honor-bound'},{'DesertEagle_Independence'},
    {'DesertEagle_Krystallos'},{'DesertEagle_Pumpkin Buster'},{'DesertEagle_ROLVe'},
    {'DesertEagle_Racer'},{'DesertEagle_Scapter'},{'DesertEagle_Skin Committee'},
    {'DesertEagle_Survivor'},{'DesertEagle_Weeb'},{'DesertEagle_Xmas'},
    {'DesertEagle_Cringe'},
    {'DualBerettas_Carbonized'},{'DualBerettas_Dusty Manor'},{'DualBerettas_Floral'},
    {'DualBerettas_Hexline'},{'DualBerettas_Neon web'},{'DualBerettas_Old Fashioned'},
    {'DualBerettas_Xmas'},
    {'Falchion Knife_Bloodwidow'},{'Falchion Knife_Chosen'},{'Falchion Knife_Coal'},
    {'Falchion Knife_Consumed'},{'Falchion Knife_Cosmos'},{'Falchion Knife_Crimson Tiger'},
    {'Falchion Knife_Crippled Fade'},{'Falchion Knife_Digital'},
    {'Falchion Knife_Egg Shell'},{'Falchion Knife_Festive'},{'Falchion Knife_Freedom'},
    {'Falchion Knife_Frozen Dream'},{'Falchion Knife_Goo'},{'Falchion Knife_Hallows'},
    {'Falchion Knife_Inversion'},{'Falchion Knife_Late Night'},
    {'Falchion Knife_Toxic Nitro'},{'Falchion Knife_Marbleized'},
    {'Falchion Knife_Naval'},{'Falchion Knife_Neonic'},{'Falchion Knife_Racer'},
    {'Falchion Knife_Ruby'},{'Falchion Knife_Splattered'},{'Falchion Knife_Stock'},
    {'Falchion Knife_Topaz'},{'Falchion Knife_Tropical'},{'Falchion Knife_Wetland'},
    {'Falchion Knife_Worn'},{'Falchion Knife_Wrapped'},{'Falchion Knife_Zombie'},
    {'Falchion Knife_Pumpkin'},
    {'Famas_Abstract'},{'Famas_Centipede'},{'Famas_Cogged'},{'Famas_Goliath'},
    {'Famas_Haunted Forest'},{'Famas_KugaX'},{'Famas_MK11'},{'Famas_Medic'},
    {'Famas_Redux'},{'Famas_Shocker'},{'Famas_Toxic Rain'},
    {'FiveSeven_Autumn Fade'},{'FiveSeven_Danjo'},{'FiveSeven_Fluid'},
    {'FiveSeven_Gifted'},{'FiveSeven_Midnight Ride'},{'FiveSeven_Mr. Anatomy'},
    {'FiveSeven_Stigma'},{'FiveSeven_Sub Zero'},{'FiveSeven_Summer'},
    {'Flip Knife_Stock'},
    {'Galil_Frosted'},{'Galil_Hardware'},{'Galil_Hardware 2'},{'Galil_Toxicity'},{'Galil_Worn'},
    {'Glock_Angler'},{'Glock_Anubis'},{'Glock_Biotrip'},{'Glock_Day Dreamer'},
    {'Glock_Desert Camo'},{'Glock_Gravestomper'},{'Glock_Midnight Tiger'},
    {'Glock_Money Maker'},{'Glock_RSL'},{'Glock_Rush'},{'Glock_Scapter'},
    {'Glock_Spacedust'},{'Glock_Tarnish'},{'Glock_Underwater'},
    {'Glock_Wetland'},{'Glock_White Sauce'},
    {'Gut Knife_Holly'},{'Gut Knife_Banner'},{'Gut Knife_Bloodwidow'},
    {'Gut Knife_Consumed'},{'Gut Knife_Cosmos'},{'Gut Knife_Crimson Tiger'},
    {'Gut Knife_Crippled Fade'},{'Gut Knife_Digital'},{'Gut Knife_Egg Shell'},
    {'Gut Knife_Frozen Dream'},{'Gut Knife_Geo Blade'},{'Gut Knife_Goo'},
    {'Gut Knife_Hallows'},{'Gut Knife_Lurker'},{'Gut Knife_Marbleized'},
    {'Gut Knife_Naval'},{'Gut Knife_Neonic'},{'Gut Knife_Present'},
    {'Gut Knife_Ruby'},{'Gut Knife_Rusty'},{'Gut Knife_Splattered'},
    {'Gut Knife_Topaz'},{'Gut Knife_Tropical'},{'Gut Knife_Wetland'},
    {'Gut Knife_Worn'},{'Gut Knife_Wrapped'},
    {'Huntsman Knife_Spirit'},{'Huntsman Knife_Aurora'},{'Huntsman Knife_Drop-Out'},
    {'Huntsman Knife_Bloodwidow'},{'Huntsman Knife_Consumed'},{'Huntsman Knife_Cosmos'},
    {'Huntsman Knife_Cozy'},{'Huntsman Knife_Crimson Tiger'},
    {'Huntsman Knife_Crippled Fade'},{'Huntsman Knife_Digital'},
    {'Huntsman Knife_Egg Shell'},{'Huntsman Knife_Frozen Dream'},
    {'Huntsman Knife_Geo Blade'},{'Huntsman Knife_Goo'},{'Huntsman Knife_Hallows'},
    {'Huntsman Knife_Honor Fade'},{'Huntsman Knife_Marbleized'},
    {'Huntsman Knife_Monster'},{'Huntsman Knife_Naval'},{'Huntsman Knife_Ruby'},
    {'Huntsman Knife_Splattered'},{'Huntsman Knife_Stock'},{'Huntsman Knife_Tropical'},
    {'Huntsman Knife_Twitch'},{'Huntsman Knife_Wetland'},{'Huntsman Knife_Worn'},
    {'Huntsman Knife_Wrapped'},
    {'Karambit_Peppermint'},{'Karambit_Bloodwidow'},{'Karambit_Consumed'},
    {'Karambit_Cosmos'},{'Karambit_Crimson Tiger'},{'Karambit_Crippled Fade'},
    {'Karambit_Death Wish'},{'Karambit_Digital'},{'Karambit_Egg Shell'},
    {'Karambit_Festive'},{'Karambit_Frozen Dream'},{'Karambit_Glossed'},
    {'Karambit_Gold'},{'Karambit_Goo'},{'Karambit_Hallows'},{'Karambit_Jade Dream'},
    {'Karambit_Jester'},{'Karambit_Lantern'},{'Karambit_Liberty Camo'},
    {'Karambit_Marbleized'},{'Karambit_Naval'},{'Karambit_Neonic'},
    {'Karambit_Pizza'},{'Karambit_Quicktime'},{'Karambit_Racer'},
    {'Karambit_Ruby'},{'Karambit_Scapter'},{'Karambit_Splattered'},
    {'Karambit_Stock'},{'Karambit_Topaz'},{'Karambit_Tropical'},
    {'Karambit_Twitch'},{'Karambit_Wetland'},{'Karambit_Worn'},{'Karambit_Drop-Out'},
    {'M4A1_Animatic'},{'M4A1_Burning'},{'M4A1_Desert Camo'},{'M4A1_Heavens Gate'},
    {'M4A1_Impulse'},{'M4A1_Jester'},{'M4A1_Lunar'},{'M4A1_Necropolis'},
    {'M4A1_Tecnician'},{'M4A1_Toucan'},{'M4A1_Wastelander'},
    {'M4A4_BOT[S]'},{'M4A4_Candyskull'},{'M4A4_Delinquent'},{'M4A4_Desert Camo'},
    {'M4A4_Devil'},{'M4A4_Endline'},{'M4A4_Flashy Ride'},{'M4A4_Ice Cap'},
    {'M4A4_Jester'},{'M4A4_King'},{'M4A4_Mistletoe'},{'M4A4_Pinkie'},
    {'M4A4_Pinkvision'},{'M4A4_Pondside'},{'M4A4_Precision'},{'M4A4_Quicktime'},
    {'M4A4_Racer'},{'M4A4_RayTrack'},{'M4A4_Scapter'},{'M4A4_Stardust'},
    {'M4A4_Toy Soldier'},
    {'MAC10_Artists Intent'},{'MAC10_Blaze'},{'MAC10_Golden Rings'},{'MAC10_Pimpin'},
    {'MAC10_Skeleboney'},{'MAC10_Toxic'},{'MAC10_Turbo'},{'MAC10_Wetland'},
    {'MP9_Blueroyal'},{'MP9_Cob Web'},{'MP9_Cookie Man'},{'MP9_Decked Halls'},
    {'MP9_SnowTime'},{'MP9_Vaporwave'},{'MP9_Velvita'},{'MP9_Wilderness'},
    {'Negev_Default'},{'Negev_Midnightbones'},{'Negev_Quazar'},{'Negev_Striped'},
    {'Negev_Wetland'},{'Negev_Winterfell'},
    {'Nova_Black Ice'},{'Nova_Cookie'},{'Nova_Paradise'},{'Nova_Sharkesh'},
    {'Nova_Starry Night'},{'Nova_Terraformer'},{'Nova_Tiger'},
    {'P250_Amber'},{'P250_Bomber'},{'P250_Equinox'},{'P250_Frosted'},
    {'P250_Goldish'},{'P250_Green Web'},{'P250_Shark'},{'P250_Solstice'},{'P250_TC250'},
    {'P90_Demon Within'},{'P90_Elegant'},{'P90_Krampus'},{'P90_Northern Lights'},
    {'P90_P-Chan'},{'P90_Pine'},{'P90_Redcopy'},{'P90_Skulls'},
    {'SG_DropX'},{'SG_Dummy'},{'SG_Drop-Out'},{'SG_Kitty Cat'},{'SG_Knighthood'},
    {'SG_Magma'},{'SG_Variant Camo'},{'SG_Yltude'},
    {'UMP_Death Grip'},{'UMP_Gum Drop'},{'UMP_Magma'},{'UMP_Militia Camo'},
    {'UMP_Molten'},{'UMP_Redline'},
    {'USP_Crimson'},{'USP_Dizzy'},{'USP_Frostbite'},{'USP_Holiday'},
    {'USP_Jade Dream'},{'USP_Kraken'},{'USP_Nighttown'},{'USP_Paradise'},
    {'USP_Racing'},{'USP_Skull'},{'USP_Unseen'},{'USP_Worlds Away'},{'USP_Yellowbelly'},
    {'Handwraps_Wraps'},{'Handwraps_Guts'},{'Handwraps_Toxic Nitro'},
    {'Handwraps_Wetland'},{'Handwraps_MMA'},{'Handwraps_Ghoul Hex'},
    {'Handwraps_Mummy'},{'Handwraps_Phantom Hex'},{'Handwraps_Spector Hex'},
    {'Handwraps_Orange Hex'},{'Handwraps_Purple Hex'},{'Handwraps_Green Hex'},
    {'Sports Glove_Hazard'},{'Sports Glove_Skulls'},{'Sports Glove_Pumpkin'},
    {'Sports Glove_Hallows'},{'Sports Glove_Majesty'},{'Sports Glove_Royal'},
    {'Sports Glove_Weeb'},{'Sports Glove_CottonTail'},{'Sports Glove_RSL'},
    {'Strapped Glove_Racer'},{'Strapped Glove_Grim'},{'Strapped Glove_Drop-Out'},
    {'Strapped Glove_Wisk'},{'Strapped Glove_Molten'},{'Strapped Glove_Kringle'},
    {'Fingerless Glove_Scapter'},{'Fingerless Glove_Crystal'},
    {'Fingerless Glove_Digital'},{'Fingerless Glove_Patch'},
}

-- CB weapon folder name → list of skin names (parsed from CB_ALL_SKINS)
-- Key = prefix before the underscore in the skin id (e.g. "AK47", "USP")
local CB_SKINS_BY_WEAPON = {}
for _, entry in ipairs(CB_ALL_SKINS) do
    local id   = entry[1]
    local sep2 = id:find("_")
    if sep2 then
        local weapon = id:sub(1, sep2-1)
        local skin   = id:sub(sep2+1)
        if not CB_SKINS_BY_WEAPON[weapon] then
            CB_SKINS_BY_WEAPON[weapon] = {"Default"}
        end
        table.insert(CB_SKINS_BY_WEAPON[weapon], skin)
    end
end

-- Map from the UI label → CB prefix (e.g. "AK-47" → "AK47")
local CB_WEAPON_MAP = {
    ["AK-47"]         = "AK47",
    ["AWP"]           = "AWP",
    ["M4A4"]          = "M4A4",
    ["M4A1-S"]        = "M4A1",
    ["USP-S"]         = "USP",
    ["Glock-18"]      = "Glock",
    ["Desert Eagle"]  = "DesertEagle",
    ["P250"]          = "P250",
    ["AUG"]           = "AUG",
    ["FAMAS"]         = "Famas",
    ["MP9"]           = "MP9",
    ["MAC-10"]        = "MAC10",
    ["UMP-45"]        = "UMP",
    ["P90"]           = "P90",
    ["Negev"]         = "Negev",
    ["Nova"]          = "Nova",
    ["SG 553"]        = "SG",
    ["Dual Berettas"] = "DualBerettas",
    ["Five-SeveN"]    = "FiveSeven",
    ["CZ75-Auto"]     = "CZ",
    ["Galil AR"]      = "Galil",
    -- Knives
    ["Karambit"]       = "Karambit",
    ["Butterfly Knife"]= "Butterfly Knife",
    ["Gut Knife"]      = "Gut Knife",
    ["Bayonet"]        = "Bayonet",
    ["Falchion Knife"] = "Falchion Knife",
    ["Flip Knife"]     = "Flip Knife",
    ["Huntsman Knife"] = "Huntsman Knife",
    -- Gloves
    ["Sports Gloves"]    = "Sports Glove",
    ["Hand Wraps"]       = "Handwraps",
    ["Strapped Gloves"]  = "Strapped Glove",
    ["Fingerless Gloves"]= "Fingerless Glove",
}

-- CB state
local CB_SC = {
    enabled   = false,
    hooked    = false,
    unlocked  = false,
    selected  = {},  -- [weaponLabel] = skinName string
    -- side: "Both", "TFolder", "CTFolder"
    side      = "Both",
}

-- Get skin list for a UI weapon label
local function cb_getSkins(weaponLabel)
    local prefix = CB_WEAPON_MAP[weaponLabel]
    if not prefix then return {"Default"} end
    local list = CB_SKINS_BY_WEAPON[prefix]
    if not list or #list <= 1 then return {"Default"} end
    return list
end

-- Apply a skin by writing to SkinFolder StringValues
-- weaponLabel = display name, skinName = the part after the underscore
local function cb_applySkin(weaponLabel, skinName)
    if not IS_COUNTERBLOX then return end
    if not skinName or skinName == "Default" then return end
    local prefix = CB_WEAPON_MAP[weaponLabel]
    if not prefix then return end

    -- The StringValue name inside TFolder/CTFolder matches the CB prefix
    pcall(function()
        local sf = lp:FindFirstChild("SkinFolder")
        if not sf then return end
        local side = CB_SC.side
        for _, folder in ipairs({"TFolder","CTFolder"}) do
            if side == "Both" or side == folder then
                local f = sf:FindFirstChild(folder)
                if f then
                    local sv = f:FindFirstChild(prefix)
                    if sv then sv.Value = skinName end
                end
            end
        end
    end)
end

-- CB knife type names (exact names used in allSkins prefixes)
local CB_KNIFE_TYPES = {
    "Default",
    "Karambit",
    "Butterfly Knife",
    "Gut Knife",
    "Bayonet",
    "Falchion Knife",
    "Flip Knife",
    "Huntsman Knife",
}

-- Spy state: we capture the first real knife DataEvent the game fires
-- (when the player equips their knife normally) and store its exact
-- structure so we can replay it with a different knife type.
local CB_knifeSpy = {
    captured  = false,
    remote    = nil,   -- the actual DataEvent RemoteEvent instance
    template  = nil,   -- deep-copy of args[1] table from the real call
    weaponKey = nil,   -- args[1][3] — the SkinFolder StringValue key name
    side      = nil,   -- args[1][2] — "Both"/"TFolder"/"CTFolder"
}
local CB_forcedKnifeType = nil

-- Replay a knife equip with a specific type+skin combo
local function cb_fireKnifeEquip(knifeType, skinName)
    if not CB_knifeSpy.captured then return false end
    skinName = skinName or "Stock"
    local payload     = {}
    for i, v in ipairs(CB_knifeSpy.template) do payload[i] = v end
    -- Slot 4 is the skin id table — replace just the first entry
    payload[4]    = {knifeType .. "_" .. skinName}
    payload[2]    = "Both"
    payload[3]    = CB_knifeSpy.weaponKey
    pcall(function()
        CB_knifeSpy.remote:FireServer(payload)
    end)
    return true
end

local function cb_setKnifeType(knifeType)
    if not IS_COUNTERBLOX then return end
    CB_forcedKnifeType = (knifeType ~= "Default") and knifeType or nil
    if CB_forcedKnifeType then
        cb_fireKnifeEquip(CB_forcedKnifeType, "Stock")
    end
end

-- Hook __namecall to unlock all skins + intercept DataEvent skin-apply calls
local function cb_hook()
    if CB_SC.hooked then return end
    CB_SC.hooked = true

    pcall(function()
        -- Inject Client.CurrentInventory so the picker UI shows all skins
        local Client = getsenv(lp.PlayerGui:WaitForChild("Client", 5))
        if Client then
            Client.CurrentInventory = CB_ALL_SKINS
        end
    end)

    local mt2       = getrawmetatable(game)
    local oldNC     = mt2.__namecall
    setreadonly(mt2, false)

    mt2.__namecall = newcclosure(function(self, ...)
        local args = {...}
        local method = getnamecallmethod()

        if method == "InvokeServer" and tostring(self) == "Hugh" then
            return  -- block anti-cheat ping
        end

        if method == "FireServer" then
            -- Block reporting your own UserId
            if args[1] == lp.UserId then return end

            -- Inventory unlock: the inventory event has a 38-char remote name
            -- and sends a table of skin entries as args[1]
            if string.len(tostring(self)) == 38 then
                if not CB_SC.unlocked then
                    CB_SC.unlocked = true
                    for _, v in ipairs(CB_ALL_SKINS) do
                        local already = false
                        for _, v2 in ipairs(args[1]) do
                            if v[1] == v2[1] then already = true; break end
                        end
                        if not already then table.insert(args[1], v) end
                    end
                end
                return
            end

            -- Skin-apply / knife-equip event via DataEvent remote
            if tostring(self) == "DataEvent" and type(args[1]) == "table" and args[1][4] then
                local fullId    = args[1][4][1]   -- e.g. "Karambit_Ruby" or "T Knife_Stock"
                local weaponKey = args[1][3]       -- SkinFolder StringValue name
                local side2     = args[1][2]

                -- Spy: capture the first knife DataEvent so we can replay it
                local knifeTypes = {"Karambit","Butterfly Knife","Gut Knife",
                    "Bayonet","Falchion Knife","Flip Knife","Huntsman Knife",
                    "T Knife","CT Knife"}
                local isKnifeCall = false
                for _, kt in ipairs(knifeTypes) do
                    if fullId:sub(1, #kt) == kt then
                        isKnifeCall = true; break
                    end
                end
                if isKnifeCall and not CB_knifeSpy.captured then
                    CB_knifeSpy.captured  = true
                    CB_knifeSpy.remote    = self
                    CB_knifeSpy.weaponKey = weaponKey
                    CB_knifeSpy.side      = side2
                    -- Deep copy the template (replace slot 4 later per-call)
                    CB_knifeSpy.template = {}
                    for i, v in ipairs(args[1]) do
                        CB_knifeSpy.template[i] = v
                    end
                end

                -- If we're forcing a knife type, rewrite this call
                if CB_forcedKnifeType and isKnifeCall then
                    local skinPart = fullId:match("_(.+)$") or "Stock"
                    args[1][4][1] = CB_forcedKnifeType .. "_" .. skinPart
                    fullId = args[1][4][1]
                end

                local currentSkin = fullId:match("_(.+)$") or fullId
                pcall(function()
                    local sf = lp:FindFirstChild("SkinFolder")
                    if not sf then return end
                    if side2 == "Both" then
                        local tf  = sf:FindFirstChild("TFolder")
                        local ctf = sf:FindFirstChild("CTFolder")
                        if tf  and tf:FindFirstChild(weaponKey)  then tf:FindFirstChild(weaponKey).Value  = currentSkin end
                        if ctf and ctf:FindFirstChild(weaponKey) then ctf:FindFirstChild(weaponKey).Value = currentSkin end
                    else
                        local f = sf:FindFirstChild(side2 .. "Folder")
                        if f and f:FindFirstChild(weaponKey) then f:FindFirstChild(weaponKey).Value = currentSkin end
                    end
                end)
            end
        end

        return oldNC(self, ...)
    end)

    setreadonly(mt2, true)

    -- Clone SkinFolder fix (mirrors original script)
    pcall(function()
        local sf    = lp:WaitForChild("SkinFolder", 5)
        if not sf then return end
        local tClone  = sf.TFolder:Clone()
        local ctClone = sf.CTFolder:Clone()
        sf.TFolder:Destroy()
        sf.CTFolder:Destroy()
        tClone.Parent  = sf
        ctClone.Parent = sf
    end)
end

-- ─── Custom Knife system (from real source) ───────────
local ck = {
    running       = false,
    selected      = "Butterfly Knife",
    spawned       = false,
    inspecting    = false,
    swinging      = false,
    lastAttack    = 0,
    vm            = nil,
    animator      = nil,
    equipAnim     = nil,
    idleAnim      = nil,
    inspectAnim   = nil,
    heavyAnim     = nil,
    swing1Anim    = nil,
    swing2Anim    = nil,
}
local CK_COOLDOWN   = 1
local CK_INSPECT    = "NW_InspectKnife"
local CK_ATTACK     = "NW_AttackKnife"
local CAS           = game:GetService("ContextActionService")

local ckKnives = {
    ["Karambit"]        = {Offset = CFrame.new(0,-1.5,1.5)},
    ["Butterfly Knife"] = {Offset = CFrame.new(0,-1.5,1.5)},
    ["M9 Bayonet"]      = {Offset = CFrame.new(0,-1.5,1)},
    ["Flip Knife"]      = {Offset = CFrame.new(0,-1.5,1.25)},
    ["Gut Knife"]       = {Offset = CFrame.new(0,-1.5,0.5)},
}
local ckOptions = {"Butterfly Knife","Karambit","M9 Bayonet","Flip Knife","Gut Knife"}

local RS_CK = game:GetService("ReplicatedStorage")

local function ck_isAlive()
    if not Characters_SC then return end
    local t  = Characters_SC:FindFirstChild("Terrorists")
    local ct = Characters_SC:FindFirstChild("Counter-Terrorists")
    return (t and t:FindFirstChild(lp.Name)) or (ct and ct:FindFirstChild(lp.Name))
end
local function ck_getKnifeInCam()
    return cam:FindFirstChild("T Knife") or cam:FindFirstChild("CT Knife")
end
local function ck_cleanPart(part)
    if not part:IsA("BasePart") then return end
    part.CanCollide=false; part.Anchored=false
    part.CastShadow=false; part.CanTouch=false; part.CanQuery=false
end
local function ck_disableCollisions(model)
    for _,p in ipairs(model:GetDescendants()) do ck_cleanPart(p) end
end
local function ck_hideOriginal(knife)
    for _,p in ipairs(knife:GetDescendants()) do
        if p:IsA("BasePart") or p:IsA("MeshPart") then p.Transparency=1 end
        if p:IsA("Texture") then p.Transparency=1 end
    end
end
local function ck_playSound(folder, name)
    local sounds = RS_CK.Sounds:FindFirstChild(ck.selected)
    if not sounds then return end
    local s = sounds:WaitForChild(folder):WaitForChild(name):Clone()
    s.Parent=cam; s:Play()
    s.Ended:Once(function() s:Destroy() end)
    return s
end
local function ck_attachAsset(folder, armName, assetName, finalName, offset)
    local arm = ck.vm:FindFirstChild(armName)
    if not arm then return end
    local mesh = folder:WaitForChild(assetName):Clone()
    ck_cleanPart(mesh); mesh.Name=finalName; mesh.Parent=arm
    local m = Instance.new("Motor6D")
    m.Part0=arm; m.Part1=mesh; m.C0=offset; m.Parent=arm
end

local function ck_remove()
    ck.spawned=false
    CAS:UnbindAction(CK_INSPECT)
    CAS:UnbindAction(CK_ATTACK)
    if ck.vm then ck.vm:Destroy(); ck.vm=nil end
    ck.animator=nil; ck.inspecting=false; ck.swinging=false
end

local function ck_handleAction(actionName, inputState)
    if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
    if not ck.spawned or not ck.animator or not ck_isAlive() then return Enum.ContextActionResult.Pass end
    if actionName == CK_INSPECT then
        if (ck.equipAnim and ck.equipAnim.IsPlaying) or ck.inspecting or ck.swinging then return Enum.ContextActionResult.Pass end
        ck.inspecting=true
        if ck.idleAnim then ck.idleAnim:Stop() end
        ck.inspectAnim:Play()
        ck.inspectAnim.Stopped:Once(function() ck.inspecting=false end)
    elseif actionName == CK_ATTACK then
        local now = os.clock()
        if (ck.equipAnim and ck.equipAnim.IsPlaying) or (now-ck.lastAttack < CK_COOLDOWN) then return Enum.ContextActionResult.Pass end
        ck.lastAttack = now
        if ck.inspecting then ck.inspecting=false; if ck.inspectAnim then ck.inspectAnim:Stop() end end
        ck.swinging=true
        if ck.idleAnim then ck.idleAnim:Stop() end
        local anims = {ck.heavyAnim, ck.swing1Anim, ck.swing2Anim}
        local chosen = anims[math.random(1,#anims)]
        local sfx = (chosen==ck.heavyAnim and "HitOne") or (chosen==ck.swing1Anim and "HitTwo") or "HitThree"
        chosen:Play()
        local s=ck_playSound(sfx,"1"); if s then s.Volume=5 end
        chosen.Stopped:Once(function() ck.swinging=false end)
    end
    return Enum.ContextActionResult.Pass
end

local function ck_spawn(knife)
    if ck.spawned or not ck.running then return end
    local myModel = ck_isAlive(); if not myModel then return end
    ck.spawned=true
    local tmpl   = RS_CK.Assets.Weapons:WaitForChild(ck.selected)
    local offset = ckKnives[ck.selected].Offset
    ck.vm        = tmpl:WaitForChild("Camera"):Clone()
    ck.vm.Name   = ck.selected; ck.vm.Parent=cam
    ck_disableCollisions(ck.vm); ck_hideOriginal(knife)
    if myModel.Parent.Name=="Terrorists" then
        local tG=RS_CK.Assets.Weapons:WaitForChild("T Glove")
        ck_attachAsset(tG,"Left Arm","Left Arm","Glove",CFrame.new(0,0,-1.5))
        ck_attachAsset(tG,"Right Arm","Right Arm","Glove",CFrame.new(0,0,-1.5))
    else
        local sl=RS_CK.Assets.Sleeves:WaitForChild("IDF")
        local cG=RS_CK.Assets.Weapons:WaitForChild("CT Glove")
        ck_attachAsset(sl,"Left Arm","Left Arm","Sleeve",CFrame.new(0,0,0.5))
        ck_attachAsset(cG,"Left Arm","Left Arm","Glove",CFrame.new(0,0,-1.5))
        ck_attachAsset(sl,"Right Arm","Right Arm","Sleeve",CFrame.new(0,0,0.5))
        ck_attachAsset(cG,"Right Arm","Right Arm","Glove",CFrame.new(0,0,-1.5))
    end
    local animCtrl = ck.vm:FindFirstChildOfClass("AnimationController") or ck.vm:FindFirstChildOfClass("Animator")
    ck.animator    = animCtrl:FindFirstChildWhichIsA("Animator") or animCtrl
    local animF    = RS_CK.Assets.WeaponAnimations:WaitForChild(ck.selected):WaitForChild("CameraAnimations")
    ck.equipAnim   = ck.animator:LoadAnimation(animF:WaitForChild("Equip"))
    ck.idleAnim    = ck.animator:LoadAnimation(animF:WaitForChild("Idle"))
    ck.inspectAnim = ck.animator:LoadAnimation(animF:WaitForChild("Inspect"))
    ck.heavyAnim   = ck.animator:LoadAnimation(animF:WaitForChild("Heavy Swing"))
    ck.swing1Anim  = ck.animator:LoadAnimation(animF:WaitForChild("Swing1"))
    ck.swing2Anim  = ck.animator:LoadAnimation(animF:WaitForChild("Swing2"))
    ck.vm:SetPrimaryPartCFrame(cam.CFrame * CFrame.new(0,-1.5,5))
    TweenSvc:Create(ck.vm.PrimaryPart, TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
        {CFrame=cam.CFrame*offset}):Play()
    ck.equipAnim:Play(); ck_playSound("Equip","1")
    CAS:BindAction(CK_INSPECT, ck_handleAction, false, Enum.KeyCode.F)
    CAS:BindAction(CK_ATTACK,  ck_handleAction, false, Enum.UserInputType.MouseButton1)
end

RunSvc.RenderStepped:Connect(function()
    if not ck.running or not ck.vm or not ck.vm.PrimaryPart then return end
    ck.vm.PrimaryPart.CFrame = cam.CFrame * ckKnives[ck.selected].Offset
    if not (ck.equipAnim and ck.equipAnim.IsPlaying) and not ck.inspecting and not ck.swinging then
        if ck.idleAnim and not ck.idleAnim.IsPlaying then ck.idleAnim:Play() end
    end
end)

task.spawn(function()
    while true do
        local alive   = ck_isAlive()
        local camKnife = ck_getKnifeInCam()
        if ck.running and alive and camKnife and not ck.spawned then
            ck_spawn(camKnife)
        elseif (not ck.running or not camKnife or not alive) and ck.spawned then
            ck_remove()
        end
        task.wait(0.1)
    end
end)

-- Silence Karambit basePart on script init (mirrors real script)
pcall(function()
    RS_CK.Assets.Weapons.Karambit.Camera.ViewmodelLight.Transparency = 1
end)

-- ═══════════════════════════════════════════════════════
-- ─── BUILD NAV + PAGES ────────────────────────────────
-- ═══════════════════════════════════════════════════════
catLabel("AIMBOT")
navItem("Aimbot",  "aimbot")
navItem("Ragebot", "ragebot")
catLabel("VISUALS")
navItem("ESP",     "esp")
navItem("HUD",     "hud")
catLabel("CONFIG")
navItem("Anti-Aim","antiaim")
navItem("Skins",   "skins")
navItem("Misc",    "misc")

-- ─── Aimbot page ──────────────────────────────────────
do local L, R = addPage("aimbot")
    secHdr(L, "Main")
    togRow(L,"Enable Aimbot",     cfg.aim_on,       function(v) cfg.aim_on=v end)
    togRow(L,"Visibility Check",  cfg.aim_vischeck,  function(v) cfg.aim_vischeck=v end)
    togRow(L,"Team Check",        cfg.aim_teamcheck, function(v) cfg.aim_teamcheck=v end)
    togRow(L,"Predict Movement",  cfg.aim_predict,   function(v) cfg.aim_predict=v end)
    ddRow(L, "Target Bone",       BONES, cfg.aim_bone, function(v) cfg.aim_bone=v end)
    secHdr(L, "Silent Aim")
    togRow(L,"Enable Silent Aim", cfg.silent_on,  function(v) cfg.silent_on=v end)
    togRow(L,"Silent FOV Ring",   cfg.silent_ring, function(v) cfg.silent_ring=v end)
    secHdr(R, "Aim Settings")
    sldRow(R,"FOV",          10,  400, cfg.aim_fov,      function(v) cfg.aim_fov=v end)
    sldRow(R,"Smooth",        1,   20, cfg.aim_smooth,   function(v) cfg.aim_smooth=v end)
    secHdr(R, "Timing")
    sldRow(R,"Lead Time ms",  0,  400, cfg.aim_lead_ms,  function(v) cfg.aim_lead_ms=v end)
    secHdr(R, "Silent")
    sldRow(R,"Silent FOV",   10,  500, cfg.silent_fov,   function(v) cfg.silent_fov=v end)
end

-- ─── Ragebot page ─────────────────────────────────────
do local L, R = addPage("ragebot")
    secHdr(L, "Auto-Fire")
    togRow(L,"Enable Ragebot",  cfg.rage_on,      function(v) cfg.rage_on=v end)
    togRow(L,"Doubletap",       cfg.rage_dt,      function(v) cfg.rage_dt=v end)
    togRow(L,"Hideshots",       cfg.rage_hs,      function(v) cfg.rage_hs=v end)
    togRow(L,"Body Aim Low HP", cfg.rage_baim,    function(v) cfg.rage_baim=v end)
    togRow(L,"Auto-Strafe",     cfg.rage_strafe,  function(v) cfg.rage_strafe=v end)
    togRow(L,"Auto-Peek",       cfg.rage_autopeak,function(v) cfg.rage_autopeak=v end)
    secHdr(L, "Backtrack")
    togRow(L,"Enable Backtrack",cfg.bt_on,        function(v) cfg.bt_on=v end)
    sldRow(L,"Ticks",            1, 20, cfg.bt_ticks, function(v) cfg.bt_ticks=v end)
    secHdr(R, "Tuning")
    sldRow(R,"Hitchance %",      1, 100, cfg.rage_hc,     function(v) cfg.rage_hc=v end)
    sldRow(R,"Min Damage",       1, 125, cfg.rage_mindmg, function(v) cfg.rage_mindmg=v end)
    secHdr(R, "Triggerbot")
    togRow(R,"Enable Triggerbot",cfg.trig_on,    function(v) cfg.trig_on=v end)
    sldRow(R,"Delay ms",         0, 500, cfg.trig_delay, function(v) cfg.trig_delay=v end)
end

-- ─── ESP page ─────────────────────────────────────────
do local L, R = addPage("esp")
    secHdr(L, "ESP")
    togRow(L,"Enable ESP",    cfg.esp_on,       function(v) cfg.esp_on=v end)
    togRow(L,"Boxes",         cfg.esp_boxes,    function(v) cfg.esp_boxes=v end)
    togRow(L,"Names",         cfg.esp_names,    function(v) cfg.esp_names=v end)
    togRow(L,"Health Bars",   cfg.esp_health,   function(v) cfg.esp_health=v end)
    togRow(L,"Distance",      cfg.esp_dist,     function(v) cfg.esp_dist=v end)
    togRow(L,"Snap Lines",    cfg.esp_snaplines,function(v) cfg.esp_snaplines=v end)
    togRow(L,"Skeleton",      cfg.esp_skeleton, function(v) cfg.esp_skeleton=v end)
    togRow(L,"Arrows",        cfg.esp_arrows,   function(v) cfg.esp_arrows=v end)
    togRow(L,"Hit Log",       cfg.esp_hitlog,   function(v) cfg.esp_hitlog=v end)
    secHdr(R, "Resolver")
    togRow(R,"Enable Resolver",  cfg.res_on,        function(v) cfg.res_on=v end)
    ddRow(R, "Mode",             RES_MODES, cfg.res_mode, function(v) cfg.res_mode=v end)
    togRow(R,"Confidence Bar",   cfg.res_confidence,function(v) cfg.res_confidence=v end)
    secHdr(R, "Range")
    sldRow(R,"Max Distance",  50, 2000, cfg.esp_maxdist, function(v) cfg.esp_maxdist=v end)
end

-- ─── HUD page ─────────────────────────────────────────
do local L, R = addPage("hud")
    secHdr(L, "Overlay")
    togRow(L,"Watermark",       cfg.wm_on,  function(v) cfg.wm_on=v end)
    togRow(L,"Keybind Display", cfg.kb_on,  function(v) cfg.kb_on=v end)
    togRow(L,"State Indicators",cfg.ind_on, function(v) cfg.ind_on=v end)
end

-- ─── Anti-Aim page ────────────────────────────────────
do local L, R = addPage("antiaim")
    secHdr(L, "Anti-Aim")
    togRow(L,"Enable Anti-Aim",cfg.aa_on,       function(v) cfg.aa_on=v end)
    ddRow(L, "Pitch",          PITCHES, cfg.aa_pitch, function(v) cfg.aa_pitch=v end)
    ddRow(L, "Yaw",            YAWS,    cfg.aa_yaw,   function(v) cfg.aa_yaw=v end)
    togRow(L,"Freestand",      cfg.aa_freestand,function(v) cfg.aa_freestand=v end)
    togRow(L,"Pitch Faker",    cfg.aa_pitchfake,function(v) cfg.aa_pitchfake=v end)
end

-- ─── Skins page ───────────────────────────────────────────────
do local L, R = addPage("skins")
    -- Game badge
    local gRow = N("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.section_bg,BackgroundTransparency=0.30,BorderSizePixel=0,LayoutOrder=wo()},L)
    corner(6,gRow); stroke(C.border,1,0.30,gRow)
    local dotCol = IS_BLOXSTRIKE and Color3.fromRGB(50,190,100) or IS_COUNTERBLOX and Color3.fromRGB(30,144,255) or Color3.fromRGB(255,120,50)
    local gDot = N("Frame",{Size=UDim2.fromOffset(8,8),Position=UDim2.fromOffset(12,14),BackgroundColor3=dotCol,BorderSizePixel=0},gRow); corner(4,gDot)
    N("TextLabel",{Size=UDim2.new(1,-28,1,0),Position=UDim2.fromOffset(26,0),BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=13,Text="Game: "..GAME_NAME,TextColor3=C.text_w,TextXAlignment=Enum.TextXAlignment.Left},gRow)

    if IS_COUNTERBLOX then
        -- ══ COUNTER BLOX SKIN CHANGER ══════════════════
        secHdr(L,"Counter Blox Skins")
        togRow(L,"Enable Skin Changer", false, function(v)
            CB_SC.enabled = v
            if v and not CB_SC.hooked then
                cb_hook()
            end
        end)

        -- Side selector
        local SIDES = {"Both", "T Only", "CT Only"}
        ddRow(L,"Apply To", SIDES, 1, function(idx)
            CB_SC.side = ({"Both","TFolder","CTFolder"})[idx]
        end)

        -- Helper: CB skin dropdown — lists skins from CB_ALL_SKINS for that weapon
        local function cbSkinRow(parent, weaponLabel)
            local skins = cb_getSkins(weaponLabel)
            if #skins <= 1 then return end  -- weapon has no skins, skip
            CB_SC.selected[weaponLabel] = skins[1]
            ddRow(parent, weaponLabel, skins, 1, function(idx)
                CB_SC.selected[weaponLabel] = skins[idx]
                if CB_SC.enabled then
                    cb_applySkin(weaponLabel, skins[idx])
                end
            end)
        end

        secHdr(L,"Rifles & SMGs")
        cbSkinRow(L,"AK-47"); cbSkinRow(L,"M4A4"); cbSkinRow(L,"M4A1-S")
        cbSkinRow(L,"AWP");   cbSkinRow(L,"AUG");  cbSkinRow(L,"FAMAS")
        cbSkinRow(L,"SG 553");cbSkinRow(L,"Galil AR")
        secHdr(L,"Pistols")
        cbSkinRow(L,"Glock-18");cbSkinRow(L,"USP-S");cbSkinRow(L,"Desert Eagle")
        cbSkinRow(L,"P250");cbSkinRow(L,"Five-SeveN");cbSkinRow(L,"CZ75-Auto")
        cbSkinRow(L,"Dual Berettas")
        secHdr(L,"Heavy & SMGs")
        cbSkinRow(L,"MAC-10");cbSkinRow(L,"MP9");cbSkinRow(L,"UMP-45")
        cbSkinRow(L,"P90");cbSkinRow(L,"Negev");cbSkinRow(L,"Nova")

        secHdr(R,"Knife Type")
        ddRow(R,"Knife Model", CB_KNIFE_TYPES, 1, function(idx)
            cb_setKnifeType(CB_KNIFE_TYPES[idx])
        end)
        local kNoteF = N("Frame",{Size=UDim2.new(1,0,0,52),BackgroundColor3=Color3.fromRGB(12,20,50),BackgroundTransparency=0.20,BorderSizePixel=0,LayoutOrder=wo()},R)
        corner(6,kNoteF); stroke(Color3.fromRGB(30,80,180),1,0.30,kNoteF)
        N("TextLabel",{Size=UDim2.new(1,-16,1,0),Position=UDim2.fromOffset(10,0),BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=11,TextWrapped=true,TextColor3=C.text_s,TextXAlignment=Enum.TextXAlignment.Left,
            Text="ℹ  Equip your knife once in-game\n   first (so the hook captures it),\n   then pick a type here."},kNoteF)

        secHdr(R,"Knives")
        cbSkinRow(R,"Karambit");cbSkinRow(R,"Butterfly Knife")
        cbSkinRow(R,"Gut Knife");cbSkinRow(R,"Bayonet")
        cbSkinRow(R,"Falchion Knife");cbSkinRow(R,"Flip Knife")
        cbSkinRow(R,"Huntsman Knife")
        secHdr(R,"Gloves")
        cbSkinRow(R,"Sports Gloves");cbSkinRow(R,"Hand Wraps")
        cbSkinRow(R,"Strapped Gloves");cbSkinRow(R,"Fingerless Gloves")

        -- Info note
        local noteF = N("Frame",{Size=UDim2.new(1,0,0,56),BackgroundColor3=Color3.fromRGB(12,20,50),BackgroundTransparency=0.20,BorderSizePixel=0,LayoutOrder=wo()},R)
        corner(6,noteF); stroke(Color3.fromRGB(30,80,180),1,0.30,noteF)
        N("TextLabel",{Size=UDim2.new(1,-16,1,0),Position=UDim2.fromOffset(10,0),BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=11,TextWrapped=true,TextColor3=C.text_s,TextXAlignment=Enum.TextXAlignment.Left,
            Text="ℹ  Hooks __namecall to unlock all skins\n   in your inventory. Set the skin then\n   re-equip the weapon to see it.\n   Enable once per session is enough."},noteF)

    elseif IS_BLOXSTRIKE then
        -- ══ BLOXSTRIKE SKIN CHANGER ════════════════════
        secHdr(L,"Skin Changer")
        togRow(L,"Enable Skin Changer", false, function(v)
            SC.enabled = v
            if not v then sc_clearSkins() end
        end)

        local function skinDropRow(parent, weaponName, label)
            local opts = sc_getSkinList(weaponName)
            SC.selectedSkins[weaponName] = opts[1]
            ddRow(parent, label or weaponName, opts, 1, function(idx)
                SC.selectedSkins[weaponName] = opts[idx]
                for _, obj in ipairs(cam:GetChildren()) do
                    if obj.Name == weaponName then
                        pcall(function() obj:SetAttribute("SkinApplied", nil) end)
                    end
                end
            end)
        end

        secHdr(L,"Gloves")
        skinDropRow(L,"Sports Gloves","Sports Gloves")
        secHdr(L,"Knives")
        for _, kn in ipairs(SC_KNIVES) do skinDropRow(L, kn) end
        secHdr(R,"CT Weapons")
        for _, wn in ipairs(SC_CT) do skinDropRow(R, wn) end
        secHdr(R,"Shared Weapons")
        for _, wn in ipairs(SC_SHARED) do skinDropRow(R, wn) end

        -- Custom Knife
        secHdr(R,"Custom Knife")
        togRow(R,"Enable Custom Knife", false, function(v)
            ck.running = v
            if not v then ck_remove() end
        end)
        ddRow(R,"Knife Model", ckOptions, 1, function(idx)
            ck.selected = ckOptions[idx]
            if ck.spawned then ck_remove() end
        end)
        local noteF = N("Frame",{Size=UDim2.new(1,0,0,46),BackgroundColor3=Color3.fromRGB(15,22,52),BackgroundTransparency=0.20,BorderSizePixel=0,LayoutOrder=wo()},R)
        corner(6,noteF); stroke(Color3.fromRGB(30,80,180),1,0.30,noteF)
        N("TextLabel",{Size=UDim2.new(1,-16,1,0),Position=UDim2.fromOffset(10,0),BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=11,TextWrapped=true,TextColor3=C.text_s,TextXAlignment=Enum.TextXAlignment.Left,
            Text="F = Inspect  •  LMB = Swing\nRequires alive & knife equipped."},noteF)

    else
        -- ══ UNKNOWN GAME ═══════════════════════════════
        local noF = N("Frame",{Size=UDim2.new(1,0,0,52),BackgroundColor3=Color3.fromRGB(40,18,8),BackgroundTransparency=0.20,BorderSizePixel=0,LayoutOrder=wo()},L)
        corner(6,noF); stroke(Color3.fromRGB(180,60,20),1,0.40,noF)
        N("TextLabel",{Size=UDim2.new(1,-16,1,0),Position=UDim2.fromOffset(10,0),BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=12,TextWrapped=true,TextColor3=Color3.fromRGB(255,140,60),TextXAlignment=Enum.TextXAlignment.Left,
            Text="⚠  Skin Changer requires BloxStrike\nor Counter Blox.\n   Detected: "..GAME_NAME},noF)
    end
end

-- ─── Misc page ────────────────────────────────────────
do local L, R = addPage("misc")
    secHdr(L, "Movement")
    togRow(L,"Bhop",             cfg.bhop_on,         function(v) cfg.bhop_on=v end)
    togRow(L,"Spread Correction",cfg.spread_on,       function(v) cfg.spread_on=v end)
    togRow(L,"Grounded Only",    cfg.spread_groundonly,function(v) cfg.spread_groundonly=v end)
    secHdr(L, "Network")
    togRow(L,"Fake Lag",       cfg.fakelag_on,    function(v) cfg.fakelag_on=v end)
    sldRow(L,"Choke Ticks",    1, 16, cfg.fakelag_ticks, function(v) cfg.fakelag_ticks=v end)
    togRow(L,"Anti-Untrust",   cfg.anti_untrust,  function(v) cfg.anti_untrust=v end)
    secHdr(R, "Camera")
    togRow(R,"FOV Changer",    cfg.fov_on,    function(v) cfg.fov_on=v end)
    sldRow(R,"FOV Value",      50, 130, cfg.fov_val, function(v) cfg.fov_val=v end)
    togRow(R,"Third Person",   cfg.thirdperson,function(v) cfg.thirdperson=v; if not v then cam.CameraType=Enum.CameraType.Custom end end)
    secHdr(R, "Config")
    local cr = N("Frame", {Size=UDim2.new(1,0,0,ROW_H), BackgroundTransparency=1, BorderSizePixel=0, LayoutOrder=wo()}, R)
    local function cfgBtn(txt, xp, fn)
        local b = N("TextButton", {
            Size = UDim2.fromOffset(100,26),
            Position = UDim2.fromOffset(xp, 4),
            BackgroundColor3 = C.section_bg,
            BackgroundTransparency = C.GLASS_BTN,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold, TextSize = 12,
            Text = txt, TextColor3 = C.text_w,
            AutoButtonColor = false,
        }, cr)
        corner(5, b); stroke(C.border, 1, C.GLASS_STROKE, b)
        b.Activated:Connect(function()
            fn()
            tw(b,0.10,{BackgroundColor3=C.green, BackgroundTransparency=0.1})
            task.delay(0.8, function() tw(b,0.15,{BackgroundColor3=C.section_bg, BackgroundTransparency=C.GLASS_BTN}) end)
        end)
    end
    cfgBtn("Save Config",   0,   saveConfig)
    cfgBtn("Load Config",  106,  loadConfig)
end

-- ─── Launch on Aimbot page  (FIX: no redeclaration conflict) ──
showPage("aimbot")
