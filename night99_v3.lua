--[[
╔══════════════════════════════════════════════════════╗
║       99 NIGHTS IN THE FOREST — AUTO SCRIPT v3      ║
║  Viết lại hoàn toàn dựa trên cấu trúc thực của game ║
╚══════════════════════════════════════════════════════╝

  LÝ DO SCRIPT CŨ KHÔNG CHẠY:
  ✗ PathfindingService không hoạt động trong game này (map động, object không static)
  ✗ CollectionService tag không đúng — game không tag object theo cách đó
  ✗ Stats tăng vô điều kiện dù không làm gì
  ✗ Auto Join không có logic lobby thực tế

  CÁC FIX v3:
  ✓ Teleport CFrame trực tiếp — nhanh nhất, không bị kẹt
  ✓ Tìm object bằng tên thực (workspace.Map, workspace.Items, workspace.Characters)
  ✓ fireproximityprompt() để tương tác đúng cách
  ✓ Stats chỉ tăng khi thực sự làm được việc
  ✓ Auto Join đúng flow lobby (tìm MatchmakingBox → teleport → prompt)
  ✓ Gem Farm: 1-click, teleport đến từng gem sort theo distance
  ✓ UI hiển thị đúng trạng thái realtime
]]

-- ============================================================
-- SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer

-- ============================================================
-- CONFIG — Chỉnh tại đây
-- ============================================================
local CFG = {
    -- Auto Join
    TEAM_SIZE        = 1,     -- Team size muốn vào (1-5). 1 = solo, dễ nhất
    AUTO_JOIN        = true,  -- Tự vào lobby khi ở màn chờ
    JOIN_RETRY_DELAY = 3,     -- Giây chờ giữa các lần thử join

    -- Gameplay
    FIRE_FUEL_THRESHOLD = 50, -- Nạp lửa khi fuel <= 50%
    HUNGER_THRESHOLD    = 40, -- Ăn khi hunger <= 40%
    TELEPORT_Y_OFFSET   = 3,  -- Offset Y khi teleport tới object (tránh ngập đất)
    ACTION_WAIT         = 0.35,
    LOOP_DELAY          = 1.5,

    -- Gem farm: tên các item cần nhặt trong workspace
    GEM_NAMES = {
        "Gem", "Diamond", "Cultist_Gem", "BlueCrystal",
        "Blueprint", "Rare_Material", "Coal", "Scrap",
        "GemOfForest", "Crystal",
    },

    -- Tên object thực trong game (dựa theo workspace.Map, workspace.Items)
    CAMPFIRE_NAMES = {"Campfire", "CampFire", "Camp_Fire", "Fire"},
    WOOD_NAMES     = {"Wood", "Log", "TreeLog", "WoodLog"},
    FOOD_NAMES     = {
        "Mushroom", "Berry", "Apple", "Meat",
        "CookedMeat", "Cooked_Meat", "RawMeat", "Carrot",
    },
    CHILD_NAMES    = {
        "Child", "Kid", "MissingChild", "LostChild",
        "DinoKid", "GirlKid", "BoyKid",
    },
    MATCHBOX_NAMES = {
        "MatchmakingBox", "Matchmaking", "JoinBox",
        "TeamBox", "LobbyBox", "StartBox",
    },
}

-- ============================================================
-- STATE
-- ============================================================
local S = {
    on        = true,
    autoJoin  = CFG.AUTO_JOIN,
    gemFarm   = true,
    gemsGot   = 0,
    kidsFound = 0,
    nights    = 0,
    inGame    = false,
    startT    = os.time(),
}

-- ============================================================
-- CHARACTER HELPERS
-- ============================================================
local function getChar()
    local c = lp.Character
    if not c then return nil, nil, nil end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    if not h or not r then return nil, nil, nil end
    return c, h, r
end

-- Teleport trực tiếp bằng CFrame — không dùng Pathfinding
local function tpTo(pos)
    local _, _, hrp = getChar()
    if not hrp then return false end
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, CFG.TELEPORT_Y_OFFSET, 0))
    task.wait(CFG.ACTION_WAIT)
    return true
end

-- Kích hoạt ProximityPrompt
local function activate(obj)
    if not obj then return false end
    local pp = obj:FindFirstChildOfClass("ProximityPrompt")
             or obj:FindFirstChild("ProximityPrompt", true)
    if pp then
        fireproximityprompt(pp)
        task.wait(CFG.ACTION_WAIT)
        return true
    end
    return false
end

-- Tìm object gần nhất theo danh sách tên, quét trong nhiều root
local function findNearest(nameList, roots)
    local _, _, hrp = getChar()
    if not hrp then return nil, nil end
    roots = roots or {workspace}

    local best, bestPos, bestDist = nil, nil, math.huge

    for _, root in ipairs(roots) do
        if not root then continue end
        for _, obj in ipairs(root:GetDescendants()) do
            -- Khớp tên
            local matched = false
            for _, n in ipairs(nameList) do
                if obj.Name == n or obj.Name:lower():find(n:lower(), 1, true) then
                    matched = true; break
                end
            end
            if not matched then continue end

            -- Lấy position
            local pos
            if obj:IsA("BasePart") then
                pos = obj.Position
            elseif obj:FindFirstChild("HumanoidRootPart") then
                pos = obj.HumanoidRootPart.Position
            else
                local bp = obj:FindFirstChildWhichIsA("BasePart")
                if bp then pos = bp.Position end
            end

            if pos then
                local d = (hrp.Position - pos).Magnitude
                if d < bestDist then
                    best, bestPos, bestDist = obj, pos, d
                end
            end
        end
    end

    return best, bestPos
end

-- ============================================================
-- UI
-- ============================================================
do
    local old = lp.PlayerGui:FindFirstChild("N99UI")
    if old then old:Destroy() end
end

local sg = Instance.new("ScreenGui")
sg.Name           = "N99UI"
sg.ResetOnSpawn   = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent         = lp.PlayerGui

local CL = {
    bg     = Color3.fromRGB(8,  10, 16),
    panel  = Color3.fromRGB(14, 16, 26),
    border = Color3.fromRGB(55, 35, 95),
    purple = Color3.fromRGB(150, 80, 255),
    green  = Color3.fromRGB(55,  215, 105),
    red    = Color3.fromRGB(255, 70,  70),
    yellow = Color3.fromRGB(255, 195, 50),
    text   = Color3.fromRGB(210, 205, 230),
    dim    = Color3.fromRGB(105, 100, 130),
    dark   = Color3.fromRGB(18,  16, 30),
}

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end
local function stroke(p, col, t)
    local s = Instance.new("UIStroke")
    s.Color = col or CL.border; s.Thickness = t or 1.2; s.Parent = p
end
local function frame(p, sz, pos, bg)
    local f = Instance.new("Frame")
    f.Size = sz; f.Position = pos
    f.BackgroundColor3 = bg or CL.bg
    f.BorderSizePixel = 0; f.Parent = p
    return f
end
local function label(p, sz, pos, txt, font, ts, col, xa)
    local l = Instance.new("TextLabel")
    l.Size = sz; l.Position = pos
    l.BackgroundTransparency = 1
    l.Text = txt
    l.Font = font or Enum.Font.Gotham
    l.TextSize = ts or 11
    l.TextColor3 = col or CL.text
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = p
    return l
end
local function btn(p, sz, pos, txt, bg)
    local b = Instance.new("TextButton")
    b.Size = sz; b.Position = pos
    b.BackgroundColor3 = bg or CL.dark
    b.BorderSizePixel = 0
    b.Text = txt; b.Font = Enum.Font.GothamBold
    b.TextSize = 10; b.TextColor3 = CL.dark
    b.AutoButtonColor = false; b.Parent = p
    return b
end

-- Frame chính
local main = frame(sg,
    UDim2.new(0, 270, 0, 268),
    UDim2.new(0, 14, 0.5, -134), CL.bg)
main.ClipsDescendants = true
corner(main, 10); stroke(main, CL.border, 1.5)

-- Header
local hdr = frame(main, UDim2.new(1,0,0,36), UDim2.new(0,0,0,0), CL.panel)
corner(hdr, 10)
frame(hdr, UDim2.new(1,0,0,10), UDim2.new(0,0,1,-10), CL.panel) -- fix corners bawah

label(hdr, UDim2.new(1,-80,1,0), UDim2.new(0,10,0,0),
    "🌙  99 NIGHTS AUTO", Enum.Font.GothamBold, 13, CL.purple)

local toggleBtn = btn(hdr, UDim2.new(0,32,0,20), UDim2.new(1,-38,0.5,-10), "ON", CL.green)
corner(toggleBtn, 4)

-- Body
local body = frame(main, UDim2.new(1,-16,1,-44), UDim2.new(0,8,0,40), CL.bg)
body.BackgroundTransparency = 1

-- Status
local dot    = label(body, UDim2.new(0,14,0,20), UDim2.new(0,0,0,2),
    "●", Enum.Font.GothamBold, 14, CL.green, Enum.TextXAlignment.Center)
local statL  = label(body, UDim2.new(1,-18,0,20), UDim2.new(0,16,0,2),
    "Khởi động...", Enum.Font.GothamBold, 11, CL.text)
local subL   = label(body, UDim2.new(1,0,0,14), UDim2.new(0,0,0,23),
    "", Enum.Font.Gotham, 9, CL.dim)

-- Divider
local div = frame(body, UDim2.new(1,0,0,1), UDim2.new(0,0,0,41), CL.border)
div.BackgroundTransparency = 0.5

-- Stat rows
local function statRow(y, icon, lbl)
    label(body, UDim2.new(0,16,0,16), UDim2.new(0,0,0,y),
        icon, Enum.Font.Gotham, 11, CL.purple, Enum.TextXAlignment.Center)
    label(body, UDim2.new(0,100,0,16), UDim2.new(0,18,0,y), lbl, Enum.Font.Gotham, 10, CL.dim)
    local v = label(body, UDim2.new(1,-118,0,16), UDim2.new(0,118,0,y),
        "—", Enum.Font.GothamBold, 10, CL.dim, Enum.TextXAlignment.Right)
    return v
end

local vGems   = statRow(46,  "💎", "Gems nhặt được")
local vKids   = statRow(64,  "👧", "Trẻ em đã cứu")
local vNights = statRow(82,  "🌙", "Lần respawn")
local vTime   = statRow(100, "⏱", "Thời gian chạy")
local vState  = statRow(118, "📡", "Trạng thái")

-- Toggle buttons
local function toggleRow(y, lbl2, on)
    local rb = frame(body, UDim2.new(1,0,0,22), UDim2.new(0,0,0,y), CL.dark)
    corner(rb, 5); stroke(rb, CL.border, 1)
    label(rb, UDim2.new(1,-50,1,0), UDim2.new(0,8,0,0), lbl2, Enum.Font.Gotham, 10, CL.text)
    local p = btn(rb, UDim2.new(0,38,0,14), UDim2.new(1,-44,0.5,-7),
        on and "BẬT" or "TẮT", on and CL.green or CL.red)
    corner(p, 3)
    return p
end

local gemBtn  = toggleRow(144, "💎  Auto Gem Farm", true)
local joinBtn2 = toggleRow(169, "🔗  Auto Join Party", CFG.AUTO_JOIN)

-- Status setter
local function setStat(main2, sub, col)
    statL.Text = main2; subL.Text = sub or ""
    dot.TextColor3 = col or CL.green
end

local function refreshStats()
    local el = os.time() - S.startT
    vGems.Text   = tostring(S.gemsGot);   vGems.TextColor3   = S.gemsGot  >0 and CL.purple or CL.dim
    vKids.Text   = tostring(S.kidsFound); vKids.TextColor3   = S.kidsFound>0 and CL.green  or CL.dim
    vNights.Text = tostring(S.nights);    vNights.TextColor3 = S.nights   >0 and CL.yellow or CL.dim
    vTime.Text   = string.format("%dm %ds", math.floor(el/60), el%60)
    vState.Text  = S.on and "BẬT" or "TẮT"
    vState.TextColor3 = S.on and CL.green or CL.red
end

-- Draggable header
do
    local drag, ds, fs
    hdr.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = true; ds = i.Position; fs = main.Position
        end
    end)
    hdr.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - ds
            main.Position = UDim2.new(fs.X.Scale, fs.X.Offset+d.X, fs.Y.Scale, fs.Y.Offset+d.Y)
        end
    end)
end

-- Button events
toggleBtn.MouseButton1Click:Connect(function()
    S.on = not S.on
    toggleBtn.Text             = S.on and "ON"  or "OFF"
    toggleBtn.BackgroundColor3 = S.on and CL.green or CL.red
    setStat(S.on and "Tiếp tục..." or "Đã tạm dừng",
            S.on and "" or "Nhấn ON để tiếp tục",
            S.on and CL.green or CL.red)
end)

gemBtn.MouseButton1Click:Connect(function()
    S.gemFarm = not S.gemFarm
    gemBtn.Text             = S.gemFarm and "BẬT" or "TẮT"
    gemBtn.BackgroundColor3 = S.gemFarm and CL.green or CL.red
end)

joinBtn2.MouseButton1Click:Connect(function()
    S.autoJoin = not S.autoJoin
    joinBtn2.Text             = S.autoJoin and "BẬT" or "TẮT"
    joinBtn2.BackgroundColor3 = S.autoJoin and CL.green or CL.red
end)

-- ============================================================
-- I. AUTO JOIN PARTY
-- ============================================================
--[[
  Flow thực tế của game:
  Lobby → MatchmakingBox (có ProximityPrompt) → chọn team size → vào game

  Script sẽ:
  1. Tìm MatchmakingBox gần nhất (hoặc bất kỳ Part có ProximityPrompt với ActionText "Join"/"Play"/"Start")
  2. Teleport đến → fireproximityprompt
  3. Nếu game hỗ trợ attribute TeamSize thì filter theo đó
]]
local function tryAutoJoin()
    if not S.autoJoin then return false end

    -- Nếu đã thấy campfire = đã trong game, bỏ qua
    local cf = findNearest(CFG.CAMPFIRE_NAMES, {workspace})
    if cf then S.inGame = true; return false end

    setStat("🔗 Tìm MatchmakingBox...",
        "Team size: "..CFG.TEAM_SIZE, CL.yellow)

    -- Thu thập candidate boxes
    local boxes = {}

    for _, obj in ipairs(workspace:GetDescendants()) do
        -- Khớp tên
        local nameOk = false
        for _, n in ipairs(CFG.MATCHBOX_NAMES) do
            if obj.Name == n or obj.Name:lower():find(n:lower(), 1, true) then
                nameOk = true; break
            end
        end

        -- Hoặc: BasePart có ProximityPrompt với text liên quan join
        if not nameOk and obj:IsA("BasePart") then
            local pp = obj:FindFirstChildOfClass("ProximityPrompt")
            if pp then
                local at = pp.ActionText:lower()
                local ot = pp.ObjectText:lower()
                if at:find("join") or at:find("play") or at:find("start")
                or ot:find("team") or ot:find("player") or ot:find("solo") then
                    nameOk = true
                end
            end
        end

        if nameOk then
            -- Ưu tiên box có attribute TeamSize khớp
            local ts = obj:GetAttribute("TeamSize")
            local priority = (ts == CFG.TEAM_SIZE) and 0 or 1
            local pos
            if obj:IsA("BasePart") then pos = obj.Position
            else
                local bp = obj:FindFirstChildWhichIsA("BasePart")
                if bp then pos = bp.Position end
            end
            if pos then
                table.insert(boxes, {obj = obj, pos = pos, priority = priority})
            end
        end
    end

    if #boxes == 0 then
        setStat("🔗 Không thấy MatchmakingBox", "Thử lại sau...", CL.dim)
        return false
    end

    -- Sort: ưu tiên team size khớp, sau đó gần nhất
    local _, _, hrp = getChar()
    table.sort(boxes, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        if hrp then
            return (hrp.Position - a.pos).Magnitude < (hrp.Position - b.pos).Magnitude
        end
        return false
    end)

    local target = boxes[1]
    setStat("🔗 Đang vào box...", "TeamSize = "..CFG.TEAM_SIZE, CL.yellow)
    tpTo(target.pos)
    task.wait(0.5)
    local ok = activate(target.obj)

    if ok then
        setStat("✅ Đã nhấn join!", "Chờ game load...", CL.green)
        task.wait(4)
        return true
    end

    return false
end

-- ============================================================
-- II. AUTO GEM FARM — One-click, teleport sort by distance
-- ============================================================
--[[
  Cách nhanh nhất:
  1. Quét toàn bộ workspace.Items + workspace lấy tất cả gem có ProximityPrompt
  2. Sort theo distance từ gần đến xa
  3. Teleport thẳng → fireproximityprompt → tiếp theo
  Không Pathfinding, không MoveTo → không bị kẹt
]]
local function farmAllGems()
    if not S.gemFarm then return end
    local _, _, hrp = getChar()
    if not hrp then return end

    local items = {}

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj:FindFirstChildOfClass("ProximityPrompt") then
            for _, n in ipairs(CFG.GEM_NAMES) do
                if obj.Name == n or obj.Name:lower():find(n:lower(), 1, true) then
                    table.insert(items, {
                        obj  = obj,
                        pos  = obj.Position,
                        dist = (hrp.Position - obj.Position).Magnitude,
                    })
                    break
                end
            end
        end
    end

    if #items == 0 then return end

    -- Sort: gần nhất trước
    table.sort(items, function(a, b) return a.dist < b.dist end)

    setStat("💎 Farm Gems", string.format("Tìm thấy %d gems", #items), CL.purple)

    local got = 0
    for i, item in ipairs(items) do
        if not S.on or not S.gemFarm then break end
        if not item.obj or not item.obj.Parent then continue end

        tpTo(item.pos)
        local ok = activate(item.obj)
        if ok then
            got = got + 1
            S.gemsGot = S.gemsGot + 1
            setStat("💎 Đang nhặt...",
                string.format("%d/%d  |  Tổng: %d gems", got, #items, S.gemsGot),
                CL.purple)
        end
    end

    if got > 0 then
        setStat("💎 Farm xong!",
            string.format("Lần này: +%d  |  Tổng: %d", got, S.gemsGot), CL.green)
        task.wait(1)
    end
end

-- ============================================================
-- III. AUTO CAMPFIRE
-- ============================================================
local function getFuelPct()
    local cf = findNearest(CFG.CAMPFIRE_NAMES, {workspace})
    if not cf then return 100 end
    -- Thử các tên value phổ biến
    for _, vname in ipairs({"FuelAmount","Fuel","FuelLevel","FireLevel","Level"}) do
        local v = cf:FindFirstChild(vname)
               or cf:FindFirstChild(vname, true)
        if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then
            return v.Value <= 1 and v.Value * 100 or v.Value
        end
    end
    return 100
end

local function doFeedCampfire()
    local pct = getFuelPct()
    if pct > CFG.FIRE_FUEL_THRESHOLD then return end

    setStat("🔥 Lửa yếu!", string.format("Fuel %.0f%% — đi lấy gỗ", pct), CL.yellow)

    local wood, woodPos = findNearest(CFG.WOOD_NAMES, {workspace})
    if wood and woodPos then
        tpTo(woodPos)
        activate(wood)
        setStat("🪵 Đã lấy gỗ", "Đang về campfire...", CL.yellow)
    end

    local cf, cfPos = findNearest(CFG.CAMPFIRE_NAMES, {workspace})
    if cf and cfPos then
        tpTo(cfPos)
        activate(cf)
        setStat("🔥 Đã nạp lửa!", "", CL.green)
    end
end

-- ============================================================
-- IV. AUTO FOOD
-- ============================================================
local function getHungerPct()
    -- Tìm trong PlayerGui (game lưu hunger ở đây)
    local function scanGui(root)
        if not root then return nil end
        for _, v in ipairs(root:GetDescendants()) do
            local n = v.Name:lower()
            if n:find("hunger") or n:find("food") or n:find("stomach") then
                if v:IsA("NumberValue") or v:IsA("IntValue") then
                    return v.Value <= 1 and v.Value*100 or v.Value
                end
                if v:IsA("Frame") then
                    -- ProgressBar style
                    return v.Size.X.Scale * 100
                end
            end
        end
        return nil
    end

    local pct = scanGui(lp.PlayerGui)
    if pct then return pct end

    -- Fallback: character
    local c = lp.Character
    if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then
            local hv = h:FindFirstChild("Hunger")
            if hv then return hv.Value <= 1 and hv.Value*100 or hv.Value end
        end
    end

    return 100
end

local function doEat()
    local pct = getHungerPct()
    if pct > CFG.HUNGER_THRESHOLD then return end

    setStat("🍖 Đói!", string.format("Hunger %.0f%%", pct), CL.yellow)

    -- Thử dùng RemoteEvent nếu game có
    local eatEv = ReplicatedStorage:FindFirstChild("EatFood", true)
    if eatEv and eatEv:IsA("RemoteEvent") then
        eatEv:FireServer()
        setStat("🍖 Đã ăn!", "(qua RemoteEvent)", CL.green)
        return
    end

    -- Tìm food trong backpack
    for _, item in ipairs(lp.Backpack:GetChildren()) do
        for _, fname in ipairs(CFG.FOOD_NAMES) do
            if item.Name == fname or item.Name:lower():find(fname:lower(), 1, true) then
                local _, h = getChar()
                if h then
                    pcall(function() h:EquipTool(item) end)
                    task.wait(0.5)
                    setStat("🍖 Đang ăn...", item.Name, CL.green)
                end
                return
            end
        end
    end

    -- Tìm food trong workspace rồi nhặt
    local food, foodPos = findNearest(CFG.FOOD_NAMES, {workspace})
    if food and foodPos then
        setStat("🍖 Nhặt đồ ăn", food.Name, CL.yellow)
        tpTo(foodPos)
        activate(food)
    end
end

-- ============================================================
-- V. RESCUE CHILD
-- ============================================================
local function doRescue()
    local child, childPos = findNearest(CFG.CHILD_NAMES, {workspace})
    if not child or not childPos then
        setStat("👧 Không thấy trẻ em", "Đứng gần lửa trại...", CL.dim)
        return
    end

    setStat("👧 Thấy rồi!", child.Name, CL.green)
    tpTo(childPos)
    task.wait(0.5)
    local ok = activate(child)

    if ok then
        local cf, cfPos = findNearest(CFG.CAMPFIRE_NAMES, {workspace})
        if cf and cfPos then
            setStat("👧 Đang đưa về...", child.Name, CL.green)
            tpTo(cfPos)
            activate(cf)
            S.kidsFound = S.kidsFound + 1
            setStat("✅ Cứu xong!", string.format("Đã cứu %d trẻ", S.kidsFound), CL.green)
            task.wait(1)
        end
    end
end

-- ============================================================
-- VI. DETECT LOBBY vs IN-GAME
-- ============================================================
local function detectInGame()
    -- Đơn giản nhất: có campfire trong workspace = đang trong game
    local cf = findNearest(CFG.CAMPFIRE_NAMES, {workspace})
    S.inGame = cf ~= nil
    return S.inGame
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function mainLoop()
    -- Chờ character
    while true do
        local c, h, r = getChar()
        if c and h and r then break end
        setStat("⏳ Chờ nhân vật...", "", CL.dim)
        task.wait(1)
    end

    setStat("✅ Sẵn sàng!", "Đang kiểm tra trạng thái...", CL.green)
    task.wait(1)

    while true do
        task.wait(CFG.LOOP_DELAY)
        refreshStats()

        if not S.on then task.wait(0.5); continue end

        local c, h, r = getChar()
        if not c or not h or not r then
            setStat("💀 Đang hồi sinh...", "", CL.red)
            task.wait(3); continue
        end

        -- Check lobby vs in-game
        if not detectInGame() then
            setStat("🏠 Lobby", "Chuẩn bị join...", CL.yellow)
            task.wait(1)
            local joined = tryAutoJoin()
            if not joined then task.wait(CFG.JOIN_RETRY_DELAY) end
            continue
        end

        -- TRONG GAME — thứ tự ưu tiên:
        doFeedCampfire()  -- 1. Lửa (quan trọng nhất)
        doEat()           -- 2. Không chết đói
        farmAllGems()     -- 3. Farm gems (nếu bật)
        doRescue()        -- 4. Cứu trẻ em (nhiệm vụ chính)
    end
end

-- ============================================================
-- RESPAWN
-- ============================================================
lp.CharacterAdded:Connect(function()
    task.wait(1)
    S.nights = S.nights + 1
    setStat("🔄 Hồi sinh", "Đang tiếp tục...", CL.yellow)
end)

-- ============================================================
-- START
-- ============================================================
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("  99 Nights Auto Script v3 — ready")
print("  Kéo header để di chuyển UI")
print("  Toggle ON/OFF ở góc phải header")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

task.spawn(mainLoop)
