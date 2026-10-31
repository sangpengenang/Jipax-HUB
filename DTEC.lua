--[[
    Jpax Hub — Drill to Earth's Core (place 74507545904779)
    v1.9 — TERRA farm/loot/esp/combat/drill on Jpax Obsidian UI.
    Shop watch and the old depth overlay are not included.
]]

if typeof(getgenv) == "function" then
    getgenv().JPAX_UI_NO_PREVIEW = true
    pcall(function()
        local prev = getgenv().JPAX_DTEC_UNLOAD
        if type(prev) == "function" then
            prev()
        end
    end)
    pcall(function()
        local lib = getgenv().JPAX_OBSIDIAN_LIBRARY
        if lib and lib.Unloaded ~= true and type(lib.Unload) == "function" then
            if type(lib.UnloadSignals) == "table" then
                table.clear(lib.UnloadSignals)
            end
            lib:Unload()
        end
    end)
    getgenv().JPAX_OBSIDIAN_READY = nil
    getgenv().JPAX_OBSIDIAN_LIBRARY = nil
    getgenv().JPAX_OBSIDIAN_SAVE = nil
    getgenv().JPAX_OBSIDIAN_THEME = nil
    getgenv().JPAX_HUB_WINDOW = nil
    getgenv().__JPAX_GAME_SCRIPT_LOADED = nil
end

local JPAX = {
    placeId = 74507545904779,
    game = "Drill to Earth's Core",
    version = "2.1.6",
    obsidian = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/",
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local ContentProvider = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

if game.PlaceId ~= JPAX.placeId and game.PlaceId ~= 101906032112547 then
    warn("[JPAX DTEC] PlaceId mismatch:", game.PlaceId, "expected", JPAX.placeId)
end

local HUB_NAME = "JPAX HUB"

local function stripBom(source)
    if type(source) ~= "string" then
        return source
    end
    if source:sub(1, 3) == "\239\187\191" then
        return source:sub(4)
    end
    return source
end

local function runSource(source, chunkName)
    source = stripBom(source)
    chunkName = chunkName or "JPAXHub"

    if typeof(compile) == "function" then
        local ok, result = pcall(function()
            return compile(source, chunkName)()
        end)
        if ok then
            return result
        end
    end

    if typeof(loadstring) ~= "function" then
        error("Executor missing loadstring()")
    end

    local fn, err = loadstring(source, chunkName)
    if not fn then
        error(tostring(err))
    end

    if setfenv and typeof(getgenv) == "function" then
        setfenv(fn, getgenv())
    end

    return fn()
end

local State = {
    fly = false,
    noclip = false,
    fullbright = true,
    flySpeed = 1,
    speedHack = false,
    speedBoost = 50,
    speedMultiplier = 2,
    jumpPower = 50,
    connections = {},
    savedLighting = nil,
}

local Config = {
    folder = "jpax_hub_configs",
    indexFile = "jpax_hub_configs/_index.json",
    autoloadFile = "jpax_hub_configs/autoload.json",
    selectedName = "default",
    newName = "default",
    autoloadEnabled = false,
    autoloadName = "default",
}

local Loot = {
    enabled = false,
    range = 2000,
    pickupRange = 40,
    batchSize = 80,
    useBlacklist = false,
    blacklistCategories = {},
    useMinCoins = false,
    minCoins = 0,
    autoDropAfterLoot = false,
    busy = false,
    autoFuel = false,
    fuelThreshold = 0.85,
    fuelBusy = false,
    skipTruckLoot = true,
    truckZonePadLength = 8,
    truckZonePadWidth = 5,
    truckZonePadHeight = 6,
    autoEquipBag = false,
}

local Money = {
    enabled = false,
    busy = false,
    forwardStuds = 35,
    walkHeight = 14,
    detectRange = 180,
    maxStepsPerCycle = 30,
    sackRange = 50,
    useMinCoins = false,
    minCoins = 0,
    travelDirection = nil,
    lineOrigin = nil,
    travelDistance = 0,
    lastGoodPosition = nil,
    trackedBagSize = 0,
}

local Reap = {
    aura = false,
    radius = 16,
    busy = false,
    sell = false,
    sellBusy = false,
    ownedNoclip = false,
    auraModel = nil,
    _touched = {},
}

-- Map scan farm: fast tween along corridor, stop for loot, sell when full.
-- Farm window (100K m) follows Drill depth; hover height is the only UI knob.
local Autofarm = {
    enabled = false,
    busy = false,
    segmentStuds = 400,
    mapStartMeters = 0,
    mapEndMeters = 100000,
    mapStartStuds = 0,
    mapEndStuds = 100000,
    axis = "+Z",
    trackForward = true,
    routeDirBase = nil,
    routeDir = nil,
    flyY = 70,
    tweenSpeed = 1500,
    origin = nil,
    distance = 0,
    activeTween = nil,
    ownedNoclip = false,
    hoverLocked = false,
    moving = false,
    ownedCamAssist = false,
    camBackup = nil,
    depthHudVisible = false,
    -- Run is tween-only. Loot stays a Farm/Auto Loot filter (Loot.enabled).
    autoLoot = false,
    autoSell = true,
    sellThreshold = 10, -- sack fill trigger (TradeSell / drill / shredder)
    dropInDrill = false, -- exclusive dump dest vs sell / shredder (whole bag)
    dropInShredder = false, -- exclusive dump dest: whole bag → ScrapShredder
    drillDropTypes = { "Coal" }, -- unused; dump dest is no longer ore-filtered
    _pendingDrillDrop = false,
    _dropDrillOwnedLock = false, -- Drop in Drill forced Auto Lock Truck ON
    scrapFarm = false, -- Autofarm Scrap: standalone farm (auto-starts engine)
    scrapPhase = "seek_pick", -- seek_pick | chest_hunt | farm_gold
    scrapOreTypes = { "Gold" }, -- Copper/Gold → furnace; others → shredder direct
    scrapSeekLaps = 0, -- map laps while seeking pickaxe
    scrapSeekMinLaps = 2, -- after this many laps, farm with whatever pickaxe you have
    scrapSaved = nil, -- settings snapshot to restore on disable
    _scrapOwnedAutofarm = false, -- Scrap turned the farm engine on by itself
    _scrapHadAutofarm = false, -- Enable Autofarm was already ON before Scrap
    lootRange = 10000,
    resumePocketDistance = nil,
    resumePocketPos = nil,
    sellFromPos = nil,
    debugHud = true, -- on-screen farm log (also prints [JPAX FARM] to F9)
    enterMines = false, -- optional Join Mines toggle
    mineDetectRange = 3000, -- only path to mines within this flat distance
    skipMinesUntil = {},
    _activeMine = nil,
    _visitGen = 0,
    suppressMinesUntil = 0,
    openChests = false, -- optional Auto Chests
    autoSkipLockedChest = true, -- Core: skip locked chests and continue to the next one
    chestUnderDepth = 11, -- stand this many studs BELOW the chest
    chestTypes = {}, -- whitelist: Common / Gold / Diamond / ...
    lockedChestSkip = {},
    autoEquipBest = false, -- Pickaxe + Sword + Armor: better equip, equal/worse → sack
    oreUnderEnabled = false, -- Auto Ores
    oreUnderTypes = {}, -- Coal / Copper / Gold / ...
    oreUnderDepth = 11,
    breakDeathWormOres = true,
    enterDungeons = false,
    miningBusy = false,
    _miningBusySince = nil,
    _busySince = nil,
    _cycleGen = 0,
    _cycleAbort = false,
    autoUnloadFuelLock = false,
}

local FollowPlatform = {
    enabled = false,
    height = -10, -- absolute map Y (same idea as tools/PlatformFollow.lua)
    sizeX = 14,
    sizeZ = 14,
    thickness = 1,
    part = nil,
    lockedTarget = nil, -- optional Vector3 to park under (ore/chest)
}

-- Auto Drive sits in cabin + holds throttle (game requires seat; float drive does not work).
local AutoDrive = {
    enabled = false,
    claiming = false,
    claimGen = 0,
}

local GearEquip = {
    enabled = false,
    categories = {}, -- "Pickaxe", "Sword", "Armor", "Gun"
    range = 120,
    busy = false,
    lastPassAt = 0,
    slotBest = {}, -- [slotKey] = { score = n, name = "...", at = tick }
    triedAt = {},
}

local GEAR_EQUIP_OPTIONS = { "Pickaxe", "Sword", "Armor", "Gun" }
local GEAR_EQUIP_MAX_STUDS = 3000

-- Wiki chest tiers (cores): Wooden 1x, Golden 2x, Diamond 5x, Void 10x.
-- CommonChest in the game is the wooden tier. Extras (Free, Tutorial, Rusty,
-- Steel, Core, Mimic) stay in the same ladder so nothing already in-game disappears.
local CHEST_CATALOG = {
    { label = "Free Chest", canon = "free" },
    { label = "Tutorial Chest", canon = "tutorialcommon" },
    { label = "Wooden Chest", canon = "common" },
    { label = "Rusty Chest", canon = "rusty" },
    { label = "Steel Chest", canon = "steel" },
    { label = "Golden Chest", canon = "gold" },
    { label = "Diamond Chest", canon = "diamond" },
    { label = "Void Chest", canon = "void" },
    { label = "Core Chest", canon = "core" },
    { label = "Mimic", canon = "mimic" },
}

local CHEST_TYPE_OPTIONS = {}
local CHEST_ALIAS = {
    free = "free",
    freechest = "free",
    tutorial = "tutorialcommon",
    tutorialcommon = "tutorialcommon",
    tutorialchest = "tutorialcommon",
    wooden = "common",
    wood = "common",
    woodenchest = "common",
    common = "common",
    commonchest = "common",
    rusty = "rusty",
    rustychest = "rusty",
    steel = "steel",
    steelchest = "steel",
    gold = "gold",
    golden = "gold",
    goldenchest = "gold",
    goldchest = "gold",
    diamond = "diamond",
    diamondchest = "diamond",
    void = "void",
    voidchest = "void",
    core = "core",
    cores = "core",
    corechest = "core",
    coreschest = "core",
    chestcore = "core",
    mimic = "mimic",
}
for _, entry in ipairs(CHEST_CATALOG) do
    table.insert(CHEST_TYPE_OPTIONS, entry.label)
end

-- Only the ores users care about (normal + DeathWorm / worm variants).
-- Game assets: OreNode_* / WormNode_* under ReplicatedStorage.Assets.Ores
-- (Coal, Iron, Gold, Diamond, Ruby, Emerald, HeartGem). Iron is shown as Copper in UI.
local ORE_DROPDOWN_OPTIONS = {
    "Coal",
    "Copper",
    "Gold",
    "Diamond",
    "Ruby",
    "Emerald",
    "HeartGem",
}

-- Scrap whitelist: Copper/Gold smelt to bars first; others go straight to shredder.
-- Iron is presented as Copper everywhere in the hub.
local SCRAP_ORE_OPTIONS = {
    "Coal",
    "Copper",
    "Gold",
    "Diamond",
    "Ruby",
    "Emerald",
    "HeartGem",
}

local SCRAP_SMELT_ORE_TYPES = {
    Copper = true,
    Gold = true,
}

-- Asset folder / model names → hub filter key.
local ORE_TYPE_REMAP = {
    Iron = "Copper",
    Heart = "HeartGem",
    Heart_Gem = "HeartGem",
    Heartgem = "HeartGem",
}

-- ESP outline colors keyed by hub type (from Ore_Model, not BrickColor).
local ORE_TYPE_COLORS = {
    Ruby = { esp = Color3.fromRGB(255, 40, 60) },
    Diamond = { esp = Color3.fromRGB(0, 220, 255) },
    Coal = { esp = Color3.fromRGB(70, 70, 80) },
    Copper = { esp = Color3.fromRGB(200, 120, 70) },
    Iron = { esp = Color3.fromRGB(200, 120, 70) },
    Gold = { esp = Color3.fromRGB(255, 160, 20) },
    Emerald = { esp = Color3.fromRGB(40, 210, 63) },
    HeartGem = { esp = Color3.fromRGB(255, 80, 140) },
    Heart = { esp = Color3.fromRGB(255, 80, 140) },
}

-- Real dungeons are ONLY Workspace.DungeonGate_* models (not mines / pits).

local Pickaxe = {
    autoMine = false,
    autoEquip = false,
    mineRange = 120,
    busy = false,
}

local Combat = {
    killAura = false,
    -- Client melee scan hard-cap from dump (Champions/Sword: math.min(Range, 30000))
    auraRange = 50,
    autoEquipBestDamage = false,
    gunHeadshotAim = true,
    gunAimLead = true,      -- prediksi gerak musuh (lompat/lari)
    gunStartRise = 6,       -- maks. tinggi titik awal tembakan dari root pemain
    autoKillDeathWorms = false,
    autoKillFaceWorms = true,
    rideAutoJump = false,
    rideJumpRange = 28,
    _killingWorm = false,
    _lastFaceWormTick = 0,
    dodgeHitbox = false,
    dodgeMode = "Under", -- "Flee" | "Above" | "Under"
    dodgeRadius = 15,
    dodgeKeepDistance = 11,
    dodgeAboveHeight = 7,
    dodgeUnderDepth = 6,
    dodgeUnderScanBonus = 8,
    dodgeUnderReachBonus = 3,
    underActive = false,
    underLastSafeXZ = nil,
    dodgeSpeed = 62,
    dodgeStep = 11,
    busy = false,
}

local AmmoBuy = {
    -- Jenis ammo yang dibeli (dropdown di tab Shop).
    types = { "All Ammo" },
    localRange = 80,        -- studs: item dianggap "ada di toko ini" kalau dalam jarak ini
    maxShops = 5,           -- maks. toko yang dikunjungi kalau stok ammo kosong
    maxItemsPerShop = 60,   -- batas pengaman jumlah pembelian per toko
    busy = false,
    _bought = setmetatable({}, { __mode = "k" }),   -- key = instance item (bukan nama!)
    _failedAt = setmetatable({}, { __mode = "k" }),
}

local SHOP_SCAN_RANGE_METERS = 100000
local SHOP_DISPLAY_SLOT_COUNT = 29
local SHOP_FORTRESS_ASSIGN_RADIUS = 1200
local SHOP_FORTRESS_ASSIGN_MIN_LEAD = 350
local SHOP_SCAN_TOTAL_BUDGET_SECONDS = 8
local SHOP_SCAN_PER_SHOP_MIN = 0.2
local SHOP_SCAN_PER_SHOP_MAX = 0.7
local SHOP_SCAN_NEAR_RADIUS = 140

local ShopWatch = {
    hudAlerts = true,
    autoBuy = false,
    checkAllShops = false,
    watchlists = {
        tools = {},
        armors = {},
        ammos = {},
        consumables = {},
        medicals = {},
    },
    watchlist = {},
    catalogByCategory = {},
    memory = {},
    scannedStock = {},
    scannedStockByKey = {},
    fortressDisplay = {},
    worldItemList = {},
    cacheSeconds = 1,
    _cachedMatches = {},
    _cachedStock = {},
    _cacheAt = 0,
    _hudMatch = nil,
    _hudIndex = 1,
    _hudEntries = {},
    _purchasedKeys = {},
    _purchasedInstances = {},
    _needsRescanPrompt = false,
    _hudEntryOrder = {},
    _lastHudEntryCount = 0,
    _lastHudText = "",
    _restockEndTime = nil,
    _restockTimerInst = nil,
    _restockLastSeconds = nil,
    _autoScanArmed = false,
    _autoScanLastSeconds = nil,
    _streamQueue = {},
    _streamQueueIdx = 1,
    _lastStreamAt = 0,
    _lastAutoBuyAt = 0,
    _autoScanCycleEnd = nil,
    _nextHudShopAt = 0,
    _bgScanBusy = false,
    _bgScanProgress = nil,
    _lastFullScanAt = 0,
    _worldListLoaded = false,
}

local DepthHudOverlay = {
    supported = nil,
    bg = nil,
    lines = {},
    origin = Vector2.new(12, 124),
    padX = 10,
    padTop = 30,
    lineHeight = 18,
    fontSize = 15,
    lastHeavyAt = 0,
    lastScanAt = 0,
    lastRestockLookupAt = 0,
    cachedRestockEnd = nil,
    maxLines = 18,
    renderBound = false,
}

local SHOP_WATCH_CATEGORY_ORDER = { "tools", "armors", "ammos", "consumables", "medicals" }

local SHOP_WATCH_CATEGORY_LABELS = {
    tools = "Tools",
    armors = "Armors",
    ammos = "Ammos",
    consumables = "Consumables",
    medicals = "Medicals",
}

local SHOP_WATCH_CATALOG_BY_CATEGORY = {
    tools = {
        "Pickaxe_Kings", "Pickaxe_Phoenix", "Pickaxe_Void", "Pickaxe_Diamond", "Pickaxe_Gold",
        "Pickaxe_Steel", "Pickaxe_Rusty", "Pickaxe_Wooden",
        "Sword_Excalibur", "Sword_Kingslayer", "Sword_Phoenix", "Sword_Void", "Sword_Diamond",
        "Sword_Gold", "Sword_BountyHunter", "Sword_Steel", "Sword_Rusty", "Sword_Wooden",
        "Void_Shotgun", "Void_Rifle", "Void_Revolver", "Phoenix_Shotgun", "Phoenix_Rifle",
        "Phoenix_Revolver", "Web_Revolver", "Revolver", "Shotgun", "Rifle_Standard",
    },
    armors = {
        "Kings_Helmet", "Phoenix_Helmet", "Void_Helmet", "Diamond_Helmet", "Gold_Helmet",
        "Steel_Helmet", "Rusty_Helmet", "MinerHelmet_Elite",
        "Kings_Chest", "Phoenix_Chest", "Void_Chest", "Diamond_Chest", "Gold_Chest",
        "Steel_Chest", "Rusty_Chest", "Reaper_Chest", "Scout_Chest",
        "Kings_Legs", "Phoenix_Legs", "Void_Legs", "Diamond_Legs", "Gold_Legs",
        "Steel_Legs", "Rusty_Legs",
    },
    ammos = {
        "Revolver_Ammo", "Rifle_Ammo", "Shotgun_Ammo", "Special_Ammo",
    },
    consumables = {
        "Dynamite_Stick", "Speed_Potion", "Decoy_Grenade", "Landmine", "Lantern", "SoulLantern",
    },
    medicals = {
        "Golden_Medkit", "Advanced_Medkit", "Medkit", "Bandages", "ReviveKit",
    },
}

local TruckLock = {
    autoLock = false,
    busy = false,
}

local Keybinds = {
    list = {},
}

local Upgrades = {
    autoBuy = false,
    busy = false,
    optionsVersion = 0,
    prioritySlots = {},
    nextSlotId = 1,
    tab = nil,
    tabPage = nil,
}

local UPGRADE_PRIORITY_ADD_BUTTON = "+ Add Priority"
local UPGRADE_PRIORITY_ADD_LAYOUT = 51
local UPGRADE_PRIORITY_FIRST_LAYOUT = UPGRADE_PRIORITY_ADD_LAYOUT + 1

local UPGRADE_DISPLAY_INFO = {
    DrillPower = "Drill Power",
    FuelStorage = "Fuel Storage",
    DriveSpeed = "Drive Speed",
    DrillDefense = "Drill Defense",
    DeadlyDrill = "Deadly Drill",
    TeamHealth = "Team Health",
    SackStorage = "Sack Storage",
    PowerDrive = "Power Drive",
    PowerSlam = "Power Slam",
    EngineOverdrive = "Engine Overdrive",
    MegaDrill = "Mega Drill",
    TeamGunDamage = "Firepower",
    TeamMeleeDamage = "Sharpness",
    TeamPickaxeDamage = "Pickaxe Damage",
    TeamExplosiveDamage = "Blast Power",
    PowerBurst = "Power Burst",
    MountedGunner = "Mounted Gunner",
    RPMOverclock = "RPM Overclock",
    LifeSteal = "Life Steal",
    MoneyDrill = "Money Drill",
    UltraDrill = "Ultra Drill",
    HealthRegen = "Health Regen",
}

local UPGRADE_DROPDOWN_OPTIONS = { "None" }
do
    local names = {}
    for _, displayName in pairs(UPGRADE_DISPLAY_INFO) do
        table.insert(names, displayName)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        table.insert(UPGRADE_DROPDOWN_OPTIONS, name)
    end
end

local BLACKLIST_OPTIONS = {
    "Scrap",
    "Fuel",
    "Ore",
    "Coal",
    "Copper",
    "Gold",
    "Diamond",
    "Ruby",
    "Emerald",
    "HeartGem",
    "Bar",
    "Corpse",
    "Consumable",
    "Armor",
    "Primary Weapon",
    "Secondary Weapon",
    "Pickaxe",
    "Sword",
    "Medkit",
    "Tool",
}

local BLACKLIST_ORE_TYPES = {}
for _, name in ipairs(ORE_DROPDOWN_OPTIONS) do
    BLACKLIST_ORE_TYPES[string.lower(name)] = name
end
BLACKLIST_ORE_TYPES.iron = "Copper"
BLACKLIST_ORE_TYPES.heart = "HeartGem"
BLACKLIST_ORE_TYPES.heartgem = "HeartGem"

local ESP_LOOT_OPTIONS = { "All Items" }
for _, name in ipairs(BLACKLIST_OPTIONS) do
    table.insert(ESP_LOOT_OPTIONS, name)
end

local Esp = {
    maxRange = 2000,
    showNames = true,
    showDistance = true,
    tracers = false,
    lootEnabled = false,
    lootCategories = {},
    mobsEnabled = false,
    oresEnabled = false,
    chestsEnabled = false,
    dungeonsEnabled = false,
    minesEnabled = false,
    villagesEnabled = false,
}

local ESP_COLORS = {
    loot = Color3.fromRGB(255, 220, 60),
    mob = Color3.fromRGB(255, 70, 70),
    ore = Color3.fromRGB(80, 220, 255),
    chest = Color3.fromRGB(255, 190, 80),
    dungeon = Color3.fromRGB(180, 90, 255),
    mine = Color3.fromRGB(255, 160, 50),
    village = Color3.fromRGB(80, 255, 120),
}

local LOOT_ESP_COLORS = {
    ["All Items"] = Color3.fromRGB(255, 220, 60),
    Scrap = Color3.fromRGB(190, 190, 190),
    Fuel = Color3.fromRGB(255, 170, 70),
    Ore = Color3.fromRGB(120, 200, 255),
    Bar = Color3.fromRGB(210, 170, 90),
    Corpse = Color3.fromRGB(160, 80, 80),
    Consumable = Color3.fromRGB(120, 255, 160),
    Armor = Color3.fromRGB(130, 150, 255),
    ["Primary Weapon"] = Color3.fromRGB(255, 120, 120),
    ["Secondary Weapon"] = Color3.fromRGB(255, 150, 90),
    Pickaxe = Color3.fromRGB(180, 180, 255),
    Sword = Color3.fromRGB(255, 100, 100),
    Medkit = Color3.fromRGB(100, 255, 150),
    Tool = Color3.fromRGB(200, 200, 120),
}

local Services = {}
local Knit

local S = {}

function S.getKnit()
    if Knit then
        return Knit
    end

    local packages = ReplicatedStorage:WaitForChild("Packages", 30)
    if not packages then
        return nil
    end

    local knitModule = packages:WaitForChild("Knit", 30)
    if not knitModule then
        return nil
    end

    local ok, lib = pcall(require, knitModule)
    if ok then
        Knit = lib
    end

    return Knit
end

-- ========== JPAX OBSIDIAN (Rayfield-shaped adapter) ==========
local Rayfield

function S.getExecutorName()
    if typeof(identifyexecutor) == "function" then
        local ok, name = pcall(identifyexecutor)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return "Unknown"
end

function S.copyToClipboard(text)
    text = tostring(text or "")
    if text == "" then
        return false
    end
    if typeof(setclipboard) == "function" then
        setclipboard(text)
        return true
    end
    if typeof(toclipboard) == "function" then
        toclipboard(text)
        return true
    end
    if syn and typeof(syn.write_clipboard) == "function" then
        syn.write_clipboard(text)
        return true
    end
    return false
end

function S.httpGetText(url)
    local ok, body = pcall(function()
        return game:HttpGet(url, true)
    end)
    if ok and type(body) == "string" and body ~= "" then
        return stripBom(body)
    end
    return nil
end

function S.httpPostJson(url, payload)
    local headers = { ["Content-Type"] = "application/json", Accept = "application/json" }
    local req = { Url = url, Method = "POST", Headers = headers, Body = payload }
    local reqAlt = { url = url, method = "POST", headers = headers, body = payload }
    local fns = {}
    local seen = {}
    local function add(fn)
        if type(fn) == "function" and not seen[fn] then
            seen[fn] = true
            table.insert(fns, fn)
        end
    end
    pcall(function()
        if syn then
            add(syn.request)
            add(syn.http_request)
        end
    end)
    pcall(function()
        add(http_request)
    end)
    pcall(function()
        add(request)
    end)
    pcall(function()
        if http then
            add(http.request)
        end
    end)
    pcall(function()
        if fluxus then
            add(fluxus.request)
        end
    end)
    if typeof(getgenv) == "function" then
        local g = getgenv()
        add(g.http_request)
        add(g.request)
    end
    for i = 1, #fns do
        if pcall(fns[i], req) or pcall(fns[i], reqAlt) then
            return true
        end
    end
    if type(game.HttpPost) == "function" then
        if pcall(function()
            return game:HttpPost(url, payload, "application/json")
        end) then
            return true
        end
    end
    if type(game.HttpPostAsync) == "function" then
        if pcall(function()
            return game:HttpPostAsync(url, payload, "application/json")
        end) then
            return true
        end
    end
    return false
end

function S.runSourceSafe(source, chunkName)
    local ok, result = pcall(runSource, source, chunkName)
    if ok then
        return result
    end
    return nil
end

function S.validHub(mod)
    return type(mod) == "table" and type(mod.create) == "function"
end

function S.buildJpaxHub()
    local Hub = {}
    Hub._afkConn = nil
    Hub._presenceRunning = false

    function Hub.setAntiAfk(enabled)
        if Hub._afkConn then
            Hub._afkConn:Disconnect()
            Hub._afkConn = nil
        end
        if not enabled then
            return
        end
        local player = LocalPlayer or Players.LocalPlayer
        if not player then
            return
        end
        local vu = game:GetService("VirtualUser")
        Hub._afkConn = player.Idled:Connect(function()
            pcall(function()
                vu:CaptureController()
                vu:ClickButton2(Vector2.new(0, 0))
            end)
        end)
    end

    function Hub.notify(Library, text, duration)
        if Library and Library.Notify then
            pcall(function()
                Library:Notify(tostring(text), duration or 4)
            end)
        end
    end

    function Hub.startPresence()
        -- Anonymous user counter: sends only a random ID, once per run.
        if Hub._presenceRunning then
            return
        end
        Hub._presenceRunning = true
        task.spawn(function()
            pcall(function()
                local req = request or http_request or (syn and syn.request)
                if not req then
                    return
                end
                if not (isfile and readfile and writefile) then
                    return
                end
                local id
                if isfile("hub_anon_id.txt") then
                    id = readfile("hub_anon_id.txt")
                end
                if type(id) ~= "string" or not id:match("^[a-f0-9]+$") or #id < 16 then
                    id = ""
                    for _ = 1, 32 do
                        id = id .. string.format("%x", math.random(0, 15))
                    end
                    writefile("hub_anon_id.txt", id)
                end
                req({
                    Url = "https://counter.sangpengenang.workers.dev/ping",
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = game:GetService("HttpService"):JSONEncode({ id = id }),
                })
            end)
        end)
    end

    local function httpGetObsidian(path)
        local body = S.httpGetText(JPAX.obsidian .. path)
        if not body then
            error("[JPAX] Obsidian download failed: " .. path)
        end
        local lib = S.runSourceSafe(body, path)
        if not lib then
            error("[JPAX] Obsidian load failed: " .. path)
        end
        return lib
    end

    function Hub.loadObsidian()
        local g = typeof(getgenv) == "function" and getgenv() or nil
        local existing = g and g.JPAX_OBSIDIAN_LIBRARY
        if existing and existing.Unloaded ~= true then
            pcall(function()
                if type(existing.UnloadSignals) == "table" then
                    table.clear(existing.UnloadSignals)
                end
                if type(existing.Unload) == "function" then
                    existing:Unload()
                end
            end)
        end
        if g then
            g.JPAX_OBSIDIAN_READY = nil
            g.JPAX_OBSIDIAN_LIBRARY = nil
            g.JPAX_OBSIDIAN_SAVE = nil
            g.JPAX_OBSIDIAN_THEME = nil
        end
        local Library = httpGetObsidian("Library.lua")
        local ThemeManager = httpGetObsidian("addons/ThemeManager.lua")
        local SaveManager = httpGetObsidian("addons/SaveManager.lua")
        ThemeManager:SetLibrary(Library)
        SaveManager:SetLibrary(Library)
        pcall(function()
            ThemeManager:SetDefaultTheme({
                FontColor = "ffffff",
                MainColor = "242424",
                AccentColor = "3db488",
                BackgroundColor = "1c1c1c",
                OutlineColor = "373737",
                BackgroundImage = "",
                FontFace = "Gotham",
            })
        end)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({
            "MenuKeybind",
            "terra_autofarm",
            "jpax_auto_farm_bandit",
            "terra_shop_depth_hud",
            "terra_shop_hud_alerts",
            "terra_shop_check_all",
            "terra_shop_auto_buy",
            "terra_shop_watch_tools",
            "terra_shop_watch_armors",
            "terra_shop_watch_ammos",
            "terra_shop_watch_consumables",
            "terra_shop_watch_medicals",
            "terra_af_ore_worms",
            "jpax_dtec_drill_depth_m",
            "jpax_dtec_player_depth_m",
            "jpax_farm_drill_depth_m",
            "jpax_farm_player_depth_m",
        })
        Library.ShowToggleFrameInKeybinds = true
        Library.ShowCustomCursor = false
        Library.NotifySide = "Right"
        if typeof(getgenv) == "function" then
            getgenv().JPAX_OBSIDIAN_LIBRARY = Library
            getgenv().JPAX_OBSIDIAN_SAVE = SaveManager
            getgenv().JPAX_OBSIDIAN_THEME = ThemeManager
            getgenv().JPAX_OBSIDIAN_READY = true
            getgenv().JPAX_HUB_WINDOW = Hub
        end
        return Library, SaveManager, ThemeManager
    end

    function Hub.create(options)
        options = options or {}
        local Library, SaveManager, ThemeManager = Hub.loadObsidian()
        local version = tostring(options.Version or JPAX.version):gsub("^v", "")
        ThemeManager:SetFolder("jpax_hub")
        SaveManager:SetFolder("jpax_hub/universe_" .. tostring(game.GameId))
        local Window = Library:CreateWindow({
            Title = "Jpax Hub",
            Footer = "v" .. version .. " · DTEC",
            Center = true,
            AutoShow = true,
            Resizable = true,
            MobileButtonsSide = "Left",
            ShowCustomCursor = false,
            NotifySide = "Right",
            Icon = 95816097006870,
            DisableSearch = true,
        })
        -- Mobile: remove the library's floating "Toggle" and "Lock" buttons.
        do
            local isMobile = Library.IsMobile == true
                or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
            if isMobile then
                local function isMobileBtnText(t)
                    t = string.lower(tostring(t or ""))
                    return t == "toggle" or t == "lock" or t == "unlock"
                end
                local function sweepMobileButtons()
                    local gui = Library.ScreenGui
                    if typeof(gui) ~= "Instance" then
                        return
                    end
                    for _, obj in ipairs(gui:GetDescendants()) do
                        if (obj:IsA("TextButton") or obj:IsA("TextLabel")) and isMobileBtnText(obj.Text) then
                            local top = obj
                            while top.Parent and top.Parent ~= gui do
                                top = top.Parent
                            end
                            if top.Parent == gui and top:IsA("GuiObject") and not top:GetAttribute("JpaxHidden") then
                                local sz = top.AbsoluteSize
                                -- Only small floating buttons, never the main window.
                                if sz.X > 0 and sz.X <= 220 and sz.Y <= 120 then
                                    top:SetAttribute("JpaxHidden", true)
                                    top.Visible = false
                                    top:GetPropertyChangedSignal("Visible"):Connect(function()
                                        if top.Visible then
                                            top.Visible = false
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
                task.spawn(function()
                    for _, wait in ipairs({ 0, 0.3, 0.7, 1.5, 3, 6 }) do
                        task.wait(wait)
                        pcall(sweepMobileButtons)
                    end
                end)
            end
        end
        Library:OnUnload(function()
            Hub.setAntiAfk(false)
            Hub._presenceRunning = false
            if type(S.unloadJpaxDtec) == "function" then
                S.unloadJpaxDtec()
            end
        end)
        if options.ShowHomeTab ~= false then
            Hub.addHomeTab(Window, Library, options)
        end
        return Window, Library, SaveManager, ThemeManager, {
            gameTitle = options.Game or JPAX.game,
            version = version,
        }
    end

    function Hub.addHomeTab(Window, Library, options)
        options = options or {}
        local tab = Window:AddTab("Home", "house")
        local userBox = tab:AddLeftGroupbox("User", "user")
        userBox:AddLabel("User: " .. (LocalPlayer and LocalPlayer.Name or "?"))
        userBox:AddLabel("Executor: " .. S.getExecutorName())
        userBox:AddButton("Copy username", function()
            if LocalPlayer and S.copyToClipboard(LocalPlayer.Name) then
                Hub.notify(Library, "Copied", 2)
            end
        end)
        local sessionBox = tab:AddRightGroupbox("Session", "globe")
        sessionBox:AddLabel("Game: " .. (options.Game or JPAX.game))
        sessionBox:AddLabel("PlaceId: " .. tostring(game.PlaceId))
        sessionBox:AddButton("Rejoin", function()
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end)
        local jpaxBox = tab:AddLeftGroupbox("Jpax Hub", "sparkles")
        jpaxBox:AddLabel(options.HubBlurb or "TERRA farm on Jpax UI. No shop HUD, no depth overlay.")
        jpaxBox:AddLabel("v" .. JPAX.version)
        return tab
    end

    function Hub.complete(Window, Library, SaveManager, ThemeManager, options)
        options = options or {}
        local uiTab = Window:AddTab("UI Settings", "settings")
        local menuBox = uiTab:AddLeftGroupbox("Menu", "wrench")
        menuBox:AddToggle("JpaxAntiAfk", {
            Text = "Anti-AFK",
            Default = true,
            Callback = function(v)
                Hub.setAntiAfk(v)
            end,
        })
        menuBox:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
            Default = options.ToggleKeybind or "RightControl",
            NoUI = true,
            Text = "Menu keybind",
            ChangedCallback = function()
                Library.ToggleKeybind = Library.Options.MenuKeybind
            end,
        })
        menuBox:AddButton("Unload script", function()
            if Library.Unload then
                Library:Unload()
            end
        end)
        ThemeManager:ApplyToTab(uiTab)
        pcall(function()
            local _, hasDefault = ThemeManager:GetDefaultTheme()
            if not hasDefault then
                ThemeManager:ApplyTheme("Mint")
                ThemeManager:SaveDefault("Mint")
                local list = Library.Options and Library.Options.ThemeManager_ThemeList
                if list and list.SetValue then
                    list:SetValue("Mint")
                end
            end
        end)
        SaveManager:BuildConfigSection(uiTab)
        local shareBox = uiTab:AddRightGroupbox("Share", "folder")
        shareBox:AddLabel("One config for the whole game, saved under the universe id: jpax_hub/universe_" .. tostring(game.GameId) .. "/settings. Set one autoload. Lobby actions run in the lobby, and the farm runs in the match.")
        SaveManager:LoadAutoloadConfig()
        Library.ToggleKeybind = Library.Options.MenuKeybind or Enum.KeyCode.RightControl
        task.defer(function()
            Hub.setAntiAfk(true)
            Hub.startPresence()
        end)
        return uiTab
    end

    return Hub
end

local function dropdownList(value)
    if type(value) ~= "table" then
        if type(value) == "string" then
            return { value }
        end
        return value
    end
    if value[1] ~= nil then
        return value
    end
    local out = {}
    for key, item in pairs(value) do
        if type(key) == "string" and item == true then
            out[#out + 1] = key
        elseif type(item) == "string" then
            out[#out + 1] = item
        end
    end
    return out
end

function S.attachJpaxUiAdapter(Window, Library)
    local icons = {
        Lobby = "users",
        Core = "gem",
        Farm = "zap",
        Autofarm = "zap",
        Scrap = "recycle",
        Combat = "swords",
        ["Auto Combat"] = "shield",
        World = "map",
        Shop = "store",
        ESP = "eye",
        Player = "user",
        ["Auto Loot"] = "shopping-bag",
        Money = "coins",
        Pickaxe = "pickaxe",
        Teleport = "map",
        Upgrades = "sparkles",
        Drill = "arrow-down",
        Keybinds = "keyboard",
        Config = "settings",
        ["Auto Buy"] = "store",
        Depth = "layers",
    }
    local flags = {}
    S._jpaxFlags = flags
    local rf = {}
    rf.Flags = flags
    function rf.LoadConfiguration()
    end
    function rf.Notify(_, opts)
        opts = opts or {}
        local text = tostring(opts.Content or opts.Title or "")
        if opts.Title and opts.Content then
            text = tostring(opts.Title) .. " · " .. tostring(opts.Content)
        end
        if Library and Library.Notify then
            pcall(function()
                Library:Notify(text, opts.Duration or 4)
            end)
        end
    end
    function rf.CreateWindow()
        return {
            CreateTab = function(_, name)
                local tab = Window:AddTab(name, icons[name] or "box")
                local nextLeft = true
                local box
                local api = {}
                local function ensureBox()
                    if box then
                        return box
                    end
                    box = tab:AddLeftGroupbox("Main", icons[name] or "box")
                    nextLeft = false
                    return box
                end

                local function bindFlag(flagName, element)
                    if type(flagName) ~= "string" or flagName == "" then
                        return element
                    end
                    flags[flagName] = element
                    rf.Flags = flags
                    if Rayfield then
                        Rayfield.Flags = flags
                    end
                    return element
                end

                    function api:CreateSection(title)
                        if nextLeft then
                            box = tab:AddLeftGroupbox(title, "box")
                        else
                            box = tab:AddRightGroupbox(title, "box")
                        end
                        nextLeft = not nextLeft
                    end

                    function api:CreateToggle(opts)
                        opts = opts or {}
                        local element = {
                            Flag = opts.Flag,
                            CurrentValue = opts.CurrentValue == true,
                            Callback = opts.Callback,
                            Set = function(self, value)
                                self.CurrentValue = value == true
                                self._suppressCallback = true
                                if self._obsidian and self._obsidian.SetValue then
                                    pcall(function()
                                        self._obsidian:SetValue(value == true)
                                    end)
                                end
                                self._suppressCallback = false
                            end,
                        }
                        element._obsidian = ensureBox():AddToggle(opts.Flag or opts.Name, {
                            Text = opts.Name,
                            Default = opts.CurrentValue == true,
                            Callback = function(value)
                                element.CurrentValue = value == true
                                if element._suppressCallback then
                                    return
                                end
                                if opts.Callback then
                                    opts.Callback(value == true)
                                end
                            end,
                        })
                        return bindFlag(opts.Flag, element)
                    end

                    function api:CreateSlider(opts)
                        opts = opts or {}
                        local range = opts.Range or { 0, 100 }
                        local increment = tonumber(opts.Increment) or 1
                        local rounding = 0
                        if increment < 1 then
                            rounding = 1
                        end
                        local element = {
                            Flag = opts.Flag,
                            CurrentValue = opts.CurrentValue,
                            Set = function(self, value)
                                self.CurrentValue = value
                                if self._obsidian and self._obsidian.SetValue then
                                    pcall(function()
                                        self._obsidian:SetValue(tostring(value))
                                    end)
                                end
                            end,
                        }
                        element._obsidian = ensureBox():AddSlider(opts.Flag or opts.Name, {
                            Text = opts.Name,
                            Default = opts.CurrentValue or range[1],
                            Min = range[1],
                            Max = range[2],
                            Rounding = rounding,
                            Callback = function(value)
                                element.CurrentValue = value
                                if opts.Callback then
                                    opts.Callback(value)
                                end
                            end,
                        })
                        return bindFlag(opts.Flag, element)
                    end

                    function api:CreateDropdown(opts)
                        opts = opts or {}
                        local multi = opts.MultipleOptions == true
                        local current = opts.CurrentOption
                        if multi then
                            if type(current) == "string" then
                                current = { current }
                            elseif type(current) ~= "table" then
                                current = {}
                            end
                        else
                            if type(current) == "table" then
                                current = current[1]
                            end
                            if type(current) ~= "string" then
                                current = nil
                            end
                        end
                        local element = {
                            Flag = opts.Flag,
                            CurrentOption = current,
                            CurrentValue = current,
                            Set = function(self, value)
                                self.CurrentOption = value
                                self.CurrentValue = value
                            end,
                        }
                        local ok, widget = pcall(function()
                            return ensureBox():AddDropdown(opts.Flag or opts.Name, {
                                Text = opts.Name,
                                Values = opts.Options or { "None" },
                                Default = current,
                                Multi = multi,
                                AllowNull = true,
                                Callback = function(value)
                                    local list = dropdownList(value)
                                    if multi then
                                        element.CurrentOption = list
                                        element.CurrentValue = list
                                        if opts.Callback then
                                            opts.Callback(list or {})
                                        end
                                    else
                                        local picked = type(value) == "string" and value or (list and list[1])
                                        element.CurrentOption = picked
                                        element.CurrentValue = picked
                                        if opts.Callback then
                                            opts.Callback(picked)
                                        end
                                    end
                                end,
                            })
                        end)
                        if ok then
                            element._obsidian = widget
                        else
                            S.hubLog("dropdown fail " .. tostring(opts.Name) .. " " .. tostring(widget))
                        end
                        return bindFlag(opts.Flag, element)
                    end

                    function api:CreateButton(opts)
                        opts = opts or {}
                        ensureBox():AddButton(opts.Name or "Button", function()
                            if opts.Callback then
                                opts.Callback()
                            end
                        end)
                    end

                    function api:CreateParagraph(opts)
                        opts = opts or {}
                        ensureBox():AddLabel((opts.Title or "") .. (opts.Content and (" — " .. opts.Content) or ""))
                    end

                    function api:CreateStatusLabel(opts)
                        opts = opts or {}
                        local title = opts.Name or opts.Title or "Status"
                        local element = { Text = opts.Default or opts.Content or "—" }
                        local function paint()
                            local full = title .. ": " .. tostring(element.Text or "—")
                            if label.SetText then
                                pcall(function()
                                    label:SetText(full)
                                end)
                            elseif label.Set then
                                pcall(function()
                                    label:Set(full)
                                end)
                            end
                        end
                        local label = ensureBox():AddLabel(title .. ": " .. element.Text)
                        function element:Set(text)
                            element.Text = tostring(text or "—")
                            paint()
                        end
                        return element
                    end

                    function api:CreateInput(opts)
                        opts = opts or {}
                        local element = {
                            Flag = opts.Flag,
                            CurrentValue = "",
                            Set = function(self, value)
                                self.CurrentValue = tostring(value or "")
                            end,
                        }
                        if box.AddInput then
                            element._obsidian = ensureBox():AddInput(opts.Flag or opts.Name, {
                                Text = opts.Name,
                                Default = "",
                                Placeholder = opts.PlaceholderText,
                                Callback = function(text)
                                    element.CurrentValue = text
                                    if opts.Callback then
                                        opts.Callback(text)
                                    end
                                end,
                            })
                        else
                            ensureBox():AddLabel(opts.Name or "Input")
                        end
                        return bindFlag(opts.Flag, element)
                    end

                    function api:CreateKeybind(opts)
                        opts = opts or {}
                        local element = {
                            Flag = opts.Flag,
                            CurrentKeybind = "Unknown",
                            Set = function(self, key)
                                self.CurrentKeybind = key
                            end,
                        }
                        local label = ensureBox():AddLabel(opts.Name or "Bind")
                        pcall(function()
                            label:AddKeyPicker(opts.Flag or (opts.Name .. "_kb"), {
                                Default = "RightControl",
                                Text = opts.Name,
                                ChangedCallback = function(key)
                                    local name = typeof(key) == "EnumItem" and key.Name or tostring(key)
                                    element.CurrentKeybind = name
                                    if opts.Callback then
                                        opts.Callback(name)
                                    end
                                end,
                            })
                        end)
                        return bindFlag(opts.Flag, element)
                    end

                return api
            end,
        }
    end
    return rf
end

do
    local Hub = S.buildJpaxHub()
    local Window, Library, SaveManager, ThemeManager, meta = Hub.create({
        Game = JPAX.game,
        Version = JPAX.version,
        HubBlurb = "TERRA logic on Jpax UI — farm, loot, chests, ESP, combat, drill.",
    })
    S._jpaxHub = Hub
    S._jpaxWindow = Window
    S._jpaxLibrary = Library
    S._jpaxSave = SaveManager
    S._jpaxTheme = ThemeManager
    S._jpaxMeta = meta
    Rayfield = S.attachJpaxUiAdapter(Window, Library)
end
if not Rayfield then
    return warn("[JPAX DTEC] Obsidian UI failed to load")
end

local LOG_FILE = "terra_hub_debug.txt"

function S.hubLog(line)
    local text = os.date("%H:%M:%S") .. " | " .. tostring(line)
    print("[TERRA HUB]", line)
    if typeof(appendfile) == "function" then
        pcall(appendfile, LOG_FILE, text .. "\n")
    elseif typeof(writefile) == "function" then
        pcall(function()
            if not pcall(readfile, LOG_FILE) then
                writefile(LOG_FILE, "=== TERRA HUB DEBUG ===\n")
            end
            appendfile(LOG_FILE, text .. "\n")
        end)
    end
end

if typeof(writefile) == "function" then
    pcall(writefile, LOG_FILE, "=== TERRA HUB DEBUG ===\n")
end

function S.notify(title, text, duration)
    pcall(function()
        Rayfield:Notify({ Title = title, Content = text, Duration = duration or 4 })
    end)
end

function S.safeCall(label, fn)
    if not Services.PlayerService then
        S.notify(HUB_NAME, "Game services not ready yet", 4)
        return false
    end

    local ok, result = pcall(fn)
    if not ok then
        S.notify("Error", label .. ": " .. tostring(result), 5)
        warn("[TERRA HUB]", label, result)
    end
    return ok, result
end

function S.getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

function S.getRoot()
    local player = Players.LocalPlayer or LocalPlayer
    local char = player and player.Character
    if not char then
        return nil
    end
    return char:FindFirstChild("HumanoidRootPart")
        or char.PrimaryPart
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("LowerTorso")
        or char:FindFirstChildWhichIsA("BasePart")
end

function S.disconnectAll(key)
    if State.connections[key] then
        pcall(function()
        State.connections[key]:Disconnect()
        end)
        State.connections[key] = nil
    end
end

function S.disconnectEveryConnection()
    for key, conn in pairs(State.connections) do
        if conn then
            pcall(function()
                conn:Disconnect()
            end)
        end
        State.connections[key] = nil
    end
end

function S.clearJpaxDtecEnv()
    if typeof(getgenv) ~= "function" then
        return
    end
    local g = getgenv()
    g.JPAX_OBSIDIAN_READY = nil
    g.JPAX_OBSIDIAN_LIBRARY = nil
    g.JPAX_OBSIDIAN_SAVE = nil
    g.JPAX_OBSIDIAN_THEME = nil
    g.JPAX_HUB_WINDOW = nil
    g.__JPAX_GAME_SCRIPT_LOADED = nil
    g.JPAX_DTEC_UNLOAD = nil
end

function S.unloadJpaxDtec()
    if S._unloading then
        return
    end
    S._unloading = true
    if S.InvSpy then
        S.InvSpy.on = false
    end

    pcall(function()
        if type(S.setShardUse) == "function" then
            S.setShardUse(false)
        end
    end)
    pcall(function()
        if type(S.setAutofarm) == "function" then
            S.setAutofarm(false, { skipReturn = true })
        end
    end)
    pcall(function()
        if type(S.setBanditFarm) == "function" then
            S.setBanditFarm(false)
        end
    end)
    pcall(function()
        if type(S.forceReleaseFarmCharacter) == "function" then
            S.forceReleaseFarmCharacter()
        end
    end)
    pcall(function()
        if type(S.setNoclip) == "function" then
            S.setNoclip(false)
        end
    end)
    pcall(function()
        if type(S.clearEspVisuals) == "function" then
            S.clearEspVisuals()
        end
    end)
    pcall(function()
        if type(S.destroyDepthGui) == "function" then
            S.destroyDepthGui()
        end
    end)
    pcall(S.destroyFarmDebugHud)
    pcall(S.destroyMiniButton)
    pcall(S.disconnectEveryConnection)
    pcall(function()
        local Hub = S._jpaxHub
        if Hub then
            Hub._presenceRunning = false
            if Hub.setAntiAfk then
                Hub.setAntiAfk(false)
            end
        end
    end)
    pcall(function()
        local lib = S._jpaxLibrary
        if lib and lib.Unloaded ~= true and type(lib.Unload) == "function" then
            if type(lib.UnloadSignals) == "table" then
                table.clear(lib.UnloadSignals)
            end
            lib:Unload()
        end
    end)

    S._jpaxLibrary = nil
    S._jpaxWindow = nil
    S._jpaxHub = nil
    S.clearJpaxDtecEnv()
    S._unloading = false
end

if typeof(getgenv) == "function" then
    getgenv().JPAX_DTEC_UNLOAD = S.unloadJpaxDtec
end

-- Depth from dump:
-- DistanceController → DepthScale.GetMetersFromWorldPosition(Drill:GetPivot())
-- then writes CollectionService GetTagged("DepthText").Text = floormeters .. "m"
-- DepthScale: physical = |Start_Position - pos| / ( |End-Start| / 100000 ), + InfiniteDepthOffsetMeters

local DEPTH_TARGET_END_METERS = 100000
local DEPTH_LEGACY_STUDS_PER_METER = 2

function S.readGameDepthTextMeters()
    local ok, tagged = pcall(function()
        return CollectionService:GetTagged("DepthText")
    end)
    if not ok or type(tagged) ~= "table" then
        return nil
    end
    for _, gui in ipairs(tagged) do
        local textOk, text = pcall(function()
            return tostring(gui.Text or "")
        end)
        if textOk and type(text) == "string" then
            local n = tonumber((string.match(text, "([%-%d%.]+)")) or "")
            if n then
                return n, text
            end
        end
    end
    return nil
end

function S.getDepthWorldPosition()
    local drill = Workspace:FindFirstChild("Drill")
    if drill then
        local ok, pos = pcall(function()
            if drill:IsA("Model") then
                return drill:GetPivot().Position
            end
            if drill:IsA("BasePart") then
                return drill.Position
            end
            local part = drill:FindFirstChildWhichIsA("BasePart", true)
            return part and part.Position or nil
        end)
        if ok and typeof(pos) == "Vector3" then
            return pos, "Drill"
        end
    end

    local root = S.getRoot()
    if root then
        return root.Position, "Character"
    end
    return nil, nil
end

-- Pure dump math (no require) — same as DepthScale.GetMetersFromWorldPosition.
function S.computeDepthMetersDump(pos)
    if typeof(pos) ~= "Vector3" then
        return 0
    end

    local offset = Workspace:GetAttribute("InfiniteDepthOffsetMeters")
    if typeof(offset) ~= "number" then
        offset = 0
    end

    local start = Workspace:GetAttribute("Start_Position")
    local endPos = Workspace:GetAttribute("End_Position")

    if typeof(start) == "Vector3" and typeof(endPos) == "Vector3" then
        local routeMag = (endPos - start).Magnitude
        if routeMag > 0 then
            local scale = routeMag / DEPTH_TARGET_END_METERS
            return (start - pos).Magnitude / scale + offset
        end
    end

    if typeof(start) == "Vector3" then
        return (start - pos).Magnitude / DEPTH_LEGACY_STUDS_PER_METER + offset
    end

    return offset
end

function S.getDepthMetersFromPos(pos)
    -- Prefer live game HUD text (already computed by DistanceController).
    local fromHud = S.readGameDepthTextMeters()
    if fromHud then
        return fromHud
    end

    if typeof(pos) ~= "Vector3" then
        return 0
    end

    -- Optional module if present, else dump formula.
    local ds = S.getDepthScale()
    if ds and type(ds.GetMetersFromWorldPosition) == "function" then
        local ok, meters = pcall(ds.GetMetersFromWorldPosition, ds, pos)
        if ok and type(meters) == "number" and meters == meters then
            return meters
        end
    end

    return S.computeDepthMetersDump(pos)
end

-- Soft layer names from dump town checkpoints (along Start→End route).
local DEPTH_LAYER_CHECKPOINTS = {
    { Name = "Dirt Layer", Pos = Vector3.new(275, -1.5, -771.5) },
    { Name = "Stone Layer", Pos = Vector3.new(2675, -1.5, -771.5) },
    { Name = "Clay Layer", Pos = Vector3.new(5075, -1.5, -771.5) },
    { Name = "Fossil Layer", Pos = Vector3.new(7475, -1.5, -771.5) },
    { Name = "Crystal Layer", Pos = Vector3.new(9875, -1.5, -771.5) },
    { Name = "Toxic Layer", Pos = Vector3.new(13275, -1.5, -771.5) },
    { Name = "Radioactive Layer", Pos = Vector3.new(16675, -1.5, -771.5) },
    { Name = "The Abyss Layer", Pos = Vector3.new(20075, -1.5, -771.5) },
    { Name = "Void Layer", Pos = Vector3.new(23475, -1.5, -771.5) },
    { Name = "Glowing Core", Pos = Vector3.new(27875, -1.5, -771.5) },
}

function S.getDepthLayerName(meters)
    meters = tonumber(meters) or 0
    local ds = S.getDepthScale()
    if ds and type(ds.GetTownLocationThresholds) == "function" then
        local ok, thresholds = pcall(ds.GetTownLocationThresholds, ds)
        if ok and type(thresholds) == "table" then
            local layer = nil
            for _, entry in ipairs(thresholds) do
                local name = entry and entry.Name
                local startM = entry and entry.StartMeters
                if type(name) == "string" and type(startM) == "number" then
                    local isLayer = string.find(name, "Layer", 1, true) or name == "Glowing Core"
                    if isLayer and startM <= meters then
                        layer = name
                    elseif not isLayer and meters < startM then
                        break
                    end
                end
            end
            if layer then
                return layer
            end
        end
    end

    local layer = nil
    for _, cp in ipairs(DEPTH_LAYER_CHECKPOINTS) do
        local startM = S.computeDepthMetersDump(cp.Pos)
        if startM <= meters then
            layer = cp.Name
        end
    end
    return layer
end

function S.getDrillDepthMeters()
    local drill = S.getDrill()
    if not drill then
        return nil
    end

    local ok, pos = pcall(function()
        if drill:IsA("Model") then
            return drill:GetPivot().Position
        end
        if drill:IsA("BasePart") then
            return drill.Position
        end
        local part = drill:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end)
    if not ok or typeof(pos) ~= "Vector3" then
        return nil
    end

    local ds = S.getDepthScale()
    if ds and type(ds.GetMetersFromWorldPosition) == "function" then
        local dsOk, meters = pcall(ds.GetMetersFromWorldPosition, ds, pos)
        if dsOk and type(meters) == "number" and meters == meters then
            return meters
        end
    end

    return S.computeDepthMetersDump(pos)
end

function S.computeAutofarmDepthWindow(drillMeters)
    drillMeters = math.max(0, tonumber(drillMeters) or 0)
    local startM = math.floor(drillMeters / DEPTH_TARGET_END_METERS) * DEPTH_TARGET_END_METERS
    return startM, startM + DEPTH_TARGET_END_METERS
end

function S.getWorldPositionAtDepthMeters(meters)
    meters = tonumber(meters) or 0
    local offset = Workspace:GetAttribute("InfiniteDepthOffsetMeters")
    if typeof(offset) ~= "number" then
        offset = 0
    end

    local start = Workspace:GetAttribute("Start_Position")
    local endPos = Workspace:GetAttribute("End_Position")
    if typeof(start) ~= "Vector3" or typeof(endPos) ~= "Vector3" then
        return nil
    end

    local routeMag = (endPos - start).Magnitude
    if routeMag <= 0 then
        return nil
    end

    local scale = routeMag / DEPTH_TARGET_END_METERS
    local along = (meters - offset) * scale
    local dir = start - endPos
    if dir.Magnitude < 0.001 then
        return nil
    end

    return start - dir.Unit * along
end

function S.getWorldFlatAtDepthMeters(meters)
    local pos = S.getWorldPositionAtDepthMeters(meters)
    if not pos then
        return nil
    end
    return Vector3.new(pos.X, S.getAutofarmFlyY(), pos.Z)
end

function S.syncAutofarmWindowFromDrill()
    local drillM = S.getDrillDepthMeters()
    if not drillM then
        drillM = tonumber(Autofarm.mapStartMeters) or 0
        if tonumber(Autofarm.mapEndMeters) then
            drillM = drillM + (Autofarm.mapEndMeters - drillM) * 0.5
        else
            drillM = DEPTH_TARGET_END_METERS * 0.5
        end
    end

    local startM, endM = S.computeAutofarmDepthWindow(drillM)
    local prevStart = tonumber(Autofarm.mapStartMeters)
    local windowChanged = prevStart == nil or prevStart ~= startM
    local spp = S.getAutofarmStudsPerMeter()

    Autofarm.mapStartMeters = startM
    Autofarm.mapEndMeters = endM
    Autofarm.mapStartStuds = 0
    Autofarm.mapEndStuds = DEPTH_TARGET_END_METERS * spp

    if windowChanged then
        local flat = S.getWorldFlatAtDepthMeters(startM)
        if flat then
            Autofarm.origin = flat
            S.refreshAutofarmRouteDir()
        end
        S.syncAutofarmDistanceFromRoot()
        if Autofarm.enabled then
            S.setAutofarmPose(Autofarm.distance or 0)
        end
    end

    return windowChanged, startM, endM
end

function S.getShopWatchRangeStuds()
    return SHOP_SCAN_RANGE_METERS * S.getAutofarmStudsPerMeter()
end

function S.normalizeShopItemKey(name)
    return string.lower(tostring(name or ""):gsub("[%s_]+", ""))
end

function S.formatShopDisplayLabel(name)
    local raw = tostring(name or "")
    if raw == "" then
        return raw
    end
    return raw:gsub("_", " ")
end

function S.shopItemMatchesWatchExact(itemName, watchName)
    return S.normalizeShopItemKey(itemName) == S.normalizeShopItemKey(watchName)
end

function S.shopItemMatchesWatch(itemName, watchName)
    local a = S.normalizeShopItemKey(itemName)
    local b = S.normalizeShopItemKey(watchName)
    if a == "" or b == "" then
        return false
    end
    if a == b then
        return true
    end
    return a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

function S.classifyShopWatchCategory(itemName)
    local n = string.lower(tostring(itemName or ""))
    if n:find("ammo", 1, true) then
        return "ammos"
    end
    if n:find("medkit", 1, true) or n:find("bandage", 1, true) or n:find("revivekit", 1, true) then
        return "medicals"
    end
    if n:find("dynamite", 1, true) or n:find("potion", 1, true) or n:find("grenade", 1, true)
        or n:find("landmine", 1, true) or n:find("lantern", 1, true) then
        return "consumables"
    end
    if n:find("helmet", 1, true) or n:find("_chest", 1, true) or n:find("_legs", 1, true)
        or n:find("_boots", 1, true) or n:find("tiara", 1, true) or n:find("crown", 1, true) then
        return "armors"
    end
    return "tools"
end

function S.rebuildShopWatchCombinedList()
    local combined = {}
    local seen = {}
    for _, category in ipairs(SHOP_WATCH_CATEGORY_ORDER) do
        for _, name in ipairs(ShopWatch.watchlists[category] or {}) do
            name = tostring(name or "")
            if name ~= "" then
                local key = S.normalizeShopItemKey(name)
                if key ~= "" and not seen[key] then
                    seen[key] = true
                    table.insert(combined, name)
                end
            end
        end
    end
    ShopWatch.watchlist = combined
    return combined
end

function S.normalizeShopWatchDropdownOptions(options)
    local out = {}
    if options == nil then
        return out
    end
    if type(options) == "string" then
        if options ~= "" then
            table.insert(out, options)
        end
    elseif type(options) == "table" then
        local numeric = {}
        for k, v in pairs(options) do
            if type(k) == "number" then
                table.insert(numeric, tostring(v))
            elseif v == true then
                table.insert(out, tostring(k))
            end
        end
        table.sort(numeric)
        for _, name in ipairs(numeric) do
            table.insert(out, name)
        end
    end

    local seen = {}
    local deduped = {}
    for _, name in ipairs(out) do
        name = tostring(name or "")
        if name ~= "" then
            local key = S.normalizeShopItemKey(name)
            if not seen[key] then
                seen[key] = true
                table.insert(deduped, name)
            end
        end
    end
    return deduped
end

function S.syncShopWatchDropdownFlagsFromRayfield()
    if not Rayfield or not Rayfield.Flags then
        return
    end
    for _, category in ipairs(SHOP_WATCH_CATEGORY_ORDER) do
        local flag = Rayfield.Flags["terra_shop_watch_" .. category]
        if flag and flag.CurrentValue ~= nil then
            ShopWatch.watchlists[category] = S.normalizeShopWatchDropdownOptions(flag.CurrentValue)
        end
    end
    S.rebuildShopWatchCombinedList()
end

function S.getCombinedShopWatchlist()
    if type(ShopWatch.watchlist) ~= "table" or #ShopWatch.watchlist == 0 then
        S.rebuildShopWatchCombinedList()
    end
    return ShopWatch.watchlist or {}
end

function S.isShopWatchlisted(itemName)
    local combined = S.getCombinedShopWatchlist()
    if #combined == 0 then
        return false
    end
    for _, watchName in ipairs(combined) do
        if S.shopItemMatchesWatchExact(itemName, watchName) or S.shopItemMatchesWatch(itemName, watchName) then
            return true
        end
    end
    return false
end

function S.getWatchlistKeyForItem(name, displayName)
    local combined = S.getCombinedShopWatchlist()
    local bestKey, bestWatch, bestLen = nil, nil, 0

    for _, watchName in ipairs(combined) do
        if S.shopItemMatchesWatchExact(name, watchName) or S.shopItemMatchesWatchExact(displayName, watchName) then
            local len = #tostring(watchName)
            if len > bestLen then
                bestLen = len
                bestKey = S.normalizeShopItemKey(watchName)
                bestWatch = watchName
            end
        end
    end
    if bestKey then
        return bestKey, bestWatch
    end

    for _, watchName in ipairs(combined) do
        if S.shopItemMatchesWatch(name, watchName) or S.shopItemMatchesWatch(displayName, watchName) then
            return S.normalizeShopItemKey(watchName), watchName
        end
    end

    return nil, nil
end

function S.tryPickRestockEndTime(inst, bestEnd)
    if not inst then
        return bestEnd
    end
    local et = inst:GetAttribute("EndTime")
    if typeof(et) ~= "number" then
        return bestEnd
    end
    if not bestEnd or et > bestEnd then
        return et
    end
    return bestEnd
end

function S.getUiRestockTimerInst()
    local pinned = ShopWatch._restockTimerInst
    if pinned and pinned.Parent and pinned:GetAttribute("EndTime") then
        return pinned
    end

    pcall(function()
        for _, inst in ipairs(CollectionService:GetTagged("TimerText")) do
            if inst:IsDescendantOf(LocalPlayer.PlayerGui) then
                ShopWatch._restockTimerInst = inst
                return
            end
        end
    end)
    if ShopWatch._restockTimerInst then
        return ShopWatch._restockTimerInst
    end

    local bestInst = nil
    local bestEnd = nil
    pcall(function()
        for _, inst in ipairs(CollectionService:GetTagged("TimerText")) do
            if inst:IsDescendantOf(Workspace) then
                local et = inst:GetAttribute("EndTime")
                if typeof(et) == "number" and (not bestEnd or et > bestEnd) then
                    bestEnd = et
                    bestInst = inst
                end
            end
        end
    end)
    ShopWatch._restockTimerInst = bestInst
    return bestInst
end

function S.findGlobalShopRestockEndTime()
    local inst = S.getUiRestockTimerInst()
    if not inst then
        return nil
    end
    local et = inst:GetAttribute("EndTime")
    if typeof(et) == "number" then
        return et
    end
    return nil
end

function S.getGlobalShopRestockTimer()
    local endTime = S.findGlobalShopRestockEndTime()
    DepthHudOverlay.cachedRestockEnd = endTime
    if not endTime then
        return { seconds = nil, endTime = nil, text = nil }
    end

    local seconds = math.max(0, endTime - workspace:GetServerTimeNow())
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return {
        seconds = seconds,
        endTime = endTime,
        text = string.format("%02d:%02d", mins, secs),
    }
end

function S.didUiRestockTimerRollOver(prevSeconds, seconds)
    prevSeconds = tonumber(prevSeconds)
    seconds = tonumber(seconds)
    if prevSeconds == nil or seconds == nil then
        return false
    end
    if seconds > prevSeconds + 15 then
        return true
    end
    return prevSeconds <= 3 and seconds >= 20
end

function S.onShopRestockCycle()
    ShopWatch.memory = {}
    ShopWatch.scannedStock = {}
    ShopWatch.scannedStockByKey = {}
    ShopWatch._purchasedKeys = {}
    ShopWatch._purchasedInstances = {}
    ShopWatch._cachedMatches = {}
    ShopWatch._cachedStock = {}
    ShopWatch._hudEntryOrder = {}
    ShopWatch._needsRescanPrompt = true
    ShopWatch._cacheAt = 0
    ShopWatch.worldItemList = {}
    S.saveShopWorldItemList()
    S.notify("Shop", "Restock! Scan shops again", 5)
end

function S.getShopWorldItemsFile()
    return Config.folder .. "/shop_world_items.json"
end

function S.getShopCatalogFile()
    return Config.folder .. "/shop_display_catalog.json"
end

function S.serializeVec3(vec)
    if typeof(vec) ~= "Vector3" then
        return nil
    end
    return { X = vec.X, Y = vec.Y, Z = vec.Z }
end

function S.deserializeVec3(raw)
    if type(raw) ~= "table" then
        return nil
    end
    local x = tonumber(raw.X)
    local y = tonumber(raw.Y)
    local z = tonumber(raw.Z)
    if x and y and z then
        return Vector3.new(x, y, z)
    end
    return nil
end

function S.getShopPosKey(pos)
    if typeof(pos) ~= "Vector3" then
        pos = S.deserializeVec3(pos)
    end
    if typeof(pos) ~= "Vector3" then
        return nil
    end
    -- High precision so stacked shop copies (e.g. 9 Special Ammo) don't collapse into 1.
    return string.format("%.4f,%.4f,%.4f", pos.X, pos.Y, pos.Z)
end

function S.buildShopPosIndex(list)
    local index = {}
    for _, rec in ipairs(list or {}) do
        local key = rec.posKey or S.getShopPosKey(rec.pos)
        if key then
            index[key] = true
        end
    end
    return index
end

function S.loadShopWorldItemList()
    ShopWatch.worldItemList = ShopWatch.worldItemList or {}
    if not S.configHasFileApi() then
        return false
    end
    S.configEnsureFolder()
    local path = S.getShopWorldItemsFile()
    if typeof(isfile) == "function" and not isfile(path) then
        ShopWatch._worldListLoaded = true
        return false
    end

    local readOk, raw = pcall(readfile, path)
    if not readOk or type(raw) ~= "string" or raw == "" then
        return false
    end

    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodeOk or type(data) ~= "table" then
        return false
    end

    ShopWatch.worldItemList = {}
    for _, rec in ipairs(data.items or {}) do
        if type(rec) == "table" and rec.name then
            local pos = S.deserializeVec3(rec.pos)
            -- Rebuild posKey with current precision so old %.1f keys don't collapse stacks.
            local posKey = pos and S.getShopPosKey(pos) or rec.posKey
            table.insert(ShopWatch.worldItemList, {
                name = rec.name,
                displayName = rec.displayName or rec.name,
                pos = pos and S.serializeVec3(pos) or rec.pos,
                posKey = posKey,
                scannedAt = tonumber(rec.scannedAt) or 0,
            })
        end
    end
    ShopWatch._worldListLoaded = true
    return true
end

function S.saveShopWorldItemList()
    if not S.configHasFileApi() then
        return false
    end
    S.configEnsureFolder()

    local items = {}
    for _, rec in ipairs(ShopWatch.worldItemList or {}) do
        table.insert(items, {
            name = rec.name,
            displayName = rec.displayName or rec.name,
            pos = rec.pos,
            posKey = rec.posKey,
            scannedAt = tonumber(rec.scannedAt) or 0,
        })
    end

    local payload = {
        version = 1,
        updatedAt = tick(),
        count = #items,
        items = items,
    }

    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
    if ok then
        pcall(writefile, S.getShopWorldItemsFile(), encoded)
        return true
    end
    return false
end

function S.dedupeShopWorldItemList()
    local list = ShopWatch.worldItemList or {}
    if #list <= 1 then
        return 0
    end
    local seenRef = {}
    local seenPos = {}
    local kept = {}
    local removed = 0
    for _, rec in ipairs(list) do
        local ref = rec._itemRef
        if ref and not ref.Parent then
            rec._itemRef = nil
            ref = nil
        end
        if ref and seenRef[ref] then
            removed = removed + 1
            continue
        end
        local key = rec.posKey or S.getShopPosKey(rec.pos)
        if key and seenPos[key] then
            removed = removed + 1
            continue
        end
        if ref then
            seenRef[ref] = true
        end
        if key then
            seenPos[key] = true
            rec.posKey = key
        end
        table.insert(kept, rec)
    end
    if removed > 0 then
        ShopWatch.worldItemList = kept
    end
    return removed
end

function S.persistWatchlistedShopItemToWorldList(item, opts)
    opts = type(opts) == "table" and opts or {}
    local allowCreate = opts.allowCreate ~= false
    if not item or not item.Parent then
        return nil
    end
    if #S.getCombinedShopWatchlist() == 0 then
        return nil
    end
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder then
        return nil
    end
    local top = item
    if top.Parent ~= itemsFolder then
        top = S.resolveWorldItem(item)
    end
    if not top or top.Parent ~= itemsFolder then
        return nil
    end
    if not S.hasShopItemTag(top) then
        return nil
    end
    local displayName = top:GetAttribute("DisplayName") or top.Name
    if not (S.isShopWatchlisted(top.Name) or S.isShopWatchlisted(displayName)) then
        return nil
    end
    local pos = S.getItemPosition(top)
    local key = S.getShopPosKey(pos)
    if not key then
        return nil
    end

    ShopWatch.worldItemList = ShopWatch.worldItemList or {}

    -- Same live instance already tracked → only update position (dragging must not clone HUD qty).
    for _, rec in ipairs(ShopWatch.worldItemList) do
        if rec._itemRef == top then
            if rec.posKey ~= key then
                rec.pos = S.serializeVec3(pos)
                rec.posKey = key
                rec.displayName = displayName
                if opts.save == true then
                    S.saveShopWorldItemList()
                end
            else
                rec._itemRef = top
            end
            return rec
        end
    end

    -- Same saved position → attach instance ref.
    for _, rec in ipairs(ShopWatch.worldItemList) do
        if rec.posKey == key then
            rec._itemRef = top
            rec.displayName = displayName or rec.displayName
            return rec
        end
    end

    if not allowCreate then
        return nil
    end

    local rec = {
        name = top.Name,
        displayName = displayName,
        pos = S.serializeVec3(pos),
        posKey = key,
        scannedAt = tick(),
        _itemRef = top,
    }
    table.insert(ShopWatch.worldItemList, rec)
    if opts.save == true then
        S.saveShopWorldItemList()
    end
    return rec
end

function S.flushLiveWatchlistedShopItemsToWorldList(opts)
    opts = type(opts) == "table" and opts or {}
    local before = #(ShopWatch.worldItemList or {})
    local allowCreate = opts.allowCreate ~= false
    for _, item in ipairs(CollectionService:GetTagged("ShopItem")) do
        S.persistWatchlistedShopItemToWorldList(item, { allowCreate = allowCreate })
    end
    S.dedupeShopWorldItemList()
    local added = #(ShopWatch.worldItemList or {}) - before
    if (added > 0 or opts.forceSave) and opts.save ~= false then
        S.saveShopWorldItemList()
    end
    return math.max(added, 0)
end

function S.countWatchlistedShopItemsNear(center, radius)
    if typeof(center) ~= "Vector3" then
        return 0
    end
    radius = tonumber(radius) or SHOP_SCAN_NEAR_RADIUS
    local count = 0
    for _, item in ipairs(CollectionService:GetTagged("ShopItem")) do
        local displayName = item:GetAttribute("DisplayName") or item.Name
        if S.isShopWatchlisted(item.Name) or S.isShopWatchlisted(displayName) then
            local pos = S.getItemPosition(item)
            if typeof(pos) == "Vector3" and (pos - center).Magnitude <= radius then
                count = count + 1
            end
        end
    end
    return count
end

function S.collectNewWorkspaceShopItems(existingList)
    existingList = existingList or ShopWatch.worldItemList or {}
    local posIndex = S.buildShopPosIndex(existingList)
    local found = {}
    if #S.getCombinedShopWatchlist() == 0 then
        return found
    end

    for _, item in ipairs(CollectionService:GetTagged("ShopItem")) do
        local itemsFolder = Workspace:FindFirstChild("Items")
        if not itemsFolder or not item.Parent then
            continue
        end
        local top = item.Parent == itemsFolder and item or S.resolveWorldItem(item)
        if not top or top.Parent ~= itemsFolder or not S.hasShopItemTag(top) then
            continue
        end
        local displayName = top:GetAttribute("DisplayName") or top.Name
        if not (S.isShopWatchlisted(top.Name) or S.isShopWatchlisted(displayName)) then
            continue
        end
        local pos = S.getItemPosition(top)
        local key = S.getShopPosKey(pos)
        if not key or posIndex[key] then
            continue
        end
        posIndex[key] = true
        table.insert(found, {
            name = top.Name,
            displayName = displayName,
            pos = S.serializeVec3(pos),
            posKey = key,
            scannedAt = tick(),
            _itemRef = top,
        })
    end

    return found
end

function S.worldItemRecordToEntry(rec)
    if not rec then
        return nil
    end
    local pos = S.deserializeVec3(rec.pos)
    if typeof(pos) ~= "Vector3" then
        return nil
    end
    local posKey = rec.posKey or S.getShopPosKey(pos)
    local inst = rec._itemRef
    if inst and not inst.Parent then
        inst = nil
        rec._itemRef = nil
    end
    if not inst then
        pcall(function()
            for _, child in ipairs(CollectionService:GetTagged("ShopItem")) do
                if child.Name == rec.name and S.getShopPosKey(S.getItemPosition(child)) == posKey then
                    inst = child
                    rec._itemRef = child
                    break
                end
            end
        end)
    elseif typeof(pos) == "Vector3" then
        -- Keep saved record glued to the live instance even if it was dragged.
        local livePos = S.getItemPosition(inst)
        local liveKey = S.getShopPosKey(livePos)
        if liveKey and liveKey ~= posKey then
            rec.pos = S.serializeVec3(livePos)
            rec.posKey = liveKey
            pos = livePos
            posKey = liveKey
        end
    end
    -- Keep saved positions even when unloaded / far away.
    return {
        name = rec.name,
        displayName = rec.displayName or rec.name,
        pos = pos,
        item = inst,
        live = inst ~= nil and inst.Parent ~= nil,
        source = "WorldItemList",
        instanceKey = "pos:" .. tostring(posKey),
        buyPart = nil,
    }
end

function S.removeShopWorldItemAtPos(pos, opts)
    opts = type(opts) == "table" and opts or {}
    local key = opts.posKey or S.getShopPosKey(pos)
    if not key or not ShopWatch.worldItemList then
        return false
    end
    for i, rec in ipairs(ShopWatch.worldItemList) do
        if rec.posKey == key or S.getShopPosKey(rec.pos) == key then
            table.remove(ShopWatch.worldItemList, i)
            ShopWatch._purchasedInstances = ShopWatch._purchasedInstances or {}
            ShopWatch._purchasedInstances["pos:" .. key] = tick()
            if opts.save ~= false then
                S.saveShopWorldItemList()
            end
            return true
        end
    end
    return false
end

function S.removeShopWorldItemRecord(opts)
    opts = type(opts) == "table" and opts or {}
    local list = ShopWatch.worldItemList or {}
    if #list == 0 then
        return false
    end
    local item = opts.item
    local key = opts.posKey or S.getShopPosKey(opts.pos)
    local removed = false
    for i = #list, 1, -1 do
        local rec = list[i]
        local matchRef = item and rec._itemRef == item
        local matchPos = key and (rec.posKey == key or S.getShopPosKey(rec.pos) == key)
        if matchRef or matchPos then
            local posKey = rec.posKey or key
            table.remove(list, i)
            if posKey then
                ShopWatch._purchasedInstances = ShopWatch._purchasedInstances or {}
                ShopWatch._purchasedInstances["pos:" .. posKey] = tick()
            end
            removed = true
            if matchRef then
                break
            end
        end
    end
    if removed and opts.save ~= false then
        S.saveShopWorldItemList()
    end
    return removed
end

function S.pruneBoughtWorldItemRecords()
    -- Drop records whose live instance lost the [$] / ShopItem tag (bought).
    -- Keep records that are only unloaded (no live ref).
    local list = ShopWatch.worldItemList or {}
    if #list == 0 then
        return 0
    end
    local kept = {}
    local removed = 0
    for _, rec in ipairs(list) do
        local ref = rec._itemRef
        if ref and not ref.Parent then
            rec._itemRef = nil
            ref = nil
        end
        if ref and not S.hasShopItemTag(ref) then
            removed = removed + 1
            local posKey = rec.posKey or S.getShopPosKey(rec.pos)
            if posKey then
                ShopWatch._purchasedInstances = ShopWatch._purchasedInstances or {}
                ShopWatch._purchasedInstances["pos:" .. posKey] = tick()
            end
        else
            table.insert(kept, rec)
        end
    end
    if removed > 0 then
        ShopWatch.worldItemList = kept
        S.saveShopWorldItemList()
    end
    return removed
end

function S.refreshShopWatchHudNow()
    ShopWatch._cacheAt = 0
    ShopWatch._hudEntries = S.mergeShopWatchHudEntries(ShopWatch._cachedMatches or {})
    S.applyShopWatchHudSelection()
    pcall(function()
        S.syncShopWatchHudState({ forcePaint = true, alwaysPaint = true })
    end)
end

function S.handleShopWorldItemGone(item, opts)
    opts = type(opts) == "table" and opts or {}
    if opts.purchased == true then
        local top = item and (S.resolveWorldItem(item) or item) or nil
        local pos = opts.pos or (top and S.getItemPosition(top)) or nil
        local posKey = opts.posKey or S.getShopPosKey(pos)
        if top then
            pcall(function()
                ShopWatch._purchasedInstances = ShopWatch._purchasedInstances or {}
                ShopWatch._purchasedInstances[top:GetFullName()] = tick()
            end)
        end
        S.removeShopWorldItemRecord({
            item = top,
            pos = pos,
            posKey = posKey,
            save = true,
        })
    end
    S.refreshShopWatchHudNow()
end

function S.formatShopWorldListSummary()
    local n = #(ShopWatch.worldItemList or {})
    if n == 0 then
        return "World items: empty"
    end
    return string.format("World items: %d saved", n)
end

function S.getShopScanPerShopSeconds(shopCount)
    shopCount = math.max(tonumber(shopCount) or 1, 1)
    local perShop = SHOP_SCAN_TOTAL_BUDGET_SECONDS / shopCount
    return math.clamp(perShop, SHOP_SCAN_PER_SHOP_MIN, SHOP_SCAN_PER_SHOP_MAX)
end

function S.waitAtFortressShop(fortressRoot, pos, opts)
    opts = type(opts) == "table" and opts or {}
    pos = pos or S.getFortressShopPivot(fortressRoot)
    if typeof(pos) ~= "Vector3" then
        return
    end

    local seconds = tonumber(opts.seconds) or S.getShopScanPerShopSeconds(1)
    seconds = math.clamp(seconds, SHOP_SCAN_PER_SHOP_MIN, SHOP_SCAN_PER_SHOP_MAX)

    S.teleportNearShopPosition(pos, 4)
    task.spawn(function()
        pcall(function()
            if typeof(LocalPlayer.RequestStreamAroundAsync) == "function" then
                LocalPlayer:RequestStreamAroundAsync(pos, math.max(seconds, 0.5))
            end
        end)
    end)

    -- Wait until watched [$] count near this shop stops increasing (or budget ends).
    local deadline = tick() + seconds
    local lastCount = -1
    local stable = 0
    while tick() < deadline do
        task.wait(0.08)
        local count = S.countWatchlistedShopItemsNear(pos, SHOP_SCAN_NEAR_RADIUS)
        S.flushLiveWatchlistedShopItemsToWorldList({ save = false })
        if count > 0 and count == lastCount then
            stable = stable + 1
            if stable >= 3 then
                break
            end
        else
            stable = 0
            lastCount = count
        end
    end
    S.flushLiveWatchlistedShopItemsToWorldList({ save = false })
end

function S.loadShopDisplayCatalog()
    ShopWatch.fortressDisplay = ShopWatch.fortressDisplay or {}
    if not S.configHasFileApi() then
        return false
    end
    S.configEnsureFolder()
    local path = S.getShopCatalogFile()
    if typeof(isfile) == "function" and not isfile(path) then
        return false
    end

    local readOk, raw = pcall(readfile, path)
    if not readOk or type(raw) ~= "string" or raw == "" then
        return false
    end

    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodeOk or type(data) ~= "table" then
        return false
    end

    ShopWatch.fortressDisplay = {}
    for fortressName, entry in pairs(data.fortresses or {}) do
        if type(entry) == "table" and type(entry.items) == "table" then
            ShopWatch.fortressDisplay[fortressName] = {
                items = entry.items,
                pos = S.deserializeVec3(entry.pos),
                scannedAt = tonumber(entry.scannedAt) or 0,
            }
        end
    end
    ShopWatch._catalogRestockEnd = data.restockEndTime
    ShopWatch._catalogLoaded = true
    return true
end

function S.saveShopDisplayCatalog()
    if not S.configHasFileApi() then
        return false
    end
    S.configEnsureFolder()

    local timer = S.getGlobalShopRestockTimer()
    local fortresses = {}
    for fortressName, entry in pairs(ShopWatch.fortressDisplay or {}) do
        local items = entry.items or {}
        fortresses[fortressName] = {
            items = items,
            count = #items,
            expected = SHOP_DISPLAY_SLOT_COUNT,
            pos = S.serializeVec3(entry.pos),
            scannedAt = entry.scannedAt or tick(),
        }
    end

    local payload = {
        version = 1,
        updatedAt = tick(),
        restockEndTime = timer.endTime or ShopWatch._restockEndTime,
        slotCount = SHOP_DISPLAY_SLOT_COUNT,
        fortresses = fortresses,
    }

    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
    if ok then
        pcall(writefile, S.getShopCatalogFile(), encoded)
        return true
    end
    return false
end

function S.clearShopDisplayCatalog(persist)
    ShopWatch.fortressDisplay = {}
    if persist ~= false then
        S.saveShopDisplayCatalog()
    end
end

function S.getFortressShopModel(fortressRoot)
    if not fortressRoot then
        return nil
    end
    local fortress = fortressRoot:FindFirstChild("Fortress") or fortressRoot
    return fortress and fortress:FindFirstChild("Shop") or nil
end

function S.isFortressEnemyShop(fortressRoot)
    if not fortressRoot then
        return true
    end

    local shop = S.getFortressShopModel(fortressRoot)
    if not shop then
        return true
    end

    if shop:FindFirstChild("FakeRegister", true) then
        return true
    end

    local hasStockScreen = false
    for _, desc in ipairs(shop:GetDescendants()) do
        if desc.Name:find("StockScreen", 1, true) then
            hasStockScreen = true
            break
        end
    end

    if hasStockScreen then
        return false
    end

    if S.findBuyPartInContainer(shop) then
        return false
    end

    return true
end

function S.isFortressPlayerShop(fortressRoot)
    return not S.isFortressEnemyShop(fortressRoot)
end

function S.mergeFortressDisplayNames(existing, incoming)
    existing = existing or {}
    incoming = incoming or {}
    local seen = {}
    local out = {}

    local function push(name)
        local key = S.normalizeShopItemKey(name)
        if key == "" or seen[key] then
            return
        end
        seen[key] = true
        table.insert(out, name)
    end

    for _, name in ipairs(existing) do
        push(name)
    end
    for _, name in ipairs(incoming) do
        push(name)
    end
    return out
end

function S.countDisplaySlotName(list, name)
    local key = S.normalizeShopItemKey(name)
    if key == "" then
        return 0
    end
    local count = 0
    for _, slot in ipairs(list or {}) do
        if S.normalizeShopItemKey(slot) == key then
            count = count + 1
        end
    end
    return count
end

function S.mergeFortressDisplaySlots(existing, incoming)
    existing = existing or {}
    incoming = incoming or {}
    if #incoming == 0 then
        return existing
    end
    if #existing == 0 then
        return incoming
    end

    local merged = {}
    for _, name in ipairs(existing) do
        table.insert(merged, name)
    end

    for _, name in ipairs(incoming) do
        local want = S.countDisplaySlotName(incoming, name)
        local have = S.countDisplaySlotName(merged, name)
        while have < want and #merged < SHOP_DISPLAY_SLOT_COUNT do
            table.insert(merged, name)
            have = have + 1
        end
    end

    if #incoming > #merged then
        merged = {}
        for _, name in ipairs(incoming) do
            table.insert(merged, name)
        end
        for _, name in ipairs(existing) do
            if #merged >= SHOP_DISPLAY_SLOT_COUNT then
                break
            end
            local want = S.countDisplaySlotName(existing, name)
            local have = S.countDisplaySlotName(merged, name)
            while have < want and #merged < SHOP_DISPLAY_SLOT_COUNT do
                table.insert(merged, name)
                have = have + 1
            end
        end
    end

    return merged
end

function S.extractDisplaySlotNames(entries)
    local names = {}
    for _, entry in ipairs(entries or {}) do
        local label = entry.name or entry.displayName
        if label and label ~= "" then
            table.insert(names, label)
        end
    end
    return names
end

function S.getFortressShopBuyPosition(fortressRoot)
    local shopModel = S.getFortressShopModel(fortressRoot)
    if shopModel then
        local inner = shopModel:FindFirstChild("Shop")
        local buyArea = (inner and inner:FindFirstChild("BuyPart")) or shopModel:FindFirstChild("BuyPart", true)
        if buyArea then
            local bp = buyArea:FindFirstChild("BuyPart")
            if bp and bp:IsA("BasePart") then
                return bp.Position
            end
            if buyArea:IsA("BasePart") then
                return buyArea.Position
            end
        end
        local part = shopModel:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.Position
        end
    end
    return S.getFortressShopPivot(fortressRoot)
end

function S.countFortressShopSignals(fortressRoot)
    local stats = {
        stockScreens = 0,
        displayTexts = 0,
        shopItems = 0,
        hasBuyPart = false,
    }
    if not fortressRoot then
        return stats
    end

    local shopModel = S.getFortressShopModel(fortressRoot)
    if shopModel then
        if shopModel:FindFirstChild("BuyPart", true) then
            stats.hasBuyPart = true
        end
        for _, child in ipairs(shopModel:GetChildren()) do
            if child.Name == "StockScreen" then
                stats.stockScreens = stats.stockScreens + 1
                for _, ui in ipairs(child:GetDescendants()) do
                    if ui:IsA("TextLabel") or ui:IsA("TextButton") or ui:IsA("TextBox") then
                        if S.isStockScreenItemLabel(ui.Text) then
                            stats.displayTexts = stats.displayTexts + 1
                        end
                    end
                end
            end
        end
    end

    for _, item in ipairs(CollectionService:GetTagged("ShopItem")) do
        if item:IsDescendantOf(fortressRoot) then
            stats.shopItems = stats.shopItems + 1
        end
    end

    return stats
end

function S.isFortressShopLoaded(fortressRoot)
    local stats = S.countFortressShopSignals(fortressRoot)
    if stats.displayTexts >= 8 then
        return true
    end
    if stats.stockScreens >= 4 and stats.hasBuyPart then
        return true
    end
    if stats.shopItems >= 4 then
        return true
    end
    return false
end

function S.waitFortressShopStream(fortressRoot, pos, opts)
    opts = type(opts) == "table" and opts or {}
    local maxSeconds = tonumber(opts.maxSeconds) or 14
    local deadline = tick() + maxSeconds
    local standPos = pos or S.getFortressShopPivot(fortressRoot)

    local shopModel = S.getFortressShopModel(fortressRoot)
    if shopModel then
        pcall(function()
            ContentProvider:PreloadAsync({ shopModel })
        end)
    end

    while tick() < deadline do
        local buyPos = S.getFortressShopBuyPosition(fortressRoot)
        if typeof(buyPos) == "Vector3" then
            standPos = buyPos
        end

        S.teleportNearShopPosition(standPos, 4)
        pcall(function()
            S.requestStreamAround(standPos, math.min(4, maxSeconds))
        end)
        task.wait(0.45)

        local stats = S.countFortressShopSignals(fortressRoot)
        if stats.displayTexts >= 8 or stats.displayTexts >= SHOP_DISPLAY_SLOT_COUNT then
            task.wait(0.35)
            return true, S.countFortressShopSignals(fortressRoot)
        end
        if stats.stockScreens >= 4 and (stats.displayTexts > 0 or stats.shopItems > 0) then
            task.wait(0.5)
            return true, S.countFortressShopSignals(fortressRoot)
        end
        if stats.shopItems >= 8 then
            task.wait(0.35)
            return true, stats
        end
        if stats.hasBuyPart and stats.stockScreens >= 1 and (tick() + 2) >= deadline then
            return false, stats
        end
    end

    return false, S.countFortressShopSignals(fortressRoot)
end

function S.getFortressShopRoots(fortressRoot)
    local roots = {}
    if not fortressRoot then
        return roots
    end
    local fortress = fortressRoot:FindFirstChild("Fortress") or fortressRoot
    local shop = fortress and fortress:FindFirstChild("Shop")
    if not shop then
        return roots
    end
    table.insert(roots, shop)
    local inner = shop:FindFirstChild("Shop")
    if inner and inner ~= shop then
        table.insert(roots, inner)
    end
    return roots
end

function S.collectDisplayNamesFromStock(stock, fortressName)
    local names = {}
    fortressName = tostring(fortressName or "")

    local function pushEntry(entry)
        local label = entry.displayName or entry.name
        if type(label) == "string" and label ~= "" then
            table.insert(names, label)
        end
    end

    for _, entry in ipairs(stock or {}) do
        if entry.source == "StockScreen" or entry.source == "StockScreenItem" then
            pushEntry(entry)
        end
    end
    if #names > 0 then
        return names
    end

    for _, entry in ipairs(stock or {}) do
        if entry.fortress == fortressName or fortressName == "" then
            pushEntry(entry)
        end
    end
    return names
end

function S.collectPlayerGuiShopDisplayNames()
    local names = {}
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then
        return names
    end

    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("TextLabel") or gui:IsA("TextButton") then
            local text = tostring(gui.Text or "")
            if S.isStockScreenItemLabel(text) then
                local parent = gui.Parent
                local inShopUi = false
                while parent do
                    local n = string.lower(tostring(parent.Name or ""))
                    if n:find("shop", 1, true) or n:find("stock", 1, true) or n:find("armory", 1, true) then
                        inShopUi = true
                        break
                    end
                    parent = parent.Parent
                end
                if inShopUi then
                    table.insert(names, text)
                end
            end
        end
    end
    return names
end

function S.collectFortressShopDisplayNames(fortressRoot, stockFallback)
    local names = {}
    if not fortressRoot then
        return names
    end

    local fortressName = fortressRoot.Name
    local function addName(text)
        text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if S.isStockScreenItemLabel(text) then
            table.insert(names, text)
        end
    end

    local function addEntry(entry)
        if not entry then
            return
        end
        addName(entry.displayName or entry.name)
    end

    local shopModel = S.getFortressShopModel(fortressRoot)
    if shopModel then
        for _, child in ipairs(shopModel:GetChildren()) do
            if child.Name == "StockScreen" then
                for _, ui in ipairs(child:GetDescendants()) do
                    if ui:IsA("TextLabel") or ui:IsA("TextButton") or ui:IsA("TextBox") then
                        addName(ui.Text)
                    end
                    if CollectionService:HasTag(ui, "ShopItem") then
                        addEntry(S.buildShopWatchEntry(ui, "StockScreenItem", fortressName))
                    end
                    local attr = ui:GetAttribute("ItemName")
                        or ui:GetAttribute("DisplayName")
                        or ui:GetAttribute("Name")
                    if attr then
                        addName(attr)
                    end
                end
            end
        end
    end

    for _, shopRoot in ipairs(S.getFortressShopRoots(fortressRoot)) do
        for _, desc in ipairs(shopRoot:GetDescendants()) do
            if desc.Name == "StockScreen" or desc.Name:find("StockScreen", 1, true) then
                for _, ui in ipairs(desc:GetDescendants()) do
                    if ui:IsA("TextLabel") or ui:IsA("TextButton") or ui:IsA("TextBox") then
                        addName(ui.Text)
                    end
                    if CollectionService:HasTag(ui, "ShopItem") then
                        addEntry(S.buildShopWatchEntry(ui, "StockScreenItem", fortressName))
                    end
                end
            elseif desc.Name:match("^Slot") or desc.Name:match("ItemSlot") or desc.Name:match("StockSlot") then
                local attr = desc:GetAttribute("ItemName")
                    or desc:GetAttribute("DisplayName")
                    or desc:GetAttribute("Name")
                if attr then
                    addName(attr)
                end
                for _, ui in ipairs(desc:GetDescendants()) do
                    if ui:IsA("TextLabel") or ui:IsA("TextButton") then
                        addName(ui.Text)
                    end
                end
            end
        end
    end

    if #names == 0 then
        names = S.collectPlayerGuiShopDisplayNames()
    end
    if #names == 0 and stockFallback then
        names = S.collectDisplayNamesFromStock(stockFallback, fortressName)
    end

    return names
end

function S.stripFortressScannedStock(fortressName)
    local kept = {}
    local byKey = {}
    for _, snap in ipairs(ShopWatch.scannedStock or {}) do
        if snap.fortress ~= fortressName then
            table.insert(kept, snap)
            if snap.instanceKey then
                byKey[snap.instanceKey] = snap
            end
        end
    end
    ShopWatch.scannedStock = kept
    ShopWatch.scannedStockByKey = byKey
end

function S.applyFortressDisplayToScannedStock(fortressName, names, pos)
    fortressName = tostring(fortressName or "")
    if fortressName == "" then
        return
    end

    S.stripFortressScannedStock(fortressName)
    names = names or {}
    for idx, name in ipairs(names) do
        S.archiveScannedShopItem({
            instanceKey = string.format(
                "display:%s:%s:%d",
                S.normalizeShopItemKey(name),
                fortressName,
                idx
            ),
            name = name,
            displayName = name,
            pos = pos,
            fortress = fortressName,
            source = "DisplayCatalog",
            live = false,
        })
    end
end

function S.setFortressDisplayCatalog(fortressName, names, pos, opts)
    opts = type(opts) == "table" and opts or {}
    fortressName = tostring(fortressName or "")
    if fortressName == "" then
        return 0
    end

    names = names or {}
    ShopWatch.fortressDisplay = ShopWatch.fortressDisplay or {}
    local prev = ShopWatch.fortressDisplay[fortressName]
    local merged = opts.replace and names or S.mergeFortressDisplaySlots(prev and prev.items or {}, names)
    ShopWatch.fortressDisplay[fortressName] = {
        items = merged,
        pos = pos or (prev and prev.pos) or nil,
        scannedAt = tick(),
        enemy = opts.enemy == true,
    }
    S.applyFortressDisplayToScannedStock(fortressName, merged, ShopWatch.fortressDisplay[fortressName].pos)
    S.saveShopDisplayCatalog()
    return #merged
end

function S.removeFortressDisplayCatalog(fortressName, persist)
    fortressName = tostring(fortressName or "")
    if fortressName == "" or not ShopWatch.fortressDisplay then
        return
    end
    ShopWatch.fortressDisplay[fortressName] = nil
    if persist ~= false then
        S.saveShopDisplayCatalog()
    end
end

function S.pruneEnemyFortressCatalog()
    for fortressName, entry in pairs(ShopWatch.fortressDisplay or {}) do
        if entry.enemy then
            ShopWatch.fortressDisplay[fortressName] = nil
        end
    end
end

function S.hydrateScannedStockFromDisplayCatalog()
    ShopWatch.scannedStock = {}
    ShopWatch.scannedStockByKey = {}
    for fortressName, entry in pairs(ShopWatch.fortressDisplay or {}) do
        S.applyFortressDisplayToScannedStock(fortressName, entry.items or {}, entry.pos)
    end
end

function S.removeShopDisplayItem(fortressName, itemName, displayName)
    fortressName = tostring(fortressName or "")
    if fortressName == "" then
        return
    end

    local target = S.normalizeShopItemKey(displayName or itemName)
    if target == "" then
        return
    end

    local bucket = ShopWatch.fortressDisplay and ShopWatch.fortressDisplay[fortressName]
    if bucket and type(bucket.items) == "table" then
        for i, name in ipairs(bucket.items) do
            if S.normalizeShopItemKey(name) == target then
                table.remove(bucket.items, i)
                break
            end
        end
    end

    for _, snap in ipairs(ShopWatch.scannedStock or {}) do
        if snap.fortress == fortressName
            and S.normalizeShopItemKey(snap.name) == target
            and not S.isShopInstancePurchased(snap.instanceKey) then
            S.markShopWatchInstancePurchased(snap)
            break
        end
    end

    S.saveShopDisplayCatalog()
end

function S.formatShopDisplayCatalogSummary()
    local shopCount = 0
    local totalItems = 0
    local totalExpected = 0
    local parts = {}

    for fortressName, entry in pairs(ShopWatch.fortressDisplay or {}) do
        if entry.enemy then
            continue
        end
        shopCount = shopCount + 1
        local count = #(entry.items or {})
        totalItems = totalItems + count
        totalExpected = totalExpected + SHOP_DISPLAY_SLOT_COUNT
        local short = fortressName:gsub("Fortress_", "")
        local mark = count == SHOP_DISPLAY_SLOT_COUNT
            and tostring(SHOP_DISPLAY_SLOT_COUNT)
            or (tostring(count) .. "/" .. tostring(SHOP_DISPLAY_SLOT_COUNT))
        table.insert(parts, short .. " " .. mark)
    end

    table.sort(parts)
    if shopCount == 0 then
        return "Catalog: empty"
    end

    local totalMark = totalItems == totalExpected
        and tostring(totalItems)
        or (tostring(totalItems) .. "/" .. tostring(totalExpected))
    return string.format(
        "Catalog: %d shops | %s names (%d/shop) — %s",
        shopCount,
        totalMark,
        SHOP_DISPLAY_SLOT_COUNT,
        table.concat(parts, ", ")
    )
end

function S.getShopDisplayCatalogStatusLine()
    local shopCount = 0
    local totalItems = 0
    local bad = 0
    for _, entry in pairs(ShopWatch.fortressDisplay or {}) do
        shopCount = shopCount + 1
        local count = #(entry.items or {})
        totalItems = totalItems + count
        if count ~= SHOP_DISPLAY_SLOT_COUNT then
            bad = bad + 1
        end
    end
    if shopCount == 0 then
        return nil
    end
    local expected = shopCount * SHOP_DISPLAY_SLOT_COUNT
    if bad == 0 and totalItems == expected then
        return string.format("Saved %d shops | %d/%d display OK", shopCount, totalItems, expected)
    end
    return string.format("Saved %d shops | %d/%d display (!%d shops)", shopCount, totalItems, expected, bad)
end

function S.clearShopRescanPrompt()
    ShopWatch._needsRescanPrompt = false
end

function S.getShopRescanPromptLine()
    if ShopWatch._needsRescanPrompt == true then
        return "!! Restock — Scan shops again !!"
    end
    return nil
end

function S.getShopStockInstanceKey(entry)
    if not entry then
        return nil
    end
    if entry.instanceKey then
        return entry.instanceKey
    end
    if entry.item then
        return entry.item:GetFullName()
    end
    return string.format(
        "%s@%s@%s",
        tostring(entry.name or "?"),
        tostring(entry.fortress or "?"),
        tostring(entry.pos or "?")
    )
end

function S.archiveScannedShopItem(entry)
    if not entry then
        return
    end
    local instKey = S.getShopStockInstanceKey(entry)
    if not instKey or ShopWatch.scannedStockByKey[instKey] then
        return
    end
    local timer = S.getGlobalShopRestockTimer()
    local snap = {
        instanceKey = instKey,
        name = entry.name,
        displayName = entry.displayName or entry.name,
        cost = entry.cost,
        pos = entry.pos,
        fortress = entry.fortress,
        source = entry.source,
        restockEndTime = timer.endTime or ShopWatch._restockEndTime,
        _itemRef = entry.item,
    }
    ShopWatch.scannedStockByKey[instKey] = snap
    table.insert(ShopWatch.scannedStock, snap)
end

function S.snapshotToShopEntry(snap)
    if not snap then
        return nil
    end
    local item = snap._itemRef
    if item and not item.Parent then
        item = nil
    end
    return {
        instanceKey = snap.instanceKey,
        item = item,
        name = snap.name,
        displayName = snap.displayName or snap.name,
        cost = snap.cost,
        pos = snap.pos,
        source = snap.source or "scanned",
        fortress = snap.fortress,
        buyPart = nil,
        live = item ~= nil and item.Parent ~= nil,
    }
end

function S.isShopInstancePurchased(instKey)
    if not instKey or not ShopWatch._purchasedInstances then
        return false
    end
    return ShopWatch._purchasedInstances[instKey] ~= nil
end

function S.markShopWatchInstancePurchased(entry)
    local instKey = S.getShopStockInstanceKey(entry)
    if not instKey then
        return
    end
    ShopWatch._purchasedInstances = ShopWatch._purchasedInstances or {}
    ShopWatch._purchasedInstances[instKey] = tick()
end

function S.buildShopEntriesFromScannedStock()
    local out = {}
    for _, snap in ipairs(ShopWatch.scannedStock or {}) do
        if not S.isShopInstancePurchased(snap.instanceKey) then
            local entry = S.snapshotToShopEntry(snap)
            if entry then
                table.insert(out, entry)
            end
        end
    end
    return out
end

function S.groupShopHudEntries(flatEntries)
    local groups = {}
    local map = {}

    for _, entry in ipairs(flatEntries or {}) do
        local instKey = S.getShopStockInstanceKey(entry)
        if instKey and S.isShopInstancePurchased(instKey) then
            continue
        end
        local watchKey = S.getWatchlistKeyForItem(entry.name, entry.displayName)
        if not watchKey then
            continue
        end
        if not map[watchKey] then
            map[watchKey] = {
                watchKey = watchKey,
                name = entry.name,
                displayName = entry.displayName or entry.name,
                cost = entry.cost,
                fortress = entry.fortress,
                pos = entry.pos,
                qty = 0,
                instances = {},
                live = false,
                item = nil,
                buyPart = nil,
                fromMemory = entry.fromMemory == true,
            }
        end
        local group = map[watchKey]
        group.qty = group.qty + 1
        entry.instanceKey = instKey
        table.insert(group.instances, entry)
        if entry.cost and not group.cost then
            group.cost = entry.cost
        end
        if entry.live == true or (entry.item and entry.item.Parent) then
            group.live = true
            group.item = entry.item or group.item
            group.pos = entry.pos or group.pos
            group.buyPart = entry.buyPart or group.buyPart
            group.fortress = entry.fortress or group.fortress
        elseif not group.pos and entry.pos then
            group.pos = entry.pos
            group.fortress = entry.fortress or group.fortress
        end
    end

    for _, g in pairs(map) do
        if (g.qty or 0) > 0 then
            table.insert(groups, g)
        end
    end
    return groups, map
end

function S.applyStableHudEntryOrder(groups)
    groups = groups or {}
    local byKey = {}
    for _, g in ipairs(groups) do
        byKey[g.watchKey] = g
    end

    local ordered = {}
    local used = {}
    for _, watchKey in ipairs(ShopWatch._hudEntryOrder or {}) do
        local g = byKey[watchKey]
        if g and (g.qty or 0) > 0 then
            table.insert(ordered, g)
            used[watchKey] = true
        end
    end

    local newcomers = {}
    for watchKey, g in pairs(byKey) do
        if not used[watchKey] and (g.qty or 0) > 0 then
            table.insert(newcomers, watchKey)
        end
    end
    table.sort(newcomers, function(a, b)
        return tostring(byKey[a].displayName or a) < tostring(byKey[b].displayName or b)
    end)
    for _, watchKey in ipairs(newcomers) do
        table.insert(ordered, byKey[watchKey])
    end

    ShopWatch._hudEntryOrder = {}
    for _, g in ipairs(ordered) do
        table.insert(ShopWatch._hudEntryOrder, g.watchKey)
    end
    return ordered
end

function S.pruneShopWatchMemory()
    local timer = S.getGlobalShopRestockTimer()
    local currentEnd = timer.endTime
    local secs = timer.seconds

    if currentEnd and ShopWatch._restockEndTime and currentEnd ~= ShopWatch._restockEndTime then
        if S.didUiRestockTimerRollOver(ShopWatch._restockLastSeconds, secs) then
            S.onShopRestockCycle()
        end
    end
    if currentEnd then
        ShopWatch._restockEndTime = currentEnd
    end
    if secs ~= nil then
        ShopWatch._restockLastSeconds = secs
    end

    if not currentEnd then
        return
    end

    for key, entry in pairs(ShopWatch.memory) do
        if entry.restockEndTime and entry.restockEndTime ~= currentEnd then
            ShopWatch.memory[key] = nil
        end
    end
end

function S.rememberShopWatchSighting(entry, fortressName)
    if not entry then
        return
    end
    S.archiveShopWatchEntry(entry, nil, fortressName)
end

function S.archiveShopWatchEntry(entry, key, fortressName)
    if not entry then
        return
    end
    local watchName
    if not key then
        key, watchName = S.getWatchlistKeyForItem(entry.name, entry.displayName)
    else
        _, watchName = S.getWatchlistKeyForItem(entry.name, entry.displayName)
    end
    if not key then
        return
    end

    S.pruneShopWatchMemory()
    local timer = S.getGlobalShopRestockTimer()
    local pos = entry.pos
    if typeof(pos) ~= "Vector3" and entry.item then
        pos = S.getItemPosition(entry.item)
    end
    if typeof(pos) ~= "Vector3" then
        local existing = ShopWatch.memory[key]
        if existing and typeof(existing.pos) == "Vector3" then
            return
        end
        return
    end

    local cycleEnd = timer.endTime or ShopWatch._restockEndTime
    if timer.endTime then
        ShopWatch._restockEndTime = timer.endTime
    end

    ShopWatch.memory[key] = {
        watchKey = key,
        watchName = watchName,
        name = entry.name,
        displayName = entry.displayName or entry.name,
        pos = pos,
        fortress = fortressName or entry.fortress,
        cost = entry.cost,
        seenAt = tick(),
        restockEndTime = cycleEnd,
        buyPartPos = entry.buyPart and entry.buyPart:IsA("BasePart") and entry.buyPart.Position or nil,
    }
end

function S.buildShopWatchEntry(item, source, fortressName)
    if not item or not item.Parent then
        return nil
    end

    local name = item.Name
    local display = item:GetAttribute("DisplayName") or name
    local cost = item:GetAttribute("Cost")
    if typeof(cost) ~= "number" then
        cost = item:GetAttribute("Value")
    end

    return {
        item = item,
        name = name,
        displayName = display,
        cost = cost,
        pos = S.getItemPosition(item),
        source = source,
        fortress = fortressName,
        buyPart = nil,
        live = true,
    }
end

function S.isStockScreenItemLabel(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" or #text < 2 then
        return false
    end
    if text:match("^[Rr]estock") then
        return false
    end
    if text:match("^%d%d:%d%d") then
        return false
    end
    if text:match("^%$%d") or text:match("^%d+$") then
        return false
    end
    if text:match("^[xX]%d+$") then
        return false
    end
    local lower = string.lower(text)
    if lower == "tools" or lower == "weapons" or lower == "armors" or lower == "armour"
        or lower == "ammos" or lower == "ammo" or lower == "consumables" or lower == "medicals"
        or lower == "fuel" or lower == "stock" or lower == "shop" then
        return false
    end
    return true
end

local SHOP_CATALOG_NAME_SET = nil

function S.ensureShopCatalogNameSet()
    if SHOP_CATALOG_NAME_SET then
        return SHOP_CATALOG_NAME_SET
    end

    SHOP_CATALOG_NAME_SET = {
        [S.normalizeShopItemKey("GasCan")] = true,
        [S.normalizeShopItemKey("ReviveKit")] = true,
    }
    for _, names in pairs(SHOP_WATCH_CATALOG_BY_CATEGORY) do
        for _, name in ipairs(names) do
            SHOP_CATALOG_NAME_SET[S.normalizeShopItemKey(name)] = true
        end
    end
    return SHOP_CATALOG_NAME_SET
end

function S.isKnownShopCatalogName(name)
    local key = S.normalizeShopItemKey(name)
    if key == "" then
        return false
    end
    return S.ensureShopCatalogNameSet()[key] == true
end

function S.isWorldOreOrJunkItem(item)
    if not item then
        return true
    end

    local name = tostring(item.Name or "")
    if name == "Money_Sack" or name == "SoulOrb" then
        return true
    end
    if name:find("OreNode", 1, true) or name:find("WormNode", 1, true) then
        return true
    end
    if name:find("^Ore_", 1, false) or name:find("_Ore", 1, true) then
        return true
    end

    local cat = S.itemCategoryKey(item)
    if cat == "ore" or cat == "scrap" or cat == "corpse" or cat == "money" then
        return true
    end

    local class = string.lower(tostring(item:GetAttribute("Class") or ""))
    if class == "ore" or class == "scrap" then
        return true
    end

    return false
end

function S.flatDistanceXZ(a, b)
    if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
        return math.huge
    end
    return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

function S.buildFortressShopIndex()
    local index = {}
    S.iterFortressesInWindow(function(fortressRoot, pos)
        table.insert(index, {
            name = fortressRoot.Name,
            root = fortressRoot,
            pos = pos,
            rootPos = S.getInstancePosition(fortressRoot),
        })
    end)
    table.sort(index, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    return index
end

function S.hasShopItemTag(item)
    if not item then
        return false
    end
    local top = S.resolveWorldItem(item) or item
    return CollectionService:HasTag(top, "ShopItem")
end

function S.isWorkspaceShopStockItem(item)
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder or not item then
        return false
    end
    local top = S.resolveWorldItem(item)
    if not top or top.Parent ~= itemsFolder then
        return false
    end
    if not (top:IsA("Model") or top:IsA("BasePart") or top:IsA("Tool")) then
        return false
    end
    return S.hasShopItemTag(top)
end

function S.findFortressForShopItemPos(pos, index, maxRadius)
    maxRadius = tonumber(maxRadius) or SHOP_FORTRESS_ASSIGN_RADIUS
    if typeof(pos) ~= "Vector3" or not index or #index == 0 then
        return nil, nil, math.huge
    end

    local bestName, bestNode, bestDist = nil, nil, math.huge
    local secondDist = math.huge
    for _, node in ipairs(index) do
        local nodeDist = math.huge
        if typeof(node.pos) == "Vector3" then
            nodeDist = math.min(nodeDist, S.flatDistanceXZ(pos, node.pos))
        end
        if typeof(node.rootPos) == "Vector3" then
            nodeDist = math.min(nodeDist, S.flatDistanceXZ(pos, node.rootPos))
        end
        if nodeDist < bestDist then
            secondDist = bestDist
            bestDist = nodeDist
            bestName = node.name
            bestNode = node
        elseif nodeDist < secondDist then
            secondDist = nodeDist
        end
    end

    if not bestName or bestDist > maxRadius then
        return nil, nil, bestDist
    end
    if secondDist < math.huge and (secondDist - bestDist) < SHOP_FORTRESS_ASSIGN_MIN_LEAD then
        return nil, nil, bestDist
    end
    return bestName, bestNode, bestDist
end

function S.countFortressShopSlotsLoaded(fortressRoot, pos, fortressIndex, fortressName)
    fortressName = fortressName or (fortressRoot and fortressRoot.Name) or ""
    fortressIndex = fortressIndex or S.buildFortressShopIndex()
    local seen = {}
    local count = 0

    local function mark(inst)
        if not inst then
            return false
        end
        local key = inst:GetFullName()
        if seen[key] then
            return false
        end
        seen[key] = true
        return true
    end

    local function considerItem(item, assignedFortress)
        if not item or assignedFortress ~= fortressName then
            return
        end
        if mark(item) then
            count = count + 1
        end
    end

    local itemsFolder = Workspace:FindFirstChild("Items")
    if itemsFolder then
        for _, child in ipairs(itemsFolder:GetChildren()) do
            if S.isWorkspaceShopStockItem(child) then
                local itemPos = S.getItemPosition(child)
                if typeof(itemPos) == "Vector3" then
                    considerItem(child, S.findFortressForShopItemPos(itemPos, fortressIndex))
                end
            end
        end
    end

    if fortressRoot then
        pcall(function()
            for _, desc in ipairs(fortressRoot:GetDescendants()) do
                if CollectionService:HasTag(desc, "ShopItem") then
                    considerItem(desc, fortressName)
                elseif desc:IsA("Model") or desc:IsA("Tool") then
                    if S.isKnownShopCatalogName(desc.Name) then
                        considerItem(desc, fortressName)
                    end
                end
            end
        end)
    end

    return count
end

function S.collectFortressShopScan(fortressRoot, fortressName, fortressIndex)
    fortressName = tostring(fortressName or (fortressRoot and fortressRoot.Name) or "")
    fortressIndex = fortressIndex or S.buildFortressShopIndex()
    local combined = {}
    local seenInst = {}

    local function addEntry(entry)
        if not entry then
            return
        end
        local instKey = entry.item and entry.item:GetFullName()
            or entry.instanceKey
            or (tostring(entry.name or entry.displayName) .. ":" .. tostring(entry.source or ""))
        if seenInst[instKey] then
            return
        end
        seenInst[instKey] = true
        entry.fortress = fortressName
        if not entry.pos and entry.item then
            entry.pos = S.getItemPosition(entry.item)
        end
        table.insert(combined, entry)
    end

    for _, entry in ipairs((S.collectFortressWorkspaceItems(fortressName, fortressIndex))) do
        addEntry(entry)
    end

    if fortressRoot then
        local shopSeen = {}
        local shopList = {}
        S.collectFortressShopStock(fortressRoot, shopSeen, shopList)
        for _, entry in ipairs(shopList) do
            if entry.item then
                addEntry(entry)
            end
        end
    end

    S.sortShopEntriesByPivot(combined)
    return combined, S.extractDisplaySlotNames(combined)
end

function S.countWorkspaceShopItemsNear(center, radius)
    radius = tonumber(radius) or SHOP_FORTRESS_ASSIGN_RADIUS
    local count = 0
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder or typeof(center) ~= "Vector3" then
        return 0
    end

    for _, child in ipairs(itemsFolder:GetChildren()) do
        if S.isWorkspaceShopStockItem(child) then
            local pos = S.getItemPosition(child)
            if pos and S.flatDistanceXZ(pos, center) <= radius then
                count = count + 1
            end
        end
    end
    return count
end

function S.sortShopEntriesByPivot(entries)
    table.sort(entries, function(a, b)
        local pa = a.pos
        local pb = b.pos
        if typeof(pa) ~= "Vector3" or typeof(pb) ~= "Vector3" then
            return tostring(a.displayName or a.name) < tostring(b.displayName or b.name)
        end
        if math.abs(pa.X - pb.X) > 1 then
            return pa.X < pb.X
        end
        if math.abs(pa.Z - pb.Z) > 1 then
            return pa.Z < pb.Z
        end
        if math.abs(pa.Y - pb.Y) > 0.25 then
            return pa.Y > pb.Y
        end
        return tostring(a.displayName or a.name) < tostring(b.displayName or b.name)
    end)
    return entries
end

function S.collectFortressWorkspaceItems(fortressName, fortressIndex)
    fortressName = tostring(fortressName or "")
    fortressIndex = fortressIndex or S.buildFortressShopIndex()
    local entries = {}
    local names = {}
    local seen = {}

    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder or fortressName == "" then
        return entries, names
    end

    local function pushItem(item)
        if not S.isWorkspaceShopStockItem(item) then
            return
        end
        local key = item:GetFullName()
        if seen[key] then
            return
        end

        local pos = S.getItemPosition(item)
        if typeof(pos) ~= "Vector3" then
            return
        end

        local assigned = S.findFortressForShopItemPos(pos, fortressIndex)
        if assigned ~= fortressName then
            return
        end

        seen[key] = true
        local entry = S.buildShopWatchEntry(item, "WorkspaceItems", fortressName)
        if not entry then
            return
        end
        entry.pos = pos
        entry.fortress = fortressName
        table.insert(entries, entry)
    end

    for _, child in ipairs(itemsFolder:GetChildren()) do
        pushItem(child)
    end

    for _, item in ipairs(CollectionService:GetTagged("ShopItem")) do
        if item:IsDescendantOf(itemsFolder) then
            pushItem(item)
        end
    end

    S.sortShopEntriesByPivot(entries)
    for _, entry in ipairs(entries) do
        table.insert(names, entry.name or entry.displayName)
    end
    return entries, names
end

function S.collectAllFortressesWorkspaceItems(fortressIndex)
    fortressIndex = fortressIndex or S.buildFortressShopIndex()
    local byFortress = {}
    for _, node in ipairs(fortressIndex) do
        byFortress[node.name] = { entries = {}, names = {} }
    end

    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder then
        return byFortress, fortressIndex
    end

    local seen = {}
    local function pushItem(item)
        if not S.isWorkspaceShopStockItem(item) then
            return
        end
        local key = item:GetFullName()
        if seen[key] then
            return
        end

        local pos = S.getItemPosition(item)
        if typeof(pos) ~= "Vector3" then
            return
        end

        local fortressName = S.findFortressForShopItemPos(pos, fortressIndex)
        if not fortressName or not byFortress[fortressName] then
            return
        end

        seen[key] = true
        local entry = S.buildShopWatchEntry(item, "WorkspaceItems", fortressName)
        if not entry then
            return
        end
        entry.pos = pos
        entry.fortress = fortressName
        table.insert(byFortress[fortressName].entries, entry)
    end

    for _, child in ipairs(itemsFolder:GetChildren()) do
        pushItem(child)
    end
    for _, item in ipairs(CollectionService:GetTagged("ShopItem")) do
        if item:IsDescendantOf(itemsFolder) then
            pushItem(item)
        end
    end

    for fortressName, bucket in pairs(byFortress) do
        S.sortShopEntriesByPivot(bucket.entries)
        bucket.names = S.extractDisplaySlotNames(bucket.entries)
        bucket.pos = nil
        for _, node in ipairs(fortressIndex) do
            if node.name == fortressName then
                bucket.pos = node.pos
                break
            end
        end
    end

    return byFortress, fortressIndex
end

function S.collectStockScreenShopHints(shopModel, seen, list, fortressName)
    if not shopModel then
        return
    end

    local shopRoots = { shopModel }
    local inner = shopModel:FindFirstChild("Shop")
    if inner and inner ~= shopModel then
        table.insert(shopRoots, inner)
    end

    for _, root in ipairs(shopRoots) do
        for _, desc in ipairs(root:GetDescendants()) do
            if desc.Name ~= "StockScreen" and not desc.Name:find("StockScreen", 1, true) then
                continue
            end

            local pos = S.getItemPosition(desc)
            for _, child in ipairs(desc:GetDescendants()) do
                if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
                    local text = tostring(child.Text or "")
                    if S.isStockScreenItemLabel(text) then
                        local key = "screen:" .. S.normalizeShopItemKey(text) .. ":" .. tostring(fortressName or "")
                        if not seen[key] then
                            seen[key] = true
                            table.insert(list, {
                                item = nil,
                                name = text,
                                displayName = text,
                                cost = nil,
                                pos = pos,
                                source = "StockScreen",
                                fortress = fortressName,
                                buyPart = nil,
                                live = false,
                            })
                        end
                    end
                elseif CollectionService:HasTag(child, "ShopItem") then
                    local key = child:GetFullName()
                    if not seen[key] then
                        seen[key] = true
                        local entry = S.buildShopWatchEntry(child, "StockScreenItem", fortressName)
                        if entry then
                            table.insert(list, entry)
                        end
                    end
                end
            end
        end
    end
end

function S.collectFortressShopStock(fortressRoot, seen, list)
    seen = seen or {}
    list = list or {}
    if not fortressRoot then
        return list
    end

    local fortress = fortressRoot:FindFirstChild("Fortress") or fortressRoot
    local shop = fortress and fortress:FindFirstChild("Shop")
    if not shop then
        return list
    end

    local fortressName = fortressRoot.Name
    pcall(function()
        for _, desc in ipairs(shop:GetDescendants()) do
            if CollectionService:HasTag(desc, "ShopItem") then
                local key = desc:GetFullName()
                if not seen[key] then
                    seen[key] = true
                    local entry = S.buildShopWatchEntry(desc, "FortressShop", fortressName)
                    if entry then
                        table.insert(list, entry)
                    end
                end
            elseif CollectionService:HasTag(desc, "ShopTable") then
                local itemsFolder = desc:FindFirstChild("Items")
                if itemsFolder then
                    for _, child in ipairs(itemsFolder:GetChildren()) do
                        local key = child:GetFullName()
                        if not seen[key] then
                            seen[key] = true
                            local entry = S.buildShopWatchEntry(child, "FortressShopTable", fortressName)
                            if entry then
                                table.insert(list, entry)
                            end
                        end
                    end
                end
            end
        end
    end)

    S.collectStockScreenShopHints(shop, seen, list, fortressName)
    return list
end

function S.collectLoadedFortressShopStock(seen, list)
    S.iterFortressesInWindow(function(fortressRoot)
        S.collectFortressShopStock(fortressRoot, seen, list)
    end)
end

function S.scanFortressShopVisit(fortressRoot, pos, fortressIndex)
    if not fortressRoot then
        return {}
    end
    pos = pos or S.getFortressShopPivot(fortressRoot)
    if typeof(pos) ~= "Vector3" then
        return {}
    end

    fortressIndex = fortressIndex or S.buildFortressShopIndex()
    local fortressName = fortressRoot.Name

    local perShopSeconds = S.getShopScanPerShopSeconds(1)
    S.teleportNearShopPosition(pos, 4)
    pcall(function()
        S.requestStreamAround(pos, perShopSeconds)
    end)
    task.wait(0.2)

    local deadline = tick() + perShopSeconds
    local lastCount = 0
    local stablePasses = 0
    while tick() < deadline do
        local count = S.countFortressShopSlotsLoaded(fortressRoot, pos, fortressIndex, fortressName)
        if count >= SHOP_DISPLAY_SLOT_COUNT then
            break
        end
        if count > lastCount then
            lastCount = count
            stablePasses = 0
        else
            stablePasses = stablePasses + 1
            if stablePasses >= 10 and count >= (SHOP_DISPLAY_SLOT_COUNT - 4) then
                break
            end
            if stablePasses >= 18 and count > 0 then
                break
            end
        end
        pcall(function()
            S.requestStreamAround(pos, 3)
        end)
        task.wait(0.45)
    end

    local entries = S.collectFortressShopScan(fortressRoot, fortressName, fortressIndex)
    local slotCount = #entries
    if slotCount == 0 then
        S.hubLog(
            string.format(
                "Shop scan empty @ %s near=%d",
                tostring(fortressName),
                S.countFortressShopSlotsLoaded(fortressRoot, pos, fortressIndex, fortressName)
            )
        )
    else
        local sample = entries[1].displayName or entries[1].name or "?"
        S.hubLog(
            string.format(
                "Shop scan @ %s: %d slots (e.g. %s)",
                tostring(fortressName),
                slotCount,
                tostring(sample)
            )
        )
    end
    return entries
end

function S.restorePlayerCFrame(cf)
    local root = S.getRoot()
    if root and cf then
        root.CFrame = cf
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

function S.getFortressShopPivot(fortressRoot)
    if not fortressRoot then
        return nil
    end
    local fortress = fortressRoot:FindFirstChild("Fortress") or fortressRoot
    local shop = fortress:FindFirstChild("Shop")
    if not shop then
        return S.getInstancePosition(fortressRoot)
    end
    local ok, pos = pcall(function()
        if shop:IsA("Model") then
            return shop:GetPivot().Position
        end
        if shop:IsA("BasePart") then
            return shop.Position
        end
        local part = shop:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end)
    if ok and typeof(pos) == "Vector3" then
        return pos
    end
    return S.getInstancePosition(fortressRoot)
end

function S.iterFortressesInWindow(callback)
    if type(callback) ~= "function" then
        return
    end
    local chunks = Workspace:FindFirstChild("Chunks")
    local fortresses = chunks and chunks:FindFirstChild("Fortresses")
    if not fortresses then
        return
    end

    local startM = tonumber(Autofarm.mapStartMeters)
    local endM = tonumber(Autofarm.mapEndMeters)
    if not startM or not endM then
        local drillM = S.getDrillDepthMeters() or 0
        startM, endM = S.computeAutofarmDepthWindow(drillM)
    end

    local rangeStuds = S.getShopWatchRangeStuds()
    for _, child in ipairs(fortresses:GetChildren()) do
        if child:IsA("Model") and string.find(child.Name, "Fortress", 1, true) then
            if S.isFortressEnemyShop(child) then
                continue
            end
            local pos = S.getFortressShopPivot(child)
            if pos then
                local depthM = S.computeDepthMetersDump(pos)
                if depthM >= startM - 500 and depthM <= endM + 500 then
                    if S.getFlatDistanceFromPosition(pos) <= rangeStuds then
                        callback(child, pos, depthM)
                    end
                end
            end
        end
    end
end

function S.queueFortressStreams()
    ShopWatch._streamQueue = {}
    ShopWatch._streamQueueIdx = 1
    S.iterFortressesInWindow(function(_, pos)
        table.insert(ShopWatch._streamQueue, pos)
    end)
    return #ShopWatch._streamQueue
end

function S.streamNextFortressInQueue()
    local q = ShopWatch._streamQueue
    if not q or #q == 0 then
        S.queueFortressStreams()
        q = ShopWatch._streamQueue
    end
    local idx = ShopWatch._streamQueueIdx or 1
    if idx > #q then
        ShopWatch._streamQueueIdx = 1
        ShopWatch._bgScanProgress = { idx = 0, total = #q }
        return false, true
    end
    pcall(function()
        S.requestStreamAround(q[idx], 0.35)
    end)
    ShopWatch._streamQueueIdx = idx + 1
    ShopWatch._bgScanProgress = { idx = idx, total = #q }
    return true, ShopWatch._streamQueueIdx > #q
end

function S.streamShopsInWindow()
    local ok, done = S.streamNextFortressInQueue()
    return ok, done
end

function S.findBuyPartInContainer(container)
    if not container then
        return nil
    end
    for _, desc in ipairs(container:GetDescendants()) do
        if desc:IsA("BasePart") and CollectionService:HasTag(desc, "BuyPart") then
            return desc
        end
    end
    return nil
end

function S.findClosestBuyPartNear(position, maxDist)
    if typeof(position) ~= "Vector3" then
        return nil
    end
    maxDist = tonumber(maxDist) or 120
    local best, bestDist = nil, maxDist
    pcall(function()
        for _, bp in ipairs(CollectionService:GetTagged("BuyPart")) do
            if bp:IsA("BasePart") and bp:IsDescendantOf(Workspace) and bp.Parent then
                local dist = (bp.Position - position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    best = bp
                end
            end
        end
    end)
    return best
end

function S.findBuyPartNearItem(item, hintPos)
    local itemPos = hintPos
    if item and typeof(itemPos) ~= "Vector3" then
        itemPos = S.getItemPosition(item)
    end

    if item then
        local register = item:FindFirstAncestor("Register")
        if register and register.Parent then
            local bp = S.findBuyPartInContainer(register.Parent)
            if bp then
                return bp
            end
        end

        for _, shopTable in ipairs(CollectionService:GetTagged("ShopTable")) do
            if item:IsDescendantOf(shopTable) then
                local bp = S.findBuyPartInContainer(shopTable)
                if bp then
                    return bp
                end
            end
        end

        local shop = item:FindFirstAncestor("Shop")
        if shop then
            local bp = S.findBuyPartInContainer(shop)
            if bp then
                return bp
            end
        end

        local current = item.Parent
        while current and current ~= Workspace do
            if current:FindFirstChild("Register") then
                local bp = S.findBuyPartInContainer(current)
                if bp then
                    return bp
                end
            end
            if CollectionService:HasTag(current, "ShopTable") then
                local bp = S.findBuyPartInContainer(current)
                if bp then
                    return bp
                end
            end
            current = current.Parent
        end
    end

    if typeof(itemPos) == "Vector3" then
        local bp = S.findClosestBuyPartNear(itemPos, 120)
        if bp then
            return bp
        end
    end

    local root = S.getRoot()
    if root then
        return S.findClosestBuyPartNear(root.Position, 80)
    end

    return nil
end

function S.findBuyPartForShopItem(item, hintPos)
    return S.findBuyPartNearItem(item, hintPos)
end

function S.findShopRegisterForBuyPart(buyPart)
    if not buyPart then
        return nil
    end
    local container = buyPart.Parent
    if container then
        local reg = container:FindFirstChild("Register")
        if reg then
            return reg
        end
    end
    local reg = buyPart:FindFirstAncestor("Register")
    if reg then
        return reg
    end
    return nil
end

function S.findShopBuyArea(item, hintPos)
    local buyPart, register

    if item then
        local shop = item:FindFirstAncestor("Shop")
        if shop then
            local buyArea = shop:FindFirstChild("BuyPart", true)
            if not buyArea then
                local inner = shop:FindFirstChild("Shop")
                buyArea = inner and inner:FindFirstChild("BuyPart")
            end
            if buyArea then
                register = buyArea:FindFirstChild("Register")
                buyPart = buyArea:FindFirstChild("BuyPart")
                if buyPart and not buyPart:IsA("BasePart") then
                    buyPart = nil
                end
                if not buyPart then
                    buyPart = S.findBuyPartInContainer(buyArea)
                end
            end
        end
    end

    if not buyPart then
        buyPart = S.findBuyPartNearItem(item, hintPos)
    end
    if buyPart and not register then
        register = S.findShopRegisterForBuyPart(buyPart)
    end

    return buyPart, register
end

function S.getShopBuyPartPlaceCFrame(buyPart)
    if not buyPart or not buyPart:IsA("BasePart") then
        return nil
    end
    local topOffset = (buyPart.Size.Y * 0.5) + 0.65
    return buyPart.CFrame * CFrame.new(0, topOffset, 0)
end

function S.isNearPosition(pos, range)
    local root = S.getRoot()
    if not root or typeof(pos) ~= "Vector3" then
        return false
    end
    return (root.Position - pos).Magnitude <= (range or 20)
end

function S.waitForDragLockOnItem(item, timeout)
    timeout = tonumber(timeout) or 1.2
    local knit = S.getKnit()
    local drag = knit and knit.GetController("DragController")
    if not drag then
        return false
    end

    if Services.DragService then
        pcall(function()
            Services.DragService:Request(item)
        end)
    end

    if drag.TryLockTarget then
        pcall(function()
            drag:TryLockTarget(item)
        end)
    end

    if drag.LockedTarget == item then
        return true
    end

    local deadline = tick() + timeout
    while tick() < deadline do
        if drag.LockedTarget == item then
            return true
        end
        if drag.TryLockTarget then
            pcall(function()
                drag:TryLockTarget(item)
            end)
        end
        task.wait(0.02)
    end

    return drag.LockedTarget == item
end

function S.placeShopItemOnBuyPart(item, buyPart)
    if not item or not item.Parent or not buyPart or not buyPart.Parent then
        return false
    end

    local placeCf = S.getShopBuyPartPlaceCFrame(buyPart)
    if not placeCf then
        return false
    end

    if S.isItemWelded(item) then
        local itemPos = S.getItemPosition(item)
        if itemPos and (itemPos - buyPart.Position).Magnitude <= 8 then
            return true
        end
    end

    pcall(function()
        if Services.ToolService then
            Services.ToolService:UnequipTool()
        end
    end)
    task.wait(0.04)

    local itemPos = S.getItemPosition(item) or buyPart.Position
    if not S.isNearPosition(itemPos, 12) then
        S.teleportNearShopPosition(itemPos, 3)
        task.wait(0.05)
    end

    if not S.waitForDragLockOnItem(item, 1.2) then
        S.setDragTarget(item)
        task.wait(0.03)
    end

    S.moveItemToCFrame(item, placeCf)

    local knit = S.getKnit()
    local drag = knit and knit.GetController("DragController")
    if drag and drag.MainAttach then
        pcall(function()
            drag.MainAttach.WorldCFrame = placeCf
        end)
    end
    task.wait(0.06)

    local welded = false
    if Services.DragService then
        local ok, result = pcall(function()
            return Services.DragService:Weld(item)
        end)
        if ok then
            if typeof(result) == "table" and result.andThen then
                local finished = false
                local weldResult = nil
                result:andThen(function(r)
                    weldResult = r
                    finished = true
                end):catch(function()
                    finished = true
                end)
                local waitUntil = tick() + 1
                while not finished and tick() < waitUntil do
                    task.wait(0.02)
                end
                welded = weldResult == "attached" or S.isItemWelded(item)
            else
                welded = result == "attached" or result == "detached" or S.isItemWelded(item)
            end
        end
    end

    if drag and drag.Weld then
        pcall(function()
            drag:Weld()
        end)
        task.wait(0.08)
        welded = welded or S.isItemWelded(item)
    end

    if not welded then
        S.moveItemToCFrame(item, placeCf)
        task.wait(0.04)
        if drag and drag.Weld then
            pcall(function()
                drag:Weld()
            end)
            task.wait(0.06)
            welded = S.isItemWelded(item)
        end
    end

    if drag and drag.ReleaseLockedTarget then
        pcall(function()
            drag:ReleaseLockedTarget()
        end)
    end
    if Services.DragService then
        pcall(function()
            Services.DragService:Cancel()
        end)
    end

    return welded or S.isItemWelded(item)
end

function S.clickShopRegister(register, buyPart)
    register = register or S.findShopRegisterForBuyPart(buyPart)
    buyPart = buyPart or (register and S.findBuyPartInContainer(register.Parent))

    local knit = S.getKnit()
    local drag = knit and knit.GetController("DragController")
    if drag and drag.SetHoveredRegister and register and buyPart then
        pcall(function()
            drag:SetHoveredRegister(register, buyPart)
        end)
    end

    local bought = false
    if Services.ShopService and buyPart then
        bought = pcall(function()
            Services.ShopService:Buy(buyPart)
        end)
    end

    if register then
        local cd = register:FindFirstChild("ClickDetector", true)
        if cd then
            pcall(function()
                if typeof(fireclickdetector) == "function" then
                    fireclickdetector(cd)
                else
                    cd:FireClick(LocalPlayer)
                end
            end)
            bought = true
        end
    end

    return bought
end

function S.performShopPurchase(item, buyPart, register)
    if not item or not item.Parent then
        return false, "Item not loaded"
    end
    if not buyPart then
        buyPart, register = S.findShopBuyArea(item)
    end
    if not buyPart then
        return false, "BuyPart not found"
    end
    register = register or S.findShopRegisterForBuyPart(buyPart)

    if not S.placeShopItemOnBuyPart(item, buyPart) then
        S.notify("Shop", "Could not place item on BuyPart", 4)
    end
    task.wait(0.04)

    local ok = S.clickShopRegister(register, buyPart)
    return ok, ok and "Purchased" or "Register click failed"
end

function S.getFloorYBelow(position, maxDrop)
    maxDrop = tonumber(maxDrop) or 16
    if typeof(position) ~= "Vector3" then
        return nil
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local char = LocalPlayer.Character
    if char then
        params.FilterDescendantsInstances = { char }
    end

    local origin = position + Vector3.new(0, 3, 0)
    local result = Workspace:Raycast(origin, Vector3.new(0, -maxDrop, 0), params)
    if result then
        return result.Position.Y
    end

    return position.Y
end

function S.teleportNearShopPosition(position, standOffset)
    local root = S.getRoot()
    if not root or typeof(position) ~= "Vector3" then
        return false
    end

    standOffset = standOffset or 3
    local floorY = S.getFloorYBelow(position, 18)
    local y = (floorY or position.Y) + standOffset
    root.CFrame = CFrame.new(position.X, y, position.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    return true
end

-- Light scan: workspace.Items (WorldPivot fortress assign) + ShopTable + loaded fortress shops.
function S.collectVisibleShopStock()
    local seen = {}
    local list = {}

    local function addEntry(entry)
        if not entry then
            return
        end
        local instKey = entry.item and entry.item:GetFullName() or nil
        local key = instKey or ((entry.fortress or "") .. ":" .. tostring(entry.displayName or entry.name))
        if seen[key] then
            return
        end
        seen[key] = true
        table.insert(list, entry)
    end

    pcall(function()
        local byFortress = S.collectAllFortressesWorkspaceItems()
        for _, bucket in pairs(byFortress) do
            for _, entry in ipairs(bucket.entries or {}) do
                addEntry(entry)
            end
        end
    end)

    pcall(function()
        for _, item in ipairs(CollectionService:GetTagged("ShopItem")) do
            if item:IsDescendantOf(Workspace) and S.isWorkspaceShopStockItem(item) then
                local pos = S.getItemPosition(item)
                local fortressName = S.findFortressForShopItemPos(pos, S.buildFortressShopIndex())
                addEntry(S.buildShopWatchEntry(item, "Items", fortressName))
            end
        end
    end)

    pcall(function()
        for _, shopTable in ipairs(CollectionService:GetTagged("ShopTable")) do
            local itemsFolder = shopTable:FindFirstChild("Items")
            if itemsFolder then
                for _, child in ipairs(itemsFolder:GetChildren()) do
                    addEntry(S.buildShopWatchEntry(child, "ShopTable"))
                end
            end
        end
    end)

    pcall(function()
        local extraSeen = {}
        local extraList = {}
        S.collectLoadedFortressShopStock(extraSeen, extraList)
        for _, entry in ipairs(extraList) do
            addEntry(entry)
        end
    end)

    return list
end

function S.mergeShopWatchHudEntries(liveMatches)
    S.pruneShopWatchMemory()
    local timer = S.getGlobalShopRestockTimer()
    if not ShopWatch._worldListLoaded then
        S.loadShopWorldItemList()
    end

    local map = {}
    local function ensureGroup(watchKey, watchName, rawName)
        if not map[watchKey] then
            map[watchKey] = {
                watchKey = watchKey,
                name = rawName or watchName,
                displayName = S.formatShopDisplayLabel(watchName or rawName),
                cost = nil,
                qty = 0,
                pos = nil,
                live = false,
                item = nil,
                buyPart = nil,
                instances = {},
            }
        end
        return map[watchKey]
    end

    local function recountGroup(group)
        group.qty = 0
        for _, inst in ipairs(group.instances or {}) do
            if not S.isShopInstancePurchased(S.getShopStockInstanceKey(inst)) then
                group.qty = group.qty + 1
            end
        end
        return group.qty
    end

    -- Only update positions of already-saved instances (never create new ones from HUD refresh / drag).
    S.flushLiveWatchlistedShopItemsToWorldList({ save = false, allowCreate = false })
    S.pruneBoughtWorldItemRecords()
    S.dedupeShopWorldItemList()

    local seenPosKeys = {}
    for _, rec in ipairs(ShopWatch.worldItemList or {}) do
        local posKey = rec.posKey or S.getShopPosKey(rec.pos)
        if posKey and seenPosKeys[posKey] then
            continue
        end
        if posKey then
            seenPosKeys[posKey] = true
        end
        -- Only keep / show records that still have [$] when live; unloaded saved ok.
        if rec._itemRef and rec._itemRef.Parent and not S.hasShopItemTag(rec._itemRef) then
            continue
        end
        local watchKey, watchName = S.getWatchlistKeyForItem(rec.name, rec.displayName)
        if not watchKey then
            continue
        end
        local entry = S.worldItemRecordToEntry(rec)
        if not entry then
            continue
        end
        if entry.item and entry.item.Parent and not S.hasShopItemTag(entry.item) then
            S.removeShopWorldItemRecord({ item = entry.item, pos = entry.pos, posKey = posKey, save = false })
            continue
        end
        local instKey = entry.instanceKey
        if instKey and S.isShopInstancePurchased(instKey) then
            continue
        end
        local group = ensureGroup(watchKey, watchName, rec.name)
        if not group.pos and entry.pos then
            group.pos = entry.pos
        end
        table.insert(group.instances, entry)
    end

    local function overlayLiveEntry(entry)
        if not entry or typeof(entry.pos) ~= "Vector3" then
            return
        end
        if entry.item then
            -- Drag/move: update saved pos for this instance, do not create extras.
            S.persistWatchlistedShopItemToWorldList(entry.item, { allowCreate = false })
        end
        local watchKey = S.getWatchlistKeyForItem(entry.name, entry.displayName)
        if not watchKey then
            return
        end
        local group = map[watchKey]
        if not group then
            return
        end
        local entryPosKey = S.getShopPosKey(entry.pos)
        for _, inst in ipairs(group.instances) do
            local samePos = inst.pos and S.getShopPosKey(inst.pos) == entryPosKey
            local sameItem = entry.item and inst.item == entry.item
            if samePos or sameItem then
                inst.item = entry.item or inst.item
                inst.pos = entry.pos or inst.pos
                inst.buyPart = entry.buyPart or inst.buyPart
                inst.cost = entry.cost or inst.cost
                inst.live = entry.item ~= nil and entry.item.Parent ~= nil
                if entryPosKey then
                    inst.instanceKey = "pos:" .. tostring(entryPosKey)
                end
                if entry.cost then
                    group.cost = entry.cost
                end
                if inst.live then
                    group.live = true
                    group.item = inst.item
                    group.pos = inst.pos
                    group.buyPart = inst.buyPart
                end
                break
            end
        end
    end

    for _, entry in ipairs(liveMatches or {}) do
        overlayLiveEntry(entry)
    end

    local groups = {}
    for _, group in pairs(map) do
        if recountGroup(group) > 0 then
            table.insert(groups, group)
        end
    end

    groups = S.applyStableHudEntryOrder(groups)
    return groups, timer
end

function S.markShopWatchPurchased(name, displayName, watchKey, entry)
    if entry then
        S.markShopWatchInstancePurchased(entry)
        if typeof(entry.pos) == "Vector3" then
            S.removeShopWorldItemAtPos(entry.pos)
        end
    end
    watchKey = watchKey
        or (entry and S.getWatchlistKeyForItem(entry.name, entry.displayName))
        or S.getWatchlistKeyForItem(name, displayName)
    if not watchKey then
        return
    end

    local stillHas = false
    for _, snap in ipairs(ShopWatch.scannedStock or {}) do
        if not S.isShopInstancePurchased(snap.instanceKey) then
            local wk = S.getWatchlistKeyForItem(snap.name, snap.displayName)
            if wk == watchKey then
                stillHas = true
                break
            end
        end
    end
    if not stillHas then
        ShopWatch._purchasedKeys = ShopWatch._purchasedKeys or {}
        ShopWatch._purchasedKeys[watchKey] = tick()
        if ShopWatch.memory then
            ShopWatch.memory[watchKey] = nil
        end
    end
end

function S.isShopWatchKeyPurchased(watchKey)
    if not watchKey then
        return false
    end
    for _, snap in ipairs(ShopWatch.scannedStock or {}) do
        if not S.isShopInstancePurchased(snap.instanceKey) then
            local wk = S.getWatchlistKeyForItem(snap.name, snap.displayName)
            if wk == watchKey then
                return false
            end
        end
    end
    if ShopWatch._purchasedKeys and ShopWatch._purchasedKeys[watchKey] then
        return true
    end
    return false
end

function S.pruneShopWatchPurchased()
    return false
end

function S.getShopWatchBuyTarget(entry)
    entry = entry or ShopWatch._hudMatch
    if not entry then
        return nil
    end
    if entry.instances then
        for _, inst in ipairs(entry.instances) do
            if not S.isShopInstancePurchased(S.getShopStockInstanceKey(inst)) then
                if inst.item and inst.item.Parent then
                    return inst
                end
            end
        end
        for _, inst in ipairs(entry.instances) do
            if not S.isShopInstancePurchased(S.getShopStockInstanceKey(inst)) then
                return inst
            end
        end
    end
    return entry
end

function S.applyShopWatchHudSelection()
    local entries = ShopWatch._hudEntries or {}
    if #entries == 0 then
        ShopWatch._hudIndex = 1
        ShopWatch._hudMatch = nil
        return
    end
    local prevKey = ShopWatch._hudMatch and ShopWatch._hudMatch.watchKey
    ShopWatch._hudIndex = math.clamp(ShopWatch._hudIndex or 1, 1, #entries)
    if prevKey then
        for i, g in ipairs(entries) do
            if g.watchKey == prevKey and (g.qty or 0) > 0 then
                ShopWatch._hudIndex = i
                break
            end
        end
    end
    ShopWatch._hudMatch = entries[ShopWatch._hudIndex]
end

function S.nowHud()
    return os.clock()
end

function S.stopDepthHudLoops()
    Autofarm._depthHudLoopGen = (Autofarm._depthHudLoopGen or 0) + 1
    if DepthHudOverlay.renderBound then
        pcall(function()
            RunService:UnbindFromRenderStep("JPAX_DepthHud")
        end)
        DepthHudOverlay.renderBound = false
    end
end

function S.destroyDepthHudDrawing()
    if DepthHudOverlay.bg then
        pcall(function()
            DepthHudOverlay.bg:Remove()
        end)
        DepthHudOverlay.bg = nil
    end
    for _, line in ipairs(DepthHudOverlay.lines) do
        pcall(function()
            line:Remove()
        end)
    end
    DepthHudOverlay.lines = {}
end

function S.ensureDepthHudDrawing()
    if DepthHudOverlay.supported == false then
        return false
    end
    if DepthHudOverlay.supported == nil then
        DepthHudOverlay.supported = typeof(Drawing) == "table"
            and pcall(function()
                local t = Drawing.new("Text")
                t:Remove()
            end) or false
    end
    if not DepthHudOverlay.supported then
        return false
    end
    if DepthHudOverlay.bg then
        return true
    end

    local bg = Drawing.new("Square")
    bg.Filled = true
    bg.Color = Color3.fromRGB(14, 16, 20)
    bg.Transparency = 0.12
    bg.Visible = false
    bg.ZIndex = 1
    DepthHudOverlay.bg = bg

    for i = 1, DepthHudOverlay.maxLines do
        local t = Drawing.new("Text")
        t.Size = DepthHudOverlay.fontSize
        t.Center = false
        t.Outline = true
        t.OutlineColor = Color3.fromRGB(0, 0, 0)
        t.Visible = false
        t.ZIndex = 2
        DepthHudOverlay.lines[i] = t
    end
    return true
end

function S.hideDepthHudDrawing()
    if DepthHudOverlay.bg then
        DepthHudOverlay.bg.Visible = false
    end
    for _, line in ipairs(DepthHudOverlay.lines) do
        line.Visible = false
    end
end

function S.syncDepthHudDrawingOrigin()
    local gui = Autofarm._depthGui
    local frame = gui and gui:FindFirstChild("Panel", true)
    if frame then
        local pos = frame.AbsolutePosition
        DepthHudOverlay.origin = Vector2.new(pos.X + DepthHudOverlay.padX, pos.Y + DepthHudOverlay.padTop)
        DepthHudOverlay.framePos = pos
        DepthHudOverlay.frameW = frame.AbsoluteSize.X
    end
end

function S.layoutDepthHudPanel(panelH)
    local gui = Autofarm._depthGui
    local frame = gui and gui:FindFirstChild("Panel", true)
    if not frame or not panelH then
        return
    end

    local entries = ShopWatch._hudEntries or {}
    local showBtns = ShopWatch.hudAlerts == true and #entries > 0
    local btnH = showBtns and 76 or 0
    local topPad = DepthHudOverlay.padTop
    frame.Size = UDim2.fromOffset(220, topPad + panelH + btnH + 10)

    local btnY = topPad + panelH + 4
    local buyBtn = frame:FindFirstChild("BuyItem")
    local tpBtn = frame:FindFirstChild("TeleportItem")
    local nextBtn = frame:FindFirstChild("NextItem")
    if buyBtn then
        buyBtn.Position = UDim2.fromOffset(6, btnY)
        buyBtn.Size = UDim2.new(1, -12, 0, 22)
    end
    if tpBtn then
        tpBtn.Position = UDim2.fromOffset(6, btnY + 24)
        tpBtn.Size = UDim2.new(1, -12, 0, 22)
    end
    if nextBtn then
        nextBtn.Position = UDim2.fromOffset(6, btnY + 48)
        nextBtn.Size = UDim2.new(1, -12, 0, 22)
        nextBtn.Visible = showBtns and #entries > 1
    end
end

function S.getShopWatchStatusLine()
    local rescan = S.getShopRescanPromptLine()
    if rescan then
        return rescan
    end
    if ShopWatch._bgScanBusy then
        local prog = ShopWatch._bgScanProgress
        if prog and prog.total and prog.total > 0 then
            return string.format("Scanning shops %d/%d…", prog.idx or 0, prog.total)
        end
        return "Scanning shops…"
    end
    local catalogLine = S.getShopDisplayCatalogStatusLine()
    if catalogLine then
        return catalogLine
    end
    if ShopWatch.checkAllShops == true then
        local timer = S.getGlobalShopRestockTimer()
        if timer.text then
            return "Auto scan @ restock (" .. timer.text .. ")"
        end
        return "Auto scan @ next restock"
    end
    return nil
end

function S.rebuildDepthHudStaticLines()
    local depthBlock = {}
    for part in string.gmatch(S.getLiveDepthLinesOnly() .. "\n", "([^\n]*)\n") do
        if part ~= "" then
            table.insert(depthBlock, { text = part, color = Color3.fromRGB(220, 230, 225) })
        end
    end

    local shopBlock = {}
    local showShop = ShopWatch.hudAlerts == true and #S.getCombinedShopWatchlist() > 0
    if showShop then
        local listText = S.formatShopWatchListText()
        if listText ~= "" then
            for part in string.gmatch(listText .. "\n", "([^\n]*)\n") do
                if part ~= "" then
                    table.insert(shopBlock, { text = part, color = Color3.fromRGB(220, 230, 225) })
                end
            end
        end
    end

    DepthHudOverlay.cachedDepthBlock = depthBlock
    DepthHudOverlay.cachedShopBlock = shopBlock
    DepthHudOverlay.cachedShowShop = showShop
end

function S.buildDepthHudDrawLines()
    local out = {}
    for _, spec in ipairs(DepthHudOverlay.cachedDepthBlock or {}) do
        table.insert(out, spec)
    end

    if DepthHudOverlay.cachedShowShop then
        local timer = S.getGlobalShopRestockTimer()
        table.insert(
            out,
            {
                text = timer.text and ("Restock " .. timer.text) or "Restock --:--",
                color = Color3.fromRGB(200, 230, 210),
            }
        )
        local status = S.getShopWatchStatusLine()
        if status then
            local statusColor = S.getShopRescanPromptLine()
                and Color3.fromRGB(255, 190, 90)
                or Color3.fromRGB(180, 200, 220)
            table.insert(out, { text = status, color = statusColor })
        end
        if #(DepthHudOverlay.cachedShopBlock or {}) > 0 then
            for _, spec in ipairs(DepthHudOverlay.cachedShopBlock) do
                table.insert(out, spec)
            end
        elseif not status then
            table.insert(out, { text = "Shop: none loaded", color = Color3.fromRGB(180, 180, 190) })
        end
    end

    return out
end

function S.paintDepthHudDrawing()
    if not S.ensureDepthHudDrawing() then
        return false
    end

    S.syncDepthHudDrawingOrigin()
    local ox = DepthHudOverlay.origin.X
    local oy = DepthHudOverlay.origin.Y
    local drawLines = S.buildDepthHudDrawLines()
    table.insert(drawLines, 1, { text = "Depth", color = Color3.fromRGB(140, 255, 170), title = true })

    local lineH = DepthHudOverlay.lineHeight
    local panelH = #drawLines * lineH + 8
    local framePos = DepthHudOverlay.framePos
    local frameW = DepthHudOverlay.frameW or 220
    if framePos then
        DepthHudOverlay.bg.Size = Vector2.new(frameW - 8, panelH + 4)
        DepthHudOverlay.bg.Position = Vector2.new(framePos.X + 4, oy - 4)
    else
        DepthHudOverlay.bg.Size = Vector2.new(204, panelH + 4)
        DepthHudOverlay.bg.Position = Vector2.new(ox - 6, oy - 4)
    end
    DepthHudOverlay.bg.Visible = true

    for i = 1, DepthHudOverlay.maxLines do
        local t = DepthHudOverlay.lines[i]
        local spec = drawLines[i]
        if spec then
            t.Text = spec.text
            t.Color = spec.color
            t.Size = spec.title and (DepthHudOverlay.fontSize + 1) or DepthHudOverlay.fontSize
            t.Position = Vector2.new(ox, oy + (i - 1) * lineH)
            t.Visible = true
        else
            t.Visible = false
        end
    end

    S.layoutDepthHudPanel(panelH + 6)
    DepthHudOverlay.lastPanelH = panelH + 6
    return true, panelH + 6
end

function S.paintDepthHudFallbackLabel()
    local label = S.getDepthHudLabel("HudBody")
    if not label then
        return
    end
    local lines = S.buildDepthHudDrawLines()
    table.insert(lines, 1, { text = "Depth", color = Color3.fromRGB(140, 255, 170) })
    local textLines = {}
    for _, spec in ipairs(lines) do
        table.insert(textLines, spec.text)
    end
    label.Text = table.concat(textLines, "\n")
end

function S.updateDepthHudContentHeavy()
    if Autofarm.depthHudVisible == false then
        return
    end

    if #S.getCombinedShopWatchlist() > 0 then
        S.pruneShopWatchPurchased()
        ShopWatch._hudEntries = S.mergeShopWatchHudEntries(ShopWatch._cachedMatches or {})
        S.applyShopWatchHudSelection()
    end

    S.updateDepthHudShopBuyButton()
    S.updateDepthHudPanelLayout()
    pcall(S.syncAutofarmWindowFromDrill)

    if #S.getCombinedShopWatchlist() > 0 and S.nowHud() >= (ShopWatch._nextHudShopAt or 0) then
        ShopWatch._nextHudShopAt = S.nowHud() + 1
        pcall(function()
            S.refreshShopWatchCache({ force = true })
        end)
    end

    S.rebuildDepthHudStaticLines()
end

function S.onDepthHudRenderStep()
    if Autofarm.depthHudVisible == false then
        S.hideDepthHudDrawing()
        return
    end

    local now = S.nowHud()
    pcall(S.tickShopWatchAutoRestock)
    if now - (DepthHudOverlay.lastHeavyAt or 0) >= 0.35 then
        DepthHudOverlay.lastHeavyAt = now
        pcall(S.updateDepthHudContentHeavy)
    end

    local okDraw = S.paintDepthHudDrawing()
    if not okDraw then
        S.paintDepthHudFallbackLabel()
    end
end

function S.getDepthHudLabel(name)
    local gui = Autofarm._depthGui or S.ensureDepthGui()
    if not gui then
        return nil
    end
    return gui:FindFirstChild(name, true)
end

function S.getLiveDepthLinesOnly()
    local snap = S.getLiveDepthSnapshot()
    if type(snap) ~= "table" then
        return "Depth: unavailable"
    end
    if snap.depthOnly then
        return snap.depthOnly
    end
    local line = snap.line or ""
    local lines = {}
    for part in string.gmatch(line .. "\n", "([^\n]*)\n") do
        table.insert(lines, part)
        if #lines >= 3 then
            break
        end
    end
    return table.concat(lines, "\n")
end

function S.formatShopWatchListText()
    if ShopWatch.hudAlerts ~= true or #S.getCombinedShopWatchlist() == 0 then
        return ""
    end

    local entries = ShopWatch._hudEntries
    if not entries or #entries == 0 then
        entries = S.mergeShopWatchHudEntries(ShopWatch._cachedMatches or {})
        ShopWatch._hudEntries = entries
    end
    if #entries == 0 then
        return ""
    end

    local lines = { "Shop:" }
    for i, m in ipairs(entries) do
        local cost = tonumber(m.cost) or 0
        local label = S.formatShopDisplayLabel(m.displayName or m.name)
        local tag = m.live == false and "*" or ""
        local qty = tonumber(m.qty) or 1
        local qtyStr = qty > 1 and (" x" .. qty) or ""
        local sel = (i == (ShopWatch._hudIndex or 1)) and ">" or " "
        table.insert(
            lines,
            string.format("%s%s$%s %s%s", sel, tag, cost > 0 and tostring(cost) or "?", label, qtyStr)
        )
    end
    return table.concat(lines, "\n")
end

function S.updateDepthHudTimers()
    -- Legacy hook: drawing HUD repaints every render step.
end

function S.updateDepthHudContent()
    S.updateDepthHudContentHeavy()
end

function S.paintDepthHudNow()
    if Autofarm.depthHudVisible == false then
        return
    end
    pcall(S.updateDepthHudContentHeavy)
    pcall(S.onDepthHudRenderStep)
end

function S.syncShopWatchHudState(opts)
    opts = type(opts) == "table" and opts or {}
    if #S.getCombinedShopWatchlist() == 0 then
        ShopWatch._cachedMatches = {}
        ShopWatch._hudEntries = {}
        ShopWatch._hudMatch = nil
        ShopWatch._lastHudEntryCount = 0
        return false
    end

    local prevCount = ShopWatch._lastHudEntryCount or 0
    local prevText = ShopWatch._lastHudText or ""

    if opts.forceScan then
        S.refreshShopWatchCache({ force = true })
    elseif S.nowHud() >= (ShopWatch._nextHudShopAt or 0) then
        ShopWatch._nextHudShopAt = S.nowHud() + 0.75
        S.refreshShopWatchCache({ force = true })
    else
        S.pruneShopWatchPurchased()
        ShopWatch._hudEntries = S.mergeShopWatchHudEntries(ShopWatch._cachedMatches or {})
        S.applyShopWatchHudSelection()
    end

    ShopWatch._lastHudEntryCount = #(ShopWatch._hudEntries or {})
    local snap = S.getLiveDepthSnapshot()
    local newText = snap.line or ""
    local changed = prevCount ~= ShopWatch._lastHudEntryCount or prevText ~= newText or opts.forcePaint == true

    if changed or opts.alwaysPaint then
        S.writeDepthHudText(newText)
        S.updateDepthHudShopBuyButton()
        S.updateDepthHudPanelLayout()
    end

    return changed
end

function S.startShopWatchListeners()
    if ShopWatch._listening then
        return
    end
    ShopWatch._listening = true

    pcall(function()
        CollectionService:GetInstanceAddedSignal("ShopItem"):Connect(function(item)
            if not item then
                return
            end
            -- Only attach/update already-scanned instances; scan creates new records.
            if S.persistWatchlistedShopItemToWorldList(item, { save = false, allowCreate = false }) then
                S.refreshShopWatchHudNow()
            end
        end)
    end)

    pcall(function()
        CollectionService:GetInstanceRemovedSignal("ShopItem"):Connect(function(item)
            if not item then
                return
            end
            -- Tag [$] removed while instance still exists = bought → drop from HUD.
            -- Instance destroyed/unloaded (Parent nil) = streaming → keep saved pos.
            if item.Parent and not CollectionService:HasTag(item, "ShopItem") then
                local pos = S.getItemPosition(item)
                S.handleShopWorldItemGone(item, {
                    purchased = true,
                    pos = pos,
                    posKey = S.getShopPosKey(pos),
                })
                return
            end
            if S.isShopWatchlisted(item.Name) or S.isShopWatchlisted(item:GetAttribute("DisplayName")) then
                S.handleShopWorldItemGone(item, { purchased = false })
            end
        end)
    end)

    pcall(function()
        local itemsFolder = Workspace:FindFirstChild("Items")
        if itemsFolder and not itemsFolder:GetAttribute("JPAX_ShopWatchItemsHook") then
            itemsFolder:SetAttribute("JPAX_ShopWatchItemsHook", true)
            itemsFolder.ChildRemoved:Connect(function(child)
                -- Leaving workspace.Items can be buy OR stream; only drop if it lost [$] / no longer tagged.
                if not child then
                    return
                end
                if not CollectionService:HasTag(child, "ShopItem") then
                    local pos = S.getItemPosition(child)
                    S.handleShopWorldItemGone(child, {
                        purchased = true,
                        pos = pos,
                        posKey = S.getShopPosKey(pos),
                    })
                else
                    S.handleShopWorldItemGone(child, { purchased = false })
                end
            end)
        end
    end)
end

function S.hookNewShopTablesForWatch()
    -- ShopTable hooks unused for world-list qty (positions come from workspace.Items + [$] tag).
end

function S.refreshShopWatchCache(opts)
    opts = type(opts) == "table" and opts or {}
    local now = tick()
    if not opts.force and (now - (ShopWatch._cacheAt or 0)) < (ShopWatch.cacheSeconds or 3) then
        return ShopWatch._hudEntries or ShopWatch._cachedMatches or {}
    end

    local stock = S.collectVisibleShopStock()
    for _, entry in ipairs(stock) do
        S.archiveScannedShopItem(entry)
    end

    local matches = {}
    for _, entry in ipairs(stock) do
        if S.isShopWatchlisted(entry.name) or S.isShopWatchlisted(entry.displayName) then
            if not entry.buyPart then
                entry.buyPart = S.findBuyPartNearItem(entry.item, entry.pos)
            end
            S.rememberShopWatchSighting(entry, entry.fortress)
            table.insert(matches, entry)
        end
    end

    for _, entry in ipairs(S.buildShopEntriesFromScannedStock()) do
        if S.isShopWatchlisted(entry.name) or S.isShopWatchlisted(entry.displayName) then
            table.insert(matches, entry)
        end
    end

    local hudEntries = S.mergeShopWatchHudEntries(matches)
    ShopWatch._cachedStock = stock
    ShopWatch._cachedMatches = matches
    ShopWatch._hudEntries = hudEntries
    S.applyShopWatchHudSelection()
    ShopWatch._cacheAt = now
    return hudEntries
end

function S.checkAllShopsNow(opts)
    opts = type(opts) == "table" and opts or {}
    if ShopWatch._bgScanBusy and not opts.force then
        return false
    end

    S.rebuildShopWatchCombinedList()
    local watchlist = S.getCombinedShopWatchlist()
    if #watchlist == 0 then
        if not opts.silent then
            S.notify("Shop", "Select an item in the dropdown first", 4)
        end
        return false
    end

    ShopWatch._bgScanBusy = true
    ShopWatch._bgScanProgress = { idx = 0, total = 0 }

    task.spawn(function()
        local savedCf = nil
        local root = S.getRoot()
        if root then
            savedCf = root.CFrame
        end

        local queue = {}
        local skippedEnemy = {}
        S.iterFortressesInWindow(function(fortressRoot, pos)
            if S.isFortressEnemyShop(fortressRoot) then
                table.insert(skippedEnemy, fortressRoot.Name)
                return
            end
            table.insert(queue, { root = fortressRoot, pos = pos })
        end)

        if #skippedEnemy > 0 then
            S.hubLog("Skipping enemy shops: " .. table.concat(skippedEnemy, ", "))
        end

        local total = #queue
        if total == 0 then
            ShopWatch._bgScanProgress = nil
            ShopWatch._bgScanBusy = false
            S.syncAutoScanRestockAnchor()
            S.restorePlayerCFrame(savedCf)
            if not opts.silent then
                S.notify("Shop", "No fortresses in 100km window", 3)
            end
            pcall(S.paintDepthHudNow)
            return
        end

        if not ShopWatch._worldListLoaded then
            S.loadShopWorldItemList()
        end
        if opts.replace == true or opts.replaceCatalog == true then
            ShopWatch.worldItemList = {}
        end

        ShopWatch.scannedStock = {}
        ShopWatch.scannedStockByKey = {}
        ShopWatch._purchasedInstances = {}
        S.clearShopRescanPrompt()

        local perShopSeconds = S.getShopScanPerShopSeconds(total)
        if not opts.silent then
            S.notify(
                "Shop",
                string.format(
                    "Scanning %d watch item(s) @ %d shops (~%.0fs)…",
                    #watchlist,
                    total,
                    math.min(SHOP_SCAN_TOTAL_BUDGET_SECONDS, perShopSeconds * total)
                ),
                3
            )
        end

        local scanStartedAt = tick()

        for i, node in ipairs(queue) do
            ShopWatch._bgScanProgress = { idx = i, total = total }
            local before = #(ShopWatch.worldItemList or {})

            S.waitAtFortressShop(node.root, node.pos, { seconds = perShopSeconds })
            local newItems = S.collectNewWorkspaceShopItems(ShopWatch.worldItemList or {})
            for _, rec in ipairs(newItems) do
                table.insert(ShopWatch.worldItemList, rec)
            end
            S.flushLiveWatchlistedShopItemsToWorldList({ save = false })

            S.hubLog(
                string.format(
                    "Shop scan @ %s +%d items (total %d, near=%d)",
                    tostring(node.root.Name),
                    #(ShopWatch.worldItemList or {}) - before,
                    #(ShopWatch.worldItemList or {}),
                    S.countWatchlistedShopItemsNear(node.pos, SHOP_SCAN_NEAR_RADIUS)
                )
            )
        end

        S.flushLiveWatchlistedShopItemsToWorldList({ save = false })
        S.saveShopWorldItemList()
        local savedCount = #(ShopWatch.worldItemList or {})
        S.hubLog(string.format("Shop scan done in %.1fs — %d positions saved", tick() - scanStartedAt, savedCount))

        ShopWatch._bgScanProgress = nil
        S.restorePlayerCFrame(savedCf)
        task.wait(0.05)

        -- Rebuild HUD from saved positions only (after leaving shops).
        ShopWatch._hudEntries = S.mergeShopWatchHudEntries({})
        S.applyShopWatchHudSelection()
        ShopWatch._cacheAt = tick()
        ShopWatch._lastFullScanAt = S.nowHud()

        local matches = ShopWatch._hudEntries or {}
        if not opts.silent then
            local qty = 0
            for _, g in ipairs(matches) do
                qty = qty + (tonumber(g.qty) or 0)
            end
            if qty > 0 then
                S.notify("Shop", string.format("%d positions saved | %dx watched", savedCount, qty), 5)
            else
                S.notify("Shop", string.format("%d positions saved | none watched found", savedCount), 5)
            end
        end
        if ShopWatch.autoBuy then
            S.tryAutoBuyShopWatch()
        end
        ShopWatch._bgScanBusy = false
        S.syncAutoScanRestockAnchor()
        pcall(S.paintDepthHudNow)
    end)
    return true
end

function S.teleportToShopWatchEntry(entry, opts)
    opts = type(opts) == "table" and opts or {}
    entry = entry or ShopWatch._hudMatch
    if not entry or typeof(entry.pos) ~= "Vector3" then
        S.notify("Shop", "No saved shop location", 3)
        return false
    end

    pcall(function()
        S.requestStreamAround(entry.pos, opts.streamTime or 0.25)
    end)
    task.wait(opts.waitAfter or 0.2)

    local ok = S.teleportNearShopPosition(entry.pos, 4)
    if ok and opts.silent ~= true then
        local label = entry.displayName or entry.name or "item"
        local where = entry.fortress and (" @ " .. entry.fortress) or ""
        S.notify("Shop", "Teleported to " .. label .. where, 3)
    end
    return ok
end

function S.buyShopWatchEntry(hudEntry)
    hudEntry = hudEntry or ShopWatch._hudMatch
    if not hudEntry then
        S.notify("Shop", "Nothing to buy", 3)
        return false
    end

    local entry = S.getShopWatchBuyTarget(hudEntry)
    if not entry then
        S.notify("Shop", "Nothing left to buy", 3)
        return false
    end

    if (not entry.item or not entry.item.Parent) and (entry.pos or hudEntry.pos) then
        S.teleportToShopWatchEntry(
            { pos = entry.pos or hudEntry.pos, fortress = entry.fortress or hudEntry.fortress, displayName = entry.displayName },
            { silent = true, waitAfter = 0.25 }
        )
        S.refreshShopWatchCache({ force = true })
        hudEntry = ShopWatch._hudMatch or hudEntry
        entry = S.getShopWatchBuyTarget(hudEntry) or entry
    end

    if not entry then
        S.notify("Shop", "Item not loaded — teleport to shop first", 4)
        return false
    end

    local item = entry.item
    if not item or not item.Parent then
        S.notify("Shop", "Item not loaded — go to the shop", 4)
        return false
    end

    if not Services.ShopService or not Services.DragService then
        S.notify("Shop", "Shop/Drag services not ready", 3)
        return false
    end

    local buyPart, register = S.findShopBuyArea(item, entry.pos)
    if not buyPart then
        S.notify("Shop", "BuyPart not found in this shop", 4)
        return false
    end

    local itemPos = S.getItemPosition(item) or entry.pos
    if not S.isNearPosition(itemPos, 14) then
        S.teleportNearShopPosition(itemPos, 3)
        task.wait(0.05)
    end

    local savedPos = entry.pos or itemPos
    local savedPosKey = nil
    if type(entry.instanceKey) == "string" then
        savedPosKey = string.match(entry.instanceKey, "^pos:(.+)$")
    end
    savedPosKey = savedPosKey or S.getShopPosKey(savedPos)

    local ok, msg = S.performShopPurchase(item, buyPart, register)
    if ok then
        ShopWatch._lastAutoBuyAt = tick()
        entry.buyPart = buyPart
        S.removeShopWorldItemRecord({
            item = item,
            pos = savedPos,
            posKey = savedPosKey,
            save = true,
        })
        S.markShopWatchPurchased(entry.name, entry.displayName, nil, entry)
        S.refreshShopWatchHudNow()
        local qtyLeft = ShopWatch._hudMatch and ShopWatch._hudMatch.qty or 0
        local suffix = qtyLeft > 1 and (" (" .. qtyLeft .. " left)") or ""
        S.notify("Shop", "Buying " .. tostring(entry.displayName or entry.name) .. suffix, 3)
    else
        S.notify("Shop", msg or "Buy failed — place item on BuyPart + register", 4)
    end
    return ok
end

function S.updateDepthHudShopBuyButton()
    local gui = Autofarm._depthGui
    if not gui then
        gui = S.ensureDepthGui()
    end
    if not gui then
        return
    end
    local frame = gui:FindFirstChild("Panel")
    local buyBtn = frame and frame:FindFirstChild("BuyItem")
    local tpBtn = frame and frame:FindFirstChild("TeleportItem")
    local nextBtn = frame and frame:FindFirstChild("NextItem")
    if not buyBtn then
        return
    end

    local entries = ShopWatch._hudEntries or {}
    if #entries == 0 then
        ShopWatch._hudMatch = nil
    else
        S.applyShopWatchHudSelection()
    end

    local match = ShopWatch._hudMatch
    local show = ShopWatch.hudAlerts == true and match ~= nil
    buyBtn.Visible = show == true
    if tpBtn then
        tpBtn.Visible = show == true
    end
    if show then
        local cost = tonumber(match.cost) or 0
        local label = match.displayName or match.name or "item"
        local suffix = match.live == false and " (saved)" or ""
        local qty = tonumber(match.qty) or 1
        local qtyStr = qty > 1 and (" x" .. qty) or ""
        local idx = ShopWatch._hudIndex or 1
        local count = #entries
        local prefix = count > 1 and ("[" .. idx .. "/" .. count .. "] ") or ""
        if cost > 0 then
            buyBtn.Text = prefix .. "Buy " .. label .. qtyStr .. " ($" .. tostring(cost) .. ")"
        else
            buyBtn.Text = prefix .. "Buy " .. label .. qtyStr
        end
        if tpBtn then
            tpBtn.Text = prefix .. "TP " .. label .. qtyStr .. suffix
        end
    end
    if nextBtn then
        nextBtn.Visible = show == true and #entries > 1
        if nextBtn.Visible then
            nextBtn.Text = "Next item (" .. tostring(ShopWatch._hudIndex or 1) .. "/" .. #entries .. ")"
        end
    end
    S.updateDepthHudPanelLayout()
end

function S.refreshShopWatchCatalog()
    S.checkAllShopsNow()
    task.wait(0.5)

    local catalogs = {}
    for _, category in ipairs(SHOP_WATCH_CATEGORY_ORDER) do
        catalogs[category] = {}
    end

    local function push(category, name)
        name = tostring(name or "")
        if name == "" then
            return
        end
        category = category or S.classifyShopWatchCategory(name)
        if not catalogs[category] then
            category = "tools"
        end
        local bucket = catalogs[category]
        local key = S.normalizeShopItemKey(name)
        for _, existing in ipairs(bucket) do
            if S.normalizeShopItemKey(existing) == key then
                return
            end
        end
        table.insert(bucket, name)
    end

    for category, preset in pairs(SHOP_WATCH_CATALOG_BY_CATEGORY) do
        for _, name in ipairs(preset) do
            push(category, name)
        end
    end

    for _, entry in ipairs(ShopWatch._cachedStock or S.collectVisibleShopStock()) do
        push(S.classifyShopWatchCategory(entry.name), entry.name)
        if entry.displayName and entry.displayName ~= entry.name then
            push(S.classifyShopWatchCategory(entry.displayName), entry.displayName)
        end
    end

    for _, category in ipairs(SHOP_WATCH_CATEGORY_ORDER) do
        table.sort(catalogs[category])
        ShopWatch.catalogByCategory[category] = catalogs[category]
    end

    return ShopWatch.catalogByCategory
end

function S.getShopWatchDropdownOptions(category)
    category = tostring(category or "tools")
    local seen = {}
    local out = {}

    local function add(name)
        name = tostring(name or "")
        if name == "" then
            return
        end
        local key = S.normalizeShopItemKey(name)
        if seen[key] then
            return
        end
        seen[key] = true
        table.insert(out, name)
    end

    for _, preset in ipairs(SHOP_WATCH_CATALOG_BY_CATEGORY[category] or {}) do
        add(preset)
    end
    for _, snap in ipairs(ShopWatch.scannedStock or {}) do
        if S.classifyShopWatchCategory(snap.name) == category then
            add(snap.displayName or snap.name)
        end
    end
    for fortressName, entry in pairs(ShopWatch.fortressDisplay or {}) do
        for _, name in ipairs(entry.items or {}) do
            if S.classifyShopWatchCategory(name) == category then
                add(name)
            end
        end
    end
    for _, name in ipairs(ShopWatch.catalogByCategory[category] or {}) do
        add(name)
    end
    table.sort(out)
    if #out > 0 then
        return out
    end
    return SHOP_WATCH_CATALOG_BY_CATEGORY[category] or {}
end

function S.cycleShopWatchHudSelection(step)
    local entries = ShopWatch._hudEntries or {}
    if #entries == 0 then
        ShopWatch._hudMatch = nil
        return nil
    end
    step = tonumber(step) or 1
    ShopWatch._hudIndex = ((ShopWatch._hudIndex or 1) - 1 + step) % #entries + 1
    ShopWatch._hudMatch = entries[ShopWatch._hudIndex]
    S.syncShopWatchHudState({ forcePaint = true, alwaysPaint = true })
    return ShopWatch._hudMatch
end

function S.updateDepthHudPanelLayout()
    -- Frame/button layout is driven by Drawing paint + layoutDepthHudPanel.
    local panelH = DepthHudOverlay.lastPanelH
    if panelH then
        S.layoutDepthHudPanel(panelH)
    end
end

function S.getShopWatchMatches()
    if #S.getCombinedShopWatchlist() == 0 then
        ShopWatch._cachedMatches = {}
        ShopWatch._hudEntries = {}
        ShopWatch._hudMatch = nil
        return {}
    end
    return S.refreshShopWatchCache()
end

function S.formatShopWatchHudLines()
    if ShopWatch.hudAlerts ~= true then
        return ""
    end
    if #S.getCombinedShopWatchlist() == 0 then
        return ""
    end

    local entries = ShopWatch._hudEntries
    if not entries or #entries == 0 then
        entries = S.mergeShopWatchHudEntries(ShopWatch._cachedMatches or {})
        ShopWatch._hudEntries = entries
    end

    local timer = S.getGlobalShopRestockTimer()
    local lines = {}
    if timer.text then
        table.insert(lines, "Restock " .. timer.text)
    end
    local rescan = S.getShopRescanPromptLine()
    if rescan then
        table.insert(lines, rescan)
    end

    if #entries == 0 then
        if ShopWatch._bgScanBusy and ShopWatch._bgScanProgress and ShopWatch._bgScanProgress.total then
            local prog = ShopWatch._bgScanProgress
            table.insert(lines, string.format("Shop: scanning %d/%d…", prog.idx or 0, prog.total))
        elseif ShopWatch.checkAllShops == true then
            local timer = S.getGlobalShopRestockTimer()
            if timer.text then
                table.insert(lines, "Auto scan @ restock (" .. timer.text .. ")")
            else
                table.insert(lines, "Auto scan @ next restock")
            end
        else
            table.insert(lines, "Shop: none loaded")
        end
        return "Shop:\n" .. table.concat(lines, "\n")
    end

    for i, m in ipairs(entries) do
        local cost = tonumber(m.cost) or 0
        local label = S.formatShopDisplayLabel(m.displayName or m.name)
        local tag = m.live == false and "*" or ""
        local qty = tonumber(m.qty) or 1
        local qtyStr = qty > 1 and (" x" .. qty) or ""
        local sel = (i == (ShopWatch._hudIndex or 1)) and ">" or " "
        table.insert(
            lines,
            string.format("%s%s$%s %s%s", sel, tag, cost > 0 and tostring(cost) or "?", label, qtyStr)
        )
    end
    return "Shop:\n" .. table.concat(lines, "\n")
end

function S.tryAutoBuyShopWatch()
    if ShopWatch.autoBuy ~= true or not Services.ShopService then
        return 0
    end
    if tick() - (ShopWatch._lastAutoBuyAt or 0) < 1.2 then
        return 0
    end
    for _, match in ipairs(ShopWatch._hudEntries or {}) do
        local target = S.getShopWatchBuyTarget(match)
        if target and target.item and target.item.Parent then
            if S.buyShopWatchEntry(match) then
                return 1
            end
        end
    end
    return 0
end

-- ========== BUY AMMO NOW ==========
-- Beli semua ammo pilihan (sebanyak yang toko punya & uang cukup) di toko terdekat,
-- kalau kosong pindah ke toko berikutnya, lalu pick up + pakai ammonya.
function S.ammoBuyTypeKey(name, displayName)
    local nameKey = S.normalizeShopItemKey(name)
    local dispKey = S.normalizeShopItemKey(displayName)
    local isAmmo = nameKey:find("ammo", 1, true) ~= nil or dispKey:find("ammo", 1, true) ~= nil
    local own = nameKey ~= "" and nameKey or dispKey
    for _, want in ipairs(AmmoBuy.types or {}) do
        local wk = S.normalizeShopItemKey(want)
        if wk == "allammo" then
            if isAmmo then
                return own
            end
        elseif wk == nameKey or wk == dispKey then
            return own
        elseif (wk == "pistolammo" and (nameKey == "revolverammo" or dispKey == "revolverammo"))
            or (wk == "revolverammo" and (nameKey == "pistolammo" or dispKey == "pistolammo")) then
            -- Pistol = Revolver (nama lain untuk ammo yang sama).
            return own
        end
    end
    return nil
end

function S.getInventoryTools()
    local list = {}
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _, box in ipairs({ char, backpack }) do
        if box then
            for _, child in ipairs(box:GetChildren()) do
                if child:IsA("Tool") then
                    table.insert(list, child)
                end
            end
        end
    end
    return list
end

function S.countInventoryTools()
    return #S.getInventoryTools()
end

-- Ammo yang dijual di toko yang sedang ter-load, terdekat dulu. skipTypes = { [typeKey] = true }.
-- PENTING: tiap item dikenali lewat instance-nya, bukan nama lengkap, supaya 3 Rifle_Ammo
-- identik di satu toko dihitung 3 item (bukan 1).
function S.collectAmmoStock(skipTypes)
    local out = {}
    local root = S.getRoot()
    if not root then
        return out
    end
    local now = tick()
    local seen = {}

    local function consider(top, source)
        if not top or seen[top] or not top.Parent then
            return
        end
        seen[top] = true
        local entry = S.buildShopWatchEntry(top, source)
        if not entry then
            return
        end
        local typeKey = S.ammoBuyTypeKey(entry.name, entry.displayName)
        if not typeKey or (skipTypes and skipTypes[typeKey]) then
            return
        end
        local boughtAt = AmmoBuy._bought[top]
        local failedAt = AmmoBuy._failedAt[top]
        if (boughtAt and now - boughtAt < 20) or (failedAt and now - failedAt < 60) then
            return
        end
        local pos = entry.pos or S.getItemPosition(top)
        if typeof(pos) ~= "Vector3" then
            return
        end
        entry.pos = pos
        entry._key = top
        entry._type = typeKey
        entry._dist = (pos - root.Position).Magnitude
        table.insert(out, entry)
    end

    pcall(function()
        for _, inst in ipairs(CollectionService:GetTagged("ShopItem")) do
            if inst:IsDescendantOf(Workspace) then
                local top = S.resolveWorldItem(inst) or inst
                if S.isWorkspaceShopStockItem(top) then
                    consider(top, "WorkspaceItems")
                end
            end
        end
    end)
    pcall(function()
        local itemsFolder = Workspace:FindFirstChild("Items")
        if itemsFolder then
            for _, child in ipairs(itemsFolder:GetChildren()) do
                if S.isWorkspaceShopStockItem(child) then
                    consider(child, "WorkspaceItems")
                end
            end
        end
    end)
    pcall(function()
        for _, shopTable in ipairs(CollectionService:GetTagged("ShopTable")) do
            local folder = shopTable:FindFirstChild("Items")
            if folder then
                for _, child in ipairs(folder:GetChildren()) do
                    consider(child, "ShopTable")
                end
            end
        end
    end)

    table.sort(out, function(a, b)
        return a._dist < b._dist
    end)
    return out
end

-- Debug: tampilkan semua barang bernama "ammo" yang terbaca di sekitar pemain.
function S.debugAmmoStock()
    local root = S.getRoot()
    if not root then
        return
    end
    local counts, order = {}, {}
    local function add(top)
        local name = tostring(top.Name)
        local disp = tostring(top:GetAttribute("DisplayName") or "")
        local blob = string.lower(name .. " " .. disp)
        if not blob:find("ammo", 1, true) then
            return
        end
        local pos = S.getItemPosition(top)
        if pos and (pos - root.Position).Magnitude <= 200 then
            local label = disp ~= "" and disp ~= name and (name .. " [" .. disp .. "]") or name
            if not counts[label] then
                counts[label] = 0
                table.insert(order, label)
            end
            counts[label] += 1
        end
    end
    local seen = {}
    for _, inst in ipairs(CollectionService:GetTagged("ShopItem")) do
        local top = S.resolveWorldItem(inst) or inst
        if not seen[top] and top.Parent then
            seen[top] = true
            add(top)
        end
    end
    table.sort(order)
    local parts = {}
    for _, label in ipairs(order) do
        table.insert(parts, label .. " x" .. counts[label])
    end
    local text = #parts > 0 and table.concat(parts, ", ") or "no ammo found within 200 studs"
    S.hubLog("Ammo stock: " .. text)
    S.notify("Shop", "Ammo found: " .. text, 8)
end

-- Berdiri di SAMPING item (bukan di atasnya) supaya badan pemain tidak menyenggol item
-- dan menjatuhkannya dari register / meja.
function S.standBesideItem(itemPos, dist)
    local root = S.getRoot()
    if not root or typeof(itemPos) ~= "Vector3" then
        return false
    end
    dist = dist or 3.5
    local flat = Vector3.new(root.Position.X - itemPos.X, 0, root.Position.Z - itemPos.Z)
    local cur = flat.Magnitude
    -- Sudah di jarak aman (tidak menumpuk item, masih dalam jangkauan): biarkan.
    if cur >= 2.5 and cur <= dist + 3 and math.abs(root.Position.Y - itemPos.Y) < 8 then
        return true
    end
    local dir = cur > 0.5 and flat.Unit or Vector3.new(1, 0, 0)
    local spot = itemPos + dir * dist
    local floorY = S.getFloorYBelow(Vector3.new(spot.X, itemPos.Y, spot.Z), 20) or itemPos.Y
    local stand = Vector3.new(spot.X, floorY + 3, spot.Z)
    root.CFrame = CFrame.lookAt(stand, Vector3.new(itemPos.X, stand.Y, itemPos.Z))
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end

-- Berdiri minimal 6 studs dari register / BuyPart (item akan ditaruh di sana), tetap dekat item.
function S.standAwayFromRegister(buyPart, itemPos)
    local root = S.getRoot()
    if not root or not buyPart or typeof(itemPos) ~= "Vector3" then
        return false
    end
    local bp = buyPart.Position
    local dirFlat = Vector3.new(itemPos.X - bp.X, 0, itemPos.Z - bp.Z)
    local itemDist = dirFlat.Magnitude
    if dirFlat.Magnitude < 1 then
        dirFlat = Vector3.new(root.Position.X - bp.X, 0, root.Position.Z - bp.Z)
    end
    if dirFlat.Magnitude < 1 then
        local right = buyPart.CFrame.RightVector
        dirFlat = Vector3.new(right.X, 0, right.Z)
    end
    if dirFlat.Magnitude < 0.1 then
        dirFlat = Vector3.new(1, 0, 0)
    end
    local dir = dirFlat.Unit
    local standDist = math.clamp(itemDist, 6, 9)
    local spot = bp + dir * standDist

    -- Sudah di tempat yang aman (>= 5 studs dari register dan dekat item)? tidak perlu pindah.
    local rootFlatToBp = Vector3.new(root.Position.X - bp.X, 0, root.Position.Z - bp.Z).Magnitude
    if rootFlatToBp >= 5 and S.isNearPosition(itemPos, 12) then
        return true
    end

    local floorY = S.getFloorYBelow(Vector3.new(spot.X, bp.Y, spot.Z), 20) or bp.Y
    local stand = Vector3.new(spot.X, floorY + 3, spot.Z)
    root.CFrame = CFrame.lookAt(stand, Vector3.new(bp.X, stand.Y, bp.Z))
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end

-- Beli satu item. Return ok, alasan ("unconfirmed" = klik register jalan tapi tidak ada tanda berhasil).
function S.purchaseAmmoEntry(entry)
    local item = entry and entry.item
    if not item or not item.Parent then
        return false, "gone"
    end
    local buyPart, register = S.findShopBuyArea(item, entry.pos)
    if not buyPart then
        return false, "nobuypart"
    end
    -- Toko musuh memakai FakeRegister.
    if register and string.find(string.lower(register.Name), "fake", 1, true) then
        return false, "fake"
    end

    local hadTag = S.hasShopItemTag(item)
    local toolsBefore = S.countInventoryTools()

    local itemPos = S.getItemPosition(item) or entry.pos
    S.standAwayFromRegister(buyPart, itemPos)
    task.wait(0.05)

    local ok = S.performShopPurchase(item, buyPart, register)
    if not ok then
        return false, "click"
    end

    -- Tanda berhasil: item hilang, tag ShopItem lepas, atau tool baru masuk inventory.
    local deadline = tick() + 1.2
    repeat
        if not item.Parent then
            return true
        end
        if hadTag and not S.hasShopItemTag(item) then
            return true
        end
        if S.countInventoryTools() > toolsBefore then
            return true
        end
        task.wait(0.1)
    until tick() >= deadline
    return false, "unconfirmed"
end

-- Satu percobaan "interact" seperti pemain: bidik item (kursor / crosshair), set target drag,
-- lalu Interact (tombol Pick Up di HP / tombol E di PC).
function S.interactAmmoOnce(item, hold)
    local pos = S.getItemPosition(item)
    local camBackup = nil
    if pos then
        -- Item bisa sudah jatuh / bergeser: berdiri di samping posisinya yang sekarang.
        S.standBesideItem(pos, 3.5)
        S.faceCharacterToward(pos)
        camBackup = S.aimCameraAtWorld(pos, nil)
        -- PC 3rd person: kursor harus ada di atas item. Kamera sudah menghadap item,
        -- jadi tengah layar = item.
        pcall(function()
            local cam = Workspace.CurrentCamera
            local vim = game:GetService("VirtualInputManager")
            if cam and vim then
                local vp = cam.ViewportSize
                vim:SendMouseMoveEvent(vp.X * 0.5, vp.Y * 0.5, game)
            end
        end)
        task.wait(0.08)
    end

    -- 3rd person: item harus di-hold dulu (DragService:Request), baru tombol Pick Up muncul.
    if hold and Services.DragService then
        pcall(function()
            Services.DragService:Request(item)
        end)
        task.wait(0.15)
    end

    pcall(S.setDragTarget, item)
    if Services.InteractionService then
        pcall(function()
            Services.InteractionService:Interact(item)
        end)
    end
    pcall(function()
        local knit = S.getKnit()
        local drag = knit and knit.GetController("DragController")
        if drag then
            drag.Target = item
            if drag.PerformConsoleInteract then
                drag:PerformConsoleInteract()
            end
        end
    end)
    if typeof(fireproximityprompt) == "function" then
        local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            pcall(fireproximityprompt, prompt)
        end
    end
    S.pressInteractKey()

    if hold and Services.DragService then
        task.wait(0.1)
        pcall(function()
            Services.DragService:Cancel()
        end)
    end
    S.restoreCameraAim(camBackup)
end

-- Pick up ammo yang sudah dibeli. Di game ini pick up = langsung memakai ammo (item hilang).
-- Urutan: 1st person / PC (bidik lalu E), lalu 3rd person (hold dulu, baru Pick Up).
function S.pickupAmmoItem(item)
    if not item or not item.Parent then
        return true
    end
    local toolsBefore = S.countInventoryTools()
    local before = item.Parent
    local function done()
        return (not item.Parent) or item.Parent ~= before or S.countInventoryTools() > toolsBefore
    end

    pcall(function()
        if Services.DragService then
            Services.DragService:Cancel()
        end
    end)
    pcall(function()
        Services.ToolService:UnequipTool()
    end)
    task.wait(0.08)

    -- Tunggu sebentar supaya item yang jatuh sempat berhenti, lalu berdiri di SAMPINGNYA.
    task.wait(0.15)
    local pos = S.getItemPosition(item)
    if pos then
        S.standBesideItem(pos, 3.5)
        task.wait(0.06)
    end

    for attempt = 1, 4 do
        if done() then
            return true
        end
        -- Percobaan ganjil: tanpa hold (1st person / PC). Genap: hold dulu (3rd person).
        S.interactAmmoOnce(item, attempt % 2 == 0)
        local deadline = tick() + 0.5
        while tick() < deadline do
            if done() then
                return true
            end
            task.wait(0.05)
        end
    end

    -- Cadangan: ItemBag.
    if item.Parent and S.bagPickup(item) then
        task.wait(0.25)
    end
    return done()
end

-- Tunggu stok toko ter-stream setelah teleport.
function S.waitForAmmoStock(timeout)
    local deadline = tick() + (tonumber(timeout) or 1.8)
    repeat
        for _, e in ipairs(S.collectAmmoStock()) do
            if e._dist <= AmmoBuy.localRange then
                return true
            end
        end
        task.wait(0.2)
    until tick() >= deadline
    return false
end

-- Beli SEMUA ammo pilihan yang ada di toko tempat pemain berada.
-- Return jumlah dibeli, apakah ada stok ammo di toko ini, rincian per nama.
function S.buyAllAmmoHere()
    local bought, sawStock = 0, false
    local detail = {}
    local fails, skip = {}, {}

    for _ = 1, AmmoBuy.maxItemsPerShop do
        local target
        for _, e in ipairs(S.collectAmmoStock(skip)) do
            if e._dist <= AmmoBuy.localRange then
                target = e
                break
            end
        end
        if not target then
            break
        end
        sawStock = true

        local item = target.item
        local ok, why = S.purchaseAmmoEntry(target)
        local picked = false
        if ok then
            AmmoBuy._bought[target._key] = tick()
            picked = S.pickupAmmoItem(item)
        elseif why == "unconfirmed" and item and item.Parent then
            -- Mungkin berhasil tapi tidak terdeteksi: coba ambil; kalau bisa diambil berarti sudah milik pemain.
            picked = S.pickupAmmoItem(item)
            ok = picked
        end

        if ok then
            bought += 1
            fails[target._type] = 0
            local label = tostring(target.displayName or target.name)
            detail[label] = (detail[label] or 0) + 1
        else
            AmmoBuy._failedAt[target._key] = tick()
            local failLabel = tostring(target.displayName or target.name) .. " (" .. tostring(why or "?") .. ")"
            detail["!" .. failLabel] = (detail["!" .. failLabel] or 0) + 1
            fails[target._type] = (fails[target._type] or 0) + 1
            -- Gagal 2x berturut-turut untuk jenis ini = uang tidak cukup: lewati jenis ini.
            if fails[target._type] >= 2 then
                skip[target._type] = true
            end
        end
        task.wait(0.15)
    end

    return bought, sawStock, detail
end

function S.buyAmmoNow()
    if AmmoBuy.busy then
        S.notify("Shop", "Already buying ammo...", 2)
        return 0
    end
    if #(AmmoBuy.types or {}) == 0 then
        S.notify("Shop", "Select an ammo type first", 3)
        return 0
    end
    if not Services.ShopService or not Services.DragService then
        S.notify("Shop", "Shop/Drag services not ready", 3)
        return 0
    end
    local root = S.getRoot()
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then
        return 0
    end

    AmmoBuy.busy = true
    local savedCf = root.CFrame
    local total = 0
    local summary = {}
    local sawAnyStock = false

    local function addDetail(detail)
        for label, n in pairs(detail or {}) do
            summary[label] = (summary[label] or 0) + n
        end
    end

    local ok, err = pcall(function()
        -- 1) Toko tempat pemain berada sekarang.
        local bought, saw, detail = S.buyAllAmmoHere()
        total += bought
        addDetail(detail)
        sawAnyStock = saw

        -- 2) Tidak ada ammo di sini: ke toko terdekat berikutnya sampai ada stok.
        if not saw then
            local startPos = savedCf.Position
            local queue = {}
            S.iterFortressesInWindow(function(fortressRoot, pos)
                if (pos - startPos).Magnitude > AmmoBuy.localRange then
                    table.insert(queue, {
                        root = fortressRoot,
                        pos = pos,
                        dist = S.getFlatDistanceFromPosition(pos),
                    })
                end
            end)
            table.sort(queue, function(a, b)
                return a.dist < b.dist
            end)
            if #queue == 0 then
                S.notify("Shop", "No other shops found", 3)
            end

            for i = 1, math.min(#queue, AmmoBuy.maxShops) do
                local node = queue[i]
                S.notify("Shop", "Out of ammo, moving to the next shop (" .. i .. ")", 2)
                S.waitAtFortressShop(node.root, node.pos, { seconds = 0.7 })
                S.waitForAmmoStock(1.8)
                local b, sawHere, d = S.buyAllAmmoHere()
                total += b
                addDetail(d)
                if sawHere then
                    sawAnyStock = true
                    break
                end
            end
        end

    end)

    local nowRoot = S.getRoot()
    if nowRoot and (nowRoot.Position - savedCf.Position).Magnitude > 3 then
        S.restorePlayerCFrame(savedCf)
    end
    AmmoBuy.busy = false

    if not ok then
        S.hubLog("BuyAmmo error: " .. tostring(err))
        S.notify("Shop", "Buy ammo error: " .. tostring(err), 5)
    elseif total > 0 then
        local parts, failed = {}, {}
        for label, n in pairs(summary) do
            if string.sub(label, 1, 1) == "!" then
                table.insert(failed, string.sub(label, 2) .. " x" .. n)
            else
                table.insert(parts, label .. " x" .. n)
            end
        end
        table.sort(parts)
        table.sort(failed)
        local msg = "Bought: " .. table.concat(parts, ", ")
        if #failed > 0 then
            msg = msg .. " | Failed: " .. table.concat(failed, ", ")
        end
        S.notify("Shop", msg, 7)
    elseif sawAnyStock then
        local failed = {}
        for label, n in pairs(summary) do
            if string.sub(label, 1, 1) == "!" then
                table.insert(failed, string.sub(label, 2) .. " x" .. n)
            end
        end
        table.sort(failed)
        S.notify("Shop", "Ammo in stock but purchase failed: " .. (#failed > 0 and table.concat(failed, ", ") or "not enough money?"), 6)
    else
        S.notify("Shop", "No ammo for sale", 3)
    end
    return total
end

function S.syncAutoScanRestockAnchor()
    if ShopWatch.checkAllShops ~= true then
        ShopWatch._autoScanCycleEnd = nil
        ShopWatch._autoScanLastSeconds = nil
        ShopWatch._autoScanArmed = false
        return
    end
    local timer = S.getGlobalShopRestockTimer()
    ShopWatch._autoScanCycleEnd = timer.endTime
    ShopWatch._autoScanLastSeconds = timer.seconds
    ShopWatch._autoScanArmed = timer.endTime ~= nil
end

function S.tickShopWatchAutoRestock()
    if ShopWatch.checkAllShops ~= true then
        return
    end
    if ShopWatch._bgScanBusy or ShopWatch._autoScanArmed ~= true then
        return
    end

    local timer = S.getGlobalShopRestockTimer()
    local secs = timer.seconds
    if secs == nil then
        return
    end

    if S.didUiRestockTimerRollOver(ShopWatch._autoScanLastSeconds, secs) then
        ShopWatch._autoScanArmed = false
        S.notify("Shop", "Restock — auto scanning…", 3)
        S.checkAllShopsNow({ silent = true })
        return
    end

    ShopWatch._autoScanLastSeconds = secs
end

function S.getLiveDepthSnapshot()
    local root = S.getRoot()
    if not root then
        return {
            meters = 0,
            layer = nil,
            farmDist = tonumber(Autofarm.distance) or 0,
            line = "Depth: no HumanoidRootPart",
            short = "no root",
        }
    end

    local pos = root.Position
    local meters = S.getDrillDepthMeters()
    if meters == nil then
        local ds = S.getDepthScale()
        if ds and type(ds.GetMetersFromWorldPosition) == "function" then
            local ok, m = pcall(ds.GetMetersFromWorldPosition, ds, pos)
            if ok and type(m) == "number" and m == m then
                meters = m
            end
        end
        if meters == nil then
            meters = S.computeDepthMetersDump(pos)
        end
    end
    meters = tonumber(meters) or 0
    if meters ~= meters then
        meters = 0
    end

    local layer = S.getDepthLayerName(meters)
    local farmDist = tonumber(Autofarm.distance) or 0
    local startM = tonumber(Autofarm.mapStartMeters)
    local endM = tonumber(Autofarm.mapEndMeters)
    if not startM or not endM then
        startM, endM = S.computeAutofarmDepthWindow(meters)
    end

    local depthOnly = string.format(
        "Drill %sm\n%s\nFarm %dk-%dk m",
        math.floor(meters + 0.5),
        layer or "Surface",
        math.floor(startM / 1000),
        math.floor(endM / 1000)
    )
    local shopLines = S.formatShopWatchHudLines()
    local line = depthOnly
    if shopLines ~= "" then
        line = line .. "\n" .. shopLines
    end

    return {
        meters = meters,
        layer = layer,
        farmDist = farmDist,
        short = string.format("%sm", math.floor(meters + 0.5)),
        depthOnly = depthOnly,
        line = line,
    }
end

function S.getAutofarmStudsPerMeter()
    local start = Workspace:GetAttribute("Start_Position")
    local endPos = Workspace:GetAttribute("End_Position")
    if typeof(start) == "Vector3" and typeof(endPos) == "Vector3" then
        local route = (endPos - start).Magnitude
        if route > 0 then
            return route / DEPTH_TARGET_END_METERS
        end
    end
    return DEPTH_LEGACY_STUDS_PER_METER
end

function S.syncAutofarmMapEndFromMeters()
    local _, startM, endM = S.syncAutofarmWindowFromDrill()
    return Autofarm.mapEndStuds, startM, endM
end

function S.destroyDepthGui()
    S.stopDepthHudLoops()
    S.destroyDepthHudDrawing()
    S.disconnectAll("depthHud")
    Autofarm._depthGui = nil
    Autofarm._depthText = nil
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local gui = pg and pg:FindFirstChild("JPAX_DepthPanel")
        if gui then
            gui:Destroy()
        end
    end)
end

function S.setDepthGuiVisible(_visible)
    Autofarm.depthHudVisible = false
        S.destroyDepthGui()
end

function S.ensureDepthGui()
    S.destroyDepthGui()
    do return nil end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then
        return nil
    end

    local existing = pg:FindFirstChild("JPAX_DepthPanel")
    if existing then
        local panel = existing:FindFirstChild("Panel", true)
        if panel
            and panel:FindFirstChild("BuyItem")
            and panel:FindFirstChild("TeleportItem")
            and panel:FindFirstChild("NextItem") then
            Autofarm._depthGui = existing
            Autofarm._depthText = panel:FindFirstChild("HudBody")
            panel.BackgroundTransparency = 1
            local title = panel:FindFirstChild("Title")
            if title then
                title.Visible = false
            end
            return existing
        end
        existing:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "JPAX_DepthPanel"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 80
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = pg

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.Size = UDim2.fromOffset(220, 72)
    frame.Position = UDim2.new(0, 12, 0, 108)
    frame.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(40, 180, 90)
    stroke.Thickness = 1
    stroke.Transparency = 0.35
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -28, 0, 22)
    title.Position = UDim2.fromOffset(8, 4)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(140, 255, 170)
    title.Text = "Depth"
    title.Visible = false
    title.Parent = frame

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "Close"
    closeBtn.Size = UDim2.fromOffset(22, 22)
    closeBtn.Position = UDim2.new(1, -26, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
    closeBtn.BorderSizePixel = 0
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
    closeBtn.Text = "X"
    closeBtn.Parent = frame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    local hudBody = Instance.new("TextLabel")
    hudBody.Name = "HudBody"
    hudBody.Size = UDim2.new(1, -12, 0, 52)
    hudBody.Position = UDim2.fromOffset(8, 28)
    hudBody.BackgroundTransparency = 1
    hudBody.Font = Enum.Font.GothamMedium
    hudBody.TextSize = 15
    hudBody.TextXAlignment = Enum.TextXAlignment.Left
    hudBody.TextYAlignment = Enum.TextYAlignment.Top
    hudBody.TextColor3 = Color3.fromRGB(220, 230, 225)
    hudBody.TextWrapped = true
    hudBody.Text = ""
    hudBody.Visible = false
    hudBody.Parent = frame

    local buyBtn = Instance.new("TextButton")
    buyBtn.Name = "BuyItem"
    buyBtn.Size = UDim2.new(1, -12, 0, 24)
    buyBtn.Position = UDim2.new(0, 6, 1, -56)
    buyBtn.BackgroundColor3 = Color3.fromRGB(28, 90, 52)
    buyBtn.BorderSizePixel = 0
    buyBtn.Font = Enum.Font.GothamBold
    buyBtn.TextSize = 11
    buyBtn.TextColor3 = Color3.fromRGB(220, 255, 230)
    buyBtn.Text = "Buy this item"
    buyBtn.Visible = false
    buyBtn.Parent = frame
    Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 6)

    buyBtn.MouseButton1Click:Connect(function()
        S.buyShopWatchEntry(ShopWatch._hudMatch)
    end)

    local tpBtn = Instance.new("TextButton")
    tpBtn.Name = "TeleportItem"
    tpBtn.Size = UDim2.new(1, -12, 0, 24)
    tpBtn.Position = UDim2.new(0, 6, 1, -28)
    tpBtn.BackgroundColor3 = Color3.fromRGB(28, 52, 90)
    tpBtn.BorderSizePixel = 0
    tpBtn.Font = Enum.Font.GothamBold
    tpBtn.TextSize = 11
    tpBtn.TextColor3 = Color3.fromRGB(210, 230, 255)
    tpBtn.Text = "TP to item"
    tpBtn.Visible = false
    tpBtn.Parent = frame
    Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 6)

    tpBtn.MouseButton1Click:Connect(function()
        S.teleportToShopWatchEntry(ShopWatch._hudMatch)
    end)

    local nextBtn = Instance.new("TextButton")
    nextBtn.Name = "NextItem"
    nextBtn.Size = UDim2.new(1, -12, 0, 22)
    nextBtn.Position = UDim2.new(0, 6, 1, -28)
    nextBtn.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
    nextBtn.BorderSizePixel = 0
    nextBtn.Font = Enum.Font.GothamBold
    nextBtn.TextSize = 11
    nextBtn.TextColor3 = Color3.fromRGB(210, 210, 220)
    nextBtn.Text = "Next item"
    nextBtn.Visible = false
    nextBtn.Parent = frame
    Instance.new("UICorner", nextBtn).CornerRadius = UDim.new(0, 6)

    nextBtn.MouseButton1Click:Connect(function()
        S.cycleShopWatchHudSelection(1)
    end)

    closeBtn.MouseButton1Click:Connect(function()
        S.setDepthGuiVisible(false)
    end)

    -- Drag by title bar / panel
    local dragging = false
    local dragStart, startPos
    local function beginDrag(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
    title.InputBegan:Connect(beginDrag)
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            -- Don't start drag from close button.
            local pos = input.Position
            local closeAbs = closeBtn.AbsolutePosition
            local closeSize = closeBtn.AbsoluteSize
            if pos.X >= closeAbs.X and pos.X <= closeAbs.X + closeSize.X
                and pos.Y >= closeAbs.Y and pos.Y <= closeAbs.Y + closeSize.Y then
                return
            end
            beginDrag(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    Autofarm._depthGui = gui
    Autofarm._depthText = hudBody
    return gui
end

function S.writeDepthHudText(text)
    text = tostring(text or "")
    ShopWatch._lastHudText = text
    pcall(S.onDepthHudRenderStep)
    return true
end

function S.startDepthHud()
    S.stopDepthHudLoops()
    S.disconnectAll("depthHud")
    if Autofarm.depthHudVisible == false then
        return
    end
    Autofarm.depthHudVisible = true
    S.ensureDepthGui()
    S.ensureDepthHudDrawing()
    S.syncAutofarmMapEndFromMeters()
    S.startShopWatchListeners()
    S.hookNewShopTablesForWatch()

    pcall(S.rebuildDepthHudStaticLines)
    pcall(S.paintDepthHudNow)

    if not DepthHudOverlay.renderBound then
        DepthHudOverlay.renderBound = true
        RunService:BindToRenderStep("JPAX_DepthHud", Enum.RenderPriority.Last.Value, function()
            pcall(S.onDepthHudRenderStep)
        end)
    end
end

-- Keep old name available if DepthScale require path is used elsewhere.
local DepthScaleModule = nil
function S.getDepthScale()
    if DepthScaleModule ~= nil then
        return DepthScaleModule ~= false and DepthScaleModule or nil
    end
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local util = shared and shared:FindFirstChild("Util")
    local modInst = util and util:FindFirstChild("DepthScale")
    if not modInst then
        return nil
    end
    local ok, mod = pcall(require, modInst)
    DepthScaleModule = (ok and type(mod) == "table") and mod or false
    return DepthScaleModule ~= false and DepthScaleModule or nil
end

-- ========== AUTO LOOT (workspace.Items + Scout dungeon tags) ==========
local EXCLUDED_ITEMS = { Money_Sack = true, SoulOrb = true }

function S.resolveWorldItem(instance)
    local current = instance
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder then
        return nil
    end

    while current and current ~= itemsFolder do
        if current.Parent == itemsFolder then
            return current
        end
        current = current.Parent
    end

    return nil
end

function S.getItemPosition(item)
    if item:IsA("Model") then
        return item:GetPivot().Position
    end
    if item:IsA("BasePart") then
        return item.Position
    end
    local part = item:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

function S.stripRarityPrefix(text, rarityAttr)
    local s = string.lower(tostring(text or "")):gsub("^%s+", ""):gsub("%s+$", "")
    local function cut(prefix)
        prefix = string.lower(tostring(prefix or "")):gsub("^%s+", ""):gsub("%s+$", "")
        if prefix == "" then
            return nil
        end
        if s == prefix then
            return ""
        end
        local lead = prefix .. " "
        if s:sub(1, #lead) == lead then
            return s:sub(#lead + 1)
        end
        return nil
    end
    local fromAttr = cut(rarityAttr)
    if fromAttr ~= nil then
        return fromAttr
    end
    for _, rarity in ipairs({
        "common",
        "uncommon",
        "rare",
        "epic",
        "legendary",
        "mythic",
        "divine",
        "exotic",
        "unique",
    }) do
        local cutOne = cut(rarity)
        if cutOne ~= nil then
            return cutOne
        end
    end
    return s
end

function S.normalizeLootCategory(cat)
    cat = string.lower(tostring(cat or ""))
    if cat == "secondary gun" or cat == "secondary weapon" or cat == "secondary" then
        return "secondary weapon"
    end
    if cat == "primary gun" or cat == "primary weapon" or cat == "primary" then
        return "primary weapon"
    end
    if cat == "consume" or cat == "consumable" then
        return "consumable"
    end
    if cat == "melee" then
        return "sword"
    end
    return cat
end

function S.itemCategoryKey(item)
    if not item then
        return ""
    end
    local rarity = item:GetAttribute("Rarity")
    local fields = {
        item:GetAttribute("DisplayCategory"),
        item:GetAttribute("Category"),
        item:GetAttribute("Class"),
        item:GetAttribute("ItemType"),
        item:GetAttribute("Type"),
    }
    for _, raw in ipairs(fields) do
        if raw ~= nil and tostring(raw) ~= "" then
            local stripped = S.normalizeLootCategory(S.stripRarityPrefix(raw, rarity))
            if stripped ~= "" then
                return stripped
            end
        end
    end
    return ""
end

function S.isBlacklisted(item)
    if not item or not Loot.useBlacklist or #Loot.blacklistCategories == 0 then
        return false
    end

    local blocked = {}
    for _, blockedName in ipairs(Loot.blacklistCategories) do
        local key = string.lower(tostring(blockedName or ""))
        if key ~= "" then
            blocked[key] = true
        end
    end

    local cat = S.itemCategoryKey(item)
    local name = string.lower(tostring(item.Name or ""))
    local rarity = item:GetAttribute("Rarity")
    local blob = cat
    for _, attr in ipairs({ "DisplayCategory", "Category", "Class", "ItemType", "Type" }) do
        local raw = item:GetAttribute(attr)
        if raw ~= nil and tostring(raw) ~= "" then
            blob ..= " " .. S.normalizeLootCategory(S.stripRarityPrefix(raw, rarity))
        end
    end
    local oreType = S.getLootOreTypeKey(item)
    if oreType and cat ~= "bar" and not name:find("bar", 1, true) then
        if blocked.ore or blocked[string.lower(oreType)] then
            return true
        end
        return false
    end

    if blocked.ore and cat == "ore" then
        return true
    end

    for key in pairs(blocked) do
        if key == "ore" or BLACKLIST_ORE_TYPES[key] then
            continue
        end
        if cat == key or (key ~= "" and blob:find(key, 1, true)) or (key ~= "" and name:find(key, 1, true)) then
            return true
        end
    end

    return false
end

function S.passesLootFilters(item)
    if not item then
        return false
    end
    if S.isBlacklisted(item) then
        return false
    end
    if Loot.useMinCoins then
        local value = item:GetAttribute("Value")
        if typeof(value) == "number" and value < Loot.minCoins then
            return false
        end
    end
    return true
end

function S.isHardExcluded(item)
    if not item then
        return true
    end
    local name = item.Name
    if name and EXCLUDED_ITEMS[name] then
        return true
    end
    local ok, tagged = pcall(function()
        return CollectionService:HasTag(item, "ShopItem")
    end)
    if ok and tagged then
        return true
    end
    return false
end

function S.passesMoneyLootFilters(item)
    if Money.useMinCoins then
        local value = item:GetAttribute("Value")
        if typeof(value) ~= "number" or value < Money.minCoins then
            return false
        end
    end
    return true
end

function S.isMoneyLootCandidate(item)
    if not item or not item.Parent then
        return false
    end
    if not item:IsDescendantOf(Workspace.Items) then
        return false
    end
    if S.isHardExcluded(item) then
        return false
    end
    return S.passesMoneyLootFilters(item)
end

function S.forEachWorldLootItem(callback)
    local itemsFolder = Workspace:FindFirstChild("Items")
    if itemsFolder then
        for _, child in ipairs(itemsFolder:GetChildren()) do
            callback(child)
        end
    end

    for _, tagged in ipairs(CollectionService:GetTagged("DungeonLootHighlightTarget")) do
        callback(S.resolveWorldItem(tagged))
    end
end

function S.collectMoneyLootTargets()
    local targets = {}
    local seen = {}
    local itemsFolder = Workspace:FindFirstChild("Items")

    if itemsFolder then
        for _, child in ipairs(itemsFolder:GetChildren()) do
            if S.isMoneyLootCandidate(child) and not seen[child] then
                seen[child] = true
                table.insert(targets, child)
            end
        end
    end

    for _, tagged in ipairs(CollectionService:GetTagged("DungeonLootHighlightTarget")) do
        local item = S.resolveWorldItem(tagged)
        if item and S.isMoneyLootCandidate(item) and not seen[item] then
            seen[item] = true
            table.insert(targets, item)
        end
    end

    table.sort(targets, function(a, b)
        local posA = S.getItemPosition(a)
        local posB = S.getItemPosition(b)
        if not posA then return false end
        if not posB then return true end
        return LocalPlayer:DistanceFromCharacter(posA) < LocalPlayer:DistanceFromCharacter(posB)
    end)

    return targets
end

function S.isLootCandidate(item)
    if not item or not item.Parent then
        return false
    end
    if not item:IsDescendantOf(Workspace.Items) then
        return false
    end
    if S.isHardExcluded(item) then
        return false
    end
    return S.passesLootFilters(item)
end

function S.collectLootTargets()
    local targets = {}
    local seen = {}
    local range = S.getLootMaxRange()

    S.forEachWorldLootItem(function(item)
        if item and S.isLootCandidate(item) and not seen[item] then
            local pos = S.getItemPosition(item)
            -- Same rule as loot ESP: flat XY distance (deep mines stay visible).
            if pos and S.getFlatDistanceFromPosition(pos) <= range then
                seen[item] = true
                table.insert(targets, item)
            end
        end
    end)

    table.sort(targets, function(a, b)
        local posA = S.getItemPosition(a)
        local posB = S.getItemPosition(b)
        if not posA then return false end
        if not posB then return true end
        return S.getFlatDistanceFromPosition(posA) < S.getFlatDistanceFromPosition(posB)
    end)

    return targets
end

-- Autofarm scoop = same system as Auto Loot tab (runLootCycle), looped until quiet.
function S.pickupAllVisibleLoot(opts)
    opts = type(opts) == "table" and opts or {}
    if S.isBagFull() then
        return 0
    end

    S.lockAutofarmHover(true)
    S.setAutofarmPlatformStand(true)

    local total = 0
    local safety = os.clock() + (opts.seconds or 6)
    local emptyStreak = 0
    local duringMine = opts.duringMine == true or Autofarm.miningBusy == true

    while os.clock() < safety and not S.isBagFull() do
        if opts.requireAutofarm ~= false and Autofarm.enabled == false then
            break
        end

        local got = S.runLootCycle({
            duringMine = duringMine,
            fast = true,
            nearRange = opts.nearRange or S.getLootMaxRange(),
            batchSize = opts.batchSize or Loot.batchSize or 50,
        })
        total += got or 0

        if (got or 0) <= 0 then
            emptyStreak += 1
            pcall(function()
                local r = S.getRoot()
                if r then
                    S.requestStreamAround(r.Position, 1.0)
                end
            end)
            local maxEmpty = opts.emptyStreakMax or 3
            if emptyStreak >= maxEmpty then
                break
            end
            task.wait(opts.emptyWait or 0.04)
        else
            emptyStreak = 0
            task.wait(0.02)
        end
    end

    Money.trackedBagAt = Money.trackedBagAt or os.clock()
    return total
end

function S.bringItemToPlayer(item)
    local root = S.getRoot()
    local pos = S.getItemPosition(item)
    if not root or not pos then
        return false
    end

    local target = root.Position + Vector3.new(0, 1.5, 0) + root.CFrame.LookVector * 2
    local ok = pcall(function()
        if item:IsA("Model") then
            item:PivotTo(CFrame.new(target))
        elseif item:IsA("BasePart") then
            item.CFrame = CFrame.new(target)
        else
            local part = item:FindFirstChildWhichIsA("BasePart", true)
            if part then
                part.CFrame = CFrame.new(target)
            end
        end
    end)

    return ok
end

function S.getEquippedTool()
    local char = LocalPlayer.Character
    if not char then
        return nil
    end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            return child
        end
    end
    return nil
end

function S.isItemBagTool(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end
    local class = tool:GetAttribute("Class")
    local name = tool.Name or ""
    if class == "ItemBag" or name == "ItemBag" or name == "Large_Sack" then
        return true
    end
    return name:find("Sack", 1, true) ~= nil or name:find("Bag", 1, true) ~= nil
end

function S.isPickaxeTool(tool)
    if not tool then
        return false
    end
    local class = tool:GetAttribute("Class") or ""
    return class == "Pickaxe" or tool.Name:lower():find("pickaxe", 1, true) ~= nil
end

local PICKAXE_EQUIP_ORDER = {
    "Pickaxe_Kings",
    "Pickaxe_Phoenix",
    "Pickaxe_Void",
    "Pickaxe_Diamond",
    "Pickaxe_Gold",
    "Pickaxe_Golden",
    "Pickaxe_Steel",
    "Pickaxe_Rusty",
    "Pickaxe_Wooden",
    "Pickaxe_Wood",
}

-- Wiki tool table (damage / shop price) + King's above Phoenix.
-- Wood 5, Rusty 10, Steel 15, Golden 25, Diamond, Void, Phoenix, King's.
local PICKAXE_TIER_KEYS = {
    { key = "kings", rank = 100 },
    { key = "king", rank = 100 },
    { key = "phoenix", rank = 90 },
    { key = "void", rank = 80 },
    { key = "diamond", rank = 70 },
    { key = "golden", rank = 60 },
    { key = "gold", rank = 60 },
    { key = "steel", rank = 40 },
    { key = "rusty", rank = 20 },
    { key = "wooden", rank = 10 },
    { key = "wood", rank = 10 },
}

-- Best → worst. Achievement Excalibur, then King's / class endgame, then
-- the same material line as armor (Phoenix > Void > Diamond > Gold > Steel > Rusty > Wood).
local SWORD_EQUIP_ORDER = {
    "Sword_Excalibur",
    "Sword_Kingslayer",
    "Sword_Kings",
    "Sword_Executioner",
    "Sword_Samurai",
    "Sword_Katana",
    "Sword_Phoenix",
    "Sword_Void",
    "Sword_Diamond",
    "Sword_Gold",
    "Sword_Golden",
    "Sword_BountyHunter",
    "Sword_Steel",
    "Sword_Rusty",
    "Sword_Wooden",
    "Sword_Wood",
}

local SWORD_TIER_KEYS = {
    { key = "excalibur", rank = 120 },
    { key = "kingslayer", rank = 110 },
    { key = "kings", rank = 110 },
    { key = "executioner", rank = 105 },
    { key = "samurai", rank = 100 },
    { key = "katana", rank = 100 },
    { key = "phoenix", rank = 90 },
    { key = "void", rank = 80 },
    { key = "diamond", rank = 70 },
    { key = "bountyhunter", rank = 60 },
    { key = "golden", rank = 50 },
    { key = "gold", rank = 50 },
    { key = "steel", rank = 40 },
    { key = "rusty", rank = 20 },
    { key = "wooden", rank = 10 },
    { key = "wood", rank = 10 },
}

-- Armor achievements (cores): King's 500 > Phoenix 350 > Void 300 > Diamond 225
-- > Gold 175 > Steel 125 > Rusty 60. Class sets stay under the material line.
local ARMOR_TIER_KEYS = {
    { key = "kings", rank = 100 },
    { key = "king", rank = 100 },
    { key = "phoenix", rank = 90 },
    { key = "void", rank = 80 },
    { key = "diamond", rank = 70 },
    { key = "golden", rank = 60 },
    { key = "gold", rank = 60 },
    { key = "steel", rank = 50 },
    { key = "rusty", rank = 40 },
    { key = "executioner", rank = 36 },
    { key = "samurai", rank = 35 },
    { key = "goblinking", rank = 34 },
    { key = "bountyhunter", rank = 33 },
    { key = "pirate", rank = 32 },
    { key = "princess", rank = 31 },
    { key = "reaper", rank = 30 },
    { key = "bruiser", rank = 28 },
    { key = "gunslinger", rank = 27 },
    { key = "demolitionist", rank = 26 },
    { key = "mechanic", rank = 24 },
    { key = "luckylooter", rank = 23 },
    { key = "scout", rank = 22 },
    { key = "racer", rank = 21 },
    { key = "driller", rank = 20 },
    { key = "tank", rank = 19 },
    { key = "healer", rank = 18 },
    { key = "medic", rank = 18 },
    { key = "miner", rank = 10 },
}

function S.findToolInInventory(predicate)
    local containers = {}
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if char then
        table.insert(containers, char)
    end
    if backpack then
        table.insert(containers, backpack)
    end

    for _, container in ipairs(containers) do
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") and predicate(child) then
                return child
            end
        end
    end

    return nil
end

function S.waitForKnitPromise(promise, timeoutSeconds)
    if typeof(promise) ~= "table" or not promise.andThen then
        return promise
    end

    local finished = false
    local value

    promise:andThen(function(result)
        value = result
        finished = true
    end):catch(function(err)
        value = err
        finished = true
    end)

    local deadline = os.clock() + (timeoutSeconds or 2)
    while not finished and os.clock() < deadline do
        task.wait()
    end

    return value
end

function S.callEquipTool(toolOrName)
    if not Services.ToolService then
        return false
    end

    local result = Services.ToolService:EquipTool(toolOrName)
    S.waitForKnitPromise(result, 2)
    return true
end

function S.ensureItemBag(fast)
    -- Sack/ItemBag sudah dihapus (update 31 Oct): item langsung ke hotbar/inventory.
end

function S.tryEquipItemBag()
    -- no-op: tidak ada ItemBag lagi.
end

function S.tryEquipPickaxe()
    if Pickaxe.autoEquip then
        S.ensurePickaxe()
    end
end

function S.findBestPickaxe()
    local bestTool = nil
    local bestRank = -1
    local function consider(tool)
        if not tool or not tool:IsA("Tool") then
            return
        end
        if not S.isPickaxeTool(tool) and not S.isPickaxeWorldItem(tool) then
            return
        end
        local rank = S.tierFromKeys(S.normalizeGearToken(tool.Name), PICKAXE_TIER_KEYS)
        if rank > bestRank then
            bestRank = rank
            bestTool = tool
        end
    end
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if char then
        for _, child in ipairs(char:GetChildren()) do
            consider(child)
        end
    end
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            consider(child)
        end
    end
    if bestTool then
        return bestTool
    end
    return S.findToolInInventory(S.isPickaxeTool)
end

function S.ensurePickaxe(timeout)
    if not Services.ToolService then
        return false
    end

    local equipped = S.getEquippedTool()
    if equipped and S.isPickaxeTool(equipped) then
        return true
    end

    -- Sword/gun in hand from Kill Aura — unequip first or EquipTool can no-op.
    if equipped and (S.isCombatTool(equipped) or S.isItemBagTool(equipped)) then
        pcall(function()
            Services.ToolService:UnequipTool()
        end)
        task.wait(0.05)
    end

    local pickaxe = S.findBestPickaxe()
    if pickaxe then
        S.callEquipTool(pickaxe)
    else
        S.callEquipTool("Pickaxe_Rusty")
    end

    local waitFor = tonumber(timeout) or 2.5
    local deadline = os.clock() + waitFor
    while os.clock() < deadline do
        equipped = S.getEquippedTool()
        if equipped and S.isPickaxeTool(equipped) then
            return true
        end
        -- Re-assert if combat re-equipped a sword mid-wait.
        if equipped and S.isCombatTool(equipped) then
            pcall(function()
                Services.ToolService:UnequipTool()
            end)
            if pickaxe then
                S.callEquipTool(pickaxe)
            end
        end
        task.wait(0.05)
    end

    equipped = S.getEquippedTool()
    return equipped ~= nil and S.isPickaxeTool(equipped)
end

function S.bagPickup(item)
    if not item or not item.Parent or not Services.InteractionService then
        return false
    end
    -- Interact range pendek: bawa ITEM ke pemain (pemain tidak dipindah).
    local root = S.getRoot()
    local pos = S.getItemPosition(item)
    if root and pos and (root.Position - pos).Magnitude > 12 then
        pcall(S.bringItemToPlayer, item)
        task.wait(0.04)
    end
    return pcall(function()
        Services.InteractionService:Interact(item)
    end)
end

-- Fire OK ≠ stored. Confirm bag fill or item left Workspace.Items.
function S.sackPickupVerified(item)
    if not item or not item.Parent then
        return false
    end
    local itemsFolder = Workspace:FindFirstChild("Items")
    local toolsBefore = #S.ownedToolList()
    if not S.bagPickup(item) then
        return false
    end
    task.wait(0.05)
    if item.Parent and itemsFolder and item:IsDescendantOf(itemsFolder) then
        S.bagPickup(item)
        task.wait(0.04)
    end

    local gone = (not item.Parent) or (itemsFolder and not item:IsDescendantOf(itemsFolder))
    if gone then
        -- Bukan tool (ore, scrap, mayat, dll) -> masuk inventory, hitung sendiri.
        if #S.ownedToolList() <= toolsBefore then
            Money.trackedBagSize = (tonumber(Money.trackedBagSize) or 0) + 1
            Money.trackedBagAt = os.clock()
        end
        S.markAutofarmDrillDropPending(item)
        return true
    end
    return false
end

-- Drop SATU item dari inventory/hotbar (dulu dari sack). Senjata, pickaxe, pedang, dan item
-- Phoenix tidak pernah di-drop. Return true kalau ada item yang berhasil di-drop.
function S.bagDrop()
    for _ = 1, 3 do
        local candidate
        for _, tool in ipairs(S.ownedToolList()) do
            if not S.isSellProtected(tool)
                and os.clock() - (S.ShardUse._fail[tool] or -999) > 3 then
                candidate = tool
                break
            end
        end
        if not candidate then
            break
        end
        if S.shardDropTool(candidate) then
            return true
        end
    end
    -- Item non-tool (ore, scrap, mayat): butuh API drop inventory game (lihat Copy Inventory Debug Info).
    if type(S.dropNonToolInventoryItem) == "function" then
        return S.dropNonToolInventoryItem() == true
    end
    return false
end

function S.dropAllFromBagInstant()
    if not Services.ToolService then
        return 0
    end

    local dropped = 0
    for _ = 1, 40 do
        if S.bagDrop() then
            dropped += 1
        end
    end

    return dropped
end

function S.getDrill()
    return Workspace:FindFirstChild("Drill")
end

function S.getDrillCabinSeat()
    local drill = S.getDrill()
    if not drill then
        return nil
    end

    local names = { "LocalDriverSeat", "DrillPhysicsSeat", "VehicleSeat" }
    for _, name in ipairs(names) do
        local seat = drill:FindFirstChild(name, true)
        if seat and seat:IsA("BasePart") then
            return seat
        end
    end

    for _, desc in ipairs(drill:GetDescendants()) do
        if desc:IsA("VehicleSeat") then
            return desc
        end
    end

    return nil
end

function S.isLocalDrillDriver()
    local drill = S.getDrill()
    if not drill then
        return false
    end
    local driverId = drill:GetAttribute("DriverUserId")
    return typeof(driverId) == "number" and driverId == LocalPlayer.UserId
end

function S.sitInDrillCabin()
    local seat = S.getDrillCabinSeat()
    local root = S.getRoot()
    local humanoid = S.getHumanoid()
    if not seat then
        return false, "Cabin not found"
    end
    if not root or not humanoid then
        return false, "Character not found"
    end

    root.Anchored = false
    root.CFrame = seat.CFrame * CFrame.new(0, 2.5, 0)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    S.requestStreamAround(seat.Position, 0.4)
    task.wait(0.1)

    pcall(function()
        humanoid.Sit = true
    end)
    if seat:IsA("VehicleSeat") then
        pcall(function()
            seat:Sit(humanoid)
        end)
    end

    return true
end

function S.leaveDrillCabin()
    local humanoid = S.getHumanoid()
    if humanoid then
        pcall(function()
            humanoid.Sit = false
        end)
    end
end

function S.releaseAutofarmSeat()
    if AutoDrive.enabled then
        pcall(function()
            S.setAutoDrive(false)
        end)
    end
    S.leaveDrillCabin()
    local char = LocalPlayer.Character
    if not char then
        return
    end
    pcall(function()
        for _, inst in ipairs(char:GetDescendants()) do
            if inst:IsA("Weld") and inst.Name == "SeatWeld" then
                inst:Destroy()
            end
        end
    end)
end

function S.stopAutoDriveThrottle()
    S.disconnectAll("autoDriveThrottle")
    if Services.DrillService then
        pcall(function()
            Services.DrillService:UpdateDriverThrottle(0)
        end)
        pcall(function()
            Services.DrillService:StopDriving()
        end)
    end
end

function S.startAutoDriveThrottleLoop()
    S.disconnectAll("autoDriveThrottle")
    State.connections.autoDriveThrottle = RunService.Heartbeat:Connect(function()
        if not AutoDrive.enabled then
            return
        end
        if not Services.DrillService then
            return
        end
        if not S.isLocalDrillDriver() then
            return
        end
        pcall(function()
            Services.DrillService:UpdateDriverThrottle(1)
        end)
    end)
end

function S.setAutoDrive(enabled)
    enabled = enabled == true

    if not enabled then
        AutoDrive.claimGen += 1
        AutoDrive.enabled = false
        AutoDrive.claiming = false
        S.stopAutoDriveThrottle()
        S.leaveDrillCabin()
        return true
    end

    if AutoDrive.enabled or AutoDrive.claiming then
        return true
    end

    if not Services.DrillService then
        S.notify("Drill", "Game services not ready yet", 4)
        return false
    end

    AutoDrive.claimGen += 1
    local gen = AutoDrive.claimGen
    AutoDrive.claiming = true

    task.spawn(function()
        local okSit, sitErr = S.sitInDrillCabin()
        if gen ~= AutoDrive.claimGen then
            return
        end
        if not okSit then
            AutoDrive.claiming = false
            S.notify("Drill", tostring(sitErr or "Cabin not found"), 4)
            return
        end

        task.wait(0.25)
        if gen ~= AutoDrive.claimGen then
            return
        end

        local result = true
        if not S.isLocalDrillDriver() then
            result = S.waitForKnitPromise(Services.DrillService:StartDriving(), 5)
        end
        if gen ~= AutoDrive.claimGen then
            return
        end

        AutoDrive.claiming = false

        if result ~= true and not S.isLocalDrillDriver() then
            S.notify("Drill", "Failed to claim driver — sit in the cabin and retry", 5)
            return
        end

        -- Keep seated; game requires cabin seat to drive.
        S.sitInDrillCabin()
        AutoDrive.enabled = true
        S.startAutoDriveThrottleLoop()
        S.notify("Drill", "Auto Drive ON — seated + throttle", 3)
    end)

    return true
end

function S.getPartCorners(cf, size)
    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
    local corners = {}
    for _, xSign in ipairs({ -1, 1 }) do
        for _, ySign in ipairs({ -1, 1 }) do
            for _, zSign in ipairs({ -1, 1 }) do
                table.insert(corners, (cf * CFrame.new(xSign * hx, ySign * hy, zSign * hz)).Position)
            end
        end
    end
    return corners
end

function S.getDrillTruckRegion()
    local drill = S.getDrill()
    if not drill then
        return nil
    end

    local look = Vector3.new(drill:GetPivot().LookVector.X, 0, drill:GetPivot().LookVector.Z)
    if look.Magnitude < 0.05 then
        local head = drill:FindFirstChild("DrillHead", true)
        if head and head:IsA("BasePart") then
            look = Vector3.new(head.CFrame.LookVector.X, 0, head.CFrame.LookVector.Z)
        end
    end
    if look.Magnitude < 0.05 and drill.PrimaryPart then
        look = Vector3.new(drill.PrimaryPart.CFrame.LookVector.X, 0, drill.PrimaryPart.CFrame.LookVector.Z)
    end
    if look.Magnitude < 0.05 then
        return nil
    end
    look = look.Unit

    local right = Vector3.new(-look.Z, 0, look.X).Unit

    local origin = drill:GetPivot().Position
    local minForward, maxForward = math.huge, -math.huge
    local minRight, maxRight = math.huge, -math.huge
    local minUp, maxUp = math.huge, -math.huge
    local found = false

    for _, part in ipairs(drill:GetDescendants()) do
        if part:IsA("BasePart") then
            found = true
            for _, corner in ipairs(S.getPartCorners(part.CFrame, part.Size)) do
                local rel = corner - origin
                local forward = rel:Dot(look)
                local sideways = rel:Dot(right)
                local vertical = rel.Y
                minForward = math.min(minForward, forward)
                maxForward = math.max(maxForward, forward)
                minRight = math.min(minRight, sideways)
                maxRight = math.max(maxRight, sideways)
                minUp = math.min(minUp, vertical)
                maxUp = math.max(maxUp, vertical)
            end
        end
    end

    if not found then
        return nil
    end

    minForward -= Loot.truckZonePadLength
    maxForward += Loot.truckZonePadLength
    minRight -= Loot.truckZonePadWidth
    maxRight += Loot.truckZonePadWidth
    minUp -= Loot.truckZonePadHeight
    maxUp += Loot.truckZonePadHeight

    local centerForward = (minForward + maxForward) / 2
    local centerRight = (minRight + maxRight) / 2
    local centerUp = (minUp + maxUp) / 2
    local sizeForward = math.max(maxForward - minForward, 4)
    local sizeRight = math.max(maxRight - minRight, 4)
    local sizeUp = math.max(maxUp - minUp, 4)

    local centerWorld = origin + look * centerForward + right * centerRight + Vector3.new(0, centerUp, 0)

    return {
        cframe = CFrame.lookAt(centerWorld, centerWorld + look, Vector3.yAxis),
        size = Vector3.new(sizeRight, sizeUp, sizeForward),
    }
end

function S.isPointInTruckRegion(point, region)
    if not point or not region then
        return false
    end

    local localPos = region.cframe:PointToObjectSpace(point)
    local half = region.size * 0.5
    return math.abs(localPos.X) <= half.X
        and math.abs(localPos.Y) <= half.Y
        and math.abs(localPos.Z) <= half.Z
end

function S.getDrillFuelPoint()
    local drill = S.getDrill()
    if not drill then
        return nil
    end

    -- Actual fuel intake (firebox touch zone) — not generic WeldParts on the floor
    local fuelTouch = drill:FindFirstChild("FuelTouchPart", true)
    if fuelTouch and fuelTouch:IsA("BasePart") then
        return fuelTouch
    end

    local furnace = drill:FindFirstChild("Furnace", true)
    if furnace and furnace:IsA("BasePart") then
        return furnace
    end

    -- Fallback: WeldPart nearest the fuel gauge / furnace area
    local anchor = drill:FindFirstChild("FuelGauge", true) or drill.PrimaryPart
    local bestPart, bestDist = nil, math.huge

    if anchor then
        for _, part in ipairs(drill:GetDescendants()) do
            if part:IsA("BasePart") and CollectionService:HasTag(part, "WeldPart") then
                local dist = (part.Position - anchor.Position).Magnitude
                if dist < bestDist then
                    bestPart = part
                    bestDist = dist
                end
            end
        end
    end

    return bestPart or drill:FindFirstChildWhichIsA("BasePart", true)
end

-- Cart / trailer bed for locking fuel with Z (NOT the furnace / FuelTouchPart).
function S.getDrillBedWeldPart()
    local drill = S.getDrill()
    if not drill then
        return nil
    end

    local fuelTouch = drill:FindFirstChild("FuelTouchPart", true)
    local furnace = drill:FindFirstChild("Furnace", true)
    local best, bestArea = nil, 0

    for _, part in ipairs(drill:GetDescendants()) do
        if part:IsA("BasePart") and CollectionService:HasTag(part, "WeldPart") then
            if part == fuelTouch or part == furnace then
                continue
            end
            local n = string.lower(part.Name or "")
            if n:find("fuel", 1, true) or n:find("furnace", 1, true) or n:find("fire", 1, true) then
                continue
            end
            local area = part.Size.X * part.Size.Z
            if area > bestArea then
                bestArea = area
                best = part
            end
        end
    end

    if best then
        return best
    end

    -- Any WeldPart that isn't the firebox.
    for _, part in ipairs(drill:GetDescendants()) do
        if part:IsA("BasePart")
            and CollectionService:HasTag(part, "WeldPart")
            and part ~= fuelTouch
            and part ~= furnace
        then
            return part
        end
    end

    return drill.PrimaryPart or drill:FindFirstChildWhichIsA("BasePart", true)
end

-- Rear of the trailer = away from FuelTouchPart / Furnace / DrillHead (not into the firebox).
function S.getDrillTrailerBackDirection(bed, drill)
    drill = drill or S.getDrill()
    bed = bed or S.getDrillBedWeldPart()

    local fuel = nil
    if drill then
        fuel = drill:FindFirstChild("FuelTouchPart", true)
            or drill:FindFirstChild("Furnace", true)
            or drill:FindFirstChild("DrillHead", true)
    end

    local origin = (bed and bed.Position) or (drill and drill:GetPivot().Position)
    if not origin then
        return Vector3.new(0, 0, 1)
    end

    if fuel and fuel:IsA("BasePart") then
        -- From furnace/head toward bed, then keep going = trailer rear.
        local flat = Vector3.new(origin.X - fuel.Position.X, 0, origin.Z - fuel.Position.Z)
        if flat.Magnitude > 0.5 then
            return flat.Unit
        end
    end

    local dig = S.getDrillFlatLook and S.getDrillFlatLook() or nil
    if dig and dig.Magnitude > 0.05 then
        return -dig.Unit -- dig forward → trailer back
    end

    if bed then
        local look = Vector3.new(bed.CFrame.LookVector.X, 0, bed.CFrame.LookVector.Z)
        if look.Magnitude > 0.05 then
            return -look.Unit
        end
    end

    return Vector3.new(0, 0, 1)
end

function S.getDrillBedParkCFrame(index)
    local bed = S.getDrillBedWeldPart()
    local drill = S.getDrill()
    if not bed and not drill then
        return nil
    end

    index = tonumber(index) or 0
    local col = index % 4
    local row = math.floor(index / 4)
    local ox = (col - 1.5) * 1.4
    local rowBack = (row % 4) * 1.15
    local backDir = S.getDrillTrailerBackDirection(bed, drill)
    local right = Vector3.new(-backDir.Z, 0, backDir.X)

    if bed then
        -- Park on the REAR half of the bed (carreta), clear of the firebox.
        local halfDepth = math.max(bed.Size.X, bed.Size.Z) * 0.5
        local rearBias = math.max(10, halfDepth * 0.75)
        local up = bed.Size.Y * 0.5 + 1.25
        local pos = bed.Position
            + backDir * (rearBias + rowBack)
            + right * ox
            + Vector3.new(0, up, 0)
        return CFrame.lookAt(pos, pos + backDir)
    end

    local pivot = drill:GetPivot().Position
    local pos = pivot + backDir * (14 + rowBack) + right * ox + Vector3.new(0, 3.5, 0)
    return CFrame.lookAt(pos, pos + backDir)
end

-- Stand on trailer rear so bag drops land on the carreta, not the furnace.
function S.getDrillTrailerStandPosition()
    local bed = S.getDrillBedWeldPart()
    local drill = S.getDrill()
    local park = S.getDrillBedParkCFrame(0)
    local backDir = S.getDrillTrailerBackDirection(bed, drill)
    if park then
        return park.Position + Vector3.new(0, 2.4, 0) + backDir * 2
    end
    if bed then
        return bed.Position + backDir * 12 + Vector3.new(0, 4, 0)
    end
    if drill then
        return drill:GetPivot().Position + backDir * 16 + Vector3.new(0, 5, 0)
    end
    return nil
end

function S.getDrillReturnCFrame()
    local stand = S.getDrillTrailerStandPosition()
    if stand then
        return CFrame.new(stand)
    end
    local seat = S.getDrillCabinSeat()
    if seat then
        return seat.CFrame * CFrame.new(0, 3.5, 0)
    end
    local drill = S.getDrill()
    if drill then
        return drill:GetPivot() * CFrame.new(0, 6, 14)
    end
    return nil
end

function S.stopFarmLoopsSoft()
    Autofarm.busy = false
    Autofarm._cycleRunning = false
    Autofarm.moving = false
    Autofarm.miningBusy = false
    Autofarm._oreHuntMode = false
    Autofarm._miningBusySince = nil
    Autofarm._busySince = nil
    Autofarm._cycleAbort = true
    Autofarm._gatePinY = nil
    Autofarm.resumePocketDistance = nil
    Autofarm.resumePocketPos = nil
    Autofarm.sellFromPos = nil
    S.cancelAutofarmTween()
    S.releaseCharacterHold()
    S.clearDragTarget()
end

-- Hard release so the character never stays stuck after toggling farms off.
function S.forceReleaseFarmCharacter()
    Autofarm._farmShuttingDown = true
    Autofarm._returningToDrill = false
    Autofarm.hoverLocked = false
    S.stopFarmLoopsSoft()
    S.disconnectAll("autofarm")
    S.disconnectAll("autofarmGlide")
    S.disconnectAll("autofarmHover")
    S.disconnectAll("autofarmAntiFall")
    S.ensureAutofarmAntiFall(false)
    S.lockAutofarmHover(false)
    S.resetAutofarmCharacterState()
    S.setAutofarmCameraAssist(false)
    local humanoid = S.getHumanoid()
    if humanoid then
        pcall(function()
            humanoid.Sit = false
            humanoid.PlatformStand = false
        end)
    end
    local root = S.getRoot()
    if root then
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    if Autofarm.ownedNoclip then
        S.setNoclip(false)
        Autofarm.ownedNoclip = false
    end
    Autofarm._farmShuttingDown = false
end

-- Clear Scrap mode flag/state without requiring the Rayfield toggle again.
function S.clearScrapFarmState(restoreSettings)
    local saved = Autofarm.scrapSaved
    Autofarm.scrapFarm = false
    Autofarm.scrapPhase = "seek_pick"
    Autofarm.scrapSeekLaps = 0
    Autofarm.scrapSaved = nil
    Autofarm._scrapOwnedAutofarm = false
    Autofarm._scrapHadAutofarm = false
    S.trySetRayfieldFlag("terra_af_scrap_farm", false, true)
    if restoreSettings ~= false and saved then
        S.restoreScrapSettings(saved)
    end
    return saved
end

-- After any farm OFF: stop mid-action and park at the drill (no void / no stuck PlatformStand).
function S.returnToDrillAfterFarmStop(opts)
    opts = type(opts) == "table" and opts or {}
    local keepEngine = opts.keepEngine == true
    local force = opts.force == true

    if Autofarm._returningToDrill and not force then
        return
    end
    Autofarm._returnGen = (Autofarm._returnGen or 0) + 1
    local gen = Autofarm._returnGen
    Autofarm._returningToDrill = true
    Autofarm._farmShuttingDown = true

    local function stale()
        return Autofarm.enabled == true or gen ~= Autofarm._returnGen
    end

    task.spawn(function()
        local ok, err = pcall(function()
            task.wait(0.05)
            if stale() then
                return
            end
            S.stopFarmLoopsSoft()
            S.ensureAutofarmAntiFall(false)
            S.lockAutofarmHover(false)

            local humanoid = S.getHumanoid()
            if humanoid then
                pcall(function()
                    humanoid.Sit = false
                    humanoid.PlatformStand = false
                end)
            end

            local target = S.getDrillReturnCFrame()
            local root = S.getRoot()
            if root and target then
                pcall(function()
                    S.requestStreamAround(target.Position, 1.0)
                end)
                task.wait(0.1)
                if stale() then
                    return
                end
                root = S.getRoot()
                if root then
                    root.Anchored = false
                    root.CFrame = target
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    task.wait(0.08)
                    if stale() then
                        return
                    end
                    root = S.getRoot()
                    if root then
                        root.CFrame = target
                        root.AssemblyLinearVelocity = Vector3.zero
                        root.AssemblyAngularVelocity = Vector3.zero
                    end
                end
            end

            if stale() then
                return
            end
            if keepEngine and Autofarm.enabled then
                Autofarm._farmShuttingDown = false
                S.resetAutofarmStart()
                S.setAutofarmPlatformStand(true)
                S.ensureAutofarmAntiFall(true)
                S.lockAutofarmHover(true)
                S.notify("Autofarm", "Back at drill", 3)
            else
                S.forceReleaseFarmCharacter()
                S.notify("Autofarm", "Stopped — back at drill", 3)
            end
        end)

        if not ok then
            warn("[TERRA HUB] returnToDrill", err)
            pcall(S.forceReleaseFarmCharacter)
        end
        Autofarm._returningToDrill = false
        Autofarm._farmShuttingDown = false
    end)
end

function S.getItemBaseParts(item)
    local parts = {}
    if not item then
        return parts
    end
    if item:IsA("BasePart") then
        table.insert(parts, item)
    elseif item:IsA("Model") then
        for _, desc in ipairs(item:GetDescendants()) do
            if desc:IsA("BasePart") then
                table.insert(parts, desc)
            end
        end
    end
    return parts
end

function S.isItemTouchingTruckWeld(item)
    local drill = S.getDrill()
    if not drill then
        return false
    end

    for _, part in ipairs(S.getItemBaseParts(item)) do
        local touchingOk, touching = pcall(function()
            return part:GetTouchingParts()
        end)
        if touchingOk and touching then
            for _, other in ipairs(touching) do
                if other:IsDescendantOf(drill) and CollectionService:HasTag(other, "WeldPart") then
                    return true
                end
            end
        end
    end

    return false
end

function S.isItemInTruckZone(item)
    if not item or not item.Parent then
        return false
    end

    local drill = S.getDrill()
    if drill and item:IsDescendantOf(drill) then
        return true
    end

    local pos = S.getItemPosition(item)
    local region = State.cachedTruckRegion or S.getDrillTruckRegion()
    if pos and region and S.isPointInTruckRegion(pos, region) then
        return true
    end

    return S.isItemTouchingTruckWeld(item)
end

function S.shouldSkipAutoLoot(item)
    -- Autofarm never scoops loot already on/in the truck (dumped ore, welded, etc).
    if Autofarm.enabled and S.isItemInTruckZone(item) then
        return true
    end
    -- Scrap Farm only yanks selected smeltable ores + their bars.
    if S.isScrapFarmMode() then
        return not (S.isScrapSelectedOreItem(item) or S.isScrapSelectedBarItem(item))
    end
    if not Loot.skipTruckLoot then
        return false
    end
    return S.isItemInTruckZone(item)
end

function S.getFuelDepositCFrame(fuelPoint)
    -- FuelTouchPart sits at the furnace opening; slight inward offset helps consumption
    if fuelPoint.Name == "FuelTouchPart" then
        return fuelPoint.CFrame * CFrame.new(0, 0.4, 0)
    end
    if fuelPoint.Name == "Furnace" then
        return fuelPoint.CFrame * CFrame.new(0, 1, 0)
    end
    return fuelPoint.CFrame * CFrame.new(0, 1.2, 0)
end

function S.moveItemToCFrame(item, cf)
    return pcall(function()
        if item:IsA("Model") then
            item:PivotTo(cf)
        elseif item:IsA("BasePart") then
            item.CFrame = cf
        else
            local part = item:FindFirstChildWhichIsA("BasePart", true)
            if part then
                part.CFrame = cf
            end
        end
    end)
end

function S.isWorldToolItem(item)
    if not item then
        return false
    end

    if item:IsA("Tool") or item:GetAttribute("Tool") == true then
        return true
    end

    local class = string.lower(item:GetAttribute("Class") or "")
    local cat = S.itemCategoryKey(item)
    local name = string.lower(item.Name)

    local toolClasses = {
        pickaxe = true,
        sword = true,
        gun = true,
        itembag = true,
        revolver = true,
        rifle = true,
        shotgun = true,
        rpg = true,
        blackholegun = true,
        blackhole = true,
        champions = true,
    }
    if toolClasses[class] then
        return true
    end

    local toolCategories = {
        tool = true,
        pickaxe = true,
        sword = true,
        ["primary weapon"] = true,
        ["secondary weapon"] = true,
        consumable = true,
        medkit = true,
        armor = true,
    }
    if toolCategories[cat] then
        return true
    end

    if item:GetAttribute("Ammo") ~= nil or item:GetAttribute("SwingRate") ~= nil then
        return true
    end

    if name:find("^pickaxe_", 1) or name:find("^sword_", 1) then
        return true
    end

    if name:find("rifle", 1, true) or name:find("shotgun", 1, true)
        or name:find("revolver", 1, true) or name:find("rpg", 1, true)
        or name:find("blackhole", 1, true) or name:find("medkit", 1, true)
        or name:find("speedpotion", 1, true) or name:find("landmine", 1, true)
        or name:find("magnet", 1, true) or name == "itembag" then
        return true
    end

    return false
end

function S.isFuelItem(item)
    if not item or S.isWorldToolItem(item) then
        return false
    end

    local fuel = item:GetAttribute("Fuel")
    if typeof(fuel) == "number" and fuel > 0 then
        return true
    end
    if item:GetAttribute("Category") == "Corpse" then
        return true
    end
    if item.Name == "GasCan" then
        return true
    end
    return false
end

function S.depositFuelItem(item)
    local fuelPoint = S.getDrillFuelPoint()
    if not fuelPoint then
        return false
    end

    local depositCf = S.getFuelDepositCFrame(fuelPoint)
    S.moveItemToCFrame(item, depositCf)
    task.wait(0.08)
    S.moveItemToCFrame(item, fuelPoint.CFrame)
    task.wait(0.08)

    local ok = false
    if Services.DragService then
        ok = pcall(function()
            Services.DragService:Request(item)
            task.wait(0.12)
            S.moveItemToCFrame(item, fuelPoint.CFrame)
            task.wait(0.1)
            Services.DragService:Cancel()
        end) or ok
    end

    if Services.InteractionService then
        ok = pcall(function()
            Services.InteractionService:Interact(item)
        end) or ok
    end

    return ok
end

function S.collectFuelItems()
    local items = {}
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder then
        return items
    end

    for _, child in ipairs(itemsFolder:GetChildren()) do
        if S.isFuelItem(child) and not S.isHardExcluded(child) then
            table.insert(items, child)
        end
    end

    table.sort(items, function(a, b)
        local posA = S.getItemPosition(a)
        local posB = S.getItemPosition(b)
        if not posA then
            return false
        end
        if not posB then
            return true
        end
        return LocalPlayer:DistanceFromCharacter(posA) < LocalPlayer:DistanceFromCharacter(posB)
    end)

    return items
end

-- Loot reach = ESP reach (flat). What ESP can see is what the sack can yank.
function S.getLootMaxRange()
    return Esp.maxRange or Loot.range or 2000
end

-- Chest / ore detection shares Auto Loot / ESP max range.
function S.getLootDetectRange()
    return S.getLootMaxRange()
end

-- Autofarm must NOT use full loot/ESP range to STOP cruise — that softlocks mid-air.
function S.getAutofarmChestOreRange()
    local loot = S.getLootDetectRange()
    local cap = Autofarm.chestOreStopRange or 220
    return math.clamp(loot, 30, cap)
end

-- Same tight cap for "is there loot beside me?" cruise stops.
function S.getAutofarmCruiseStopRange()
    return S.getAutofarmChestOreRange()
end

-- After entering a mine / while digging: hunt ores much farther than cruise-stop range.
function S.getAutofarmOreHuntRange()
    local loot = S.getLootDetectRange()
    return math.clamp(loot, 400, math.max(S.getLootMaxRange(), 1200))
end

function S.markOreSkip(ore, seconds)
    if not ore then
        return
    end
    Autofarm.skipOresUntil = Autofarm.skipOresUntil or {}
    Autofarm.skipOresUntil[ore] = tick() + (seconds or 45)
end

function S.isOreSkipped(ore)
    if not ore then
        return true
    end
    Autofarm.skipOresUntil = Autofarm.skipOresUntil or {}
    local untilTick = Autofarm.skipOresUntil[ore]
    if untilTick and tick() < untilTick then
        return true
    end
    if untilTick then
        Autofarm.skipOresUntil[ore] = nil
    end
    return false
end

function S.runFuelCycle()
    local drill = S.getDrill()
    if not drill or not Services.DragService then
        return 0
    end

    local fuel = drill:GetAttribute("Fuel") or 0
    local maxFuel = drill:GetAttribute("MaxFuel") or 100
    if fuel >= maxFuel * Loot.fuelThreshold then
        return 0
    end

    local processed = 0
    for _, item in ipairs(S.collectFuelItems()) do
        fuel = drill:GetAttribute("Fuel") or 0
        if fuel >= maxFuel * 0.98 then
            break
        end

        local pos = S.getItemPosition(item)
        if pos then
            local dist = LocalPlayer:DistanceFromCharacter(pos)
            if dist > Loot.pickupRange and dist <= Loot.range then
                S.bringItemToPlayer(item)
                task.wait(0.05)
                pos = S.getItemPosition(item) or pos
                dist = LocalPlayer:DistanceFromCharacter(pos)
            end
            if dist <= Loot.pickupRange + 8 then
                if S.depositFuelItem(item) then
                    processed += 1
                end
                task.wait(0.2)
            end
        end
    end

    return processed
end

function S.setAutoFuel(enabled)
    Loot.autoFuel = enabled
    S.disconnectAll("autoFuel")

    if not enabled then
        return
    end

    State.connections.autoFuel = RunService.Heartbeat:Connect(function()
        if not Loot.autoFuel or Loot.fuelBusy or (tick() - (State.lastFuelTick or 0)) < 1.2 then
            return
        end
        State.lastFuelTick = tick()
        Loot.fuelBusy = true
        task.spawn(function()
            pcall(S.runFuelCycle)
            Loot.fuelBusy = false
        end)
    end)
end

function S.ensureBagReadyForLoot()
    -- no-op: tidak perlu memegang bag untuk loot.
    return nil
end

function S.runLootCycle(opts)
    opts = type(opts) == "table" and opts or {}
    if not Services.ToolService then
        return 0
    end

    -- miningBusy used to block ALL loot — that killed mine drop pickup after ore break.
    if Autofarm.miningBusy and not opts.duringMine then
        return 0
    end

    if S.isBagFull() then
        return 0
    end

    local targets = S.collectLootTargets()
    if #targets == 0 then
        if not opts.fast then
            pcall(S.runAutoEquipBestPass)
        end
        return 0
    end

    local processed = 0
    local root = S.getRoot()
    local lootRange = opts.nearRange or S.getLootMaxRange()
    local waitEach = opts.fast and 0.01 or 0.04
    State.cachedTruckRegion = (Loot.skipTruckLoot or Autofarm.enabled) and S.getDrillTruckRegion() or nil
    S.ensureBagReadyForLoot()

    for _, item in ipairs(targets) do
        if S.isBagFull() then
            break
        end
        if not S.shouldSkipAutoLoot(item) then
            local pos = S.getItemPosition(item)
            if not pos or not root then
                continue
            end
            -- Flat distance — same as ESP (deep shafts count).
            local dist = S.getFlatDistanceFromPosition(pos)
            if dist > lootRange then
                continue
            end

            local gearCat = S.getGearItemCategory(item)
            -- Weapon yang sudah ada / bukan upgrade (dan bukan Phoenix) tidak diambil lagi.
            if gearCat and GearEquip.enabled and S.isWeaponCategory(gearCat)
                and S.gearCategoryEnabled(gearCat) and not S.shouldAutoEquipWorldItem(item) then
                continue
            end
            if gearCat and S.gearCategoryEnabled(gearCat) and not opts.duringMine and not S.isScrapFarmMode() then
                -- Better → equip. Equal/worse → Instant Pickup into sack (no client bring).
                if S.shouldAutoEquipWorldItem(item) then
                    if S.equipWorldGearItem(item) then
                        processed += 1
                        task.wait(waitEach)
                    end
                else
                    if S.sackPickupVerified(item) then
                        processed += 1
                    end
                    task.wait(waitEach)
                    if processed >= (opts.batchSize or Loot.batchSize) then
                        break
                    end
                end
            else
                -- Instant Pickup with sack Range — no bring needed.
                if S.sackPickupVerified(item) then
                    processed += 1
                end
                task.wait(waitEach)
                if processed >= (opts.batchSize or Loot.batchSize) then
                    break
                end
            end
        end
    end

    if not opts.fast and not S.isScrapFarmMode() then
        pcall(S.runAutoEquipBestPass)
    end

    if Loot.autoDropAfterLoot then
        S.dropAllFromBagInstant()
    end

    return processed
end

function S.setDragTarget(item)
    local knit = S.getKnit()
    if not knit then
        return false
    end
    return pcall(function()
        local drag = knit.GetController("DragController")
        if not drag then
            return
        end
        drag.Target = item
        if drag.TargetChanged then
            drag.TargetChanged:Fire(item)
        end
    end)
end

function S.waitForItemBagEquipped(timeout)
    return nil
end

-- Real Instant Pickup: sack + Range + Drag target. No client bring.
function S.pickupWorldItemNow(item)
    if not item or not item.Parent then
        return false
    end

    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder or not item:IsDescendantOf(itemsFolder) then
        return false
    end
    if S.isHardExcluded(item) or S.shouldSkipAutoLoot(item) then
        return false
    end
    if not S.passesLootFilters(item) then
        return false
    end

    return S.sackPickupVerified(item)
end

function S.sweepGroundLootNearby(range)
    return S.pickupAllVisibleLoot({
        duringMine = true,
        seconds = 4,
        nearRange = range or S.getLootMaxRange(),
        requireAutofarm = false,
    })
end

-- After ore break: stay on cruise Y, then Auto Loot cycle until quiet.
function S.vacuumMineDrops(nearPos)
    if S.isBagFull() then
        return 0
    end

    local root = S.getRoot()
    nearPos = nearPos or (root and root.Position)
    if not nearPos then
        return 0
    end

    local flyY = S.getAutofarmFlyY()
    local hold = Vector3.new(nearPos.X, flyY, nearPos.Z)
    root = S.getRoot()
    if root then
        S.setAutofarmPlatformStand(true)
        root.Anchored = false
        root.CFrame = CFrame.lookAt(hold, Vector3.new(nearPos.X, hold.Y, nearPos.Z))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    S.lockAutofarmHover(true)
    pcall(function()
        S.requestStreamAround(hold, 1.2)
    end)

    if S.isScrapGoldPhase() then
        return S.yankScrapGoldLootNearby(900)
    end

    return S.pickupAllVisibleLoot({
        duringMine = true,
        seconds = 5,
        requireAutofarm = false,
    })
end

-- ========== MONEY FARM ==========
function S.boostToolRange(tool, targetRange)
    if not tool then
        return
    end
    local base = tool:GetAttribute("HubBaseRange") or tool:GetAttribute("Range") or 10
    if not tool:GetAttribute("HubBaseRange") then
        tool:SetAttribute("HubBaseRange", base)
    end
    tool:SetAttribute("Range", targetRange or base)
end

function S.findOresInRange(range)
    local ores = {}
    local root = S.getRoot()
    if not root or not S.isSaneWorldPos(root.Position) then
        return ores
    end

    local seen = {}
    S.forEachWorldOreNode(function(ore)
        if seen[ore] then
            return
        end
        local pos = S.getOreWorldPosition(ore) or S.getItemPosition(ore)
        if pos and S.isSaneOrePos(pos) and (pos - root.Position).Magnitude <= range then
            seen[ore] = true
            table.insert(ores, ore)
        end
    end)

    return ores
end

function S.getBagCapacity()
    -- Inventory baru: Carry Capacity awal 15 (hotbar ikut dihitung).
    local drill = S.getDrill()
    local sackStorage = drill and (drill:GetAttribute("SackStorage") or 0) or 0
    local extra = LocalPlayer:GetAttribute("ExtraSackStorage") and 5 or 0
    local configured = LocalPlayer:GetAttribute("CarryCapacity")
    if typeof(configured) == "number" and configured > 0 then
        return configured
    end
    return 15 + sackStorage * 2 + extra
end

function S.parseSackQuantity()
    local sackUi = LocalPlayer.PlayerGui:FindFirstChild("SackUI", true)
    if not sackUi then
        return nil, nil
    end

    local quantity = sackUi:FindFirstChild("Quantity", true)
    if not quantity or not quantity:IsA("TextLabel") then
        return nil, nil
    end

    local cur, maxv = quantity.Text:match("(%d+)%s*/%s*(%d+)")
    if cur then
        return tonumber(cur), tonumber(maxv)
    end

    local only = quantity.Text:match("^(%d+)")
    return only and tonumber(only) or nil, nil
end

-- Jumlah item yang bisa dijual (tool non-utama + item non-tool yang dilacak).
function S.getBagFillCount()
    local extra = tonumber(Money.trackedBagSize) or 0
    if extra > 0 and os.clock() - (Money.trackedBagAt or 0) > 60 then
        extra = 0
        Money.trackedBagSize = 0
    end
    local sellable = 0
    for _, tool in ipairs(S.ownedToolList()) do
        if not S.isSellProtected(tool) then
            sellable += 1
        end
    end
    return sellable + extra
end

function S.isBagFull()
    -- Penuh = seluruh slot (hotbar + inventory) mencapai Carry Capacity.
    local extra = tonumber(Money.trackedBagSize) or 0
    if extra > 0 and os.clock() - (Money.trackedBagAt or 0) > 60 then
        extra = 0
        Money.trackedBagSize = 0
    end
    return (#S.ownedToolList() + extra) >= S.getBagCapacity()
end

function S.getAutofarmSellThreshold()
    local cap = math.max(1, S.getBagCapacity())
    local thresh = math.floor(tonumber(Autofarm.sellThreshold) or cap)
    return math.clamp(thresh, 1, cap)
end

function S.isDropInDrillMode()
    return Autofarm.dropInDrill == true
end

function S.isDropInShredderMode()
    return Autofarm.dropInShredder == true
end

function S.getScrapOreTypes()
    local selected = Autofarm.scrapOreTypes
    local out, seen = {}, {}
    if type(selected) ~= "table" then
        selected = { selected }
    end
    for key, value in pairs(selected) do
        local raw = value
        if type(key) == "string" and (value == true or value == 1) then
            raw = key
        end
        if type(raw) == "table" then
            raw = raw[1] or raw.Name or raw.CurrentOption
        end
        local lower = string.lower(tostring(raw or ""))
        local canonical = nil
        if lower == "gold" then
            canonical = "Gold"
        elseif lower == "copper" or lower == "iron" then
            canonical = "Copper"
        else
            for _, opt in ipairs(SCRAP_ORE_OPTIONS) do
                if string.lower(opt) == lower then
                    canonical = opt
                    break
                end
            end
        end
        if canonical and not seen[canonical] then
            seen[canonical] = true
            table.insert(out, canonical)
        end
    end
    if #out == 0 then
        out = { "Gold" }
    end
    return out
end

function S.setScrapOreTypes(selected)
    Autofarm.scrapOreTypes = selected
    Autofarm.scrapOreTypes = S.getScrapOreTypes()
    if S.isScrapGoldPhase() then
        Autofarm.oreUnderTypes = table.clone and table.clone(Autofarm.scrapOreTypes)
            or { table.unpack(Autofarm.scrapOreTypes) }
        Autofarm._oreScanCache = nil
    end
end

function S.getScrapOreTypesLabel()
    return table.concat(S.getScrapOreTypes(), " + ")
end

function S.isScrapSmeltOreType(oreType)
    return SCRAP_SMELT_ORE_TYPES[tostring(oreType or "")] == true
end

function S.hasScrapSmeltTypesSelected()
    for _, oreType in ipairs(S.getScrapOreTypes()) do
        if S.isScrapSmeltOreType(oreType) then
            return true
        end
    end
    return false
end

function S.hasScrapDirectTypesSelected()
    for _, oreType in ipairs(S.getScrapOreTypes()) do
        if not S.isScrapSmeltOreType(oreType) then
            return true
        end
    end
    return false
end

function S.getAutofarmActiveOreTypes()
    if S.isScrapGoldPhase() then
        return S.getScrapOreTypes()
    end
    return Autofarm.oreUnderTypes
end

function S.isAutofarmBagReadyToSell()
    if S.isDropInDrillMode() or S.isDropInShredderMode() or S.isScrapFarmMode() or not Autofarm.autoSell then
        return false
    end
    local fill = S.getBagFillCount()
    if fill <= 0 then
        return false
    end
    if S.isBagFull() then
        return true
    end
    return fill >= S.getAutofarmSellThreshold()
end

function S.isAutofarmBagReadyToDropDrill()
    if not S.isDropInDrillMode() or S.isScrapFarmMode() or S.isDropInShredderMode() then
        return false
    end
    local fill = S.getBagFillCount()
    if fill <= 0 then
        return false
    end
    if S.isBagFull() then
        return true
    end
    return fill >= S.getAutofarmSellThreshold()
end

function S.isAutofarmBagReadyToDumpShredder()
    if not S.isDropInShredderMode() or S.isScrapFarmMode() or S.isDropInDrillMode() then
        return false
    end
    local fill = S.getBagFillCount()
    if fill <= 0 then
        return false
    end
    if S.isBagFull() then
        return true
    end
    return fill >= S.getAutofarmSellThreshold()
end

-- Shared bag-threshold dump for Auto Sell / Drop in Drill / Dump for Scrap.
function S.runAutofarmThresholdDumpIfReady()
    if S.isAutofarmBagReadyToDropDrill() then
        S.autofarmDumpBagToDrill()
        return "drill"
    end
    if S.isAutofarmBagReadyToDumpShredder() then
        S.autofarmDumpBagToShredder()
        return "shredder"
    end
    if S.isAutofarmBagReadyToSell() then
        S.autofarmAutoSell()
        return "sell"
    end
    return nil
end

function S.isAutofarmBagReadyToDumpAny()
    return S.isAutofarmBagReadyToDropDrill()
        or S.isAutofarmBagReadyToDumpShredder()
        or S.isAutofarmBagReadyToSell()
end

function S.trySetRayfieldFlag(flagName, value, silent)
    if not Rayfield or not Rayfield.Flags then
        return
    end
    local flag = Rayfield.Flags[flagName]
    if not flag then
        return
    end

    if silent or State._rayfieldFlagBusy == flagName or State._dumpDestApplying then
        flag.CurrentValue = value == true or value
        if flag.Set and not silent and State._dumpDestApplying then
            -- Visual-only: adapter Set suppresses the callback.
            pcall(function()
                flag:Set(value)
            end)
        end
        return
    end

    local prevBusy = State._rayfieldFlagBusy
    State._rayfieldFlagBusy = flagName
    State._rayfieldFlagDepth = (State._rayfieldFlagDepth or 0) + 1
    local ok, err = pcall(function()
        if flag.Set then
            flag:Set(value)
        else
            flag.CurrentValue = value
        end
    end)
    State._rayfieldFlagDepth = math.max(0, (State._rayfieldFlagDepth or 1) - 1)
    State._rayfieldFlagBusy = prevBusy
    if not ok then
        pcall(function()
            flag.CurrentValue = value
        end)
        warn("[TERRA HUB] trySetRayfieldFlag", flagName, err)
    end
end

function S.runRayfieldSafeCallback(flagName, fn)
    State._rayfieldFlagDepth = (State._rayfieldFlagDepth or 0) + 1
    State._rayfieldFlagBusy = flagName
    task.defer(function()
        local ok, err = pcall(fn)
        State._rayfieldFlagDepth = math.max(0, (State._rayfieldFlagDepth or 1) - 1)
        if State._rayfieldFlagBusy == flagName then
            State._rayfieldFlagBusy = nil
        end
        if not ok then
            warn("[TERRA HUB] flag callback", flagName, err)
        end
    end)
end

function S.setFarmDumpDest(dest, enabled)
    enabled = enabled == true
    dest = tostring(dest or "")
    if dest ~= "sell" and dest ~= "drill" and dest ~= "shredder" then
        return
    end
    if State._dumpDestApplying then
        return
    end

    local newSell = Autofarm.autoSell == true
    local newDrill = Autofarm.dropInDrill == true
    local newShred = Autofarm.dropInShredder == true
    if enabled then
        newSell = dest == "sell"
        newDrill = dest == "drill"
        newShred = dest == "shredder"
    elseif dest == "sell" then
        newSell = false
    elseif dest == "drill" then
        newDrill = false
    elseif dest == "shredder" then
        newShred = false
    end

    if newSell == (Autofarm.autoSell == true)
        and newDrill == (Autofarm.dropInDrill == true)
        and newShred == (Autofarm.dropInShredder == true)
    then
        return
    end

    State._dumpDestApplying = true
    Autofarm.autoSell = newSell
    Autofarm.dropInDrill = newDrill
    Autofarm.dropInShredder = newShred
    Autofarm._pendingDrillDrop = false

    if enabled and S.isScrapFarmMode() then
        S.setScrapFarm(false)
        S.trySetRayfieldFlag("terra_af_scrap_farm", false)
    end

    if newDrill then
        if S.isScrapFarmMode() then
            S.setScrapFarm(false)
            S.trySetRayfieldFlag("terra_af_scrap_farm", false)
        end
        S.setAutoLockTruck(true)
        S.trySetRayfieldFlag("terra_auto_lock_truck", true)
        Autofarm._dropDrillOwnedLock = true
    elseif Autofarm._dropDrillOwnedLock then
            S.setAutoLockTruck(false)
            S.trySetRayfieldFlag("terra_auto_lock_truck", false)
            Autofarm._dropDrillOwnedLock = false
    end

    S.trySetRayfieldFlag("terra_af_auto_sell", newSell)
    S.trySetRayfieldFlag("terra_af_drop_drill", newDrill)
    S.trySetRayfieldFlag("terra_af_drop_shredder", newShred)
    State._dumpDestApplying = false

    if enabled then
        local names = { sell = "Auto Sell", drill = "Drop in Drill", shredder = "Dump on Shredder" }
        S.notify("Drops", names[dest] .. " ON", 2)
    end
end

function S.setDropInDrill(enabled)
    S.setFarmDumpDest("drill", enabled)
end

function S.setDropInShredder(enabled)
    S.setFarmDumpDest("shredder", enabled)
end

function S.isScrapFarmMode()
    return Autofarm.scrapFarm == true
end

function S.isScrapGoldPhase()
    return S.isScrapFarmMode() and Autofarm.scrapPhase == "farm_gold"
end

function S.isScrapSeekPhase()
    return S.isScrapFarmMode() and (Autofarm.scrapPhase == "seek_pick" or Autofarm.scrapPhase == "chest_hunt")
end

-- Diamond or better from chests; Void or better from mines/map seek.
function S.getScrapPickaxeRank()
    local rank = -1
    local best = S.findBestPickaxe()
    if best then
        rank = math.max(rank, S.getPickaxeRank(best.Name))
    end
    local equipped = S.getEquippedTool()
    if equipped and S.isPickaxeTool(equipped) then
        rank = math.max(rank, S.getPickaxeRank(equipped.Name))
    end
    return rank
end

function S.hasScrapVoidPickaxe()
    local minRank = S.getPickaxeRank("Pickaxe_Void")
    if minRank <= 0 then
        minRank = 6
    end
    return S.getScrapPickaxeRank() >= minRank
end

function S.hasScrapDiamondPickaxe()
    local minRank = S.getPickaxeRank("Pickaxe_Diamond")
    if minRank <= 0 then
        minRank = 5
    end
    return S.getScrapPickaxeRank() >= minRank
end

-- Mines/map seek = Void+. Chest hunt = Diamond+ is enough.
function S.hasScrapMinPickaxe()
    if Autofarm.scrapPhase == "chest_hunt" then
        return S.hasScrapDiamondPickaxe()
    end
    return S.hasScrapVoidPickaxe()
end

-- Void first, then Diamond, then lower tiers.
local SCRAP_CHEST_TIER = {
    Void = 100,
    Diamond = 90,
    Gold = 80,
    Steel = 70,
    Core = 65,
    Mimic = 60,
    Rusty = 50,
    Common = 40,
    Free = 30,
    TutorialCommon = 20,
}

local SCRAP_CHEST_ORDER = {
    "Void",
    "Diamond",
    "Gold",
    "Steel",
    "Core",
    "Mimic",
    "Rusty",
    "Common",
    "Free",
    "TutorialCommon",
}

function S.findScrapChestForHunt()
    if Autofarm.openChests ~= true then
        return nil
    end

    local best, bestScore = nil, -math.huge
    for _, entry in ipairs(S.collectEspChests()) do
        local chest = entry.inst
        if chest and chest.Parent and not S.isChestPadlocked(chest) then
            local key = S.getChestTypeKey(chest)
            local tier = SCRAP_CHEST_TIER[key]
            if not tier then
                local keyLower = string.lower(key)
                for name, score in pairs(SCRAP_CHEST_TIER) do
                    if string.lower(name) == keyLower then
                        tier = score
                        break
                    end
                end
            end
            if tier then
                local dist = entry.dist or S.getFlatDistanceToPlayer(chest) or 99999
                local score = tier * 100000 - dist
                if score > bestScore then
                    bestScore = score
                    best = chest
                end
            end
        end
    end
    return best
end

-- Consumables / tools that contain "gold" in the name (Gold Medkit, etc).
function S.isScrapJunkItem(item)
    if not item then
        return true
    end
    if S.isWorldToolItem(item) or S.getGearItemCategory(item) then
        return true
    end

    local name = string.lower(tostring(item.Name or ""))
    local display = string.lower(tostring(item:GetAttribute("DisplayName") or ""))
    local class = string.lower(tostring(item:GetAttribute("Class") or ""))
    local cat = S.itemCategoryKey(item)
    local blob = name .. " " .. display .. " " .. class .. " " .. cat

    if cat == "consumable" or cat == "medkit" or cat == "tool"
        or cat == "pickaxe" or cat == "sword" or cat == "armor"
        or cat == "primary weapon" or cat == "secondary weapon"
    then
        return true
    end

    if blob:find("medkit", 1, true) or blob:find("med kit", 1, true)
        or blob:find("firstaid", 1, true) or blob:find("first aid", 1, true)
        or blob:find("potion", 1, true) or blob:find("bandage", 1, true)
        or blob:find("heal", 1, true) or blob:find("consumable", 1, true)
        or blob:find("pickaxe", 1, true) or blob:find("sword", 1, true)
        or blob:find("rifle", 1, true) or blob:find("shotgun", 1, true)
    then
        return true
    end

    return false
end

function S.isScrapSelectedOreItem(item)
    if not item then
        return false
    end
    -- Reject bars, gear and consumables before reading broad ore attributes.
    if S.isScrapJunkItem(item) then
        return false
    end

    local name = string.lower(tostring(item.Name or ""))
    local class = string.lower(tostring(item:GetAttribute("Class") or ""))
    local display = string.lower(tostring(item:GetAttribute("DisplayName") or ""))
    local cat = S.itemCategoryKey(item)
    if name:find("bar", 1, true) or display:find("bar", 1, true) or class:find("bar", 1, true) then
        return false
    end
    if cat == "scrap" or cat == "consumable" then
        return false
    end
    if (name:find("chest", 1, true) or display:find("chest", 1, true))
        and cat ~= "ore"
        and not (name:find("ore", 1, true) or display:find("ore", 1, true))
    then
        return false
    end

    local oreType = S.getLootOreTypeKey(item)
    if not oreType then
        return false
    end
    for _, selected in ipairs(S.getScrapOreTypes()) do
        if oreType == selected then
            local bareMetal = selected == "Gold"
                and (name == "gold" or display == "gold")
                or selected == "Copper"
                    and (name == "iron" or display == "iron" or name == "copper" or display == "copper")
            -- Require ore evidence; prevents Copper/Gold gear with matching names.
            return cat == "ore"
                or name:find("ore", 1, true) ~= nil
                or display:find("ore", 1, true) ~= nil
                or class:find("ore", 1, true) ~= nil
                or item:GetAttribute("SessionOreType") ~= nil
                or item:GetAttribute("OreType") ~= nil
                or (bareMetal and cat == "")
        end
    end

    return false
end

function S.isScrapSelectedBarItem(item)
    if not item then
        return false
    end
    if S.isScrapJunkItem(item) then
        return false
    end

    local name = string.lower(tostring(item.Name or ""))
    local class = string.lower(tostring(item:GetAttribute("Class") or ""))
    local display = string.lower(tostring(item:GetAttribute("DisplayName") or ""))
    local cat = S.itemCategoryKey(item)

    if cat == "ore" or name:find("ore", 1, true) or display:find("ore", 1, true) or class:find("ore", 1, true) then
        return false
    end

    local looksBar = name:find("bar", 1, true) or display:find("bar", 1, true) or class:find("bar", 1, true)
        or name:find("ingot", 1, true) or display:find("ingot", 1, true) or class:find("ingot", 1, true)
    local blob = name .. " " .. display .. " " .. class
    local typedMetal = looksBar and S.getLootOreTypeKey(item) or nil
    for _, selected in ipairs(S.getScrapOreTypes()) do
        if not S.isScrapSmeltOreType(selected) then
            continue
        end
        local metal = selected == "Copper" and "iron" or string.lower(selected)
        local hubMetal = string.lower(selected)
        local looksMetal = blob:find(metal, 1, true) or blob:find(hubMetal, 1, true)
        if (looksMetal or typedMetal == selected)
            and (looksBar or cat == "scrap" or class:find("scrap", 1, true))
        then
            return true
        end
    end

    return false
end

-- Copper/Gold ore only — these must hit the furnace first.
function S.isScrapFurnaceOreItem(item)
    if not S.isScrapSelectedOreItem(item) then
        return false
    end
    return S.isScrapSmeltOreType(S.getLootOreTypeKey(item))
end

-- Coal/Diamond/Ruby/Emerald (and any non-smelt selected ore) go straight to shredder.
function S.isScrapDirectOreItem(item)
    if not S.isScrapSelectedOreItem(item) then
        return false
    end
    return not S.isScrapSmeltOreType(S.getLootOreTypeKey(item))
end

-- Shredder accepts smelted bars + raw direct-shred ores.
function S.isScrapShredderDumpItem(item)
    return S.isScrapSelectedBarItem(item) or S.isScrapDirectOreItem(item)
end

-- Dump for Scrap: anything shredder-safe (reject gear / consumables).
function S.isDumpForScrapItem(item)
    return item ~= nil and not S.isScrapJunkItem(item)
end

-- Compatibility aliases for older internal callers.
S.isGoldOreLootItem = S.isScrapSelectedOreItem
S.isGoldBarItem = S.isScrapSelectedBarItem

function S.getSpotDropPart(spot)
    if not spot then
        return nil
    end
    if spot:IsA("BasePart") then
        return spot
    end
    local sellPart = spot:FindFirstChild("SellPart", true)
    if sellPart and sellPart:IsA("BasePart") then
        return sellPart
    end
    if spot:IsA("Model") and spot.PrimaryPart then
        return spot.PrimaryPart
    end
    -- Prefer larger touch pads over tiny attachments.
    local best, bestVol = nil, -1
    for _, d in ipairs(spot:GetDescendants()) do
        if d:IsA("BasePart") then
            local vol = d.Size.X * d.Size.Y * d.Size.Z
            if vol > bestVol then
                bestVol = vol
                best = d
            end
        end
    end
    return best or spot:FindFirstChildWhichIsA("BasePart", true)
end

-- True SellSpot for ore smelting (OreConvert / Furnace), never TradingCamp / CraftingShack.
function S.isFurnaceOreConvertSellTarget(inst)
    if not inst or not inst.Parent then
        return false
    end
    local name = inst.Name
    if name ~= "SellSpot" and name ~= "OreConvert" and name ~= "SellPart" then
        return false
    end

    local hasOreConvert = name == "OreConvert"
    local hasFurnace = false
    local forbidden = false
    local cur = inst
    while cur and cur ~= Workspace do
        local n = cur.Name
        if n == "OreConvert" then
            hasOreConvert = true
        end
        if n == "Furnace"
            or n == "FurnaceCampsite"
            or n == "FurnacePost"
            or string.find(string.lower(n), "furnacecampsite", 1, true)
        then
            hasFurnace = true
        end
        if n == "Sell_Table"
            or n == "CraftingShack"
            or n == "TradingCampTutorial"
            or n == "TradeSell"
            or n == "BountySell"
        then
            forbidden = true
            break
        end
        cur = cur.Parent
    end

    if forbidden then
        return false
    end
    -- Prefer OreConvert; accept any SellSpot clearly under a Furnace* tree.
    if name == "OreConvert" then
        return true
    end
    return hasOreConvert or hasFurnace
end

function S.findFurnaceOreSellSpot()
    local root = S.getRoot()
    local origin = root and root.Position or Vector3.zero
    local best, bestDist = nil, math.huge
    local foundAny = 0

    local function consider(spot)
        if not S.isFurnaceOreConvertSellTarget(spot) then
            return
        end
        -- Prefer SellSpot child if we got OreConvert / Furnace shell.
        if spot.Name == "OreConvert" or spot.Name == "Furnace" then
            local childSpot = spot:FindFirstChild("SellSpot", true) or spot:FindFirstChild("SellPart", true)
            if childSpot then
                spot = childSpot
            end
        end
        local part = S.getSpotDropPart(spot)
        if not part then
            return
        end
        foundAny += 1
        local dist = (part.Position - origin).Magnitude
        if dist < bestDist then
            bestDist = dist
            best = part
        end
    end

    -- 1) Direct campsites at Workspace root.
    for _, child in ipairs(Workspace:GetChildren()) do
        local n = child.Name
        if n == "FurnaceCampsite" or n == "FurnacePost" or string.find(n, "Furnace", 1, true) == 1 then
            local oreConvert = child:FindFirstChild("OreConvert", true)
            if oreConvert then
                consider(oreConvert:FindFirstChild("SellSpot", true) or oreConvert)
            else
                local furnace = child:FindFirstChild("Furnace", true)
                if furnace then
                    consider(furnace:FindFirstChild("SellSpot", true) or furnace:FindFirstChild("OreConvert", true) or furnace)
                end
            end
        end
    end

    -- 2) Full Workspace sweep — streaming / nested Chunks / late SellSpot.
    pcall(function()
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d.Name == "OreConvert" then
                consider(d:FindFirstChild("SellSpot", true) or d)
            elseif d.Name == "SellSpot" then
                consider(d)
            end
        end
    end)

    if best then
        return best
    end

    -- 3) Last try: stream around known furnace pivots then rescan OreConvert only.
    pcall(function()
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d.Name == "FurnaceCampsite" or d.Name == "FurnacePost" or d.Name == "OreConvert" then
                local pos = S.getInstancePosition(d) or (d:IsA("Model") and d:GetPivot().Position)
                if pos then
                    S.requestStreamAround(pos, 0.35)
                end
            end
        end
    end)
    task.wait(0.2)
    pcall(function()
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d.Name == "OreConvert" then
                consider(d:FindFirstChild("SellSpot", true) or d)
            elseif d.Name == "SellSpot" then
                consider(d)
            end
        end
    end)

    if not best and foundAny == 0 then
        S.notify("Scrap Farm", "Furnace SellSpot not in Workspace yet", 3)
    end
    return best
end

-- True if this instance is (or lives under) the free ScrapShredder — never CraftingShack SellSpot.
function S.isScrapShredderTarget(inst)
    if not inst or not inst.Parent then
        return false
    end
    local cur = inst
    local sawShredder = false
    local sawPaidSell = false
    while cur and cur ~= Workspace do
        local n = cur.Name
        if n == "ScrapShredder" then
            sawShredder = true
        end
        -- Paid craft/trade pads — dumping here shows "you need to pay for this first".
        if n == "SellSpot" or n == "SellPart" or n == "Sell_Table" or n == "TradeSell" or n == "BountySell" then
            sawPaidSell = true
        end
        cur = cur.Parent
    end
    if sawShredder and not sawPaidSell then
        return true
    end
    -- Rotators under CraftingShack with shredder mesh / blades / sound count as shredder zone.
    if inst.Name == "Rotators" or (inst.Parent and inst.Parent.Name == "Rotators") then
        local rot = inst.Name == "Rotators" and inst or inst.Parent
        if rot and (rot:FindFirstChild("ScrapShredder")
            or rot:FindFirstChild("RotatingBlade")
            or rot:FindFirstChild("ShredSound", true))
        then
            return true
        end
    end
    return false
end

function S.findScrapShredderPart()
    local root = S.getRoot()
    local origin = root and root.Position or Vector3.zero
    local best, bestDist = nil, math.huge
    local foundAny = 0

    local function consider(inst)
        if not inst or not inst.Parent then
            return
        end
        -- NEVER accept CraftingShack / SellSpot as dump pad (paid → "pay for this first").
        if inst.Name == "CraftingShack" or inst.Name == "SellSpot" or inst.Name == "SellPart" then
            return
        end
        local target = inst
        if inst.Name ~= "ScrapShredder" then
            local nested = inst:FindFirstChild("ScrapShredder", true)
            if nested then
                target = nested
            elseif inst.Name == "Rotators"
                and (inst:FindFirstChild("ScrapShredder")
                    or inst:FindFirstChild("RotatingBlade")
                    or inst:FindFirstChild("ShredSound", true))
            then
                target = inst:FindFirstChild("ScrapShredder") or inst
            else
                return
            end
        end
        if not S.isScrapShredderTarget(target) then
            return
        end
        local part = S.getSpotDropPart(target)
        if not part or not S.isScrapShredderTarget(part) then
            return
        end
        foundAny += 1
        local dist = (part.Position - origin).Magnitude
        if dist < bestDist then
            bestDist = dist
            best = part
        end
    end

    local function scanAll()
        pcall(function()
            for _, tagged in ipairs(CollectionService:GetTagged("ScrapCollector")) do
                local shred = tagged.Name == "ScrapShredder" and tagged or tagged:FindFirstChild("ScrapShredder", true)
                if shred then
                    consider(shred)
                end
                local rot = tagged:FindFirstChild("Rotators", true)
                if rot then
                    consider(rot:FindFirstChild("ScrapShredder") or rot)
                end
            end
        end)

        pcall(function()
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d.Name == "ScrapShredder" then
                    consider(d)
                elseif d.Name == "Rotators" and d.Parent and d.Parent.Name == "CraftingShack" then
                    if d:FindFirstChild("ScrapShredder") or d:FindFirstChild("RotatingBlade") then
                        consider(d:FindFirstChild("ScrapShredder") or d)
                    end
                end
            end
        end)
    end

    scanAll()
    if best then
        return best
    end

    -- Stream CraftingShack / Rotators then require a real ScrapShredder (no SellSpot fallback).
    pcall(function()
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d.Name == "CraftingShack" or d.Name == "Rotators" or d.Name == "ScrapShredder" or d.Name == "Fortress" then
                local pos = S.getInstancePosition(d)
                if not pos and d:IsA("Model") then
                    local ok, pivot = pcall(function()
                        return d:GetPivot().Position
                    end)
                    if ok then
                        pos = pivot
                    end
                end
                if pos then
                    S.requestStreamAround(pos, 0.45)
                end
            end
        end
    end)
    task.wait(0.4)
    scanAll()

    if not best then
        S.notify("Scrap Farm", "Waiting for ScrapShredder (not SellSpot)", 3)
    end
    return best
end

function S.snapshotScrapSettings()
    return {
        autoSell = Autofarm.autoSell == true,
        dropInDrill = Autofarm.dropInDrill == true,
        dropInShredder = Autofarm.dropInShredder == true,
        autoEquipBest = Autofarm.autoEquipBest == true,
        enterMines = Autofarm.enterMines == true,
        openChests = Autofarm.openChests == true,
        chestTypes = Autofarm.chestTypes,
        oreUnderEnabled = Autofarm.oreUnderEnabled == true,
        oreUnderTypes = Autofarm.oreUnderTypes,
        breakDeathWormOres = Autofarm.breakDeathWormOres == true,
        autoLock = TruckLock.autoLock == true,
    }
end

function S.restoreScrapSettings(saved)
    if type(saved) ~= "table" then
        return
    end
    Autofarm.autoSell = saved.autoSell == true
    Autofarm.dropInDrill = saved.dropInDrill == true
    Autofarm.dropInShredder = saved.dropInShredder == true
    Autofarm.enterMines = saved.enterMines == true
    Autofarm.openChests = saved.openChests == true
    Autofarm.chestTypes = saved.chestTypes
    Autofarm.oreUnderEnabled = saved.oreUnderEnabled == true
    Autofarm.oreUnderTypes = saved.oreUnderTypes
    Autofarm.breakDeathWormOres = saved.breakDeathWormOres == true
    S.trySetRayfieldFlag("terra_af_auto_sell", Autofarm.autoSell)
    S.trySetRayfieldFlag("terra_af_drop_drill", Autofarm.dropInDrill)
    S.trySetRayfieldFlag("terra_af_drop_shredder", Autofarm.dropInShredder)
    S.trySetRayfieldFlag("terra_af_join_mines", Autofarm.enterMines)
    S.trySetRayfieldFlag("terra_af_auto_chests", Autofarm.openChests)
    S.trySetRayfieldFlag("terra_af_auto_ores", Autofarm.oreUnderEnabled)
    S.trySetRayfieldFlag("terra_af_ore_worms", Autofarm.breakDeathWormOres)
    S.trySetRayfieldFlag("terra_af_equip_best", saved.autoEquipBest == true)
    S.setAutofarmEquipBest(saved.autoEquipBest == true)
    S.setAutoLockTruck(saved.autoLock == true)
    S.trySetRayfieldFlag("terra_auto_lock_truck", saved.autoLock == true)
end

function S.beginScrapGoldFarm(forcedCurrentPick)
    Autofarm.scrapPhase = "farm_gold"
    Autofarm.scrapSeekLaps = 0
    Autofarm.autoSell = false
    Autofarm.dropInDrill = false
    Autofarm.dropInShredder = false
    Autofarm.openChests = false
    Autofarm.enterMines = true
    Autofarm.oreUnderEnabled = true
    Autofarm.oreUnderTypes = S.getScrapOreTypes()
    Autofarm.breakDeathWormOres = true
    S.trySetRayfieldFlag("terra_af_auto_sell", false)
    S.trySetRayfieldFlag("terra_af_drop_drill", false)
    S.trySetRayfieldFlag("terra_af_drop_shredder", false)
    S.trySetRayfieldFlag("terra_af_auto_chests", false)
    S.trySetRayfieldFlag("terra_af_join_mines", true)
    S.trySetRayfieldFlag("terra_af_auto_ores", true)
    S.trySetRayfieldFlag("terra_af_ore_worms", true)
    -- No Equip Best during ore farm — only selected ores / bars get yanked.
    S.setAutofarmEquipBest(false)
    S.trySetRayfieldFlag("terra_af_equip_best", false)
    GearEquip.enabled = false
    -- Forget seek progress — restart cruise for gold.
    Autofarm.distance = 0
    S.resetAutofarmStart()
    if forcedCurrentPick then
        S.notify("Scrap Farm", "No Void+/Diamond+ after 2 laps — farming with current pickaxe", 5)
    else
        S.notify("Scrap Farm", "Pick OK — " .. S.getScrapOreTypesLabel() .. " Ore/Bars", 5)
    end
end

function S.setScrapFarm(enabled)
    enabled = enabled == true

    -- Already off in state: still hard-release if toggle spam / desync left character stuck.
    if not enabled and not S.isScrapFarmMode() then
        if type(CoreFarm) == "table" and (CoreFarm._ownedRun or CoreFarm.openAll) then
            return
        end
        S.trySetRayfieldFlag("terra_af_scrap_farm", false, true)
        local owned = Autofarm._scrapOwnedAutofarm
        Autofarm._scrapOwnedAutofarm = false
        task.spawn(function()
            if owned and Autofarm.enabled then
                pcall(S.setAutofarm, false)
                S.trySetRayfieldFlag("terra_autofarm", false, true)
            else
                pcall(S.forceReleaseFarmCharacter)
            end
        end)
        return
    end

    if enabled == S.isScrapFarmMode() then
        Autofarm.scrapFarm = enabled
        return
    end

    if enabled then
        Autofarm._farmShuttingDown = false
        Autofarm.scrapSaved = S.snapshotScrapSettings()
        Autofarm._scrapHadAutofarm = Autofarm.enabled == true
        Autofarm._scrapOwnedAutofarm = not Autofarm.enabled
        if Autofarm.dropInDrill then
            Autofarm.dropInDrill = false
            S.trySetRayfieldFlag("terra_af_drop_drill", false, true)
            if Autofarm._dropDrillOwnedLock then
                S.setAutoLockTruck(false)
                S.trySetRayfieldFlag("terra_auto_lock_truck", false, true)
                Autofarm._dropDrillOwnedLock = false
            end
        end
        if Autofarm.dropInShredder then
            Autofarm.dropInShredder = false
            S.trySetRayfieldFlag("terra_af_drop_shredder", false, true)
        end
        Autofarm.scrapFarm = true
        Autofarm.scrapPhase = "seek_pick"
        Autofarm.scrapSeekLaps = 0
        Autofarm.autoSell = false
        Autofarm.openChests = false
        Autofarm.oreUnderEnabled = false
        Autofarm.enterMines = true
        Autofarm.breakDeathWormOres = true
        S.trySetRayfieldFlag("terra_af_auto_sell", false, true)
        S.trySetRayfieldFlag("terra_af_join_mines", true, true)
        S.trySetRayfieldFlag("terra_af_auto_chests", false, true)
        S.trySetRayfieldFlag("terra_af_auto_ores", false, true)
        S.trySetRayfieldFlag("terra_af_ore_worms", true, true)
        S.setAutofarmEquipBest(true)
        S.trySetRayfieldFlag("terra_af_equip_best", true, true)
        Autofarm.distance = 0

        if not Autofarm.enabled then
            S.setAutofarm(true)
        end
        S.trySetRayfieldFlag("terra_autofarm", true, true)
        S.notify("Scrap Farm", "ON — mines Void+ / chests Diamond+ · worms ON", 5)
    else
        -- Instant clear so Rayfield callback never yields / never re-Sets this flag.
        local bagFill = S.getBagFillCount()
        local owned = Autofarm._scrapOwnedAutofarm
        local had = Autofarm._scrapHadAutofarm
        Autofarm._farmShuttingDown = true
        Autofarm.scrapFarm = false
        Autofarm.scrapPhase = "seek_pick"
        Autofarm.enterMines = false
        Autofarm.suppressChestOreStopUntil = tick() + 12
        S.trySetRayfieldFlag("terra_af_scrap_farm", false, true)
        S.trySetRayfieldFlag("terra_af_join_mines", false, true)
        pcall(S.releaseStuckFarmHold)
        S.stopFarmLoopsSoft()

        task.spawn(function()
            local ok, err = pcall(function()
                -- End-game: only finish bag (ore→furnace→bars→shred). Never re-farm / re-pin mine.
                if bagFill > 0 then
                    Autofarm._scrapFlushing = true
                    S.notify("Scrap Farm", "End game — furnace/shred bag (" .. tostring(bagFill) .. ")", 4)
                    S.scrapSmeltAndShredCycle({ force = true })
                    Autofarm._skipNextEndGame = true
                    Autofarm._scrapFlushing = false
                end

                S.clearScrapFarmState(true)
                Autofarm._scrapOwnedAutofarm = false
                Autofarm._scrapHadAutofarm = false
                Autofarm.enterMines = false

                if owned and not had then
                    S.setAutofarm(false, { skipReturn = true })
                    S.trySetRayfieldFlag("terra_autofarm", false, true)
                    pcall(S.forceReleaseFarmCharacter)
                else
                    Autofarm._farmShuttingDown = false
                    Autofarm._cycleAbort = false
                    if not Autofarm.enabled then
                        S.setAutofarm(true)
                    else
                        S.resetAutofarmStart()
                        S.ensureAutofarmAntiFall(true)
                        S.lockAutofarmHover(true)
                        S.startJpaxRouteGlide()
                    end
                    S.trySetRayfieldFlag("terra_autofarm", true, true)
                end
            end)
            Autofarm._farmShuttingDown = false
            Autofarm._scrapFlushing = false
            if not ok then
                warn("[TERRA HUB] scrap farm OFF", err)
                pcall(S.forceReleaseFarmCharacter)
            end
            S.notify("Scrap Farm", "OFF", 3)
        end)
    end
end

-- Light mine pass for Scrap seek: touch entrance + yank/equip pickaxes in a wide radius.
function S.collectWorldPickaxesNearby(range)
    range = range or 500
    local list = {}
    local root = S.getRoot()
    if not root then
        return list
    end
    S.forEachWorldLootItem(function(item)
        if not item or not item.Parent or not S.isPickaxeWorldItem(item) then
            return
        end
        if CollectionService:HasTag(item, "ShopItem") or S.isHardExcluded(item) then
            return
        end
        local pos = S.getItemPosition(item)
        if not pos then
            return
        end
        local flat = S.getFlatDistanceFromPosition(pos)
        local full = (pos - root.Position).Magnitude
        -- Prefer flat for shafts; also accept close 3D (deep under entrance).
        if flat <= range or full <= math.min(range, 220) then
            table.insert(list, {
                item = item,
                score = S.getWorldGearScore(item),
                dist = math.min(flat, full),
            })
        end
    end)
    table.sort(list, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.dist < b.dist
    end)
    return list
end

-- Aggressive gear grab for Scrap seek (uses full Auto Equip Best categories).
function S.scrapSeekEquipPickaxesNearby(range)
    range = range or 650
    if not Autofarm.enabled or not S.isScrapSeekPhase() then
        return 0
    end

    if not GearEquip.enabled or not Autofarm.autoEquipBest then
        S.setAutofarmEquipBest(true)
    end
    GearEquip.range = range
    Autofarm.autoEquipBest = true

    GearEquip.lastPassAt = 0
    local equipped = 0
    pcall(function()
        equipped = S.runAutoEquipBestPass()
    end)

    -- Extra pickaxe bring if still missing minimum tier (deep mine shafts).
    if not S.hasScrapMinPickaxe() then
        local list = S.collectWorldPickaxesNearby(range)
        for i = 1, math.min(#list, 10) do
            local entry = list[i]
            local item = entry and entry.item
            if item and item.Parent and S.shouldAutoEquipWorldItem(item) then
                for _ = 1, 3 do
                    pcall(S.bringItemToPlayer, item)
                    task.wait(0.04)
                end
                if S.equipWorldGearItem(item) then
                    equipped += 1
                    task.wait(0.15)
                    if S.hasScrapMinPickaxe() then
                        break
                    end
                end
            end
        end
    end

    if equipped <= 0 and not S.hasScrapMinPickaxe() then
        local savedBusy = GearEquip.busy
        GearEquip.busy = false
        local prevMining = Autofarm.miningBusy
        Autofarm.miningBusy = false
        GearEquip.lastPassAt = 0
        pcall(function()
            equipped = S.runAutoEquipBestPass()
        end)
        Autofarm.miningBusy = prevMining
        GearEquip.busy = savedBusy
    end

    return equipped
end

function S.scrapSeekMinePass(mine)
    if not mine or S.autofarmCycleShouldAbort() or not S.isScrapSeekPhase() then
        return false
    end

    Autofarm._activeMine = mine
    Autofarm._visitGen = Autofarm._cycleGen
    local entrance = S.getMineEntranceWorldPos(mine)
    if entrance then
        S.cancelAutofarmTween()
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
        S.farmLog("seek mine", mine.Name)
        S.autofarmTweenTowardWorldPos(entrance)
        if S.autofarmVisitStale() then
            S.skipAutofarmMine(mine, 75, "seek abort")
            return false
        end
        local rootNow = S.getRoot()
        local seekFlat = 9999
        if rootNow then
            seekFlat = Vector3.new(rootNow.Position.X - entrance.X, 0, rootNow.Position.Z - entrance.Z).Magnitude
        end
        if seekFlat > 55 then
            S.farmLog("seek mine miss", string.format("flat=%.0f", seekFlat))
            S.skipAutofarmMine(mine, 90, "seek miss")
            return false
        end
        S.holdAutofarmAtEntrance(mine)
        pcall(function()
            S.requestStreamAround(entrance, 0.8)
        end)
        pcall(function()
            S.streamMineInterior(mine, 10, 90)
        end)
    end

    -- Wide scan around this mine — old pass only checked ~280 and often saw nothing.
    S.scrapSeekEquipPickaxesNearby(700)
    task.wait(0.2)
    S.scrapSeekEquipPickaxesNearby(700)

    -- If best pick is still far (deep shaft), tween toward top scored pick once.
    if not S.hasScrapMinPickaxe() then
        local list = S.collectWorldPickaxesNearby(900)
        local best = list[1]
        if best and best.item and best.item.Parent and S.shouldAutoEquipWorldItem(best.item) then
            local pos = S.getItemPosition(best.item)
            if pos then
                S.autofarmTweenTowardWorldPos(pos)
                pcall(function()
                    S.requestStreamAround(pos, 0.6)
                end)
                S.scrapSeekEquipPickaxesNearby(400)
            end
        end
    end

    S.skipAutofarmMine(mine, 25, "seek done")
    S.suppressAutofarmMines(3)

    if Autofarm.enabled then
        S.syncAutofarmDistanceFromRoot()
        S.setAutofarmPose(Autofarm.distance or 0)
        S.lockAutofarmHover(true)
    end

    return S.hasScrapVoidPickaxe() or S.hasScrapMinPickaxe()
end

-- Flush leftover bag for the active farm mode before full stop.
function S.endGameFlushActiveFarmBag()
    if S.isScrapFarmMode() or Autofarm._scrapFlushing then
        if S.getBagFillCount() > 0 then
            S.notify("Autofarm", "End game — Scrap bag flush", 3)
            pcall(function()
                S.scrapSmeltAndShredCycle({ force = true })
            end)
        end
        return
    end
    if S.isDropInDrillMode() then
        if S.getBagFillCount() > 0 then
            S.notify("Autofarm", "End game — Drop in Drill flush", 3)
            pcall(S.autofarmDumpBagToDrill)
        end
        return
    end
    if S.isDropInShredderMode() then
        if S.getBagFillCount() > 0 then
            S.notify("Autofarm", "End game — Dump for Scrap flush", 3)
            pcall(S.autofarmDumpBagToShredder)
        end
        return
    end
    -- Normal autofarm OFF: always sell whatever is left in the sack.
    if S.getBagFillCount() > 0 then
        S.notify("Autofarm", "End game — selling bag", 3)
        pcall(S.autofarmAutoSell)
    end
end

function S.isAutofarmBagReadyToScrapProcess()
    if not S.isScrapGoldPhase() or Autofarm._scrapProcessing or Autofarm._scrapFlushing then
        return false
    end
    if tick() < (Autofarm._scrapCooldownUntil or 0) then
        return false
    end
    local fill = S.getBagFillCount()
    if fill <= 0 then
        return false
    end
    if S.isBagFull() then
        return true
    end
    return fill >= S.getAutofarmSellThreshold()
end

function S.getDumpPadDropCFrame(part)
    if not part or not part:IsA("BasePart") then
        local p = S.getSpotDropPart(part)
        part = p
    end
    if not part or not part:IsA("BasePart") then
        return nil
    end
    return part.CFrame * CFrame.new(0, part.Size.Y * 0.5 + 0.15, 0)
end

function S.getDumpPadStandCFrame(part)
    local dropCf = S.getDumpPadDropCFrame(part)
    if not dropCf then
        return nil
    end
    local standY = dropCf.Position.Y + 2.2
    return CFrame.new(dropCf.Position.X, standY, dropCf.Position.Z), dropCf
end

-- True only when character is physically on the dump pad (not cruise / void / mid-tween).
function S.isCharacterAtDumpPad(part, maxFlat)
    local root = S.getRoot()
    local standCf, dropCf = S.getDumpPadStandCFrame(part)
    if not root or not standCf or not dropCf then
        return false
    end
    maxFlat = maxFlat or 10
    local pos = root.Position
    if pos.Y ~= pos.Y or pos.Y < -400 or pos.Y > 2500 then
        return false
    end
    local flat = Vector3.new(pos.X - dropCf.Position.X, 0, pos.Z - dropCf.Position.Z).Magnitude
    local yOk = math.abs(pos.Y - standCf.Position.Y) <= 14
    return flat <= maxFlat and yOk
end

-- Snap / re-snap until verified on pad. Never returns true if still elsewhere.
function S.arriveAtDumpPad(part, label, opts)
    opts = type(opts) == "table" and opts or {}
    local force = opts.force == true
    local timeout = tonumber(opts.timeout) or 6
    local standCf, dropCf = S.getDumpPadStandCFrame(part)
    if not standCf or not dropCf then
        S.notify("Scrap Farm", tostring(label or "Pad") .. " invalid", 3)
        return false
    end

    S.cancelAutofarmTween()
    Autofarm.moving = false
    Autofarm._gatePinY = standCf.Position.Y
    S.ensureAutofarmAntiFall(true)
    S.lockAutofarmHover(true)
    pcall(function()
        S.requestStreamAround(dropCf.Position, 0.8)
    end)

    local deadline = os.clock() + timeout
    local okStreak = 0
    while os.clock() < deadline do
        if not force and not Autofarm.enabled then
            return false
        end
        if Autofarm._farmShuttingDown and not force then
            return false
        end

        local root = S.getRoot()
        if root then
            Autofarm._gatePinY = standCf.Position.Y
            Autofarm._mineHoldPos = standCf.Position
            Autofarm._mineLookAt = nil
            root.Anchored = false
            root.CFrame = standCf
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            S.setAutofarmPlatformStand(true)
        end

        task.wait(0.08)
        if S.isCharacterAtDumpPad(part, 10) then
            okStreak += 1
            if okStreak >= 3 then
                S.notify("Scrap Farm", tostring(label or "Pad") .. " OK — dumping", 2)
                return true
            end
        else
            okStreak = 0
        end
    end

    S.notify("Scrap Farm", tostring(label or "Pad") .. " NOT reached — abort dump", 4)
    return false
end

-- Dump sack onto a BasePart (furnace SellSpot / ScrapShredder).
-- NEVER drops unless character is verified on the pad (prevents void dumps).
-- itemFilter: non-matching items are yanked back immediately (stay on pad so ore hits SellSpot).
function S.dumpBagOntoPart(part, label, itemFilter, opts)
    opts = type(opts) == "table" and opts or {}
    local force = opts.force == true
    if not part or not Services.ToolService then
        return 0
    end
    if tostring(label or "") == "Shredder" and not S.isScrapShredderTarget(part) then
        warn("[TERRA HUB] refused dump on non-shredder pad (would pay-wall)")
        S.notify("Scrap Farm", "Wrong pad — need ScrapShredder", 3)
        return 0
    end
    if tostring(label or "") == "Furnace" then
        local okFurnace = S.isFurnaceOreConvertSellTarget(part)
            or S.isFurnaceOreConvertSellTarget(part.Parent)
        if not okFurnace then
            local cur = part
            while cur and cur ~= Workspace do
                if S.isFurnaceOreConvertSellTarget(cur) then
                    okFurnace = true
                    break
                end
                local n = cur.Name
                if n == "Furnace" or n == "OreConvert" or n == "FurnaceCampsite" or n == "FurnacePost" then
                    okFurnace = true
                    break
                end
                if n == "CraftingShack" or n == "Sell_Table" or n == "TradeSell" then
                    okFurnace = false
                    break
                end
                cur = cur.Parent
            end
        end
        if not okFurnace then
            warn("[TERRA HUB] refused dump on non-furnace pad (would pay-wall)")
            S.notify("Scrap Farm", "Wrong pad — need furnace OreConvert", 3)
            return 0
        end
    end

    local root = S.getRoot()
    S.cancelAutofarmTween()
    if root then
        Autofarm.resumePocketDistance = Autofarm.distance or S.syncAutofarmDistanceFromRoot()
        Autofarm.resumePocketPos = root.Position
    end

    if not S.arriveAtDumpPad(part, label, { force = force, timeout = force and 8 or 6 }) then
        return 0
    end

    local dropCf = S.getDumpPadDropCFrame(part)
    if not dropCf then
        return 0
    end

    S.clearDragTarget()
    S.ensureItemBag()
    pcall(function()
        local update = Services.ToolService.Update
        if update and update.Fire then
            local _ = update -- (sack dihapus)
        end
    end)

    local dumped = 0
    local rejected = 0
    local stalledDrops = 0
    for _ = 1, 220 do
        if not force and not Autofarm.enabled then
            break
        end
        if Autofarm._farmShuttingDown and not force then
            break
        end
        local before = S.getBagFillCount()
        if before <= 0 then
            break
        end

        -- Re-verify every drop. Lost pad = stop (don't void the rest of the bag).
        if not S.isCharacterAtDumpPad(part, 12) then
            if not S.arriveAtDumpPad(part, label, { force = force, timeout = 3 }) then
                S.notify("Scrap Farm", "Left " .. tostring(label) .. " — stopped dump", 3)
                break
            end
        end

        S.ensureItemBag()
        local beforeSet = S.snapshotItemsSet()
        S.bagDrop()
        task.wait(0.05)
        local news = S.findNewWorldItems(beforeSet)
        local matchedThisDrop = false
        local rejectedThisDrop = 0
        for _, item in ipairs(news) do
            if item and item.Parent then
                if itemFilter and not itemFilter(item) then
                    rejected += 1
                    rejectedThisDrop += 1
                    pcall(S.sackPickupVerified, item)
                    continue
                end
                -- Pin matching item on the pad (bagDrop already at feet on pad).
                if S.isCharacterAtDumpPad(part, 14) then
                    S.moveItemToCFrame(item, dropCf)
                    local ip = S.getItemPosition(item)
                    if ip and (ip.Y < -400 or (ip - dropCf.Position).Magnitude > 40) then
                        S.moveItemToCFrame(item, dropCf)
                    end
                    dumped += 1
                    matchedThisDrop = true
                else
                    pcall(S.sackPickupVerified, item)
                end
            end
        end
        local after = S.getBagFillCount()
        if after >= before then
            pcall(function()
                local update = Services.ToolService.Update
                if update and update.Fire then
                    local _ = update -- (sack dihapus)
                end
            end)
            if matchedThisDrop then
                stalledDrops = 0
            elseif rejectedThisDrop > 0 then
                stalledDrops += 1
                -- The remaining bag items do not match this pad (usually bars at
                -- the furnace). Stop cycling them through Drop/Pickup.
                if stalledDrops >= 3 then
                    break
                end
            elseif #news == 0 then
                -- Allow several retries for replication lag, but never spin 220
                -- times if bagDrop stops producing a world item.
                stalledDrops += 1
                if stalledDrops >= 8 then
                    break
                end
            else
                -- Character/pad moved after the pre-check; retry without treating
                -- valid ore as a filtered item.
                stalledDrops = 0
            end
        else
            stalledDrops = 0
            dumped = math.max(dumped, before - after)
        end
    end

    Money.trackedBagAt = Money.trackedBagAt or os.clock()
    if label then
        S.notify("Scrap Farm", tostring(label) .. ": dumped " .. tostring(dumped), 3)
    end
    return dumped, rejected
end

function S.collectWorldGoldBars(range)
    range = range or 120
    local list = {}
    S.forEachWorldLootItem(function(item)
        if S.isGoldBarItem(item) and not S.isHardExcluded(item) then
            local pos = S.getItemPosition(item)
            if pos and S.getFlatDistanceFromPosition(pos) <= range then
                table.insert(list, item)
            end
        end
    end)
    return list
end

-- Selected smeltable ores + their bars on the floor (scrap farm only).
function S.collectWorldScrapGoldLoot(range)
    range = range or 500
    local list = {}
    S.forEachWorldLootItem(function(item)
        if S.isHardExcluded(item) then
            return
        end
        if not (S.isGoldOreLootItem(item) or S.isGoldBarItem(item)) then
            return
        end
        local pos = S.getItemPosition(item)
        if pos and S.getFlatDistanceFromPosition(pos) <= range then
            table.insert(list, {
                item = item,
                dist = S.getFlatDistanceFromPosition(pos),
            })
        end
    end)
    table.sort(list, function(a, b)
        return a.dist < b.dist
    end)
    return list
end

function S.hasScrapGoldLootNearby(range)
    if not S.isScrapGoldPhase() then
        return false
    end
    range = range or math.max(S.getAutofarmCruiseStopRange(), 550)
    return #S.collectWorldScrapGoldLoot(range) > 0
end

-- Instant yank selected ores/bars into sack (no bring).
function S.yankScrapGoldLootNearby(range)
    if S.isBagFull() then
        return 0
    end
    range = range or 700
    S.ensureBagReadyForLoot()
    local yanked = 0
    for _ = 1, 40 do
        if not Autofarm.enabled or S.isBagFull() then
            break
        end
        if Autofarm._farmShuttingDown and not Autofarm._scrapFlushing then
            break
        end
        local list = S.collectWorldScrapGoldLoot(range)
        if #list == 0 then
            break
        end
        local before = S.getBagFillCount()
        local gotAny = false
        for i = 1, math.min(#list, 12) do
            local item = list[i].item
            if item and item.Parent and S.sackPickupVerified(item) then
                yanked += 1
                gotAny = true
            elseif item and item.Parent and S.bagPickup(item) then
                -- Fallback: fire-only if verify is slow mid-mining.
                task.wait(0.02)
                if S.getBagFillCount() > before then
                    yanked += 1
                    gotAny = true
                    before = S.getBagFillCount()
                end
            end
            if S.isBagFull() then
                break
            end
        end
        if not gotAny then
            break
        end
        task.wait(0.03)
    end
    Money.trackedBagAt = Money.trackedBagAt or os.clock()
    return yanked
end

function S.yankGoldBarsIntoBag(range, opts)
    opts = type(opts) == "table" and opts or {}
    local force = opts.force == true
    range = range or 150
    local yanked = 0
    -- Direct sack pickup — NEVER runLootCycle here (miningBusy blocks it during smelt).
    for _ = 1, 48 do
        if (not force and not Autofarm.enabled) or S.isBagFull() then
            break
        end
        if Autofarm._farmShuttingDown and not force then
            break
        end
        local bars = S.collectWorldGoldBars(range)
        if #bars == 0 then
            break
        end
        S.ensureItemBag()
        S.ensureBagReadyForLoot()
        local before = S.getBagFillCount()
        local gotAny = false
        for i = 1, math.min(#bars, 16) do
            local item = bars[i]
            if item and item.Parent then
                -- Pull bar to player first — Instant Pickup often fails if bar is still on furnace pad.
                pcall(S.bringItemToPlayer, item)
                task.wait(0.02)
                if S.sackPickupVerified(item) then
                    yanked += 1
                    gotAny = true
                elseif S.bagPickup(item) then
                    task.wait(0.05)
                    if S.getBagFillCount() > before then
                        yanked += 1
                        gotAny = true
                        before = S.getBagFillCount()
                    end
                end
            end
            if S.isBagFull() then
                break
            end
        end
        if not gotAny then
            break
        end
        task.wait(0.03)
    end
    Money.trackedBagAt = Money.trackedBagAt or os.clock()
    return yanked
end

-- Smeltable ores → furnace → bars; direct ores + bars → ScrapShredder.
-- force=true: end-game flush only (no return to farm).
-- Never resumes ore farm until furnace+shred finish (or abort without dumping).
function S.scrapSmeltAndShredCycle(opts)
    opts = type(opts) == "table" and opts or {}
    local force = opts.force == true
    if Autofarm._scrapProcessing then
        return false
    end
    if not force then
        if not Autofarm.enabled or not S.isScrapGoldPhase() then
            return false
        end
    end

    Autofarm._scrapProcessing = true
    Autofarm.miningBusy = true
    Autofarm.busy = true
    Autofarm.moving = false
    S.cancelAutofarmTween()
    S.releaseCharacterHold()

    local ok, err = pcall(function()
        local needFurnace = S.hasScrapSmeltTypesSelected()
        local dumpedOre = 0
        local keptForLater = 0
        local yankedBars = 0

        -- Copper/Gold go through OreConvert first. Direct ores stay in bag for shredder.
        if needFurnace then
            local sellSpot = S.findFurnaceOreSellSpot()
            if not sellSpot then
                if not force then
                    S.notify("Scrap Farm", "No furnace — keep farming", 3)
                    task.wait(0.8)
                end
                -- Still allow direct-ore shred if bag has non-smelt ores.
                if not S.hasScrapDirectTypesSelected() then
                    return
                end
            else
                local dumped, kept = S.dumpBagOntoPart(
                    sellSpot,
                    "Furnace",
                    S.isScrapFurnaceOreItem,
                    { force = force }
                )
                dumpedOre = dumped or 0
                keptForLater = kept or 0
                if dumpedOre <= 0 and S.getBagFillCount() > 0 and keptForLater <= 0 then
                    S.notify("Scrap Farm", "Furnace dump aborted — bag safe", 4)
                    return
                end

                -- Wait for bars only if we actually dumped smeltable ore.
                local quiet = 0
                local maxWait = force and 60 or 100
                if dumpedOre > 0 then
                    for _ = 1, maxWait do
                        if Autofarm._farmShuttingDown and not force then
                            break
                        end
                        if not force and (not Autofarm.enabled or not S.isScrapGoldPhase()) then
                            break
                        end
                        if not S.isCharacterAtDumpPad(sellSpot, 18) then
                            if not S.arriveAtDumpPad(sellSpot, "Furnace", { force = force, timeout = 3 }) then
                                break
                            end
                        else
                            S.snapCharacterOntoTradeSell(sellSpot)
                        end
                        local bars = S.collectWorldGoldBars(220)
                        if #bars > 0 then
                            quiet = 0
                            yankedBars += S.yankGoldBarsIntoBag(240, { force = force })
                        else
                            quiet += 1
                            if quiet >= (force and 16 or 22) and yankedBars > 0 then
                                break
                            end
                            if quiet >= (force and 28 or 36) then
                                break
                            end
                            task.wait(0.2)
                        end
                    end
                    yankedBars += S.yankGoldBarsIntoBag(force and 200 or 280, { force = force })
                end
            end
        end

        -- Shredder: bars from furnace + raw Coal/Diamond/Ruby/Emerald (etc).
        S.yankGoldBarsIntoBag(160, { force = force })
        local shredder = S.findScrapShredderPart()
        local bagReady = S.getBagFillCount() > 0
            or #S.collectWorldGoldBars(140) > 0
        if shredder and bagReady then
            S.yankGoldBarsIntoBag(160, { force = force })
            local dumped = S.dumpBagOntoPart(
                shredder,
                "Shredder",
                S.isScrapShredderDumpItem,
                { force = force }
            )
            task.wait(0.4)
            S.yankGoldBarsIntoBag(100, { force = force })
            if S.getBagFillCount() > 0 then
                S.dumpBagOntoPart(shredder, "Shredder", S.isScrapShredderDumpItem, { force = force })
            end
            if dumped <= 0 and S.getBagFillCount() > 0 then
                S.notify("Scrap Farm", "Shredder dump aborted — bag safe", 4)
            elseif dumped > 0 then
                S.notify("Scrap Farm", "Shredder OK — " .. tostring(dumped), 3)
            end
        elseif not shredder and not force then
            S.notify("Scrap Farm", "No ScrapShredder — waiting", 3)
            task.wait(1)
        elseif shredder and S.getBagFillCount() <= 0 and yankedBars <= 0 and dumpedOre <= 0 then
            S.notify("Scrap Farm", "Nothing to shred", 3)
        end

        -- Resume cruise only after full process attempt.
        if not force and Autofarm.enabled and S.isScrapGoldPhase() then
            Autofarm.distance = Autofarm.resumePocketDistance or Autofarm.distance or 0
            Autofarm._gatePinY = nil
            S.returnToAutofarmPocket()
            S.ensureAutofarmAntiFall(true)
            S.lockAutofarmHover(true)
        end
    end)

    Autofarm._scrapProcessing = false
    Autofarm.miningBusy = false
    Autofarm._gatePinY = nil
    S.clearMineHoldPin()
    -- Cooldown so we don't instantly bounce furnace ↔ ores in the same second.
    Autofarm._scrapCooldownUntil = tick() + (force and 1.0 or 3.5)
    if not ok then
        warn("[TERRA HUB] scrapSmeltAndShredCycle", err)
        return false
    end
    return true
end

function S.setAutofarmAutoSell(enabled)
    S.setFarmDumpDest("sell", enabled)
end

function S.getLootOreTypeKey(item)
    if not item then
        return nil
    end

    local attrs = {
        item:GetAttribute("SessionOreType"),
        item:GetAttribute("OreType"),
        item:GetAttribute("Class"),
        item:GetAttribute("DisplayName"),
        item.Name,
    }
    for _, raw in ipairs(attrs) do
        if typeof(raw) == "string" and raw ~= "" then
            local hub = S.mapOreTypeString(raw)
            if hub then
                return hub
            end
        end
    end

    local name = string.lower(tostring(item.Name or ""))
    for _, opt in ipairs(ORE_DROPDOWN_OPTIONS) do
        if name:find(string.lower(opt), 1, true) then
            return opt
        end
    end
    if name:find("iron", 1, true) then
        return "Copper"
    end
    return nil
end

function S.isDrillDropWhitelistItem(item)
    if not item then
        return false
    end
    local types = Autofarm.drillDropTypes
    if type(types) ~= "table" or #types == 0 then
        return false
    end
    local key = S.getLootOreTypeKey(item)
    if not key then
        return false
    end
    for _, selected in ipairs(types) do
        if selected == key then
            return true
        end
    end
    return false
end

function S.isSelectedOreDropItem(item)
    if not item or not item.Parent then
        return false
    end
    if S.isHardExcluded(item) or S.isItemInTruckZone(item) then
        return false
    end
    -- Gear, guns, medkits. "Gold" in the name is not an ore drop.
    if S.isScrapJunkItem(item) then
        return false
    end

    local rarity = item:GetAttribute("Rarity")
    local name = string.lower(tostring(item.Name or ""))
    local display = string.lower(tostring(item:GetAttribute("DisplayName") or ""))
    local class = string.lower(tostring(item:GetAttribute("Class") or ""))
    local cat = S.itemCategoryKey(item)
    if cat == "scrap" or class:find("scrap", 1, true) or name:find("scrap", 1, true) or display:find("scrap", 1, true) then
        return false
    end
    if cat == "bar" or name:find("bar", 1, true) or display:find("bar", 1, true) or class:find("bar", 1, true) then
        return false
    end
    if cat ~= "" and cat ~= "ore" then
        return false
    end

    -- Exact type only. A substring search also matched Gold Scrap / Gold Helmet.
    local function exactOreKey(raw)
        if typeof(raw) ~= "string" or raw == "" then
            return nil
        end
        local stripped = S.stripRarityPrefix(raw, rarity)
        return S.mapOreTypeString(stripped) or S.mapOreTypeString(raw)
    end

    local key = exactOreKey(item:GetAttribute("SessionOreType"))
        or exactOreKey(item:GetAttribute("OreType"))
        or exactOreKey(item.Name)
        or exactOreKey(item:GetAttribute("DisplayName"))
    if not key then
        return false
    end
    if cat ~= "ore" and class ~= "ore" and item:GetAttribute("SessionOreType") == nil and item:GetAttribute("OreType") == nil then
        -- Bare drop names (Coal, Gold, Iron) are ores. Anything else needs the ore tag.
        local bare = S.stripRarityPrefix(item.Name, rarity)
        local bareDisplay = S.stripRarityPrefix(tostring(item:GetAttribute("DisplayName") or ""), rarity)
        local function isBare(label)
            label = string.lower(tostring(label or ""))
            if label == "" then
                return false
            end
            if label == "iron" or label == "copper" then
                return true
            end
            for _, opt in ipairs(ORE_DROPDOWN_OPTIONS) do
                if label == string.lower(opt) then
                    return true
                end
            end
            return false
        end
        if not isBare(bare) and not isBare(bareDisplay) then
            return false
        end
    end

    local types = S.getAutofarmActiveOreTypes()
    if type(types) ~= "table" or #types == 0 then
        return true
    end
    for _, selected in ipairs(types) do
        if selected == key then
            return true
        end
    end
    return false
end

function S.collectWorldOreDrops(range)
    range = tonumber(range) or 800
    local list = {}
    S.forEachWorldLootItem(function(item)
        if S.isSelectedOreDropItem(item) then
            local pos = S.getItemPosition(item)
            if pos then
                local dist = S.getFlatDistanceFromPosition(pos)
                if dist <= range then
                    table.insert(list, { item = item, dist = dist })
                end
            end
        end
    end)
    table.sort(list, function(a, b)
        return a.dist < b.dist
    end)
    return list
end

-- Auto Ores pickup: bag the broken ore without Auto Loot / loot blacklist.
function S.yankOreDropsNearby(range)
    if S.isBagFull() then
        return 0
    end
    range = tonumber(range) or 800
    S.ensureBagReadyForLoot()
    local yanked = 0
    for _ = 1, 40 do
        if not Autofarm.enabled or S.isBagFull() then
            break
        end
        local list = S.collectWorldOreDrops(range)
        if #list == 0 then
            break
        end
        local before = S.getBagFillCount()
        local gotAny = false
        for i = 1, math.min(#list, 12) do
            local item = list[i].item
            if item and item.Parent and S.sackPickupVerified(item) then
                yanked += 1
                gotAny = true
            elseif item and item.Parent and S.bagPickup(item) then
                task.wait(0.02)
                if S.getBagFillCount() > before then
                    yanked += 1
                    gotAny = true
                    before = S.getBagFillCount()
                end
            end
            if S.isBagFull() then
                break
            end
        end
        if not gotAny then
            break
        end
        task.wait(0.03)
    end
    Money.trackedBagAt = Money.trackedBagAt or os.clock()
    return yanked
end

function S.markAutofarmDrillDropPending(item)
    -- Drop in Drill dumps at sack threshold; no mid-loot pending dump.
    Autofarm._pendingDrillDrop = false
end

function S.getDrillFlatLook()
    local drill = S.getDrill()
    if drill then
        local flat = Vector3.new(drill:GetPivot().LookVector.X, 0, drill:GetPivot().LookVector.Z)
        if flat.Magnitude > 0.05 then
            return flat.Unit
        end

        local head = drill:FindFirstChild("DrillHead", true)
        if head and head:IsA("BasePart") then
            flat = Vector3.new(head.CFrame.LookVector.X, 0, head.CFrame.LookVector.Z)
            if flat.Magnitude > 0.05 then
                return flat.Unit
            end
        end

        if drill.PrimaryPart then
            flat = Vector3.new(drill.PrimaryPart.CFrame.LookVector.X, 0, drill.PrimaryPart.CFrame.LookVector.Z)
            if flat.Magnitude > 0.05 then
                return flat.Unit
            end
        end
    end

    return Money.travelDirection or Vector3.new(0, 0, -1)
end

function S.getDrillLineOrigin()
    local drill = S.getDrill()
    if drill then
        return drill:GetPivot().Position
    end

    local root = S.getRoot()
    return root and root.Position or Vector3.zero
end

function S.ensureMoneyTravelHeading()
    Money.travelDirection = S.getDrillFlatLook()
    if not Money.lineOrigin then
        Money.lineOrigin = S.getDrillLineOrigin()
    end
    return Money.travelDirection
end

function S.resetMoneyTravelHeading()
    Money.travelDirection = S.getDrillFlatLook()
    Money.lineOrigin = S.getDrillLineOrigin()

    local root = S.getRoot()
    if root and Money.travelDirection.Magnitude > 0.05 then
        local rel = root.Position - Money.lineOrigin
        local flatRel = Vector3.new(rel.X, 0, rel.Z)
        Money.travelDistance = math.max(0, flatRel:Dot(Money.travelDirection.Unit))
    else
        Money.travelDistance = 0
    end

    return Money.travelDirection
end

function S.getGroundY(position)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local char = LocalPlayer.Character
    if char then
        params.FilterDescendantsInstances = { char }
    end

    local result = Workspace:Raycast(position + Vector3.new(0, 200, 0), Vector3.new(0, -500, 0), params)
    if result then
        return result.Position.Y
    end

    return math.max(position.Y - Money.walkHeight, 5)
end

function S.getPointOnDrillLine(distance)
    local dir = S.ensureMoneyTravelHeading()
    local origin = Money.lineOrigin or S.getDrillLineOrigin()
    local flatOrigin = Vector3.new(origin.X, 0, origin.Z)
    local linePoint = flatOrigin + dir * distance
    local groundY = S.getGroundY(Vector3.new(linePoint.X, origin.Y, linePoint.Z))
    return Vector3.new(linePoint.X, groundY, linePoint.Z)
end

function S.getWalkCFrame(atPosition)
    local groundY = S.getGroundY(atPosition)
    local y = groundY + Money.walkHeight
    local dir = S.ensureMoneyTravelHeading()
    local pos = Vector3.new(atPosition.X, y, atPosition.Z)
    return CFrame.lookAt(pos, pos + dir)
end

function S.setWalkOnLine(distance)
    local root = S.getRoot()
    if not root then
        return false
    end

    local point = S.getPointOnDrillLine(distance)
    local cf = S.getWalkCFrame(point)
    root.CFrame = cf
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    Money.lastGoodPosition = cf.Position
    Money.travelDistance = distance
    return true
end

function S.resumeOnDrillLine()
    return S.setWalkOnLine(Money.travelDistance or 0)
end

function S.advanceAlongLine(studs)
    return S.setWalkOnLine((Money.travelDistance or 0) + studs)
end

function S.teleportToGroundPosition(position, offset)
    local root = S.getRoot()
    if not root then
        return false
    end

    offset = offset or Vector3.new(0, 3, 0)
    local groundY = S.getGroundY(position)
    root.CFrame = CFrame.new(Vector3.new(position.X, groundY, position.Z) + offset)
    root.AssemblyLinearVelocity = Vector3.zero
    return true
end

function S.teleportToDrillViaVoid()
    local root = S.getRoot()
    if not root then
        return false
    end

    root.CFrame = CFrame.new(root.Position.X, -500, root.Position.Z)
    return true
end

function S.findNearestSellPart(fromPos)
    local root = S.getRoot()
    fromPos = fromPos or (root and root.Position)
    if not fromPos then
        return nil
    end

    local bestPart, bestDist = nil, math.huge

    local function consider(part)
        if not part or not part:IsA("BasePart") or part.Name ~= "SellPart" then
            return
        end
        local dist = (part.Position - fromPos).Magnitude
        if dist < bestDist then
            bestPart = part
            bestDist = dist
        end
    end

    -- Prefer known village SellParts first (fast + close to travel path).
    pcall(function()
        S.scanWorldModels(function(inst)
            if S.isVillageModel(inst) then
                local part = inst:FindFirstChild("SellPart", true)
                if part then
                    consider(part)
                end
            end
        end)
    end)

    -- Broader scan per Workspace root (avoids one giant GetDescendants timeout).
    pcall(function()
        for _, rootInst in ipairs(Workspace:GetChildren()) do
            if rootInst.Name == "SellPart" and rootInst:IsA("BasePart") then
                consider(rootInst)
            end
            pcall(function()
                for _, d in ipairs(rootInst:GetDescendants()) do
                    if d.Name == "SellPart" then
                        consider(d)
                    end
                end
            end)
        end
    end)

    return bestPart
end

function S.getSellTableModel(sellPart)
    local current = sellPart.Parent
    while current and current ~= Workspace do
        if current.Name == "Sell_Table" then
            return current
        end
        current = current.Parent
    end
    return sellPart.Parent
end

function S.getSellFloorY(sellPart, sellTable)
    local sellSpot = sellTable and sellTable:FindFirstChild("SellSpot", true)
    if sellSpot and sellSpot:IsA("BasePart") then
        return sellSpot.Position.Y - sellSpot.Size.Y / 2 + 1.5
    end

    local tableModel = sellTable and sellTable:FindFirstChild("Table", true)
    if tableModel then
        local part = tableModel:IsA("BasePart") and tableModel or tableModel:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.Position.Y + part.Size.Y / 2 + 1.5
        end
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local char = LocalPlayer.Character
    if char then
        params.FilterDescendantsInstances = { char }
    end

    local origin = Vector3.new(sellPart.Position.X, sellPart.Position.Y - 8, sellPart.Position.Z)
    local result = Workspace:Raycast(origin, Vector3.new(0, -40, 0), params)
    if result then
        return result.Position.Y + 3
    end

    return sellPart.Position.Y - 3
end

function S.getSellStandCFrame(sellPart)
    local sellTable = S.getSellTableModel(sellPart)
    local floorY = S.getSellFloorY(sellPart, sellTable)

    local away = sellPart.CFrame.LookVector
    local flatAway = Vector3.new(away.X, 0, away.Z)
    if flatAway.Magnitude < 0.05 then
        flatAway = Vector3.new(0, 0, 1)
    else
        flatAway = flatAway.Unit
    end

    local standPos = Vector3.new(sellPart.Position.X, floorY, sellPart.Position.Z) + flatAway * 5
    local lookAt = Vector3.new(sellPart.Position.X, floorY, sellPart.Position.Z)
    return CFrame.lookAt(standPos, lookAt)
end

function S.getSellDropCFrame(sellPart)
    -- Exact top-center of SellPart (TradeSell pad).
    return sellPart.CFrame * CFrame.new(0, sellPart.Size.Y * 0.5 + 0.12, 0)
end

-- Stand dead-center on TradeSell so bagDrop lands on the pad.
function S.snapCharacterOntoTradeSell(sellPart)
    local root = S.getRoot()
    if not root or not sellPart then
        return false
    end

    local dropCf = S.getSellDropCFrame(sellPart)
    local standY = dropCf.Position.Y + 2.15
    Autofarm._gatePinY = standY
    root.Anchored = false
    root.CFrame = CFrame.new(dropCf.Position.X, standY, dropCf.Position.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    S.setAutofarmPlatformStand(true)
    return true
end

-- Item utama (tidak boleh dijual / di-drop): pickaxe, pedang, semua senjata (gun, RPG, Black Hole),
-- dan item Phoenix.
function S.isMainItem(item)
    if not item then
        return false
    end
    if S.isPhoenixTool(item) then
        return true
    end
    local ok, cat = pcall(S.getGearItemCategory, item)
    if ok and (cat == "Pickaxe" or cat == "Sword" or cat == "Gun") then
        return true
    end
    return false
end

-- Tool yang tidak pernah dijual oleh Auto Sell.
function S.isSellProtected(tool)
    if not tool then
        return true
    end
    if S.isMainItem(tool) or S.isItemBagTool(tool) or S.shardTierOf(tool) then
        return true
    end
    local label = string.lower(tostring(tool.Name or "") .. " " .. tostring(tool:GetAttribute("DisplayName") or ""))
    for _, key in ipairs({ "medkit", "bandage", "revive", "potion", "scepter", "shard", "crystal" }) do
        if label:find(key, 1, true) then
            return true
        end
    end
    return false
end

-- Kumpulkan info inventory baru (remote, UI, tool) lalu salin ke clipboard / print.
function S.dumpInventoryDebugInfo()
    local lines = {}
    local function add(text)
        table.insert(lines, tostring(text))
    end
    add("== Hotbar tools ==")
    for _, t in ipairs(S.ownedToolList()) do
        local attrs = {}
        for k, v in pairs(t:GetAttributes()) do
            table.insert(attrs, tostring(k) .. "=" .. tostring(v))
        end
        add(string.format("%s | CanBeDropped=%s | %s", t.Name, tostring(t.CanBeDropped), table.concat(attrs, ", ")))
    end
    add("== Services known ==")
    for name in pairs(Services) do
        add(tostring(name))
    end
    add("== Remotes (inventory/drop/pickup/slot/hotbar) ==")
    local count = 0
    pcall(function()
        for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
            if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
                local full = d:GetFullName()
                local low = string.lower(full)
                if low:find("inventory", 1, true) or low:find("drop", 1, true) or low:find("pickup", 1, true)
                    or low:find("slot", 1, true) or low:find("hotbar", 1, true) or low:find("backpack", 1, true) then
                    add(full)
                    count += 1
                    if count >= 80 then
                        break
                    end
                end
            end
        end
    end)
    add("== PlayerGui (inventory/hotbar/slot) ==")
    count = 0
    pcall(function()
        for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            local low = string.lower(d.Name)
            if low:find("inventory", 1, true) or low:find("hotbar", 1, true) or low:find("slot", 1, true) then
                add(d.ClassName .. " " .. d:GetFullName())
                count += 1
                if count >= 60 then
                    break
                end
            end
        end
    end)
    pcall(S.probeCarryInventory, add)
    pcall(S.dumpBackpackUi, add)
    local text = table.concat(lines, "\n")
    print("[JPAX inventory debug]\n" .. text)
    local copied = false
    if typeof(setclipboard) == "function" then
        copied = pcall(setclipboard, text)
    elseif typeof(toclipboard) == "function" then
        copied = pcall(toclipboard, text)
    end
    S.notify(HUB_NAME, copied and "Inventory info copied to clipboard" or "Inventory info printed to console", 4)
end

-- ========== INVENTORY SPY / PROBE (learn the new carry-inventory API) ==========
-- Read-only tools: they LOG what the game's own client sends and what GetInventory returns.
-- They never drop, store or move anything.
S.InvSpy = S.InvSpy or {
    on = false,
    hooked = false,
    log = {},
    maxLines = 300,
    keys = { "carryinventory", "toolservice", "interactionservice", "dragservice", "inventory", "drop", "pickup", "store" },
}

function S.invSerialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local kind = typeof(value)
    if kind == "string" then
        return string.format("%q", value)
    elseif kind == "Instance" then
        local text = "<" .. value.ClassName .. " " .. value:GetFullName()
        if depth == 0 then
            local attrs = {}
            for key, attr in pairs(value:GetAttributes()) do
                if #attrs < 12 then
                    table.insert(attrs, tostring(key) .. "=" .. tostring(attr))
                end
            end
            if #attrs > 0 then
                text = text .. " {" .. table.concat(attrs, ", ") .. "}"
            end
        end
        return text .. ">"
    elseif kind == "table" then
        if seen[value] then
            return "<cycle>"
        end
        if depth >= 4 then
            return "{...}"
        end
        seen[value] = true
        local parts, n = {}, 0
        for key, val in pairs(value) do
            n += 1
            if n > 40 then
                table.insert(parts, "...")
                break
            end
            table.insert(parts, "[" .. S.invSerialize(key, depth + 1, seen) .. "]=" .. S.invSerialize(val, depth + 1, seen))
        end
        seen[value] = nil
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(value)
end

-- Called from inside the __namecall hook: property reads only (no method calls), real work is deferred.
function S.invSpyCapture(remote, method, args, fromScript)
    pcall(function()
        local parts, node = {}, remote
        for _ = 1, 12 do
            if not node or node == game then
                break
            end
            table.insert(parts, 1, node.Name)
            node = node.Parent
        end
        local path = table.concat(parts, ".")
        local low = string.lower(path)
        if string.sub(low, -7) == ".update" then
            return -- swing/shoot spam
        end
        local matched = false
        for _, key in ipairs(S.InvSpy.keys) do
            if string.find(low, key, 1, true) then
                matched = true
                break
            end
        end
        if not matched then
            return
        end
        local stamp = os.clock()
        task.defer(function()
            local argText = {}
            for i = 1, args.n do
                table.insert(argText, S.invSerialize(args[i]))
            end
            local line = string.format(
                "[%.2f] %s %s %s(%s)",
                stamp,
                fromScript and "[script]" or "[GAME]",
                method,
                path,
                table.concat(argText, ", ")
            )
            local log = S.InvSpy.log
            table.insert(log, line)
            if #log > S.InvSpy.maxLines then
                table.remove(log, 1)
            end
        end)
    end)
end

function S.setInventorySpy(enabled)
    local spy = S.InvSpy
    spy.on = enabled == true
    if not spy.on then
        return
    end
    if spy.hooked then
        S.notify(HUB_NAME, "Inventory Spy ON", 3)
        return
    end
    if typeof(hookmetamethod) ~= "function" or typeof(getnamecallmethod) ~= "function" then
        spy.on = false
        S.notify(HUB_NAME, "Executor has no hookmetamethod/getnamecallmethod", 4)
        return
    end

    local wrap = function(fn)
        return fn
    end
    if typeof(newcclosure) == "function" then
        wrap = newcclosure
    end

    local oldNamecall
    local ok = pcall(function()
        oldNamecall = hookmetamethod(
            game,
            "__namecall",
            wrap(function(self, ...)
                local method = getnamecallmethod()
                if spy.on and (method == "FireServer" or method == "InvokeServer") then
                    local args = table.pack(...)
                    local fromScript = false
                    if typeof(checkcaller) == "function" then
                        fromScript = checkcaller() == true
                    end
                    S.invSpyCapture(self, method, args, fromScript)
                end
                return oldNamecall(self, ...)
            end)
        )
    end)

    if ok and oldNamecall then
        spy.hooked = true
        S.notify(HUB_NAME, "Inventory Spy ON — now pick up / drop items manually", 4)
    else
        spy.on = false
        S.notify(HUB_NAME, "Inventory Spy failed to hook", 4)
    end
end

local function invCopyToClipboard(text)
    if typeof(setclipboard) == "function" then
        return pcall(setclipboard, text)
    elseif typeof(toclipboard) == "function" then
        return pcall(toclipboard, text)
    end
    return false
end

function S.copyInventorySpyLog()
    local log = S.InvSpy.log
    local text
    if #log > 0 then
        text = table.concat(log, "\n")
    else
        text = "(spy log empty - turn Inventory Spy on, then pick up / drop items manually)"
    end
    print("[JPAX inventory spy]\n" .. text)
    local copied = invCopyToClipboard(text)
    S.notify(HUB_NAME, copied and ("Spy log copied (" .. #log .. " lines)") or "Spy log printed to console", 4)
end

function S.clearInventorySpyLog()
    table.clear(S.InvSpy.log)
    S.notify(HUB_NAME, "Inventory Spy log cleared", 2)
end

function S.probeCarryInventory(add)
    add("== CarryInventoryService ==")
    local svc = Services.CarryInventoryService
    if not svc then
        local knit = S.getKnit()
        if knit then
            local ok, got = pcall(function()
                return knit.GetService("CarryInventoryService")
            end)
            if ok and got then
                svc = got
                Services.CarryInventoryService = got
            end
        end
    end
    if not svc then
        add("service not available via Knit")
        return
    end

    local members = {}
    for key, value in pairs(svc) do
        table.insert(members, tostring(key) .. ":" .. typeof(value))
    end
    table.sort(members)
    add("members: " .. table.concat(members, ", "))

    local ok, res = pcall(function()
        return S.waitForKnitPromise(svc:GetInventory(), 3)
    end)
    add("GetInventory ok=" .. tostring(ok) .. " -> " .. S.invSerialize(res))
end

function S.dumpBackpackUi(add)
    add("== Backpack UI tree ==")
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local ui = gui and gui:FindFirstChild("UI")
    local hud = ui and ui:FindFirstChild("HUD")
    local root = hud and hud:FindFirstChild("Backpack")
    if not root then
        add("UI.HUD.Backpack not found")
        return
    end

    local count, scrollShown = 0, 0
    for _, d in ipairs(root:GetDescendants()) do
        local skip = false
        if d:FindFirstAncestorOfClass("ScrollingFrame") then
            scrollShown += 1
            if scrollShown > 40 then
                skip = true
            end
        end
        if not skip then
            local extra = ""
            if d:IsA("GuiObject") then
                extra = extra .. " visible=" .. tostring(d.Visible)
            end
            if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                extra = extra .. " text=" .. string.format("%q", d.Text)
            end
            local path = (d:GetFullName():gsub("^.-HUD%.Backpack", "Backpack"))
            add(d.ClassName .. " " .. path .. extra)
            count += 1
            if count >= 200 then
                add("... truncated")
                break
            end
        end
    end
end

function S.moveItemsOntoSellPart(sellPart, radius)
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder or not sellPart then
        return 0
    end

    local dropCf = S.getSellDropCFrame(sellPart)
    local center = dropCf.Position
    radius = radius or 40
    local moved = 0
    for _, item in ipairs(itemsFolder:GetChildren()) do
        -- Skip money bags — those are collected after the dump.
        if item.Name ~= "Money_Sack" and item:GetAttribute("Class") ~= "Money_Sack"
            and not S.isMainItem(item) then
            local pos = S.getItemPosition(item)
            if pos and (pos - center).Magnitude <= radius then
                if S.moveItemToCFrame(item, dropCf) then
                    moved += 1
                end
            end
        end
    end

    return moved
end

-- After each Drop: yank EVERY nearby non-sack item onto exact TradeSell top.
function S.forceDropsOntoTradeSell(sellPart)
    if not sellPart then
        return 0
    end
    S.snapCharacterOntoTradeSell(sellPart)
    local moved = S.moveItemsOntoSellPart(sellPart, 55)
    -- Second pass closer — catch anything that slid off.
    moved += S.moveItemsOntoSellPart(sellPart, 20)
    return moved
end

function S.standNextToWorldItem(item, distance)
    local pos = S.getItemPosition(item)
    local root = S.getRoot()
    if not pos or not root then
        return false
    end

    distance = distance or 2.5
    local toItem = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
    if toItem.Magnitude < 0.5 then
        toItem = S.ensureMoneyTravelHeading() * -1
    end
    toItem = toItem.Unit

    local stand = pos - toItem * distance
    local groundY = S.getGroundY(stand)
    local standPos = Vector3.new(stand.X, groundY + 3, stand.Z)
    local lookAt = Vector3.new(pos.X, groundY + 3, pos.Z)
    root.CFrame = CFrame.lookAt(standPos, lookAt)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end

function S.interactMoneySack(item)
    if not item or not item.Parent or not Services.InteractionService then
        return false
    end

    pcall(function()
        Services.ToolService:UnequipTool()
    end)
    task.wait(0.15)

    S.standNextToWorldItem(item, 2)
    task.wait(0.12)

    local knit = S.getKnit()
    if knit then
        pcall(function()
            local drag = knit.GetController("DragController")
            drag.Target = item
            if drag.TargetChanged then
                drag.TargetChanged:Fire(item)
            end
        end)
    end

    task.wait(0.08)

    local interacted = false
    pcall(function()
        Services.InteractionService:Interact(item)
        interacted = true
    end)

    if knit then
        pcall(function()
            local drag = knit.GetController("DragController")
            if drag.PerformConsoleInteract then
                drag:PerformConsoleInteract()
                interacted = true
            end
        end)
    end

    task.wait(0.2)
    return interacted
end

function S.isDungeonRoot(inst)
    if not inst or not inst:IsA("Model") then
        return false
    end
    -- Only top-level Workspace.DungeonGate_* (ignore nested DungeonGate_Tier1 inside the interior).
    if inst.Parent ~= Workspace then
        return false
    end
    return tostring(inst.Name or ""):find("DungeonGate_", 1, true) ~= nil
end

function S.getDungeonApproachPos(dungeonRoot)
    if not dungeonRoot then
        return nil, nil
    end
    local path = dungeonRoot:FindFirstChild("Path1")
        or dungeonRoot:FindFirstChild("Path2")
        or dungeonRoot:FindFirstChild("Path3")
    if path then
        local pos = S.getInstancePosition(path)
        if pos then
            return pos, path
        end
    end
    local qs = dungeonRoot:FindFirstChild("QueueSpot", true)
    if qs then
        local pos = S.getInstancePosition(qs)
        if pos then
            return pos, qs
        end
    end
    for _, door in ipairs(CollectionService:GetTagged("DungeonDoor")) do
        if door:IsDescendantOf(dungeonRoot)
            and door.Name ~= "Gate_Cave"
            and door.Name ~= "Gate_Mineshaft"
        then
            local pos = S.getInstancePosition(door)
            if pos then
                return pos, door
            end
        end
    end
    return S.getInstancePosition(dungeonRoot) or dungeonRoot:GetPivot().Position, nil
end

function S.getInstancePosition(inst)
    if not inst then
        return nil
    end
    if inst:IsA("BasePart") then
        return inst.Position
    end
    if inst:IsA("Attachment") then
        return inst.WorldPosition
    end
    if inst:IsA("Model") then
        return inst:GetPivot().Position
    end
    if inst:IsA("Folder") or inst:IsA("Configuration") then
        local part = inst:FindFirstChildWhichIsA("BasePart", true)
            or inst:FindFirstChildWhichIsA("Attachment", true)
        if part then
            return S.getInstancePosition(part)
        end
    end
    local part = inst:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part.Position
    end
    local att = inst:FindFirstChildWhichIsA("Attachment", true)
    return att and att.WorldPosition or nil
end

function S.tryFireProximityPrompt(instance)
    -- Do NOT mutate ProximityPrompt properties — that was breaking chests.
    if not instance then
        return false
    end

    local function fireOne(prompt)
        if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
            return false
        end
        if typeof(fireproximityprompt) ~= "function" then
            return false
        end
        local hold = tonumber(prompt.HoldDuration) or 0
        local ok = pcall(function()
            if hold > 0 then
                local held = pcall(fireproximityprompt, prompt, hold)
                if not held then
                    fireproximityprompt(prompt)
                    task.wait(hold + 0.08)
                    fireproximityprompt(prompt)
                else
                    task.wait(hold + 0.08)
                end
            else
                fireproximityprompt(prompt)
            end
        end)
        return ok == true
    end

    local fired = false
    if instance:IsA("ProximityPrompt") then
        fired = fireOne(instance) or fired
    end
    for _, desc in ipairs(instance:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            fired = fireOne(desc) or fired
        end
    end
    return fired
end

function S.collectProximityPrompts(instance)
    local prompts = {}
    if not instance then
        return prompts
    end
    if instance:IsA("ProximityPrompt") and instance.Enabled then
        table.insert(prompts, instance)
    end
    for _, desc in ipairs(instance:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled then
            table.insert(prompts, desc)
        end
    end
    return prompts
end

function S.getPromptWorldPosition(prompt)
    if not prompt then
        return nil
    end
    local parent = prompt.Parent
    -- Gate.Attachment.ProximityPrompt → Attachment.WorldPosition
    if parent and parent:IsA("Attachment") then
        return parent.WorldPosition
    end
    if parent and parent:IsA("BasePart") then
        return parent.Position
    end
    if parent then
        local att = parent:FindFirstChildWhichIsA("Attachment")
        if att then
            return att.WorldPosition
        end
        local part = parent:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.Position
        end
    end
    return S.getInstancePosition(prompt) or S.getItemPosition(prompt)
end

function S.promptActionLower(prompt)
    if not prompt then
        return ""
    end
    return string.lower(tostring(prompt.ActionText or "") .. " " .. tostring(prompt.ObjectText or ""))
end

function S.promptLooksLikeEnter(prompt)
    local t = S.promptActionLower(prompt)
    return t:find("enter", 1, true) ~= nil or t:find("entrar", 1, true) ~= nil
end

function S.promptLooksLikeExit(prompt)
    local t = S.promptActionLower(prompt)
    return t:find("sair", 1, true) ~= nil
        or t:find("leave", 1, true) ~= nil
        or t:find("exit", 1, true) ~= nil
end

-- TP onto Gate.Attachment then fire Enter / Sair — stay PlatformStand, never freefall.
function S.teleportToPromptAndFire(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then
        return false
    end

    local root = S.getRoot()
    local pos = S.getPromptWorldPosition(prompt)
    if not root or not pos then
        return false
    end

    local standY = pos.Y + 2.5
    local flyY = S.getAutofarmFlyY()
    Autofarm._gatePinY = standY
    if Autofarm.enabled then
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
    end
    S.setAutofarmPlatformStand(true)
    root.Anchored = false
    root.CFrame = CFrame.new(pos.X, standY, pos.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    pcall(function()
        S.requestStreamAround(pos, 1.2)
    end)
    task.wait(0.12)

    local prePos = root.Position
    local fired = S.tryFireProximityPrompt(prompt)

    -- Stay glued until server TP lands (or timeout) — never hover=off mid-gate.
    local deadline = os.clock() + 1.4
    local teleported = false
    while os.clock() < deadline do
        root = S.getRoot()
        if not root then
            break
        end
        S.setAutofarmPlatformStand(true)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        local now = root.Position
        if (Vector3.new(now.X - prePos.X, 0, now.Z - prePos.Z)).Magnitude > 10
            or math.abs(now.Y - prePos.Y) > 12 then
            teleported = true
            Autofarm._gatePinY = flyY
            local dir = S.getAutofarmAxisVector()
            local hold = Vector3.new(now.X, flyY, now.Z)
            root.CFrame = CFrame.lookAt(hold, hold + dir)
            break
        end

        Autofarm._gatePinY = standY
        root.CFrame = CFrame.new(pos.X, standY, pos.Z)
        task.wait()
    end

    Autofarm._gatePinY = nil
    root = S.getRoot()
    if root then
        local dir = S.getAutofarmAxisVector()
        local hold = Vector3.new(root.Position.X, flyY, root.Position.Z)
        root.CFrame = CFrame.lookAt(hold, hold + dir)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        S.setAutofarmPlatformStand(true)
    end
    if Autofarm.enabled then
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
    end
    return fired, teleported
end

-- Enter: DungeonGate_*.Gate.Attachment.ProximityPrompt (ActionText Enter)
function S.findDungeonEnterPrompt(dungeonRoot)
    if not dungeonRoot then
        return nil
    end
    local gate = dungeonRoot:FindFirstChild("Gate")
    if gate then
        for _, desc in ipairs(gate:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled and S.promptLooksLikeEnter(desc) then
                return desc
            end
        end
        for _, desc in ipairs(gate:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled then
                return desc
            end
        end
    end
    for _, desc in ipairs(dungeonRoot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled and S.promptLooksLikeEnter(desc) then
            local underInterior = false
            local cur = desc.Parent
            while cur and cur ~= dungeonRoot do
                local n = tostring(cur.Name or "")
                if (n:match("^Dungeon_") or n:find("Dungeon_Tier", 1, true))
                    and not n:find("DungeonGate", 1, true)
                then
                    underInterior = true
                    break
                end
                if n:find("DungeonGate_", 1, true) and cur ~= dungeonRoot then
                    underInterior = true
                    break
                end
                cur = cur.Parent
            end
            if not underInterior then
                return desc
            end
        end
    end
    return nil
end

-- Leave: ...Dungeon_*.DungeonGate_*.Gate.Attachment (ActionText Sair)
function S.findDungeonExitPrompt(dungeonRoot)
    if not dungeonRoot then
        return nil
    end
    local best, bestDist = nil, math.huge
    local root = S.getRoot()
    local origin = root and root.Position

    for _, desc in ipairs(dungeonRoot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled and S.promptLooksLikeExit(desc) then
            local pos = S.getPromptWorldPosition(desc)
            local dist = (origin and pos) and (pos - origin).Magnitude or 0
            if dist < bestDist then
                bestDist = dist
                best = desc
            end
        end
    end
    if best then
        return best
    end

    for _, desc in ipairs(dungeonRoot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled then
            local cur = desc.Parent
            local nested = false
            while cur and cur ~= dungeonRoot do
                local n = tostring(cur.Name or "")
                if n:find("DungeonGate_", 1, true) and cur ~= dungeonRoot then
                    nested = true
                    break
                end
                if n:match("^Dungeon_") and not n:find("DungeonGate", 1, true) then
                    nested = true
                    break
                end
                cur = cur.Parent
            end
            if nested then
                return desc
            end
        end
    end
    return nil
end

function S.findMineEnterPrompt(mine)
    if not mine then
        return nil
    end
    for _, desc in ipairs(mine:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled and S.promptLooksLikeEnter(desc) then
            return desc
        end
    end
    return nil
end

function S.findMineExitPrompt(mine)
    if not mine then
        return nil
    end
    local best, bestDist = nil, math.huge
    local root = S.getRoot()
    local origin = root and root.Position
    for _, desc in ipairs(mine:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled and S.promptLooksLikeExit(desc) then
            local pos = S.getPromptWorldPosition(desc)
            local dist = (origin and pos) and (pos - origin).Magnitude or 0
            if dist < bestDist then
                bestDist = dist
                best = desc
            end
        end
    end
    return best
end

function S.faceCharacterToward(worldPos)
    local root = S.getRoot()
    if not root or not worldPos then
        return
    end
    local pos = root.Position
    local flat = Vector3.new(worldPos.X, pos.Y, worldPos.Z)
    if (flat - pos).Magnitude < 0.05 then
        return
    end
    root.CFrame = CFrame.lookAt(pos, flat)
    root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
    root.AssemblyAngularVelocity = Vector3.zero
end

function S.aimCameraAtWorld(worldPos, saved)
    local cam = Workspace.CurrentCamera
    if not cam or not worldPos then
        return saved
    end

    if not saved then
        saved = {
            cf = cam.CFrame,
            cameraType = cam.CameraType,
            subject = cam.CameraSubject,
        }
    end

    local root = S.getRoot()
    local eye = (root and (root.Position + Vector3.new(0, 2.2, 0))) or cam.CFrame.Position
    pcall(function()
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = CFrame.lookAt(eye, worldPos)
    end)
    return saved
end

function S.restoreCameraAim(saved)
    if not saved then
        return
    end
    local cam = Workspace.CurrentCamera
    if not cam then
        return
    end
    pcall(function()
        cam.CameraType = saved.cameraType or Enum.CameraType.Custom
        if saved.subject then
            cam.CameraSubject = saved.subject
        end
        if saved.cf then
            cam.CFrame = saved.cf
        end
    end)
end

-- Soften prompt eligibility for hold only. Never touch HoldDuration.
function S.preparePromptsForHold(prompts)
    local backup = {}
    for _, prompt in ipairs(prompts) do
        local entry = {
            prompt = prompt,
            requiresLOS = prompt.RequiresLineOfSight,
            maxDist = prompt.MaxActivationDistance,
            exclusivity = prompt.Exclusivity,
        }
        pcall(function()
            prompt.RequiresLineOfSight = false
            prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
        end)
        table.insert(backup, entry)
    end
    return backup
end

function S.restorePromptsAfterHold(backup)
    if type(backup) ~= "table" then
        return
    end
    for _, entry in ipairs(backup) do
        local prompt = entry.prompt
        if prompt and prompt.Parent then
            pcall(function()
                prompt.RequiresLineOfSight = entry.requiresLOS
                prompt.MaxActivationDistance = entry.maxDist
                prompt.Exclusivity = entry.exclusivity
            end)
        end
    end
end

function S.pressInteractKey()
    local pressed = false
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        if vim then
            vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            pressed = true
        end
    end)
    return pressed
end

-- Hold time from the chest's own ProximityPrompt (Void=5s, Diamond=4s, etc.).
function S.getChestHoldSeconds(chest)
    if not chest then
        return 0.1
    end

    chest = S.resolveDungeonChestModel(chest) or chest
    local maxHold = 0
    for _, prompt in ipairs(S.collectProximityPrompts(chest)) do
        local hold = tonumber(prompt.HoldDuration) or 0
        if hold > maxHold then
            maxHold = hold
        end
    end

    if maxHold > 0 then
        return maxHold + 0.12
    end
    return 0.1
end

-- Hold E + prompt InputHoldBegin/End. Camera locked on ProximityPrompt.
function S.holdChestInteract(instance, seconds)
    if seconds == nil then
        seconds = S.getChestHoldSeconds(instance)
    end
    seconds = tonumber(seconds) or 0.1
    if seconds < 0.1 then
        seconds = 0.1
    end

    local prompts = S.collectProximityPrompts(instance)
    local lookPos = nil
    if #prompts > 0 then
        lookPos = S.getPromptWorldPosition(prompts[1])
    end
    lookPos = lookPos or S.getInstancePosition(instance) or S.getItemPosition(instance)

    local promptBackup = S.preparePromptsForHold(prompts)
    local camBackup = nil
    if lookPos then
        S.faceCharacterToward(lookPos)
        camBackup = S.aimCameraAtWorld(lookPos, nil)
    end

    local vim
    pcall(function()
        vim = game:GetService("VirtualInputManager")
    end)

    -- Let prompt UI refresh after LOS/camera changes.
    task.wait(0.08)

    for _, prompt in ipairs(prompts) do
        pcall(function()
            prompt:InputHoldBegin()
        end)
    end
    pcall(function()
        if vim then
            vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        end
    end)

    local deadline = os.clock() + seconds
    while os.clock() < deadline do
        if S.playerGuiSaysChestLocked() then
            S.markChestLocked(instance)
            break
        end
        if FollowPlatform.enabled and FollowPlatform.lockedTarget then
            S.updateFollowPlatform()
            S.supportCharacterOnFollowPlatform()
        end
        -- Keep camera glued to the prompt the whole hold.
        if #prompts > 0 then
            lookPos = S.getPromptWorldPosition(prompts[1]) or lookPos
        end
        if lookPos then
            S.faceCharacterToward(lookPos)
            camBackup = S.aimCameraAtWorld(lookPos, camBackup)
        end
        task.wait(0.05)
    end

    for _, prompt in ipairs(prompts) do
        pcall(function()
            prompt:InputHoldEnd()
        end)
    end
    pcall(function()
        if vim then
            vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end
    end)

    S.restorePromptsAfterHold(promptBackup)
    S.restoreCameraAim(camBackup)

    if S.playerGuiSaysChestLocked() then
        S.markChestLocked(instance)
        return false
    end

    return true
end

function S.openChestHold(chest, seconds)
    return S.holdChestInteract(chest, seconds)
end

function S.ensureFollowPlatform()
    if FollowPlatform.part and FollowPlatform.part.Parent then
        return FollowPlatform.part
    end

    local part = Instance.new("Part")
    part.Name = "JPAX_FollowPlatform"
    part.Anchored = true
    part.CanCollide = true
    part.CanQuery = false
    part.CanTouch = false
    part.Material = Enum.Material.SmoothPlastic
    part.Color = Color3.fromRGB(55, 55, 60)
    part.Transparency = 0.35
    part.Size = Vector3.new(FollowPlatform.sizeX or 14, FollowPlatform.thickness or 1, FollowPlatform.sizeZ or 14)
    part.Parent = Workspace
    FollowPlatform.part = part
    return part
end

function S.destroyFollowPlatform()
    S.disconnectAll("followPlatform")
    FollowPlatform.lockedTarget = nil
    if FollowPlatform.part then
        pcall(function()
            FollowPlatform.part:Destroy()
        end)
        FollowPlatform.part = nil
    end
end

function S.getFollowStandOffset()
    local humanoid = S.getHumanoid()
    local hip = (humanoid and humanoid.HipHeight) or 2
    return hip + 1 -- roughly feet → HRP
end

function S.getFollowPlatformCFrame()
    local root = S.getRoot()
    if not root then
        return nil
    end

    local thickness = FollowPlatform.thickness or 1
    local standOffset = S.getFollowStandOffset()

    -- lockedTarget / height = desired HRP stand Y (platform top sits below that).
    if FollowPlatform.lockedTarget then
        local t = FollowPlatform.lockedTarget
        if typeof(S.isSaneWorldPos) == "function" and not S.isSaneWorldPos(t) then
            return nil
        end
        local topY = t.Y - standOffset
        return CFrame.new(t.X, topY - thickness * 0.5, t.Z)
    end

    local standY = FollowPlatform.height or Autofarm.flyY or 28.89
    local topY = standY - standOffset
    return CFrame.new(root.Position.X, topY - thickness * 0.5, root.Position.Z)
end

function S.snapCharacterOntoPlatform()
    local root = S.getRoot()
    local part = FollowPlatform.part
    if not root or not part or not part.Parent then
        return false
    end

    local topY = part.Position.Y + part.Size.Y * 0.5
    local stand = Vector3.new(part.Position.X, topY + S.getFollowStandOffset(), part.Position.Z)
    if typeof(S.isSaneWorldPos) == "function" and not S.isSaneWorldPos(stand) then
        return false
    end

    root.Anchored = false
    S.setAutofarmPlatformStand(true)
    root.CFrame = CFrame.new(stand)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end

function S.lockFollowPlatformAt(worldPos)
    if worldPos and (typeof(S.isSaneWorldPos) ~= "function" or S.isSaneWorldPos(worldPos)) then
        FollowPlatform.lockedTarget = worldPos
    else
        FollowPlatform.lockedTarget = nil
    end
    S.updateFollowPlatform()
end

function S.clearFollowPlatformLock()
    FollowPlatform.lockedTarget = nil
end

function S.updateFollowPlatform()
    if not FollowPlatform.enabled then
        return
    end

    local part = S.ensureFollowPlatform()
    local cf = S.getFollowPlatformCFrame()
    if not part or not cf then
        return
    end

    part.Size = Vector3.new(FollowPlatform.sizeX or 14, FollowPlatform.thickness or 1, FollowPlatform.sizeZ or 14)
    part.CanCollide = true
    part.CFrame = cf
end

-- Noclip sets character CanCollide=false, so physics can't stand on the pad.
-- Soft-floor / hard-lock the HRP onto the platform while noclip (or lock) is active.
function S.supportCharacterOnFollowPlatform()
    if not FollowPlatform.enabled then
        return
    end

    local part = FollowPlatform.part
    local root = S.getRoot()
    if not part or not part.Parent or not root then
        return
    end

    part.CanCollide = true

    local needsSupport = State.noclip or FollowPlatform.lockedTarget ~= nil
    if not needsSupport then
        return
    end

    local topY = part.Position.Y + part.Size.Y * 0.5
    local standY = topY + S.getFollowStandOffset()

    if FollowPlatform.lockedTarget then
        root.Anchored = false
        S.setAutofarmPlatformStand(true)
        root.CFrame = CFrame.new(part.Position.X, standY, part.Position.Z)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return
    end

    local half = part.Size * 0.5
    local localPos = part.CFrame:PointToObjectSpace(root.Position)
    local onPad = math.abs(localPos.X) <= half.X + 3 and math.abs(localPos.Z) <= half.Z + 3
    if not onPad then
        return
    end

    if root.Position.Y < standY then
        root.CFrame = CFrame.new(root.Position.X, standY, root.Position.Z)
        local v = root.AssemblyLinearVelocity
        if v.Y < 0 then
            root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
        end
    end
end

function S.setFollowPlatform(enabled)
    FollowPlatform.enabled = enabled == true
    S.disconnectAll("followPlatform")

    if not FollowPlatform.enabled then
        S.destroyFollowPlatform()
        return
    end

    S.ensureFollowPlatform()
    S.updateFollowPlatform()
    S.snapCharacterOntoPlatform()

    State.connections.followPlatform = RunService.Heartbeat:Connect(function()
        if not FollowPlatform.enabled then
            return
        end
        S.updateFollowPlatform()
        S.supportCharacterOnFollowPlatform()
    end)
end

function S.inspectChest(chest)
    if not chest then
        return "nil"
    end
    local prompts = 0
    local interactive = CollectionService:HasTag(chest, "Interactive")
    for _, d in ipairs(chest:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            prompts += 1
        end
        if CollectionService:HasTag(d, "Interactive") then
            interactive = true
        end
    end
    local pos = S.getInstancePosition(chest)
    local posText = pos and string.format("%.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z) or "?"
    return string.format(
        "%s | prompts=%d | interactive=%s | padlock=%s | pos=%s | path=%s",
        chest.Name,
        prompts,
        tostring(interactive),
        tostring(S.isChestPadlocked(chest)),
        posText,
        chest:GetFullName()
    )
end

-- Strip OreNode_/WormNode_/digits so OreNode_Ruby1 → ruby, WormNode_Coal2 → coal.
function S.normalizeOreBaseName(name)
    local n = string.lower(tostring(name or ""))
    n = n:gsub("[%s%-]+", "_")
    n = n:gsub("^orenode_", ""):gsub("^wormnode_", ""):gsub("^ore_", "")
    n = n:gsub("^worm_", "")
    n = n:gsub("_+worm$", ""):gsub("worm$", "")
    n = n:gsub("%d+$", "")
    n = n:gsub("^_+", ""):gsub("_+$", "")
    return n
end

function S.getOreDropdownOptions()
    return ORE_DROPDOWN_OPTIONS
end

-- MeshPart "Ore" (gem) under the socket.
function S.getOreGemPart(ore)
    if not ore or not ore.Parent then
        return nil
    end

    local preferred = ore:FindFirstChild("Ore")
    if preferred and preferred:IsA("BasePart") then
        return preferred
    end

    for _, desc in ipairs(ore:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name == "Ore" then
            return desc
        end
    end
    return nil
end

function S.isOreNodeName(name)
    if type(name) ~= "string" then
        return false
    end
    local lower = string.lower(name)
    return lower:sub(1, 4) == "ore_" or lower:sub(1, 4) == "ore " or lower == "ore"
end

-- Map hub type string (Coal / Iron / WormIron) → dropdown key + worm flag.
function S.mapOreTypeString(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil, false
    end
    local lower = string.lower(raw)
    if lower:find("pathblocker", 1, true) then
        return nil, false
    end

    local isWorm = lower:sub(1, 4) == "worm" or lower:find("worm", 1, true) ~= nil
    local base = raw
    if base:sub(1, 4) == "Worm" then
        base = base:sub(5)
    elseif lower:sub(1, 4) == "worm" then
        base = raw:sub(5)
    end
    base = S.normalizeOreBaseName(base)
    if base == "" then
        return nil, isWorm
    end

    for known, _ in pairs(ORE_TYPE_COLORS) do
        if base == string.lower(known) then
            return ORE_TYPE_REMAP[known] or known, isWorm
        end
    end
    for _, opt in ipairs(ORE_DROPDOWN_OPTIONS) do
        if base == string.lower(opt) then
            return opt, isWorm
        end
    end
    if base == "iron" then
        return "Copper", isWorm
    end
    if base == "heart" or base == "heart_gem" or base == "heartgem" then
        return "HeartGem", isWorm
    end
    return nil, isWorm
end

-- OreNode_Ruby1 / WormNode_Iron1 (Ore_Model / SessionOreModel).
function S.parseOreModelType(modelName)
    return S.mapOreTypeString(modelName)
end

-- SessionOreType = "Coal" / "WormIron" / "Ruby" / ...
function S.parseSessionOreType(sessionType)
    return S.mapOreTypeString(sessionType)
end

function S.getOreSessionType(node)
    if not node then
        return nil
    end
    local st = node:GetAttribute("SessionOreType")
    if type(st) == "string" and st ~= "" then
        return st
    end
    return nil
end

-- Visible rock/gem. Health can read 0 before it replicates; the stone is still there.
function S.oreBodyStillPresent(ore)
    if not ore or not ore.Parent then
        return false
    end
    local function alive(part)
        return part and part:IsA("BasePart") and part.Transparency < 0.98
    end
    if alive(ore:FindFirstChild("Rock")) or alive(ore:FindFirstChild("Ore")) then
        return true
    end
    for _, child in ipairs(ore:GetChildren()) do
        if (child.Name == "Rock" or child.Name == "Ore") and alive(child) then
            return true
        end
    end
    return false
end

-- True while the socket still has a live ore to break (ESP/farm both use this).
-- Do NOT treat Health <= 0 as broken while the rock mesh is still in the world.
function S.isOreStillMineable(ore)
    if not ore or not ore.Parent then
        return false
    end
    local body = S.oreBodyStillPresent(ore)
    local health = ore:FindFirstChild("Health")
    local hp = nil
    if health and (health:IsA("NumberValue") or health:IsA("IntValue")) then
        hp = health.Value
    end
    if body then
        return true
    end
    if hp ~= nil and hp > 0 then
        return true
    end
    if hp ~= nil and hp <= 0 then
        return false
    end
    if ore:GetAttribute("OreLoaded") == false then
        return false
    end
    if not S.getOreSessionType(ore) and not S.getOreSessionModel(ore) then
        return false
    end
    return false
end

function S.getOreSessionModel(node)
    if not node then
        return nil
    end
    local sm = node:GetAttribute("SessionOreModel")
    if type(sm) == "string" and sm ~= "" then
        return sm
    end
    local om = node:GetAttribute("Ore_Model")
    if type(om) == "string" and om ~= "" then
        return om
    end
    return nil
end

-- Canonical: SessionOreType / SessionOreModel / Ore_Model on mineable ores.
function S.looksLikeOreNode(node)
    if not node or not node.Parent then
        return false
    end
    local n = node.Name
    local lower = string.lower(n)
    if n == "Nodes" or n == "Props" or n == "Structure" or n == "Dirt" or n == "Ores" then
        return false
    end
    -- Only Node_* spawn pads (Node_Enemy). Do NOT match Ore_NodeDirt.
    if lower:sub(1, 5) == "node_" then
        return false
    end

    if S.getOreSessionType(node) then
        return true
    end
    if S.getOreSessionModel(node) then
        return true
    end
    if CollectionService:HasTag(node, "Ore") then
        return true
    end
    if S.isOreNodeName(n) and (node:FindFirstChild("Rock") or node:FindFirstChild("Ore") or node:FindFirstChild("Health")) then
        return true
    end
    return false
end

function S.getOreEspAdornee(ore)
    if not ore then
        return nil
    end
    local gem = ore:FindFirstChild("Ore")
    if gem and gem:IsA("BasePart") then
        return gem
    end
    for _, desc in ipairs(ore:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name == "Ore" then
            return desc
        end
    end
    local rock = ore:FindFirstChild("Rock")
    if rock and rock:IsA("BasePart") then
        return rock
    end
    if ore:IsA("BasePart") then
        return ore
    end
    local ok, part = pcall(function()
        return ore:FindFirstChildWhichIsA("BasePart", true)
    end)
    return ok and part or nil
end

-- Worm* SessionOreType / WormNode_* model only — don't skip normal Emerald just because a DeathWorm mesh is parented nearby.
function S.oreHasDeathWorm(ore)
    if not ore then
        return false
    end
    local sessionType = S.getOreSessionType(ore)
    if type(sessionType) == "string" then
        if sessionType:sub(1, 4) == "Worm" or string.lower(sessionType):sub(1, 4) == "worm" then
            return true
        end
    end
    local model = S.getOreSessionModel(ore)
    if type(model) == "string" and (model:match("^WormNode_") or string.lower(model):match("^wormnode_")) then
        return true
    end
    return false
end

function S.resolveOreTypeKey(ore)
    if not ore then
        return nil
    end

    -- Primary: SessionOreType (Coal / WormIron / Ruby / ...)
    local fromSession = S.parseSessionOreType(S.getOreSessionType(ore))
    if fromSession then
        return fromSession
    end

    -- SessionOreModel / Ore_Model (WormNode_Iron1 / OreNode_Coal1)
    local fromModel = S.parseOreModelType(S.getOreSessionModel(ore))
    if fromModel then
        return fromModel
    end

    return nil
end

function S.getOreTypeName(ore)
    return S.resolveOreTypeKey(ore)
        or S.getOreSessionType(ore)
        or S.getOreSessionModel(ore)
        or (ore and ore.Name)
        or ""
end

function S.getOreEspColor(ore)
    local key = S.resolveOreTypeKey(ore)
    if key and ORE_TYPE_COLORS[key] then
        return ORE_TYPE_COLORS[key].esp
    end
    return ESP_COLORS.ore
end

function S.oreMatchesAutofarmSelection(ore)
    local selected = S.getAutofarmActiveOreTypes()
    if type(selected) ~= "table" or #selected == 0 then
        return false
    end

    if not S.isOreStillMineable(ore) then
        return false
    end

    if S.oreHasDeathWorm(ore) and not Autofarm.breakDeathWormOres then
        return false
    end

    -- Prefer SessionOreType (Coal / WormIron / Ruby...) then model fallback.
    local typeKey = S.parseSessionOreType(S.getOreSessionType(ore))
        or S.resolveOreTypeKey(ore)
    local oreRaw = string.lower(tostring(typeKey or S.getOreSessionType(ore) or ""))
    local oreBase = S.normalizeOreBaseName(oreRaw)
    if oreBase == "" then
        return false
    end

    for _, sel in ipairs(selected) do
        if type(sel) == "table" then
            sel = sel[1] or sel.Name or sel.CurrentOption
        end
        local keyRaw = string.lower(tostring(sel or ""))
        local keyBase = S.normalizeOreBaseName(keyRaw)
        if keyBase ~= "" then
            if oreBase == keyBase
                or oreRaw == keyRaw
                or oreRaw:find(keyBase, 1, true)
                or keyRaw:find(oreBase, 1, true)
                or (keyBase == "copper" and (oreBase == "iron" or oreBase == "wormiron"))
                or (keyBase == "iron" and oreBase == "copper")
            then
                return true
            end
        end
    end
    return false
end

-- Name match: Ore_NodeDirt, Ore_NodeMineshaft, OreNode_Gold1, WormNode_Gold1, etc.
function S.isOreNodeInstanceName(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local n = string.lower(name)
    return n:find("ore_node", 1, true) ~= nil
        or n:find("orenode", 1, true) ~= nil
        or n:find("worm_node", 1, true) ~= nil
        or n:find("wormnode", 1, true) ~= nil
end

-- Farm + ESP: Workspace ore sockets (Ore_Node* / OreNode* / WormNode*) + tagged Ore.
function S.forEachWorldOreNode(callback)
    local seen = {}

    local function emit(node)
        if not node or seen[node] then
            return
        end
        local okParent, parent = pcall(function()
            return node.Parent
        end)
        if not okParent or not parent then
            return
        end

        local name = ""
        pcall(function()
            name = tostring(node.Name or "")
        end)

        local sessionType = nil
        pcall(function()
            sessionType = node:GetAttribute("SessionOreType")
        end)
        local hasSession = type(sessionType) == "string" and sessionType ~= ""

        local tagged = false
        pcall(function()
            tagged = CollectionService:HasTag(node, "Ore") == true
        end)

        local nameOk = S.isOreNodeInstanceName(name)
        if not nameOk and not tagged and not hasSession then
            return
        end
        -- Skip empty sockets / enemy pads.
        if not hasSession then
            local model = nil
            pcall(function()
                model = node:GetAttribute("SessionOreModel") or node:GetAttribute("Ore_Model")
            end)
            if type(model) ~= "string" or model == "" then
                if not tagged then
                    return
                end
            end
        end

        seen[node] = true
        pcall(callback, node)
    end

    local function visit(container, depth)
        if not container or depth > 18 then
            return
        end
        local children = nil
        local ok = pcall(function()
            children = container:GetChildren()
        end)
        if not ok or type(children) ~= "table" then
            return
        end
        for _, child in ipairs(children) do
            if not child then
                continue
            end
            local cname = ""
            pcall(function()
                cname = tostring(child.Name or "")
            end)
            if S.isOreNodeInstanceName(cname) then
                emit(child)
            end
            if cname == "Ores" or cname == "Nodes" or cname == "Dirt" or cname == "Props" then
                local nestedKids = nil
                pcall(function()
                    nestedKids = child:GetChildren()
                end)
                if type(nestedKids) == "table" then
                    for _, nested in ipairs(nestedKids) do
                        if nested and S.isOreNodeInstanceName(nested.Name) then
                            emit(nested)
                        elseif nested and (nested:IsA("Folder") or nested:IsA("Model")) then
                            visit(nested, depth + 1)
                        end
                    end
                end
            elseif depth < 18 then
                local isContainer = false
                pcall(function()
                    isContainer = child:IsA("Folder") or child:IsA("Model")
                end)
                if isContainer then
                    visit(child, depth + 1)
                end
            end
        end
    end

    pcall(function()
        for _, ore in ipairs(CollectionService:GetTagged("Ore")) do
            emit(ore)
        end
    end)

    pcall(function()
        visit(Workspace, 0)
    end)
end

function S.debugNearbyOres(range)
    range = range or 120
    local root = S.getRoot()
    if not root then
        S.notify("Ore Debug", "No character", 3)
        return
    end

    local lines = {}
    local count = 0
    S.forEachWorldOreNode(function(ore)
        local pos = S.getOreWorldPosition(ore)
        if not pos or (pos - root.Position).Magnitude > range then
            return
        end
        count += 1
        if #lines < 12 then
            local dist = math.floor((pos - root.Position).Magnitude + 0.5)
            local session = ore:GetAttribute("SessionOreType") or "?"
            table.insert(lines, string.format("%s %dm", tostring(session), dist))
        end
    end)

    local msg = string.format("%d Ore_Node nearby\n%s", count, table.concat(lines, " | "))
    S.notify("Ore Debug", msg, 8)
    print("[JPAX Ore Debug]", msg)
    return count, lines
end

function S.isArmorWorldItem(item)
    if not item then
        return false
    end
    if item:GetAttribute("Armor") ~= nil or item:GetAttribute("ArmorType") ~= nil then
        return true
    end
    local cat = S.itemCategoryKey(item)
    local class = string.lower(tostring(item:GetAttribute("Class") or ""))
    if cat == "armor" or class == "armor" then
        return true
    end
    -- Junk with armor-ish names ("Old Boot" is UI category Scrap) is NOT armor.
    if cat ~= "" and cat ~= "armor" then
        return false
    end
    if class ~= "" and class ~= "armor" then
        return false
    end
    local name = string.lower(item.Name or "")
    -- Armor piece names (Reaper Chest, Void_Helmet…). Skip chest crates.
    if CollectionService:HasTag(item, "Interactive") and item:FindFirstChildWhichIsA("ProximityPrompt", true) then
        return false
    end
    if name:find("helmet", 1, true)
        or name:find("boot", 1, true)
        or name:find("torso", 1, true)
        or name:find("vest", 1, true)
        or name:find("_legs", 1, true)
        or name:find("legs_", 1, true)
        or (name:find("chest", 1, true) and not name:find("chestnode", 1, true))
    then
        return true
    end
    return false
end

function S.isSwordWorldItem(item)
    if not item then
        return false
    end
    if S.isPickaxeWorldItem(item) then
        return false
    end
    local class = string.lower(tostring(item:GetAttribute("Class") or ""))
    local name = string.lower(item.Name or "")
    local display = string.lower(tostring(item:GetAttribute("DisplayName") or ""))
    local cat = S.itemCategoryKey(item)
    if class == "pickaxe" or cat == "pickaxe" or cat == "scrap" or cat == "fuel" or cat == "ore" then
        return false
    end
    if class == "sword" or cat == "sword" or cat == "melee" then
        return true
    end
    return S.looksLikeSwordName(S.normalizeGearToken(name .. display))
end

function S.isPickaxeWorldItem(item)
    if not item then
        return false
    end
    local class = string.lower(tostring(item:GetAttribute("Class") or ""))
    local name = string.lower(item.Name or "")
    local display = string.lower(tostring(item:GetAttribute("DisplayName") or ""))
    local cat = S.itemCategoryKey(item)
    if class == "pickaxe" or cat == "pickaxe" then
        return true
    end
    if name:find("pickaxe", 1, true) or display:find("pickaxe", 1, true) then
        return true
    end
    -- Game UI often uses Category "Tool" for pickaxes (Pickaxe_Void, etc).
    if (cat == "tool" or class == "tool") and (
        name:find("pick", 1, true) or display:find("pick", 1, true)
            or name:find("picareta", 1, true)
    ) then
        return true
    end
    -- Ranked names even without the word pickaxe in odd renames.
    if S.getPickaxeRank(item.Name) > 0 then
        return true
    end
    return false
end

function S.isGunWorldItem(item)
    if not item then
        return false
    end
    local class = string.lower(tostring(item:GetAttribute("Class") or ""))
    local name = string.lower(item.Name or "")
    local display = string.lower(tostring(item:GetAttribute("DisplayName") or ""))
    local cat = S.itemCategoryKey(item)
    -- Ammo boxes share gun names (Revolver_Ammo, Rifle_Ammo): never treat as a gun.
    if name:find("ammo", 1, true) or display:find("ammo", 1, true)
        or class == "ammo" or cat == "ammo" then
        return false
    end
    if class == "pickaxe" or class == "sword" or class == "armor"
        or cat == "pickaxe" or cat == "sword" or cat == "armor" or cat == "scrap" then
        return false
    end
    if S.isPickaxeWorldItem(item) or S.isSwordWorldItem(item) then
        return false
    end
    if class == "gun" or cat == "gun" or cat == "ranged"
        or cat == "primary weapon" or cat == "secondary weapon" then
        return true
    end
    if item:GetAttribute("Ammo") ~= nil then
        return true
    end
    local label = name .. display
    return label:find("rifle", 1, true) ~= nil
        or label:find("shotgun", 1, true) ~= nil
        or label:find("revolver", 1, true) ~= nil
        or label:find("pistol", 1, true) ~= nil
        or label:find("blackhole", 1, true) ~= nil
        or label:find("rpg", 1, true) ~= nil
end

-- Gun ranking (higher = better). Priority order:
--   Phoenix (primary AND secondary)  >  Black Hole Gun  >  Void  >  game rarity  >  name fallback.
-- Phoenix/Void are read from the name / display name / rarity text FIRST, so they always
-- beat a plain rarity tier (Rare/Epic/Legendary...) whatever Rarity the game stamps on them.
S.GUN_TOP_KEYS = {
    { key = "phoenix", rank = 200 },
    { key = "blackhole", rank = 170 },
    { key = "void", rank = 150 },
}
-- Auto equip senjata HANYA mengambil Phoenix, Black Hole Gun, atau Void (rank >= ini).
S.GUN_MIN_EQUIP_RANK = 150
S.GUN_RARITY_KEYS = {
    { key = "common", rank = 10 },
    { key = "uncommon", rank = 20 },
    { key = "rare", rank = 30 },
    { key = "epic", rank = 40 },
    { key = "legendary", rank = 50 },
    { key = "mythic", rank = 60 },
    { key = "special", rank = 60 },
}
S.GUN_NAME_FALLBACK = {
    { key = "blackhole", rank = 60 },
    { key = "rpg", rank = 50 },
    { key = "web", rank = 35 },
}

function S.getGunRank(item)
    if not item then
        return 0
    end
    local tokenName = S.normalizeGearToken(item.Name or "")
    local tokenDisplay = S.normalizeGearToken(item:GetAttribute("DisplayName") or "")
    local tokens = { tokenName, tokenDisplay }
    for _, attr in ipairs({ "Rarity", "DisplayCategory", "Category", "Class", "Type", "ItemName", "ItemId" }) do
        local raw = item:GetAttribute(attr)
        if raw ~= nil and tostring(raw) ~= "" then
            table.insert(tokens, (S.normalizeGearToken(raw)))
        end
    end

    -- 1) Phoenix first, then Void.
    for _, entry in ipairs(S.GUN_TOP_KEYS) do
        for _, token in ipairs(tokens) do
            if token:find(entry.key, 1, true) then
                return entry.rank
            end
        end
    end

    -- 2) Game rarity, 3) name fallback. Take the best of both (rarity no longer hides the name).
    local best = 0
    for _, entry in ipairs(S.GUN_RARITY_KEYS) do
        local k = entry.key
        for _, token in ipairs(tokens) do
            if token:sub(1, #k) == k then
                best = math.max(best, entry.rank)
                break
            end
        end
    end
    for _, entry in ipairs(S.GUN_NAME_FALLBACK) do
        if tokenName:find(entry.key, 1, true) or tokenDisplay:find(entry.key, 1, true) then
            best = math.max(best, entry.rank)
        end
    end
    return best
end

-- Pistol/revolver = secondary slot. Rifle/shotgun/others = primary slot.
function S.getGunSlot(item)
    if not item then
        return "primary"
    end
    local cat = S.itemCategoryKey(item)
    if cat == "secondary weapon" then
        return "secondary"
    end
    if cat == "primary weapon" then
        return "primary"
    end
    local label = string.lower(tostring(item.Name or "") .. " " .. tostring(item:GetAttribute("DisplayName") or ""))
    if label:find("revolver", 1, true) or label:find("pistol", 1, true) then
        return "secondary"
    end
    return "primary"
end

function S.getGearSlotKey(item, category)
    if category == "Armor" then
        return S.getArmorSlotKey(item)
    end
    if category == "Gun" then
        return "Gun:" .. S.getGunSlot(item)
    end
    return category
end

function S.getGearItemCategory(item)
    if S.isPickaxeWorldItem(item) then
        return "Pickaxe"
    end
    if S.isSwordWorldItem(item) then
        return "Sword"
    end
    if S.isArmorWorldItem(item) then
        return "Armor"
    end
    if S.isGunWorldItem(item) then
        return "Gun"
    end
    return nil
end

function S.gearCategoryEnabled(category)
    if not GearEquip.enabled or type(GearEquip.categories) ~= "table" then
        return false
    end
    for _, selected in ipairs(GearEquip.categories) do
        if selected == category then
            return true
        end
    end
    return false
end

function S.normalizeGearToken(name)
    return string.lower(tostring(name or "")):gsub("[^%a%d]", "")
end

function S.tierFromKeys(token, keys)
    local best = 0
    for _, entry in ipairs(keys) do
        if token:find(entry.key, 1, true) and entry.rank > best then
            best = entry.rank
        end
    end
    return best
end

function S.looksLikeSwordName(token)
    return token:find("sword", 1, true)
        or token:find("excalibur", 1, true)
        or token:find("katana", 1, true)
        or token:find("kingslayer", 1, true)
        or token:find("executioner", 1, true)
        or token:find("samurai", 1, true)
end

function S.getOrderedGearRank(name, orderList)
    name = tostring(name or "")
    for i, ordered in ipairs(orderList) do
        if ordered == name then
            return (#orderList - i) + 1
        end
    end
    return 0
end

function S.getPickaxeRank(name)
    local token = S.normalizeGearToken(name)
    if not token:find("pick", 1, true) and not token:find("picareta", 1, true) then
        return 0
    end
    return S.tierFromKeys(token, PICKAXE_TIER_KEYS)
end

function S.getSwordRank(name)
    local token = S.normalizeGearToken(name)
    if not S.looksLikeSwordName(token) then
        return 0
    end
    return S.tierFromKeys(token, SWORD_TIER_KEYS)
end

function S.getArmorMaterialRank(name)
    return S.tierFromKeys(S.normalizeGearToken(name), ARMOR_TIER_KEYS)
end

function S.armorLabel(item)
    if not item then
        return ""
    end
    local bits = { tostring(item.Name or ""), tostring(item:GetAttribute("DisplayName") or "") }
    for _, key in ipairs({
        "ArmorType",
        "Material",
        "ArmorMaterial",
        "Set",
        "ArmorSet",
        "Skin",
        "Tier",
        "ArmorName",
        "ItemId",
    }) do
        local value = item:GetAttribute(key)
        if typeof(value) == "string" then
            table.insert(bits, value)
        end
    end
    pcall(function()
        for _, child in ipairs(item:GetChildren()) do
            table.insert(bits, child.Name)
            local display = child:GetAttribute("DisplayName")
            if typeof(display) == "string" then
                table.insert(bits, display)
            end
        end
    end)
    return table.concat(bits, " ")
end

function S.getArmorSlotKey(item)
    if not item then
        return "Chest"
    end
    local armorType = item:GetAttribute("ArmorType")
    local t = typeof(armorType) == "string" and armorType or ""
    local name = string.lower(S.armorLabel(item))
    local tl = string.lower(t)
    local acc = ""
    pcall(function()
        if item:IsA("Accessory") then
            acc = string.lower(tostring(item.AccessoryType))
        end
    end)
    -- Game maps Head→Helmet, Torso→Chest, Leg→Legs, Boot→Boots.
    if tl == "head" or tl == "helmet" or acc:find("hat", 1, true) or name:find("helmet", 1, true) or name:find("hat", 1, true) then
        return "Helmet"
    end
    if tl == "boots" or tl == "boot" or tl == "feet" or tl == "foot" or name:find("boot", 1, true) then
        return "Boots"
    end
    if tl == "legs" or tl == "leg" or name:find("legs", 1, true) or name:find("pants", 1, true) then
        return "Legs"
    end
    if tl == "torso" or tl == "chest" or name:find("chest", 1, true) or name:find("torso", 1, true) or name:find("vest", 1, true) then
        return "Chest"
    end
        if tl == "helmet" or tl == "chest" or tl == "legs" or tl == "boots" then
            return t
    end
    return "Chest"
end

-- Tier dominates damage so a weak listed sword cannot beat a stronger tier
-- just because ToolDamage spiked, and an equipped rename cannot fall back to 0.
function S.getWorldGearScore(item)
    if not item then
        return -1
    end
    local category = S.getGearItemCategory(item)
    local dmg = math.clamp(tonumber(S.getToolDamage(item)) or 0, 0, 50000)
    local label = tostring(item.Name or "") .. tostring(item:GetAttribute("DisplayName") or "")

    if category == "Pickaxe" then
        local rank = S.tierFromKeys(S.normalizeGearToken(label), PICKAXE_TIER_KEYS)
        if rank > 0 then
            return rank * 100000 + dmg
        end
        return dmg
    end
    if category == "Sword" then
        local rank = S.getSwordRank(label)
        if rank > 0 then
            return rank * 100000 + dmg
        end
        return dmg
    end
    if category == "Gun" then
        local rank = S.getGunRank(item)
        if rank > 0 then
            return rank * 100000 + dmg
        end
        return dmg
    end
    if category == "Armor" then
        local armorHp = item:GetAttribute("Armor")
        local defense = item:GetAttribute("Defense")
        local value = item:GetAttribute("Value")
        -- Worn pieces are Accessories. The material lives in ArmorName
        -- (Void_Helmet), not in the instance Name.
        local mat = S.getArmorMaterialRank(S.armorLabel(item))
        local hp = 0
        if typeof(armorHp) == "number" then
            hp = armorHp
        elseif typeof(defense) == "number" then
            hp = defense
        elseif typeof(value) == "number" then
            hp = value
        end
        if mat > 0 then
            return mat * 100000 + math.clamp(hp, 0, 50000)
        end
        return math.clamp(hp, 0, 50000)
    end
    return -1
end

function S.getEquippedArmorPiece(slotKey)
    local char = LocalPlayer.Character
    if not char or not slotKey then
        return nil
    end
    local best, bestScore = nil, -1
    local function consider(child)
        if not child or child == char then
            return
        end
        local armorName = child:GetAttribute("ArmorName")
        local hasArmor = typeof(armorName) == "string"
            or child:GetAttribute("ArmorType") ~= nil
            or child:GetAttribute("Armor") ~= nil
            or child:GetAttribute("ArmorIcon") ~= nil
        if not hasArmor and not S.isArmorWorldItem(child) then
            return
        end
        if S.getArmorSlotKey(child) ~= slotKey then
            return
        end
        local score = S.getWorldGearScore(child)
        if score > bestScore then
            bestScore = score
            best = child
        end
    end
    for _, child in ipairs(char:GetChildren()) do
        consider(child)
    end
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("Accessory") then
            consider(desc)
        end
    end
    return best
end

function S.rememberWornArmor()
    for _, slot in ipairs({ "Helmet", "Chest", "Legs", "Boots" }) do
        local piece = S.getEquippedArmorPiece(slot)
        if not piece then
            continue
        end
        local score = S.getWorldGearScore(piece)
        if score < 0 then
            continue
        end
        GearEquip.slotBest[slot] = {
            score = score,
            name = tostring(piece:GetAttribute("ArmorName") or piece.Name),
            at = tick(),
        }
    end
end

function S.getEquippedArmorScore(armorType)
    local slot = nil
    if armorType then
        slot = S.getArmorSlotKey({
            Name = tostring(armorType),
            GetAttribute = function(_, key)
                if key == "ArmorType" then
                    return armorType
                end
                return nil
            end,
        })
    end
    if not slot then
        return -1
    end
    local piece = S.getEquippedArmorPiece(slot)
    if not piece then
        return -1
    end
    return S.getWorldGearScore(piece)
end

function S.bestOwnedToolScore(kind, gunSlot)
    local best = -1
    local function scan(container)
        if not container then
            return
        end
        for _, child in ipairs(container:GetChildren()) do
            if not child:IsA("Tool") then
                continue
            end
            local match = (kind == "Pickaxe" and S.isPickaxeWorldItem(child))
                or (kind == "Sword" and S.isSwordWorldItem(child))
                or (kind == "Gun" and S.isGunWorldItem(child)
                    and (not gunSlot or S.getGunSlot(child) == gunSlot))
            if match then
                best = math.max(best, S.getWorldGearScore(child))
            end
        end
    end
    scan(LocalPlayer.Character)
    scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
    return best
end

function S.getCurrentGearScore(category, worldItem)
    if category == "Pickaxe" or category == "Sword" then
        return S.bestOwnedToolScore(category)
    end
    if category == "Gun" then
        local gunSlot = S.getGunSlot(worldItem)
        local owned = S.bestOwnedToolScore("Gun", gunSlot)
        local remembered = GearEquip.slotBest["Gun:" .. gunSlot]
        if remembered and typeof(remembered.score) == "number" then
            local window = owned >= 0 and 120 or 12
            if tick() - (remembered.at or 0) < window then
                owned = math.max(owned, remembered.score)
            else
                GearEquip.slotBest["Gun:" .. gunSlot] = nil
            end
        end
        return owned
    end
    if category == "Armor" then
        local slot = S.getArmorSlotKey(worldItem)
        local piece = S.getEquippedArmorPiece(slot)
        local equipped = piece and S.getWorldGearScore(piece) or -1
        local remembered = GearEquip.slotBest[slot]
        if remembered and typeof(remembered.score) == "number" then
            local fresh = piece ~= nil or (tick() - (remembered.at or 0) < 12)
            if fresh then
                equipped = math.max(equipped, remembered.score)
            else
                GearEquip.slotBest[slot] = nil
            end
        end
        return equipped
    end
    return -1
end

-- Weapon (pickaxe / sword / primary gun / secondary gun) tidak boleh double.
-- Pengecualian: weapon Phoenix boleh double (maksimal 2 Phoenix per slot).
function S.isWeaponCategory(category)
    return category == "Pickaxe" or category == "Sword" or category == "Gun"
end

function S.countOwnedPhoenix(category, item)
    local n = 0
    for _, t in ipairs(S.ownedToolList()) do
        if S.isPhoenixTool(t) and S.getGearItemCategory(t) == category
            and (category ~= "Gun" or S.getGunSlot(t) == S.getGunSlot(item)) then
            n += 1
        end
    end
    return n
end

function S.isPhoenixDoubleAllowed(item, category)
    return S.isWeaponCategory(category)
        and S.isPhoenixTool(item)
        and S.countOwnedPhoenix(category, item) < 2
end

-- Equip only when upgrade is strictly better (Phoenix boleh double). Equal/worse → tidak diambil.
-- Skip ShopItem ([$] marked) — those cannot be equipped from the world.
function S.shouldAutoEquipWorldItem(item)
    if not GearEquip.enabled or not item or not item.Parent then
        return false
    end
    if CollectionService:HasTag(item, "ShopItem") then
        return false
    end
    if S.isHardExcluded(item) then
        return false
    end
    local category = S.getGearItemCategory(item)
    if not category or not S.gearCategoryEnabled(category) then
        return false
    end

    -- Senjata: hanya Phoenix > Black Hole Gun > Void yang boleh di-equip.
    if category == "Gun" then
        local label = string.lower(tostring(item.Name or "") .. " " .. tostring(item:GetAttribute("DisplayName") or ""))
        if label:find("rpg", 1, true) then
            return false -- RPG tidak pernah di-equip oleh Auto Equip Best
        end
        if S.getGunRank(item) < S.GUN_MIN_EQUIP_RANK then
            return false
        end
    end

    if S.isPhoenixDoubleAllowed(item, category) then
        return true
    end

    local score = S.getWorldGearScore(item)
    local current = S.getCurrentGearScore(category, item)
    return score > current
end

function S.getGearCompareDelta(item)
    local category = S.getGearItemCategory(item)
    if not category then
        return nil
    end
    local score = S.getWorldGearScore(item)
    local current = S.getCurrentGearScore(category, item)
    return score - current, score, current, category
end

-- Owned tools (hotbar + held).
function S.ownedToolList()
    local list = {}
    for _, container in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }) do
        if container then
            for _, c in ipairs(container:GetChildren()) do
                if c:IsA("Tool") then
                    table.insert(list, c)
                end
            end
        end
    end
    return list
end

-- The weakest owned gun in the same slot (primary / secondary) as the world gun.
function S.findGunToReplace(worldItem)
    local slot = S.getGunSlot(worldItem)
    local worst, worstScore
    for _, tool in ipairs(S.ownedToolList()) do
        if S.isGunWorldItem(tool) and S.getGunSlot(tool) == slot then
            local sc = S.getWorldGearScore(tool)
            if not worst or sc < worstScore then
                worst, worstScore = tool, sc
            end
        end
    end
    return worst
end

function S.equipWorldGearItem(item)
    if not item or not item.Parent then
        return false
    end
    if CollectionService:HasTag(item, "ShopItem") then
        return false
    end

    local category = S.getGearItemCategory(item)
    local slot = S.getGearSlotKey(item, category)
    if slot and GearEquip.triedAt[slot] and tick() - GearEquip.triedAt[slot] < 2.2 then
        return false
    end
    local score = S.getWorldGearScore(item)
    local current = S.getCurrentGearScore(category, item)
    if score <= current and not S.isPhoenixDoubleAllowed(item, category) then
        return false
    end
    local itemName = item.Name
    local itemsFolder = Workspace:FindFirstChild("Items")
    local stillWorld = itemsFolder and item:IsDescendantOf(itemsFolder)

    -- Interact range is short. Bring the ITEM in — never move the player.
    -- DragController is what stuck the character in the air, so it stays off.
    local root = S.getRoot()
    local pos = S.getItemPosition(item)
    if root and pos then
        local dist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
        if dist > GEAR_EQUIP_MAX_STUDS then
            return false
        end
        if dist > 12 then
            S.bringItemToPlayer(item)
        task.wait(0.05)
    end
    end
    if slot then
        GearEquip.triedAt[slot] = tick()
    end

    -- Guns: hold the weaker gun of the same slot first so the pickup swaps it out
    -- (this is the gun that is "in use"), then drop it afterwards if the game keeps it.
    local replacedGun, prevHeld, toolsBefore = nil, nil, {}
    for _, t in ipairs(S.ownedToolList()) do
        toolsBefore[t] = true
    end
    if category == "Gun" then
        prevHeld = S.getEquippedTool()
        replacedGun = S.findGunToReplace(item)
        if replacedGun and replacedGun.Parent and replacedGun.Parent ~= LocalPlayer.Character then
            pcall(S.callEquipTool, replacedGun)
            task.wait(0.15)
        end
    end

    local ok = false
    if Services.InteractionService then
        ok = pcall(function()
            Services.InteractionService:Interact(item)
        end) or ok
        task.wait(0.08)
        ok = pcall(function()
            Services.InteractionService:Interact(item)
        end) or ok
    end

    if category ~= "Armor" and item:IsA("Tool") and Services.ToolService then
        S.callEquipTool(item)
        ok = true
    end

    -- Guns: only count it as equipped if the new gun really reached the inventory
    -- (otherwise a failed attempt would be remembered as success and block retries).
    if category == "Gun" then
        task.wait(0.25)
        local arrived = false
        for _, t in ipairs(S.ownedToolList()) do
            if not toolsBefore[t] and S.isGunWorldItem(t)
                and S.getGunSlot(t) == S.getGunSlot(item)
                and S.getWorldGearScore(t) >= score then
                arrived = true
                break
            end
        end
        if not arrived and stillWorld and (not item.Parent or not itemsFolder or not item:IsDescendantOf(itemsFolder)) then
            -- item left the world: the game swapped it in place (same Tool instance reused)
            for _, t in ipairs(S.ownedToolList()) do
                if S.isGunWorldItem(t) and S.getGunSlot(t) == S.getGunSlot(item)
                    and S.getWorldGearScore(t) >= score then
                    arrived = true
                    break
                end
            end
        end
        if arrived and replacedGun and replacedGun.Parent
            and S.getWorldGearScore(replacedGun) < score
            and type(S.shardDropTool) == "function" then
            pcall(S.shardDropTool, replacedGun)
        end
        if prevHeld and prevHeld.Parent and not S.isGunWorldItem(prevHeld) then
            pcall(S.callEquipTool, prevHeld)
        end
        ok = arrived
    end

    -- Pickaxe / Sword: setelah update item tidak lagi saling mengganti, jadi buang yang lama
    -- (non-Phoenix) supaya tidak double. Weapon Phoenix tidak pernah di-drop.
    if category == "Pickaxe" or category == "Sword" then
        local function sameKind(t)
            return (category == "Pickaxe" and S.isPickaxeWorldItem(t))
                or (category == "Sword" and S.isSwordWorldItem(t))
        end
        task.wait(0.25)
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local newTool
        for _, t in ipairs(S.ownedToolList()) do
            if sameKind(t) and not toolsBefore[t] and S.getWorldGearScore(t) >= score then
                newTool = t
                break
            end
        end
        if not newTool and item.Parent
            and (item.Parent == LocalPlayer.Character or item.Parent == backpack) then
            newTool = item
        end
        if newTool and not S.isPhoenixTool(newTool) and type(S.shardDropTool) == "function" then
            for _, t in ipairs(S.ownedToolList()) do
                if t ~= newTool and sameKind(t) and not S.isPhoenixTool(t)
                    and S.getWorldGearScore(t) < score then
                    pcall(S.shardDropTool, t)
                    task.wait(0.2)
                end
            end
            if newTool.Parent then
                pcall(S.callEquipTool, newTool)
            end
        end
    end

    -- Confirm armor actually wore (item left world OR accessory appeared).
    if category == "Armor" then
        task.wait(0.12)
        local wore = false
        if stillWorld and (not item.Parent or not itemsFolder or not item:IsDescendantOf(itemsFolder)) then
            wore = true
        end
        local piece = S.getEquippedArmorPiece(slot)
        if piece then
            if S.getArmorMaterialRank(S.armorLabel(piece)) >= S.getArmorMaterialRank(itemName) then
                wore = true
            end
            if S.getWorldGearScore(piece) >= score then
                wore = true
            end
        end
        ok = wore
    end

    if ok and slot and typeof(score) == "number" then
        local prev = GearEquip.slotBest[slot]
        if not prev or score > (prev.score or -1) then
            GearEquip.slotBest[slot] = {
                score = score,
                name = itemName,
            at = tick(),
            }
        end
    end

    return ok
end

function S.runAutoEquipBestPass()
    if not GearEquip.enabled or GearEquip.busy then
        return 0
    end
    S.rememberWornArmor()
    if Autofarm.miningBusy then
        return 0
    end
    if type(GearEquip.categories) ~= "table" or #GearEquip.categories == 0 then
        return 0
    end
    local cooldown = (Autofarm.enabled and Autofarm.autoEquipBest) and 0.35 or 1.5
    if tick() - (GearEquip.lastPassAt or 0) < cooldown then
        return 0
    end

    GearEquip.busy = true
    GearEquip.lastPassAt = tick()
    local equippedCount = 0
    local root = S.getRoot()
    local range = GEAR_EQUIP_MAX_STUDS
    local bestBySlot = {}

    pcall(function()
        S.forEachWorldLootItem(function(item)
            if not S.shouldAutoEquipWorldItem(item) then
                return
            end
            -- Only real gear categories (game UI: Tool = pickaxe/sword, Armor = armor).
            local category = S.getGearItemCategory(item)
            if category ~= "Pickaxe" and category ~= "Sword" and category ~= "Armor" and category ~= "Gun" then
                return
            end
            local pos = S.getItemPosition(item)
            if not pos or not root then
                return
            end
            local dist = S.getFlatDistanceFromPosition(pos)
            if dist > range then
                return
            end
            local slot = S.getGearSlotKey(item, category)
            local score = S.getWorldGearScore(item)
            local cur = bestBySlot[slot]
            if not cur or score > cur.score then
                bestBySlot[slot] = { item = item, score = score }
            end
        end)

        for _, entry in pairs(bestBySlot) do
            if equippedCount >= 3 then
                break
            end
            if entry.item and S.shouldAutoEquipWorldItem(entry.item) then
                if S.equipWorldGearItem(entry.item) then
                    equippedCount += 1
                    task.wait(0.12)
                end
            end
        end
    end)

    GearEquip.busy = false
    return equippedCount
end

-- One toggle: Tools (Pickaxe + Sword) + Armor. Better equip; equal/worse → sack.
function S.setAutofarmEquipBest(enabled)
    Autofarm.autoEquipBest = enabled == true
    if not Autofarm.autoEquipBest then
        -- Only tear down if we own the gear loop for autofarm.
        if GearEquip._ownedByAutofarm then
            GearEquip._ownedByAutofarm = false
            S.setAutoEquipBestGear(false)
        end
        return
    end

    GearEquip.categories = { "Pickaxe", "Sword", "Armor", "Gun" }
    GearEquip.range = GEAR_EQUIP_MAX_STUDS
    GearEquip.triedAt = {}
    S.rememberWornArmor()
    GearEquip._ownedByAutofarm = true
    if not GearEquip.enabled then
        S.setAutoEquipBestGear(true)
    else
        GearEquip.enabled = true
    end
end

function S.setAutoEquipBestGear(enabled)
    GearEquip.enabled = enabled
    S.disconnectAll("autoEquipBestGear")
    if not enabled then
        GearEquip.triedAt = {}
        return
    end
    S.rememberWornArmor()

    local lastTick = 0
    State.connections.autoEquipBestGear = RunService.Heartbeat:Connect(function()
        if not GearEquip.enabled or GearEquip.busy or Autofarm.miningBusy then
            return
        end
        local gap = (Autofarm.enabled and Autofarm.autoEquipBest) and 0.4 or 2
        if tick() - lastTick < gap then
            return
        end
        lastTick = tick()
        task.spawn(function()
            pcall(S.runAutoEquipBestPass)
        end)
    end)
end

function S.isDecorativeOrShopChest(inst)
    if not inst then
        return true
    end

    local cur = inst
    while cur and cur ~= Workspace do
        local n = string.lower(cur.Name or "")
        if n == "coinshop"
            or n == "shop"
            or n == "sell_table"
            or n == "bountysell"
            or n == "sellparts"
            or n:find("coinshop", 1, true)
            or n:find("armory", 1, true)
            or n:find("blacksmith", 1, true)
        then
            return true
        end
        cur = cur.Parent
    end

    return false
end

function S.isVillageAncestor(inst)
    local cur = inst
    while cur and cur ~= Workspace do
        local n = string.lower(cur.Name or "")
        if n == "minertown"
            or n == "bountycamp"
            or n == "tradingcamptutorial"
            or n:match("^camptier")
            or n == "tradingpost"
            or n == "tradingpostmini"
            or n == "bounterhuntercamp"
            or n == "bountyhuntercamp"
            or n == "coinshop"
        then
            return true
        end

        -- Village models only — never treat whole Fortress as village ancestor
        -- (dungeon chests live under the same Fortress model).
        if cur:IsA("Model")
            and not cur.Name:find("Fortress", 1, true)
            and S.isVillageModel(cur)
        then
            return true
        end

        cur = cur.Parent
    end
    return false
end

function S.isPointInsidePart(part, point, pad)
    if not part or not point or not part:IsA("BasePart") then
        return false
    end
    pad = pad or 0
    local localPos = part.CFrame:PointToObjectSpace(point)
    local half = (part.Size + Vector3.new(pad, pad, pad)) * 0.5
    return math.abs(localPos.X) <= half.X
        and math.abs(localPos.Y) <= half.Y
        and math.abs(localPos.Z) <= half.Z
end

function S.isPointInsideBox(cf, size, point, pad)
    if not cf or not size or not point then
        return false
    end
    pad = pad or 0
    local localPos = cf:PointToObjectSpace(point)
    local half = (size + Vector3.new(pad, pad, pad)) * 0.5
    return math.abs(localPos.X) <= half.X
        and math.abs(localPos.Y) <= half.Y
        and math.abs(localPos.Z) <= half.Z
end

function S.getModelOrFolderBox(inst)
    if not inst then
        return nil, nil
    end
    if inst:IsA("Model") then
        local ok, cf, size = pcall(function()
            return inst:GetBoundingBox()
        end)
        if ok and cf and size then
            return cf, size
        end
    end

    local minV, maxV
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then
            local cf = d.CFrame
            local half = d.Size * 0.5
            local corners = {
                cf * Vector3.new( half.X,  half.Y,  half.Z),
                cf * Vector3.new( half.X,  half.Y, -half.Z),
                cf * Vector3.new( half.X, -half.Y,  half.Z),
                cf * Vector3.new( half.X, -half.Y, -half.Z),
                cf * Vector3.new(-half.X,  half.Y,  half.Z),
                cf * Vector3.new(-half.X,  half.Y, -half.Z),
                cf * Vector3.new(-half.X, -half.Y,  half.Z),
                cf * Vector3.new(-half.X, -half.Y, -half.Z),
            }
            for _, c in ipairs(corners) do
                if not minV then
                    minV = c
                    maxV = c
                else
                    minV = Vector3.new(math.min(minV.X, c.X), math.min(minV.Y, c.Y), math.min(minV.Z, c.Z))
                    maxV = Vector3.new(math.max(maxV.X, c.X), math.max(maxV.Y, c.Y), math.max(maxV.Z, c.Z))
                end
            end
        end
    end
    if not minV or not maxV then
        return nil, nil
    end
    local size = maxV - minV
    local cf = CFrame.new((minV + maxV) * 0.5)
    return cf, size
end

function S.collectVillageHitboxRegions()
    local now = os.clock()
    if State._villageHitboxCache and (now - (State._villageHitboxCacheAt or 0)) < 1.5 then
        return State._villageHitboxCache
    end

    local regions = {}

    local function addPart(part)
        if part and part:IsA("BasePart") then
            table.insert(regions, { kind = "part", part = part })
        end
    end

    local function addBox(inst, pad)
        local cf, size = S.getModelOrFolderBox(inst)
        if cf and size then
            table.insert(regions, { kind = "box", cf = cf, size = size, pad = pad or 12 })
        end
    end

    local function addVillageZones(root)
        if not root then
            return
        end

        -- Explicit hitbox parts if the game has them.
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("BasePart") then
                local n = string.lower(d.Name or "")
                if n == "hitbox"
                    or n == "villagehitbox"
                    or n == "camphitbox"
                    or n == "townhitbox"
                    or n == "safezone"
                then
                    addPart(d)
                end
            end
        end

        -- Fortress chests are ignored entirely — no need to build trade-zone boxes.
        if root.Name:find("Fortress", 1, true) then
            return
        end

        addBox(root, 16)
    end

    S.scanWorldModels(function(inst)
        if S.isVillageModel(inst) or string.lower(inst.Name or "") == "minertown" then
            addVillageZones(inst)
        end
    end)

    -- MinerTown / camps may sit as direct Workspace children without matching scan filters.
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") then
            local n = string.lower(child.Name or "")
            if n == "minertown" or n == "bountycamp" or n:match("^camptier") then
                addVillageZones(child)
            end
        end
    end

    State._villageHitboxCache = regions
    State._villageHitboxCacheAt = now
    return regions
end

function S.isPositionInVillageHitbox(pos)
    if not pos then
        return false
    end

    for _, region in ipairs(S.collectVillageHitboxRegions()) do
        if region.kind == "part" then
            if S.isPointInsidePart(region.part, pos, 4) then
                return true
            end
        elseif region.kind == "box" then
            if S.isPointInsideBox(region.cf, region.size, pos, region.pad or 12) then
                return true
            end
        end
    end

    return false
end

-- Fortress chests (CoinShop etc.) — always ignore.
function S.isChestInFortress(inst)
    local cur = inst
    while cur and cur ~= Workspace do
        local n = tostring(cur.Name or "")
        if n:find("Fortress", 1, true) or n == "Fortresses" or n == "CoinShop" then
            return true
        end
        cur = cur.Parent
    end
    return false
end

-- Boss loot: DungeonGate_*.Wave — always ignore.
function S.isChestInDungeonWave(inst)
    local cur = inst
    while cur and cur ~= Workspace do
        local n = tostring(cur.Name or "")
        if n == "Wave" or n:match("^Wave%d+$") then
            return true
        end
        cur = cur.Parent
    end
    return false
end

-- Arena ChestStep is NOT a chest (geometry only).
function S.isChestStepJunk(inst)
    if not inst then
        return true
    end
    local cur = inst
    while cur and cur ~= Workspace do
        if cur.Name == "ChestStep" then
            return true
        end
        cur = cur.Parent
    end
    return false
end

-- Under DungeonGate_*.Dungeon_* interior folder (not the gate model, not Wave).
function S.isUnderDungeonInteriorFolder(inst)
    if not inst then
        return false
    end
    local cur = inst
    while cur and cur ~= Workspace do
        local n = tostring(cur.Name or "")
        if not n:find("DungeonGate", 1, true) then
            if n:match("^Dungeon_") or n:find("Dungeon_Tier", 1, true) then
                return true
            end
        end
        cur = cur.Parent
    end
    return false
end

function S.chestHasProximityPrompt(inst)
    if not inst then
        return false
    end
    if inst:IsA("ProximityPrompt") then
        return inst.Enabled ~= false
    end
    for _, desc in ipairs(inst:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled ~= false then
            return true
        end
    end
    return false
end

-- Resolve MeshPart/Prompt → DiamondChest / CommonChest model (parent of Chest mesh).
function S.resolveDungeonChestModel(inst)
    if not inst then
        return nil
    end

    if inst:IsA("ProximityPrompt") then
        local parent = inst.Parent
        if parent then
            local model = parent:FindFirstAncestorOfClass("Model") or parent.Parent
            if model and model:IsA("Model") then
                inst = model
            end
        end
    elseif inst:IsA("BasePart") then
        -- Prefer model that owns this part (DiamondChest), not a distant ancestor.
        local model = inst.Parent
        if model and model:IsA("Model") and string.lower(model.Name):find("chest", 1, true) then
            inst = model
        else
            inst = inst:FindFirstAncestorOfClass("Model") or inst
        end
    end

    if not inst or not inst.Parent then
        return nil
    end

    -- Walk up a bit if we're on the Chest mesh / AnimController container.
    local n = string.lower(inst.Name or "")
    if n == "chest" and inst.Parent and inst.Parent:IsA("Model") then
        local pn = string.lower(inst.Parent.Name or "")
        if pn:find("chest", 1, true) then
            inst = inst.Parent
        end
    end

    return inst
end

-- Real openable dungeon chest:
--   ...Dungeon_Tier*.ChestNode.DiamondChest.Chest.ProximityPrompt
function S.isDungeonInteriorChest(inst)
    if not inst then
        return false
    end
    if S.isChestInFortress(inst) or S.isChestInDungeonWave(inst) or S.isChestStepJunk(inst) then
        return false
    end
    if not S.isUnderDungeonInteriorFolder(inst) then
        return false
    end

    local model = S.resolveDungeonChestModel(inst)
    if not model then
        return false
    end
    if S.isChestStepJunk(model) then
        return false
    end

    local name = string.lower(model.Name or "")
    if name == "cheststep" or name == "chestnode" or name == "chestnodes" then
        return false
    end
    if not name:find("chest", 1, true) then
        return false
    end

    -- Must have ProximityPrompt (Interact) — otherwise it is not a chest.
    if not S.chestHasProximityPrompt(model) then
        return false
    end

    -- Prefer ChestNode sockets; also allow direct dungeon children with prompt.
    local parent = model.Parent
    if parent and (parent.Name == "ChestNode" or parent.Name == "ChestNodes") then
        return true
    end
    if model:FindFirstChild("Chest", true) then
        return true
    end

    return S.chestHasProximityPrompt(model)
end

function S.isBossRoomChest(inst)
    return S.isChestInDungeonWave(inst) or S.isChestStepJunk(inst)
end

function S.isDungeonTreasureRoomChest(inst)
    return S.isDungeonInteriorChest(inst)
end

function S.getUnderStandPosition(worldPos, depth)
    if not worldPos then
        return nil
    end
    depth = depth or 10
    local under = Vector3.new(worldPos.X, worldPos.Y - depth, worldPos.Z)
    -- Mines go deep; isSaneOrePos (not the old Y<-100 world clamp).
    if typeof(S.isSaneOrePos) == "function" then
        if not S.isSaneOrePos(under) then
            return nil
        end
    elseif typeof(S.isSaneWorldPos) == "function" and not S.isSaneWorldPos(under) then
        return nil
    end
    return under
end

function S.isChestInVillage(inst)
    if not inst then
        return false
    end
    if S.isVillageAncestor(inst) then
        return true
    end
    local pos = S.getInstancePosition(inst) or S.getItemPosition(inst)
    return S.isPositionInVillageHitbox(pos)
end

function S.chestHasOpenMethod(inst)
    if not inst then
        return false
    end

    if CollectionService:HasTag(inst, "Interactive") then
        return true
    end

    for _, desc in ipairs(inst:GetDescendants()) do
        if CollectionService:HasTag(desc, "Interactive") then
            return true
        end
        if desc:IsA("ProximityPrompt") and desc.Enabled then
            local action = string.lower(desc.ActionText or "")
            local object = string.lower(desc.ObjectText or "")
            if action == "interact"
                or action:find("open", 1, true)
                or object:find("chest", 1, true)
            then
                return true
            end
        end
    end

    -- Dungeon spawn sockets — real loot chests (prompt may stream in late).
    local parent = inst.Parent
    if parent then
        if parent.Name == "ChestNode" then
            return true
        end
        if parent.Name == "ChestNodes" or (parent.Parent and parent.Parent.Name == "ChestNodes") then
            return true
        end
    end

    return false
end

function S.isTreasureChest(inst)
    if not inst or not inst.Parent then
        return false
    end
    if CollectionService:HasTag(inst, "SupplyCrate") then
        return false
    end
    if S.isArmorWorldItem(inst) then
        return false
    end
    if CollectionService:HasTag(inst, "ShopItem") then
        return false
    end
    if S.isDecorativeOrShopChest(inst) then
        return false
    end
    -- Any ChestNode chest is valid, except Wave / ChestStep.
    local model = S.resolveDungeonChestModel(inst) or inst
    if not S.isChestEspTarget(model) then
        return false
    end
    return S.chestHasProximityPrompt(model) or S.chestHasOpenMethod(model)
end

function S.markChestLocked(inst)
    if not inst then
        return
    end
    Autofarm.lockedChestSkip = Autofarm.lockedChestSkip or {}
    local untilTick = tick() + 120 -- skip ~2 min (boss lock or failed open)
    Autofarm.lockedChestSkip[inst] = untilTick
    local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
    if model then
        Autofarm.lockedChestSkip[model] = untilTick
    end
end

function S.isChestMarkedLocked(inst)
    if not inst then
        return false
    end
    Autofarm.lockedChestSkip = Autofarm.lockedChestSkip or {}
    local function check(obj)
        local untilTick = Autofarm.lockedChestSkip[obj]
        if not untilTick then
            return false
        end
        if tick() < untilTick then
            return true
        end
        Autofarm.lockedChestSkip[obj] = nil
        return false
    end
    if check(inst) then
        return true
    end
    local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
    return model ~= nil and check(model)
end

function S.playerGuiSaysChestLocked()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then
        return false
    end
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
            local t = string.lower(gui.Text or "")
            if t:find("chest is locked", 1, true)
                or t:find("this chest is locked", 1, true)
                or (t:find("locked", 1, true) and t:find("chest", 1, true))
            then
                if gui.Visible ~= false then
                    local parent = gui.Parent
                    if not parent or parent.Visible ~= false then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function S.isChestPadlocked(inst)
    if not inst then
        return false
    end
    if S.isChestMarkedLocked(inst) then
        return true
    end

    local function attrLocked(obj)
        if not obj then
            return false
        end
        if obj:GetAttribute("Locked") == true then
            return true
        end
        if obj:GetAttribute("Unlocked") == false then
            return true
        end
        if obj:GetAttribute("CanOpen") == false or obj:GetAttribute("CanInteract") == false then
            return true
        end
        if obj:GetAttribute("RequiresKey") == true
            or obj:GetAttribute("KeyRequired") == true
            or obj:GetAttribute("NeedsKey") == true
            or obj:GetAttribute("Padlocked") == true
            or obj:GetAttribute("BossLocked") == true
        then
            return true
        end
        local keyAttr = obj:GetAttribute("Key") or obj:GetAttribute("RequiredKey") or obj:GetAttribute("UnlockKey")
        if type(keyAttr) == "string" and keyAttr ~= "" then
            return true
        end
        return false
    end

    if attrLocked(inst) then
        return true
    end

    local function looksLikeLockName(n)
        n = string.lower(tostring(n or ""))
        return n == "lock"
            or n == "padlock"
            or n:find("padlock", 1, true)
            or n:find("lockicon", 1, true)
            or n:find("chestlock", 1, true)
            or n:find("bosslock", 1, true)
            or n == "locked"
            or n:find("keyhole", 1, true)
            or n:find("keylock", 1, true)
    end

    -- Prompt text can say Locked / Requires Key.
    for _, desc in ipairs(inst:GetDescendants()) do
        if attrLocked(desc) then
            return true
        end
        if desc:IsA("ProximityPrompt") then
            local action = string.lower(desc.ActionText or "")
            local object = string.lower(desc.ObjectText or "")
            if action:find("lock", 1, true)
                or object:find("lock", 1, true)
                or action:find("key", 1, true)
                or object:find("key", 1, true)
            then
                return true
            end
        end
        if looksLikeLockName(desc.Name) then
            if desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
                if desc.Enabled ~= false then
                    return true
                end
            elseif desc:IsA("ImageLabel") or desc:IsA("ImageButton") or desc:IsA("TextLabel") then
                if desc.Visible ~= false then
                    return true
                end
            elseif desc:IsA("BasePart") or desc:IsA("Model") or desc:IsA("Folder") or desc:IsA("Attachment") then
                local n = string.lower(desc.Name or "")
                -- Avoid false positives from decorative keyhole meshes on normal chests.
                if n == "padlock"
                    or n:find("padlock", 1, true)
                    or n:find("lockicon", 1, true)
                    or n:find("chestlock", 1, true)
                    or n:find("bosslock", 1, true)
                then
                    return true
                end
            end
        end
    end

    local name = string.lower(inst.Name or "")
    if name:find("boss", 1, true) and name:find("chest", 1, true) then
        return true
    end
    if name:find("lockedchest", 1, true) or name:find("padlockchest", 1, true) then
        return true
    end

    return false
end

-- Scan only DungeonGate_*.Dungeon_* for ChestNode.*Chest that have ProximityPrompt.
function S.forEachDungeonChestCandidate(callback)
    if type(callback) ~= "function" then
        return
    end

    local function hasAncestorNamed(inst, want)
        local cur = inst
        while cur and cur ~= Workspace do
            if cur.Name == want then
                return true
            end
            cur = cur.Parent
        end
        return false
    end

    local function emit(inst)
        if not inst or hasAncestorNamed(inst, "ChestStep") then
            return
        end
        local model = S.resolveDungeonChestModel(inst)
        if model and S.isDungeonInteriorChest(model) and S.chestHasProximityPrompt(model) then
            callback(model)
        end
    end

    local function scanDungeonFolder(dungeonFolder)
        if not dungeonFolder then
            return
        end
        for _, desc in ipairs(dungeonFolder:GetDescendants()) do
            if hasAncestorNamed(desc, "ChestStep") or desc.Name == "ChestStep" then
                -- geometry only
            elseif desc:IsA("ProximityPrompt") then
                emit(desc)
            elseif desc.Name == "ChestNode" then
                for _, child in ipairs(desc:GetChildren()) do
                    emit(child)
                end
            elseif desc:IsA("Model") then
                local n = string.lower(desc.Name or "")
                if n:find("chest", 1, true)
                    and not n:find("cheststep", 1, true)
                    and n ~= "chestnode"
                    and n ~= "chestnodes"
                    and S.chestHasProximityPrompt(desc)
                then
                    emit(desc)
                end
            end
        end
    end

    for _, gate in ipairs(Workspace:GetChildren()) do
        local gn = gate.Name or ""
        if gn:find("DungeonGate", 1, true) then
            for _, child in ipairs(gate:GetChildren()) do
                local cn = child.Name or ""
                if (cn:match("^Dungeon_") or cn:find("Dungeon_Tier", 1, true))
                    and not cn:find("DungeonGate", 1, true)
                then
                    scanDungeonFolder(child)
                end
            end
        elseif (gn:match("^Dungeon_") or gn:find("Dungeon_Tier", 1, true))
            and not gn:find("DungeonGate", 1, true)
        then
            scanDungeonFolder(gate)
        end
    end
end

function S.collectAutofarmChests(range)
    local root = S.getRoot()
    if not root then
        return {}
    end

    range = range or S.getLootDetectRange()
    local origin = root.Position
    local list = {}
    local seen = {}

    local function consider(inst)
        if not inst then
            return
        end

        local model = S.resolveDungeonChestModel(inst) or inst
        if not model or seen[model] then
            return
        end
        if not S.isTreasureChest(model) then
            return
        end
        if S.isChestPadlocked(model) then
            return
        end
        if not S.chestHasProximityPrompt(model) then
            return
        end

        local pos = S.getInstancePosition(model) or S.getItemPosition(model)
        if not pos then
            return
        end
        -- Flat XY so deep dungeon chests still interrupt cruise.
        local flat = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z).Magnitude
        if flat > range then
            return
        end

        seen[model] = true
        table.insert(list, { inst = model, dist = flat, pos = pos })
    end

    pcall(function()
        S.forEachWorldChestNode(consider)
    end)

    for _, tagged in ipairs(CollectionService:GetTagged("Interactive")) do
        consider(tagged)
    end

    table.sort(list, function(a, b)
        return a.dist < b.dist
    end)
    return list
end

function S.openChestInstant(chest)
    if not chest or not chest.Parent then
        return false
    end

    chest = S.resolveDungeonChestModel(chest) or chest
    if S.isChestPadlocked(chest) then
        return false
    end
    if S.isDecorativeOrShopChest(chest) then
        return false
    end
    -- Open any ChestNode chest except Wave.
    if not S.isChestEspTarget(chest) then
        return false
    end
    if not S.chestHasProximityPrompt(chest) then
        return false
    end

    local root = S.getRoot()
    local savedDistance = Autofarm.distance
    local wasHover = Autofarm.hoverLocked
    local wasPlatform = FollowPlatform.enabled

    if Services.ToolService then
        pcall(function()
            Services.ToolService:UnequipTool()
        end)
        task.wait(0.05)
    end

    local pos = S.getInstancePosition(chest) or S.getItemPosition(chest)
    if root and pos and S.isSaneWorldPos(pos) then
        -- Don't unlock hover while autofarm (void). Pin at chest Y for interact.
        if Autofarm.enabled then
            Autofarm._gatePinY = pos.Y + 3
            S.ensureAutofarmAntiFall(true)
            S.setAutofarmPlatformStand(true)
        else
            S.lockAutofarmHover(false)
        end
        if not FollowPlatform.enabled then
            S.setFollowPlatform(true)
        end
        local under = S.getUnderStandPosition(pos, Autofarm.chestUnderDepth or 10)
        if under then
            if Autofarm.enabled then
                Autofarm._gatePinY = under.Y
            end
            S.lockFollowPlatformAt(under)
            S.snapCharacterOntoPlatform()
            S.supportCharacterOnFollowPlatform()
            task.wait(0.2)
        else
            -- Fallback stand near chest if under-pos rejected.
            root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            root.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.15)
        end
    end

    local knit = S.getKnit()
    if knit then
        pcall(function()
            local drag = knit.GetController("DragController")
            if drag then
                drag.Target = chest
                if drag.TargetChanged then
                    drag.TargetChanged:Fire(chest)
                end
            end
        end)
    end

    local mesh = chest:FindFirstChild("Chest", true) or chest:FindFirstChildWhichIsA("BasePart", true)
    if Services.InteractionService then
        pcall(function()
            Services.InteractionService:Interact(chest)
        end)
        if mesh then
            pcall(function()
                Services.InteractionService:Interact(mesh)
            end)
        end
        for _, part in ipairs(chest:GetDescendants()) do
            if CollectionService:HasTag(part, "Interactive") then
                pcall(function()
                    Services.InteractionService:Interact(part)
                end)
            end
        end
    end

    local held = S.holdChestInteract(chest)
    task.wait(0.2)

    -- Open only. Loot stays on the ground for Auto Loot.
    if held == false or S.playerGuiSaysChestLocked() then
        S.markChestLocked(chest)
        S.clearFollowPlatformLock()
        if not wasPlatform then
            S.setFollowPlatform(false)
        end
        Autofarm._gatePinY = nil
        if Autofarm.enabled and savedDistance ~= nil then
            Autofarm.distance = savedDistance
            S.setAutofarmPose(savedDistance)
            S.ensureAutofarmAntiFall(true)
            S.lockAutofarmHover(true)
        elseif wasHover then
            S.lockAutofarmHover(true)
        end
        return false
    end

    S.clearFollowPlatformLock()
    if not wasPlatform then
        S.setFollowPlatform(false)
    end

    Autofarm._gatePinY = nil
    if Autofarm.enabled and savedDistance ~= nil then
        Autofarm.distance = savedDistance
        S.setAutofarmPose(savedDistance)
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
    elseif wasHover then
        S.lockAutofarmHover(true)
    end

    return true
end

function S.autofarmOpenNearbyChests()
    if not Autofarm.openChests then
        return 0
    end

    local chests = S.collectAutofarmChests(S.getLootDetectRange())
    local opened = 0
    for i, entry in ipairs(chests) do
        if i > 4 then
            break
        end
        local chest = entry.inst
        if S.openChestInstant(chest) then
            opened += 1
            task.wait(0.15)
        end
        -- Do NOT blacklist on normal open failure — only toast/padlock marking does that.
    end
    return opened
end

function S.isSaneWorldPos(pos)
    if typeof(pos) ~= "Vector3" then
        return false
    end
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
        return false
    end
    -- Allow deep mines (ores sit far below sea level). Only reject asset/void dumps (~-999999).
    if pos.Y < -8000 or pos.Y > 5000 then
        return false
    end
    if math.abs(pos.X) > 200000 or math.abs(pos.Z) > 200000 then
        return false
    end
    return true
end

-- Ore nodes can be deep underground inside mines — looser Y than general void checks.
function S.isSaneOrePos(pos)
    if typeof(pos) ~= "Vector3" then
        return false
    end
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
        return false
    end
    if pos.Y < -8000 or pos.Y > 5000 then
        return false
    end
    if math.abs(pos.X) > 200000 or math.abs(pos.Z) > 200000 then
        return false
    end
    return true
end

-- lookAt blows up / NaNs when from≈to — that TPs you into the void and softlocks farm.
function S.safeLookAt(from, lookAt)
    if typeof(from) ~= "Vector3" then
        return nil
    end
    if typeof(lookAt) ~= "Vector3" then
        lookAt = from + Vector3.new(0, 1, 0)
    end
    if (lookAt - from).Magnitude < 0.08 then
        lookAt = from + Vector3.new(0, 1, 0)
    end
    local ok, cf = pcall(CFrame.lookAt, from, lookAt)
    if ok and typeof(cf) == "CFrame" then
        local p = cf.Position
        if p.X == p.X and p.Y == p.Y and p.Z == p.Z then
            return cf
        end
    end
    return CFrame.new(from)
end

function S.autofarmCycleShouldAbort()
    return Autofarm._cycleAbort == true
        or Autofarm.enabled ~= true
        or Autofarm._farmShuttingDown == true
        or Autofarm._banditPause == true
end

function S.autofarmVisitStale()
    if S.autofarmCycleShouldAbort() then
        return true
    end
    local visitGen = Autofarm._visitGen
    return typeof(visitGen) == "number" and visitGen > 0 and Autofarm._cycleGen ~= visitGen
end

function S.suppressAutofarmMines(seconds)
    Autofarm.suppressMinesUntil = math.max(Autofarm.suppressMinesUntil or 0, tick() + (tonumber(seconds) or 5))
end

function S.skipAutofarmMine(mine, seconds, why)
    Autofarm.skipMinesUntil = Autofarm.skipMinesUntil or {}
    local hold = tick() + (tonumber(seconds) or 90)
    local target = mine or Autofarm._activeMine
    if target then
        Autofarm.skipMinesUntil[target] = hold
    end
    local name = target and target.Name or "?"
    S.farmLog("mine skip", string.format("%s %ds %s", tostring(name), tonumber(seconds) or 90, tostring(why or "done")))
    Autofarm._activeMine = nil
    Autofarm._gatePinY = nil
end

-- Instantly drop mine-gate / hover pins so disable actually frees the character.
function S.releaseStuckFarmHold()
    Autofarm._cycleAbort = true
    Autofarm._cycleGen = (Autofarm._cycleGen or 0) + 1
    Autofarm._returnGen = (Autofarm._returnGen or 0) + 1
    Autofarm._activeMine = nil
    Autofarm._gatePinY = nil
    Autofarm.miningBusy = false
    Autofarm._miningBusySince = nil
    Autofarm._oreHuntMode = false
    Autofarm.moving = false
    Autofarm.busy = false
    Autofarm._cycleRunning = false
    Autofarm._scrapProcessing = false
    S.cancelAutofarmTween()
    S.clearMineHoldPin()
    S.disconnectAll("autofarmHover")
    S.disconnectAll("autofarmAntiFall")
    Autofarm.hoverLocked = false
    pcall(S.releaseAutofarmSeat)
    local humanoid = S.getHumanoid()
    if humanoid then
        pcall(function()
            humanoid.Sit = false
            humanoid.PlatformStand = false
        end)
    end
    local root = S.getRoot()
    if root then
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

function S.touchMiningBusyHeartbeat()
    Autofarm._miningBusySince = tick()
end

-- Visible stone. NEVER prefer MeshPart "Ore" at asset dump coords.
-- maxFromPlayer: nil = no player-distance filter (ESP / long detect).
function S.getOreAnchorPart(ore, maxFromPlayer)
    if not ore or not ore.Parent then
        return nil
    end

    local root = S.getRoot()
    local origin = root and root.Position or nil
    if origin and not S.isSaneOrePos(origin) then
        origin = Vector3.new(origin.X, Autofarm.flyY or 28, origin.Z)
    end

    local best, bestDist = nil, math.huge

    local function consider(part)
        if not part or not part:IsA("BasePart") then
            return
        end
        if part.Name == "Ore" and part ~= ore then
            return
        end
        local pos = part.Position
        if not S.isSaneOrePos(pos) then
            return
        end
        local dist = origin and (pos - origin).Magnitude or 0
        if maxFromPlayer and origin and dist > maxFromPlayer then
            return
        end
        if dist < bestDist then
            best = part
            bestDist = dist
        end
    end

    for _, child in ipairs(ore:GetChildren()) do
        if child:IsA("BasePart") and child.Name == "Rock" then
            consider(child)
        end
    end
    if best then
        return best
    end

    for _, desc in ipairs(ore:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name == "Rock" then
            consider(desc)
        end
    end
    if best then
        return best
    end

    if ore:IsA("BasePart") then
        consider(ore)
    end
    if best then
        return best
    end

    -- Prefer gem MeshPart "Ore" when present (cloned from Assets.Ores).
    local gem = S.getOreGemPart(ore)
    if gem and S.isSaneOrePos(gem.Position) then
        if not maxFromPlayer or not origin or (gem.Position - origin).Magnitude <= maxFromPlayer then
            return gem
        end
    end

    for _, desc in ipairs(ore:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name ~= "Ore" and desc.Transparency < 1 then
            consider(desc)
        end
    end

    return best
end

function S.getOreWorldPosition(ore)
    if not ore or not ore.Parent then
        return nil
    end
    -- NEVER prefer MeshPart "Ore" alone — it can sit at asset-dump coords.
    local part = S.getOreAnchorPart(ore, nil) or S.getOreEspAdornee(ore)
    if part then
        return part.Position
    end
    if ore:IsA("Model") and ore.GetPivot then
        local ok, pivot = pcall(function()
            return ore:GetPivot().Position
        end)
        if ok and pivot and S.isSaneOrePos(pivot) then
            return pivot
        end
    end
    return nil
end

-- Stand ~depth studs UNDER the rock so surface mobs / worms can't hit you.
function S.getOreUnderPosition(ore, depth)
    local part = S.getOreAnchorPart(ore, 250) or S.getOreAnchorPart(ore, nil)
    if not part then
        local pos = S.getOreWorldPosition(ore)
        if not pos or not S.isSaneOrePos(pos) then
            return nil
        end
        depth = depth or Autofarm.oreUnderDepth or 11
        return S.getUnderStandPosition(pos, depth)
    end

    local pos = part.Position
    depth = depth or Autofarm.oreUnderDepth or 11
    return S.getUnderStandPosition(pos, depth)
end

-- Auto Ore dig stand = under rock (safe from mobs). Kept as alias for call sites.
function S.getOreMineStandPosition(ore)
    return S.getOreUnderPosition(ore, Autofarm.oreUnderDepth or 11)
end

-- Stand on cruise Y above the ore (loot pass / non-dig).
function S.getOreCruiseHoldPosition(ore)
    local pos = S.getOreWorldPosition(ore)
    if not pos or not S.isSaneOrePos(pos) then
        return nil
    end
    return Vector3.new(pos.X, S.getAutofarmFlyY(), pos.Z)
end

function S.holdCharacterAt(pos, opts)
    opts = opts or {}
    if not pos then
        return
    end
    if opts.cruise ~= true and not S.isSaneWorldPos(pos) then
        return
    end

    Autofarm._holdPos = pos
    Autofarm._holdLook = opts.lookAt
    Autofarm._holdOre = opts.ore
    Autofarm._holdCruise = opts.cruise == true

    if State.connections.oreUnderHold then
        return
    end

    S.setAutofarmPlatformStand(true)
    State.connections.oreUnderHold = RunService.Heartbeat:Connect(function()
        local root = S.getRoot()
        if not root then
            return
        end

        local hold = Autofarm._holdPos
        local ore = Autofarm._holdOre
        if ore and ore.Parent then
            local nextHold = Autofarm._holdCruise and S.getOreCruiseHoldPosition(ore)
                or S.getOreUnderPosition(ore, Autofarm.oreUnderDepth or 11)
            if nextHold and (Autofarm._holdCruise or S.isSaneWorldPos(nextHold)) then
                hold = nextHold
                Autofarm._holdPos = hold
                Autofarm._holdLook = S.getOreWorldPosition(ore)
            end
        end
        if not hold then
            return
        end
        if not Autofarm._holdCruise and not S.isSaneWorldPos(hold) then
            return
        end

        root.Anchored = false
        local look = Autofarm._holdLook
        if look then
            root.CFrame = CFrame.lookAt(hold, look)
        else
            root.CFrame = CFrame.new(hold)
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

function S.releaseCharacterHold()
    Autofarm._holdPos = nil
    Autofarm._holdLook = nil
    Autofarm._holdOre = nil
    Autofarm._holdCruise = nil
    S.disconnectAll("oreUnderHold")
end

function S.collectAutofarmSelectedOres(range)
    local root = S.getRoot()
    if not root then
        return {}
    end

    range = range or S.getLootDetectRange()
    local origin = root.Position
    if not S.isSaneOrePos(origin) then
        origin = Vector3.new(origin.X, Autofarm.flyY or 70, origin.Z)
    end

    local list = {}

    S.forEachWorldOreNode(function(ore)
        if S.isOreSkipped(ore) or not S.oreMatchesAutofarmSelection(ore) then
            return
        end
        local pos = S.getOreWorldPosition(ore)
        if not pos or not S.isSaneOrePos(pos) then
            return
        end
        -- Flat range: Workspace.Ores can be thousands of studs below cruise Y.
        local flat = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z).Magnitude
        if flat <= range then
            table.insert(list, { ore = ore, dist = flat, pos = pos })
        end
    end)

    table.sort(list, function(a, b)
        return a.dist < b.dist
    end)
    return list
end

-- Mine selected ores standing UNDER the rock (not cruise Y).
function S.autofarmUnderMinePass(opts)
    opts = type(opts) == "table" and opts or {}
    if not (Autofarm.oreUnderEnabled or S.isScrapGoldPhase()) then
        return 0
    end
    if type(S.getAutofarmActiveOreTypes()) ~= "table" or #S.getAutofarmActiveOreTypes() == 0 then
        return 0
    end
    if S.autofarmVisitStale() then
        return 0
    end

    local root = S.getRoot()
    if not root then
        return 0
    end

    Autofarm.miningBusy = true
    S.touchMiningBusyHeartbeat()
    Autofarm._oreHuntMode = true
    local huntRange = tonumber(opts.range) or (S.isScrapGoldPhase() and 200 or S.getAutofarmOreHuntRange())
    local maxSeconds = tonumber(opts.seconds) or (S.isScrapGoldPhase() and 8 or 20)
    local visitGen = Autofarm._visitGen or Autofarm._cycleGen
    local savedDistance = Autofarm.distance or S.syncAutofarmDistanceFromRoot()
    local depth = tonumber(Autofarm.oreUnderDepth) or 11
    local mined = 0
    S.farmLog("mine dig", string.format("range=%d %ds", huntRange, maxSeconds))

    local ok, err = pcall(function()
        S.lockAutofarmHover(true)
        root.Anchored = false
        S.setAutofarmPlatformStand(true)

        pcall(function()
            Autofarm.miningBusy = false
            if S.isScrapGoldPhase() then
                S.yankScrapGoldLootNearby(700)
            else
                S.yankOreDropsNearby(500)
            end
            Autofarm.miningBusy = true
            S.touchMiningBusyHeartbeat()
            S.lockAutofarmHover(true)
        end)

        local passSafety = os.clock() + maxSeconds
        local minedThisPass = 0

        while Autofarm.enabled and os.clock() < passSafety do
            if S.autofarmCycleShouldAbort() or Autofarm._cycleGen ~= visitGen then
                break
            end
            local ores = S.collectAutofarmSelectedOres(huntRange)
            if #ores == 0 then
                task.wait(0.25)
                pcall(function()
                    local r = S.getRoot()
                    if r then
                        S.requestStreamAround(r.Position, 1)
                    end
                end)
                ores = S.collectAutofarmSelectedOres(huntRange)
                if #ores == 0 then
                    break
                end
            end

            local ore = ores[1].ore
            if not ore or not ore.Parent then
                break
            end

            local rockPos = S.getOreWorldPosition(ore)
            local underHold = S.getOreUnderPosition(ore, Autofarm.oreUnderDepth or 11)
            if not underHold and rockPos then
                underHold = S.getUnderStandPosition(rockPos, Autofarm.oreUnderDepth or 11)
            end
            if not (rockPos and underHold and S.isSaneOrePos(underHold) and S.isSaneOrePos(rockPos)) then
                S.markOreSkip(ore, 20)
                continue
            end

            -- Stand UNDER the ore so worms/mobs can't hit.
            S.releaseCharacterHold()
            S.cancelAutofarmTween()
            if not S.ensurePickaxe(0.6) then
                S.markOreSkip(ore, 15)
                continue
            end
            Autofarm._gatePinY = underHold.Y
            Autofarm._mineHoldPos = underHold
            Autofarm._mineLookAt = rockPos
            root = S.getRoot()
            if root then
                root.Anchored = false
                local cf = S.safeLookAt(underHold, rockPos)
                if cf then
                    root.CFrame = cf
                end
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                S.setAutofarmPlatformStand(true)
            end
            S.ensurePickaxe(0.45)
            pcall(function()
                S.requestStreamAround(underHold, 0.8)
            end)
            S.touchMiningBusyHeartbeat()
            S.farmLog("mine swing", S.resolveOreTypeKey(ore) or ore.Name)
            S.notify("Autofarm", "Ore under → " .. tostring(S.resolveOreTypeKey(ore) or ore.Name), 2)

            local oreDeadline = os.clock() + 55
            local startedMineable = S.isOreStillMineable(ore)
            local lastHealth = nil
            local noProgressSince = os.clock()
            local healthObj = ore:FindFirstChild("Health")
            if healthObj and (healthObj:IsA("NumberValue") or healthObj:IsA("IntValue")) then
                lastHealth = healthObj.Value
            end

            while S.isOreStillMineable(ore) and Autofarm.enabled and os.clock() < oreDeadline do
                if S.autofarmCycleShouldAbort() or Autofarm._cycleGen ~= visitGen then
                    break
                end
                local livePos = S.getOreWorldPosition(ore) or rockPos
                local liveUnder = S.getOreUnderPosition(ore, Autofarm.oreUnderDepth or 11)
                    or (livePos and S.getUnderStandPosition(livePos, Autofarm.oreUnderDepth or 11))
                underHold = liveUnder
                rockPos = livePos
                Autofarm._gatePinY = underHold.Y
                Autofarm._mineHoldPos = underHold
                Autofarm._mineLookAt = rockPos

                root = S.getRoot()
                if root and S.isSaneOrePos(underHold) then
                    local cf = S.safeLookAt(underHold, rockPos)
                    if cf then
                        root.CFrame = cf
                    end
                    root.AssemblyLinearVelocity = Vector3.zero
                    S.setAutofarmPlatformStand(true)
                end

                if S.hasFaceDeathWormThreat() then
                    pcall(S.tryAutoKillFaceWorms)
                else
                    local swingTargets = { ore }
                    for _, worm in ipairs(S.collectFaceDeathWorms()) do
                        table.insert(swingTargets, worm)
                    end
                    S.fireMeleeSwingTargets(swingTargets)
                end

                S.touchMiningBusyHeartbeat()
                healthObj = ore:FindFirstChild("Health")
                if healthObj and (healthObj:IsA("NumberValue") or healthObj:IsA("IntValue")) and healthObj.Value > 0 then
                    if lastHealth == nil or healthObj.Value < lastHealth then
                        lastHealth = healthObj.Value
                        noProgressSince = os.clock()
                    elseif os.clock() - noProgressSince >= 22 then
                        S.markOreSkip(ore, 12)
                        break
                    end
                end
                task.wait(0.08)
            end

            if startedMineable and not S.isOreStillMineable(ore) then
                minedThisPass += 1
                local breakPos = rockPos or S.getOreWorldPosition(ore) or underHold
                pcall(function()
                    S.vacuumOreDropsVerified(breakPos)
                end)
                if S.isScrapGoldPhase() then
                    S.yankScrapGoldLootNearby(900)
                end
                S.touchMiningBusyHeartbeat()
                if S.isBagFull() then
                    break
                end
                task.wait(0.04)
            else
                S.markOreSkip(ore, 20)
            end

            if minedThisPass >= 4 then
                break
            end
        end

        mined = minedThisPass
    end)

    if not ok then
        warn("[TERRA HUB] ore-under error:", err)
    end

    S.releaseCharacterHold()
    S.clearFollowPlatformLock()
    Autofarm._gatePinY = nil
    S.clearMineHoldPin()

    Autofarm.distance = savedDistance
    if Autofarm.enabled then
        S.setAutofarmPose(savedDistance)
        S.lockAutofarmHover(true)
        S.ensureAutofarmAntiFall(true)
    end
    Autofarm.miningBusy = false
    Autofarm._miningBusySince = nil
    Autofarm._oreHuntMode = false

    return mined
end

function S.findDungeonForAutofarm(range, sideLimit)
    range = range or math.max(Autofarm.mapEndStuds or 100000, 5000)
    sideLimit = tonumber(sideLimit) or 420
    local root = S.getRoot()
    if not root then
        return nil
    end

    local origin = Autofarm.origin or root.Position
    local dir = S.getAutofarmAxisVector()
    local best, bestDist = nil, math.huge
    local now = tick()
    local skips = Autofarm.skipDungeonsUntil or {}
    local playerFlat = Vector3.new(root.Position.X, 0, root.Position.Z)

    local function consider(inst)
        if not inst or not S.isDungeonRoot(inst) then
            return
        end
        if skips[inst] and now < skips[inst] then
            return
        end
        local pos = select(1, S.getDungeonApproachPos(inst))
        if not pos then
            return
        end
        local rel = pos - origin
        local flat = Vector3.new(rel.X, 0, rel.Z)
        local along = flat:Dot(dir)
        local side = (flat - dir * along).Magnitude
        if along < -range or along > range or side > sideLimit then
            return
        end
        local dist = (Vector3.new(pos.X, 0, pos.Z) - playerFlat).Magnitude
        if dist < bestDist then
            bestDist = dist
            best = inst
        end
    end

    for _, child in ipairs(Workspace:GetChildren()) do
        consider(child)
    end

    return best
end

function S.findDungeonAhead(range)
    return S.findDungeonForAutofarm(range)
end

function S.enterDungeonForLoot(dungeonRoot)
    local root = S.getRoot()
    if not root or not dungeonRoot or not S.isDungeonRoot(dungeonRoot) then
        return false
    end

    Money.savedTravelDistance = Money.travelDistance or 0

    -- Enter = DungeonGate_*.Gate.Attachment.ProximityPrompt (ActionText "Enter")
    local enterPrompt = S.findDungeonEnterPrompt(dungeonRoot)
    if enterPrompt then
        S.teleportToPromptAndFire(enterPrompt)
    else
        local enterPos = select(1, S.getDungeonApproachPos(dungeonRoot)) or dungeonRoot:GetPivot().Position
        S.autofarmTweenTowardWorldPos(enterPos)
        task.wait(0.15)
    end

    S.lockAutofarmHover(true)
    if not S.coreChestsOnly() then
    pcall(function()
        S.pickupAllVisibleLoot({ duringMine = true, seconds = 6, requireAutofarm = false })
    end)
    end

    return true
end

function S.exitDungeonToLine()
    local root = S.getRoot()
    if not root then
        return
    end

    local dungeonRoot = nil
    local inDungeon = LocalPlayer:GetAttribute("InDungeon") == true
    pcall(function()
        for _, child in ipairs(Workspace:GetChildren()) do
            if S.isDungeonRoot(child) then
                local exitPrompt = S.findDungeonExitPrompt(child)
                local pos = exitPrompt and S.getPromptWorldPosition(exitPrompt)
                    or select(1, S.getDungeonApproachPos(child))
                if pos and (pos - root.Position).Magnitude < 500 then
                    dungeonRoot = child
                    inDungeon = true
                    break
                end
            end
        end
    end)

    if inDungeon then
        local exitPrompt = dungeonRoot and S.findDungeonExitPrompt(dungeonRoot)
        if not exitPrompt then
            for _, child in ipairs(Workspace:GetChildren()) do
                if S.isDungeonRoot(child) then
                    exitPrompt = S.findDungeonExitPrompt(child)
                    if exitPrompt then
                        dungeonRoot = child
                        break
                    end
                end
            end
        end
        if exitPrompt then
            -- Leave = ...Dungeon_*.DungeonGate_*.Gate.Attachment (ActionText "Sair")
            S.teleportToPromptAndFire(exitPrompt)
        end
    end

    if Money.savedTravelDistance then
        Money.travelDistance = Money.savedTravelDistance
        Money.savedTravelDistance = nil
    end

    S.resumeOnDrillLine()
    task.wait(0.1)
end

function S.lootMoneyTargetsOnce(capacity)
    local looted = 0
    local targets = S.collectMoneyLootTargets()
    S.ensureBagReadyForLoot()

    for _, item in ipairs(targets) do
        if S.getBagFillCount() >= capacity then
            break
        end

        local pos = S.getItemPosition(item)
        if pos and LocalPlayer:DistanceFromCharacter(pos) <= Loot.range then
            if S.bagPickup(item) then
                looted += 1
                Money.trackedBagAt = Money.trackedBagAt or os.clock()
                task.wait(0.18)
            end
        end
    end

    return looted
end

function S.lootInsideDungeon(dungeonRoot, capacity)
    local looted = 0

    for pass = 1, 10 do
        if S.getBagFillCount() >= capacity then
            break
        end

        local passLoot = S.lootMoneyTargetsOnce(capacity)
        looted += passLoot

        if passLoot == 0 and dungeonRoot then
            local offset = S.ensureMoneyTravelHeading() * (8 + pass * 3)
            local pos = dungeonRoot:GetPivot().Position + offset + Vector3.new(0, 4, 0)
            S.teleportToGroundPosition(pos, Vector3.new(0, 3, 0))
            task.wait(0.12)
        else
            task.wait(0.1)
        end
    end

    return looted
end

function S.sellAndCollectAtPart(sellPart, options)
    options = options or {}
    if not sellPart then
        return 0, 0
    end

    local root = S.getRoot()
    if root then
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        -- Stand on the trade surface so Drop lands on SellPart.
        root.CFrame = S.getSellDropCFrame(sellPart) * CFrame.new(0, 2.4, 0)
        root.AssemblyLinearVelocity = Vector3.zero
    end
    task.wait(0.15)

    S.ensureItemBag()
    local equipped = S.getEquippedTool()
    if not equipped or not S.isItemBagTool(equipped) then
        S.ensureItemBag()
        task.wait(0.2)
    end

    local function refreshStored()
        S.ensureItemBag()
        pcall(function()
            local update = Services.ToolService and Services.ToolService.Update
            if update and update.Fire then
                local _ = update -- (sack dihapus)
            end
        end)
    end

    refreshStored()
    task.wait(0.08)

    local beforeFill = math.max(S.getBagFillCount(), Money.trackedBagSize or 0)
    if beforeFill < 1 then
        beforeFill = 10
    end

    -- Dump the whole sack fast — no money-bag collection mid-drop.
    local sold = 0
    for _ = 1, beforeFill + 4 do
        refreshStored()
        if not S.bagDrop() then
            break
        end
        sold += 1
        task.wait(0.05)
    end

    task.wait(0.12)
    S.moveItemsOntoSellPart(sellPart, 50)
    task.wait(0.2)
    S.moveItemsOntoSellPart(sellPart, 50)

    -- One more dump pass if UI still shows items.
    local still = S.getBagFillCount()
    if still > 0 then
        refreshStored()
        for _ = 1, still + 2 do
            if not S.bagDrop() then
                break
            end
            sold += 1
            task.wait(0.05)
        end
        S.moveItemsOntoSellPart(sellPart, 50)
        task.wait(0.15)
    end

    Money.trackedBagSize = 0

    local sackRange = options.sackRange or 60
    local sacks = 0
    if options.thoroughSacks then
        -- Only near the sell post — never Workspace:GetDescendants spam.
        sacks = S.collectSellMoneySacks(sellPart, math.max(sold, 1), sackRange)
    else
        sacks = S.collectMoneySacks(sackRange, false)
    end
    task.wait(0.1)

    if options.resumeDrillLine then
        S.resumeOnDrillLine()
        task.wait(0.1)
    end

    return sold, sacks
end

function S.interactMoneySackFast(item, floorY)
    if not item or not item.Parent or not Services.InteractionService then
        return false
    end

    local pos = S.getItemPosition(item)
    local root = S.getRoot()
    if pos and root then
        local y = floorY or (pos.Y + 2)
        -- Stay on the trade floor — never snap up to cruise height.
        root.CFrame = CFrame.new(pos.X, y, pos.Z)
        root.AssemblyLinearVelocity = Vector3.zero
    end

    local before = item.Parent
    pcall(function()
        Services.InteractionService:Interact(item)
    end)

    if typeof(fireproximityprompt) == "function" then
        for _, desc in ipairs(item:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then
                pcall(fireproximityprompt, desc)
            end
        end
    end

    local knit = S.getKnit()
    if knit then
        pcall(function()
            local drag = knit.GetController("DragController")
            if drag then
                drag.Target = item
                if drag.PerformConsoleInteract then
                    drag:PerformConsoleInteract()
                end
            end
        end)
    end

    task.wait(0.04)
    return (not item.Parent) or (before ~= item.Parent)
end

function S.collectSellMoneySacks(sellPart, expectedCount, range)
    if not sellPart then
        return 0
    end

    expectedCount = expectedCount or 1
    range = range or 55
    local collected = 0
    local sellTable = S.getSellTableModel(sellPart)
    local floorY = S.getSellFloorY(sellPart, sellTable) + 2

    -- Stand once on the sell floor, then vacuum bags in place.
    local root = S.getRoot()
    if root then
        root.Anchored = false
        root.CFrame = S.getSellStandCFrame(sellPart)
        root.AssemblyLinearVelocity = Vector3.zero
    end
    pcall(function()
        if Services.ToolService then
            Services.ToolService:UnequipTool()
        end
    end)
    task.wait(0.08)

    local emptyStreak = 0
    for _ = 1, expectedCount + 8 do
        if collected >= expectedCount then
            break
        end

        local batch = {}
        local itemsFolder = Workspace:FindFirstChild("Items")
        if itemsFolder then
            for _, item in ipairs(itemsFolder:GetChildren()) do
                if item.Name == "Money_Sack" or item:GetAttribute("Class") == "Money_Sack" then
                    local pos = S.getItemPosition(item)
                    if pos and (pos - sellPart.Position).Magnitude <= range then
                        table.insert(batch, { item = item, dist = (pos - sellPart.Position).Magnitude })
                    end
                end
            end
        end

        table.sort(batch, function(a, b)
            return a.dist < b.dist
        end)

        if #batch == 0 then
            emptyStreak += 1
            if emptyStreak >= 5 then
                break
            end
            task.wait(0.08)
        else
            emptyStreak = 0
            -- Grab every spawned bag this tick (1 bag per sold loot).
            for _, entry in ipairs(batch) do
                if collected >= expectedCount then
                    break
                end
                if entry.item.Parent and S.interactMoneySackFast(entry.item, floorY) then
                    collected += 1
                end
            end
            if root and root.Parent then
                root.CFrame = S.getSellStandCFrame(sellPart)
            end
            task.wait(0.05)
        end
    end

    S.ensureItemBag()
    return collected
end

function S.sellAndCollectAtNearestPost()
    return S.sellAndCollectAtPart(S.ensureTownSellPart(), {
        resumeDrillLine = true,
        sackRange = Money.sackRange,
    })
end

-- ========== AUTOFARM (chunk scan + sell loop) ==========

-- Nearest streamed layer track. Tutorial_Layer is not forced: its LookVector is not the drill line.
function S.findAutofarmTrackPart()
    local chunks = Workspace:FindFirstChild("Chunks")
    local layers = chunks and chunks:FindFirstChild("Layers")
    if not layers then
        return nil
    end

    local root = S.getRoot()
    local origin = root and root.Position
    local best, bestDist = nil, math.huge

    for _, layer in ipairs(layers:GetChildren()) do
        local track = layer:FindFirstChild("Track") or layer:FindFirstChild("Track", true)
        if track then
            local cf = S.getTrackInstanceCFrame(track)
            if cf then
                if not origin then
                    return track
                end
                local dist = (Vector3.new(cf.Position.X, 0, cf.Position.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    best = track
                end
            end
        end
    end

    return best
end

function S.getTrackInstanceCFrame(track)
    if not track then
        return nil
    end
    if track:IsA("BasePart") then
        return track.CFrame
    end
    if track:IsA("Model") then
        local ok, pivot = pcall(function()
            return track:GetPivot()
        end)
        if ok and pivot then
            return pivot
        end
        local pp = track.PrimaryPart or track:FindFirstChildWhichIsA("BasePart", true)
        return pp and pp.CFrame or nil
    end
    local part = track:FindFirstChildWhichIsA("BasePart", true)
    return part and part.CFrame or nil
end

function S.getAutofarmAxisVectorFromString()
    local axis = Autofarm.axis or "+Z"
    if axis == "+X" then
        return Vector3.new(1, 0, 0)
    elseif axis == "-X" then
        return Vector3.new(-1, 0, 0)
    elseif axis == "-Z" then
        return Vector3.new(0, 0, -1)
    end
    return Vector3.new(0, 0, 1)
end

-- Straight drill line is Start_Position → End_Position. Track LookVector is only a fallback.
function S.getDrillRouteAxis()
    local startPos = Workspace:GetAttribute("Start_Position")
    local endPos = Workspace:GetAttribute("End_Position")
    if typeof(startPos) ~= "Vector3" or typeof(endPos) ~= "Vector3" then
        return nil
    end
    local flat = Vector3.new(endPos.X - startPos.X, 0, endPos.Z - startPos.Z)
    if flat.Magnitude < 1 then
        return nil
    end
    return flat.Unit
end

function S.refreshAutofarmRouteDir()
    local drillAxis = S.getDrillRouteAxis()
    if drillAxis then
        Autofarm.routeDirBase = drillAxis
        return S.getAutofarmAxisVector()
    end

    local track = S.findAutofarmTrackPart()
    if track then
        local cf = S.getTrackInstanceCFrame(track)
        if cf then
            local look = cf.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude > 0.05 then
                Autofarm.routeDirBase = flat.Unit
                return S.getAutofarmAxisVector()
            end
        end
    end

    -- No Track streamed yet: keep previous base, else character look.
    if Autofarm.routeDirBase and Autofarm.routeDirBase.Magnitude > 0.05 then
        return S.getAutofarmAxisVector()
    end

    return S.snapAutofarmAxisFromLook()
end

function S.setAutofarmTrackForward(forward)
    Autofarm.trackForward = forward ~= false
    if not (Autofarm.routeDirBase and Autofarm.routeDirBase.Magnitude > 0.05) then
        S.refreshAutofarmRouteDir()
    end
    Autofarm.routeDir = S.getAutofarmAxisVector()
    local flat = Autofarm.routeDir
    if flat and flat.Magnitude > 0.05 then
        if math.abs(flat.X) >= math.abs(flat.Z) then
            Autofarm.axis = flat.X >= 0 and "+X" or "-X"
        else
            Autofarm.axis = flat.Z >= 0 and "+Z" or "-Z"
        end
    end
    if Autofarm.enabled then
        S.syncAutofarmDistanceFromRoot()
        S.setAutofarmPose(Autofarm.distance or 0)
    end
    return Autofarm.routeDir
end

function S.getAutofarmAxisVector()
    local base = Autofarm.routeDirBase
    if base and base.Magnitude > 0.05 then
        local dir = base.Unit
        if Autofarm.trackForward == false then
            dir = -dir
        end
        Autofarm.routeDir = dir
        return dir
    end
    if Autofarm.routeDir and Autofarm.routeDir.Magnitude > 0.05 then
        return Autofarm.routeDir.Unit
    end
    return S.getAutofarmAxisVectorFromString()
end

function S.getAutofarmFlyY()
    return Autofarm.flyY or 70
end

function S.getAutofarmWorldPosition(distance)
    local origin = Autofarm.origin
    if not origin then
        local root = S.getRoot()
        if not root then
            return nil
        end
        origin = root.Position
    end

    local dir = S.getAutofarmAxisVector()
    local flat = Vector3.new(origin.X, 0, origin.Z) + dir * (distance or 0)
    return Vector3.new(flat.X, S.getAutofarmFlyY(), flat.Z)
end

function S.getAutofarmCFrame(distance)
    local pos = S.getAutofarmWorldPosition(distance)
    if not pos then
        return nil
    end
    local dir = S.getAutofarmAxisVector()
    return S.safeLookAt(pos, pos + dir)
end

function S.cancelAutofarmTween()
    Autofarm.moving = false
    if Autofarm.activeTween then
        pcall(function()
            Autofarm.activeTween:Cancel()
        end)
        Autofarm.activeTween = nil
    end
end

function S.setAutofarmPlatformStand(enabled)
    -- While autofarm is on, never drop PlatformStand (flyY ~ -15 = instant void).
    -- Shutting down must always be allowed to release the character.
    if Autofarm.enabled and not Autofarm._farmShuttingDown then
        enabled = true
    end
    local humanoid = S.getHumanoid()
    if not humanoid then
        return
    end
    pcall(function()
        humanoid.PlatformStand = enabled == true
    end)
end

function S.clearDragTarget()
    local knit = S.getKnit()
    if not knit then
        return
    end
    pcall(function()
        local drag = knit.GetController("DragController")
        if drag then
            drag.Target = nil
            if drag.TargetChanged then
                drag.TargetChanged:Fire(nil)
            end
        end
    end)
end

function S.requestStreamAround(position, timeout)
    local root = S.getRoot()
    position = position or (root and root.Position)
    if not position then
        return false
    end

    timeout = timeout or 1.5
    local ok = pcall(function()
        if typeof(LocalPlayer.RequestStreamAroundAsync) == "function" then
            LocalPlayer:RequestStreamAroundAsync(position, timeout)
        end
    end)
    return ok
end

-- Faster speed outruns StreamingEnabled harder — settle longer / shorter legs automatically.
function S.getAutofarmSpeed()
    return math.clamp(Autofarm.tweenSpeed or 1500, 80, 4000)
end

function S.farmHoldReason()
    if Autofarm._farmShuttingDown then
        return "shutting down"
    end
    if Autofarm._scrapFlushing then
        return "scrap flush"
    end
    if Autofarm._scrapProcessing then
        return "scrap process"
    end
    if Autofarm.miningBusy then
        if Autofarm._activeMine then
            return "mine dig"
        end
        return "ore dig"
    end
    if Autofarm._oreHuntMode then
        return "ore hunt"
    end
    if Autofarm.moving then
        return "tween"
    end
    if Autofarm.busy then
        return Autofarm._holdReason or "busy"
    end
    return "none"
end

function S.destroyFarmDebugHud()
    S.disconnectAll("farmDebugHud")
    local gui = Autofarm._debugGui
    Autofarm._debugGui = nil
    Autofarm._debugLabel = nil
    if gui then
        pcall(function()
            gui:Destroy()
        end)
    end
end

function S.ensureFarmDebugHud()
    if Autofarm.debugHud ~= true or Autofarm._debugHudBlocked then
        return Autofarm._debugLabel
    end
    if Autofarm._debugLabel and Autofarm._debugLabel.Parent then
        return Autofarm._debugLabel
    end
    S.destroyFarmDebugHud()

    local parent
    -- Never CoreGui: executors throw "lacking capability Plugin" and that used to kill the farm cycle.
    if typeof(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and hui then
            parent = hui
        end
    end
    if not parent and LocalPlayer then
        parent = LocalPlayer:FindFirstChild("PlayerGui")
        if not parent then
            pcall(function()
                parent = LocalPlayer:WaitForChild("PlayerGui", 2)
            end)
        end
    end
    if not parent then
        Autofarm._debugHudBlocked = true
        return nil
    end

    local ok, label = pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "JPAXFarmDebug"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 9999
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        pcall(function()
            gui.ClipToDeviceSafeArea = false
        end)
        local lab = Instance.new("TextLabel")
        lab.Name = "Log"
        lab.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
        lab.BackgroundTransparency = 0.25
        lab.BorderSizePixel = 0
        lab.TextColor3 = Color3.fromRGB(140, 255, 170)
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.TextYAlignment = Enum.TextYAlignment.Top
        lab.Font = Enum.Font.Code
        lab.TextSize = 14
        lab.TextWrapped = false
        lab.RichText = false
        lab.Position = UDim2.fromOffset(10, 70)
        lab.Size = UDim2.fromOffset(420, 168)
        lab.Text = "JPAX FARM"
        lab.Parent = gui
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingTop = UDim.new(0, 6)
        pad.Parent = lab
        if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
            pcall(syn.protect_gui, gui)
        end
        gui.Parent = parent
        Autofarm._debugGui = gui
        Autofarm._debugLabel = lab
        return lab
    end)
    if not ok or not label then
        Autofarm._debugHudBlocked = true
        Autofarm._dbgErr = "overlay blocked (F9 still logs)"
        S.destroyFarmDebugHud()
        return nil
    end
    return label
end

function S.refreshFarmDebugHud()
    local ok, err = pcall(function()
        if Autofarm.debugHud ~= true then
            return
        end
        local label = S.ensureFarmDebugHud()
        if not label then
            return
        end
        local dir = S.getAutofarmAxisVector()
        local dirTxt = dir and string.format("%.2f,%.2f", dir.X, dir.Z) or "?"
        local origin = Autofarm.origin
        local originTxt = origin and string.format("%.0f,%.0f", origin.X, origin.Z) or "nil"
        label.Text = string.format(
            "JPAX FARM DEBUG  v%s\n%s  d=%.0f  spd=%d  y=%.1f\nhold: %s\nbusy=%s move=%s mine=%s cycle=%s\n%s\norigin %s  dir %s\nerr: %s",
            JPAX.version,
            Autofarm.enabled and "ON" or "OFF",
            Autofarm.distance or 0,
            S.getAutofarmSpeed(),
            S.getAutofarmFlyY(),
            S.farmHoldReason(),
            Autofarm.busy and "1" or "0",
            Autofarm.moving and "1" or "0",
            Autofarm.miningBusy and "1" or "0",
            Autofarm._cycleRunning and "1" or "0",
            Autofarm._dbgAction or "—",
            originTxt,
            dirTxt,
            Autofarm._dbgErr or "—"
        )
    end)
    if not ok then
        Autofarm._debugHudBlocked = true
        Autofarm._dbgErr = tostring(err)
    end
end

function S.farmLog(action, detail)
    local ok, err = pcall(function()
        local key = tostring(action or "?")
        local line = key
        if detail ~= nil and detail ~= "" then
            line = key .. " · " .. tostring(detail)
        end
        Autofarm._dbgAction = line
        local noisy = key == "glide" or key == "held" or key == "grace" or key == "cycle"
        local stamp = key
        if key == "held" then
            stamp = "held|" .. tostring(detail or "")
        end
        if Autofarm._dbgKey ~= stamp or not noisy then
            Autofarm._dbgKey = stamp
            print("[JPAX FARM]", line)
            if typeof(S.hubLog) == "function" then
                pcall(S.hubLog, "FARM " .. line)
            end
        end
        S.refreshFarmDebugHud()
    end)
    if not ok then
        Autofarm._dbgErr = tostring(err)
        pcall(print, "[JPAX FARM]", action, detail)
    end
end

function S.farmErr(action, err)
    pcall(function()
        Autofarm._dbgErr = tostring(err)
        warn("[JPAX FARM]", action, err)
        S.farmLog(action, err)
    end)
end

function S.autofarmInStartupGrace()
    local untilT = Autofarm._cruiseReadyAt
    return typeof(untilT) == "number" and tick() < untilT
end

function S.holdAutofarmCruise(reason)
    Autofarm.busy = true
    Autofarm._busySince = tick()
    Autofarm._holdReason = reason or "busy"
    S.farmLog("HOLD", Autofarm._holdReason)
end

function S.isAutofarmCruiseHeld()
    return Autofarm.busy == true
        or Autofarm._banditPause == true
        or Autofarm.moving == true
        or Autofarm.miningBusy == true
        or Autofarm._oreHuntMode == true
        or Autofarm._scrapProcessing == true
        or Autofarm._scrapFlushing == true
end

function S.stopJpaxRouteGlide()
    S.disconnectAll("autofarmGlide")
end

-- Continuous origin + track-axis glide. Distance only advances while nothing is holding us.
function S.startJpaxRouteGlide()
    S.stopJpaxRouteGlide()
    S.farmLog("glide start", string.format("spd=%d y=%.1f", S.getAutofarmSpeed(), S.getAutofarmFlyY()))
    local lastHud = 0
    State.connections.autofarmGlide = RunService.RenderStepped:Connect(function(dt)
        if not Autofarm.enabled then
            return
        end
        if S.isAutofarmCruiseHeld() then
            if os.clock() - lastHud > 0.25 then
                lastHud = os.clock()
                S.farmLog("held", S.farmHoldReason())
            end
            return
        end
        dt = math.min(math.max(dt or 0, 0), 0.05)
        local speed = S.getAutofarmSpeed()
        local mapEnd = Autofarm.mapEndStuds or 100000
        local nextD = (Autofarm.distance or 0) + speed * dt
        if nextD >= mapEnd then
            Autofarm._pendingMapWrap = true
            local ok, err = pcall(S.setAutofarmPose, 0)
            if not ok then
                S.farmErr("wrap pose", err)
            else
                S.farmLog("wrap", "map end → 0")
            end
            if CoreFarm.openAll or CoreFarm._ownedRun then
                S.coreNoteLap()
            end
            return
        end
        local ok, err = pcall(S.setAutofarmPose, nextD)
        if not ok then
            S.farmErr("pose", err)
            return
        end
        if os.clock() - lastHud > 0.35 then
            lastHud = os.clock()
            S.farmLog("glide", string.format("d=%.0f", nextD))
        end
    end)
end

function S.getAutofarmSettleWait()
    local speed = S.getAutofarmSpeed()
    return math.clamp(0.25 + (speed / 2000) * 0.85, 0.25, 1.15)
end

function S.getAutofarmSegmentLength()
    local speed = S.getAutofarmSpeed()
    return math.floor(math.clamp(480 - speed * 0.12, 120, 420))
end

function S.resetAutofarmCharacterState()
    S.cancelAutofarmTween()
    S.lockAutofarmHover(false)
    S.clearDragTarget()
    S.setAutofarmPlatformStand(false)

    local root = S.getRoot()
    if root then
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

function S.clearMineHoldPin()
    Autofarm._mineHoldPos = nil
    Autofarm._mineLookAt = nil
end

-- While miningBusy/furnace dump: NEVER freefall. Pin Y (and ore XZ) without
-- overwriting dig aim with the cruise look-along-track glue.
function S.pinBusyFarmHold(root)
    if not root then
        return
    end
    S.setAutofarmPlatformStand(true)
    root.Anchored = false
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero

    local pos = root.Position
    local pin = Autofarm._mineHoldPos
    local pinY = Autofarm._gatePinY
    if typeof(pinY) ~= "number" then
        pinY = (typeof(pin) == "Vector3" and pin.Y) or nil
    end
    -- No pin at all → snap to cruise flyY so we never sink to void mid-busy.
    if typeof(pinY) ~= "number" then
        pinY = S.getAutofarmFlyY()
    end

    local x, z = pos.X, pos.Z
    if typeof(pin) == "Vector3" then
        x, z = pin.X, pin.Z
    end

    local driftedY = pos.Y ~= pos.Y or math.abs(pos.Y - pinY) > 0.4
    local driftedXZ = typeof(pin) == "Vector3"
        and Vector3.new(pos.X - x, 0, pos.Z - z).Magnitude > 1.5
    if not driftedY and not driftedXZ then
        return
    end

    local stand = Vector3.new(x, pinY, z)
    local look = Autofarm._mineLookAt
    local cf
    if typeof(look) == "Vector3" and (look - stand).Magnitude > 0.1 then
        cf = S.safeLookAt(stand, look)
    else
        cf = S.safeLookAt(stand, stand + S.getAutofarmAxisVector())
    end
    if cf then
        root.CFrame = cf
    end
end

function S.hardRecoverAutofarmCruise(reason)
    warn("[TERRA HUB] hard recover cruise" .. (reason and (" — " .. tostring(reason)) or ""))
    S.farmLog("recover", reason)
    Autofarm._cycleAbort = true
    Autofarm._cycleRunning = false
    Autofarm.miningBusy = false
    Autofarm._miningBusySince = nil
    Autofarm._oreHuntMode = false
    Autofarm.moving = false
    S.suppressAutofarmMines(6)
    if Autofarm._activeMine then
        S.skipAutofarmMine(Autofarm._activeMine, 120, reason or "recover")
    else
        Autofarm._gatePinY = nil
    end
    S.clearMineHoldPin()
    pcall(S.releaseCharacterHold)
    pcall(S.cancelAutofarmTween)
    if not Autofarm.enabled then
        return
    end
    local dist = Autofarm.distance or 0
    pcall(function()
        S.setAutofarmPose(dist)
        S.setAutofarmPlatformStand(true)
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
        -- Second snap next frame — first can lose to residual physics.
        task.defer(function()
            if Autofarm.enabled and not Autofarm.miningBusy then
                S.setAutofarmPose(Autofarm.distance or dist)
            end
        end)
    end)
    pcall(S.startJpaxRouteGlide)
end

function S.ensureAutofarmAntiFall(on)
    S.disconnectAll("autofarmAntiFall")
    if not on then
        Autofarm._gatePinY = nil
        return
    end

    State.connections.autofarmAntiFall = RunService.Heartbeat:Connect(function()
        if not Autofarm.enabled then
            return
        end
        if Autofarm._banditUnder then
            return
        end
        if Reap and Reap.busy then
            return
        end

        local root = S.getRoot()
        if not root then
            return
        end

        -- Dig / furnace dump: pin height hard, don't use cruise look glue.
        if Autofarm.miningBusy or Autofarm._oreHuntMode or Autofarm._scrapProcessing then
            S.pinBusyFarmHold(root)
            return
        end

        S.setAutofarmPlatformStand(true)
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        local flyY = S.getAutofarmFlyY()
        local targetY = Autofarm._gatePinY
        if typeof(targetY) ~= "number" then
            targetY = flyY
        end

        local pos = root.Position
        local dir = S.getAutofarmAxisVector()

        -- Moving: setAutofarmPose owns XZ — only rescue Y if gravity ate you.
        if Autofarm.moving then
            if pos.Y ~= pos.Y or pos.Y < targetY - 1.5 then
                local cf = S.safeLookAt(Vector3.new(pos.X, targetY, pos.Z), Vector3.new(pos.X, targetY, pos.Z) + dir)
                if cf then
                    root.CFrame = cf
                end
            end
            return
        end

        -- Idle / gate / loot: glue height every frame (never freefall).
        -- Chest visits set _mineHoldPos so XZ stays on the chest, not the cruise line.
        local pin = Autofarm._mineHoldPos
        local x, z = pos.X, pos.Z
        if typeof(pin) == "Vector3" then
            x, z = pin.X, pin.Z
        end
        local hold = Vector3.new(x, targetY, z)
        local cf = S.safeLookAt(hold, hold + dir)
        if cf then
            root.CFrame = cf
        end
    end)
end

function S.lockAutofarmHover(enabled)
    Autofarm.hoverLocked = enabled == true
    S.disconnectAll("autofarmHover")

    -- While autofarm runs, NEVER release PlatformStand / anti-fall (void at flyY -15).
    if Autofarm.enabled then
        S.ensureAutofarmAntiFall(true)
        S.setAutofarmPlatformStand(true)
    end

    if not Autofarm.hoverLocked then
        if not Autofarm.enabled then
            S.ensureAutofarmAntiFall(false)
            S.setAutofarmPlatformStand(false)
            local root = S.getRoot()
            if root then
                root.Anchored = false
            end
        end
        return
    end

    -- Hold height WITHOUT Anchored — anchored HRP makes the server think you vanished.
    S.setAutofarmPlatformStand(true)
    State.connections.autofarmHover = RunService.Heartbeat:Connect(function()
        if not Autofarm.enabled or not Autofarm.hoverLocked then
            return
        end
        if Autofarm._banditUnder then
            return
        end
        if Reap and Reap.busy then
            return
        end
        if Autofarm.moving then
            return
        end
        local root = S.getRoot()
        if not root then
            return
        end

        if Autofarm.miningBusy or Autofarm._oreHuntMode or Autofarm._scrapProcessing then
            S.pinBusyFarmHold(root)
            return
        end

        local dir = S.getAutofarmAxisVector()
        local flyY = Autofarm._gatePinY or S.getAutofarmFlyY()
        local pos = root.Position
        local pin = Autofarm._mineHoldPos
        local x, z = pos.X, pos.Z
        if typeof(pin) == "Vector3" then
            x, z = pin.X, pin.Z
        end
        local hold = Vector3.new(x, flyY, z)
        root.Anchored = false
        local cf = S.safeLookAt(hold, hold + dir)
        if cf then
            root.CFrame = cf
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        S.setAutofarmPlatformStand(true)
    end)
end

function S.setAutofarmPose(distance)
    local root = S.getRoot()
    local cf = S.getAutofarmCFrame(distance)
    if not root or not cf then
        return false
    end

    root.Anchored = false
    if Autofarm.enabled then
        S.setAutofarmPlatformStand(true)
    end
    root.CFrame = cf
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    Autofarm.distance = distance or 0
    return true
end

function S.syncAutofarmDistanceFromRoot()
    local root = S.getRoot()
    local origin = Autofarm.origin
    if not root or not origin then
        return Autofarm.distance or 0
    end

    local dir = S.getAutofarmAxisVector()
    local rel = root.Position - origin
    local flat = Vector3.new(rel.X, 0, rel.Z)
    local dist = math.max(0, flat:Dot(dir))
    local mapEnd = Autofarm.mapEndStuds or (DEPTH_TARGET_END_METERS * S.getAutofarmStudsPerMeter())
    Autofarm.distance = math.clamp(dist, 0, mapEnd)
    return Autofarm.distance
end

function S.snapAutofarmAxisFromLook()
    local root = S.getRoot()
    if not root then
        return Autofarm.routeDir or S.getAutofarmAxisVectorFromString()
    end

    local look = root.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.05 then
        flat = Vector3.new(0, 0, 1)
    else
        flat = flat.Unit
    end

    -- Store as base Track-less fallback; Forward/Backward still applies.
    Autofarm.routeDirBase = flat
    return S.getAutofarmAxisVector()
end

function S.ensureAutofarmOrigin(force)
    local root = S.getRoot()
    if not root then
        return false
    end

    if force or not Autofarm.origin then
        Autofarm.origin = Vector3.new(root.Position.X, S.getAutofarmFlyY(), root.Position.Z)
    end
    return true
end

-- Next Enable Autofarm (or mid-run) starts from the character's current XZ.
function S.resetAutofarmStart()
    local root = S.getRoot()
    if not root then
        return false
    end

    S.cancelAutofarmTween()
    Autofarm.miningBusy = false
    Autofarm.suppressChestOreStopUntil = 0
    Autofarm.origin = Vector3.new(root.Position.X, S.getAutofarmFlyY(), root.Position.Z)
    Autofarm.distance = 0
    S.refreshAutofarmRouteDir()

    if Autofarm.enabled then
        S.setAutofarmPose(0)
        S.setAutofarmPlatformStand(true)
    end

    return true
end

function S.findAutofarmSellPart(fromPos)
    local sellPart = S.findNearestSellPart(fromPos)
    if sellPart then
        return sellPart
    end

    local village = S.findNearestVillage()
    if village then
        local part = village:FindFirstChild("SellPart", true)
        if part and part:IsA("BasePart") then
            return part
        end
    end

    return nil
end

-- Leave dungeon / stream village so SellPart exists before selling.
-- Prefers the SellPart closest to where the bag filled (fromPos).
function S.ensureTownSellPart(fromPos)
    pcall(S.exitDungeonToLine)

    local root = S.getRoot()
    fromPos = fromPos or Autofarm.sellFromPos or (root and root.Position)

    local sellPart = S.findAutofarmSellPart(fromPos)
    if sellPart then
        return sellPart
    end

    local village = S.findNearestVillage()
    if village and root then
        local cf = S.getVillageEntranceCFrame(village)
        if not cf then
            local pos = S.getInstancePosition(village) or village:GetPivot().Position
            cf = CFrame.new(pos.X, S.getGroundY(pos) + 4, pos.Z)
        end
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = cf
        S.requestStreamAround(cf.Position, 2.5)
        task.wait(1.0)
        sellPart = village:FindFirstChild("SellPart", true)
        if sellPart and sellPart:IsA("BasePart") then
            return sellPart
        end
    end

    sellPart = S.findAutofarmSellPart(fromPos)
    if sellPart then
        return sellPart
    end

    if Autofarm.origin and root then
        root.CFrame = CFrame.new(Autofarm.origin)
        S.requestStreamAround(Autofarm.origin, 2)
        task.wait(0.8)
    end

    return S.findAutofarmSellPart(fromPos)
end

-- Cam through walls + longer zoom while autofarming.
function S.setAutofarmCameraAssist(enabled)
    if enabled then
        if Autofarm.ownedCamAssist then
            return
        end
        Autofarm.camBackup = {
            maxZoom = LocalPlayer.CameraMaxZoomDistance,
            minZoom = LocalPlayer.CameraMinZoomDistance,
        }
        pcall(function()
            LocalPlayer.CameraMaxZoomDistance = math.max(tonumber(Autofarm.camBackup.maxZoom) or 128, 500)
            LocalPlayer.CameraMinZoomDistance = math.min(tonumber(Autofarm.camBackup.minZoom) or 0.5, 0.5)
        end)
        Autofarm.ownedCamAssist = true
        return
    end

    if not Autofarm.ownedCamAssist then
        return
    end
    local bak = Autofarm.camBackup
    pcall(function()
        if bak then
            LocalPlayer.CameraMaxZoomDistance = bak.maxZoom or 128
            LocalPlayer.CameraMinZoomDistance = bak.minZoom or 0.5
        end
    end)
    Autofarm.camBackup = nil
    Autofarm.ownedCamAssist = false
end

-- Autofarm loot reach — same Auto Loot method, max practical flat range.
function S.getAutofarmLootRange()
    return math.max(tonumber(Autofarm.lootRange) or 10000, S.getLootMaxRange() or 0)
end

-- Same target rules as runLootCycle / Auto Loot tab.
-- Cruise-stop uses a SHORT range so distant Items don't softlock you mid-air.
function S.hasAutofarmLootInRange(range)
    if not Autofarm.enabled then
        return false
    end
    -- Run is tween-only unless Auto Loot is on. Scrap keeps its own loot sweep.
    if Loot.enabled ~= true and not S.isScrapFarmMode() then
        return false
    end
    range = tonumber(range) or S.getAutofarmCruiseStopRange()
    local targets = S.collectLootTargets()
    for _, item in ipairs(targets) do
        if not S.shouldSkipAutoLoot(item) then
            local pos = S.getItemPosition(item)
            if pos and S.getFlatDistanceFromPosition(pos) <= range then
                return true
            end
        end
    end
    return false
end

function S.returnToAutofarmPocket()
    local dist = Autofarm.resumePocketDistance
    if dist == nil then
        dist = Autofarm.distance or 0
    end
    Autofarm.distance = dist
    if Autofarm.enabled then
        S.setAutofarmPose(dist)
        S.setAutofarmPlatformStand(true)
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
    end
    local root = S.getRoot()
    if root and Autofarm.resumePocketPos then
        pcall(function()
            S.requestStreamAround(Autofarm.resumePocketPos, 2)
        end)
    end
end

-- Stop and loot exactly like Auto Loot tab (runLootCycle), max range, ultra fast.
function S.autofarmLootPass()
    if not Autofarm.enabled then
        return 0
    end

    S.cancelAutofarmTween()
    S.lockAutofarmHover(true)
    S.ensureAutofarmAntiFall(true)
    S.setAutofarmPlatformStand(true)
    Loot.autoDropAfterLoot = false
    Loot.autoEquipBag = false

    local range = S.getAutofarmLootRange()
    local looted = 0
    local empty = 0

    for _ = 1, 48 do
        if not Autofarm.enabled then
            break
        end
        if S.isBagFull() then
            break
        end

        S.ensureItemBag()
        S.ensureBagReadyForLoot()
        local bag = S.getEquippedTool()
        if bag and S.isItemBagTool(bag) then
            S.boostToolRange(bag, range)
        end

        local before = S.getBagFillCount()
        local got = S.runLootCycle({
            fast = true,
            nearRange = range,
            batchSize = 64,
        }) or 0

        local after = S.getBagFillCount()
        if got > 0 or after > before then
            looted += math.max(got, after - before)
            empty = 0
        else
            empty += 1
            if empty >= 3 then
                break
            end
        end
        task.wait()
    end

    S.flushAutofarmDrillDropIfNeeded()
    return looted
end

-- Move one dropped world item onto the drill truck bed + Weld (Z).
function S.sendItemToDrillBed(item, parkIndex)
    if not item or not item.Parent then
        return false
    end

    local bed = S.getDrillBedWeldPart()
    local drill = S.getDrill()
    if not bed and not drill then
        return false
    end

    local park = S.getDrillBedParkCFrame(parkIndex)
        or (drill and CFrame.new(drill:GetPivot().Position + Vector3.new(0, 2, 0)))
    if not park then
        return false
    end

    S.moveItemToCFrame(item, park)
    task.wait(0.06)
    if S.weldItem(item) then
        return true
    end
    if bed then
        S.moveItemToCFrame(item, bed.CFrame * CFrame.new(0, bed.Size.Y * 0.5 + 1.2, 0))
        task.wait(0.05)
        S.weldItem(item)
    end
    return item.Parent ~= nil
end

function S.flushAutofarmDrillDropIfNeeded()
    Autofarm._pendingDrillDrop = false
    return 0
end

-- Dump ENTIRE sack onto drill truck bed + Weld (Drop in Drill mode), then resume pocket.
function S.autofarmDumpBagToDrill()
    if not Autofarm.enabled or not S.isDropInDrillMode() then
        return 0
    end
    if not Services.ToolService then
        return 0
    end

    local bed = S.getDrillBedWeldPart()
    local drill = S.getDrill()
    if not bed and not drill then
        S.notify("Autofarm", "Drill bed not found", 3)
        return 0
    end

    local root = S.getRoot()
    S.cancelAutofarmTween()
    Autofarm.resumePocketDistance = Autofarm.distance or S.syncAutofarmDistanceFromRoot()
    Autofarm.resumePocketPos = root and root.Position or nil

    local function standAtTrailer()
        root = S.getRoot()
        if not root then
            return
        end
        local stand = S.getDrillTrailerStandPosition()
            or (bed and (bed.Position + S.getDrillTrailerBackDirection(bed, drill) * 12 + Vector3.new(0, 4, 0)))
            or (drill and (drill:GetPivot().Position + Vector3.new(0, 5, 0)))
        if not stand then
            return
        end
        Autofarm._gatePinY = stand.Y
        root.Anchored = false
        root.CFrame = CFrame.new(stand)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        S.setAutofarmPlatformStand(true)
        if not Autofarm._farmShuttingDown then
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
        end
        S.requestStreamAround(stand, 0.8)
    end

    local function atTrailer()
        local rootNow = S.getRoot()
        local stand = S.getDrillTrailerStandPosition()
        if not rootNow or not stand then
            return false
        end
        local flat = (Vector3.new(rootNow.Position.X, 0, rootNow.Position.Z) - Vector3.new(stand.X, 0, stand.Z)).Magnitude
        return flat <= 16 and math.abs(rootNow.Position.Y - stand.Y) <= 18
    end

    local function dropOnlyAtTrailer()
        if not atTrailer() then
            standAtTrailer()
            task.wait(0.08)
        end
        if not atTrailer() then
            return false
        end
        S.bagDrop()
        return true
    end

    standAtTrailer()
    S.clearDragTarget()
    S.ensureItemBag()
    pcall(function()
        local update = Services.ToolService.Update
        if update and update.Fire then
            local _ = update -- (sack dihapus)
        end
    end)
    task.wait(0.05)

    local dumped = 0
    local parkIndex = 0
    local stalls = 0

    for _ = 1, 220 do
        if not Autofarm.enabled or not S.isDropInDrillMode() then
            break
        end
        local before = S.getBagFillCount()
        if before <= 0 then
            break
        end

        standAtTrailer()
        S.ensureItemBag(true)
        local beforeSet = S.snapshotItemsSet()
        if not dropOnlyAtTrailer() then
            S.notify("Autofarm", "Drop in Drill — still on the map, not dropping", 3)
            break
        end

        local item = nil
        local confirmed = false
        for _ = 1, 12 do
            task.wait()
            local news = S.findNewWorldItems(beforeSet)
            if news[1] then
                item = news[1]
                confirmed = true
                break
            end
            if S.getBagFillCount() < before then
                confirmed = true
                break
            end
            if not dropOnlyAtTrailer() then
                break
            end
        end

        if item and item.Parent then
            if S.sendItemToDrillBed(item, parkIndex) then
                dumped += 1
                parkIndex += 1
                stalls = 0
            else
                stalls += 1
            end
        elseif confirmed then
            stalls = 0
            dumped += math.max(0, before - S.getBagFillCount())
        else
            pcall(function()
                local update = Services.ToolService.Update
                if update and update.Fire then
                    local _ = update -- (sack dihapus)
                end
            end)
            stalls += 1
            if stalls >= 10 then
                break
            end
        end
    end

    -- Final pass: empty anything still counted in the sack UI.
    for _ = 1, 16 do
        if S.getBagFillCount() <= 0 then
            break
        end
        standAtTrailer()
        S.ensureItemBag(true)
        local beforeSet = S.snapshotItemsSet()
        local before = S.getBagFillCount()
        if not dropOnlyAtTrailer() then
            break
        end
        task.wait(0.05)
        local news = S.findNewWorldItems(beforeSet)
        if news[1] and news[1].Parent then
            if S.sendItemToDrillBed(news[1], parkIndex) then
                dumped += 1
                parkIndex += 1
            end
        elseif S.getBagFillCount() >= before then
            break
        end
    end

    pcall(S.autoLockTruckCycle)

    Autofarm._gatePinY = nil
    Money.trackedBagAt = Money.trackedBagAt or os.clock()
    Autofarm.distance = Autofarm.resumePocketDistance or Autofarm.distance or 0
    if Autofarm.enabled and not Autofarm._farmShuttingDown then
        S.returnToAutofarmPocket()
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
    end

    local left = S.getBagFillCount()
    if left > 0 then
        S.notify("Autofarm", "Dropped " .. tostring(dumped) .. " — bag still " .. tostring(left), 4)
    else
        S.notify("Autofarm", "Dropped full sack (" .. tostring(dumped) .. ") · resumed", 3)
    end
    return dumped
end

-- Dump sack onto ScrapShredder (Dump for Scrap mode).
function S.autofarmDumpBagToShredder()
    if not Autofarm.enabled or not S.isDropInShredderMode() then
        return 0
    end

    local shredder = S.findScrapShredderPart()
    if not shredder then
        S.notify("Autofarm", "ScrapShredder not found", 3)
        return 0
    end

    S.notify("Autofarm", "Drops — shredder", 2)
    local dumped = S.dumpBagOntoPart(shredder, "Shredder", nil, {})

    Autofarm._gatePinY = nil
    Money.trackedBagAt = Money.trackedBagAt or os.clock()
    Autofarm.distance = Autofarm.resumePocketDistance or Autofarm.distance or 0
    if Autofarm.enabled then
        S.returnToAutofarmPocket()
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
    end

    local left = S.getBagFillCount()
    if left > 0 then
        S.notify("Autofarm", "Shredded " .. tostring(dumped) .. " — bag still " .. tostring(left), 4)
    else
        S.notify("Autofarm", "Shredded sack (" .. tostring(dumped) .. ") · resumed", 3)
    end
    return dumped
end

-- Dump ENTIRE sack onto TradeSell (Auto Sell mode only).
function S.autofarmAutoSell()
    if not Autofarm.enabled or not Autofarm.autoSell or S.isDropInDrillMode() or S.isDropInShredderMode() then
        return 0, 0
    end

    local root = S.getRoot()
    if not root then
        return 0, 0
    end

    S.cancelAutofarmTween()
    S.ensureAutofarmAntiFall(true)
    S.setAutofarmPlatformStand(true)
    S.lockAutofarmHover(true)
    S.clearDragTarget()

    Autofarm.resumePocketDistance = Autofarm.distance or S.syncAutofarmDistanceFromRoot()
    Autofarm.resumePocketPos = root.Position
    Autofarm.sellFromPos = root.Position
    Autofarm._pendingDrillDrop = false

    local sellPart = S.findNearestSellPart(Autofarm.sellFromPos)
        or S.ensureTownSellPart(Autofarm.sellFromPos)
    if not sellPart then
        S.notify("Autofarm", "Sell post not found", 3)
        return 0, 0
    end

    S.snapCharacterOntoTradeSell(sellPart)
    S.ensureAutofarmAntiFall(true)
    S.lockAutofarmHover(true)

    S.ensureItemBag()
    pcall(function()
        local update = Services.ToolService and Services.ToolService.Update
        if update and update.Fire then
            local _ = update -- (sack dihapus)
        end
    end)

    local sold = 0
    for _ = 1, 220 do
        if not Autofarm.enabled then
            break
        end
        local before = S.getBagFillCount()
        if before <= 0 then
            break
        end

        S.snapCharacterOntoTradeSell(sellPart)
        S.ensureItemBag()
        S.bagDrop()
        S.forceDropsOntoTradeSell(sellPart)

        local confirmed = false
        for _ = 1, 10 do
            task.wait()
            S.forceDropsOntoTradeSell(sellPart)
            local after = S.getBagFillCount()
            if after < before then
                sold += (before - after)
                confirmed = true
                break
            end
            S.bagDrop()
        end

        if not confirmed then
            pcall(function()
                local update = Services.ToolService and Services.ToolService.Update
                if update and update.Fire then
                    local _ = update -- (sack dihapus)
                end
            end)
            S.snapCharacterOntoTradeSell(sellPart)
            S.bagDrop()
            S.forceDropsOntoTradeSell(sellPart)
            task.wait()
        end
    end

    for _ = 1, 12 do
        if S.getBagFillCount() <= 0 then
            break
        end
        S.snapCharacterOntoTradeSell(sellPart)
        S.bagDrop()
        S.forceDropsOntoTradeSell(sellPart)
        task.wait()
    end

    Autofarm._gatePinY = nil

    local sacks = 0
    if S.getBagFillCount() <= 0 then
        sacks = S.collectSellMoneySacks(sellPart, math.max(sold, 1), 90) or 0
    else
        S.notify("Autofarm", "Bag not empty — skip bags", 3)
    end

    Money.trackedBagAt = Money.trackedBagAt or os.clock()
    Autofarm.sellFromPos = nil
    Autofarm.distance = Autofarm.resumePocketDistance or Autofarm.distance or 0
    Autofarm._gatePinY = nil

    if Autofarm.enabled then
        S.returnToAutofarmPocket()
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
    end

    return sold, sacks
end

function S.autofarmSellTrip()
    return S.autofarmAutoSell()
end

function S.getMineEntranceWorldPos(mine)
    if not mine then
        return nil
    end
    local hit, gate = S.getMineEntranceHitbox(mine)
    local pos = hit and S.getInstancePosition(hit)
    if pos then
        return pos
    end
    pos = gate and S.getInstancePosition(gate)
    if pos then
        return pos
    end
    -- Last resort: same point ESP uses for the mine label.
    return S.getInstancePosition(mine) or S.getEspWorldPosition(mine)
end

-- Hold cruise Y at EntranceHitbox XZ (firm).
function S.holdAutofarmAtEntrance(mine)
    if S.autofarmVisitStale() then
        return false
    end
    local root = S.getRoot()
    local pos = S.getMineEntranceWorldPos(mine)
    if not root or not pos then
        return false
    end
    local flyY = S.getAutofarmFlyY()
    local dir = S.getAutofarmAxisVector()
    Autofarm._gatePinY = flyY
    local hold = Vector3.new(pos.X, flyY, pos.Z)
    root.Anchored = false
    root.CFrame = CFrame.lookAt(hold, hold + dir)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    S.setAutofarmPlatformStand(true)
    S.ensureAutofarmAntiFall(true)
    S.lockAutofarmHover(true)
    return true
end

-- StreamingEnabled: loot/ores inside a shaft often don't exist client-side until probed.
function S.streamMineInterior(mine, steps, stepStuds)
    if not mine then
        return
    end
    steps = math.clamp(tonumber(steps) or 10, 3, 24)
    stepStuds = math.clamp(tonumber(stepStuds) or 90, 40, 200)

    local entrance = S.getMineEntranceWorldPos(mine)
    local heading, _, hitPos = S.getMineExploreHeading(mine)
    local origin = hitPos or entrance
    if not origin then
        return
    end

    local flyY = S.getAutofarmFlyY()
    heading = heading or S.getAutofarmAxisVector()

    for i = 0, steps do
        if S.autofarmCycleShouldAbort() then
            return
        end
        local probe = origin + heading * (stepStuds * i)
        probe = Vector3.new(probe.X, flyY, probe.Z)
        pcall(function()
            S.requestStreamAround(probe, 0.4)
        end)
        task.wait(0.06)
    end

    if entrance then
        pcall(function()
            S.requestStreamAround(entrance, 0.8)
        end)
    end
end

-- Join Mines discovery (flat dist). Caps at mineDetectRange so cruise doesn't pull mines from across the map.
function S.getAutofarmMineDetectRange()
    return math.clamp(tonumber(Autofarm.mineDetectRange) or 3000, 500, 5000)
end

function S.collectAutofarmMinesLikeEsp()
    local range = S.getAutofarmMineDetectRange()
    local list = {}

    S.scanWorldModels(function(inst)
        if not S.isMineRoot(inst) then
            return
        end
        local espDist = S.getFlatDistanceToPlayer(inst)
        if espDist > range then
            return
        end
        local travel = S.getMineEntranceWorldPos(inst)
        if not travel then
            return
        end
        table.insert(list, {
            mine = inst,
            espDist = espDist,
            travel = travel,
            travelDist = S.getFlatDistanceFromPosition(travel),
        })
    end)

    return list
end

-- Mine within mineDetectRange (~3k) + travel to EntranceHitbox.
function S.findMineBesideOnCruise()
    local root = S.getRoot()
    if not root or Autofarm.enterMines == false then
        return nil
    end
    if tick() < (Autofarm.suppressMinesUntil or 0) then
        return nil
    end

    local skips = Autofarm.skipMinesUntil or {}
    local now = tick()
    local best, bestDist = nil, math.huge
    local range = S.getAutofarmMineDetectRange()

    for _, entry in ipairs(S.collectAutofarmMinesLikeEsp()) do
        local mine = entry.mine
        if not (skips[mine] and now < skips[mine]) then
            -- Prefer entrance reach; fallback espDist so nearby mines still count.
            local dist = entry.travelDist
            if typeof(dist) ~= "number" or dist ~= dist then
                dist = entry.espDist
            end
            if dist <= range and dist < bestDist then
                bestDist = dist
                best = mine
            end
        end
    end

    return best
end

-- Masuk ke DALAM mine: dari EntranceHitbox maju searah LookVector (arah ke dalam shaft).
-- Tiap langkah di-stream supaya ore interior ter-load dan bisa terdeteksi. Hover lock
-- (Autofarm._mineHoldPos + _gatePinY) menahan posisi di dalam; leave() melepasnya lagi.
function S.autofarmEnterMineInterior(mine, entrance)
    if not mine then
        return false
    end
    local hit = S.getMineEntranceHitbox(mine)
    local heading = S.getMineExploreHeading(mine)
    local base = (hit and S.getInstancePosition(hit)) or entrance
    if not base then
        return false
    end
    if typeof(heading) ~= "Vector3" or heading.Magnitude < 0.05 then
        heading = S.getAutofarmAxisVector()
    end
    heading = Vector3.new(heading.X, 0, heading.Z).Unit

    local depth = math.clamp(tonumber(Autofarm.mineEnterDepth) or 220, 40, 600)
    local stepStuds = 16
    local insideY = base.Y + 3
    local wantOres = (Autofarm.oreUnderEnabled == true or S.isScrapGoldPhase())
        and type(S.getAutofarmActiveOreTypes()) == "table"
        and #S.getAutofarmActiveOreTypes() > 0

    S.farmLog("mine enter", mine.Name)
    local reached = 0
    for d = 0, depth, stepStuds do
        if not Autofarm.enabled or S.autofarmVisitStale() or S.autofarmCycleShouldAbort() then
            break
        end
        local root = S.getRoot()
        if not root then
            break
        end
        local p = base + heading * d
        local hold = Vector3.new(p.X, insideY, p.Z)
        Autofarm._gatePinY = insideY
        Autofarm._mineHoldPos = hold
        local cf = S.safeLookAt(hold, hold + heading)
        root.Anchored = false
        if cf then
            root.CFrame = cf
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        S.setAutofarmPlatformStand(true)
        pcall(function()
            S.requestStreamAround(hold, 0.5)
        end)
        task.wait(0.08)
        reached = d
        -- Ore yang dipilih sudah terdeteksi di dekat sini -> cukup, biar dig pass yang lanjut.
        if wantOres and d >= 32 and #S.collectAutofarmSelectedOres(60) > 0 then
            break
        end
    end
    pcall(function()
        local r = S.getRoot()
        if r then
            S.requestStreamAround(r.Position, 1.2)
        end
    end)
    S.farmLog("mine inside", string.format("depth=%d", reached))
    return reached > 0
end

-- Tween to Gate_Mineshaft.EntranceHitbox → go inside → short dig → leave. Never re-pin.
function S.autofarmVisitMine(mine)
    if not mine or S.autofarmCycleShouldAbort() then
        return false
    end

    local entrance = S.getMineEntranceWorldPos(mine)
    if not entrance then
        return false
    end

    local savedDist = Autofarm.distance or S.syncAutofarmDistanceFromRoot()
    local root = S.getRoot()
    Autofarm.resumePocketDistance = savedDist
    Autofarm.resumePocketPos = root and root.Position or entrance
    Autofarm._activeMine = mine
    Autofarm._visitGen = Autofarm._cycleGen

    local function leave(why, skipSec)
        Autofarm._mineHoldPos = nil
        Autofarm._gatePinY = nil
        local stale = Autofarm._cycleGen ~= Autofarm._visitGen
        S.skipAutofarmMine(mine, skipSec or 90, why)
        S.suppressAutofarmMines(4)
        -- Stale visit after watchdog: don't snap back onto the mine track.
        if not stale and Autofarm.enabled and not S.autofarmCycleShouldAbort() then
            Autofarm.distance = savedDist
            S.setAutofarmPose(savedDist)
            S.setAutofarmPlatformStand(true)
            S.ensureAutofarmAntiFall(true)
            S.lockAutofarmHover(true)
        end
        S.farmLog("mine leave", why or mine.Name)
        return why == "done"
    end

    S.cancelAutofarmTween()
    S.ensureAutofarmAntiFall(true)
    S.lockAutofarmHover(true)

    S.farmLog("mine go", mine.Name)
    S.autofarmTweenTowardWorldPos(entrance)
    if S.autofarmVisitStale() then
        return leave("abort", 75)
    end
    root = S.getRoot()
    local arriveFlat = 9999
    if root then
        arriveFlat = Vector3.new(root.Position.X - entrance.X, 0, root.Position.Z - entrance.Z).Magnitude
        end
    if arriveFlat > 55 then
        S.farmLog("mine miss", string.format("flat=%.0f", arriveFlat))
        return leave("miss", 90)
    end
    S.holdAutofarmAtEntrance(mine)
    pcall(function()
        S.requestStreamAround(entrance, 1.5)
    end)
    pcall(function()
        S.streamMineInterior(mine, 8, 90)
    end)
    task.wait(0.2)
    if S.autofarmVisitStale() then
        return leave("stale", 90)
    end

    -- Join Mines = benar-benar masuk ke dalam mine supaya ore/chest interior ter-load.
    local enteredInside = false
    if Autofarm.mineEnterInside ~= false then
        enteredInside = S.autofarmEnterMineInterior(mine, entrance) == true
        if S.autofarmVisitStale() then
            return leave("stale", 90)
        end
    end

    if S.coreChestsOnly() then
        local guard = 0
        while Autofarm.enabled and Autofarm.openChests and guard < 8 do
            local inside = S.findChestForAutofarm()
            if not inside then
                break
            end
            S.autofarmVisitChest(inside)
            guard += 1
        end
        return leave("done", 90)
    end

    local wantOres = (Autofarm.oreUnderEnabled == true or S.isScrapGoldPhase())
        and type(S.getAutofarmActiveOreTypes()) == "table"
        and #S.getAutofarmActiveOreTypes() > 0
    if wantOres then
        pcall(function()
            S.requestStreamAround(entrance, 1.0)
        end)
        local digRange = enteredInside and 240 or 160
        if #S.collectAutofarmSelectedOres(digRange) > 0 then
            S.autofarmUnderMinePass({ range = digRange, seconds = enteredInside and 10 or 6 })
        end
        if S.autofarmVisitStale() then
            return leave("stale", 90)
        end
        if S.isScrapGoldPhase() then
            S.yankScrapGoldLootNearby(600)
        end
        if S.isAutofarmBagReadyToScrapProcess() then
            S.scrapSmeltAndShredCycle()
        end
    end

    -- One short loot sweep — do not re-dig or re-pin at the gate.
    local linger = os.clock() + (S.isScrapGoldPhase() and 1.2 or 2)
    while Autofarm.enabled and os.clock() < linger do
        if S.autofarmVisitStale() then
            return leave("stale", 90)
        end
        if S.isScrapGoldPhase() and S.hasScrapGoldLootNearby(400) then
            S.yankScrapGoldLootNearby(600)
        elseif S.hasAutofarmLootInRange() then
            S.autofarmLootPass()
            else
                break
            end
        if S.isAutofarmBagReadyToScrapProcess() then
            S.scrapSmeltAndShredCycle()
                break
            end
        end

    return leave("done", 90)
end

function S.runScrapFarmCycle()
    if not Services.ToolService or not Autofarm.enabled then
        return
    end

    if S.autofarmInStartupGrace() then
        S.farmLog("grace", "scrap glide only")
        S.ensureAutofarmOrigin(false)
        return
    end

    S.ensureAutofarmOrigin(false)
    S.syncAutofarmWindowFromDrill()
    S.ensureAutofarmAntiFall(true)
    S.lockAutofarmHover(true)

    -- Seek phase: Auto Equip Best (pickaxe + sword + armor), wide mine scan.
    if S.isScrapSeekPhase() then
        if not Autofarm.autoEquipBest then
            S.setAutofarmEquipBest(true)
        end
        GearEquip.range = GEAR_EQUIP_MAX_STUDS
        S.scrapSeekEquipPickaxesNearby(GEAR_EQUIP_MAX_STUDS)

        if S.hasScrapMinPickaxe() then
            S.holdAutofarmCruise("scrap gold phase")
            S.beginScrapGoldFarm(false)
            return
        end

        if Autofarm.scrapPhase == "chest_hunt" then
            local chest = S.findScrapChestForHunt() or S.findChestForAutofarm()
            if chest then
                S.holdAutofarmCruise("scrap chest")
                S.autofarmVisitChest(chest)
                S.scrapSeekEquipPickaxesNearby(500)
                if S.hasScrapMinPickaxe() then
                    S.beginScrapGoldFarm(false)
                end
                return
            end
        end

        local mine = S.findMineBesideOnCruise()
        if mine then
            S.holdAutofarmCruise("scrap seek mine")
            if S.scrapSeekMinePass(mine) or S.hasScrapMinPickaxe() then
                S.beginScrapGoldFarm(false)
            end
            return
        end
    else
        -- Smelt phase: only selected ore nodes + matching ore/bar loot.
        if Autofarm._scrapProcessing or Autofarm._scrapFlushing then
            return
        end
        if GearEquip.enabled and GearEquip._ownedByAutofarm then
            -- Keep equip off so runLootCycle doesn't teleport gear to you.
            GearEquip.enabled = false
        end

        if S.isAutofarmBagReadyToScrapProcess() then
            S.holdAutofarmCruise("scrap smelt")
            S.scrapSmeltAndShredCycle()
            return
        end

        -- After furnace/shred cooldown, don't instantly re-enter mines/ores.
        if tick() < (Autofarm._scrapCooldownUntil or 0) then
            return
        end

        local ore, orePos = S.findOreForAutofarm()
        if ore then
            S.holdAutofarmCruise("scrap ore")
            S.autofarmVisitOre(ore, orePos)
            S.suppressAutofarmMines(5)
            if S.isAutofarmBagReadyToScrapProcess() then
                S.scrapSmeltAndShredCycle()
            end
            return
        end

        local mine = S.findMineBesideOnCruise()
        if mine then
            S.holdAutofarmCruise("scrap mine")
            S.autofarmVisitMine(mine)
            if S.isAutofarmBagReadyToScrapProcess() then
                S.scrapSmeltAndShredCycle()
            end
            return
        end

        if S.hasScrapGoldLootNearby(600) then
            S.holdAutofarmCruise("scrap loot")
            S.yankScrapGoldLootNearby(900)
            if S.isAutofarmBagReadyToScrapProcess() then
                S.scrapSmeltAndShredCycle()
            end
            return
        end
    end

    if not Autofarm._pendingMapWrap then
        return
    end
    Autofarm._pendingMapWrap = false

        if S.isScrapSeekPhase() then
            Autofarm.scrapSeekLaps = (Autofarm.scrapSeekLaps or 0) + 1
            local laps = Autofarm.scrapSeekLaps
            local need = math.max(1, tonumber(Autofarm.scrapSeekMinLaps) or 2)

            if Autofarm.scrapPhase == "chest_hunt" and S.hasScrapDiamondPickaxe() then
            S.holdAutofarmCruise("scrap diamond pick")
                S.beginScrapGoldFarm(false)
                return
            end
            if Autofarm.scrapPhase ~= "chest_hunt" and S.hasScrapVoidPickaxe() then
            S.holdAutofarmCruise("scrap void pick")
                S.beginScrapGoldFarm(false)
                return
            end

            if laps == 1 then
                Autofarm.scrapPhase = "chest_hunt"
                Autofarm.openChests = true
                Autofarm.chestTypes = table.clone and table.clone(SCRAP_CHEST_ORDER) or {
                    "Void", "Diamond", "Gold", "Steel", "Core", "Mimic",
                    "Rusty", "Common", "Free", "TutorialCommon",
                }
                S.trySetRayfieldFlag("terra_af_auto_chests", true)
                S.notify("Scrap Farm", "Lap 1 done — chests Void→Diamond→…", 4)
            elseif laps >= need then
            S.holdAutofarmCruise("scrap laps done")
                S.beginScrapGoldFarm(true)
                return
            end
        else
            S.notify("Scrap Farm", "Map end — continuing", 3)
    end
end

-- Cruise + loot + sell / drop-in-drill. Built into Enable Autofarm.
function S.runAutofarmCycle()
    if Reap and Reap.sell then
        return
    end
    if not Services.ToolService then
        return
    end

    if S.isScrapFarmMode() then
        S.farmLog("cycle", "scrap")
        S.runScrapFarmCycle()
        return
    end

    if S.autofarmInStartupGrace() then
        S.farmLog("grace", string.format("%.1fs", (Autofarm._cruiseReadyAt or 0) - tick()))
        S.ensureAutofarmOrigin(false)
        return
    end

    if type(CoreFarm) == "table" and (CoreFarm.openAll or CoreFarm._ownedRun) and not CoreFarm._leaving then
        S.coreHoldChestRun()
    end

    S.ensureAutofarmOrigin(false)
    local windowChanged, winStartM, winEndM = S.syncAutofarmWindowFromDrill()
    if windowChanged and Autofarm.enabled then
        S.notify(
            "Autofarm",
            string.format("Farm window %dk–%dk m (drill)", math.floor(winStartM / 1000), math.floor(winEndM / 1000)),
            4
        )
    end
    if Autofarm.enabled then
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
    end

    if S.coreChestsOnly() and Loot.enabled then
        S.setAutoLoot(false)
        S.trySetRayfieldFlag("terra_auto_loot", false)
    end

    if not S.coreChestsOnly() and S.isAutofarmBagReadyToDumpAny() then
        S.holdAutofarmCruise("dump bag")
        S.runAutofarmThresholdDumpIfReady()
        return
    end

    -- Auto Ores: don't run Equip Best every cycle (bring/interact softlocks cruise for 20-40s).
    if not S.coreChestsOnly() and Autofarm.autoEquipBest and not Autofarm.oreUnderEnabled then
        GearEquip.categories = { "Pickaxe", "Sword", "Armor", "Gun" }
        GearEquip.range = GEAR_EQUIP_MAX_STUDS
        if not GearEquip.enabled then
            S.setAutofarmEquipBest(true)
        end
        local lastEquip = Autofarm._lastEquipBestAt or 0
        if tick() - lastEquip >= 6 then
            Autofarm._lastEquipBestAt = tick()
            S.farmLog("equip best", "no hold")
            pcall(S.runAutoEquipBestPass)
        end
    elseif not S.coreChestsOnly() and Autofarm.autoEquipBest and Autofarm.oreUnderEnabled then
        -- Occasional pickaxe-only check, never armor/sword bring mid-ore-farm.
        local lastEquip = Autofarm._lastEquipBestAt or 0
        if tick() - lastEquip >= 12 then
            Autofarm._lastEquipBestAt = tick()
            GearEquip.categories = { "Pickaxe" }
            GearEquip.range = GEAR_EQUIP_MAX_STUDS
            if GearEquip.enabled then
                S.farmLog("equip pickaxe", "no hold")
                pcall(S.runAutoEquipBestPass)
            end
        end
    end

    -- Auto Ores before chests. Core chest runs only open chests.
    local ore, orePos = nil, nil
    if not S.coreChestsOnly() then
        ore, orePos = S.findOreForAutofarm()
    end
    if ore then
        S.holdAutofarmCruise("ore")
        S.autofarmVisitOre(ore, orePos)
        S.runAutofarmThresholdDumpIfReady()
        return
    end

    local mine = S.findMineBesideOnCruise()
    if mine then
        S.holdAutofarmCruise("mine")
        S.autofarmVisitMine(mine)
        return
    end

    if Autofarm.enterDungeons == true then
        local dungeon = S.findDungeonForAutofarm(8000, 2500)
        if dungeon then
            S.holdAutofarmCruise("dungeon")
            local wasInside = LocalPlayer:GetAttribute("InDungeon") == true
            pcall(function()
                S.enterDungeonForLoot(dungeon)
            end)
            local entered = wasInside or LocalPlayer:GetAttribute("InDungeon") == true
            Autofarm.skipDungeonsUntil = Autofarm.skipDungeonsUntil or {}
            Autofarm.skipDungeonsUntil[dungeon] = tick() + (entered and 120 or 25)
            if entered then
                local guard = 0
                while Autofarm.enabled and Autofarm.openChests and guard < 8 do
                    local inside = S.findChestForAutofarm()
                    if not inside then
                        break
                    end
                    S.autofarmVisitChest(inside)
                    guard += 1
                end
                pcall(S.exitDungeonToLine)
            end
        return
    end
    end

        local chest = S.findChestForAutofarm()
        if chest then
        S.holdAutofarmCruise("chest")
            S.autofarmVisitChest(chest)
            return
    end

    if not S.coreChestsOnly() and S.hasAutofarmLootInRange() then
        S.holdAutofarmCruise("loot")
        S.autofarmLootPass()
        S.runAutofarmThresholdDumpIfReady()
        return
    end

    if Autofarm._pendingMapWrap then
        Autofarm._pendingMapWrap = false
        if not (CoreFarm.openAll or CoreFarm._ownedRun) then
        S.notify("Autofarm", "Map end reached - restarting from 0", 4)
        end
    end
end
function S.autofarmTweenToDistance(targetDistance, shouldStop)
    local root = S.getRoot()
    if not root or not S.getAutofarmCFrame(targetDistance) then
        return false
    end

    -- Never kill hover for tween — at flyY like -15, no hover = void fall.
    -- Hover Heartbeat already no-ops while Autofarm.moving.
    if Autofarm.enabled then
        S.lockAutofarmHover(true)
    end
    S.cancelAutofarmTween()
    S.ensureAutofarmOrigin(false)

    local from = Autofarm.distance or 0
    local goal = targetDistance or from
    local travel = math.abs(goal - from)
    if travel < 0.5 then
        S.setAutofarmPose(goal)
        if Autofarm.enabled then
            S.lockAutofarmHover(true)
        end
        return false
    end

    local speed = S.getAutofarmSpeed()
    local dirSign = goal >= from and 1 or -1
    local current = from
    local nextLootCheck = os.clock()

    Autofarm.moving = true
    S.setAutofarmPlatformStand(true)
    root.Anchored = false
    local deadline = os.clock() + math.clamp(travel / math.max(speed, 80) + 1.2, 2, 8)

    while Autofarm.enabled and not S.autofarmCycleShouldAbort() do
        if os.clock() >= deadline then
            S.farmLog("tween timeout", string.format("%.0f→%.0f", current, goal))
            break
        end
        local dt = RunService.Heartbeat:Wait()
        root = S.getRoot()
        if not root then
            break
        end

        local step = speed * math.max(dt, 1 / 120)
        current = current + dirSign * step
        if (dirSign > 0 and current >= goal) or (dirSign < 0 and current <= goal) then
            current = goal
            S.setAutofarmPose(current)
            break
        end

        S.setAutofarmPose(current)

        -- Check often when Auto Ores is on, but NEVER every frame — the world ore
        -- walk is expensive and per-frame scans progressively freeze the client.
        if shouldStop then
            local gap = (Autofarm.oreUnderEnabled == true) and 0.12 or 0.1
            if os.clock() >= nextLootCheck then
                nextLootCheck = os.clock() + gap
                if shouldStop() then
                    S.syncAutofarmDistanceFromRoot()
                    Autofarm.moving = false
                    S.lockAutofarmHover(true)
                    return true
                end
            end
        end
    end

    Autofarm.moving = false
    S.syncAutofarmDistanceFromRoot()

    if Autofarm.enabled then
        S.setAutofarmPose(goal)
        S.lockAutofarmHover(true)
    else
        S.setAutofarmPlatformStand(false)
        root = S.getRoot()
        if root then
            root.Anchored = false
        end
    end
    return false
end

-- Snapshot / restore farm axis so mine+dungeon only swap direction, same tween/speed/flyY.
function S.pushAutofarmRoute()
    return {
        origin = Autofarm.origin,
        routeDirBase = Autofarm.routeDirBase,
        routeDir = Autofarm.routeDir,
        trackForward = Autofarm.trackForward,
        distance = Autofarm.distance,
        axis = Autofarm.axis,
    }
end

function S.popAutofarmRoute(saved, keepWorldPos)
    if not saved then
        return
    end
    Autofarm.origin = saved.origin
    Autofarm.routeDirBase = saved.routeDirBase
    Autofarm.routeDir = saved.routeDir
    Autofarm.trackForward = saved.trackForward
    Autofarm.axis = saved.axis
    if keepWorldPos then
        S.syncAutofarmDistanceFromRoot()
    else
        Autofarm.distance = saved.distance or 0
        if Autofarm.enabled then
            S.setAutofarmPose(Autofarm.distance)
        end
    end
end

-- Point farm axis at a world XZ and tween with autofarmTweenToDistance (same config).
function S.autofarmTweenTowardWorldPos(targetPos, shouldStop)
    local root = S.getRoot()
    if not root or typeof(targetPos) ~= "Vector3" then
        return false
    end

    local from = root.Position
    local flat = Vector3.new(targetPos.X - from.X, 0, targetPos.Z - from.Z)
    local dist = flat.Magnitude
    local saved = S.pushAutofarmRoute()

    local dir = dist > 0.05 and flat.Unit or (saved.routeDirBase or S.getAutofarmAxisVector())
    if typeof(dir) == "Vector3" and dir.Magnitude > 0.05 then
        dir = dir.Unit
    else
        dir = Vector3.new(0, 0, 1)
    end

    Autofarm.origin = Vector3.new(from.X, S.getAutofarmFlyY(), from.Z)
    Autofarm.routeDirBase = dir
    Autofarm.routeDir = dir
    Autofarm.trackForward = true
    Autofarm.distance = 0
    S.setAutofarmPose(0)

    local interrupted = false
    if dist > 1 then
        interrupted = S.autofarmTweenToDistance(dist, shouldStop) == true
    end

    pcall(function()
        local r = S.getRoot()
        if r then
            S.requestStreamAround(r.Position, 1.4)
        end
    end)

    S.popAutofarmRoute(saved, true)
    return interrupted
end

-- Keep current XZ, face heading, tween `studs` with the real autofarm tween.
function S.autofarmTweenAlongHeading(heading, studs, shouldStop)
    local root = S.getRoot()
    if not root then
        return false
    end

    heading = Vector3.new(heading.X, 0, heading.Z)
    if heading.Magnitude < 0.05 then
        heading = S.getAutofarmAxisVector()
    else
        heading = heading.Unit
    end
    studs = math.max(0, tonumber(studs) or 0)
    if studs < 0.5 then
        return false
    end

    local saved = S.pushAutofarmRoute()
    Autofarm.origin = Vector3.new(root.Position.X, S.getAutofarmFlyY(), root.Position.Z)
    Autofarm.routeDirBase = heading
    Autofarm.routeDir = heading
    Autofarm.trackForward = true
    Autofarm.distance = 0
    S.setAutofarmPose(0)

    local interrupted = S.autofarmTweenToDistance(studs, shouldStop) == true

    pcall(function()
        local r = S.getRoot()
        if r then
            S.requestStreamAround(r.Position, 1.4)
        end
    end)

    S.popAutofarmRoute(saved, true)
    return interrupted
end

-- Alias used by mine/dungeon: always farm tween + farm flyY.
function S.setAutofarm(enabled, opts)
    enabled = enabled == true
    opts = type(opts) == "table" and opts or {}
    if enabled and game.PlaceId ~= JPAX.placeId then
        return
    end

    -- Enable Autofarm OFF always wins: never block behind Scrap (that stuck Lael).
    if not enabled then
        -- Kill cruise/hover before the bag flush. Otherwise Drop in Drill
        -- empties the sack on the map, then the return trip finishes at the drill.
        Autofarm._farmShuttingDown = true
        S.disconnectAll("autofarm")
        S.disconnectAll("autofarmGlide")
        S.cancelAutofarmTween()
        S.lockAutofarmHover(false)
    end

    if not enabled and S.isScrapFarmMode() then
        Autofarm._farmShuttingDown = true
        local fill = S.getBagFillCount()
        Autofarm.scrapFarm = false
        S.trySetRayfieldFlag("terra_af_scrap_farm", false)
        if fill > 0 then
            Autofarm._scrapFlushing = true
            pcall(function()
                S.scrapSmeltAndShredCycle({ force = true })
            end)
            Autofarm._scrapFlushing = false
            Autofarm._skipNextEndGame = true
        end
        S.clearScrapFarmState(true)
    end

    -- End-game bag flush while engine still considered ON.
    if not enabled then
        if Autofarm._skipNextEndGame then
            Autofarm._skipNextEndGame = false
        else
            pcall(S.endGameFlushActiveFarmBag)
        end
    end

    Autofarm.enabled = enabled
    S.disconnectAll("autofarm")
    S.disconnectAll("autofarmGlide")
    S.cancelAutofarmTween()

    if not enabled then
        S.farmLog("disable", "off")
        pcall(S.destroyFarmDebugHud)
        pcall(S.releaseStuckFarmHold)
        S.stopFarmLoopsSoft()
        if opts.skipReturn then
            pcall(S.forceReleaseFarmCharacter)
            return
        end
        S.returnToDrillAfterFarmStop({ keepEngine = false, force = true })
        return
    end

    Autofarm._returnGen = (Autofarm._returnGen or 0) + 1
    Autofarm._returningToDrill = false
    Autofarm._farmShuttingDown = false
    Autofarm._banditPause = false
    Autofarm._banditUnder = false
    if S.Bandit then
        S.Bandit.paused = false
        S.Bandit.underActive = false
        S.Bandit.underTarget = nil
    end
    Autofarm.busy = false
    Autofarm._cycleRunning = false
    Autofarm.moving = false
    Autofarm.miningBusy = false
    Autofarm._oreHuntMode = false
    Autofarm._scrapProcessing = false
    Autofarm._scrapFlushing = false

    if Money.enabled then
        S.setAutoMoney(false)
    end

    if Autofarm.autoEquipBest then
        S.setAutofarmEquipBest(true)
    end
    S.syncAutofarmMapEndFromMeters()

    Autofarm._holdReason = nil
    Autofarm._dbgErr = nil
    Autofarm._cruiseReadyAt = tick() + 2.5
    Autofarm.debugHud = Autofarm.debugHud ~= false
    S.ensureFarmDebugHud()
    S.farmLog("enable", "run / tween only — filters stay as set")

    S.releaseAutofarmSeat()
    S.resetAutofarmStart()
    if not Autofarm.origin then
        Autofarm.enabled = false
        return
    end

    if not State.noclip then
        S.setNoclip(true)
        Autofarm.ownedNoclip = true
    end
    pcall(S.setAutofarmCameraAssist, true)

    S.setAutofarmPose(Autofarm.distance or 0)
    S.setAutofarmPlatformStand(true)
    S.ensureAutofarmAntiFall(true)
    S.lockAutofarmHover(true)

    task.spawn(function()
        S.ensureItemBag()
    end)

    State.connections.autofarm = RunService.Heartbeat:Connect(function()
        if not Autofarm.enabled or (Reap and Reap.sell) then
            return
        end

        -- Ore dig stuck under a rock: hard snap back to cruise (don't leave floating).
        if Autofarm.miningBusy then
            local mineSince = Autofarm._miningBusySince
            if typeof(mineSince) == "number" and (tick() - mineSince) > 70 then
                S.hardRecoverAutofarmCruise("miningBusy watchdog")
            end
        end

        -- Also catch freefall even when not flagged miningBusy (sink-to-void).
        local rootCheck = S.getRoot()
        if rootCheck
            and not Autofarm.moving
            and not Autofarm.miningBusy
            and not Autofarm._oreHuntMode
            and not Autofarm._scrapProcessing
            and not Autofarm._banditUnder
        then
            local flyY = S.getAutofarmFlyY()
            local pinY = Autofarm._gatePinY
            local expectY = typeof(pinY) == "number" and pinY or flyY
            if rootCheck.Position.Y < expectY - 20 or rootCheck.Position.Y ~= rootCheck.Position.Y then
                S.hardRecoverAutofarmCruise("void sink")
            end
        end

        if Autofarm.busy or Autofarm._cycleRunning then
            -- Watchdog: never leave character PlatformStand-floating forever.
            -- Ore/mine cycles are longer — don't clear busy early or a 2nd cycle races the 1st.
            local since = Autofarm._busySince
    local oresOn = Autofarm.oreUnderEnabled == true or S.isScrapGoldPhase()
            local maxBusy = oresOn and 95 or 45
            if Autofarm.busy and typeof(since) == "number" and (tick() - since) > maxBusy then
                Autofarm._cycleGen = (Autofarm._cycleGen or 0) + 1
                Autofarm.busy = false
                Autofarm._busySince = nil
                Autofarm._cycleRunning = false
                S.farmLog("watchdog", string.format("%.0fs %s", tick() - since, Autofarm._holdReason or "busy"))
                S.hardRecoverAutofarmCruise("busy watchdog")
            end
            return
        end
        if Autofarm._banditPause then
            return
        end
        if (tick() - (State.lastAutofarmTick or 0)) < 0.2 then
            return
        end
        State.lastAutofarmTick = tick()
        Autofarm._cycleAbort = false
        Autofarm._cycleGen = (Autofarm._cycleGen or 0) + 1
        local gen = Autofarm._cycleGen
        Autofarm._cycleRunning = true
        task.spawn(function()
            local ok, err = pcall(S.runAutofarmCycle)
            if not ok then
                pcall(S.farmErr, "cycle ERR", err)
                pcall(S.hardRecoverAutofarmCruise, "cycle error")
            end
            -- Only the active generation may clear busy (watchdog may have superseded us).
            if gen == Autofarm._cycleGen then
                Autofarm._cycleRunning = false
                Autofarm.busy = false
                Autofarm._busySince = nil
                Autofarm._cycleAbort = false
            end
        end)
    end)

    S.startJpaxRouteGlide()
end

function S.gatherMoneySackInstances(thorough)
    local seen = {}
    local list = {}

    local function add(item)
        if not item or seen[item] then
            return
        end
        if item.Name ~= "Money_Sack" and item:GetAttribute("Class") ~= "Money_Sack" then
            return
        end
        seen[item] = true
        table.insert(list, item)
    end

    local itemsFolder = Workspace:FindFirstChild("Items")
    if itemsFolder then
        for _, item in ipairs(itemsFolder:GetChildren()) do
            add(item)
        end
    end

    for _, tagged in ipairs(CollectionService:GetTagged("DungeonLootHighlightTarget")) do
        add(tagged)
        if tagged.Parent then
            add(tagged.Parent)
        end
    end

    if thorough then
        for _, desc in ipairs(Workspace:GetDescendants()) do
            if desc.Name == "Money_Sack" then
                add(desc)
            end
        end
    end

    return list
end

function S.collectMoneySacks(range, thorough)
    if not Services.InteractionService then
        return 0
    end

    range = range or 80
    local sacks = {}
    for _, item in ipairs(S.gatherMoneySackInstances(thorough == true)) do
        local pos = S.getItemPosition(item)
        if pos then
            table.insert(sacks, { item = item, dist = LocalPlayer:DistanceFromCharacter(pos), pos = pos })
        end
    end

    table.sort(sacks, function(a, b)
        return a.dist < b.dist
    end)

    local collected = 0
    for _, entry in ipairs(sacks) do
        local item = entry.item
        if item.Parent then
            local pos = S.getItemPosition(item) or entry.pos
            if pos and LocalPlayer:DistanceFromCharacter(pos) <= range then
                local root = S.getRoot()
                if root then
                    -- Get close — interact often fails from far away.
                    root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
                    root.AssemblyLinearVelocity = Vector3.zero
                    task.wait(0.08)
                end

                local before = item.Parent
                S.interactMoneySack(item)

                if not item.Parent or before ~= item.Parent then
                    collected += 1
                else
                    if typeof(fireproximityprompt) == "function" then
                        for _, desc in ipairs(item:GetDescendants()) do
                            if desc:IsA("ProximityPrompt") then
                                pcall(fireproximityprompt, desc)
                            end
                        end
                    end
                    task.wait(0.12)
                    S.interactMoneySack(item)
                    if not item.Parent then
                        collected += 1
                    end
                end

                task.wait(0.12)
            end
        end
    end

    S.tryEquipItemBag()
    return collected
end

function S.isMoneySackItem(item)
    if not item or not item.Parent then
        return false
    end
    if item.Name == "Money_Sack" or item:GetAttribute("Class") == "Money_Sack" then
        return true
    end
    local ok, tagged = pcall(function()
        return CollectionService:HasTag(item, "MoneySack")
    end)
    return ok and tagged == true
end

function S.reapInteractSack(item)
    if not item or not item.Parent or not Services.InteractionService then
        return false
    end
    local before = item.Parent
    pcall(function()
        Services.InteractionService:Interact(item)
    end)
    if typeof(fireproximityprompt) == "function" then
        local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            pcall(fireproximityprompt, prompt)
        end
    end
    return (not item.Parent) or item.Parent ~= before
end

function S.destroyReapAura()
    S.disconnectAll("reapAuraSpin")
    if Reap.auraModel then
        pcall(function()
            Reap.auraModel:Destroy()
        end)
    end
    Reap.auraModel = nil
end

function S.buildReapAura(root)
    S.destroyReapAura()
    if not root then
        return
    end

    local radius = Reap.radius or 16
    local model = Instance.new("Model")
    model.Name = "JPAX_MoneySackAura"

    local host = Instance.new("Part")
    host.Name = "Host"
    host.Size = Vector3.new(1, 1, 1)
    host.Transparency = 1
    host.Anchored = true
    host.CanCollide = false
    host.CanQuery = false
    host.CanTouch = false
    host.Massless = true
    host.CFrame = root.CFrame
    host.Parent = model

    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(128, 72, 255)
    light.Brightness = 2.6
    light.Range = radius + 6
    light.Shadows = false
    light.Parent = host

    local att = Instance.new("Attachment")
    att.Parent = host

    local wisps = Instance.new("ParticleEmitter")
    wisps.Name = "Wisps"
    wisps.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    wisps.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(210, 180, 255)),
        ColorSequenceKeypoint.new(0.4, Color3.fromRGB(120, 50, 220)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 210, 255)),
    })
    wisps.LightEmission = 0.9
    wisps.LightInfluence = 0.15
    wisps.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.35, 1.15),
        NumberSequenceKeypoint.new(1, 0),
    })
    wisps.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(0.65, 0.35),
        NumberSequenceKeypoint.new(1, 1),
    })
    wisps.Lifetime = NumberRange.new(0.7, 1.35)
    wisps.Rate = 42
    wisps.Speed = NumberRange.new(1.2, 3.4)
    wisps.SpreadAngle = Vector2.new(180, 40)
    wisps.Acceleration = Vector3.new(0, 4.2, 0)
    wisps.RotSpeed = NumberRange.new(-120, 120)
    wisps.Drag = 1.2
    wisps.Parent = att

    local mist = Instance.new("ParticleEmitter")
    mist.Name = "Mist"
    mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
    mist.Color = ColorSequence.new(Color3.fromRGB(70, 20, 140), Color3.fromRGB(40, 120, 220))
    mist.LightEmission = 0.55
    mist.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.4),
        NumberSequenceKeypoint.new(1, 3.2),
    })
    mist.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.72),
        NumberSequenceKeypoint.new(1, 1),
    })
    mist.Lifetime = NumberRange.new(0.9, 1.5)
    mist.Rate = 14
    mist.Speed = NumberRange.new(0.4, 1.4)
    mist.SpreadAngle = Vector2.new(180, 180)
    mist.RotSpeed = NumberRange.new(-20, 20)
    mist.Parent = att

    local ring = Instance.new("Part")
    ring.Name = "Ring"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.12, radius * 2, radius * 2)
    ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(130, 70, 255)
    ring.Transparency = 0.78
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CanTouch = false
    ring.Massless = true
    ring.CFrame = root.CFrame * CFrame.new(0, -2.6, 0) * CFrame.Angles(0, 0, math.rad(90))
    ring.Parent = model

    Reap._motes = {}
    for i = 1, 7 do
        local mote = Instance.new("Part")
        mote.Name = "Aura"
        mote.Shape = Enum.PartType.Ball
        mote.Size = Vector3.new(0.55, 0.55, 0.55)
        mote.Material = Enum.Material.Neon
        mote.Color = (i % 2 == 0) and Color3.fromRGB(80, 210, 255) or Color3.fromRGB(170, 80, 255)
        mote.Anchored = true
        mote.CanCollide = false
        mote.CanQuery = false
        mote.CanTouch = false
        mote.CastShadow = false
        mote.Parent = model
        local moteLight = Instance.new("PointLight")
        moteLight.Color = mote.Color
        moteLight.Brightness = 1.4
        moteLight.Range = 7
        moteLight.Shadows = false
        moteLight.Parent = mote
        Reap._motes[i] = mote
    end

    model.Parent = Workspace
    Reap.auraModel = model

    local spin = 0
    State.connections.reapAuraSpin = RunService.Heartbeat:Connect(function(dt)
        local live = S.getRoot()
        if not live or not Reap.auraModel or not Reap.auraModel.Parent then
            return
        end
        spin += dt or 0.016
        local origin = live.Position
        if host and host.Parent then
            host.CFrame = live.CFrame
        end
        if ring and ring.Parent then
            ring.CFrame = CFrame.new(origin.X, origin.Y - 2.6, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
        end
        local r = (Reap.radius or 16) * 0.72
        for i, mote in ipairs(Reap._motes or {}) do
            if mote and mote.Parent then
                local ang = spin * 1.15 + (i - 1) * (math.pi * 2 / 7)
                local y = math.sin(spin * 2.2 + i) * 1.6
                mote.CFrame = CFrame.new(origin.X + math.cos(ang) * r, origin.Y + y - 0.4, origin.Z + math.sin(ang) * r)
            end
        end
    end)
end

function S.setReapAura(enabled)
    Reap.aura = enabled == true
    S.disconnectAll("reapAura")
    S.disconnectAll("reapAuraTouch")
    S.destroyReapAura()
    if not Reap.aura then
        return
    end

    local function arm(char)
        if not Reap.aura then
            return
        end
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            root = char and char:WaitForChild("HumanoidRootPart", 8)
        end
        if root and Reap.aura then
            S.buildReapAura(root)
        end
    end

    if LocalPlayer.Character then
        task.spawn(arm, LocalPlayer.Character)
    end
    State.connections.reapAura = LocalPlayer.CharacterAdded:Connect(function(char)
        task.defer(arm, char)
    end)

    local nextScan = 0
    local cached = {}
    State.connections.reapAuraTouch = RunService.Heartbeat:Connect(function()
        if not Reap.aura or Reap.busy then
            return
        end
        local root = S.getRoot()
        if not root or not Services.InteractionService then
            return
        end
        local now = tick()
        if now >= nextScan then
            nextScan = now + 0.12
            cached = {}
            local itemsFolder = Workspace:FindFirstChild("Items")
            if itemsFolder then
                for _, child in ipairs(itemsFolder:GetChildren()) do
                    if S.isMoneySackItem(child) then
                        cached[#cached + 1] = child
                    end
                end
            end
            local ok, tagged = pcall(function()
                return CollectionService:GetTagged("MoneySack")
            end)
            if ok and type(tagged) == "table" then
                for _, item in ipairs(tagged) do
                    if S.isMoneySackItem(item) then
                        cached[#cached + 1] = item
                    end
                end
            end
        end

        local radius = Reap.radius or 16
        local origin = root.Position
        for _, item in ipairs(cached) do
            if item and item.Parent then
                local pos = S.getItemPosition(item)
                if pos and (pos - origin).Magnitude <= radius then
                    local last = Reap._touched[item]
                    if not last or now - last >= 0.28 then
                        Reap._touched[item] = now
                        S.reapInteractSack(item)
                    end
                end
            end
        end
    end)
end

function S.reapRestoreSpot(cf, farming, dist)
    local root = S.getRoot()
    if root and typeof(cf) == "CFrame" then
        root.CFrame = cf
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    if farming and Autofarm.enabled then
        Autofarm.distance = dist or Autofarm.distance
        pcall(function()
            S.syncAutofarmDistanceFromRoot()
            S.setAutofarmPose(Autofarm.distance or dist or 0)
            S.lockAutofarmHover(true)
        end)
    end
end

function S.setReapSellBag(enabled)
    if enabled ~= true then
        Reap.sell = false
        Reap.sellBusy = false
        Reap.busy = false
        S.disconnectAll("reapSellPin")
        if Reap.ownedNoclip then
            S.setNoclip(false)
            Reap.ownedNoclip = false
        end
        pcall(function()
            S.setAutofarmPlatformStand(false)
        end)
        local root = S.getRoot()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
        return true
    end
    if Reap.sell then
        return true
    end

    local root = S.getRoot()
    if not root then
        S.notify("Money", "No character", 3)
        return false
    end
    local sell = S.findNearestSellPart(root.Position)
    if not sell then
        S.notify("Money", "No sell trade nearby", 4)
        return false
    end

    local drop = S.getSellDropCFrame(sell)
    local hold = CFrame.new(drop.Position.X, drop.Position.Y + 2.15, drop.Position.Z)
    Reap.sell = true
    Reap.sellBusy = true
    Reap.busy = true
    Reap._sellPart = sell
    Reap._sellHold = hold
    if not State.noclip then
        S.setNoclip(true)
        Reap.ownedNoclip = true
    else
        Reap.ownedNoclip = false
    end
    S.setAutofarmPlatformStand(true)

    State.connections.reapSellPin = RunService.Heartbeat:Connect(function()
        if not Reap.sell then
            return
        end
        local live = S.getRoot()
        local part = Reap._sellPart
        local cf = Reap._sellHold
        if part and part.Parent then
            local drop = S.getSellDropCFrame(part)
            cf = CFrame.new(drop.Position.X, drop.Position.Y + 2.15, drop.Position.Z)
            Reap._sellHold = cf
        end
        if not live or typeof(cf) ~= "CFrame" then
            return
        end
        live.Anchored = false
        live.CFrame = cf
        live.AssemblyLinearVelocity = Vector3.zero
        live.AssemblyAngularVelocity = Vector3.zero
        S.setAutofarmPlatformStand(true)
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end)

    task.spawn(function()
        S.notify("Money", "Sell Loot In Bag ON", 3)
        while Reap.sell do
            local part = Reap._sellPart
            if part and part.Parent then
                pcall(function()
                    S.ensureItemBag(true)
                    local update = Services.ToolService and Services.ToolService.Update
                    if update and update.Fire then
                        local _ = update -- (sack dihapus)
                    end
                end)
                if S.getBagFillCount() > 0 then
                    S.bagDrop()
                    S.moveItemsOntoSellPart(part, 80)
                end
            end
            task.wait(0.15)
        end
    end)
    return true
end

function S.reapSweepRenderedSacks()
    if Reap.busy then
        S.notify("Money", "Already running", 2)
        return 0
    end
    Reap.busy = true
    local root = S.getRoot()
    local back = root and root.CFrame
    local farming = Autofarm.enabled == true
    local dist = Autofarm.distance
    local got = 0
    local ok, err = pcall(function()
        local list = {}
        local seen = {}
        local function add(item)
            if item and not seen[item] and S.isMoneySackItem(item) then
                seen[item] = true
                list[#list + 1] = item
            end
        end
        local itemsFolder = Workspace:FindFirstChild("Items")
        if itemsFolder then
            for _, child in ipairs(itemsFolder:GetChildren()) do
                add(child)
            end
        end
        local taggedOk, tagged = pcall(function()
            return CollectionService:GetTagged("MoneySack")
        end)
        if taggedOk and type(tagged) == "table" then
            for _, item in ipairs(tagged) do
                add(item)
            end
        end
        for _, item in ipairs(list) do
            if item.Parent then
                local pos = S.getItemPosition(item)
                root = S.getRoot()
                if pos and root then
                    root.CFrame = CFrame.new(pos + Vector3.new(0, 2.2, 0))
                    root.AssemblyLinearVelocity = Vector3.zero
                    if S.reapInteractSack(item) then
                        got += 1
                    end
                end
            end
        end
    end)
    if not ok then
        warn("[JPAX] reap sweep:", err)
    end
    S.reapRestoreSpot(back, farming, dist)
    Reap.busy = false
    S.notify("Money", string.format("Collected %d money sacks", got), 3)
    return got
end

function S.lootUntilBagFull()
    S.tryEquipItemBag()
    local capacity = S.getBagCapacity()
    local looted = 0
    local emptySteps = 0
    local visitedDungeons = {}

    for _ = 1, Money.maxStepsPerCycle do
        if S.getBagFillCount() >= capacity then
            break
        end

        S.advanceAlongLine(Money.forwardStuds)
        task.wait(0.1)

        local stepLoot = S.lootMoneyTargetsOnce(capacity)
        looted += stepLoot

        if stepLoot > 0 then
            emptySteps = 0
        else
            emptySteps += 1
        end

        local dungeon = S.findDungeonAhead(Money.detectRange)
        if dungeon and not visitedDungeons[dungeon] and S.getBagFillCount() < capacity then
            visitedDungeons[dungeon] = true
            S.enterDungeonForLoot(dungeon)
            looted += S.lootInsideDungeon(dungeon, capacity)
            S.exitDungeonToLine()
            emptySteps = 0
        end

        if emptySteps >= 12 then
            break
        end
    end

    return looted
end

function S.runMoneyCycle()
    if not Services.ToolService then
        return 0, 0, 0
    end

    if not Money.lineOrigin then
        S.resetMoneyTravelHeading()
    end

    S.ensureMoneyTravelHeading()
    S.resumeOnDrillLine()

    local looted = S.lootUntilBagFull()
    local sold = 0
    local sacks = 0

    if S.getBagFillCount() > 0 then
        sold, sacks = S.sellAndCollectAtNearestPost()
        Money.trackedBagSize = 0
    end

    return looted, sold, sacks
end

function S.mineSwing()
    if not Services.ToolService or not Services.ToolService.Update then
        return 0
    end

    S.tryEquipPickaxe()
    local tool = S.getEquippedTool()
    if not tool or not S.isPickaxeTool(tool) then
        return 0
    end

    S.boostToolRange(tool, Pickaxe.mineRange)

    local ores = S.findOresInRange(Pickaxe.mineRange)
    if #ores == 0 then
        return 0
    end

    pcall(function()
        Services.ToolService.Update:Fire({ "Swing", ores })
    end)

    return #ores
end

function S.getCombatAnchorPosition()
    local root = S.getRoot()
    return root and root.Position or nil
end

function S.findHostileMobsInRange(range)
    local mobs = {}
    local seen = {}
    local anchorPos = S.getCombatAnchorPosition()
    if not anchorPos then
        return mobs
    end

    local function tryAdd(model)
        if not model or seen[model] then
            return
        end
        if not S.isHostileMob(model) then
            return
        end

        local pos = S.getEspWorldPosition(model)
        if pos and (pos - anchorPos).Magnitude <= range then
            seen[model] = true
            table.insert(mobs, model)
        end
    end

    local npcFolder = Workspace:FindFirstChild("Npc")
    if npcFolder then
        for _, child in ipairs(npcFolder:GetChildren()) do
            if child:IsA("Model") then
                tryAdd(child)
            end
        end
    end

    for _, tagged in ipairs(CollectionService:GetTagged("NpcManager")) do
        tryAdd(S.getNpcModelFromManager(tagged))
    end

    table.sort(mobs, function(a, b)
        local posA = S.getEspWorldPosition(a)
        local posB = S.getEspWorldPosition(b)
        if not posA then
            return false
        end
        if not posB then
            return true
        end
        return (posA - anchorPos).Magnitude < (posB - anchorPos).Magnitude
    end)

    return mobs
end

function S.isCombatTool(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end

    local class = string.lower(tool:GetAttribute("Class") or "")
    local name = string.lower(tool.Name)

    if class == "itembag" or name == "itembag" then
        return false
    end
    if class == "consumable" or name:find("medkit", 1, true) then
        return false
    end
    if name:find("speedpotion", 1, true) or name:find("landmine", 1, true) then
        return false
    end
    if name:find("taunt", 1, true) or name:find("magnet", 1, true) then
        return false
    end

    return true
end

function S.getToolCombatAction(tool)
    if not S.isCombatTool(tool) then
        return nil
    end

    local class = string.lower(tool:GetAttribute("Class") or "")
    local name = string.lower(tool.Name)

    if tool:GetAttribute("Ammo") ~= nil
        or class == "gun"
        or name:find("rifle", 1, true)
        or name:find("shotgun", 1, true)
        or name:find("revolver", 1, true)
        or name:find("rpg", 1, true)
        or name:find("blackhole", 1, true) then
        return "Shoot"
    end

    return "Swing"
end

function S.getToolDamage(tool)
    if not tool then
        return 0
    end

    local damage = 0
    pcall(function()
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        local damageModule = shared and shared:FindFirstChild("ToolDamage")
        if damageModule then
            local ToolDamage = require(damageModule)
            local total = ToolDamage.GetTotalDamage(tool)
            if typeof(total) == "number" then
                damage = total
                return
            end
        end

        local raw = tool:GetAttribute("Damage")
        if typeof(raw) == "number" then
            damage = raw
        end
    end)

    return damage
end

function S.getToolDamageScore(tool)
    local damage = S.getToolDamage(tool)
    if S.getToolCombatAction(tool) == "Shoot" then
        return damage + 0.001
    end
    return damage
end

function S.findBestDamageCombatTool()
    local bestTool = nil
    local bestScore = -1
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local containers = {}

    if char then
        table.insert(containers, char)
    end
    if backpack then
        table.insert(containers, backpack)
    end

    for _, container in ipairs(containers) do
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") and S.isCombatTool(child) then
                local score = S.getToolDamageScore(child)
                if score > bestScore then
                    bestScore = score
                    bestTool = child
                end
            end
        end
    end

    return bestTool
end

function S.ensureBestDamageTool()
    if not Services.ToolService then
        return false
    end
    -- Auto Ore dig owns the hotbar — never yank pickaxe for a sword mid-swing
    -- (DeathWorm auto-kill sets Combat._killingWorm and is allowed through).
    if Autofarm.enabled and (Autofarm.miningBusy or Autofarm._oreHuntMode) and not Combat._killingWorm then
        return false
    end

    local best = S.findBestDamageCombatTool()
    if not best then
        return false
    end

    local equipped = S.getEquippedTool()
    if equipped == best then
        return true
    end

    if equipped and S.isCombatTool(equipped) then
        if S.getToolDamageScore(equipped) >= S.getToolDamageScore(best) then
            return true
        end
    end

    S.callEquipTool(best)
    equipped = S.getEquippedTool()
    return equipped == best or (equipped ~= nil and equipped.Name == best.Name)
end

function S.getMobHitPart(mob)
    if not mob then
        return nil
    end
    if mob:IsA("BasePart") then
        return mob
    end
    return mob.PrimaryPart
        or mob:FindFirstChild("HumanoidRootPart")
        or mob:FindFirstChildWhichIsA("BasePart", true)
end

function S.getMobAimPosition(mob)
    local part = S.getMobHitPart(mob)
    local basePos = nil
    if part then
        basePos = (S.getEspWorldPosition(mob) or part.Position) + Vector3.new(0, 1, 0)
    end
    if not Combat.gunHeadshotAim or not mob or not mob.Parent then
        return basePos, part
    end

    local model = mob
    if mob:IsA("BasePart") then
        model = mob.Parent and mob.Parent:IsA("Model") and mob.Parent or mob
    end

    -- Prediksi: geser titik bidik sesuai kecepatan musuh (lompat / lari) + ping.
    local lead = Vector3.zero
    if Combat.gunAimLead and part then
        local okV, vel = pcall(function()
            return part.AssemblyLinearVelocity
        end)
        if okV and vel then
            local okP, ping = pcall(function()
                return LocalPlayer:GetNetworkPing()
            end)
            local t = math.clamp((okP and ping or 0.05) + 0.06, 0.05, 0.3)
            lead = vel * t
            if lead.Magnitude > 12 then
                lead = lead.Unit * 12
            end
        end
    end

    -- 1) Part bernama Head (kalau mob punya).
    local headPart = model:FindFirstChild("Head", true)
    if not (headPart and headPart:IsA("BasePart")) then
        headPart = nil
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") and string.lower(d.Name):find("head", 1, true)
                and not string.lower(d.Name):find("light", 1, true) then
                headPart = d
                break
            end
        end
    end
    if headPart then
        return headPart.Position + lead, headPart
    end

    -- 2) Tidak ada Head: bidik dekat puncak bounding box (musuh besar).
    if model:IsA("Model") then
        local ok, cf, size = pcall(model.GetBoundingBox, model)
        if ok and cf and size and size.Y > 6.5 then
            local top = cf.Position.Y + size.Y * 0.5
            local aimY = top - math.max(1.2, size.Y * 0.15)
            local ref = basePos or cf.Position
            if aimY > ref.Y then
                return Vector3.new(cf.Position.X, aimY, cf.Position.Z) + lead, part
            end
        end
    end

    return basePos and (basePos + lead) or nil, part
end

-- Titik awal tembakan: dinaikkan mendekati tinggi kepala musuh supaya garis tembak
-- hampir horizontal dan tidak menembus badan musuh dulu saat jarak dekat.
function S.getShotStartPos(root, aimPos)
    local startPos = root.Position + Vector3.new(0, 1.5, 0)
    if not Combat.gunHeadshotAim or not aimPos then
        return startPos
    end
    local rise = math.clamp(aimPos.Y - root.Position.Y, 1.5, math.max(1.5, tonumber(Combat.gunStartRise) or 6))
    return root.Position + Vector3.new(0, rise, 0)
end

function S.fireShootAttack(tool, targets)
    local root = S.getRoot()
    if not root or #targets == 0 then
        return 0
    end

    local startPos = root.Position + Vector3.new(0, 1.5, 0)
    local name = string.lower(tool.Name)

    if name:find("shotgun", 1, true) then
        local shots = {}
        for i = 1, math.min(4, #targets) do
            local mob = targets[i]
            local part = S.getMobHitPart(mob)
            local pos = part and S.getMobAimPosition(mob) or nil
            if pos then
                table.insert(shots, {
                    Start = S.getShotStartPos(root, pos),
                    EndPos = pos,
                    HeadShot = false,
                })
            end
        end
        if #shots == 0 then
            return 0
        end
        Services.ToolService.Update:Fire({ "Shoot", shots })
        return #shots
    end

    local target = targets[1]
    local hitPart = S.getMobHitPart(target)
    if not hitPart then
        return 0
    end

    local endPos, aimPart = S.getMobAimPosition(target)
    endPos = endPos or (hitPart.Position + Vector3.new(0, 1, 0))
    if Combat.gunHeadshotAim and aimPart and aimPart:IsA("BasePart") then
        hitPart = aimPart
    end
    startPos = S.getShotStartPos(root, endPos)
    local magnitude = (endPos - startPos).Magnitude
    Services.ToolService.Update:Fire({ "Shoot", hitPart, false, startPos, endPos, magnitude })
    return 1
end

function S.isSwordTool(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end
    local class = string.lower(tool:GetAttribute("Class") or "")
    local name = string.lower(tool.Name)
    return class == "sword" or name:find("sword", 1, true) ~= nil
end

function S.findBestSwordTool()
    local best, bestScore = nil, -1
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local boxes = {}
    if char then
        table.insert(boxes, char)
    end
    if backpack then
        table.insert(boxes, backpack)
    end
    for _, box in ipairs(boxes) do
        for _, child in ipairs(box:GetChildren()) do
            if child:IsA("Tool") and S.isSwordTool(child) then
                local score = S.getToolDamageScore(child)
                if score > bestScore then
                    bestScore = score
                    best = child
                end
            end
        end
    end
    return best
end

function S.ensureSwordTool()
    if not Services.ToolService then
        return false
    end
    local sword = S.findBestSwordTool()
    if not sword then
        return false
    end
    local equipped = S.getEquippedTool()
    if equipped == sword then
        return true
    end
    pcall(function()
        Services.ToolService:EquipTool(sword)
    end)
    return true
end

function S.combatAttack()
    if not Services.ToolService or not Services.ToolService.Update then
        return 0
    end

    if Autofarm.miningBusy or Autofarm._oreHuntMode then
        return 0
    end

    local range = math.max(10, tonumber(Combat.auraRange) or 50)
    local targets = S.findHostileMobsInRange(range)
    if #targets == 0 then
        return 0
    end

    local worms, others = {}, {}
    for _, mob in ipairs(targets) do
        if S.isDeathWorm(mob) then
            table.insert(worms, mob)
        else
            table.insert(others, mob)
        end
    end

    local hits = 0
    if #worms > 0 then
        if not S.ensureSwordTool() then
        return 0
        end
        local tool = S.getEquippedTool()
        if tool then
            S.boostToolRange(tool, range)
        end
        pcall(function()
            Services.ToolService.Update:Fire({ "Swing", worms })
        end)
        hits += #worms
        return hits
    end

    if Combat.autoEquipBestDamage then
        S.ensureBestDamageTool()
    end
    local tool = S.getEquippedTool()
    if not tool or not S.isCombatTool(tool) then
        return 0
    end
    S.boostToolRange(tool, range)
    local action = S.getToolCombatAction(tool)
    if not action then
        return 0
    end
    pcall(function()
        if action == "Shoot" then
            hits = S.fireShootAttack(tool, others)
        else
            Services.ToolService.Update:Fire({ "Swing", others })
            hits = #others
        end
    end)
    return hits
end

function S.hasReviveKit()
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") and child.Name == "ReviveKit" then
                return true
            end
        end
    end

    return backpack and backpack:FindFirstChild("ReviveKit") ~= nil
end

function S.isPlayerDead()
    if LocalPlayer:GetAttribute("RejoinDead") == true then
        return true
    end

    local humanoid = S.getHumanoid()
    return humanoid ~= nil and humanoid.Health <= 0
end

function S.getReviveProductId()
    local productId = 3559515298
    pcall(function()
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        local productsModule = shared and shared:FindFirstChild("Products")
        if productsModule then
            local products = require(productsModule)
            if products and products.Revive then
                productId = products.Revive
            end
        end
    end)
    return productId
end

function S.requestSelfRevive()
    if not Services.PlayerService then
        S.notify("Player", "Game services not ready yet", 4)
        return false
    end

    if not S.isPlayerDead() then
        S.notify("Player", "You must be dead to self revive", 3)
        return false
    end

    local ok, err = pcall(function()
        Services.PlayerService:SelfRevive():andThen(function(keepReviveOption)
            -- Same flow as the game's death screen button.
            if keepReviveOption then
                if S.hasReviveKit() then
                    S.notify("Player", "Revive sent (ReviveKit)", 3)
                else
                    S.notify("Player", "Free revive not available - use death screen or get a ReviveKit", 5)
                end
                return
            end

            MarketplaceService:PromptProductPurchase(LocalPlayer, S.getReviveProductId())
            S.notify("Player", "No free revive - Robux purchase opened", 4)
        end):catch(function(promiseErr)
            S.notify("Player", "Revive failed: " .. tostring(promiseErr), 5)
        end)
    end)

    if not ok then
        S.notify("Player", "Revive error: " .. tostring(err), 5)
        warn("[TERRA HUB] SelfRevive", err)
    end

    return ok
end

function S.setKillAura(enabled)
    Combat.killAura = enabled
    S.disconnectAll("killAura")

    if not enabled then
        return
    end

    State.connections.killAura = RunService.Heartbeat:Connect(function()
        if not Combat.killAura or Combat.busy or (tick() - (State.lastAuraTick or 0)) < 0.45 then
            return
        end
        State.lastAuraTick = tick()
        Combat.busy = true
        task.spawn(function()
            pcall(S.combatAttack)
            Combat.busy = false
        end)
    end)
end

-- ============================================================
-- Auto Farm Bandit (Farm > Run)
-- Membunuh bandit dalam radius 100 studs. Bandit yang bermutasi Stone di-skip.
-- ============================================================
S.Bandit = S.Bandit or {
    enabled = false,
    range = 5000,
    _stoneCache = setmetatable({}, { __mode = "k" }),
    interval = 0.2,
    maxPause = 20,
    paused = false,
    underMode = true,
    underDepth = 6,
    underTarget = nil,
    underActive = false,
    _underXZ = nil,
    _pauseStart = 0,
    _clearSince = nil,
    _lastAttack = 0,
    _ignore = setmetatable({}, { __mode = "k" }),
    debug = false,
    busy = false,
    _lastTick = 0,
    _debugSeen = {},
    -- nama sudah dinormalisasi: huruf kecil, tanpa spasi/underscore/angka
    names = {
        banditminer = true,
        voidbanditminer = true,
        crazyminer = true,
        voidcrazyminer = true,
    },
}

function S.banditNormalizeName(name)
    return (string.lower(tostring(name or "")):gsub("[^%a]", ""))
end

function S.banditMatchesName(model)
    local names = { model.Name, model:GetAttribute("RealName"), model:GetAttribute("DisplayName") }
    for _, n in ipairs(names) do
        if n ~= nil and S.Bandit.names[S.banditNormalizeName(n)] then
            return true
        end
    end
    return false
end

S.BANDIT_STONE_MATERIALS = {
    [Enum.Material.Slate] = true,
    [Enum.Material.Granite] = true,
    [Enum.Material.Basalt] = true,
    [Enum.Material.Cobblestone] = true,
    [Enum.Material.Pebble] = true,
    [Enum.Material.Rock] = true,
}

function S.banditHasStoneText(value)
    return type(value) == "string" and string.lower(value):find("stone", 1, true) ~= nil
end

-- True kalau bandit sedang bermutasi Stone. Mutasi dicek lewat beberapa cara karena
-- game bisa menyimpannya sebagai attribute, tag, value object, atau material tubuh.
function S.banditIsStone(model)
    -- 1) Attribute di model / humanoid
    local holders = { model, model:FindFirstChildOfClass("Humanoid") }
    for _, holder in ipairs(holders) do
        if holder then
            for key, value in pairs(holder:GetAttributes()) do
                if S.banditHasStoneText(key) then
                    if type(value) == "boolean" then
                        if value then return true end
                    elseif type(value) == "number" then
                        if value > 0 then return true end
                    elseif value ~= nil and value ~= "" then
                        return true
                    end
                elseif S.banditHasStoneText(value) then
                    return true
                end
            end
        end
    end

    -- 2) CollectionService tag
    local okTags, tags = pcall(function()
        return CollectionService:GetTags(model)
    end)
    if okTags and type(tags) == "table" then
        for _, tag in ipairs(tags) do
            if S.banditHasStoneText(tag) then
                return true
            end
        end
    end

    -- 3) Value object / folder / effect bernama Stone (bukan BasePart)
    for _, inst in ipairs(model:GetDescendants()) do
        if not inst:IsA("BasePart") and S.banditHasStoneText(inst.Name) then
            if inst:IsA("BoolValue") then
                if inst.Value then return true end
            elseif inst:IsA("StringValue") then
                if inst.Value ~= "" then return true end
            else
                return true
            end
        end
        if inst:IsA("StringValue") and S.banditHasStoneText(inst.Value) then
            return true
        end
    end

    -- 4) Visual: mayoritas part berubah jadi material batu
    local total, stone = 0, 0
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("BasePart") and inst.Transparency < 0.9 then
            total += 1
            if S.BANDIT_STONE_MATERIALS[inst.Material] then
                stone += 1
            end
        end
    end
    if total >= 3 and stone / total >= 0.7 then
        return true
    end

    return false
end

function S.banditDebugPrint(model)
    local B = S.Bandit
    if B._debugSeen[model] then
        return
    end
    B._debugSeen[model] = true
    local parts = {}
    for key, value in pairs(model:GetAttributes()) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
    end
    local tags = {}
    pcall(function()
        tags = CollectionService:GetTags(model)
    end)
    print(string.format(
        "[JPAX BANDIT] %s | stone=%s | attrs: %s | tags: %s",
        model.Name,
        tostring(S.banditIsStone(model)),
        table.concat(parts, ", "),
        table.concat(tags, ", ")
    ))
end

function S.banditIsStoneCached(mob)
    local B = S.Bandit
    local now = tick()
    local c = B._stoneCache[mob]
    if c and (now - c.t) < 0.4 then
        return c.v
    end
    local v = S.banditIsStone(mob)
    B._stoneCache[mob] = { t = now, v = v }
    return v
end

-- Bandit target terdekat dulu; yang Stone (atau di-ignore karena tidak bisa dibunuh) dilewati.
function S.getBanditTargets()
    local B = S.Bandit
    local now = tick()
    local targets = {}
    for _, mob in ipairs(S.findHostileMobsInRange(B.range)) do
        if S.banditMatchesName(mob) then
            if B.debug then
                pcall(S.banditDebugPrint, mob)
            end
            local ignoreUntil = B._ignore[mob]
            if (not ignoreUntil or ignoreUntil < now) and not S.banditIsStoneCached(mob) then
                targets[#targets + 1] = mob
            end
        end
    end
    return targets
end

-- Jangan menjeda Run di tengah proses sensitif (scrap/jual/pulang ke drill).
function S.banditCanPauseRun()
    if Autofarm._scrapProcessing or Autofarm._scrapFlushing or Autofarm._returningToDrill then
        return false
    end
    if Reap and Reap.sell then
        return false
    end
    return true
end

-- Run langsung berhenti saat ada bandit di sekitar.
function S.banditPauseRun()
    local B = S.Bandit
    if B.paused then
        return
    end
    B.paused = true
    B._pauseStart = tick()
    B._clearSince = nil

    local wasDigging = Autofarm.miningBusy == true or Autofarm._oreHuntMode == true
    Autofarm._banditPause = true
    Autofarm._cycleAbort = true
    Autofarm._cycleGen = (Autofarm._cycleGen or 0) + 1

    if wasDigging then
        -- Keluar dari galian dulu supaya karakter tidak tertinggal di bawah batu.
        pcall(S.hardRecoverAutofarmCruise, "bandit")
    else
        Autofarm._cycleRunning = false
        Autofarm.busy = false
        Autofarm._busySince = nil
        Autofarm.moving = false
        pcall(S.cancelAutofarmTween)
    end
    S.notify("Farm", "Bandit detected · Run paused", 2)
end

-- Bandit habis (atau mentok) -> Run lanjut dari posisi terakhir.
function S.banditResumeRun(reason)
    local B = S.Bandit
    if not B.paused then
        Autofarm._banditPause = false
        return
    end
    B.paused = false
    B._clearSince = nil
    Autofarm._banditPause = false
    if Autofarm.enabled then
        Autofarm._cycleAbort = false
        Autofarm.busy = false
        Autofarm._busySince = nil
        Autofarm._cycleRunning = false
        Autofarm.moving = false
        pcall(S.setAutofarmPose, Autofarm.distance or 0)
        S.notify("Farm", reason or "No bandits left · Run resumed", 2)
    end
end

function S.banditAttack(targets)
    if not Services.ToolService or not Services.ToolService.Update then
        return 0
    end
    if not targets or #targets == 0 then
        return 0
    end
    -- Saat Run sedang menggali (dan belum dijeda), jangan ganti tool.
    if not S.Bandit.paused and (Autofarm.miningBusy or Autofarm._oreHuntMode) then
        return 0
    end

    S.ensureBestDamageTool()
    local tool = S.getEquippedTool()
    if not tool or not S.isCombatTool(tool) then
        return 0
    end

    S.boostToolRange(tool, S.Bandit.range)
    local action = S.getToolCombatAction(tool)
    if not action then
        return 0
    end

    local hits = 0
    pcall(function()
        if action == "Shoot" then
            hits = S.fireShootAttack(tool, targets)
        else
            Services.ToolService.Update:Fire({ "Swing", targets })
            hits = #targets
        end
    end)
    return hits
end

-- Keluar dari posisi "di bawah bandit".
-- Run ON : flag dilepas, anti-fall mengangkat karakter ke ketinggian hover, lalu Run menaruhnya kembali di rute.
-- Run OFF: karakter dikembalikan ke permukaan tanah.
function S.banditLeaveUnder()
    local B = S.Bandit
    B.underTarget = nil
    if not B.underActive then
        Autofarm._banditUnder = false
        return
    end
    B.underActive = false
    Autofarm._banditUnder = false
    if not Autofarm.enabled then
        local root = S.getRoot()
        if root then
            if B._underXZ then
                Combat.underLastSafeXZ = B._underXZ
            end
            pcall(S.recoverFromUnder, root)
        end
    end
end

-- Dipanggil tiap frame: tempel karakter tepat di bawah bandit supaya tidak terkena serangannya.
function S.banditFollowUnder()
    local B = S.Bandit
    local mob = B.underTarget
    if not B.enabled or not B.underMode or not mob then
        return
    end
    if not mob.Parent or not S.isHostileMob(mob) then
        B.underTarget = nil
        return
    end
    local root = S.getRoot()
    if not root then
        return
    end
    local under = S.getMobUnderPosition(mob, B.underDepth)
    if not under then
        return
    end
    Autofarm._banditUnder = true
    B.underActive = true
    B._underXZ = Vector3.new(under.X, 0, under.Z)
    root.CFrame = CFrame.new(under) * (root.CFrame - root.CFrame.Position)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

function S.banditStep()
    local B = S.Bandit
    local runOn = Autofarm.enabled == true and not Autofarm._farmShuttingDown

    if B.paused and not runOn then
        S.banditResumeRun()
    end

    local targets = S.getBanditTargets()

    if runOn then
        if #targets > 0 then
            B._clearSince = nil
            if not B.paused and S.banditCanPauseRun() then
                S.banditPauseRun()
            end
            -- Pengaman: bandit tidak mati > maxPause detik -> abaikan 60 detik, Run lanjut.
            if B.paused and (tick() - B._pauseStart) > B.maxPause then
                for _, mob in ipairs(targets) do
                    B._ignore[mob] = tick() + 60
                end
                targets = {}
                S.banditResumeRun("Bandit can't be killed · Run resumed")
            end
        elseif B.paused then
            B._clearSince = B._clearSince or tick()
            if (tick() - B._clearSince) >= 0.6 then
                S.banditResumeRun()
            end
        end
    end

    -- Posisi di bawah bandit (hanya saat Run dijeda, atau Run mati).
    if B.underMode and #targets > 0 and (not runOn or B.paused) then
        local keep = false
        for _, mob in ipairs(targets) do
            if mob == B.underTarget then
                keep = true
                break
            end
        end
        if not keep then
            B.underTarget = targets[1]
        end
    else
        S.banditLeaveUnder()
    end

    if #targets == 0 or (tick() - B._lastAttack) < 0.45 then
        return
    end
    B._lastAttack = tick()
    S.banditAttack(targets)
end

function S.setBanditFarm(enabled)
    local B = S.Bandit
    B.enabled = enabled == true
    S.disconnectAll("banditFarm")
    S.disconnectAll("banditUnder")

    if not B.enabled then
        B.busy = false
        pcall(S.banditLeaveUnder)
        pcall(S.banditResumeRun)
        return
    end

    State.connections.banditUnder = RunService.Heartbeat:Connect(function()
        pcall(S.banditFollowUnder)
    end)

    State.connections.banditFarm = RunService.Heartbeat:Connect(function()
        if not B.enabled or B.busy or (tick() - B._lastTick) < B.interval then
            return
        end
        B._lastTick = tick()
        B.busy = true
        task.spawn(function()
            pcall(S.banditStep)
            B.busy = false
        end)
    end)
end

function S.isNpcAttacking(mob)
    if not mob then
        return false
    end

    for _, tagged in ipairs(CollectionService:GetTagged("NpcManager")) do
        local model = S.getNpcModelFromManager(tagged)
        if model == mob then
            local force = tagged:GetAttribute("ForceAnimation")
            if typeof(force) == "string" and force ~= "" then
                local lower = string.lower(force)
                if string.find(lower, "attack", 1, true)
                    or string.find(lower, "slash", 1, true)
                    or string.find(lower, "swing", 1, true)
                    or string.find(lower, "bite", 1, true)
                    or string.find(lower, "smash", 1, true) then
                    return true
                end
            end
        end
    end

    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local name = string.lower(track.Name or "")
            local animName = track.Animation and string.lower(track.Animation.Name or "") or ""
            if string.find(name, "attack", 1, true)
                or string.find(animName, "attack", 1, true)
                or string.find(name, "slash", 1, true)
                or string.find(animName, "slash", 1, true) then
                return true
            end
        end
    end

    return false
end

function S.collectAttackDangerZones(rootPos, options)
    options = options or {}
    local scanBonus = tonumber(options.scanBonus) or 0
    local reachBonus = tonumber(options.reachBonus) or 0
    local earlyEngage = options.earlyEngage == true

    local zones = {}
    local scanRange = math.max(Combat.dodgeRadius * 2.5, 36) + scanBonus
    local mobs = S.findHostileMobsInRange(scanRange)

    for _, mob in ipairs(mobs) do
        local pivot = mob:GetPivot()
        local mobPos = pivot.Position
        local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
        if look.Magnitude < 0.05 then
            look = Vector3.new(0, 0, -1)
        else
            look = look.Unit
        end

        local okBox, _, size = pcall(function()
            return mob:GetBoundingBox()
        end)
        if not okBox or typeof(size) ~= "Vector3" then
            size = Vector3.new(4, 6, 4)
        end

        local reach = math.max(Combat.dodgeRadius, (size.X + size.Z) * 0.55 + 6) + reachBonus
        local attacking = S.isNpcAttacking(mob)
        if attacking then
            reach = reach * 1.35
        end

        local toPlayer = Vector3.new(rootPos.X - mobPos.X, 0, rootPos.Z - mobPos.Z)
        local dist = toPlayer.Magnitude
        local engagePad = earlyEngage and 5 or 2
        if dist <= reach + engagePad then
            local facing = 0
            if dist > 0.05 then
                facing = toPlayer.Unit:Dot(look)
            end

            -- Proactive: leave melee cone / close body range BEFORE windup finishes.
            local inFrontCone = facing > -0.25
            local tooClose = dist <= math.max(Combat.dodgeKeepDistance, reach * 0.55)
            local earlyUnder = earlyEngage and dist <= (reach + engagePad)
            local hitPartThreat = false
            local center = mobPos + look * math.min(reach * 0.45, 8)

            for _, part in ipairs(mob:GetDescendants()) do
                if part:IsA("BasePart") then
                    local n = string.lower(part.Name)
                    if string.find(n, "hit", 1, true)
                        or string.find(n, "attack", 1, true)
                        or string.find(n, "damage", 1, true)
                        or string.find(n, "hurt", 1, true)
                        or string.find(n, "claw", 1, true) then
                        hitPartThreat = true
                        center = part.Position
                        reach = math.max(reach, math.max(part.Size.X, part.Size.Z) * 0.7 + 4)
                    end
                end
            end

            if attacking or hitPartThreat or tooClose or (inFrontCone and dist <= reach) or earlyUnder then
                local urgency = 1
                if attacking or hitPartThreat then
                    urgency = 3
                elseif tooClose then
                    urgency = 2
                end
                table.insert(zones, {
                    center = center,
                    mobPos = mobPos,
                    radius = reach,
                    mob = mob,
                    urgency = urgency,
                    dist = dist,
                })
            end
        end
    end

    return zones
end

function S.findSafeFleePosition(rootPos, dangerCenter, step)
    local away = Vector3.new(rootPos.X - dangerCenter.X, 0, rootPos.Z - dangerCenter.Z)
    if away.Magnitude < 0.15 then
        away = Vector3.new(1, 0, 0)
    else
        away = away.Unit
    end

    local char = LocalPlayer.Character
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char }
    params.IgnoreWater = true

    local angles = { 0, 22, -22, 45, -45, 70, -70, 100, -100, 140, -140, 180 }
    local bestPos, bestScore = nil, -1

    for _, deg in ipairs(angles) do
        local dir = (CFrame.Angles(0, math.rad(deg), 0):VectorToWorldSpace(away)).Unit
        local origin = rootPos + Vector3.new(0, 2.5, 0)
        local hit = Workspace:Raycast(origin, dir * step, params)
        local travel = hit and math.max(0, hit.Distance - 1.8) or step
        if travel >= 2.5 then
            local candidate = rootPos + dir * math.min(travel, step)
            local groundHit = Workspace:Raycast(candidate + Vector3.new(0, 6, 0), Vector3.new(0, -24, 0), params)
            if groundHit then
                candidate = Vector3.new(candidate.X, groundHit.Position.Y + 3, candidate.Z)
            end

            local sideHit = Workspace:Raycast(candidate + Vector3.new(0, 2.5, 0), dir * 2.2, params)
            local score = travel + (math.abs(deg) < 35 and 2 or 0)
            if sideHit then
                score -= 5
            end
            if score > bestScore then
                bestScore = score
                bestPos = candidate
            end
        end
    end

    return bestPos
end

function S.smoothMoveToward(root, targetPos, dt, speed, allowVertical)
    local current = root.Position
    local delta = allowVertical and (targetPos - current) or Vector3.new(targetPos.X - current.X, 0, targetPos.Z - current.Z)
    local dist = delta.Magnitude
    if dist < 0.35 then
        return false
    end

    local moveSpeed = speed or Combat.dodgeSpeed
    local step = math.min(dist, moveSpeed * math.max(dt, 1 / 120))
    local nextPos = current + delta.Unit * step

    if not allowVertical then
        nextPos = Vector3.new(nextPos.X, current.Y, nextPos.Z)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { LocalPlayer.Character }
        local ground = Workspace:Raycast(nextPos + Vector3.new(0, 4, 0), Vector3.new(0, -16, 0), params)
        if ground then
            nextPos = Vector3.new(nextPos.X, ground.Position.Y + 3, nextPos.Z)
        end
    end

    local alpha = math.clamp(dt * 14, 0.08, 0.45)
    local blended = current:Lerp(nextPos, alpha)
    root.CFrame = CFrame.new(blended) * (root.CFrame - root.CFrame.Position)

    local vel = delta.Unit * moveSpeed
    if allowVertical then
        root.AssemblyLinearVelocity = vel
    else
        root.AssemblyLinearVelocity = Vector3.new(vel.X, root.AssemblyLinearVelocity.Y, vel.Z)
    end
    return true
end

function S.getMobAbovePosition(mob, height)
    if not mob then
        return nil
    end

    local pivot = mob:GetPivot()
    local okBox, cf, size = pcall(function()
        return mob:GetBoundingBox()
    end)

    local topY = pivot.Position.Y + 3
    local x, z = pivot.Position.X, pivot.Position.Z
    if okBox and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
        topY = cf.Position.Y + (size.Y * 0.5)
        x, z = cf.Position.X, cf.Position.Z
    end

    return Vector3.new(x, topY + (height or Combat.dodgeAboveHeight), z)
end

function S.getMobUnderPosition(mob, depth)
    if not mob then
        return nil
    end

    local pivot = mob:GetPivot()
    local okBox, cf, size = pcall(function()
        return mob:GetBoundingBox()
    end)

    local bottomY = pivot.Position.Y - 2
    local x, z = pivot.Position.X, pivot.Position.Z
    if okBox and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
        bottomY = cf.Position.Y - (size.Y * 0.5)
        x, z = cf.Position.X, cf.Position.Z
    end

    return Vector3.new(x, bottomY - (depth or Combat.dodgeUnderDepth), z)
end

function S.recoverFromUnder(root)
    if not root then
        return false
    end

    local x = root.Position.X
    local z = root.Position.Z
    if Combat.underLastSafeXZ then
        x = Combat.underLastSafeXZ.X
        z = Combat.underLastSafeXZ.Z
    end

    local probe = Vector3.new(x, math.max(root.Position.Y + 120, 120), z)
    local groundY = S.getGroundY(probe)

    if groundY < -50 or groundY ~= groundY then
        local drill = S.getDrill()
        if drill then
            local dpos = drill:GetPivot().Position
            groundY = S.getGroundY(Vector3.new(dpos.X, dpos.Y + 120, dpos.Z))
            x, z = dpos.X, dpos.Z
        else
            groundY = 5
        end
    end

    root.CFrame = CFrame.new(Vector3.new(x, groundY + 4, z)) * (root.CFrame - root.CFrame.Position)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    Combat.underActive = false
    return true
end

function S.snapUnderMob(root, mob)
    local under = S.getMobUnderPosition(mob, Combat.dodgeUnderDepth)
    if not under then
        return false
    end

    -- Instant — no smooth delay (hits land before lerp finishes)
    root.CFrame = CFrame.new(under) * (root.CFrame - root.CFrame.Position)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    Combat.underActive = true
    Combat.underLastSafeXZ = Vector3.new(under.X, 0, under.Z)
    return true
end

function S.dodgeAttackHitboxes(dt)
    local root = S.getRoot()
    if not root then
        return false
    end

    local mode = Combat.dodgeMode
    if mode ~= "Under" and Combat.underActive then
        S.recoverFromUnder(root)
    end

    local zones
    if mode == "Under" then
        zones = S.collectAttackDangerZones(root.Position, {
            scanBonus = Combat.dodgeUnderScanBonus or 8,
            reachBonus = Combat.dodgeUnderReachBonus or 3,
            earlyEngage = true,
        })

        if #zones == 0 then
            if Combat.underActive then
                return S.recoverFromUnder(root)
            end
            return false
        end

        table.sort(zones, function(a, b)
            if a.urgency ~= b.urgency then
                return a.urgency > b.urgency
            end
            return a.dist < b.dist
        end)

        local danger = zones[1]
        local mob = danger and danger.mob
        if not mob or not mob.Parent or not S.isHostileMob(mob) then
            return S.recoverFromUnder(root)
        end

        return S.snapUnderMob(root, mob)
    end

    zones = S.collectAttackDangerZones(root.Position)
    if #zones == 0 then
        return false
    end

    table.sort(zones, function(a, b)
        if a.urgency ~= b.urgency then
            return a.urgency > b.urgency
        end
        return a.dist < b.dist
    end)

    local danger = zones[1]
    local boost = danger.urgency >= 3 and (Combat.dodgeSpeed * 1.35) or Combat.dodgeSpeed

    if mode == "Above" then
        local above = S.getMobAbovePosition(danger.mob, Combat.dodgeAboveHeight)
        if not above then
            return false
        end
        return S.smoothMoveToward(root, above, dt or 0.016, boost, true)
    end

    local desiredDist = math.max(Combat.dodgeKeepDistance, danger.radius * 0.85)
    local fromDanger = Vector3.new(root.Position.X - danger.center.X, 0, root.Position.Z - danger.center.Z)
    if fromDanger.Magnitude < desiredDist then
        local safe = S.findSafeFleePosition(root.Position, danger.center, Combat.dodgeStep + (danger.urgency * 2))
        if safe then
            return S.smoothMoveToward(root, safe, dt or 0.016, boost, false)
        end
    end

    return false
end

function S.setDodgeHitbox(enabled)
    Combat.dodgeHitbox = enabled
    S.disconnectAll("dodgeHitbox")

    if not enabled then
        local root = S.getRoot()
        if Combat.underActive and root then
            S.recoverFromUnder(root)
        end
        Combat.underActive = false
        return
    end

    State.connections.dodgeHitbox = RunService.Heartbeat:Connect(function(dt)
        if not Combat.dodgeHitbox then
            return
        end
        pcall(S.dodgeAttackHitboxes, dt)
    end)
end

function S.isCharacterRiding()
    local humanoid = S.getHumanoid()
    if humanoid and humanoid.Sit then
        return true
    end
    local root = S.getRoot()
    if root and root:FindFirstChild("SeatWeld") then
        return true
    end
    return false
end

function S.setRideAutoJump(enabled)
    Combat.rideAutoJump = enabled == true
    S.disconnectAll("rideAutoJump")
    if not Combat.rideAutoJump then
        return
    end
    State.connections.rideAutoJump = RunService.Heartbeat:Connect(function()
        if not Combat.rideAutoJump or Autofarm.miningBusy then
            return
        end
        if not S.isCharacterRiding() then
            return
        end
        local range = math.max(8, tonumber(Combat.rideJumpRange) or 28)
        local mobs = S.findHostileMobsInRange(range)
        if #mobs == 0 then
            return
        end
        local humanoid = S.getHumanoid()
        if humanoid then
            humanoid.Jump = true
        end
        if Combat.dodgeHitbox then
            pcall(S.dodgeAttackHitboxes, 0.03)
        end
    end)
end

function S.isItemWelded(item)
    return item ~= nil and item:GetAttribute("Welded") == true
end

function S.weldItem(item)
    if not item or not Services.DragService then
        return false
    end

    local ok, result = pcall(function()
        return Services.DragService:Weld(item)
    end)
    if not ok then
        return false
    end

    if typeof(result) == "table" and result.andThen then
        pcall(function()
            result:andThen(function() end):catch(function() end)
        end)
        return true
    end

    return result == "attached" or result == "detached" or result == true or result == nil
end

function S.snapshotItemsSet()
    local set = {}
    local folder = Workspace:FindFirstChild("Items")
    if not folder then
        return set
    end
    for _, child in ipairs(folder:GetChildren()) do
        set[child] = true
    end
    return set
end

function S.findNewWorldItems(beforeSet)
    local news = {}
    local folder = Workspace:FindFirstChild("Items")
    if not folder then
        return news
    end
    for _, child in ipairs(folder:GetChildren()) do
        if not beforeSet[child] then
            table.insert(news, child)
        end
    end
    return news
end

-- Drop sack fuel onto the cart bed and Weld (Z). Never into FuelTouchPart / fire.
function S.collectTruckItems()
    local items = {}
    local folder = Workspace:FindFirstChild("Items")
    if not folder then
        return items
    end

    State.cachedTruckRegion = S.getDrillTruckRegion()
    for _, child in ipairs(folder:GetChildren()) do
        if S.isItemInTruckZone(child) then
            table.insert(items, child)
        end
    end
    return items
end

function S.lockTruckItems(wantLocked)
    if not Services.DragService then
        return 0, "DragService not ready"
    end

    local changed = 0
    for _, item in ipairs(S.collectTruckItems()) do
        local welded = S.isItemWelded(item)
        if wantLocked and not welded then
            if S.weldItem(item) then
                changed += 1
            end
        elseif not wantLocked and welded then
            if S.weldItem(item) then
                changed += 1
            end
        end
        task.wait(0.03)
    end

    return changed
end

function S.autoLockTruckCycle()
    if TruckLock.busy or not Services.DragService then
        return 0
    end

    TruckLock.busy = true
    local locked = 0
    local ok, err = pcall(function()
        for _, item in ipairs(S.collectTruckItems()) do
            if not S.isItemWelded(item) and (S.isItemTouchingTruckWeld(item) or S.isItemInTruckZone(item)) then
                if S.weldItem(item) then
                    locked += 1
                end
                task.wait(0.02)
            end
        end
    end)
    TruckLock.busy = false

    if not ok then
        warn("[TERRA HUB] autoLockTruck", err)
    end
    return locked
end

function S.setAutoLockTruck(enabled)
    TruckLock.autoLock = enabled
    S.disconnectAll("autoLockTruck")

    if not enabled then
        return
    end

    State.connections.autoLockTruck = RunService.Heartbeat:Connect(function()
        if not TruckLock.autoLock or TruckLock.busy or (tick() - (State.lastAutoLockTick or 0)) < 0.35 then
            return
        end
        State.lastAutoLockTick = tick()
        task.spawn(S.autoLockTruckCycle)
    end)
end

function S.toggleRayfieldFlag(flagName)
    if not Rayfield or not Rayfield.Flags then
        return
    end
    local flag = Rayfield.Flags[flagName]
    if not flag then
        return
    end
    local current = flag.CurrentValue
    if typeof(current) ~= "boolean" then
        current = false
    end
    local newValue = not current
    if flag.Set then
        pcall(function()
            flag:Set(newValue)
        end)
    else
        flag.CurrentValue = newValue
        if flag.Callback then
            pcall(flag.Callback, newValue)
        end
    end
end

function S.isKeybindBound(keyName)
    if type(keyName) ~= "string" then
        return false
    end
    if keyName == "" or keyName == "None" or keyName == "Unbound" or keyName == "Unknown" then
        return false
    end
    local ok, code = pcall(function()
        return Enum.KeyCode[keyName]
    end)
    return ok and code ~= nil
end

function S.startKeybindListener()
    S.disconnectAll("hubKeybinds")
    Keybinds.list = Keybinds.list or {}

    State.connections.hubKeybinds = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end
        if tick() - (State.lastKeybindToggle or 0) < 0.25 then
            return
        end

        local pressed = input.KeyCode.Name
        for _, entry in ipairs(Keybinds.list) do
            local bound = entry.settings and entry.settings.CurrentKeybind
            if S.isKeybindBound(bound) and bound == pressed then
                State.lastKeybindToggle = tick()
                S.toggleRayfieldFlag(entry.flag)
                break
            end
        end
    end)
end

-- ========== TELEPORT (villages, dungeons, mines) ==========
function S.getDoorEntranceCFrame(doorInstance, standDistance)
    standDistance = standDistance or 6
    if not doorInstance then
        return nil
    end

    local part = doorInstance:IsA("BasePart") and doorInstance or doorInstance:FindFirstChildWhichIsA("BasePart", true)
    if not part then
        return nil
    end

    local away = part.CFrame.LookVector
    local flatAway = Vector3.new(away.X, 0, away.Z)
    if flatAway.Magnitude < 0.05 then
        flatAway = Vector3.new(0, 0, 1)
    else
        flatAway = flatAway.Unit
    end

    local stand = part.Position + flatAway * standDistance
    local groundY = S.getGroundY(stand)
    local standPos = Vector3.new(stand.X, groundY + 3, stand.Z)
    local lookAt = Vector3.new(part.Position.X, groundY + 3, part.Position.Z)
    return CFrame.lookAt(standPos, lookAt)
end

function S.isMineRoot(inst)
    if not inst:IsA("Model") then
        return false
    end
    if inst.Name == "Mineshaft" or inst.Name == "VoidMineshaft" then
        return true
    end
    if CollectionService:HasTag(inst, "Mineshaft") and inst:FindFirstChild("Gate_Mineshaft", true) then
        return true
    end
    return false
end

function S.isHubDungeonRoot(inst)
    -- Same rule as autofarm: only DungeonGate_* models.
    return S.isDungeonRoot(inst)
end

function S.isVillageModel(inst)
    if not inst:IsA("Model") or S.isMineRoot(inst) or S.isHubDungeonRoot(inst) then
        return false
    end
    if inst.Name == "BountyCamp" or inst.Name == "TradingCampTutorial" or inst.Name == "MinerTown" then
        return true
    end
    if inst.Name:match("^CampTier") then
        return true
    end
    if inst:FindFirstChild("Sell_Table", true) or inst:FindFirstChild("SellPart", true) then
        return true
    end
    if inst:FindFirstChild("TradingPostMini", true) then
        return true
    end
    if inst.Name:find("Fortress") and inst:FindFirstChild("TradingPost", true) then
        return true
    end
    return false
end

function S.getFlatDistanceToPlayer(inst)
    local root = S.getRoot()
    local pos = S.getInstancePosition(inst)
    if not root or not pos then
        return math.huge
    end
    return (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
end

function S.scanWorldModels(callback)
    local seen = {}

    local function visit(inst)
        if seen[inst] or not inst:IsA("Model") then
            return
        end
        seen[inst] = true
        callback(inst)
    end

    for _, child in ipairs(Workspace:GetChildren()) do
        visit(child)
    end

    local chunks = Workspace:FindFirstChild("Chunks")
    if chunks then
        for _, desc in ipairs(chunks:GetDescendants()) do
            if desc:IsA("Model") and (desc.Name:find("Fortress") or desc.Name:find("Camp")) then
                visit(desc)
            end
        end
    end
end

-- ========== ESP ==========
local EspDrawingSupported = typeof(Drawing) == "table" and pcall(function()
    local line = Drawing.new("Line")
    line:Remove()
end)

function S.getDistanceToPlayer(pos)
    local root = S.getRoot()
    if not root or not pos then
        return math.huge
    end
    return (root.Position - pos).Magnitude
end

function S.getEspAdornee(target)
    if not target or not target.Parent then
        return nil
    end
    if target:IsA("BasePart") then
        return target
    end
    if target:IsA("Model") then
        return target.PrimaryPart
            or target:FindFirstChild("HumanoidRootPart")
            or target:FindFirstChildWhichIsA("BasePart", true)
    end
    return target:FindFirstChildWhichIsA("BasePart", true)
end

function S.getEspWorldPosition(target)
    local adornee = S.getEspAdornee(target)
    if adornee then
        return adornee.Position
    end
    return S.getItemPosition(target) or S.getInstancePosition(target)
end

function S.worldToScreen(pos)
    local camera = Workspace.CurrentCamera
    if not camera or not pos then
        return nil, false
    end
    local screenPos, onScreen = camera:WorldToViewportPoint(pos)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen and screenPos.Z > 0
end

function S.getLootEspColor(item)
    local cat = S.itemCategoryKey(item)
    local name = string.lower(item.Name)

    for _, selected in ipairs(Esp.lootCategories) do
        if selected == "All Items" then
            return LOOT_ESP_COLORS["All Items"] or ESP_COLORS.loot
        end
        local key = string.lower(selected)
        if key ~= "" and (cat == key or cat:find(key, 1, true) or name:find(key, 1, true)) then
            return LOOT_ESP_COLORS[selected] or ESP_COLORS.loot
        end
    end

    return ESP_COLORS.loot
end

function S.passesLootEspFilter(item)
    if not item or not item.Parent or S.isHardExcluded(item) then
        return false
    end
    if #Esp.lootCategories == 0 then
        return false
    end

    for _, selected in ipairs(Esp.lootCategories) do
        if selected == "All Items" then
            return true
        end
    end

    local cat = S.itemCategoryKey(item)
    local name = string.lower(item.Name)
    for _, selected in ipairs(Esp.lootCategories) do
        local key = string.lower(selected)
        if key ~= "" and (cat == key or cat:find(key, 1, true) or name:find(key, 1, true)) then
            return true
        end
    end

    return false
end

function S.getFlatDistanceFromPosition(pos)
    local root = S.getRoot()
    if not root or not pos then
        return math.huge
    end
    return (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
end

function S.collectEspLootTargets()
    local targets = {}
    local seen = {}

    local function tryAdd(item)
        if item and S.passesLootEspFilter(item) and not seen[item] then
            local pos = S.getItemPosition(item)
            if pos and S.getFlatDistanceFromPosition(pos) <= Esp.maxRange then
                seen[item] = true
                table.insert(targets, {
                    inst = item,
                    name = item.Name,
                    pos = pos,
                    color = S.getLootEspColor(item),
                    kind = "loot",
                })
            end
        end
    end

    S.forEachWorldLootItem(tryAdd)

    return targets
end

function S.getNpcModelFromManager(managerInst)
    if not managerInst then
        return nil
    end
    if managerInst:IsA("Model") and managerInst:FindFirstChildOfClass("Humanoid") then
        return managerInst
    end
    local parent = managerInst.Parent
    if parent and parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
        return parent
    end
    return managerInst:FindFirstAncestorOfClass("Model")
end

function S.isHostileMob(model)
    if not model or not model.Parent then
        return false
    end
    if Players:GetPlayerFromCharacter(model) then
        return false
    end
    if model:GetAttribute("NpcFaction") == "FriendlyCompanion" then
        return false
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

function S.getNpcFolder()
    return Workspace:FindFirstChild("Npc") or Workspace:FindFirstChild("NPC")
end

-- Dump: OnFace → clone parented to CurrentCamera (FaceSuck). Real worm stays tagged in Npc.
function S.getCameraFaceWormModel()
    local cam = Workspace.CurrentCamera
    if not cam then
        return nil
    end
    for _, child in ipairs(cam:GetChildren()) do
        if not child:IsA("Model") then
            continue
        end
        if not child:FindFirstChildOfClass("Humanoid") then
            continue
        end
        local n = string.lower(child.Name or "")
        if S.isDeathWorm(child) or n:find("worm", 1, true) then
            return child
        end
    end
    return nil
end

function S.invokeClientToolSwing()
    local knit = S.getKnit()
    if not knit then
        return false
    end
    local ok, controller = pcall(function()
        return knit.GetController("ToolController")
    end)
    if not ok or not controller or not controller.ActiveTool then
        return false
    end
    local active = controller.ActiveTool
    if type(active.Swing) ~= "function" then
        return false
    end
    local swung = false
    pcall(function()
        active:Swing()
        swung = true
    end)
    return swung
end

-- Prefer real client swing (pickaxe hit scan → server). Remote only as fallback.
function S.fireMeleeSwingTargets(targets)
    if type(targets) ~= "table" or #targets == 0 then
        return false
    end

    S.ensurePickaxe(0.4)
    local tool = S.getEquippedTool()
    if tool and S.isPickaxeTool(tool) then
        S.boostToolRange(tool, 30000)
    elseif tool and S.isCombatTool(tool) then
        S.boostToolRange(tool, math.max(Combat.auraRange or 30000, 500))
    end

    if S.invokeClientToolSwing() then
        return true
    end

    if Services.ToolService and Services.ToolService.Update then
        pcall(function()
            Services.ToolService.Update:Fire({ "Swing", targets })
        end)
        return true
    end
    return false
end

-- Dump: WormComponent tag "Worm", ObjectValue Target, attribute OnFace (camera suck / damage).
function S.isDeathWorm(model)
    if not model or not model.Parent then
        return false
    end
    local okTag, tagged = pcall(function()
        return CollectionService:HasTag(model, "Worm")
    end)
    if okTag and tagged then
        return true
    end
    local name = string.lower(tostring(model:GetAttribute("RealName") or model.Name or ""))
    if name:find("deathworm", 1, true) or name:find("death_worm", 1, true) then
        return true
    end
    if name == "worm" or name:find("worm", 1, true) then
        -- Avoid matching random "WormNode" props — need humanoid.
        return model:FindFirstChildOfClass("Humanoid") ~= nil
    end
    return false
end

function S.getWormTargetCharacter(worm)
    if not worm then
        return nil
    end
    local target = worm:FindFirstChild("Target")
    if target and target:IsA("ObjectValue") then
        return target.Value
    end
    return nil
end

-- Threatening = chasing you, on your face, or on-screen nearby after a worm ore break.
function S.isWormThreateningLocal(worm)
    if not S.isDeathWorm(worm) or not S.isHostileMob(worm) then
        return false
    end
    if worm:GetAttribute("OnFace") == true then
        return true
    end
    local char = LocalPlayer.Character
    if char and S.getWormTargetCharacter(worm) == char then
        return true
    end
    local pos = S.getEspWorldPosition(worm) or S.getInstancePosition(worm)
    if not pos then
        return false
    end
    local dist = S.getDistanceToPlayer(pos)
    if dist and dist <= 120 then
        return true
    end
    local _, onScreen = S.worldToScreen(pos)
    if onScreen and dist and dist <= 350 then
        return true
    end
    return false
end

function S.collectFaceDeathWorms()
    local list = {}
    local seen = {}
    local char = LocalPlayer.Character

    local function add(model)
        if not model or seen[model] or not model.Parent then
            return
        end
        if not S.isDeathWorm(model) or not S.isHostileMob(model) then
            return
        end
        seen[model] = true
        table.insert(list, model)
    end

    pcall(function()
        for _, tagged in ipairs(CollectionService:GetTagged("Worm")) do
            if tagged:GetAttribute("OnFace") == true then
                add(tagged)
            end
        end
    end)

    local npcFolder = S.getNpcFolder()
    if npcFolder then
        for _, child in ipairs(npcFolder:GetChildren()) do
            if child:IsA("Model") and child:GetAttribute("OnFace") == true then
                add(child)
            end
        end
    end

    if #list == 0 and S.getCameraFaceWormModel() and char then
        pcall(function()
            for _, tagged in ipairs(CollectionService:GetTagged("Worm")) do
                if S.getWormTargetCharacter(tagged) == char then
                    add(tagged)
                end
            end
        end)
        if npcFolder then
            for _, child in ipairs(npcFolder:GetChildren()) do
                if child:IsA("Model") and S.getWormTargetCharacter(child) == char then
                    add(child)
                end
            end
        end
    end

    return list
end

function S.hasFaceDeathWormThreat()
    if S.getCameraFaceWormModel() then
        return true
    end
    return #S.collectFaceDeathWorms() > 0
end

function S.collectThreateningDeathWorms()
    local list = {}
    local seen = {}

    local function consider(model)
        if not model or seen[model] then
            return
        end
        if S.isWormThreateningLocal(model) then
            seen[model] = true
            table.insert(list, model)
        end
    end

    for _, worm in ipairs(S.collectFaceDeathWorms()) do
        consider(worm)
    end

    pcall(function()
        for _, tagged in ipairs(CollectionService:GetTagged("Worm")) do
            consider(tagged)
        end
    end)

    local npcFolder = S.getNpcFolder()
    if npcFolder then
        for _, child in ipairs(npcFolder:GetChildren()) do
            if child:IsA("Model") then
                consider(child)
            end
        end
    end

    return list
end

function S.resumePickaxeAfterWormKill()
    if Autofarm.enabled and (Autofarm.miningBusy or Autofarm._oreHuntMode or Autofarm.oreUnderEnabled) then
        pcall(function()
            S.ensurePickaxe(0.6)
        end)
    end
end

function S.wormsStillAlive(worms)
    for _, worm in ipairs(worms or {}) do
        if worm and worm.Parent and S.isHostileMob(worm) then
            return true
        end
    end
    return false
end

-- Face worm on camera → pickaxe client swing (game hit scan), not raw remote spam.
function S.tryAutoKillFaceWorms()
    if Combat._killingWorm then
        return 0
    end
    if not Combat.autoKillFaceWorms and not Autofarm.enabled then
        return 0
    end
    if not S.hasFaceDeathWormThreat() then
        return 0
    end

    Combat._killingWorm = true
    local swings = 0
    local ok, err = pcall(function()
        for _ = 1, 10 do
            if not S.hasFaceDeathWormThreat() then
                break
            end

            local worms = S.collectFaceDeathWorms()
            local targets = {}
            for _, worm in ipairs(worms) do
                table.insert(targets, worm)
            end

            if #targets == 0 then
                S.ensurePickaxe(0.4)
                local tool = S.getEquippedTool()
                if tool and S.isPickaxeTool(tool) then
                    S.boostToolRange(tool, 30000)
                end
                S.invokeClientToolSwing()
            else
                S.fireMeleeSwingTargets(targets)
            end
            swings += 1
            task.wait(0.07)

            if not S.wormsStillAlive(worms) and not S.getCameraFaceWormModel() then
                break
            end
        end
    end)
    if not ok then
        warn("[TERRA HUB] autoKillFaceWorms", err)
    end

    Combat._killingWorm = false
    S.resumePickaxeAfterWormKill()
    return swings
end

-- Interrupt dig briefly: pickaxe swing (client) → kill worm(s) → pickaxe back if still farming.
function S.tryAutoKillDeathWorms()
    if Combat._killingWorm then
        return 0
    end

    if S.hasFaceDeathWormThreat() then
        return S.tryAutoKillFaceWorms()
    end

    if not Combat.autoKillDeathWorms then
        return 0
    end

    local worms = S.collectThreateningDeathWorms()
    if #worms == 0 then
        return 0
    end

    Combat._killingWorm = true
    local killed = 0
    local ok, err = pcall(function()
        for _ = 1, 12 do
            worms = S.collectThreateningDeathWorms()
            if #worms == 0 then
                break
            end
            S.fireMeleeSwingTargets(worms)
            killed = math.max(killed, #worms)
            task.wait(0.08)
            if not S.wormsStillAlive(worms) then
                break
            end
        end
    end)
    if not ok then
        warn("[TERRA HUB] autoKillDeathWorms", err)
    end

    Combat._killingWorm = false
    S.resumePickaxeAfterWormKill()
    return killed
end

function S.tickAutoKillFaceWorms()
    if Combat._killingWorm then
        return
    end
    if not Combat.autoKillFaceWorms and not Autofarm.enabled then
        return
    end
    if not S.hasFaceDeathWormThreat() then
        return
    end
    local now = tick()
    if now - (Combat._lastFaceWormTick or 0) < 0.1 then
        return
    end
    Combat._lastFaceWormTick = now
    task.spawn(function()
        pcall(S.tryAutoKillFaceWorms)
    end)
end

function S.ensureFaceWormGuard()
    if State.connections.faceWormGuard then
        return
    end
    State.connections.faceWormGuard = RunService.Heartbeat:Connect(function()
        S.tickAutoKillFaceWorms()
    end)
end

function S.setAutoKillDeathWorms(enabled)
    Combat.autoKillDeathWorms = enabled == true
    S.disconnectAll("autoKillDeathWorms")
    if not Combat.autoKillDeathWorms then
        Combat._killingWorm = false
        return
    end

    local lastTick = 0
    State.connections.autoKillDeathWorms = RunService.Heartbeat:Connect(function()
        if not Combat.autoKillDeathWorms or Combat._killingWorm then
            return
        end
        if tick() - lastTick < 0.35 then
            return
        end
        lastTick = tick()
        task.spawn(function()
            pcall(S.tryAutoKillDeathWorms)
        end)
    end)
end

function S.collectEspMobs()
    local mobs = {}
    local seen = {}

    for _, tagged in ipairs(CollectionService:GetTagged("NpcManager")) do
        local model = S.getNpcModelFromManager(tagged)
        if model and S.isHostileMob(model) and not seen[model] then
            local pos = S.getEspWorldPosition(model)
            if pos and S.getDistanceToPlayer(pos) <= Esp.maxRange then
                seen[model] = true
                local displayName = model:GetAttribute("RealName") or model.Name
                table.insert(mobs, {
                    inst = model,
                    name = displayName,
                    pos = pos,
                    color = ESP_COLORS.mob,
                    kind = "mob",
                })
            end
        end
    end

    return mobs
end

-- ESP: Workspace Ore_Node* with SessionOreType. Soft gem highlight + clean label.
function S.collectEspOres()
    local ores = {}
    local maxRange = Esp.maxRange or 2000

    S.forEachWorldOreNode(function(inst)
        local sessionType = inst:GetAttribute("SessionOreType")
        if type(sessionType) ~= "string" or sessionType == "" then
            return
        end

        -- Position from Rock/world anchor — not dump-coords Ore mesh.
        local pos = S.getOreWorldPosition(inst)
        local adornee = S.getOreAnchorPart(inst, nil) or S.getOreEspAdornee(inst)
        if not pos or not adornee then
            return
        end

        local dist = S.getFlatDistanceFromPosition(pos)
        if not dist or dist > maxRange then
            return
        end

        table.insert(ores, {
            inst = inst,
            name = sessionType,
            pos = pos,
            color = S.getOreEspColor(inst),
            kind = "ore",
            dist = dist,
        })
    end)

    table.sort(ores, function(a, b)
        return (a.dist or 0) < (b.dist or 0)
    end)

    -- Roblox Highlight soft-cap ~31 — nearest get outline, all get labels.
    for i, entry in ipairs(ores) do
        entry.useHighlight = i <= 28
    end

    return ores
end

-- Soft Chest MeshPart (not giant model bounds).
function S.getChestEspAdornee(chest)
    if not chest then
        return nil
    end
    local mesh = chest:FindFirstChild("Chest")
    if mesh and mesh:IsA("BasePart") then
        return mesh
    end
    for _, desc in ipairs(chest:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name == "Chest" then
            return desc
        end
    end
    local root = chest:FindFirstChild("RootPart")
    if root and root:IsA("BasePart") then
        return root
    end
    if chest:IsA("BasePart") then
        return chest
    end
    if chest:IsA("Model") then
        return chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

-- DiamondChest → Diamond, VoidChest → Void, CommonChest → Common, Gold_Chest → Gold
function S.getChestEspLabel(chest)
    if not chest then
        return "Chest"
    end
    local clean = S.getChestTypeKey(chest)
    if S.isChestPadlocked(chest) then
        return clean .. " [Locked]"
    end
    return clean
end

function S.normalizeChestTypeToken(name)
    local key = tostring(name or "")
    key = key:gsub("_Chest$", ""):gsub("_chest$", "")
    key = key:gsub("Chest$", ""):gsub("chest$", "")
    key = key:gsub("^_+", ""):gsub("_+$", "")
    key = key:gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then
        key = "Chest"
    end
    return key
end

function S.getChestTypeKey(chest)
    return S.normalizeChestTypeToken(chest and chest.Name or "Chest")
end

function S.chestTypeStrings(chest)
    local out = {}
    local function add(value)
        if type(value) == "string" and value ~= "" then
            out[#out + 1] = value
        end
    end
    if not chest then
        return out
    end
    add(chest.Name)
    local parent = chest.Parent
    if parent and parent.Name ~= "ChestNode" and parent.Name ~= "ChestNodes" then
        add(parent.Name)
    end
    for _, attr in ipairs({ "Type", "ChestType", "Rarity", "Category", "ChestId", "Id", "Name", "DisplayName", "Tier" }) do
        pcall(function()
            add(chest:GetAttribute(attr))
        end)
    end
    local prompts = S.collectProximityPrompts(chest)
    local prompt = prompts[1]
    if prompt then
        add(prompt.ObjectText)
        if prompt.Parent then
            add(prompt.Parent.Name)
        end
    end
    for _, child in ipairs(chest:GetChildren()) do
        local n = string.lower(child.Name)
        if n:find("chest", 1, true) or n:find("core", 1, true) then
            add(child.Name)
        end
    end
    return out
end

function S.chestCanon(chest)
    for _, raw in ipairs(S.chestTypeStrings(chest)) do
        local canon = S.canonChestKey(S.normalizeChestTypeToken(raw))
        local rawCanon = S.canonChestKey(raw)
        for _, entry in ipairs(CHEST_CATALOG) do
            if canon == entry.canon or rawCanon == entry.canon then
                return entry.canon
            end
        end
    end
    return S.canonChestKey(S.getChestTypeKey(chest))
end

function S.canonChestKey(text)
    local token = string.lower(tostring(text or "")):gsub("[^%a%d]", "")
    return CHEST_ALIAS[token] or token
end

function S.chestLabelsFromSaved(list)
    local out = {}
    local seen = {}
    for _, opt in ipairs(list or {}) do
        local canon = S.canonChestKey(opt)
        for _, entry in ipairs(CHEST_CATALOG) do
            if entry.canon == canon and not seen[entry.label] then
                seen[entry.label] = true
                table.insert(out, entry.label)
                break
            end
        end
    end
    return out
end

function S.chestSelectionList(value)
    local list = dropdownList(value)
    if type(list) ~= "table" then
        return {}
    end
    local out = {}
    for _, opt in ipairs(list) do
        if type(opt) == "string" and opt ~= "" then
            out[#out + 1] = opt
        end
    end
    return out
end

function S.chestWhitelistWants(canon)
    for _, opt in ipairs(S.chestSelectionList(Autofarm.chestTypes)) do
        if S.canonChestKey(opt) == canon then
            return true
        end
    end
    return false
end

function S.chestTextHasCore(chest)
    for _, raw in ipairs(S.chestTypeStrings(chest)) do
        local token = string.lower(raw)
        if token:find("core", 1, true) and not token:find("score", 1, true) then
            return true
        end
    end
    return false
end

function S.chestMatchesAutofarmWhitelist(chest)
    local selected = S.chestSelectionList(Autofarm.chestTypes)
    if #selected == 0 then
        return false
    end
    local key = S.chestCanon(chest)
    for _, opt in ipairs(selected) do
        if S.canonChestKey(opt) == key then
            return true
        end
    end
    if S.chestWhitelistWants("core") and S.chestTextHasCore(chest) then
        return true
    end
    return false
end

-- Exact same detection as Auto Scrap chest hunt (findScrapChestForHunt) — that one
-- works. Only difference: whitelist filter instead of tier priority. No range cap;
-- cruise altitude makes 3D dist huge, a cap here made chests invisible to autofarm.
function S.shouldSkipLockedChest(inst)
    return Autofarm.autoSkipLockedChest == true and S.isChestPadlocked(inst)
end

function S.findChestForAutofarm()
    if Autofarm.openChests ~= true then
        return nil
    end
    if #S.chestSelectionList(Autofarm.chestTypes) == 0 then
        return nil
    end
    if tick() < (Autofarm.suppressChestOreStopUntil or 0) then
        return nil
    end

    local best, bestDist = nil, math.huge
    local reach = 15000
    local seenNames = {}
    local function consider(model)
        if not model or not model.Parent or S.shouldSkipLockedChest(model) then
            return
        end
        local label = S.getChestTypeKey(model)
        if label ~= "" and not seenNames[label] and #seenNames < 8 then
            seenNames[#seenNames + 1] = label
            seenNames[label] = true
        end
        if not S.chestMatchesAutofarmWhitelist(model) then
            return
        end
        local dist = S.getFlatDistanceToPlayer(model)
        if dist <= reach and dist < bestDist then
                    bestDist = dist
            best = model
                end
            end
    S.forEachWorldChestNode(consider)
    if not best and S.chestWhitelistWants("core") then
        local chunks = Workspace:FindFirstChild("Chunks") or Workspace
        local now = os.clock()
        local cache = Autofarm._coreNameScan
        if not cache or now - (cache.at or 0) > 2 then
            local list = {}
            for _, desc in ipairs(chunks:GetDescendants()) do
                if #list >= 30 then
                    break
                end
                if desc:IsA("Model") then
                    local n = string.lower(desc.Name)
                    if n:find("core", 1, true) and n:find("chest", 1, true) and not S.isChestInDungeonWave(desc) then
                        list[#list + 1] = desc
                    end
                end
            end
            cache = { at = now, list = list }
            Autofarm._coreNameScan = cache
        end
        for _, model in ipairs(cache.list) do
            consider(model)
        end
    end
    if not best and S.chestWhitelistWants("core") and os.clock() - (Autofarm._coreMissNote or 0) > 8 then
        Autofarm._coreMissNote = os.clock()
        local saw = #seenNames > 0 and table.concat(seenNames, ", ") or "none"
        S.notify("Core", "No Core chest found. Nearby: " .. saw, 5)
    end
    return best
end

function S.instantChestOpen(chest)
    if not chest or not chest.Parent then
        return false
    end
    local prompts = S.collectProximityPrompts(chest)
    if #prompts == 0 then
        return false
    end

    -- Never write HoldDuration. Changing it breaks the chest prompt.
    local knit = S.getKnit()
    if knit then
        pcall(function()
            local drag = knit.GetController("DragController")
            if drag then
                drag.Target = chest
                if drag.TargetChanged then
                    drag.TargetChanged:Fire(chest)
                end
            end
        end)
    end

    local mesh = chest:FindFirstChild("Chest", true)
    if Services.InteractionService then
        local function interact(inst)
            if not inst then
                return
            end
            pcall(function()
                Services.InteractionService:Interact(inst)
            end)
        end
        interact(chest)
        interact(mesh)
        for _, desc in ipairs(chest:GetDescendants()) do
            if CollectionService:HasTag(desc, "Interactive") then
                interact(desc)
            end
        end
    end

    local player = Players.LocalPlayer
    local root = S.getRoot()
    local fired = false
    for _, prompt in ipairs(prompts) do
        local promptPos = S.getPromptWorldPosition(prompt)
        local maxDist = tonumber(prompt.MaxActivationDistance) or 10
        if root and promptPos and (root.Position - promptPos).Magnitude > maxDist then
            continue
        end
        fired = true
        pcall(function()
            if typeof(firesignal) == "function" then
                firesignal(prompt.Triggered, player)
                firesignal(prompt.PromptButtonHoldEnded, player)
            end
        end)
        pcall(function()
            if typeof(fireproximityprompt) == "function" then
                fireproximityprompt(prompt, 0)
            end
        end)
    end
    if not fired then
        return false
    end

    task.wait(0.08)
    if S.playerGuiSaysChestLocked() then
        S.markChestLocked(chest)
        return false
    end
    return true
end

-- Stop under the chest, aim the camera, and hold the prompt for its own duration.
function S.autofarmVisitChest(chest)
    if not chest or not Autofarm.enabled or Autofarm.openChests ~= true then
        return false
    end

    chest = S.resolveDungeonChestModel(chest) or chest
    if S.shouldSkipLockedChest(chest) or not S.chestMatchesAutofarmWhitelist(chest) then
        return false
    end
    if not S.chestHasProximityPrompt(chest) then
        return false
    end

    local savedDist = Autofarm.distance or S.syncAutofarmDistanceFromRoot()
    local prompts = S.collectProximityPrompts(chest)
    local chestPos = S.getInstancePosition(chest) or S.getItemPosition(chest)
    local prompt = prompts[1]
    local promptPos = (prompt and S.getPromptWorldPosition(prompt)) or chestPos
    if not chestPos or not promptPos then
        return false
    end

    -- Under the chest, but still inside the prompt's own range.
    local maxDist = prompt and tonumber(prompt.MaxActivationDistance) or 10
    if not maxDist or maxDist <= 0 then
        maxDist = 10
    end
    local depth = tonumber(Autofarm.chestUnderDepth) or 11
    local drop = math.min(depth, maxDist * 0.75)
    if drop < 1.5 then
        drop = math.min(1.5, maxDist * 0.5)
    end
    local standPos = Vector3.new(promptPos.X, promptPos.Y - drop, promptPos.Z)

    S.cancelAutofarmTween()
    S.ensureAutofarmAntiFall(true)
    S.lockAutofarmHover(true)
    S.setAutofarmPlatformStand(true)

    Autofarm._mineHoldPos = standPos
    Autofarm._mineLookAt = promptPos
    Autofarm._gatePinY = standPos.Y
    local root = S.getRoot()
    if root then
        root.Anchored = false
        root.CFrame = CFrame.lookAt(standPos, Vector3.new(promptPos.X, standPos.Y, promptPos.Z))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        S.setAutofarmPlatformStand(true)
    end
    task.wait(0.12)
    root = S.getRoot()
    if root then
        local away = (root.Position - promptPos).Magnitude
        if away > maxDist * 0.9 then
            root.CFrame = CFrame.lookAt(standPos, Vector3.new(promptPos.X, standPos.Y, promptPos.Z))
        root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end

    if Services.ToolService then
        pcall(function()
            Services.ToolService:UnequipTool()
        end)
    end

    local function chestPromptLive()
        return chest.Parent and #S.collectProximityPrompts(chest) > 0
    end

    local function forceChestServerOpen()
        local prompts = S.collectProximityPrompts(chest)
        local prompt = prompts[1]
        local target = (prompt and prompt.Parent) or chest
        local knit = S.getKnit()
        if knit then
            pcall(function()
                local drag = knit.GetController("DragController")
                if drag then
                    drag.Target = target
                    if drag.TargetChanged then
                        drag.TargetChanged:Fire(target)
                    end
                end
            end)
        end
        local svc = Services.InteractionService
        if not svc and knit and type(knit.GetService) == "function" then
            pcall(function()
                svc = knit.GetService("InteractionService")
                Services.InteractionService = svc
            end)
        end
        if svc and type(svc.Interact) == "function" then
            pcall(function()
                svc:Interact(target)
            end)
            if target ~= chest then
                pcall(function()
                    svc:Interact(chest)
                end)
            end
        end
    end

    -- Stay under the chest until the prompt actually dies. A local lid tween
    -- is not an open: the server only pays cores on InteractionService:Interact.
    local opened = false
    for _ = 1, 3 do
        if not Autofarm.enabled or not chest.Parent then
            break
        end
        root = S.getRoot()
        if root then
            root.CFrame = CFrame.lookAt(standPos, Vector3.new(promptPos.X, standPos.Y, promptPos.Z))
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            S.setAutofarmPlatformStand(true)
        end
        task.wait(0.2)
        local coresBefore = tonumber(LocalPlayer:GetAttribute("Cores")) or 0
        forceChestServerOpen()
        S.holdChestInteract(chest)
        forceChestServerOpen()
        task.wait(0.4)
        local coresAfter = tonumber(LocalPlayer:GetAttribute("Cores")) or 0
        if S.playerGuiSaysChestLocked() then
            S.markChestLocked(chest)
            opened = false
            break
        end
        if not chestPromptLive() or coresAfter > coresBefore then
            opened = true
                    break
                end
    end

    local ok = opened

    S.clearMineHoldPin()
    Autofarm._gatePinY = nil
    Autofarm.distance = savedDist
    if Autofarm.enabled then
        S.setAutofarmPose(savedDist)
        S.setAutofarmPlatformStand(true)
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
        if not S.coreChestsOnly() then
        S.ensureItemBag()
        end
    end

    -- If the chest reported as locked, keep markChestLocked's longer skip
    -- window so findChestForAutofarm moves on to the next chest instead of retrying it.
    Autofarm.lockedChestSkip = Autofarm.lockedChestSkip or {}
    if ok then
        Autofarm.lockedChestSkip[chest] = tick() + 25
    elseif not S.isChestMarkedLocked(chest) then
        Autofarm.lockedChestSkip[chest] = tick() + 4
    end
    return ok == true
end

-- Instant collect after ore break — verify bag fill / quiet with fast runLootCycle.
function S.vacuumOreDropsVerified(nearPos)
    if S.isBagFull() then
        return 0
    end

    local root = S.getRoot()
    nearPos = nearPos or (root and root.Position)
    if not nearPos then
        return 0
    end

    local pinY = Autofarm._gatePinY
    if typeof(pinY) ~= "number" then
        pinY = nearPos.Y - (tonumber(Autofarm.oreUnderDepth) or 11)
    end
    local hold = Vector3.new(nearPos.X, pinY, nearPos.Z)
    Autofarm._gatePinY = pinY

    root = S.getRoot()
    if root then
        S.setAutofarmPlatformStand(true)
        root.Anchored = false
        root.CFrame = CFrame.new(hold)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    S.ensureAutofarmAntiFall(true)
    S.lockAutofarmHover(true)
    S.ensureItemBag()

    local range = math.max(S.getAutofarmLootRange(), 800)
    local bag = S.getEquippedTool()
    if bag and S.isItemBagTool(bag) then
        S.boostToolRange(bag, range)
    end

    -- Auto Ores: yank the broken ore. Scrap gold keeps its own yank.
    if S.isScrapGoldPhase() then
        return S.yankScrapGoldLootNearby(math.max(range, 900))
    end

    return S.yankOreDropsNearby(math.max(range, 800))
end

-- Selected ores near you / about to pass on Track. Cruise-stop range only (not full loot range).
-- Cheap cached wrapper: the cruise stop-check hits this every frame, but the full
-- Workspace ore walk is expensive — only rescan every ~0.12s to avoid FPS softlock.
function S.findOreForAutofarmCached()
    local now = tick()
    local cache = Autofarm._oreScanCache
    if cache and (now - (cache.at or 0)) < 0.12 then
        local ore = cache.ore
        if not ore then
            return nil
        end
        if ore.Parent and not S.isOreSkipped(ore) and S.isOreStillMineable(ore) then
            return ore, cache.pos
        end
        -- Cached ore gone — fall through to a fresh scan.
    end
    local ore, pos = S.findOreForAutofarm()
    Autofarm._oreScanCache = { at = now, ore = ore, pos = pos }
    return ore, pos
end

function S.findOreForAutofarm()
    local types = S.getAutofarmActiveOreTypes()
    local oresOn = Autofarm.oreUnderEnabled == true or S.isScrapGoldPhase()
    if not oresOn then
        return nil
    end
    if Autofarm._scrapProcessing or Autofarm._scrapFlushing then
        return nil
    end
    if tick() < (Autofarm._scrapCooldownUntil or 0) and S.isScrapGoldPhase() then
        return nil
    end
    if type(types) ~= "table" or #types == 0 then
        return nil
    end
    if Autofarm.miningBusy then
        return nil
    end
    if tick() < (Autofarm.suppressChestOreStopUntil or 0) then
        return nil
    end

    local root = S.getRoot()
    if not root then
        return nil
    end

    local range = S.getAutofarmChestOreRange()
    -- Inside / hunting mines: use ore-hunt range so deep Gold nodes aren't ignored.
    if Autofarm._oreHuntMode or S.isScrapGoldPhase() then
        range = math.max(range, S.getAutofarmOreHuntRange())
    end
    local origin = Autofarm.origin or root.Position
    local dir = S.getAutofarmAxisVector()
    local originFlat = Vector3.new(origin.X, 0, origin.Z)
    local playerFlat = Vector3.new(root.Position.X, 0, root.Position.Z)
    local alongPlayer = (playerFlat - originFlat):Dot(dir)
    local best, bestScore, bestPos = nil, math.huge, nil

    S.forEachWorldOreNode(function(ore)
        if not ore or not ore.Parent then
            return
        end
        if S.isOreSkipped(ore) then
            return
        end
        if not S.oreMatchesAutofarmSelection(ore) then
            return
        end
        if not S.isOreStillMineable(ore) then
            return
        end

        local pos = S.getOreWorldPosition(ore)
        if not pos or not S.isSaneOrePos(pos) then
            return
        end

        local posFlat = Vector3.new(pos.X, 0, pos.Z)
        local flat = (posFlat - playerFlat).Magnitude
        -- Also consider 3D distance — mines put ores far below cruise Y.
        local dist3 = (pos - root.Position).Magnitude
        local rel = posFlat - originFlat
        local along = rel:Dot(dir)
        local side = (rel - dir * along).Magnitude
        local ahead = along - alongPlayer

        local near = flat <= range or dist3 <= range
        local approaching = side <= math.min(220, range) and ahead >= -80 and ahead <= math.min(range, 500)
        if not near and not approaching then
            return
        end

        local score = math.min(flat, dist3)
        if ahead < -30 then
            score = score + 80
        end
        if score < bestScore then
            bestScore = score
            best = ore
            bestPos = pos
        end
    end)

    return best, bestPos
end

-- Mine ore from 11 studs UNDER the rock (mobs can't hit). Sword mid-farm → force pickaxe.
function S.autofarmVisitOre(ore, knownPos)
    if not ore or not Autofarm.enabled then
        return false
    end
    if S.autofarmCycleShouldAbort() then
        return false
    end
    if not (Autofarm.oreUnderEnabled == true or S.isScrapGoldPhase()) then
        return false
    end
    if not S.oreMatchesAutofarmSelection(ore) or not S.isOreStillMineable(ore) then
        return false
    end

    local savedDist = Autofarm.distance or S.syncAutofarmDistanceFromRoot()
    local broken = false

    local ok, err = pcall(function()
        -- Kill Aura / manual sword: unequip + pickaxe BEFORE any TP.
        if not S.ensurePickaxe(1.0) then
            S.markOreSkip(ore, 15)
            S.notify("Autofarm", "Need pickaxe (sword equipped?) — skip ore", 3)
            return
        end

        local orePos = knownPos or S.getOreWorldPosition(ore)
        local standPos = S.getOreUnderPosition(ore, Autofarm.oreUnderDepth or 11)
        if not standPos and orePos then
            standPos = S.getUnderStandPosition(orePos, Autofarm.oreUnderDepth or 11)
        end
        if not standPos or not orePos or not S.isSaneOrePos(standPos) or not S.isSaneOrePos(orePos) then
            S.markOreSkip(ore, 8)
            return
        end

        Autofarm.miningBusy = true
        Autofarm._oreHuntMode = true
        S.touchMiningBusyHeartbeat()
        S.cancelAutofarmTween()
        S.setAutofarmPlatformStand(true)

        Autofarm._gatePinY = standPos.Y
        Autofarm._mineHoldPos = standPos
        Autofarm._mineLookAt = orePos

        local root = S.getRoot()
        if root then
            root.Anchored = false
            local cf = S.safeLookAt(standPos, orePos)
            if cf then
                root.CFrame = cf
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
        task.wait(0.04)

        if not S.ensurePickaxe(0.5) then
            S.markOreSkip(ore, 15)
            return
        end

        S.farmLog("ore dig", S.resolveOreTypeKey(ore) or ore.Name)
        S.notify("Autofarm", "Ore → " .. tostring(S.resolveOreTypeKey(ore) or ore.Name), 2)

        local deadline = os.clock() + 55
        local started = S.isOreStillMineable(ore)
        if not started then
            S.markOreSkip(ore, 8)
            return
        end
        local lastHealth = nil
        local noProgressSince = os.clock()
        local swung = false
        local standMisses = 0
        local healthObj = ore:FindFirstChild("Health")
        if healthObj and (healthObj:IsA("NumberValue") or healthObj:IsA("IntValue")) then
            lastHealth = healthObj.Value
        end

        while Autofarm.enabled and S.isOreStillMineable(ore) and os.clock() < deadline do
            if S.autofarmCycleShouldAbort() then
                break
            end

            local livePos = S.getOreWorldPosition(ore) or orePos
            local liveStand = S.getOreUnderPosition(ore, Autofarm.oreUnderDepth or 11)
                or (livePos and S.getUnderStandPosition(livePos, Autofarm.oreUnderDepth or 11))
            if not liveStand or not S.isSaneOrePos(liveStand) then
                standMisses += 1
                S.touchMiningBusyHeartbeat()
                if standMisses >= 15 then
                break
            end
                task.wait(0.08)
                continue
            end
            standMisses = 0
            standPos = liveStand
            orePos = livePos
            Autofarm._gatePinY = standPos.Y
            Autofarm._mineHoldPos = standPos
            Autofarm._mineLookAt = orePos

            root = S.getRoot()
            if root then
                local cf = S.safeLookAt(standPos, orePos)
                if cf then
                    root.CFrame = cf
                end
                root.AssemblyLinearVelocity = Vector3.zero
                S.setAutofarmPlatformStand(true)
            end

            local tool = S.getEquippedTool()
            if not (tool and S.isPickaxeTool(tool)) then
                if not S.ensurePickaxe(0.4) then
                    break
                end
                tool = S.getEquippedTool()
            end
            if tool and S.isPickaxeTool(tool) and Services.ToolService then
                S.boostToolRange(tool, 30000)
                pcall(function()
                    Services.ToolService.Update:Fire({ "Swing", { ore } })
                end)
                swung = true
            end

            S.touchMiningBusyHeartbeat()
            healthObj = ore:FindFirstChild("Health")
            if healthObj and (healthObj:IsA("NumberValue") or healthObj:IsA("IntValue")) and healthObj.Value > 0 then
                if lastHealth == nil or healthObj.Value < lastHealth then
                    lastHealth = healthObj.Value
                    noProgressSince = os.clock()
                elseif os.clock() - noProgressSince >= 22 then
                    S.markOreSkip(ore, 12)
                    break
                end
            end
            task.wait(0.07)
        end

        broken = started and not S.isOreStillMineable(ore)
        if broken then
            local breakPos = S.getOreWorldPosition(ore) or orePos
            task.wait(0.08)
            pcall(function()
                S.vacuumOreDropsVerified(breakPos)
            end)
            if S.isScrapGoldPhase() then
                S.yankScrapGoldLootNearby(900)
            end
            -- Worm ore break → DeathWorm often aggroes; kill before it face-sucks.
            if S.oreHasDeathWorm(ore) or Combat.autoKillDeathWorms then
                pcall(S.tryAutoKillDeathWorms)
            end
            S.flushAutofarmDrillDropIfNeeded()
        else
            S.markOreSkip(ore, swung and 20 or 28)
        end
    end)

    if not ok then
        warn("[TERRA HUB] autofarmVisitOre error:", err)
        S.markOreSkip(ore, 15)
    end

    Autofarm._oreScanCache = nil
    Autofarm._gatePinY = nil
    S.clearMineHoldPin()
    Autofarm.miningBusy = false
    Autofarm._oreHuntMode = false
    Autofarm._miningBusySince = nil
    Autofarm.distance = savedDist
    if Autofarm.enabled then
        S.setAutofarmPose(savedDist)
        S.setAutofarmPlatformStand(true)
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
    end

    return broken
end

function S.isChestEspTarget(inst)
    if not inst or not inst.Parent then
        return false
    end
    -- Rule: ChestNode chests are ESP/openable unless under Wave.
    if S.isChestInDungeonWave(inst) or S.isChestStepJunk(inst) then
        return false
    end

    local lower = string.lower(inst.Name or "")
    if lower == "chestnode"
        or lower == "chestnodes"
        or lower == "cheststep"
        or lower:find("cheststep", 1, true)
        or lower:find("supply", 1, true)
    then
        return false
    end
    if CollectionService:HasTag(inst, "SupplyCrate") then
        return false
    end

    local underSocket = false
    local walk = inst.Parent
    for _ = 1, 6 do
        if not walk then
            break
        end
        if walk.Name == "ChestNode" or walk.Name == "ChestNodes" then
            underSocket = true
            break
        end
        walk = walk.Parent
    end
    if not underSocket then
        return false
    end

    if lower:find("chest", 1, true) or inst:FindFirstChild("Chest") or CollectionService:HasTag(inst, "Interactive") then
        return true
    end
    if inst:FindFirstChildWhichIsA("ProximityPrompt", true) then
        return true
    end
    local canon = S.canonChestKey(S.normalizeChestTypeToken(inst.Name))
    for _, entry in ipairs(CHEST_CATALOG) do
        if entry.canon == canon then
            return true
        end
    end
    return false
end

-- Walk all ChestNodes in Workspace, skip Wave folders entirely.
function S.forEachWorldChestNode(callback)
    local seen = {}

    local function emit(chest)
        if not chest or not chest.Parent or seen[chest] then
            return
        end
        local model = S.resolveDungeonChestModel(chest) or chest
        if seen[model] or not S.isChestEspTarget(model) then
            return
        end
        seen[model] = true
        callback(model)
    end

    local function scanChestNodesFolder(folder)
        if not folder or S.isChestInDungeonWave(folder) then
            return
        end
        for _, node in ipairs(folder:GetChildren()) do
            if node.Name == "ChestNode" then
                for _, child in ipairs(node:GetChildren()) do
                    emit(child)
                end
            else
                emit(node)
            end
        end
    end

    local function visit(container, depth)
        if not container or depth > 16 then
            return
        end
        for _, child in ipairs(container:GetChildren()) do
            local name = tostring(child.Name or "")
            -- Skip boss Wave loot folders (workspace.*.Wave).
            if name == "Wave" or name:match("^Wave%d+$") then
                -- ignore
            elseif name == "ChestNodes" then
                scanChestNodesFolder(child)
            elseif name == "ChestNode" then
                if not S.isChestInDungeonWave(child) then
                    for _, nested in ipairs(child:GetDescendants()) do
                        if nested:IsA("Model") or nested:IsA("BasePart") then
                        emit(nested)
                        end
                    end
                end
            elseif depth < 16 and (child:IsA("Folder") or child:IsA("Model")) then
                visit(child, depth + 1)
            end
        end
    end

    pcall(function()
        visit(Workspace, 0)
    end)

    pcall(function()
        for _, tagged in ipairs(CollectionService:GetTagged("Interactive")) do
            local model = S.resolveDungeonChestModel(tagged) or tagged
            if S.isChestEspTarget(model) then
                emit(model)
            end
        end
    end)
end

function S.collectEspChests()
    local chests = {}
    local maxRange = Esp.maxRange or 2000

    S.forEachWorldChestNode(function(model)
        local adornee = S.getChestEspAdornee(model)
        local pos = adornee and adornee.Position
            or S.getInstancePosition(model)
            or S.getItemPosition(model)
        if not pos then
            return
        end
        local dist = S.getDistanceToPlayer(pos)
        if not dist or dist > maxRange then
            return
        end

        local locked = S.isChestPadlocked(model)
        table.insert(chests, {
            inst = model,
            name = S.getChestEspLabel(model),
            pos = pos,
            color = locked and Color3.fromRGB(255, 80, 180) or ESP_COLORS.chest,
            kind = "chest",
            dist = dist,
        })
    end)

    table.sort(chests, function(a, b)
        return (a.dist or 0) < (b.dist or 0)
    end)

    for i, entry in ipairs(chests) do
        entry.useHighlight = i <= 28
    end

    return chests
end

function S.collectEspLocations()
    local locations = {}

    S.scanWorldModels(function(inst)
        local kind, label, color
        if Esp.minesEnabled and S.isMineRoot(inst) then
            kind = "mine"
            label = "Mine: " .. inst.Name
            color = ESP_COLORS.mine
        elseif Esp.dungeonsEnabled and S.isHubDungeonRoot(inst) then
            kind = "dungeon"
            label = "Dungeon: " .. inst.Name
            color = ESP_COLORS.dungeon
        elseif Esp.villagesEnabled and S.isVillageModel(inst) then
            kind = "village"
            label = "Village: " .. inst.Name
            color = ESP_COLORS.village
        end

        if kind then
            local dist = S.getFlatDistanceToPlayer(inst)
            if dist <= Esp.maxRange then
                local pos = S.getInstancePosition(inst) or S.getEspWorldPosition(inst)
                if pos then
                    table.insert(locations, {
                        inst = inst,
                        name = label,
                        pos = pos,
                        color = color,
                        kind = kind,
                    })
                end
            end
        end
    end)

    return locations
end

function S.espIsActive()
    return Esp.lootEnabled
        or Esp.mobsEnabled
        or Esp.oresEnabled
        or Esp.chestsEnabled
        or Esp.dungeonsEnabled
        or Esp.minesEnabled
        or Esp.villagesEnabled
end

function S.disconnectEspTracerLoop()
    if State.connections.espTracers then
        State.connections.espTracers:Disconnect()
        State.connections.espTracers = nil
    end
end

function S.lerpVector2(a, b, alpha)
    return a + (b - a) * alpha
end

function S.clearEspVisuals()
    State.espRunning = false

    if State.espHighlightFolder then
        State.espHighlightFolder:Destroy()
        State.espHighlightFolder = nil
    end

    State.espHighlights = {}
    State.espLootBoxes = State.espLootBoxes or {}

    for _, box in pairs(State.espLootBoxes) do
        pcall(function()
            box:Destroy()
        end)
    end
    State.espLootBoxes = {}
    State.espLabels = State.espLabels or {}

    for _, billboard in pairs(State.espLabels) do
        pcall(function()
            billboard:Destroy()
        end)
    end
    State.espLabels = {}

    State.espTracers = State.espTracers or {}
    for _, line in pairs(State.espTracers) do
        pcall(function()
            line.Visible = false
        end)
    end
    State.espTracerTargets = {}
    S.disconnectEspTracerLoop()
end

function S.getEspTracer(key)
    if not EspDrawingSupported or not Esp.tracers then
        return nil
    end

    State.espTracers = State.espTracers or {}
    if not State.espTracers[key] then
        local line = Drawing.new("Line")
        line.Thickness = 1.1
        line.Transparency = 0.5
        line.Visible = false
        State.espTracers[key] = line
    end

    return State.espTracers[key]
end

function S.setEspTracerTarget(key, worldPos, color)
    if not EspDrawingSupported or not Esp.tracers then
        return
    end

    State.espTracerTargets = State.espTracerTargets or {}

    local root = S.getRoot()
    if not root or not worldPos then
        State.espTracerTargets[key] = { visible = false }
        return
    end

    local fromScreen, fromVisible = S.worldToScreen(root.Position + Vector3.new(0, 1.5, 0))
    local toScreen, toVisible = S.worldToScreen(worldPos + Vector3.new(0, 1.5, 0))
    if not fromScreen or not fromVisible or not toScreen or not toVisible then
        State.espTracerTargets[key] = { visible = false }
        return
    end

    State.espTracerTargets[key] = {
        visible = true,
        from = fromScreen,
        to = toScreen,
        color = color,
    }
end

function S.startEspTracerLoop()
    S.disconnectEspTracerLoop()

    if not EspDrawingSupported or not Esp.tracers or not S.espIsActive() then
        return
    end

    State.espTracerTargets = State.espTracerTargets or {}

    State.connections.espTracers = RunService.RenderStepped:Connect(function(dt)
        if not Esp.tracers or not S.espIsActive() then
            return
        end

        local alpha = math.clamp(dt * 14, 0.12, 0.4)
        local targets = State.espTracerTargets or {}

        for key, target in pairs(targets) do
            local line = S.getEspTracer(key)
            if not line then
                continue
            end

            if not target.visible then
                line.Visible = false
                continue
            end

            line.Color = target.color
            line.Thickness = 1.1
            line.Transparency = 0.5
            line.From = line.Visible and S.lerpVector2(line.From, target.from, alpha) or target.from
            line.To = line.Visible and S.lerpVector2(line.To, target.to, alpha) or target.to
            line.Visible = true
        end

        for key, line in pairs(State.espTracers or {}) do
            if not targets[key] or not targets[key].visible then
                line.Visible = false
            end
        end
    end)
end

function S.buildEspLabelText(name, dist)
    if Esp.showNames and Esp.showDistance then
        return string.format("%s [%dm]", name, math.floor(dist))
    end
    if Esp.showNames then
        return name
    end
    if Esp.showDistance then
        return string.format("%dm", math.floor(dist))
    end
    return name
end

function S.ensureEspLabel(key, adornee, text, color, opts)
    if not adornee or not adornee.Parent then
        return nil
    end
    opts = opts or {}

    State.espLabels = State.espLabels or {}
    local billboard = State.espLabels[key]
    if not billboard or not billboard.Parent then
        billboard = Instance.new("BillboardGui")
        billboard.Name = "JPAX_ESP_" .. key
        billboard.AlwaysOnTop = true
        billboard.Size = opts.compact and UDim2.fromOffset(140, 28) or UDim2.fromOffset(220, 44)
        billboard.MaxDistance = Esp.maxRange
        billboard.StudsOffset = opts.compact and Vector3.new(0, 1.6, 0) or Vector3.new(0, 2.8, 0)

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = opts.compact and Enum.Font.GothamMedium or Enum.Font.GothamBold
        label.TextSize = opts.compact and 13 or 14
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextStrokeTransparency = 0.35
        label.Parent = billboard

        billboard.Parent = LocalPlayer:WaitForChild("PlayerGui")
        State.espLabels[key] = billboard
    end

    billboard.Adornee = adornee
    if opts.forceShow then
        billboard.Enabled = true
    else
        billboard.Enabled = Esp.showNames or Esp.showDistance
    end
    billboard.MaxDistance = Esp.maxRange
    if opts.compact then
        billboard.Size = UDim2.fromOffset(140, 28)
        billboard.StudsOffset = Vector3.new(0, 1.6, 0)
    end

    local label = billboard:FindFirstChild("Label")
    if label then
        label.Text = text
        label.TextColor3 = color
        if opts.compact then
            label.Font = Enum.Font.GothamMedium
            label.TextSize = 13
        end
    end

    return billboard
end

-- Soft gem Highlight (no giant Rock box).
function S.ensureEspOreHighlight(key, adornee, color)
    if not adornee or not adornee.Parent then
        return nil
    end

    if not State.espHighlightFolder or not State.espHighlightFolder.Parent then
        State.espHighlightFolder = Instance.new("Folder")
        State.espHighlightFolder.Name = "JPAXHubESP"
        State.espHighlightFolder.Parent = Workspace
    end

    State.espHighlights = State.espHighlights or {}
    local highlight = State.espHighlights[key]
    if not highlight or not highlight.Parent then
        highlight = Instance.new("Highlight")
        highlight.Name = "ESP_Ore_" .. key
        highlight.Parent = State.espHighlightFolder
        State.espHighlights[key] = highlight
    end

    highlight.Adornee = adornee
    highlight.FillColor = color
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.72
    highlight.OutlineTransparency = 0.25
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    return highlight
end

-- Unique ESP key: tostring(Instance) is often just the Name (many Ore_NodeDirt → one key).
function S.getEspInstanceKey(kind, inst)
    if not inst then
        return tostring(kind) .. "_nil"
    end
    State.espInstIds = State.espInstIds or setmetatable({}, { __mode = "k" })
    local id = State.espInstIds[inst]
    if not id then
        State.espIdCounter = (State.espIdCounter or 0) + 1
        id = State.espIdCounter
        State.espInstIds[inst] = id
    end
    return tostring(kind) .. "_" .. tostring(id)
end

function S.ensureEspHighlight(key, adornee, color, keepPartAdornee)
    if not adornee or not adornee.Parent then
        return nil
    end

    if not State.espHighlightFolder or not State.espHighlightFolder.Parent then
        State.espHighlightFolder = Instance.new("Folder")
        State.espHighlightFolder.Name = "JPAXHubESP"
        State.espHighlightFolder.Parent = Workspace
    end

    State.espHighlights = State.espHighlights or {}
    local highlight = State.espHighlights[key]
    if not highlight or not highlight.Parent then
        highlight = Instance.new("Highlight")
        highlight.Name = "ESP_" .. key
        highlight.Parent = State.espHighlightFolder
        State.espHighlights[key] = highlight
    end

    -- Ores: NEVER FindFirstAncestorOfClass("Model") — that becomes the whole Mineshaft.
    if keepPartAdornee or adornee:IsA("BasePart") then
        highlight.Adornee = adornee
    else
        highlight.Adornee = adornee:IsA("Model") and adornee or adornee
    end
    highlight.FillColor = color
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.62
    highlight.OutlineTransparency = 0.15
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    return highlight
end

function S.ensureEspLootBox(key, adornee, color)
    if not adornee or not adornee.Parent then
        return nil
    end

    State.espLootBoxes = State.espLootBoxes or {}
    local box = State.espLootBoxes[key]
    if not box then
        box = Instance.new("BoxHandleAdornment")
        box.Name = "JPAX_LootBox"
        box.Transparency = 0.55
        box.AlwaysOnTop = true
        box.ZIndex = 5
        State.espLootBoxes[key] = box
    end

    box.Adornee = adornee
    box.Color3 = color
    if adornee:IsA("BasePart") then
        box.Size = adornee.Size
    elseif adornee:IsA("Model") then
        box.Size = adornee:GetExtentsSize()
    end
    box.Parent = adornee

    return box
end

function S.refreshEspSystem()
    S.clearEspVisuals()

    if not S.espIsActive() then
        return
    end

    local folder = Instance.new("Folder")
    folder.Name = "JPAXHubESP"
    folder.Parent = Workspace
    State.espHighlightFolder = folder
    State.espHighlights = {}
    State.espLootBoxes = {}
    State.espLabels = {}
    State.espTracerTargets = {}
    State.espRunning = true

    if Esp.tracers then
        S.startEspTracerLoop()
    end

    task.spawn(function()
        while State.espRunning and S.espIsActive() do
            local wanted = {}

            if Esp.lootEnabled then
                for _, entry in ipairs(S.collectEspLootTargets()) do
                    wanted[S.getEspInstanceKey("loot", entry.inst)] = entry
                end
            end
            if Esp.mobsEnabled then
                for _, entry in ipairs(S.collectEspMobs()) do
                    wanted[S.getEspInstanceKey("mob", entry.inst)] = entry
                end
            end
            if Esp.oresEnabled then
                for _, entry in ipairs(S.collectEspOres()) do
                    wanted[S.getEspInstanceKey("ore", entry.inst)] = entry
                end
            end
            if Esp.chestsEnabled then
                for _, entry in ipairs(S.collectEspChests()) do
                    wanted[S.getEspInstanceKey("chest", entry.inst)] = entry
                end
            end
            if Esp.dungeonsEnabled or Esp.minesEnabled or Esp.villagesEnabled then
                for _, entry in ipairs(S.collectEspLocations()) do
                    wanted[S.getEspInstanceKey(entry.kind, entry.inst)] = entry
                end
            end

            for key, highlight in pairs(State.espHighlights) do
                if not wanted[key] then
                    pcall(function()
                        highlight:Destroy()
                    end)
                    State.espHighlights[key] = nil
                end
            end

            for key, box in pairs(State.espLootBoxes) do
                if not wanted[key] then
                    pcall(function()
                        box:Destroy()
                    end)
                    State.espLootBoxes[key] = nil
                end
            end

            for key, billboard in pairs(State.espLabels) do
                if not wanted[key] then
                    pcall(function()
                        billboard:Destroy()
                    end)
                    State.espLabels[key] = nil
                end
            end

            for key, entry in pairs(wanted) do
                if entry.inst.Parent then
                    local adornee
                    local pos
                    if entry.kind == "ore" then
                        adornee = S.getOreEspAdornee(entry.inst)
                        pos = entry.pos or S.getOreWorldPosition(entry.inst)
                    elseif entry.kind == "chest" then
                        adornee = S.getChestEspAdornee(entry.inst)
                        pos = entry.pos or (adornee and adornee.Position) or S.getInstancePosition(entry.inst)
                    else
                        adornee = S.getEspAdornee(entry.inst)
                        pos = S.getEspWorldPosition(entry.inst) or entry.pos
                    end
                    if adornee and pos then
                        local dist = S.getFlatDistanceFromPosition(pos)
                        if entry.kind == "ore" then
                            if entry.useHighlight ~= false then
                                S.ensureEspOreHighlight(key, adornee, entry.color)
                            elseif State.espHighlights and State.espHighlights[key] then
                                pcall(function()
                                    State.espHighlights[key]:Destroy()
                                end)
                                State.espHighlights[key] = nil
                            end
                            local labelText = Esp.showDistance
                                and S.buildEspLabelText(entry.name, dist)
                                or tostring(entry.name)
                            S.ensureEspLabel(key, adornee, labelText, entry.color, {
                                forceShow = true,
                                compact = true,
                            })
                        elseif entry.kind == "chest" then
                            if entry.useHighlight ~= false then
                                S.ensureEspOreHighlight(key, adornee, entry.color)
                            elseif State.espHighlights and State.espHighlights[key] then
                                pcall(function()
                                    State.espHighlights[key]:Destroy()
                                end)
                                State.espHighlights[key] = nil
                            end
                            local labelText = Esp.showDistance
                                and S.buildEspLabelText(entry.name, dist)
                                or tostring(entry.name)
                            S.ensureEspLabel(key, adornee, labelText, entry.color, {
                                forceShow = true,
                                compact = true,
                            })
                        elseif entry.kind == "loot" then
                            S.ensureEspLootBox(key, adornee, entry.color)
                            if Esp.showNames or Esp.showDistance then
                                S.ensureEspLabel(key, adornee, S.buildEspLabelText(entry.name, dist), entry.color)
                            end
                        else
                            S.ensureEspHighlight(key, adornee, entry.color)
                            if Esp.showNames or Esp.showDistance then
                                S.ensureEspLabel(key, adornee, S.buildEspLabelText(entry.name, dist), entry.color)
                            end
                        end

                        if Esp.tracers then
                            S.setEspTracerTarget(key, pos, entry.color)
                        end
                    end
                end
            end

            if Esp.tracers then
                State.espTracerTargets = State.espTracerTargets or {}
                for tracerKey in pairs(State.espTracerTargets) do
                    if not wanted[tracerKey] then
                        State.espTracerTargets[tracerKey] = { visible = false }
                    end
                end
            end

            task.wait(Esp.oresEnabled and 0.12 or 0.2)
        end

        S.clearEspVisuals()
    end)
end

function S.refreshEspIfNeeded()
    if not S.espIsActive() then
        S.clearEspVisuals()
        return
    end

    if Esp.tracers then
        S.startEspTracerLoop()
    else
        S.disconnectEspTracerLoop()
        State.espTracerTargets = {}
        for _, line in pairs(State.espTracers or {}) do
            pcall(function()
                line.Visible = false
            end)
        end
    end

    if not State.espRunning then
        S.refreshEspSystem()
    end
end

function S.findNearestVillage()
    local best, bestDist = nil, math.huge
    S.scanWorldModels(function(inst)
        if S.isVillageModel(inst) then
            local dist = S.getFlatDistanceToPlayer(inst)
            if dist < bestDist then
                best = inst
                bestDist = dist
            end
        end
    end)
    return best
end

-- Dex: workspace.Mineshaft.Gate_Mineshaft.EntranceHitbox — into-shaft LookVector.
function S.getMineEntranceHitbox(mine)
    if not mine then
        return nil, nil
    end

    -- Prefer exact Dex path first.
    local gate = mine:FindFirstChild("Gate_Mineshaft")
        or mine:FindFirstChild("Gate_Cave")
        or mine:FindFirstChild("Gate_Mineshaft", true)
        or mine:FindFirstChild("Gate_Cave", true)
        or mine:FindFirstChild("Gate", true)

    local hit = nil
    if gate then
        hit = gate:FindFirstChild("EntranceHitbox")
            or gate:FindFirstChild("EntranceHitbox", true)
    end
    if not hit then
        hit = mine:FindFirstChild("EntranceHitbox", true)
    end
    return hit, gate
end

function S.getInstanceFlatLook(inst)
    if not inst then
        return nil
    end
    local cf = nil
    if inst:IsA("BasePart") then
        cf = inst.CFrame
    elseif inst:IsA("Model") then
        local ok, pivot = pcall(function()
            return inst:GetPivot()
        end)
        cf = ok and pivot or nil
        if not cf then
            local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
            cf = part and part.CFrame
        end
    else
        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        cf = part and part.CFrame
    end
    if not cf then
        return nil
    end
    local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
    if look.Magnitude < 0.05 then
        return nil
    end
    return look.Unit, cf.Position
end

-- Explore heading: Gate_Mineshaft.EntranceHitbox LookVector (into the mine).
function S.getMineExploreHeading(mine)
    local hit, gate = S.getMineEntranceHitbox(mine)
    local look, hitPos = S.getInstanceFlatLook(hit)
    if look then
        return look, hit, hitPos
    end
    look, hitPos = S.getInstanceFlatLook(gate)
    if look then
        return look, gate, hitPos
    end
    return S.getAutofarmAxisVector(), nil, nil
end

function S.findNearestMine()
    local best, bestDist = nil, math.huge
    S.scanWorldModels(function(inst)
        if S.isMineRoot(inst) then
            local dist = S.getFlatDistanceToPlayer(inst)
            if dist < bestDist then
                best = inst
                bestDist = dist
            end
        end
    end)
    return best
end

function S.findNearestHubDungeon()
    local best, bestDist = nil, math.huge
    S.scanWorldModels(function(inst)
        if S.isHubDungeonRoot(inst) then
            local dist = S.getFlatDistanceToPlayer(inst)
            if dist < bestDist then
                best = inst
                bestDist = dist
            end
        end
    end)
    return best
end

function S.getVillageEntranceCFrame(village)
    local sellPart = village:FindFirstChild("SellPart", true)
    if sellPart and sellPart:IsA("BasePart") then
        return S.getSellStandCFrame(sellPart)
    end

    local mini = village:FindFirstChild("TradingPostMini", true)
    if mini then
        local cf = S.getDoorEntranceCFrame(mini, 8)
        if cf then
            return cf
        end
    end

    local trading = village:FindFirstChild("TradingPost", true)
    if trading then
        local cf = S.getDoorEntranceCFrame(trading, 8)
        if cf then
            return cf
        end
    end

    local pos = village:GetPivot().Position
    local groundY = S.getGroundY(pos)
    return CFrame.new(pos.X, groundY + 4, pos.Z)
end

function S.getMineEntranceCFrame(mine)
    local hit, gate = S.getMineEntranceHitbox(mine)
    local target = hit or gate
    if target then
        return S.getDoorEntranceCFrame(target, 6)
    end
    return nil
end

-- Nearest unskipped mine on farm corridor — ahead AND behind (never leave mines behind).
function S.getHubDungeonEntranceCFrame(dungeonRoot)
    if not dungeonRoot or not S.isDungeonRoot(dungeonRoot) then
        return nil
    end

    local entrance = dungeonRoot:FindFirstChild("QueueSpot", true)
    if not entrance then
        for _, door in ipairs(CollectionService:GetTagged("DungeonDoor")) do
            if door:IsDescendantOf(dungeonRoot)
                and door.Name ~= "Gate_Cave"
                and door.Name ~= "Gate_Mineshaft"
            then
                entrance = door
                break
            end
        end
    end

    if entrance then
        return S.getDoorEntranceCFrame(entrance, 6)
    end

    return nil
end

function S.teleportHubToNearest(kind)
    local target, label, cf

    if kind == "village" then
        target = S.findNearestVillage()
        label = "Village"
        cf = target and S.getVillageEntranceCFrame(target)
    elseif kind == "mine" then
        target = S.findNearestMine()
        label = "Mine"
        cf = target and S.getMineEntranceCFrame(target)
    else
        target = S.findNearestHubDungeon()
        label = "Dungeon"
        cf = target and S.getHubDungeonEntranceCFrame(target)
    end

    if not target then
        S.notify("Teleport", label .. " not found", 4)
        return false
    end

    if not cf then
        local pos = S.getInstancePosition(target) or target:GetPivot().Position
        local groundY = S.getGroundY(pos)
        cf = CFrame.new(pos.X, groundY + 4, pos.Z)
    end

    local root = S.getRoot()
    if not root then
        S.notify("Teleport", "Character not found", 3)
        return false
    end

    root.CFrame = cf
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    S.notify("Teleport", label .. ": " .. target.Name, 4)
    return true
end

-- ============================================================
-- Teleport ke village di tiap layer (World > Layer Village)
-- ============================================================
-- keys  : nama layer (dinormalisasi) untuk dicocokkan dengan data DepthScale milik game
-- cp    : urutan di DEPTH_LAYER_CHECKPOINTS (cadangan bila data game tidak terbaca)
S.WorldLayers = {
    { label = "Grass Layer", keys = { "grass" }, cp = nil },
    { label = "Dirt Layer", keys = { "dirt" }, cp = 1 },
    { label = "Stone Layer", keys = { "stone" }, cp = 2 },
    { label = "Clay Layer", keys = { "clay" }, cp = 3 },
    { label = "Fossil Layer", keys = { "fossil" }, cp = 4 },
    { label = "Crystal Layer", keys = { "crystal" }, cp = 5 },
    { label = "Toxic Layer", keys = { "toxic" }, cp = 6 },
    { label = "Frozen Layer", keys = { "frozen", "radioactive" }, cp = 7 },
    { label = "Abyss Layer", keys = { "abyss" }, cp = 8 },
    { label = "Void Layer", keys = { "void" }, cp = 9 },
    { label = "Glowing Core Layer", keys = { "glowingcore" }, cp = 10 },
}

function S.normalizeLayerName(name)
    local n = string.lower(tostring(name or "")):gsub("[^%a]", "")
    n = n:gsub("^the", "")
    n = n:gsub("layer$", "")
    return n
end

-- Posisi titik awal layer pada rute. Utamakan data asli game, lalu cadangan dari dump.
function S.resolveLayerWorldPos(layer)
    local ds = S.getDepthScale()
    if ds and type(ds.GetTownLocationThresholds) == "function" then
        local ok, thresholds = pcall(ds.GetTownLocationThresholds, ds)
        if ok and type(thresholds) == "table" then
            for _, entry in ipairs(thresholds) do
                local name = entry and entry.Name
                local startM = entry and entry.StartMeters
                if type(name) == "string" and type(startM) == "number" then
                    local norm = S.normalizeLayerName(name)
                    for _, key in ipairs(layer.keys) do
                        if norm == key then
                            local pos = S.getWorldPositionAtDepthMeters(startM)
                            if pos then
                                return pos, "game"
                            end
                        end
                    end
                end
            end
        end
    end

    if layer.cp and DEPTH_LAYER_CHECKPOINTS[layer.cp] then
        return DEPTH_LAYER_CHECKPOINTS[layer.cp].Pos, "dump"
    end

    -- Grass Layer = awal rute.
    local startPos = Workspace:GetAttribute("Start_Position")
    if typeof(startPos) == "Vector3" then
        return startPos, "start"
    end
    local pos = S.getWorldPositionAtDepthMeters(0)
    if pos then
        return pos, "start"
    end
    return nil
end

function S.findVillageNearPosition(target, maxDist)
    local best, bestDist = nil, maxDist or 2500
    S.scanWorldModels(function(inst)
        if S.isVillageModel(inst) then
            local pos = S.getInstancePosition(inst)
            if pos then
                local dx, dz = pos.X - target.X, pos.Z - target.Z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist < bestDist then
                    best, bestDist = inst, dist
                end
            end
        end
    end)
    return best
end

-- Titik tengah village (bukan trading post): ambil pusat bounding box, lalu cari tanah terbuka
-- terdekat dari pusat. Titik di atap/bangunan dibuang dengan membandingkan ke tinggi tanah.
function S.getVillageCenterCFrame(village)
    local okBox, boxCF, size = pcall(function()
        return village:GetBoundingBox()
    end)
    if not okBox or typeof(boxCF) ~= "CFrame" or typeof(size) ~= "Vector3" then
        return S.getVillageEntranceCFrame(village)
    end

    local center = boxCF.Position
    S.requestStreamAround(center, 2)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local char = LocalPlayer.Character
    if char then
        params.FilterDescendantsInstances = { char }
    end
    pcall(function()
        params.RespectCanCollide = true
    end)

    local topY = center.Y + size.Y * 0.5 + 60
    local rayLen = size.Y + 400
    local function cast(x, z)
        local hit = Workspace:Raycast(Vector3.new(x, topY, z), Vector3.new(0, -rayLen, 0), params)
        if hit and hit.Normal.Y > 0.6 then
            return hit.Position.Y
        end
        return nil
    end

    -- Perkiraan tinggi tanah = kuartil bawah dari grid sampel di dalam village.
    local halfX = math.clamp(size.X * 0.5, 10, 70)
    local halfZ = math.clamp(size.Z * 0.5, 10, 70)
    local ys = {}
    for ix = -2, 2 do
        for iz = -2, 2 do
            local y = cast(center.X + halfX * ix / 2, center.Z + halfZ * iz / 2)
            if y then
                ys[#ys + 1] = y
            end
        end
    end
    if #ys == 0 then
        return S.getVillageEntranceCFrame(village)
    end
    table.sort(ys)
    local groundY = ys[math.max(1, math.floor(#ys * 0.25))]

    -- Cari titik terdekat dari pusat yang berdiri di tanah (bukan di atap).
    local radii = { 0, 8, 16, 24, 32, 44, 56, 70 }
    for _, r in ipairs(radii) do
        local steps = (r == 0) and 1 or 8
        for i = 0, steps - 1 do
            local ang = (i / steps) * math.pi * 2
            local x = center.X + math.cos(ang) * r
            local z = center.Z + math.sin(ang) * r
            local y = cast(x, z)
            if y and math.abs(y - groundY) <= 3 then
                return CFrame.new(x, y + 4, z)
            end
        end
    end

    return CFrame.new(center.X, groundY + 4, center.Z)
end

function S.teleportToLayerVillage(layer)
    if S._layerTpBusy then
        S.notify("Teleport", "Layer teleport still in progress…", 2)
        return
    end
    if Autofarm.enabled then
        S.notify("Teleport", "Turn Run off before teleporting to a layer", 3)
        return
    end
    if not S.getRoot() then
        S.notify("Teleport", "Character not found", 3)
        return
    end

    local target = S.resolveLayerWorldPos(layer)
    if not target then
        S.notify("Teleport", layer.label .. ": position not found", 4)
        return
    end

    S._layerTpBusy = true
    task.spawn(function()
        local ok, err = pcall(function()
            local root = S.getRoot()
            if not root then
                return
            end

            S.notify("Teleport", layer.label .. ": menuju area layer…", 3)
            local hold = Vector3.new(target.X, target.Y + 40, target.Z)
            root.Anchored = true
            root.CFrame = CFrame.new(hold)
            root.AssemblyLinearVelocity = Vector3.zero
            S.requestStreamAround(hold, 3)

            -- Tunggu dunia ter-load, lalu cari village terdekat dari titik layer.
            local village = nil
            for _ = 1, 8 do
                village = S.findVillageNearPosition(target, 2500)
                if village then
                    break
                end
                task.wait(0.6)
                S.requestStreamAround(hold, 2)
            end

            root = S.getRoot()
            if not root then
                return
            end

            if village then
                local cf = S.getVillageCenterCFrame(village)
                local vpos = cf.Position
                S.requestStreamAround(vpos, 2)
                root.CFrame = cf
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                task.wait(0.5)
                S.notify("Teleport", layer.label .. ": " .. village.Name, 4)
            else
                local groundY = S.getGroundY(hold)
                root.CFrame = CFrame.new(target.X, groundY + 4, target.Z)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                S.notify("Teleport", layer.label .. ": village not loaded yet, sent to the layer point", 5)
            end
        end)

        local root = S.getRoot()
        if root then
            root.Anchored = false
            root.AssemblyLinearVelocity = Vector3.zero
        end
        S._layerTpBusy = false
        if not ok then
            S.notify("Teleport", "Failed: " .. tostring(err), 5)
            warn("[JPAX] layer teleport", err)
        end
    end)
end

-- ============================================================
-- Minimize menu + tombol bundar "J"
-- Tombol J selalu tampil di layar. Klik untuk menampilkan / menyembunyikan menu.
-- Hijau penuh = menu terbuka, gelap = menu tersembunyi. Tombol bisa digeser.
-- ============================================================
function S.isMenuVisible()
    local lib = S._jpaxLibrary
    if lib and type(lib.Toggled) == "boolean" then
        return lib.Toggled
    end
    return not (S._mini and S._mini.hiddenByMe == true)
end

function S.setMenuVisible(visible)
    visible = visible == true
    local lib = S._jpaxLibrary
    if not lib or S.isMenuVisible() == visible then
        return
    end
    local ok = pcall(function()
        lib:Toggle()
    end)
    if not ok then
        pcall(function()
            if lib.ScreenGui then
                lib.ScreenGui.Enabled = visible
            end
        end)
    end
    if S._mini then
        S._mini.hiddenByMe = not visible
    end
    S.syncMiniButton()
end

function S.minimizeMenu()
    S.setMenuVisible(false)
end

function S.syncMiniButton()
    local M = S._mini
    if M and M.btn and M.btn.Parent then
        local shown = S.isMenuVisible()
        M.btn.Visible = true
        M.btn.BackgroundColor3 = shown and Color3.fromRGB(61, 180, 136) or Color3.fromRGB(28, 28, 28)
        M.btn.TextColor3 = shown and Color3.fromRGB(28, 28, 28) or Color3.fromRGB(61, 180, 136)
    end
end

function S.destroyMiniButton()
    local M = S._mini
    if not M then
        return
    end
    S._mini = nil
    for _, conn in ipairs(M.conns) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    if M.gui then
        pcall(function()
            M.gui:Destroy()
        end)
    end
end

function S.createMiniButton()
    S.destroyMiniButton()

    local parent
    if typeof(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and hui then
            parent = hui
        end
    end
    if not parent and LocalPlayer then
        parent = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 3)
    end
    if not parent then
        return false
    end

    local SIZE = 52
    local ACCENT = Color3.fromRGB(61, 180, 136)
    local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)

    local gui = Instance.new("ScreenGui")
    gui.Name = "JpaxMiniButton"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 10000
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local btn = Instance.new("TextButton")
    btn.Name = "J"
    btn.Text = "J"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 28
    btn.TextColor3 = ACCENT
    btn.AutoButtonColor = false
    btn.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
    btn.BorderSizePixel = 0
    btn.Size = UDim2.fromOffset(SIZE, SIZE)
    btn.Position = UDim2.fromOffset(16, math.floor(viewport.Y * 0.5 - SIZE * 0.5))
    btn.Visible = true
    btn.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Color = ACCENT
    stroke.Thickness = 2
    stroke.Parent = btn

    if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, gui)
    end
    gui.Parent = parent

    local M = { gui = gui, btn = btn, conns = {}, hiddenByMe = false }
    S._mini = M
    S.syncMiniButton()

    -- Geser + klik (gerakan < 6px dianggap klik)
    local dragging, moved = false, false
    local dragStart, startPos = Vector2.zero, Vector2.zero

    table.insert(M.conns, btn.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart = Vector2.new(input.Position.X, input.Position.Y)
            startPos = Vector2.new(btn.Position.X.Offset, btn.Position.Y.Offset)
            local ended
            ended = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    ended:Disconnect()
                    local wasClick = dragging and not moved
                    dragging = false
                    if wasClick then
                        S.setMenuVisible(not S.isMenuVisible())
                    end
                end
            end)
        end
    end))

    table.insert(M.conns, UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then
            return
        end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        if delta.Magnitude > 6 then
            moved = true
        end
        if moved then
            local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or viewport
            local x = math.clamp(startPos.X + delta.X, 0, math.max(0, vp.X - SIZE))
            local y = math.clamp(startPos.Y + delta.Y, 0, math.max(0, vp.Y - SIZE))
            btn.Position = UDim2.fromOffset(x, y)
        end
    end))

    -- Sinkronkan warna tombol dengan status menu (termasuk saat menu disembunyikan lewat keybind).
    task.spawn(function()
        while S._mini == M and gui.Parent do
            pcall(S.syncMiniButton)
            task.wait(0.2)
        end
    end)
    return true
end

function S.rejoinSameServer()
    local placeId = game.PlaceId
    local jobId = game.JobId
    if type(jobId) ~= "string" or jobId == "" then
        S.notify("Rejoin", "No JobId (solo/private?). Trying place teleport…", 4)
        local ok, err = pcall(function()
            TeleportService:Teleport(placeId, LocalPlayer)
        end)
        if not ok then
            S.notify("Rejoin", "Failed: " .. tostring(err), 5)
            return false
        end
        return true
    end

    S.notify("Rejoin", "Rejoining same server…", 3)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
    end)
    if not ok then
        S.notify("Rejoin", "Failed: " .. tostring(err), 5)
        return false
    end
    return true
end

-- ========== AUTO UPGRADES ==========
function S.resolveDropdownChoice(choice)
    if type(choice) == "table" then
        return choice[1] or choice.Name or choice.CurrentOption or "None"
    end
    if choice == nil or choice == "" then
        return "None"
    end
    return choice
end

function S.syncUpgradePrioritiesFromFlags()
    local flags = Rayfield and Rayfield.Flags
    if not flags then
        return
    end

    for _, slot in ipairs(Upgrades.prioritySlots) do
        local flag = flags[slot.flag]
        if flag and flag.CurrentOption ~= nil then
            slot.value = S.resolveDropdownChoice(flag.CurrentOption)
        end
    end
end

function S.findRayfieldTabPage(tabName)
    for _, gui in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            local elements = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Elements")
            if not elements then
                elements = gui:FindFirstChild("Elements", true)
            end
            if elements then
                local page = elements:FindFirstChild(tabName)
                if page then
                    return page
                end
            end
        end
    end
    return nil
end

function S.applyPriorityElementLayout(elementName, layoutOrder)
    task.spawn(function()
        local page = Upgrades.tabPage or S.findRayfieldTabPage("Upgrades")
        for _ = 1, 30 do
            if page then
                break
            end
            task.wait(0.1)
            page = Upgrades.tabPage or S.findRayfieldTabPage("Upgrades")
        end
        if not page then
            return
        end
        Upgrades.tabPage = page

        for _ = 1, 20 do
            local element = page:FindFirstChild(elementName)
            if element then
                element.LayoutOrder = layoutOrder
                return
            end
            task.wait(0.05)
        end
    end)
end

function S.capturePrioritySlotGui(slot)
    task.defer(function()
        local page = Upgrades.tabPage or S.findRayfieldTabPage("Upgrades")
        if page then
            Upgrades.tabPage = page
        end
        if not page then
            return
        end
        slot.dropdownGui = page:FindFirstChild(slot.dropdownLabel)
    end)
end

function S.getPriorityLayout(index)
    return UPGRADE_PRIORITY_FIRST_LAYOUT + index - 1
end

function S.getPriorityDropdownLabel(index)
    if index == 1 then
        return "Priority 1 (buy first)"
    end
    return "Priority " .. index
end

function S.cleanupLegacyPriorityRemoveButtons()
    local page = Upgrades.tabPage or S.findRayfieldTabPage("Upgrades")
    if not page then
        return
    end
    Upgrades.tabPage = page
    for _, child in ipairs(page:GetChildren()) do
        if child.Name:match("^HubPrioRemove_") then
            child:Destroy()
        end
    end
end

function S.relayoutUpgradePrioritySlots()
    S.cleanupLegacyPriorityRemoveButtons()

    for index, slot in ipairs(Upgrades.prioritySlots) do
        local dropdownLabel = S.getPriorityDropdownLabel(index)
        slot.dropdownLabel = dropdownLabel
        slot.layoutDropdown = S.getPriorityLayout(index)

        if slot.dropdownGui and slot.dropdownGui.Parent then
            slot.dropdownGui.Name = dropdownLabel
            local title = slot.dropdownGui:FindFirstChild("Title")
            if title then
                title.Text = dropdownLabel
            end
            slot.dropdownGui.LayoutOrder = slot.layoutDropdown
        else
            S.applyPriorityElementLayout(dropdownLabel, slot.layoutDropdown)
        end
    end
end

function S.destroyUpgradePrioritySlotAtIndex(index)
    local slot = Upgrades.prioritySlots[index]
    if not slot then
        return
    end

    if slot.dropdownGui and slot.dropdownGui.Parent then
        slot.dropdownGui:Destroy()
    elseif Upgrades.tabPage then
        local dropdown = Upgrades.tabPage:FindFirstChild(slot.dropdownLabel)
        if dropdown then
            dropdown:Destroy()
        end
    end

    if Rayfield and Rayfield.Flags and slot.flag then
        Rayfield.Flags[slot.flag] = nil
    end

    table.remove(Upgrades.prioritySlots, index)
end

function S.ensureUpgradePrioritySlotCount(targetCount)
    if not Upgrades.tab then
        return false
    end

    targetCount = math.max(1, targetCount or 1)

    while #Upgrades.prioritySlots < targetCount do
        S.createUpgradePrioritySlot(Upgrades.tab, "None")
    end

    while #Upgrades.prioritySlots > targetCount do
        S.destroyUpgradePrioritySlotAtIndex(#Upgrades.prioritySlots)
    end

    S.relayoutUpgradePrioritySlots()
    return true
end

function S.applyUpgradePrioritiesFromConfig(priorities)
    if type(priorities) ~= "table" then
        return
    end

    local values = {}
    for index, value in ipairs(priorities) do
        values[index] = S.resolveDropdownChoice(value)
    end

    S.ensureUpgradePrioritySlotCount(math.max(1, #values))

    for index, value in ipairs(values) do
        local slot = Upgrades.prioritySlots[index]
        if slot then
            slot.value = value or "None"
            S.configApplyFlagValue(slot.flag, slot.value)
        end
    end

    S.syncUpgradePrioritiesFromFlags()
    S.relayoutUpgradePrioritySlots()
end

function S.createUpgradePrioritySlot(tab, preferredValue)
    local slotId = Upgrades.nextSlotId
    Upgrades.nextSlotId += 1

    local index = #Upgrades.prioritySlots + 1
    local dropdownLabel = S.getPriorityDropdownLabel(index)
    local flag = "terra_upgrade_prio_" .. slotId

    local slot = {
        id = slotId,
        value = preferredValue or "None",
        flag = flag,
        dropdownLabel = dropdownLabel,
        layoutDropdown = S.getPriorityLayout(index),
    }

    local dropdownSettings = tab:CreateDropdown({
        Name = dropdownLabel,
        Options = UPGRADE_DROPDOWN_OPTIONS,
        CurrentOption = slot.value,
        Flag = flag,
        Callback = function(option)
            slot.value = S.resolveDropdownChoice(option)
        end,
    })

    S.registerRayfieldFlag(dropdownSettings)

    table.insert(Upgrades.prioritySlots, slot)
    S.capturePrioritySlotGui(slot)
    S.applyPriorityElementLayout(dropdownLabel, slot.layoutDropdown)

    return slot
end

function S.addUpgradePrioritySlot(tab)
    S.createUpgradePrioritySlot(tab, "None")
    S.relayoutUpgradePrioritySlots()
    S.notify("Upgrades", "Added priority " .. #Upgrades.prioritySlots, 2)
end

function S.normalizeUpgradeLabel(text)
    return string.lower((tostring(text or "")):gsub("%s+", " "):match("^%s*(.-)%s*$") or "")
end

function S.getUpgradeDisplayName(internalName)
    return UPGRADE_DISPLAY_INFO[internalName] or internalName
end

function S.hasUpgradeOptions(options)
    if type(options) ~= "table" then
        return false
    end

    for _, option in pairs(options) do
        if type(option) == "table" and option.UpgradeName then
            return true
        end
    end

    return false
end

function S.rememberUpgradeOptionsVersion(optionsVersion)
    if typeof(optionsVersion) ~= "number" then
        return
    end
    if optionsVersion > (Upgrades.optionsVersion or 0) then
        Upgrades.optionsVersion = optionsVersion
    end
end

function S.getUpgradeOptionsFromUI()
    local gui = LocalPlayer.PlayerGui:FindFirstChild("DrillUpgrade")
    if not gui or not gui.Enabled then
        return nil
    end

    local frame = gui:FindFirstChild("Frame")
    local cards = frame and frame:FindFirstChild("Cards")
    if not cards then
        return nil
    end

    local options = {}
    for _, child in ipairs(cards:GetChildren()) do
        if child:IsA("Frame") then
            local upgradeName = child:GetAttribute("UpgradeName")
            if upgradeName and upgradeName ~= "" then
                local slot = tonumber(child.Name) or (#options + 1)
                options[slot] = {
                    UpgradeName = upgradeName,
                    Cost = child:GetAttribute("Cost"),
                    Rarity = child:GetAttribute("Rarity"),
                    Type = child:GetAttribute("RobuxCard") and "Robux" or "Coins",
                }
            end
        end
    end

    if not S.hasUpgradeOptions(options) then
        return nil
    end

    return options
end

function S.getUpgradePriorities()
    local priorities = {}
    for _, slot in ipairs(Upgrades.prioritySlots) do
        table.insert(priorities, S.resolveDropdownChoice(slot.value))
    end
    return priorities
end

function S.optionMatchesPreference(option, preference)
    preference = S.resolveDropdownChoice(preference)
    if not option or not preference or preference == "None" then
        return false
    end

    if option.Type == "Robux" or option.RobuxCard then
        return false
    end

    local pref = S.normalizeUpgradeLabel(preference)
    if pref == "" then
        return false
    end

    local internalName = option.UpgradeName or ""
    local displayName = S.getUpgradeDisplayName(internalName)
    local normInternal = S.normalizeUpgradeLabel(internalName)
    local normDisplay = S.normalizeUpgradeLabel(displayName)

    if normInternal == pref or normDisplay == pref then
        return true
    end
    if normDisplay:find(pref, 1, true) or normInternal:find(pref, 1, true) then
        return true
    end

    return false
end

function S.pickUpgradeFromOptions(options)
    if not S.hasUpgradeOptions(options) then
        return nil
    end

    for _, preference in ipairs(S.getUpgradePriorities()) do
        for _, option in pairs(options) do
            if type(option) == "table" and S.optionMatchesPreference(option, preference) then
                return option, preference
            end
        end
    end

    return nil
end

function S.tryAutoBuyUpgrade(options)
    if not Upgrades.autoBuy or Upgrades.busy or not Services.DrillService then
        return false
    end

    S.syncUpgradePrioritiesFromFlags()

    local pick, matchedPref = S.pickUpgradeFromOptions(options)
    if not pick then
        return false
    end

    Upgrades.busy = true

    local function finish()
        task.wait(0.5)
        Upgrades.busy = false
    end

    local function purchase(coins)
        local upgradeName = pick.UpgradeName
        local displayName = S.getUpgradeDisplayName(upgradeName)
        local tier = pick.Tier and (" " .. tostring(pick.Tier)) or ""
        local cost = tonumber(pick.Cost) or 0

        if cost > 0 and coins ~= nil and coins < cost then
            S.hubLog("Auto buy skipped (not enough coins): " .. displayName .. " cost " .. cost .. " have " .. coins)
            Upgrades.busy = false
            return
        end

        local version = Upgrades.optionsVersion
        if typeof(version) ~= "number" or version <= 0 then
            S.hubLog("Auto buy skipped: missing OptionsVersion (wait for upgrade roll)")
            Upgrades.busy = false
            return
        end

        S.hubLog("Auto buy: " .. displayName .. tier .. " (" .. tostring(upgradeName) .. ") v" .. tostring(version))

        local result = Services.DrillService:UpgradeDrill(upgradeName, version)
        if typeof(result) == "table" and result.andThen then
            result:andThen(function(ok)
                if ok == true then
                    S.notify("Upgrades", "Bought: " .. displayName .. tier, 3)
                else
                    S.hubLog("UpgradeDrill returned: " .. tostring(ok))
                end
                finish()
            end):catch(function(err)
                S.hubLog("UpgradeDrill error: " .. tostring(err))
                finish()
            end)
        else
            if result == true then
                S.notify("Upgrades", "Bought: " .. displayName .. tier, 3)
            else
                S.hubLog("UpgradeDrill returned: " .. tostring(result))
            end
            finish()
        end
    end

    if Services.CurrencyService then
        Services.CurrencyService:GetCurrency():andThen(function(coins)
            purchase(tonumber(coins))
        end):catch(function()
            purchase(nil)
        end)
    else
        purchase(nil)
    end

    return true
end

function S.scheduleAutoBuy(options, rollPreview)
    if not Upgrades.autoBuy then
        return
    end

    local delaySeconds = 0.75
    if type(rollPreview) == "table" and #rollPreview > 0 then
        delaySeconds = 3.5
    end

    task.delay(delaySeconds, function()
        local uiOptions = S.getUpgradeOptionsFromUI()
        S.tryAutoBuyUpgrade(uiOptions or options)
    end)
end

function S.refreshAndAutoBuy()
    if not Services.DrillService then
        return
    end

    local uiOptions = S.getUpgradeOptionsFromUI()
    if uiOptions then
        S.scheduleAutoBuy(uiOptions)
        return
    end

    Services.DrillService:FetchOptions():andThen(function(options, optionsVersion)
        S.rememberUpgradeOptionsVersion(optionsVersion)
        S.scheduleAutoBuy(options, nil)
    end)
end

function S.connectUpgradePoll()
    S.disconnectAll("upgradePoll")

    State.lastUpgradePoll = 0
    State.connections.upgradePoll = RunService.Heartbeat:Connect(function()
        if not Upgrades.autoBuy or Upgrades.busy then
            return
        end

        if tick() - (State.lastUpgradePoll or 0) < 1.5 then
            return
        end
        State.lastUpgradePoll = tick()

        local uiOptions = S.getUpgradeOptionsFromUI()
        if uiOptions then
            if (Upgrades.optionsVersion or 0) <= 0 and Services.DrillService and not Upgrades.optionsFetchPending then
                Upgrades.optionsFetchPending = true
                Services.DrillService:FetchOptions():andThen(function(_, optionsVersion)
                    Upgrades.optionsFetchPending = false
                    S.rememberUpgradeOptionsVersion(optionsVersion)
                    S.tryAutoBuyUpgrade(uiOptions)
                end):catch(function()
                    Upgrades.optionsFetchPending = false
                end)
            else
            S.tryAutoBuyUpgrade(uiOptions)
            end
        end
    end)
end

function S.connectAutoUpgrade()
    S.disconnectAll("upgradeOptions")

    if not Services.DrillService then
        return
    end

    if Services.DrillService.Options then
        State.connections.upgradeOptions = Services.DrillService.Options:Connect(function(options, rollPreview, optionsVersion)
            S.rememberUpgradeOptionsVersion(optionsVersion)
            if Upgrades.autoBuy and S.hasUpgradeOptions(options) then
                S.scheduleAutoBuy(options, rollPreview)
            end
        end)
    else
        S.hubLog("DrillService.Options signal missing")
    end
end

function S.setAutoUpgrade(enabled)
    Upgrades.autoBuy = enabled
    S.disconnectAll("upgradePoll")

    if not enabled then
        return
    end

    S.syncUpgradePrioritiesFromFlags()
    S.connectAutoUpgrade()
    S.connectUpgradePoll()
    S.refreshAndAutoBuy()
end

function S.setAutoMine(enabled)
    Pickaxe.autoMine = enabled
    S.disconnectAll("autoMine")

    if not enabled then
        return
    end

    State.connections.autoMine = RunService.Heartbeat:Connect(function()
        if not Pickaxe.autoMine or Pickaxe.busy or Autofarm.miningBusy then
            return
        end
        if (tick() - (State.lastMineTick or 0)) < 0.7 then
            return
        end
        State.lastMineTick = tick()
        Pickaxe.busy = true
        task.spawn(function()
            pcall(S.mineSwing)
            Pickaxe.busy = false
        end)
    end)
end

function S.setAutoMoney(enabled)
    Money.enabled = enabled
    S.disconnectAll("autoMoney")

    if not enabled then
        return
    end

    S.resetMoneyTravelHeading()
    task.spawn(function()
        S.resumeOnDrillLine()
    end)

    State.connections.autoMoney = RunService.Heartbeat:Connect(function()
        if not Money.enabled or Money.busy or (tick() - (State.lastMoneyTick or 0)) < 4 then
            return
        end
        State.lastMoneyTick = tick()
        Money.busy = true
        task.spawn(function()
            pcall(S.runMoneyCycle)
            Money.busy = false
        end)
    end)
end

function S.setAutoEquipBag(enabled)
    -- Fitur Auto Equip Bag dihapus karena sack sudah tidak ada.
    Loot.autoEquipBag = false
    S.disconnectAll("autoEquipBag")
end

function S.setAutoEquipPickaxe(enabled)
    Pickaxe.autoEquip = enabled
    S.disconnectAll("autoEquipPickaxe")

    if not enabled then
        return
    end

    task.spawn(function()
        S.ensurePickaxe()
    end)

    local lastTick = 0
    State.connections.autoEquipPickaxe = RunService.Heartbeat:Connect(function()
        if not Pickaxe.autoEquip then
            return
        end
        if tick() - lastTick < 0.5 then
            return
        end
        lastTick = tick()

        local equipped = S.getEquippedTool()
        local best = S.findBestPickaxe()
        if not best then
            return
        end
        if not equipped or not S.isPickaxeTool(equipped) or equipped.Name ~= best.Name then
            S.ensurePickaxe()
        end
    end)
end

function S.setAutoLoot(enabled)
    Loot.enabled = enabled
    S.disconnectAll("autoLoot")

    if not enabled then
        State.cachedTruckRegion = nil
        return
    end

    State.connections.autoLoot = RunService.Heartbeat:Connect(function()
        if not Loot.enabled or Loot.busy or (tick() - (State.lastLootTick or 0)) < 0.08 then
            return
        end
        State.lastLootTick = tick()
        Loot.busy = true
        task.spawn(function()
            pcall(S.runLootCycle)
            Loot.busy = false
        end)
    end)
end

function S.applySpeed()
    local humanoid = S.getHumanoid()
    if not humanoid then
        return
    end
    if State.speedHack then
        humanoid:SetAttribute("SpeedBoost", State.speedBoost)
        humanoid:SetAttribute("SpeedMultiplier", State.speedMultiplier)
        humanoid:SetAttribute("SpeedPotionMultiplier", 1)
        humanoid:SetAttribute("ClassAuraSpeedMultiplier", 1)
        humanoid:SetAttribute("MaxSpeed", 500)
    end
    humanoid.JumpPower = State.jumpPower
end

function S.setSpeedHack(enabled)
    State.speedHack = enabled == true
    S.disconnectAll("speed")
    S.disconnectAll("speedHeartbeat")

    if not State.speedHack then
        local humanoid = S.getHumanoid()
        if humanoid then
            humanoid:SetAttribute("SpeedBoost", 0)
            humanoid:SetAttribute("SpeedMultiplier", 1)
            humanoid:SetAttribute("MaxSpeed", math.huge)
        end
        return
    end

    S.applySpeed()
    local lastApply = 0
    State.connections.speedHeartbeat = RunService.Heartbeat:Connect(function()
        if not State.speedHack then
            return
        end
        if tick() - lastApply < 0.2 then
            return
        end
        lastApply = tick()
        S.applySpeed()
    end)
    State.connections.speed = LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        if State.speedHack then
            S.applySpeed()
        end
    end)
end

function S.setNoclip(enabled)
    State.noclip = enabled
    S.disconnectAll("noclip")
    if not enabled then return end

    State.connections.noclip = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

function S.setFly(enabled)
    State.fly = enabled
    S.disconnectAll("fly")
    S.disconnectAll("flyKeysDown")
    S.disconnectAll("flyKeysUp")

    local function cleanupFlyInstances(root)
        if not root then
            return
        end
        pcall(function()
            for _, name in ipairs({ "JPAXFlyBV", "JPAXFlyBG" }) do
                local old = root:FindFirstChild(name)
                if old then
                    old:Destroy()
                end
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    cleanupFlyInstances(S.getRoot())
    local humanoid = S.getHumanoid()
    if humanoid and not Autofarm.enabled then
        pcall(function()
            humanoid.PlatformStand = false
        end)
    end
    pcall(function()
        Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
    end)

    if not enabled then
        return
    end

    -- Infinite Yield sFLY clone (fly / fly 2 / fly 10 style)
    local CONTROL = { F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0 }
    local lCONTROL = { F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0 }
    local SPEED = 0
    local bg, bv

    local function iySpeed()
        return math.clamp(tonumber(State.flySpeed) or 1, 0.1, 10)
    end

    State.connections.flyKeysDown = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end
        local s = iySpeed()
        if input.KeyCode == Enum.KeyCode.W then
            CONTROL.F = s
        elseif input.KeyCode == Enum.KeyCode.S then
            CONTROL.B = -s
        elseif input.KeyCode == Enum.KeyCode.A then
            CONTROL.L = -s
        elseif input.KeyCode == Enum.KeyCode.D then
            CONTROL.R = s
        elseif input.KeyCode == Enum.KeyCode.E then
            CONTROL.Q = s * 2
        elseif input.KeyCode == Enum.KeyCode.Q then
            CONTROL.E = -s * 2
        end
    end)

    State.connections.flyKeysUp = UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.W then
            CONTROL.F = 0
        elseif input.KeyCode == Enum.KeyCode.S then
            CONTROL.B = 0
        elseif input.KeyCode == Enum.KeyCode.A then
            CONTROL.L = 0
        elseif input.KeyCode == Enum.KeyCode.D then
            CONTROL.R = 0
        elseif input.KeyCode == Enum.KeyCode.E then
            CONTROL.Q = 0
        elseif input.KeyCode == Enum.KeyCode.Q then
            CONTROL.E = 0
        end
    end)

    State.connections.fly = RunService.Heartbeat:Connect(function()
        if not State.fly then
            return
        end

        local char = LocalPlayer.Character
        local root = S.getRoot()
        local hum = S.getHumanoid()
        local cam = Workspace.CurrentCamera
        if not char or not root or not hum or not cam or hum.Health <= 0 then
            return
        end

        hum.PlatformStand = true

        if not bg or not bg.Parent then
            bg = Instance.new("BodyGyro")
            bg.Name = "JPAXFlyBG"
            bg.P = 9e4
            bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            bg.CFrame = root.CFrame
            bg.Parent = root
        end
        if not bv or not bv.Parent then
            bv = Instance.new("BodyVelocity")
            bv.Name = "JPAXFlyBV"
            bv.Velocity = Vector3.zero
            bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bv.Parent = root
        end

        -- Mobile / controller stick → same CONTROL layout as WASD
        if UserInputService.TouchEnabled and CONTROL.F == 0 and CONTROL.B == 0 and CONTROL.L == 0 and CONTROL.R == 0 then
            local md = hum.MoveDirection
            if md.Magnitude > 0.05 then
                local s = iySpeed()
                local flatLook = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
                local flatRight = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
                if flatLook.Magnitude > 0.05 and flatRight.Magnitude > 0.05 then
                    flatLook = flatLook.Unit
                    flatRight = flatRight.Unit
                    local f = md:Dot(flatLook)
                    local r = md:Dot(flatRight)
                    CONTROL.F = f > 0.15 and s or 0
                    CONTROL.B = f < -0.15 and -s or 0
                    CONTROL.R = r > 0.15 and s or 0
                    CONTROL.L = r < -0.15 and -s or 0
                end
            else
                CONTROL.F, CONTROL.B, CONTROL.L, CONTROL.R = 0, 0, 0, 0
            end
        end

        if CONTROL.L + CONTROL.R ~= 0 or CONTROL.F + CONTROL.B ~= 0 or CONTROL.Q + CONTROL.E ~= 0 then
            SPEED = 50
        elseif SPEED ~= 0 then
            SPEED = 0
        end

        if (CONTROL.L + CONTROL.R) ~= 0 or (CONTROL.F + CONTROL.B) ~= 0 or (CONTROL.Q + CONTROL.E) ~= 0 then
            bv.Velocity = (
                (cam.CFrame.LookVector * (CONTROL.F + CONTROL.B))
                + ((cam.CFrame * CFrame.new(CONTROL.L + CONTROL.R, (CONTROL.F + CONTROL.B + CONTROL.Q + CONTROL.E) * 0.2, 0)).Position - cam.CFrame.Position)
            ) * SPEED
            lCONTROL = { F = CONTROL.F, B = CONTROL.B, L = CONTROL.L, R = CONTROL.R }
        elseif SPEED ~= 0 then
            bv.Velocity = (
                (cam.CFrame.LookVector * (lCONTROL.F + lCONTROL.B))
                + ((cam.CFrame * CFrame.new(lCONTROL.L + lCONTROL.R, (lCONTROL.F + lCONTROL.B + CONTROL.Q + CONTROL.E) * 0.2, 0)).Position - cam.CFrame.Position)
            ) * SPEED
        else
            bv.Velocity = Vector3.zero
        end

        bg.CFrame = cam.CFrame
    end)
end

-- ========== KNIT BOOTSTRAP ==========
function S.bindServices()
    local knit = S.getKnit()
    if not knit then
        return false, "Knit module not found"
    end

    Services.PlayerService = knit.GetService("PlayerService")
    Services.ToolService = knit.GetService("ToolService")
    Services.QuestService = knit.GetService("QuestService")
    Services.CurrencyService = knit.GetService("CurrencyService")
    Services.DrillService = knit.GetService("DrillService")
    Services.TeleportManagerService = knit.GetService("TeleportManagerService")
    Services.ClassService = knit.GetService("ClassService")
    Services.PlayerDataService = knit.GetService("PlayerDataService")
    Services.SpectateService = knit.GetService("SpectateService")
    Services.CutSceneService = knit.GetService("CutSceneService")
    Services.ShopService = knit.GetService("ShopService")
    Services.InteractionService = knit.GetService("InteractionService")
    Services.DragService = knit.GetService("DragService")
    pcall(function()
        Services.CarryInventoryService = knit.GetService("CarryInventoryService")
    end)
    Services.ArmoryShopService = knit.GetService("ArmoryShopService")
    Services.BadgeAwardingService = knit.GetService("BadgeAwardingService")
    Services.AdminCommandService = knit.GetService("AdminCommandService")

    return true
end

function S.waitForKnit(maxSeconds)
    maxSeconds = maxSeconds or 90
    S.hubLog("Waiting for PlayerScripts...")

    local player = LocalPlayer or Players.LocalPlayer
    if not player then
        return false, "LocalPlayer not ready"
    end
    local playerScripts = player:WaitForChild("PlayerScripts", maxSeconds)
    if not playerScripts then
        return false, "PlayerScripts not found"
    end

    local controllers = playerScripts:WaitForChild("Controllers", math.min(30, maxSeconds))
    if controllers then
        S.hubLog("Controllers found")
    else
        S.hubLog("Controllers not found yet")
    end

    local knit = S.getKnit()
    if not knit then
        return false, "Knit module not found"
    end

    S.hubLog("Waiting for Knit.OnStart...")
    local finished = false
    local knitError = nil

    task.spawn(function()
        local ok, err = pcall(function()
            knit.OnStart():await()
        end)
        if not ok then
            knitError = err
        end
        finished = true
    end)

    local started = os.clock()
    while not finished and os.clock() - started < maxSeconds do
        task.wait(0.25)
    end

    if not finished then
        return false, "Knit timeout"
    end

    if knitError then
        return false, tostring(knitError)
    end

    S.hubLog("Knit ready")
    return true
end

function S.waitForGameReady()
    if not game:IsLoaded() then
        S.hubLog("Waiting for game load...")
        game.Loaded:Wait()
    end
    local player = Players.LocalPlayer or LocalPlayer
    if not player then
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        player = Players.LocalPlayer
    end
    local char = player.Character or player.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart", 30)
    if not root then
        return false, "no root"
    end
    local shieldDeadline = os.clock() + 20
    while char.Parent and char:FindFirstChildOfClass("ForceField") and os.clock() < shieldDeadline do
        task.wait(0.2)
    end
    task.wait(0.4)
    return S.waitForKnit(45)
end

function S.connectServicesAsync()
    task.spawn(function()
        local ready, err = S.waitForKnit()
        S._knitReady = true
        if not ready then
            S.hubLog("Services unavailable: " .. tostring(err))
            S.notify(HUB_NAME, "Offline mode (movement only): " .. tostring(err), 6)
            return
        end

        local bindOk, bindErr = pcall(S.bindServices)
        if bindOk then
            S.hubLog("Services bound")
            S.connectAutoUpgrade()
            if Upgrades.autoBuy then
                S.connectUpgradePoll()
                S.refreshAndAutoBuy()
            end
            S.notify(HUB_NAME, "Game services connected", 4)
        else
            S.hubLog("Bind error: " .. tostring(bindErr))
            S.notify(HUB_NAME, "Failed to bind services", 5)
        end
    end)
end

function S.setFullbright(enabled)
    State.fullbright = enabled
    S.disconnectAll("fullbright")

    if not enabled then
        if State.savedLighting then
            pcall(function()
                Lighting.Brightness = State.savedLighting.Brightness
                Lighting.ClockTime = State.savedLighting.ClockTime
                Lighting.GlobalShadows = State.savedLighting.GlobalShadows
                Lighting.Ambient = State.savedLighting.Ambient
                Lighting.OutdoorAmbient = State.savedLighting.OutdoorAmbient
                Lighting.FogEnd = State.savedLighting.FogEnd
            end)
        end
        return
    end

    State.savedLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        GlobalShadows = Lighting.GlobalShadows,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        FogEnd = Lighting.FogEnd,
    }

    State.connections.fullbright = RunService.RenderStepped:Connect(function()
        Lighting.Brightness = 2
        Lighting.ClockTime = 12
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.FogEnd = 100000
    end)
end

function S.registerRayfieldFlag(element)
    if Rayfield and element and element.Flag then
        Rayfield.Flags = Rayfield.Flags or {}
        Rayfield.Flags[element.Flag] = element
    end
    return element
end

function S.configGetInputName()
    local flag = Rayfield and Rayfield.Flags and Rayfield.Flags["jpax_config_name"]
    if flag and type(flag.CurrentValue) == "string" and flag.CurrentValue ~= "" then
        return S.configSanitizeName(flag.CurrentValue)
    end

    local page = S.findRayfieldTabPage("Config")
    if page then
        for _, child in ipairs(page:GetChildren()) do
            if child.Name == "Config Name" then
                local box = child:FindFirstChild("InputFrame", true)
                if box then
                    box = box:FindFirstChild("InputBox")
                end
                if box and type(box.Text) == "string" and box.Text ~= "" then
                    return S.configSanitizeName(box.Text)
                end
                break
            end
        end
    end

    return S.configSanitizeName(Config.newName or Config.selectedName or "default")
end

function S.configGetSelectedName()
    local flag = Rayfield and Rayfield.Flags and Rayfield.Flags["jpax_config_select"]
    if flag and flag.CurrentOption ~= nil then
        return S.configSanitizeName(S.resolveDropdownChoice(flag.CurrentOption))
    end
    return S.configGetInputName()
end

function S.configGetFlagValue(flag)
    if not flag then
        return nil
    end
    if flag.CurrentValue ~= nil then
        return flag.CurrentValue
    end
    if flag.CurrentOption ~= nil then
        return flag.CurrentOption
    end
    if flag.CurrentKeybind ~= nil then
        return flag.CurrentKeybind
    end
    return nil
end

function S.configJsonSafe(value)
    local t = typeof(value)
    if t == "boolean" or t == "number" or t == "string" then
        return value
    end
    if t == "table" then
        local copy = {}
        for key, item in pairs(value) do
            if type(key) == "string" or type(key) == "number" then
                copy[key] = S.configJsonSafe(item)
            end
        end
        return copy
    end
    return nil
end

function S.configHasFileApi()
    return typeof(writefile) == "function" and typeof(readfile) == "function"
end

function S.configEnsureFolder()
    if not S.configHasFileApi() then
        return false
    end
    if typeof(isfolder) == "function" and typeof(makefolder) == "function" then
        if not isfolder(Config.folder) then
            makefolder(Config.folder)
        end
    end
    return true
end

function S.configSanitizeName(name)
    local cleaned = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    cleaned = cleaned:gsub("[^%w%-_ ]", "")
    cleaned = cleaned:gsub("%s+", "_")
    if cleaned == "" then
        return "default"
    end
    return cleaned
end

function S.configGetPath(name)
    return Config.folder .. "/" .. S.configSanitizeName(name) .. ".json"
end

function S.configLoadIndex()
    local names = {}
    if not S.configHasFileApi() then
        return names
    end
    if typeof(isfile) == "function" and not isfile(Config.indexFile) then
        return names
    end

    local readOk, raw = pcall(readfile, Config.indexFile)
    if not readOk then
        return names
    end

    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if decodeOk and type(data) == "table" then
        for _, name in ipairs(data) do
            if type(name) == "string" and name ~= "" then
                table.insert(names, S.configSanitizeName(name))
            end
        end
    end
    return names
end

function S.configSaveIndex(names)
    if not S.configHasFileApi() then
        return
    end
    S.configEnsureFolder()

    local unique = {}
    local cleaned = {}
    for _, name in ipairs(names) do
        local safe = S.configSanitizeName(name)
        if safe ~= "" and not unique[safe] then
            unique[safe] = true
            table.insert(cleaned, safe)
        end
    end
    table.sort(cleaned)

    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, cleaned)
    if ok then
        pcall(writefile, Config.indexFile, encoded)
    end
    return cleaned
end

function S.configAddToIndex(name)
    local safe = S.configSanitizeName(name)
    local names = S.configLoadIndex()
    if not table.find(names, safe) then
        table.insert(names, safe)
    end
    return S.configSaveIndex(names)
end

function S.configRemoveFromIndex(name)
    local safe = S.configSanitizeName(name)
    local names = S.configLoadIndex()
    local kept = {}
    for _, entry in ipairs(names) do
        if entry ~= safe then
            table.insert(kept, entry)
        end
    end
    return S.configSaveIndex(kept)
end

function S.configProfileExists(name)
    local path = S.configGetPath(name)
    if typeof(isfile) == "function" then
        return isfile(path)
    end
    local readOk = pcall(readfile, path)
    return readOk == true
end

function S.configListNames()
    if not S.configHasFileApi() then
        return {}
    end

    local seen = {}
    local names = {}

    local function addName(name)
        local safe = S.configSanitizeName(name)
        if safe == "" or seen[safe] then
            return
        end
        seen[safe] = true
        table.insert(names, safe)
    end

    for _, name in ipairs(S.configLoadIndex()) do
        addName(name)
    end

    if typeof(listfiles) == "function" then
        S.configEnsureFolder()

        local ok, files = pcall(listfiles, Config.folder)
        if ok and type(files) == "table" then
            for _, fileName in ipairs(files) do
                if type(fileName) == "string" then
                    local base = fileName:match("([^/\\]+)$") or fileName
                    if base:sub(-5) == ".json" and base ~= "_index.json" and base ~= "autoload.json" then
                        addName(base:sub(1, -6))
                    end
                end
            end
        end

        ok, files = pcall(listfiles)
        if ok and type(files) == "table" then
            for _, fileName in ipairs(files) do
                if type(fileName) == "string" then
                    local matched = fileName:match("^" .. Config.folder:gsub("([^%w])", "%%%1") .. "/([^/\\]+)%.json$")
                    if matched and matched ~= "_index" and matched ~= "autoload" then
                        addName(matched)
                    end
                end
            end
        end
    end

    local verified = {}
    for _, name in ipairs(names) do
        if S.configProfileExists(name) then
            table.insert(verified, name)
        end
    end

    table.sort(verified)
    if #verified > 0 then
        S.configSaveIndex(verified)
    end
    return verified
end

function S.configRefreshDropdownOptions()
    local names = S.configListNames()
    if #names == 0 then
        names = { "default" }
    end

    local selected = S.configGetSelectedName()
    if not table.find(names, selected) then
        selected = S.configGetInputName()
    end
    if not table.find(names, selected) then
        selected = names[1]
    end

    Config.selectedName = selected
    Config.newName = selected

    local flag = Rayfield and Rayfield.Flags and Rayfield.Flags["jpax_config_select"]
    if flag then
        if flag.Refresh then
            pcall(function()
                flag:Refresh(names)
            end)
        else
            flag.Options = names
        end

        if flag.Set then
            pcall(function()
                flag:Set(selected)
            end)
        else
            flag.CurrentOption = selected
        end
    end

    return names, selected
end

function S.configCapture()
    local payload = {
        version = 2,
        savedAt = os.time(),
        flags = {},
        extras = {},
    }

    if Rayfield and Rayfield.Flags then
        for name, flagObj in pairs(Rayfield.Flags) do
            if name ~= "jpax_config_select" and name ~= "jpax_config_autoload" and name ~= "jpax_config_name"
                and not name:match("^terra_upgrade_prio_") then
                local value = S.configGetFlagValue(flagObj)
                local safe = S.configJsonSafe(value)
                if safe ~= nil then
                    payload.flags[name] = safe
                end
            end
        end
    end

    payload.extras.minCoins = Loot.minCoins
    payload.extras.upgradePriorities = {}
    for index, slot in ipairs(Upgrades.prioritySlots) do
        payload.extras.upgradePriorities[index] = S.resolveDropdownChoice(slot.value)
    end

    return payload
end

function S.configApplyFlag(name, entry)
    if not entry or not Rayfield or not Rayfield.Flags then
        return
    end

    if entry.t == "value" then
        S.configApplyFlagValue(name, entry.v)
    elseif entry.t == "option" then
        S.configApplyFlagValue(name, entry.v)
    end
end

function S.configApplyFlagValue(name, value)
    if not Rayfield or not Rayfield.Flags then
        return
    end

    -- Old configs saved empty keybinds; Rayfield errors on Enum.KeyCode[""].
    if type(name) == "string" and name:find("^terra_kb_", 1, true) then
        if type(value) ~= "string" or value == "" or value == "None" then
            value = "Unknown"
        end
    end

    local flagObj = Rayfield.Flags[name]
    if not flagObj then
        return
    end

    if flagObj.Set then
        pcall(function()
            flagObj:Set(value)
        end)
        return
    end

    if typeof(value) == "boolean" or typeof(value) == "number" or typeof(value) == "string" then
        flagObj.CurrentValue = value
        if flagObj.CurrentKeybind ~= nil then
            flagObj.CurrentKeybind = value
        end
        if flagObj.Callback then
            pcall(flagObj.Callback, value)
        end
        return
    end

    flagObj.CurrentOption = value
    if flagObj.Callback then
        pcall(flagObj.Callback, value)
    end
end

function S.configApply(payload)
    if type(payload) ~= "table" then
        return false, "Invalid config data"
    end

    if type(payload.flags) == "table" then
        for name, value in pairs(payload.flags) do
            if not name:match("^terra_upgrade_prio_") then
                if type(value) == "table" and value.t ~= nil and value.v ~= nil then
                    S.configApplyFlag(name, value)
                else
                    S.configApplyFlagValue(name, value)
                end
            end
        end
    end

    if type(payload.extras) == "table" then
        if payload.extras.minCoins ~= nil then
            Loot.minCoins = tonumber(payload.extras.minCoins) or 0
            S.configApplyFlagValue("terra_loot_min_coins", tostring(Loot.minCoins))
        end

        if type(payload.extras.upgradePriorities) == "table" then
            S.applyUpgradePrioritiesFromConfig(payload.extras.upgradePriorities)
        end
    end

    return true
end

function S.configSaveProfile(name)
    if not S.configHasFileApi() then
        return false, "Executor has no writefile support"
    end
    if not Rayfield or not Rayfield.Flags or not next(Rayfield.Flags) then
        return false, "UI flags not ready yet"
    end
    S.configEnsureFolder()

    local profileName = S.configSanitizeName(name or S.configGetSelectedName())
    local payload = S.configCapture()
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
    if not ok then
        return false, "Failed to encode config"
    end

    local writeOk, writeErr = pcall(writefile, S.configGetPath(profileName), encoded)
    if not writeOk then
        return false, tostring(writeErr)
    end

    Config.selectedName = profileName
    S.configAddToIndex(profileName)
    S.configRefreshDropdownOptions()
    return true
end

function S.configLoadProfile(name)
    if not S.configHasFileApi() then
        return false, "Executor has no readfile support"
    end
    if not Rayfield or not Rayfield.Flags or not next(Rayfield.Flags) then
        return false, "UI flags not ready yet"
    end

    local profileName = S.configSanitizeName(name or S.configGetSelectedName())
    local path = S.configGetPath(profileName)
    if typeof(isfile) == "function" and not isfile(path) then
        return false, "Config not found: " .. profileName
    end

    local readOk, raw = pcall(readfile, path)
    if not readOk then
        return false, tostring(raw)
    end

    local decodeOk, payload = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodeOk then
        return false, "Invalid config file"
    end

    local applyOk, applyErr = S.configApply(payload)
    if not applyOk then
        return false, applyErr
    end

    Config.selectedName = profileName
    S.configRefreshDropdownOptions()
    return true
end

function S.configDeleteProfile(name)
    if not S.configHasFileApi() then
        return false, "Executor has no file support"
    end

    local profileName = S.configSanitizeName(name or Config.selectedName)
    local path = S.configGetPath(profileName)

    if typeof(isfile) == "function" and not isfile(path) then
        return false, "Config not found: " .. profileName
    end

    if typeof(delfile) ~= "function" then
        return false, "Executor has no delfile support"
    end

    local delOk, delErr = pcall(delfile, path)
    if not delOk then
        return false, tostring(delErr)
    end

    S.configRemoveFromIndex(profileName)
    S.configRefreshDropdownOptions()
    return true
end

function S.configCreateProfile(name)
    local profileName = S.configSanitizeName(name or S.configGetInputName())
    Config.selectedName = profileName
    Config.newName = profileName
    local ok, err = S.configSaveProfile(profileName)
    if not ok then
        return false, err
    end
    S.configRefreshDropdownOptions()
    return true
end

function S.configSaveAutoloadSettings()
    if not S.configHasFileApi() then
        return
    end
    S.configEnsureFolder()
    local payload = {
        enabled = Config.autoloadEnabled,
        name = S.configSanitizeName(Config.autoloadName or S.configGetSelectedName()),
    }
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
    if ok then
        pcall(writefile, Config.autoloadFile, encoded)
    end
end

function S.configLoadAutoloadSettings()
    if not S.configHasFileApi() then
        return
    end
    if typeof(isfile) == "function" and not isfile(Config.autoloadFile) then
        return
    end

    local readOk, raw = pcall(readfile, Config.autoloadFile)
    if not readOk then
        return
    end

    local decodeOk, payload = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodeOk or type(payload) ~= "table" then
        return
    end

    Config.autoloadEnabled = payload.enabled == true
    Config.autoloadName = S.configSanitizeName(payload.name or "default")
end

function S.configSetAutoload(enabled)
    Config.autoloadEnabled = enabled
    if enabled then
        Config.autoloadName = S.configSanitizeName(S.configGetSelectedName())
    end
    S.configSaveAutoloadSettings()

    local flag = Rayfield and Rayfield.Flags and Rayfield.Flags["jpax_config_autoload"]
    if flag then
        flag.CurrentValue = Config.autoloadEnabled
        if flag.Set then
            pcall(function()
                flag:Set(Config.autoloadEnabled)
            end)
        end
    end
end

function S.configTryAutoload()
    S.configLoadAutoloadSettings()
    if not Config.autoloadEnabled then
        S.hubLog("Autoload OFF - starting with defaults")
        return
    end

    local target = S.configSanitizeName(Config.autoloadName or "default")
    if not S.configProfileExists(target) then
        S.hubLog("Autoload ON but profile missing: " .. target)
        S.notify("Config", "Autoload profile not found: " .. target .. " — using defaults", 5)
        return
    end

    task.delay(0.6, function()
        local ok, err = S.configLoadProfile(target)
        if ok then
            S.notify("Config", "Autoloaded: " .. target, 4)
        else
            S.notify("Config", "Autoload failed: " .. tostring(err), 5)
        end
    end)
end

function S.bindDepthReadout(kind, slider)
    if not slider then
        return
    end
    S._depthReadouts = S._depthReadouts or {}
    table.insert(S._depthReadouts, { kind = kind, slider = slider })
    if S._depthReadoutLoop then
        return
    end
    S._depthReadoutLoop = true
    task.spawn(function()
        while S._jpaxLibrary do
            pcall(function()
                local hud = S.readGameDepthTextMeters()
                local drillPos = select(1, S.getDepthWorldPosition())
                local drillM = tonumber(hud) or (drillPos and S.computeDepthMetersDump(drillPos)) or 0
                local root = S.getRoot()
                local you = root and S.computeDepthMetersDump(root.Position) or 0
                drillM = math.floor(drillM + 0.5)
                you = math.floor((you or 0) + 0.5)
                for _, rec in ipairs(S._depthReadouts or {}) do
                    local slider = rec.slider
                    local value = rec.kind == "you" and you or drillM
                    if slider and slider.Set then
                        slider:Set(value)
                    end
                end
            end)
            task.wait(0.35)
        end
        S._depthReadoutLoop = false
    end)
end

local LOBBY_PLACE = 101906032112547
local CORE_FILE = "jpax_dtec_core.json"

local LOBBY_CHEST_TIERS = { "Common", "Gold", "Diamond", "Void" }
local LOBBY_CHEST_KEYS = {
    Common = "CommonChest",
    Gold = "GoldChest",
    Diamond = "DiamondChest",
    Void = "VoidChest",
}

local LobbyChestWatch = {
    autoBuy = false,
    watchTiers = { "Diamond", "Void" },
    _shopGui = nil,
    _lastBuyAt = 0,
    _lastFindAt = 0,
    _lastUiText = "",
    _statusLabel = nil,
    snapshot = {
        open = false,
        timer = "—",
        focusTier = nil,
        focusStock = 0,
        tiers = {},
        buy1 = nil,
        buy10 = nil,
        tierButtons = {},
    },
}

for _, tier in ipairs(LOBBY_CHEST_TIERS) do
    LobbyChestWatch.snapshot.tiers[tier] = { stock = nil, out = "—" }
end

function S.lobbyChestNorm(text)
    if type(text) ~= "string" then
        return ""
    end
    return string.upper((text:gsub("%s+", " ")):match("^%s*(.-)%s*$") or "")
end

function S.lobbyChestGuiVisible(obj)
    local cur = obj
    while cur do
        if cur:IsA("ScreenGui") and cur.Enabled == false then
            return false
        end
        if cur:IsA("GuiObject") and cur.Visible == false then
            return false
        end
        cur = cur.Parent
    end
    return true
end

function S.lobbyChestExtractText(obj)
    if not obj then
        return nil
    end
    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        local t = obj.Text
        if type(t) == "string" and t ~= "" then
            return t
        end
    end
    return nil
end

function S.lobbyChestTierFromNorm(norm)
    if norm == "" then
        return nil
    end
    for _, tier in ipairs(LOBBY_CHEST_TIERS) do
        local key = string.upper(tier)
        if norm == key or norm:find(key .. " CHEST", 1, true) or norm:find("^" .. key .. " ", 1, true) then
            return tier
        end
    end
    return nil
end

function S.scoreLobbyChestShopGui(sg)
    if not sg or not sg:IsA("ScreenGui") or sg.Enabled == false then
        return 0
    end
    local score = 0
    local hasBuy1, hasBuy10, tierHits, hasStock, hasRestock = false, false, {}, false, false
    for _, desc in ipairs(sg:GetDescendants()) do
        if not S.lobbyChestGuiVisible(desc) then
            continue
        end
        local t = S.lobbyChestExtractText(desc)
        if not t then
            continue
        end
        local norm = S.lobbyChestNorm(t)
        if norm:find("RESTOCK IN", 1, true) or norm:find("CHESTS STOCK", 1, true) or norm:find("STOCK IN", 1, true) then
            hasRestock = true
        end
        if norm:find("BUY 1", 1, true) or norm == "BUY1" then
            hasBuy1 = true
        end
        if norm:find("BUY 10", 1, true) or norm:find("BUY10", 1, true) then
            hasBuy10 = true
        end
        local tier = S.lobbyChestTierFromNorm(norm)
        if tier then
            tierHits[tier] = true
        end
        if norm:find("NO STOCK", 1, true) or norm:find("LEFT", 1, true) then
            hasStock = true
        end
        if norm:find("^CHESTS$", 1, true) then
            score += 1
        end
    end
    if hasRestock then
        score += 3
    end
    if hasBuy1 then
        score += 2
    end
    if hasBuy10 then
        score += 2
    end
    if hasStock then
        score += 1
    end
    local tierCount = 0
    for _ in pairs(tierHits) do
        tierCount += 1
    end
    if tierCount >= 2 then
        score += 2
    elseif tierCount >= 1 then
        score += 1
    end
    return score
end

function S.findLobbyChestShopGui()
    local now = tick()
    local cached = LobbyChestWatch._shopGui
    if cached and cached.Parent and cached.Enabled ~= false and S.scoreLobbyChestShopGui(cached) >= 4 then
        return cached
    end
    if now - (LobbyChestWatch._lastFindAt or 0) < 2.5 then
        return nil
    end
    LobbyChestWatch._lastFindAt = now
    LobbyChestWatch._shopGui = nil

    local best, bestScore = nil, 0
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Enabled ~= false then
                local score = S.scoreLobbyChestShopGui(sg)
                if score > bestScore then
                    bestScore = score
                    best = sg
                end
            end
        end
    end
    if bestScore < 4 and pg then
        for _, inst in ipairs(pg:GetChildren()) do
            if inst:IsA("ScreenGui") then
                for _, child in ipairs(inst:GetDescendants()) do
                    if child:IsA("ScreenGui") and child.Enabled ~= false then
                        local score = S.scoreLobbyChestShopGui(child)
                        if score > bestScore then
                            bestScore = score
                            best = child
                        end
                    end
                end
            end
        end
    end
    if best and bestScore >= 4 then
        LobbyChestWatch._shopGui = best
        return best
    end
    return nil
end

function S.lobbyChestStockFromText(norm)
    if norm == "" then
        return nil
    end
    if norm:find("NO STOCK", 1, true) then
        return 0, "NO STOCK"
    end
    if norm:find("LEFT", 1, true) then
        local n = tonumber(norm:match("(%d+)"))
        if n then
            return n, tostring(n) .. " LEFT"
        end
    end
    return nil, nil
end

function S.lobbyChestStockNearTier(btn)
    if not btn or not btn.Parent then
        return nil, "—"
    end
    local root = btn.Parent
    for _ = 1, 3 do
        if not root then
            break
        end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("GuiObject") and d.Visible ~= false and (d:IsA("TextLabel") or d:IsA("TextButton")) then
                local stock, out = S.lobbyChestStockFromText(S.lobbyChestNorm(d.Text))
                if stock ~= nil then
                    return stock, out
                end
            end
        end
        root = root.Parent
    end
    return nil, "—"
end

function S.fireLobbyChestGuiButton(guiObj)
    if not guiObj or not guiObj:IsA("GuiButton") then
        return false
    end
    if guiObj.Activated and typeof(getconnections) == "function" then
        local ok, list = pcall(getconnections, guiObj.Activated)
        if ok and type(list) == "table" then
            for _, c in ipairs(list) do
                if type(c.Function) == "function" then
                    pcall(c.Function)
                    return true
                end
                if type(c.Fire) == "function" then
                    pcall(c.Fire, c)
                    return true
                end
            end
        end
    end
    if guiObj.Activated and typeof(firesignal) == "function" then
        local ok = pcall(firesignal, guiObj.Activated)
        if ok then
            return true
        end
    end
    pcall(function()
        guiObj:Activate()
    end)
    return true
end

function S.lobbyChestServiceFolder()
    local cached = LobbyChestWatch._svcFolder
    if cached and cached.Parent then
        return cached
    end
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then
        LobbyChestWatch._fail = "no Packages"
        return nil
    end
    local index = packages:FindFirstChild("_Index")
    if index then
        for _, pkg in ipairs(index:GetChildren()) do
            if string.find(string.lower(pkg.Name), "knit", 1, true) then
                local knitFolder = pkg:FindFirstChild("knit") or pkg:FindFirstChild("Knit")
                local services = knitFolder and knitFolder:FindFirstChild("Services")
                local svc = services and services:FindFirstChild("ArmoryChestService")
                if svc then
                    LobbyChestWatch._svcFolder = svc
                    LobbyChestWatch._fail = nil
                    return svc
                end
            end
        end
    end
    local now = tick()
    if now - (LobbyChestWatch._svcScanAt or 0) < 3 then
        return nil
    end
    LobbyChestWatch._svcScanAt = now
    for _, desc in ipairs(packages:GetDescendants()) do
        if desc.Name == "ArmoryChestService" and desc:FindFirstChild("RF") then
            LobbyChestWatch._svcFolder = desc
            LobbyChestWatch._fail = nil
            return desc
        end
    end
    LobbyChestWatch._fail = "no ArmoryChestService"
    return nil
end

function S.lobbyChestBindRemotes()
    if LobbyChestWatch._rfGet and LobbyChestWatch._rfGet.Parent then
        return LobbyChestWatch._rfGet
    end
    local svc = S.lobbyChestServiceFolder()
    if not svc then
        return nil
    end
    local rf = svc:FindFirstChild("RF")
    local re = svc:FindFirstChild("RE")
    LobbyChestWatch._rfGet = rf and rf:FindFirstChild("GetShopState")
    LobbyChestWatch._rfBuy = rf and rf:FindFirstChild("Purchase")
    if not LobbyChestWatch._rfGet then
        local names = {}
        if rf then
            for _, child in ipairs(rf:GetChildren()) do
                table.insert(names, child.Name)
                if #names >= 4 then
                    break
                end
            end
        end
        LobbyChestWatch._fail = #names > 0 and ("RF " .. table.concat(names, ",")) or "no RF"
    end
    local changed = re and re:FindFirstChild("ShopStateChanged")
    if changed and changed:IsA("RemoteEvent") and not LobbyChestWatch._stateHooked then
        LobbyChestWatch._stateHooked = true
        changed.OnClientEvent:Connect(function(state)
            if type(state) == "table" and type(state.Stock) == "table" then
                LobbyChestWatch._state = state
                LobbyChestWatch._stateAt = tick()
            end
        end)
    end
    return LobbyChestWatch._rfGet
end

function S.lobbyChestRememberState(state)
    if type(state) == "table" and type(state.Stock) == "table" then
        LobbyChestWatch._state = state
        LobbyChestWatch._stateAt = tick()
        return state
    end
    return nil
end

function S.refreshLobbyChestState()
    local now = tick()
    if LobbyChestWatch._state and now - (LobbyChestWatch._stateAt or 0) < 1.2 then
        return LobbyChestWatch._state
    end
    local rf = S.lobbyChestBindRemotes()
    if rf and rf:IsA("RemoteFunction") then
        local ok, state = pcall(function()
            return rf:InvokeServer()
        end)
        if ok and S.lobbyChestRememberState(state) then
            LobbyChestWatch._fail = nil
            return LobbyChestWatch._state
        end
        if not ok then
            LobbyChestWatch._fail = string.sub(tostring(state), 1, 42)
        end
    end
    local knit = S.getKnit()
    if knit and type(knit.GetController) == "function" then
        local ok, ctrl = pcall(function()
            return knit.GetController("ChestShopController")
        end)
        if ok and type(ctrl) == "table" and type(ctrl.Stock) == "table" then
            return S.lobbyChestRememberState({
                Stock = ctrl.Stock,
                ActiveChest = ctrl.SelectedChest or ctrl.ActiveChest,
                NextResetAt = ctrl.NextResetAt,
            })
        end
    end
    return LobbyChestWatch._state
end

function S.lobbyChestResetText(nextAt)
    local n = tonumber(nextAt)
    if not n then
        return "—"
    end
    local left = math.max(0, math.floor(n - workspace:GetServerTimeNow()))
    return string.format("%d:%02d", math.floor(left / 60), left % 60)
end

function S.applyLobbyChestStock(snap, tier, stock)
    stock = math.max(0, math.floor(tonumber(stock) or 0))
    snap.tiers[tier].stock = stock
    snap.tiers[tier].out = stock > 0 and (tostring(stock) .. " LEFT") or "NO STOCK"
end

function S.fillLobbyChestSnap(snap, stockMap, selectedKey, nextAt)
    snap.open = true
    snap.timer = S.lobbyChestResetText(nextAt)
    snap.focusTier = nil
    for tier, key in pairs(LOBBY_CHEST_KEYS) do
        S.applyLobbyChestStock(snap, tier, stockMap and stockMap[key])
        if selectedKey == key then
            snap.focusTier = tier
            snap.focusStock = snap.tiers[tier].stock or 0
            snap.focusStockOut = snap.tiers[tier].out
        end
    end
    if not snap.focusTier then
        for _, tier in ipairs(LOBBY_CHEST_TIERS) do
            if (snap.tiers[tier].stock or 0) > 0 then
                snap.focusTier = tier
                snap.focusStock = snap.tiers[tier].stock
                snap.focusStockOut = snap.tiers[tier].out
                break
            end
        end
    end
    return true
end

function S.scanLobbyChestShop()
    local snap = LobbyChestWatch.snapshot
    snap.open = false
    snap.timer = "—"
    snap.focusTier = nil
    snap.focusStock = 0
    snap.buy1 = nil
    snap.buy10 = nil
    snap.tierButtons = {}
    for _, tier in ipairs(LOBBY_CHEST_TIERS) do
        snap.tiers[tier].stock = nil
        snap.tiers[tier].out = "—"
    end

    local state = S.refreshLobbyChestState()
    if type(state) == "table" and type(state.Stock) == "table" then
        S.fillLobbyChestSnap(snap, state.Stock, state.ActiveChest, state.NextResetAt)
    end
    return snap
end

function S.formatLobbyChestWatchStatus(snap)
    snap = snap or LobbyChestWatch.snapshot
    if not snap.open then
        return LobbyChestWatch._fail or "syncing"
    end
    local parts = { "R:" .. tostring(snap.timer or "?") }
    for _, tier in ipairs(LOBBY_CHEST_TIERS) do
        local row = snap.tiers[tier]
        local ab = string.sub(tier, 1, 1)
        local out = row and row.out or "—"
        if type(out) == "string" and out:find("NO STOCK", 1, true) then
            out = "0"
        elseif type(out) == "string" and out:find("LEFT", 1, true) then
            out = (out:match("(%d+)") or "?") .. "L"
        end
        table.insert(parts, ab .. ":" .. tostring(out))
    end
    if snap.focusTier then
        table.insert(parts, ">>" .. snap.focusTier)
    end
    return table.concat(parts, " ")
end

function S.tryLobbyChestAutoBuy(snap)
    snap = snap or S.scanLobbyChestShop()
    if not snap.open or LobbyChestWatch.autoBuy ~= true then
        return
    end
    if tick() - (LobbyChestWatch._lastBuyAt or 0) < 1.25 then
        return
    end
    local watch = LobbyChestWatch.watchTiers
    if type(watch) ~= "table" or #watch == 0 then
        return
    end
    local rf = LobbyChestWatch._rfBuy
    if not (rf and rf.Parent) then
        S.lobbyChestBindRemotes()
        rf = LobbyChestWatch._rfBuy
    end
    if not rf or not rf:IsA("RemoteFunction") then
        return
    end
    for _, tier in ipairs(watch) do
        local row = snap.tiers[tier]
        local stock = row and row.stock
        local key = LOBBY_CHEST_KEYS[tier]
        if key and type(stock) == "number" and stock >= 1 then
            local amount = stock >= 10 and 10 or 1
            LobbyChestWatch._lastBuyAt = tick()
            task.spawn(function()
                local ok, result = pcall(function()
                    return rf:InvokeServer(key, amount)
                end)
                if ok and type(result) == "table" then
                    S.lobbyChestRememberState(result.State)
                end
            end)
            S.notify("Lobby Chest", string.format("Buy %d · %s (%s)", amount, tier, tostring(row.out)), 4)
            return
        end
    end
end

function S.tickLobbyChestWatch()
    local snap = S.scanLobbyChestShop()
    local line = S.formatLobbyChestWatchStatus(snap)
    if line ~= LobbyChestWatch._lastUiText then
        LobbyChestWatch._lastUiText = line
        if LobbyChestWatch._statusLabel and LobbyChestWatch._statusLabel.Set then
            pcall(function()
                LobbyChestWatch._statusLabel:Set(line)
            end)
        end
    end
    if LobbyChestWatch.autoBuy then
        S.tryLobbyChestAutoBuy(snap)
    end
end

function S.lobbyChestWatchListFromDropdown(options)
    if type(options) ~= "table" then
        return {}
    end
    local out = {}
    local seen = {}
    for _, v in ipairs(options) do
        if type(v) == "string" then
            for _, tier in ipairs(LOBBY_CHEST_TIERS) do
                if string.lower(v) == string.lower(tier) and not seen[tier] then
                    seen[tier] = true
                    table.insert(out, tier)
                end
            end
        end
    end
    return out
end

local coreChestDefaults = {}
for _, label in ipairs(CHEST_TYPE_OPTIONS) do
    coreChestDefaults[#coreChestDefaults + 1] = label
end

CoreFarm = {
    enabled = false,
    mode = "Unranked",
    partySize = 4,
    openAll = false,
    rescans = 2,
    joinDungeon = false,
    joinMines = false,
    chestTypes = coreChestDefaults,
    laps = 0,
    saveAtWell = false, -- Core: after the laps are done, TP to Church and save items at the Well
    _pendingWellSave = false,
}

-- Pending save survives the place teleport (map -> lobby) through CORE_FILE.
function S.coreWellLoadPending()
    if typeof(readfile) ~= "function" then
        return
    end
    if typeof(isfile) == "function" and not isfile(CORE_FILE) then
        return
    end
    local ok, raw = pcall(readfile, CORE_FILE)
    if not ok or type(raw) ~= "string" then
        return
    end
    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if okDecode and type(data) == "table" then
        CoreFarm.saveAtWell = data.saveAtWell == true
        CoreFarm._pendingWellSave = data.pendingWellSave == true
    end
end
pcall(S.coreWellLoadPending)

function S.coreTeleportService()
    local knit = S.getKnit()
    if not knit then
        return nil
    end
    local ok, svc = pcall(function()
        return knit.GetService("TeleportManagerService")
    end)
    if ok then
        return svc
    end
    return nil
end

function S.coreAwait(promise)
    if type(promise) ~= "table" then
        return promise
    end
    if type(promise.expect) == "function" then
        local ok, value = pcall(function()
            return promise:expect()
        end)
        if ok then
            return value
        end
    end
    if type(promise.await) == "function" then
        local ok, a, b = pcall(function()
            return promise:await()
        end)
        if ok then
            return b ~= nil and b or a
        end
    end
    return nil
end

function S.coreSaveQueue()
    if typeof(writefile) ~= "function" then
        return
    end
    local payload = {
        enabled = CoreFarm.enabled == true,
        mode = CoreFarm.mode == "Ranked" and "Ranked" or "Unranked",
        partySize = CoreFarm.partySize,
        rescans = CoreFarm.rescans,
        joinDungeon = CoreFarm.joinDungeon == true,
        joinMines = CoreFarm.joinMines == true,
        openAll = CoreFarm.openAll == true,
        chestTypes = CoreFarm.chestTypes,
        saveAtWell = CoreFarm.saveAtWell == true,
        pendingWellSave = CoreFarm._pendingWellSave == true,
    }
    pcall(writefile, CORE_FILE, HttpService:JSONEncode(payload))
end

function S.coreLoadQueue()
    if typeof(readfile) ~= "function" then
        return
    end
    if typeof(isfile) == "function" and not isfile(CORE_FILE) then
        return
    end
    local readOk, raw = pcall(readfile, CORE_FILE)
    if not readOk or type(raw) ~= "string" then
        return
    end
    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodeOk or type(data) ~= "table" then
        return
    end
    CoreFarm.enabled = data.enabled == true
    CoreFarm.mode = data.mode == "Ranked" and "Ranked" or "Unranked"
    CoreFarm.partySize = tonumber(data.partySize) or 4
    CoreFarm.rescans = tonumber(data.rescans) or 2
    CoreFarm.joinDungeon = data.joinDungeon == true
    CoreFarm.joinMines = data.joinMines == true
    if type(data.chestTypes) == "table" and #data.chestTypes > 0 then
        CoreFarm.chestTypes = data.chestTypes
    end
    CoreFarm.openAll = false
end

function S.coreZoneEmpty(zone)
    if typeof(zone) ~= "Instance" then
        return false
    end
    local count = tonumber(zone:GetAttribute("PlayerCount")) or 0
    local state = tonumber(zone:GetAttribute("State")) or 0
    return count < 1 and state <= 1
end

function S.coreFindZone()
    for _, inst in ipairs(CollectionService:GetTagged("PartyZone")) do
        if S.coreZoneEmpty(inst) then
            return inst
        end
    end
    return nil
end

function S.coreStandOn(zone)
    local root = S.getRoot()
    if not root or not zone then
        return
    end
    local cf = zone:IsA("BasePart") and zone.CFrame or zone:GetPivot()
    local lift = 4
    if zone:IsA("BasePart") then
        lift = zone.Size.Y * 0.5 + 2
    end
    root.CFrame = cf + Vector3.new(0, lift, 0)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

function S.corePartyIsLeaving()
    if game.PlaceId ~= LOBBY_PLACE then
        return false
    end
    local knit = S.getKnit()
    if not knit then
        return false
    end
    local ctrl
    pcall(function()
        ctrl = knit.GetController("PartyCreateController")
    end)
    local zone = ctrl and ctrl.Zone
    if not zone then
        return false
    end
    local state = tonumber(zone:GetAttribute("State")) or 0
    local teleportTime = tonumber(zone:GetAttribute("TeleportTime")) or 0
    return state > 1 or teleportTime ~= 0
end

function S.coreFinishStart(ok)
    CoreFarm._starting = false
    CoreFarm._partyStarted = ok == true
    return ok == true
end

function S.coreStartLobby()
    if CoreFarm._starting then
        return false
    end
    CoreFarm._starting = true
    if game.PlaceId ~= LOBBY_PLACE then
        S.notify("Lobby", "This only runs in the lobby", 4)
        return S.coreFinishStart(false)
    end
    local rootDeadline = os.clock() + 15
    while not S.getRoot() and os.clock() < rootDeadline do
        task.wait(0.25)
    end
    if not S.getRoot() then
        return S.coreFinishStart(false)
    end
    local saveWait = os.clock() + 60
    while (CoreFarm._wellSaving or (CoreFarm.saveAtWell and CoreFarm._pendingWellSave)) and os.clock() < saveWait do
        task.wait(0.5)
    end
    local svc = S.coreTeleportService()
    local tagged = CollectionService:GetTagged("PartyZone")
    if not svc or #tagged == 0 then
        if os.clock() - (CoreFarm._waitNote or 0) > 8 then
            CoreFarm._waitNote = os.clock()
            S.notify("Lobby", "Waiting for party pads to load.", 4)
        end
        return S.coreFinishStart(false)
    end
    local zone = S.coreFindZone()
    if not zone or not S.coreZoneEmpty(zone) then
        if os.clock() - (CoreFarm._waitNote or 0) > 8 then
            CoreFarm._waitNote = os.clock()
            S.notify("Lobby", "Pads are full. Waiting for an empty one.", 4)
        end
        return S.coreFinishStart(false)
    end
    local knit = S.getKnit()
    local ctrl = nil
    if knit then
        pcall(function()
            ctrl = knit.GetController("PartyCreateController")
        end)
    end
    local claimed = false
    for _ = 1, 5 do
        if not S.coreZoneEmpty(zone) and (tonumber(zone:GetAttribute("PlayerCount")) or 0) > 1 then
            break
        end
        S.coreStandOn(zone)
        task.wait(0.2)
        pcall(function()
            S.coreAwait(svc:TouchedZone(zone))
        end)
        task.wait(0.35)
        local count = tonumber(zone:GetAttribute("PlayerCount")) or 0
        if ctrl and ctrl.Zone == zone then
            claimed = true
            break
        end
        if count == 1 then
            claimed = true
            break
        end
        if count > 1 then
            break
        end
    end
    if not claimed or (ctrl and ctrl.Zone and ctrl.Zone ~= zone) then
        if ctrl and ctrl.Zone and ctrl.Zone ~= zone then
            pcall(function()
                svc:ExitZone(ctrl.Zone)
            end)
        end
        return S.coreFinishStart(false)
    end
    local countNow = tonumber(zone:GetAttribute("PlayerCount")) or 0
    if countNow > 1 then
        pcall(function()
            svc:ExitZone(zone)
        end)
        return S.coreFinishStart(false)
    end
    local modeName = CoreFarm.mode == "Ranked" and "Ranked" or "Unranked"
    local size = math.clamp(math.floor(tonumber(CoreFarm.partySize) or 4), 1, 8)
    if ctrl and ctrl.Zone == zone and ctrl.CreateUI and ctrl.CreateUI.MapSelect then
        pcall(function()
            ctrl:UpdatePlayerCount(size)
        end)
        local button = ctrl.CreateUI.MapSelect:FindFirstChild(modeName)
        if button then
            ctrl.SelectedMapButton = button
            pcall(function()
                ctrl:UpdateMapSelection()
            end)
        end
        pcall(function()
            ctrl:StartParty()
        end)
    else
        local ranked = modeName == "Ranked"
        local ok, promise = pcall(function()
            return svc:CreatedZone(zone, size, "Earth", ranked)
        end)
        if not ok or S.coreAwait(promise) == false then
            pcall(function()
                svc:ExitZone(zone)
            end)
            return S.coreFinishStart(false)
        end
    end
    S.notify("Lobby", modeName .. " · party " .. size, 4)
    return S.coreFinishStart(true)
end

function S.coreChestsOnly()
    return type(CoreFarm) == "table" and CoreFarm._ownedRun == true
end

function S.coreAutoChestOn()
    return Autofarm.openChests == true or (type(CoreFarm) == "table" and (CoreFarm.openAll == true or CoreFarm._ownedRun == true))
end

function S.coreSkipCutscene()
    if not S.coreAutoChestOn() then
        return
    end
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local skip = gui and gui:FindFirstChild("CutSceneUI") and gui.CutSceneUI:FindFirstChild("Skip")
    local showing = skip and skip.Visible == true
    if workspace:GetAttribute("InCutScene") ~= true and not showing then
        return
    end
    local knit = S.getKnit()
    if not knit then
        return
    end
    local ctrl, svc
    pcall(function()
        ctrl = knit.GetController("CutSceneController")
    end)
    pcall(function()
        svc = knit.GetService("CutSceneService")
    end)
    local scene = ctrl and ctrl.CurrentCutScene
    if not scene then
        return
    end
    local now = os.clock()
    if CoreFarm._skippedScene == scene and now - (CoreFarm._skippedAt or 0) < 0.4 then
        return
    end
    if CoreFarm._skippedScene == scene and workspace:GetAttribute("InCutScene") == true and now - (CoreFarm._skippedAt or 0) >= 0.45 then
        if ctrl.AbortCutScene then
            pcall(function()
                ctrl:AbortCutScene()
            end)
        end
        CoreFarm._skippedAt = now
        return
    end
    CoreFarm._skippedScene = scene
    CoreFarm._skippedAt = now
    local ctx = ctrl.CurrentCutSceneContext
    if svc then
        if ctx and ctx.Private and ctx.RuntimeId ~= nil then
            pcall(function()
                svc:VoteSkipPrivate(ctx.RuntimeId, scene)
            end)
        else
            pcall(function()
                svc:VoteSkip(scene)
            end)
        end
    end
end

function S.coreRefreshChestPick()
    local flags = Rayfield and Rayfield.Flags
    local types = flags and flags.dtec_core_chest_types
    local raw = types and ((types._obsidian and types._obsidian.Value) or types.CurrentValue)
    local picked = S.chestSelectionList(raw)
    if #picked == 0 then
        picked = S.chestSelectionList(CoreFarm._chestPick)
    end
    if #picked == 0 then
        picked = S.chestSelectionList(CoreFarm.chestTypes)
    end
    if #picked > 0 then
        CoreFarm._chestPick = picked
    end
    return picked
end

function S.coreHoldChestRun()
    if not (CoreFarm.openAll or CoreFarm._ownedRun) or CoreFarm._leaving then
        return
    end
    local picked = S.coreRefreshChestPick()
    if #picked == 0 then
        return
    end
    CoreFarm.chestTypes = picked
    CoreFarm._chestPick = picked
    Autofarm.chestTypes = picked
    Autofarm.openChests = true
    Autofarm.enterMines = false
    Autofarm.enterDungeons = false
    Autofarm.oreUnderEnabled = false
    Autofarm.autoSell = false
end

function S.corePlayerReady()
    if not S._bootAt then
        S._bootAt = os.clock()
    end
    if S._knitReady ~= true and os.clock() - S._bootAt < 15 then
        return false
    end
    if workspace:GetAttribute("InCutScene") == true then
        return false
    end
    local player = LocalPlayer or Players.LocalPlayer
    local char = player and player.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    if not root or not char:FindFirstChildOfClass("Humanoid") then
        CoreFarm._rootSeenAt = nil
        return false
    end
    if char:FindFirstChildOfClass("ForceField") then
        CoreFarm._rootSeenAt = nil
        return false
    end
    if not CoreFarm._rootSeenAt then
        CoreFarm._rootSeenAt = os.clock()
        return false
    end
    return os.clock() - CoreFarm._rootSeenAt >= 1
end

function S.stopCoreChestRun()
    if CoreFarm._stopping then
        return
    end
    CoreFarm._stopping = true
    CoreFarm._userStop = true
    CoreFarm._applyGen = (CoreFarm._applyGen or 0) + 1
    CoreFarm.openAll = false
    CoreFarm._ownedRun = false
    CoreFarm._runStarted = false
    CoreFarm._applying = false
    CoreFarm._leaving = false
    Autofarm.openChests = false
    if game.PlaceId == JPAX.placeId then
        S.setAutofarm(false)
        S.trySetRayfieldFlag("terra_autofarm", false)
    end
    S.trySetRayfieldFlag("dtec_core_open", false)
    S.coreSaveQueue()
    CoreFarm._stopping = false
end

function S.coreApplyRun()
    if CoreFarm._userStop or CoreFarm._applying then
        return
    end
    if CoreFarm._leaving and os.clock() - (CoreFarm._leavingAt or 0) < 240 then
        return
    end
    CoreFarm._applying = true
    CoreFarm._applySince = os.clock()
    local gen = CoreFarm._applyGen or 0
    local function stillThisRun()
        return not CoreFarm._userStop and gen == (CoreFarm._applyGen or 0) and CoreFarm.openAll == true
    end
    local rootDeadline = os.clock() + 20
    while not S.getRoot() and os.clock() < rootDeadline do
        if not stillThisRun() then
            CoreFarm._applying = false
            return
        end
        task.wait(0.5)
    end
    if not stillThisRun() then
        CoreFarm._applying = false
        return
    end
    if not S.getRoot() then
        CoreFarm._applying = false
        CoreFarm._runStarted = false
        return
    end
    local picked = S.coreRefreshChestPick()
    if #picked == 0 then
        picked = {}
        for _, label in ipairs(CHEST_TYPE_OPTIONS) do
            picked[#picked + 1] = label
        end
    end
    CoreFarm.chestTypes = picked
    CoreFarm._chestPick = picked
    CoreFarm._ownedRun = true
    Autofarm.chestTypes = picked
    Autofarm.openChests = true
    Autofarm.enterMines = false
    Autofarm.enterDungeons = false
    Autofarm.oreUnderEnabled = false
    Autofarm.autoSell = false
    S.setAutoLoot(false)
    S.trySetRayfieldFlag("terra_auto_loot", false)
    S.trySetRayfieldFlag("terra_af_auto_ores", false)
    S.trySetRayfieldFlag("terra_af_auto_chests", true)
    S.trySetRayfieldFlag("terra_af_chest_types", S.chestLabelsFromSaved(Autofarm.chestTypes))
    CoreFarm.laps = 0
    CoreFarm._leaving = false
    CoreFarm._lapLock = 0
    CoreFarm._coresBefore = tonumber(LocalPlayer:GetAttribute("Cores")) or 0
    if not stillThisRun() then
        CoreFarm._applying = false
        return
    end
    S.setAutofarm(true)
    if not Autofarm.enabled or not Autofarm.origin then
        CoreFarm._runStarted = false
        CoreFarm._applying = false
        Autofarm._dbgErr = "no root"
        return
    end
    Autofarm._dbgErr = nil
    CoreFarm._runStarted = true
    CoreFarm._stuckAt = nil
    S.trySetRayfieldFlag("terra_autofarm", true)
    local need = math.clamp(math.floor(tonumber(CoreFarm.rescans) or 2), 1, 10)
    S.notify("Core", "Run on · auto chests · " .. need .. " map ends", 4)
    CoreFarm._applying = false
end

function S.coreUnstickRun()
    if not (CoreFarm.openAll and CoreFarm._ownedRun) or CoreFarm._leaving or CoreFarm._applying then
        return
    end
    if workspace:GetAttribute("InCutScene") == true then
        return
    end
    local root = S.getRoot()
    if not root then
        return
    end
    if not Autofarm.enabled or not State.connections.autofarm or not State.connections.autofarmGlide then
        CoreFarm._stuckAt = nil
        if not Autofarm.enabled or not State.connections.autofarm then
            S.setAutofarm(true)
        else
            S.ensureAutofarmOrigin(true)
            S.startJpaxRouteGlide()
            S.lockAutofarmHover(true)
        end
        return
    end
    if Autofarm.moving or (Autofarm.busy and Autofarm._holdReason == "chest") then
        CoreFarm._stuckAt = nil
        return
    end
    local pos = root.Position
    local stamp = CoreFarm._stuckAt
    if type(stamp) ~= "table" then
        CoreFarm._stuckAt = { x = pos.X, z = pos.Z, at = os.clock() }
        return
    end
    local moved = (Vector3.new(pos.X - stamp.x, 0, pos.Z - stamp.z)).Magnitude
    if moved > 12 then
        CoreFarm._stuckAt = { x = pos.X, z = pos.Z, at = os.clock() }
        return
    end
    if os.clock() - (stamp.at or 0) < 4 then
        return
    end
    CoreFarm._stuckAt = { x = pos.X, z = pos.Z, at = os.clock() }
    S.clearMineHoldPin()
    Autofarm._gatePinY = nil
    Autofarm.busy = false
    Autofarm.moving = false
    Autofarm._cycleRunning = false
    if (Autofarm.distance or 0) < 40 then
        S.setAutofarm(true)
        return
    end
    S.ensureAutofarmOrigin(not Autofarm.origin)
    S.startJpaxRouteGlide()
    S.setAutofarmPose(Autofarm.distance or 0)
    S.lockAutofarmHover(true)
end

function S.coreSyncFlags()
    local flags = Rayfield and Rayfield.Flags
    if type(flags) ~= "table" then
        return
    end
    local function setFlag(name, value)
        local flag = flags[name]
        if flag and flag.Set then
            pcall(function()
                flag:Set(value)
            end)
        end
    end
    setFlag("dtec_lobby_auto", CoreFarm.enabled == true)
    setFlag("dtec_lobby_mode", CoreFarm.mode)
    setFlag("dtec_lobby_size", CoreFarm.partySize)
    setFlag("dtec_core_open", CoreFarm.openAll == true)
    setFlag("dtec_core_save_well", CoreFarm.saveAtWell == true)
    setFlag("dtec_core_rescan", CoreFarm.rescans)
    setFlag("dtec_core_dungeon", CoreFarm.joinDungeon == true)
    setFlag("dtec_core_mines", CoreFarm.joinMines == true)
    setFlag("dtec_core_chest_types", CoreFarm.chestTypes)
end

function S.coreNoteLap()
    if not (CoreFarm.openAll or CoreFarm._ownedRun) or CoreFarm._leaving then
        return
    end
    local now = os.clock()
    if now - (CoreFarm._lapLock or 0) < 3 then
        return
    end
    CoreFarm._lapLock = now
    CoreFarm.laps = (CoreFarm.laps or 0) + 1
    local need = math.clamp(math.floor(tonumber(CoreFarm.rescans) or 2), 1, 10)
    S.notify("Core", "Lap " .. CoreFarm.laps .. "/" .. need, 4)
    if CoreFarm.laps < need then
        return
    end
    CoreFarm._leaving = true
    CoreFarm._leavingAt = os.clock()
    CoreFarm.openAll = false
    -- Auto Chest mati sekarang juga (tidak ada detour chest lagi menuju Church / Altar).
    Autofarm.openChests = false
    Autofarm.suppressChestOreStopUntil = tick() + 600
    S.trySetRayfieldFlag("terra_af_auto_chests", false)
    local before = CoreFarm._coresBefore
    task.spawn(function()
        if CoreFarm.saveAtWell then
            -- Mark pending first: if the Church/Well are not in this map, the lobby finishes the job.
            CoreFarm._pendingWellSave = true
            S.coreSaveQueue()
            S.notify("Core", "Laps done — flying on until the Church, then saving at the Altar", 5)
            local done = false
            pcall(function()
                done = S.coreFlyToChurchAndSave()
            end)
            if done then
                CoreFarm._pendingWellSave = false
                S.coreSaveQueue()
            end
        else
            S.coreHardStopFlying()
        end
        -- Fallback only: the Well normally teleports the player to the lobby by itself.
        S.coreReturnLobby(before)
    end)
end

-- Fully stop the farm flight (glide, hover lock, platform stand, noclip, manual fly).
function S.coreHardStopFlying()
    pcall(S.setAutofarm, false, { skipReturn = true })
    pcall(S.forceReleaseFarmCharacter)
    if State.fly then
        pcall(S.setFly, false)
    end
    local root = S.getRoot()
    if root then
        pcall(function()
            root.Anchored = false
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

-- ===== Save items at the Well (Church) =====
S.CHURCH_KEYS = { "church", "chapel", "gereja", "cathedral", "shrine", "sanctuary" }
S.WELL_KEYS = { "altar", "well", "sumur" }
S.WELL_SAVE_WORDS = { "save", "store", "deposit", "stash", "simpan", "throw", "toss", "donate", "well", "altar", "pray", "return", "lobby" }

function S.coreNameHasKey(name, keys)
    local n = string.lower(tostring(name or ""))
    for _, key in ipairs(keys) do
        if #key >= 5 and n:find(key, 1, true) then
            return true
        end
        if n == key
            or n:sub(1, #key) == key
            or n:sub(-#key) == key
            or n:find("[^%a]" .. key) ~= nil
        then
            return true
        end
    end
    return false
end

function S.coreInstDepth(inst)
    local d, p = 0, inst.Parent
    while p do
        d = d + 1
        p = p.Parent
    end
    return d
end

-- One pass over Workspace: Church candidates, Well candidates and every ProximityPrompt.
function S.coreScanWorld()
    local churches, wells, prompts = {}, {}, {}
    local n = 0
    for _, inst in ipairs(Workspace:GetDescendants()) do
        n = n + 1
        if n % 3000 == 0 then
            task.wait()
        end
        if inst:IsA("ProximityPrompt") then
            prompts[#prompts + 1] = inst
        elseif inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Folder") then
            if S.coreNameHasKey(inst.Name, S.CHURCH_KEYS) then
                churches[#churches + 1] = inst
            elseif S.coreNameHasKey(inst.Name, S.WELL_KEYS) then
                wells[#wells + 1] = inst
            end
        end
    end
    return churches, wells, prompts
end

function S.corePickChurch(churches)
    local best, bestScore, bestPos
    for _, inst in ipairs(churches) do
        local pos = S.getInstancePosition(inst)
        if pos then
            local score = (inst:IsA("Model") and 100 or 0) - S.coreInstDepth(inst)
            if not bestScore or score > bestScore then
                best, bestScore, bestPos = inst, score, pos
            end
        end
    end
    return best, bestPos
end

function S.corePickSavePrompt(list)
    local fallback
    for _, prompt in ipairs(list) do
        if prompt.Enabled then
            fallback = fallback or prompt
            local text = S.promptActionLower(prompt)
            for _, word in ipairs(S.WELL_SAVE_WORDS) do
                if text:find(word, 1, true) then
                    return prompt
                end
            end
        end
    end
    return fallback
end

function S.corePickWell(wells, prompts, nearPos)
    local best, bestScore, bestPrompt, bestPos
    for _, inst in ipairs(wells) do
        local pos = S.getInstancePosition(inst)
        if pos then
            local own = S.collectProximityPrompts(inst)
            if #own == 0 then
                for _, prompt in ipairs(prompts) do
                    if prompt.Enabled then
                        local pp = S.getPromptWorldPosition(prompt)
                        if pp and (pp - pos).Magnitude <= 25 then
                            own[#own + 1] = prompt
                        end
                    end
                end
            end
            local prompt = S.corePickSavePrompt(own)
            local score = (prompt and 1000 or 0) + (inst:IsA("Model") and 50 or 0) - S.coreInstDepth(inst)
            if string.find(string.lower(inst.Name), "altar", 1, true) then
                score = score + 200
            end
            if nearPos then
                score = score - (pos - nearPos).Magnitude * 0.05
            end
            if not bestScore or score > bestScore then
                best, bestScore, bestPrompt, bestPos = inst, score, prompt, pos
            end
        end
    end
    return best, bestPrompt, bestPos
end

-- Where to stand on the Altar when no ProximityPrompt exists yet (the prompt may only appear
-- once the player is inside the altar circle): prefer a circle/zone part, else the altar's floor.
function S.coreAltarStandPos(inst)
    local zoneWords = { "circle", "zone", "ring", "hitbox", "area", "trigger", "save", "platform" }
    local part
    if inst:IsA("BasePart") then
        part = inst
    else
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then
                local n = string.lower(d.Name)
                for _, w in ipairs(zoneWords) do
                    if n:find(w, 1, true) then
                        part = d
                        break
                    end
                end
            end
            if part then
                break
            end
        end
    end
    if part then
        return Vector3.new(part.Position.X, part.Position.Y + part.Size.Y / 2 + 3, part.Position.Z)
    end
    if inst:IsA("Model") then
        local ok, cf, size = pcall(inst.GetBoundingBox, inst)
        if ok and cf and size then
            return Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2 + 4, cf.Position.Z)
        end
    end
    local pos = S.getInstancePosition(inst)
    return pos and (pos + Vector3.new(0, 4, 0)) or nil
end

-- After landing on the altar, wait for a prompt to show up (own descendants first, then any near us).
function S.coreWaitAltarPrompt(well, seconds)
    local deadline = os.clock() + (seconds or 3)
    repeat
        local found = S.corePickSavePrompt(S.collectProximityPrompts(well))
        if found then
            return found
        end
        local root = S.getRoot()
        if root then
            local near = {}
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("ProximityPrompt") and d.Enabled then
                    local pp = S.getPromptWorldPosition(d)
                    if pp and (pp - root.Position).Magnitude <= 20 then
                        near[#near + 1] = d
                    end
                end
            end
            found = S.corePickSavePrompt(near)
            if found then
                return found
            end
        end
        task.wait(0.5)
    until os.clock() >= deadline
    return nil
end

function S.coreGoNear(pos, lift)
    local root = S.getRoot()
    if not root or not pos then
        return false
    end
    pcall(function()
        S.requestStreamAround(pos, 1.5)
    end)
    root.CFrame = CFrame.new(pos.X, pos.Y + (lift or 6), pos.Z)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end

-- ===== Altar options popup: auto-click the "go to lobby" choice =====
S.WELL_OPTION_POS = {
    { "lobby", 10 }, { "teleport", 6 }, { "return", 5 }, { "leave", 5 },
    { "exit", 4 }, { "quit", 3 }, { "save", 3 }, { "confirm", 2 }, { "yes", 2 }, { "go", 1 },
}
S.WELL_OPTION_NEG = {
    { "cancel", 10 }, { "stay", 10 }, { "continue", 8 }, { "resume", 8 },
    { "close", 8 }, { "keep", 6 }, { "later", 6 },
}

function S.coreGuiShown(obj)
    local cur = obj
    while cur and cur ~= game do
        if cur:IsA("GuiObject") and cur.Visible == false then
            return false
        end
        if cur:IsA("ScreenGui") and cur.Enabled == false then
            return false
        end
        cur = cur.Parent
    end
    return obj.AbsoluteSize.X > 0 and obj.AbsoluteSize.Y > 0
end

function S.coreGuiButtonText(btn)
    local parts = {}
    if btn:IsA("TextButton") then
        parts[#parts + 1] = btn.Text
    end
    for _, d in ipairs(btn:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            parts[#parts + 1] = d.Text
        end
    end
    parts[#parts + 1] = btn.Name
    local text = string.lower(table.concat(parts, " "))
    return (text:gsub("<[^>]+>", ""))
end

function S.coreOptionScore(text)
    local score = 0
    for _, entry in ipairs(S.WELL_OPTION_POS) do
        if text:find(entry[1], 1, true) then
            score = score + entry[2]
        end
    end
    for _, entry in ipairs(S.WELL_OPTION_NEG) do
        if text:find(entry[1], 1, true) then
            score = score - entry[2]
        end
    end
    local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "no" then
        score = score - 10
    end
    return score
end

function S.coreSnapshotButtons()
    local snap = {}
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("GuiButton") and S.coreGuiShown(d) then
                snap[d] = true
            end
        end
    end
    return snap
end

function S.coreFindLobbyOption(baseline, onlyNew, minScore)
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then
        return nil
    end
    local best, bestScore, bestText
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("GuiButton") and not (onlyNew and baseline and baseline[d]) and S.coreGuiShown(d) then
            local text = S.coreGuiButtonText(d)
            local score = S.coreOptionScore(text)
            if score >= minScore and (not bestScore or score > bestScore) then
                best, bestScore, bestText = d, score, text
            end
        end
    end
    return best, bestText, bestScore
end

function S.coreClickGuiButton(btn)
    local fired = false
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local inset = game:GetService("GuiService"):GetGuiInset()
        local sg = btn:FindFirstAncestorOfClass("ScreenGui")
        local yOff = (sg and sg.IgnoreGuiInset) and 0 or inset.Y
        local pos = btn.AbsolutePosition + btn.AbsoluteSize / 2
        vim:SendMouseButtonEvent(pos.X, pos.Y + yOff, 0, true, game, 0)
        task.wait(0.06)
        vim:SendMouseButtonEvent(pos.X, pos.Y + yOff, 0, false, game, 0)
        fired = true
    end)
    if typeof(getconnections) == "function" then
        for _, name in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" }) do
            pcall(function()
                for _, c in ipairs(getconnections(btn[name])) do
                    if type(c.Fire) == "function" then
                        c:Fire()
                        fired = true
                    elseif type(c.Function) == "function" then
                        task.spawn(c.Function)
                        fired = true
                    end
                end
            end)
        end
    end
    return fired
end

-- Waits for the 2-option popup that appears after holding E on the altar, then clicks the
-- option that sends the player to the lobby. A second confirm popup is handled too.
function S.coreClickLobbyOption(baseline, seconds)
    local clickedAny = false
    local deadline = os.clock() + (tonumber(seconds) or 10)
    local started = os.clock()
    while os.clock() < deadline do
        local btn, text, score = S.coreFindLobbyOption(baseline, true, 3)
        if not btn and os.clock() - started > 4 then
            -- Popup may have been visible before we looked: only accept a clear "lobby" button.
            btn, text, score = S.coreFindLobbyOption(baseline, false, 8)
        end
        if btn then
            print("[Core] Clicking option:", btn:GetFullName(), "| text:", text, "| score:", score)
            S.coreClickGuiButton(btn)
            clickedAny = true
            baseline = S.coreSnapshotButtons()
            baseline[btn] = nil
            task.wait(1.5)
            deadline = math.min(deadline, os.clock() + 4)
            if deadline < os.clock() + 2.5 then
                deadline = os.clock() + 2.5
            end
        else
            task.wait(0.2)
        end
    end
    return clickedAny
end

-- Same hold method the chest opener uses: InputHoldBegin + real E key + camera on the prompt.
-- prompt may be nil (altar without a ProximityPrompt): then only the real E key is held.
function S.coreHoldWellPrompt(prompt, lookAt)
    local hold = prompt and (tonumber(prompt.HoldDuration) or 0) or 3
    local seconds = math.max(hold, 0.3) + 1.0
    local lookPos = (prompt and S.getPromptWorldPosition(prompt)) or lookAt
    local backup = prompt and S.preparePromptsForHold({ prompt }) or nil
    local camBackup = nil
    if lookPos then
        S.faceCharacterToward(lookPos)
        camBackup = S.aimCameraAtWorld(lookPos, nil)
    end
    local vim
    pcall(function()
        vim = game:GetService("VirtualInputManager")
    end)
    local key = Enum.KeyCode.E
    pcall(function()
        if prompt and prompt.KeyboardKeyCode ~= Enum.KeyCode.Unknown then
            key = prompt.KeyboardKeyCode
        end
    end)
    task.wait(0.1)
    if prompt then
        pcall(function()
            prompt:InputHoldBegin()
        end)
    end
    pcall(function()
        if vim then
            vim:SendKeyEvent(true, key, false, game)
        end
    end)
    local deadline = os.clock() + seconds
    while os.clock() < deadline do
        if prompt and not prompt.Parent then
            break
        end
        if lookPos then
            S.faceCharacterToward(lookPos)
            camBackup = S.aimCameraAtWorld(lookPos, camBackup)
        end
        task.wait(0.05)
    end
    if prompt then
        pcall(function()
            prompt:InputHoldEnd()
        end)
    end
    pcall(function()
        if vim then
            vim:SendKeyEvent(false, key, false, game)
        end
    end)
    if backup then
        S.restorePromptsAfterHold(backup)
    end
    S.restoreCameraAim(camBackup)
    return true
end

-- Church first (streams the area in), then the Altar/Well inside it, then hold E on it.
-- Returns true only if the game teleported us away (prompt gone) after holding E.
function S.coreChurchWellSave(searchSeconds, allowWellOnly)
    local deadline = os.clock() + (tonumber(searchSeconds) or 6)
    local church, churchPos, well, prompt, wellPos
    repeat
        local churches, wells, prompts = S.coreScanWorld()
        church, churchPos = S.corePickChurch(churches)
        if church then
            S.coreGoNear(churchPos, 8)
            task.wait(1.2)
            churches, wells, prompts = S.coreScanWorld()
        end
        well, prompt, wellPos = S.corePickWell(wells, prompts, churchPos)
        if well and (church or allowWellOnly) then
            break
        end
        well, prompt = nil, nil
        task.wait(1)
    until os.clock() >= deadline

    if not well then
        return false
    end
    print("[Core] Church:", church and church:GetFullName() or "none", "| Altar/Well:", well:GetFullName(),
        "| Prompt:", prompt and prompt:GetFullName() or "none yet")

    local function standPos()
        local pp = prompt and S.getPromptWorldPosition(prompt)
        if pp then
            return Vector3.new(pp.X, pp.Y + 3, pp.Z)
        end
        return S.coreAltarStandPos(well)
    end

    local target = standPos()
    if not S.getRoot() or not target then
        return false
    end

    -- The altar saves the run AND sends the player back to the lobby, so this script may die
    -- mid-teleport. Clear the pending flag now so the lobby does not repeat the search.
    CoreFarm._pendingWellSave = false
    S.coreSaveQueue()
    S.notify("Core", "At the Altar — holding E to save and return to lobby", 5)

    local sentToLobby = false
    for attempt = 1, 3 do
        local root = S.getRoot()
        if not root then
            break
        end
        target = standPos() or target
        pcall(function()
            S.requestStreamAround(target, 1.2)
        end)
        pcall(function()
            root.Anchored = false
        end)
        root.CFrame = CFrame.new(target)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.3)
        pcall(function()
            root.Anchored = true
        end)

        -- Inside the altar circle the prompt may only appear now.
        if not (prompt and prompt.Parent and prompt.Enabled) then
            prompt = S.coreWaitAltarPrompt(well, 3)
        end
        task.wait(0.2)

        local baseline = S.coreSnapshotButtons()
        S.coreHoldWellPrompt(prompt, wellPos)

        -- After E the altar shows 2 options: auto-pick the one that goes to the lobby.
        local clicked = S.coreClickLobbyOption(baseline, 10)
        if clicked then
            S.notify("Core", "Lobby option clicked — waiting for teleport", 4)
        end

        local waitUntil = os.clock() + (clicked and 15 or 8)
        while os.clock() < waitUntil do
            task.wait(0.25)
        end
        if clicked or (prompt and not prompt.Parent) then
            sentToLobby = true
            break
        end
    end

    local root = S.getRoot()
    if root then
        pcall(function()
            root.Anchored = false
        end)
    end
    return sentToLobby
end

-- Church / Altar only exist in Workspace while streamed in, and the farm glide is far too fast for a
-- periodic scan to catch them. So a Workspace.DescendantAdded watcher remembers the position the
-- moment they stream in (during the whole run). After the last lap we stop and teleport there.
S.CHURCH_STOP_RANGE = 700

function S.coreRememberChurch(inst)
    if not (inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Folder")) then
        return
    end
    local isChurch = S.coreNameHasKey(inst.Name, S.CHURCH_KEYS)
    local isAltar = (not isChurch) and S.coreNameHasKey(inst.Name, S.WELL_KEYS)
    if not (isChurch or isAltar) then
        return
    end
    local seen = CoreFarm._churchSeen
    if seen and seen.inst and seen.inst.Parent and (seen.isChurch or not isChurch) then
        return
    end
    task.spawn(function()
        local pos
        for _ = 1, 8 do
            pos = inst.Parent and S.getInstancePosition(inst)
            if pos then
                break
            end
            task.wait(0.25)
        end
        if not pos then
            return
        end
        local cur = CoreFarm._churchSeen
        if cur and cur.inst and cur.inst.Parent and (cur.isChurch or not isChurch) then
            return
        end
        CoreFarm._churchSeen = { inst = inst, pos = pos, isChurch = isChurch }
        print("[Core] Seen", isChurch and "Church:" or "Altar:", inst:GetFullName(), pos)
    end)
end

function S.coreStartChurchWatch()
    S.disconnectAll("coreChurch")
    State.connections.coreChurch = Workspace.DescendantAdded:Connect(function(inst)
        pcall(S.coreRememberChurch, inst)
    end)
    local n = 0
    for _, inst in ipairs(Workspace:GetDescendants()) do
        n = n + 1
        if n % 3000 == 0 then
            task.wait()
        end
        pcall(S.coreRememberChurch, inst)
    end
end

-- Prints everything that looks like a church / altar so the exact names can be checked in F9.
function S.coreDumpChurchCandidates()
    local words = { "church", "chapel", "altar", "cathedral", "shrine", "temple", "sanct", "well", "pray", "gereja" }
    local out, n = {}, 0
    for _, inst in ipairs(Workspace:GetDescendants()) do
        n = n + 1
        if n % 3000 == 0 then
            task.wait()
        end
        if inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Folder") or inst:IsA("ProximityPrompt") then
            local low = string.lower(inst.Name)
            for _, w in ipairs(words) do
                if low:find(w, 1, true) then
                    out[#out + 1] = inst:GetFullName() .. " [" .. inst.ClassName .. "]"
                    break
                end
            end
        end
        if #out >= 60 then
            break
        end
    end
    print("[Core] Church/Altar candidates:", #out)
    for _, line in ipairs(out) do
        print("  ", line)
    end
    S.notify("Core", #out .. " candidates printed to the F9 console", 5)
    return out
end

function S.coreChurchNearPlayer()
    local seen = CoreFarm._churchSeen
    if seen and seen.inst and seen.inst.Parent then
        return seen.inst
    end
    local churches, wells = S.coreScanWorld()
    local church = S.corePickChurch(churches)
    if church then
        return church
    end
    return wells[1]
end

function S.coreFlyToChurchAndSave()
    local speed = math.max(tonumber(S.getAutofarmSpeed()) or 1500, 1)
    local mapEnd = tonumber(Autofarm.mapEndStuds) or 100000
    local deadline = os.clock() + math.clamp(mapEnd / speed + 40, 60, 600)
    Autofarm.openChests = false -- no more chest detours
    Autofarm.suppressChestOreStopUntil = tick() + 600

    local found = false
    while os.clock() < deadline do
        if not Autofarm.enabled then
            break
        end
        local seen = CoreFarm._churchSeen
        if seen and seen.pos then
            found = true
            break
        end
        task.wait(0.25)
    end

    -- Sampai di Church (Frozen Layer): Auto Chest OFF + terbang berhenti total.
    Autofarm.openChests = false
    S.coreHardStopFlying()
    task.wait(0.4)
    Autofarm.openChests = false
    Autofarm.enabled = false

    local seen = CoreFarm._churchSeen
    if found and seen and seen.pos then
        S.notify("Core", "Church found — stopping and going to the Altar", 4)
        S.coreGoNear(seen.pos, 8)
        task.wait(1.8) -- let the Church / Altar stream in around us
        return S.coreChurchWellSave(8, true)
    end

    -- Never seen during the run: dump candidates for debugging, then try a direct search.
    task.spawn(function()
        pcall(S.coreDumpChurchCandidates)
    end)
    return S.coreChurchWellSave(8, false)
end

if typeof(task) == "table" or typeof(task) == "userdata" then
    task.spawn(function()
        pcall(S.coreStartChurchWatch)
    end)
end

-- Runs in the lobby when the map had no Church/Well (pending flag survives the teleport).
function S.coreRunPendingWellSave()
    if CoreFarm._wellSaving then
        return
    end
    CoreFarm._wellSaving = true
    pcall(function()
        local deadline = os.clock() + 15
        while not S.getRoot() and os.clock() < deadline do
            task.wait(0.25)
        end
        task.wait(2.5)
        local done = S.coreChurchWellSave(25, true)
        if not done then
            S.notify("Core", "Church/Well not found — save skipped", 5)
        end
    end)
    CoreFarm._pendingWellSave = false
    S.coreSaveQueue()
    CoreFarm._wellSaving = false
end

function S.coreReturnLobby(before)
    local earned = tonumber(LocalPlayer:GetAttribute("CoresEarned")) or 0
    local after = tonumber(LocalPlayer:GetAttribute("Cores")) or 0
    local gained = after - (tonumber(before) or after)
    if gained > 0 then
        S.notify("Core", "Account +" .. gained .. " cores. Leaving.", 5)
    elseif earned > 0 then
        S.notify("Core", earned .. " cores this run. Leaving so they save.", 5)
    else
        S.notify("Core", "No cores this run. Leaving.", 4)
    end
    local svc = S.coreTeleportService()
    if svc and type(svc.TeleportToLobby) == "function" then
        pcall(function()
            S.coreAwait(svc:TeleportToLobby(true))
        end)
    end
end

function S.buildLobbyTab(Window)
    local tab = Window:CreateTab("Lobby")
    tab:CreateSection("Party")
    tab:CreateDropdown({
        Name = "Mode",
        Options = { "Unranked", "Ranked" },
        CurrentOption = CoreFarm.mode,
        Flag = "dtec_lobby_mode",
        Callback = function(value)
            local picked = type(value) == "string" and value or CoreFarm.mode
            CoreFarm.mode = picked == "Ranked" and "Ranked" or "Unranked"
            S.coreSaveQueue()
        end,
    })
    tab:CreateSlider({
        Name = "Party Size",
        Range = { 1, 8 },
        Increment = 1,
        CurrentValue = CoreFarm.partySize,
        Flag = "dtec_lobby_size",
        Callback = function(value)
            CoreFarm.partySize = math.clamp(math.floor(tonumber(value) or 4), 1, 8)
            S.coreSaveQueue()
        end,
    })
    tab:CreateToggle({
        Name = "Auto Core Farm",
        CurrentValue = CoreFarm.enabled == true,
        Flag = "dtec_lobby_auto",
        Callback = function(value)
            CoreFarm.enabled = value == true
            if S._configLoading then
                return
            end
            CoreFarm._partyStarted = false
            CoreFarm._swept = false
            S.coreSaveQueue()
            if value and game.PlaceId == LOBBY_PLACE then
                task.spawn(function()
                    pcall(S.coreStartLobby)
                end)
            end
        end,
    })
    tab:CreateParagraph({
        Title = "Lobby",
        Content = "This place keeps its own config. Empty pad only. If every pad has people, it waits.",
    })

    tab:CreateSection("Lobby Chest Watcher (gems)")
    LobbyChestWatch._statusLabel = tab:CreateStatusLabel({
        Name = "Stock",
        Default = "syncing",
    })
    tab:CreateDropdown({
        Name = "Auto-buy tiers",
        Options = LOBBY_CHEST_TIERS,
        CurrentOption = LobbyChestWatch.watchTiers,
        MultipleOptions = true,
        Flag = "dtec_lobby_chest_tiers",
        Callback = function(options)
            local picked = S.lobbyChestWatchListFromDropdown(options)
            if #picked > 0 then
                LobbyChestWatch.watchTiers = picked
            end
        end,
    })
    tab:CreateToggle({
        Name = "Auto buy watched tiers",
        CurrentValue = LobbyChestWatch.autoBuy == true,
        Flag = "dtec_lobby_chest_auto_buy",
        Callback = function(value)
            LobbyChestWatch.autoBuy = value == true
            if value and #LobbyChestWatch.watchTiers == 0 then
                LobbyChestWatch.watchTiers = { "Diamond", "Void" }
            end
        end,
    })
    tab:CreateParagraph({
        Title = "Chest watcher",
        Content = "Stock comes from the server. Menu can stay closed. Auto buy takes 10 when stock allows, otherwise 1.",
    })
end

-- ============================================================
-- Auto Pickup Shard (tab Core)
-- Shard yang jatuh di tanah (mis. dari chest) otomatis diambil ke inventory
-- supaya bisa dibawa ke lobby. Prioritas: Void > Mythic > Legendary > Epic > Rare.
-- Kalau slot inventory penuh, drop 1 item yang bisa di-drop dulu (bukan shard,
-- bukan ItemBag, bukan pickaxe) supaya shard bisa masuk.
-- ============================================================
S.ShardUse = {
    enabled = false,
    busy = false,
    range = 300,
    maxSlots = 6, -- hotbar game = 6 slot (tetap)
    interval = 0.4,
    dropWhenFull = true,
    _gen = 0,
    _fail = {},
    _lastNotify = 0,
}

local SHARD_TIERS = {
    { key = "mythic", rank = 5, label = "Mythic" },
    { key = "void", rank = 4, label = "Void" },
    { key = "legendary", rank = 3, label = "Legendary" },
    { key = "legend", rank = 3, label = "Legendary" },
    { key = "epic", rank = 2, label = "Epic" },
    { key = "rare", rank = 1, label = "Rare" },
}

function S.shardTierOf(inst)
    if not inst then
        return nil
    end
    local blob = string.lower(tostring(inst.Name))
    for _, attr in ipairs({ "DisplayName", "ItemName", "Rarity", "Tier" }) do
        local v = inst:GetAttribute(attr)
        if v ~= nil then
            blob = blob .. " " .. string.lower(tostring(v))
        end
    end
    blob = blob:gsub("[^%a]", "")
    if not blob:find("shard", 1, true) then
        return nil
    end
    for _, tier in ipairs(SHARD_TIERS) do
        if blob:find(tier.key, 1, true) then
            return tier.rank, tier.label
        end
    end
    return nil
end

function S.shardAllTools()
    local list = {}
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({ char, backpack }) do
        if container then
            for _, c in ipairs(container:GetChildren()) do
                if c:IsA("Tool") then
                    table.insert(list, c)
                end
            end
        end
    end
    return list
end

function S.shardInventoryFull()
    return #S.shardAllTools() >= 6
end

-- Shard di tanah: terlangka dulu, lalu yang terdekat.
function S.shardCollectWorld()
    local list = {}
    local root = S.getRoot()
    if not root then
        return list
    end
    local range = tonumber(S.ShardUse.range) or 300
    local seen = {}
    S.forEachWorldLootItem(function(item)
        if not item or not item.Parent or seen[item] then
            return
        end
        seen[item] = true
        local rank, label = S.shardTierOf(item)
        if not rank then
            return
        end
        if os.clock() - (S.ShardUse._fail[item] or -999) < 2.5 then
            return
        end
        local pos = S.getItemPosition(item)
        if not pos then
            return
        end
        local dist = (pos - root.Position).Magnitude
        if dist <= range then
            table.insert(list, { item = item, rank = rank, label = label, dist = dist })
        end
    end)
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then
            return a.rank > b.rank
        end
        return a.dist < b.dist
    end)
    return list
end

-- Item Phoenix (senjata, pedang, pickaxe, dll) tidak pernah di-drop.
function S.isPhoenixTool(tool)
    if not tool then
        return false
    end
    local bits = { tostring(tool.Name or "") }
    for _, attr in ipairs({ "DisplayName", "ItemName", "Rarity", "ArmorName", "ItemId" }) do
        local v = tool:GetAttribute(attr)
        if v ~= nil then
            table.insert(bits, tostring(v))
        end
    end
    return string.lower(table.concat(bits, " ")):find("phoenix", 1, true) ~= nil
end

-- Urutan drop: item biasa (medkit, potion, dll) dulu, lalu item tak dikenal, lalu senjata/pedang
-- yang lebih lemah. ItemBag, pickaxe, shard, dan senjata/pedang TERBAIK per slot tidak pernah di-drop.
function S.shardPickDropCandidate()
    local tools = S.shardAllTools()
    local bestByKey = {}
    for _, tool in ipairs(tools) do
        local cat = S.getGearItemCategory(tool)
        if cat == "Sword" or cat == "Gun" then
            local key = S.getGearSlotKey(tool, cat)
            local sc = S.getWorldGearScore(tool)
            local cur = bestByKey[key]
            if not cur or sc > cur.score then
                bestByKey[key] = { tool = tool, score = sc }
            end
        end
    end
    local protected = {}
    for _, entry in pairs(bestByKey) do
        protected[entry.tool] = true
    end

    local best, bestPri, bestScore
    for _, tool in ipairs(tools) do
        if not S.shardTierOf(tool)
            and not S.isItemBagTool(tool)
            and not S.isPickaxeTool(tool)
            and not S.isPhoenixTool(tool)
            and not protected[tool]
            and os.clock() - (S.ShardUse._fail[tool] or -999) > 3 then
            local cat = S.getGearItemCategory(tool)
            local pri, score = 0, 0
            if cat == "Sword" or cat == "Gun" then
                pri = 2
                score = S.getWorldGearScore(tool)
            elseif S.isCombatTool(tool) then
                pri = 3
            else
                pri = 4
            end
            if tool.CanBeDropped ~= false then
                pri += 0.5
            end
            if not best or pri > bestPri or (pri == bestPri and score < bestScore) then
                best, bestPri, bestScore = tool, pri, score
            end
        end
    end
    return best
end

function S.shardEquip(tool)
    if not tool or not tool.Parent then
        return false
    end
    if tool.Parent == LocalPlayer.Character then
        return true
    end
    pcall(function()
        S.callEquipTool(tool)
    end)
    local deadline = os.clock() + 0.6
    while os.clock() < deadline do
        if tool.Parent == LocalPlayer.Character then
            return true
        end
        task.wait(0.03)
    end
    pcall(function()
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:EquipTool(tool)
        end
    end)
    task.wait(0.1)
    return tool.Parent == LocalPlayer.Character
end

function S.shardDropTool(tool)
    if not tool or not tool.Parent then
        return false
    end
    if S.isPhoenixTool(tool) then
        return false
    end
    if not S.shardEquip(tool) then
        S.ShardUse._fail[tool] = os.clock()
        return false
    end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local function gone()
        local p = tool.Parent
        return (not p) or (p ~= LocalPlayer.Character and p ~= backpack)
    end
    local function waitGone(seconds)
        local deadline = os.clock() + seconds
        while os.clock() < deadline do
            if gone() then
                return true
            end
            task.wait(0.05)
        end
        return gone()
    end

    -- Some games set CanBeDropped=false; the default drop key checks it on the client.
    pcall(function()
        tool.CanBeDropped = true
    end)

    -- 1) Default drop key (Backspace).
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
        task.wait(0.06)
        vim:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
    end)
    if waitGone(0.7) then
        return true
    end

    -- 2) Same thing the default drop does: unequip, then move the Tool to Workspace.
    pcall(function()
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:UnequipTools()
        end
    end)
    task.wait(0.08)
    pcall(function()
        tool.Parent = Workspace
    end)
    if waitGone(0.7) and tool.Parent ~= nil then
        task.wait(0.3)
        if gone() then
            return true
        end
    end

    S.ShardUse._fail[tool] = os.clock()
    return false
end

local function shardToolSet()
    local set = {}
    for _, t in ipairs(S.shardAllTools()) do
        set[t] = true
    end
    return set
end

-- Ambil shard dari tanah ke inventory (item dibawa ke player, player tidak dipindah).
function S.shardPickup(item)
    if not item or not item.Parent then
        return false
    end
    local itemsFolder = Workspace:FindFirstChild("Items")
    local before = shardToolSet()
    local beforeCount = 0
    for _ in pairs(before) do
        beforeCount += 1
    end

    local root = S.getRoot()
    local pos = S.getItemPosition(item)
    if root and pos and (pos - root.Position).Magnitude > 12 then
        S.bringItemToPlayer(item)
        task.wait(0.05)
    end

    local function picked()
        if #S.shardAllTools() > beforeCount then
            return true
        end
        for _, t in ipairs(S.shardAllTools()) do
            if not before[t] and S.shardTierOf(t) then
                return true
            end
        end
        if not item.Parent then
            return true
        end
        if itemsFolder and not item:IsDescendantOf(itemsFolder) and not item:IsDescendantOf(Workspace) then
            return true
        end
        return false
    end

    for _ = 1, 3 do
        if Services.InteractionService then
            pcall(function()
                Services.InteractionService:Interact(item)
            end)
        end
        if item.Parent and item:IsA("Tool") and Services.ToolService then
            pcall(S.callEquipTool, item)
        end
        local deadline = os.clock() + 0.45
        while os.clock() < deadline do
            if picked() then
                return true
            end
            task.wait(0.05)
        end
        if S.getRoot() and item.Parent then
            S.bringItemToPlayer(item)
        end
    end
    S.ShardUse._fail[item] = os.clock()
    return false
end

function S.shardStep()
    local cfg = S.ShardUse
    if cfg.busy then
        return
    end
    local targets = S.shardCollectWorld()
    local target = targets[1]
    if not target then
        return
    end
    cfg.busy = true
    local prevEquipped = S.getEquippedTool()
    local ok, err = pcall(function()
        local function dropOne()
            local junk = S.shardPickDropCandidate()
            if not junk then
                return false
            end
            local dropped = S.shardDropTool(junk)
            task.wait(0.25)
            return dropped
        end

        if cfg.dropWhenFull and S.shardInventoryFull() then
            dropOne()
        end
        if not target.item.Parent then
            return
        end

        local got = S.shardPickup(target.item)

        if got and os.clock() - cfg._lastNotify > 1 then
            cfg._lastNotify = os.clock()
            S.notify("Shard", "Picked up " .. tostring(target.label) .. " shard", 3)
        end
    end)
    if not ok then
        warn("[JPAX] shard step:", err)
    end
    pcall(function()
        if prevEquipped and prevEquipped.Parent and prevEquipped ~= S.getEquippedTool() then
            S.shardEquip(prevEquipped)
        end
    end)
    cfg.busy = false
end

function S.setShardUse(enabled)
    local cfg = S.ShardUse
    cfg.enabled = enabled == true
    cfg._gen += 1
    cfg._fail = {}
    cfg.busy = false
    if not cfg.enabled then
        return
    end
    local gen = cfg._gen
    task.spawn(function()
        while cfg.enabled and cfg._gen == gen do
            pcall(S.shardStep)
            task.wait(cfg.interval)
        end
    end)
end

function S.buildCoreTab(Window)
    local tab = Window:CreateTab("Core")
    tab:CreateSection("Chests")
    tab:CreateToggle({
        Name = "Open all chests",
        CurrentValue = CoreFarm.openAll == true,
        Flag = "dtec_core_open",
        Callback = function(value)
            if not value then
                S.stopCoreChestRun()
                return
            end
            CoreFarm._userStop = false
            CoreFarm.openAll = true
            CoreFarm._applying = false
            CoreFarm.laps = 0
            CoreFarm._runStarted = false
            S.coreSaveQueue()
            if game.PlaceId == JPAX.placeId then
                CoreFarm._ownedRun = true
                task.spawn(function()
                    pcall(S.coreApplyRun)
                end)
            end
        end,
    })
    tab:CreateToggle({
        Name = "Auto Skip Locked Chest",
        CurrentValue = Autofarm.autoSkipLockedChest ~= false,
        Flag = "dtec_core_skip_locked_chest",
        Callback = function(value)
            Autofarm.autoSkipLockedChest = value == true
            S.coreSaveQueue()
        end,
    })
    tab:CreateDropdown({
        Name = "Chest Types",
        Options = CHEST_TYPE_OPTIONS,
        CurrentOption = S.chestLabelsFromSaved(CoreFarm.chestTypes),
        MultipleOptions = true,
        Flag = "dtec_core_chest_types",
        Callback = function(options)
            local picked = S.chestSelectionList(options)
            if #picked == 0 then
                if CoreFarm.openAll or CoreFarm._ownedRun then
                    S.coreHoldChestRun()
                end
                return
            end
            CoreFarm.chestTypes = picked
            CoreFarm._chestPick = picked
            if CoreFarm.openAll or CoreFarm._ownedRun then
                Autofarm.chestTypes = picked
                Autofarm.openChests = true
            end
            S.coreSaveQueue()
        end,
    })
    tab:CreateSlider({
        Name = "Laps",
        Range = { 1, 10 },
        Increment = 1,
        CurrentValue = CoreFarm.rescans,
        Flag = "dtec_core_rescan",
        Callback = function(value)
            CoreFarm.rescans = math.clamp(math.floor(tonumber(value) or 2), 1, 10)
            S.coreSaveQueue()
        end,
    })
    tab:CreateToggle({
        Name = "Save Items at Well (after laps)",
        CurrentValue = CoreFarm.saveAtWell == true,
        Flag = "dtec_core_save_well",
        Callback = function(value)
            CoreFarm.saveAtWell = value == true
            if not value then
                CoreFarm._pendingWellSave = false
            end
            S.coreSaveQueue()
        end,
    })
    tab:CreateButton({
        Name = "Save Item at Altar",
        Callback = function()
            task.spawn(function()
                local done = S.coreChurchWellSave(15, true)
                if not done then
                    S.notify("Core", "Altar not found, or holding E did not trigger the save", 5)
                end
            end)
        end,
    })
    tab:CreateSection("Shards")
    tab:CreateToggle({
        Name = "Auto Pickup Shard",
        CurrentValue = S.ShardUse.enabled == true,
        Flag = "jpax_auto_use_shard",
        Callback = function(value)
            S.setShardUse(value == true)
        end,
    })
    tab:CreateToggle({
        Name = "Drop Items When Slots Are Full",
        CurrentValue = S.ShardUse.dropWhenFull ~= false,
        Flag = "jpax_shard_drop_full",
        Callback = function(value)
            S.ShardUse.dropWhenFull = value == true
        end,
    })
    tab:CreateSlider({
        Name = "Shard Detection Range (studs)",
        Range = { 20, 3000 },
        Increment = 10,
        CurrentValue = S.ShardUse.range,
        Flag = "jpax_shard_range",
        Callback = function(value)
            S.ShardUse.range = math.clamp(tonumber(value) or 300, 20, 3000)
        end,
    })
    tab:CreateParagraph({
        Title = "Auto Pickup Shard",
        Content = "Shards that fall on the ground (e.g. from chests) are picked up into your inventory automatically. Priority: Mythic > Void > Legendary > Epic > Rare. When the hotbar (6 slots) is full, droppable items are dropped first (ItemBag, pickaxes, Phoenix items, and shards are never dropped).",
    })
    tab:CreateParagraph({
        Title = "Core",
        Content = "Opens the chest types on the path. Dungeons are not required. Laps is how many times it reaches 100K, then it goes back to the lobby. With Save Items at Well on, it first teleports to the Church and saves items at the Well (finishes in the lobby if the map has no Church/Well).",
    })
end

function S.buildAutofarmTab(Window)
    local MoneyTab = Window:CreateTab("Money")

    MoneyTab:CreateSection("Money Sacks")

    MoneyTab:CreateToggle({
        Name = "Money Sack Aura",
        CurrentValue = false,
        Flag = "jpax_reap_aura",
        Callback = function(value)
            S.setReapAura(value == true)
        end,
    })

    MoneyTab:CreateParagraph({
        Title = "Picks up money sacks you touch. No teleport.",
    })

    MoneyTab:CreateButton({
        Name = "Collect All Money Sacks",
        Callback = function()
            task.spawn(S.reapSweepRenderedSacks)
        end,
    })

    MoneyTab:CreateSection("Sell")

    local reapSellToggle
    reapSellToggle = MoneyTab:CreateToggle({
        Name = "Sell Loot In Bag",
        CurrentValue = false,
        Flag = "jpax_reap_sell_bag",
        Callback = function(value)
            if value == true then
                local ok = S.setReapSellBag(true)
                if not ok and reapSellToggle and reapSellToggle.Set then
                    reapSellToggle:Set(false)
                end
            else
                S.setReapSellBag(false)
            end
        end,
    })

    local FarmTab = Window:CreateTab("Farm")

    FarmTab:CreateSection("Run")

    FarmTab:CreateToggle({
        Name = "Run",
        CurrentValue = false,
        Flag = "terra_autofarm",
        Callback = function(value)
            if S._configLoading or game.PlaceId ~= JPAX.placeId then
                return
            end
            if not value and type(CoreFarm) == "table" and (CoreFarm.openAll or CoreFarm._ownedRun) then
                S.stopCoreChestRun()
                S.notify("Run", "OFF", 3)
                return
            end
            if value then
                CoreFarm._userStop = false
            end
            S.runRayfieldSafeCallback("terra_autofarm", function()
                S.setAutofarm(value == true)
                if value then
                    local _, startM, endM = S.syncAutofarmWindowFromDrill()
                    S.notify(
                        "Run",
                        string.format("ON · farm %dk–%dk m (drill)", math.floor(startM / 1000), math.floor(endM / 1000)),
                        4
                    )
                else
                    S.notify("Run", "OFF", 3)
                end
            end)
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Farm Bandit",
        CurrentValue = false,
        Flag = "jpax_auto_farm_bandit",
        Callback = function(value)
            S.setBanditFarm(value == true)
            S.notify(
                "Farm",
                value and string.format("Auto Farm Bandit ON · %d studs (Stone skipped)", S.Bandit.range)
                    or "Auto Farm Bandit OFF",
                3
            )
        end,
    })

    FarmTab:CreateToggle({
        Name = "Bandit: Under Enemy",
        CurrentValue = true,
        Flag = "jpax_bandit_under",
        Callback = function(value)
            S.Bandit.underMode = value == true
            if not value then
                S.banditLeaveUnder()
            end
        end,
    })

    FarmTab:CreateSlider({
        Name = "Bandit Detection Range (studs)",
        Range = { 100, 5000 },
        Increment = 100,
        CurrentValue = S.Bandit.range,
        Flag = "jpax_bandit_range_v2",
        Callback = function(value)
            S.Bandit.range = math.clamp(tonumber(value) or 5000, 100, 5000)
        end,
    })

    FarmTab:CreateSlider({
        Name = "Hover Height",
        Range = { -15, 70 },
        Increment = 0.5,
        CurrentValue = Autofarm.flyY,
        Flag = "terra_autofarm_fly_y",
        Callback = function(value)
            Autofarm.flyY = value
            if Autofarm.enabled then
                S.setAutofarmPose(Autofarm.distance or 0)
            end
        end,
    })

    FarmTab:CreateSlider({
        Name = "Move Speed",
        Range = { 200, 4000 },
        Increment = 50,
        CurrentValue = Autofarm.tweenSpeed,
        Flag = "jpax_autofarm_move_speed",
        Callback = function(value)
            Autofarm.tweenSpeed = math.clamp(tonumber(value) or 1500, 80, 4000)
        end,
    })

    FarmTab:CreateToggle({
        Name = "Farm Debug",
        CurrentValue = Autofarm.debugHud ~= false,
        Flag = "jpax_farm_debug",
        Callback = function(value)
            Autofarm.debugHud = value == true
            if Autofarm.debugHud then
                S.ensureFarmDebugHud()
                S.farmLog("debug", "ON")
            else
                S.destroyFarmDebugHud()
            end
        end,
    })

    FarmTab:CreateSection("Depth")
    S.bindDepthReadout("drill", FarmTab:CreateSlider({
        Name = "Drill Depth",
        Range = { 0, 100000 },
        Increment = 1,
        CurrentValue = 0,
        Flag = "jpax_farm_drill_depth_m",
        Callback = function() end,
    }))
    S.bindDepthReadout("you", FarmTab:CreateSlider({
        Name = "Your Depth",
        Range = { 0, 100000 },
        Increment = 1,
        CurrentValue = 0,
        Flag = "jpax_farm_player_depth_m",
        Callback = function() end,
    }))

    FarmTab:CreateSection("Ores")

    FarmTab:CreateToggle({
        Name = "Auto Ores",
        CurrentValue = Autofarm.oreUnderEnabled == true,
        Flag = "terra_af_auto_ores",
        Callback = function(value)
            Autofarm.oreUnderEnabled = value == true
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Ore Types",
        Options = ORE_DROPDOWN_OPTIONS,
        CurrentOption = Autofarm.oreUnderTypes or {},
        MultipleOptions = true,
        Flag = "terra_af_ore_types",
        Callback = function(options)
            Autofarm.oreUnderTypes = options or {}
        end,
    })

    FarmTab:CreateToggle({
        Name = "Skip DeathWorm Ores",
        CurrentValue = false,
        Flag = "terra_af_skip_worms",
        Callback = function(value)
            Autofarm.breakDeathWormOres = value ~= true
        end,
    })

    FarmTab:CreateSection("Loot")

    FarmTab:CreateToggle({
        Name = "Auto Loot",
        CurrentValue = false,
        Flag = "terra_auto_loot",
        Callback = function(value)
            S.setAutoLoot(value)
        end,
    })

    FarmTab:CreateButton({
        Name = "Copy Inventory Debug Info",
        Callback = function()
            S.dumpInventoryDebugInfo()
        end,
    })

    FarmTab:CreateToggle({
        Name = "Inventory Spy (log game remotes)",
        CurrentValue = false,
        Flag = "terra_inv_spy",
        Callback = function(value)
            S.setInventorySpy(value)
        end,
    })

    FarmTab:CreateButton({
        Name = "Copy Inventory Spy Log",
        Callback = function()
            S.copyInventorySpyLog()
        end,
    })

    FarmTab:CreateButton({
        Name = "Clear Inventory Spy Log",
        Callback = function()
            S.clearInventorySpyLog()
        end,
    })

    FarmTab:CreateToggle({
        Name = "Skip Loot On Truck",
        CurrentValue = Loot.skipTruckLoot,
        Flag = "terra_loot_skip_truck",
        Callback = function(value)
            Loot.skipTruckLoot = value
        end,
    })

    FarmTab:CreateToggle({
        Name = "Use Blacklist",
        CurrentValue = false,
        Flag = "terra_loot_blacklist_toggle",
        Callback = function(value)
            Loot.useBlacklist = value
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Loot Blacklist",
        Options = BLACKLIST_OPTIONS,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = "terra_loot_blacklist",
        Callback = function(options)
            Loot.blacklistCategories = options or {}
        end,
    })

    FarmTab:CreateToggle({
        Name = "Min Coins Only",
        CurrentValue = false,
        Flag = "terra_loot_min_coins_toggle",
        Callback = function(value)
            Loot.useMinCoins = value
        end,
    })

    FarmTab:CreateInput({
        Name = "Min coin value",
        PlaceholderText = "off unless Min Coins Only is on",
        RemoveTextAfterFocusLost = false,
        Flag = "terra_loot_min_coins",
        Callback = function(text)
            Loot.minCoins = tonumber(text) or 0
        end,
    })

    FarmTab:CreateSection("Mines & Chests")

    FarmTab:CreateToggle({
        Name = "Join Mines",
        CurrentValue = Autofarm.enterMines == true,
        Flag = "terra_af_join_mines",
        Callback = function(value)
            Autofarm.enterMines = value == true
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Chests",
        CurrentValue = Autofarm.openChests == true,
        Flag = "terra_af_auto_chests",
        Callback = function(value)
            if CoreFarm and (CoreFarm._ownedRun or CoreFarm.openAll) then
                return
            end
            Autofarm.openChests = value == true
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Chest Types",
        Options = CHEST_TYPE_OPTIONS,
        CurrentOption = S.chestLabelsFromSaved(Autofarm.chestTypes),
        MultipleOptions = true,
        Flag = "terra_af_chest_types",
        Callback = function(options)
            if CoreFarm and (CoreFarm._ownedRun or CoreFarm.openAll) then
                return
            end
            Autofarm.chestTypes = S.chestSelectionList(options)
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Equip Best",
        CurrentValue = Autofarm.autoEquipBest == true,
        Flag = "terra_af_equip_best",
        Callback = function(value)
            S.setAutofarmEquipBest(value == true)
        end,
    })

    FarmTab:CreateSection("Drops")

    FarmTab:CreateSlider({
        Name = "Dump At (items)",
        Range = { 1, 50 },
        Increment = 1,
        CurrentValue = math.clamp(tonumber(Autofarm.sellThreshold) or 10, 1, 50),
        Flag = "terra_af_sell_threshold",
        Callback = function(value)
            Autofarm.sellThreshold = math.clamp(math.floor(value), 1, 50)
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Sell",
        CurrentValue = Autofarm.autoSell == true,
        Flag = "terra_af_auto_sell",
        Callback = function(value)
            S.runRayfieldSafeCallback("terra_af_auto_sell", function()
                S.setAutofarmAutoSell(value == true)
            end)
        end,
    })

    FarmTab:CreateToggle({
        Name = "Drop in Drill",
        CurrentValue = Autofarm.dropInDrill == true,
        Flag = "terra_af_drop_drill",
        Callback = function(value)
            S.runRayfieldSafeCallback("terra_af_drop_drill", function()
                S.setDropInDrill(value == true)
            end)
        end,
    })

    FarmTab:CreateToggle({
        Name = "Dump on Shredder",
        CurrentValue = Autofarm.dropInShredder == true,
        Flag = "terra_af_drop_shredder",
        Callback = function(value)
            S.runRayfieldSafeCallback("terra_af_drop_shredder", function()
                S.setDropInShredder(value == true)
            end)
        end,
    })
end

function S.buildScrapTab(Window)
    local ScrapTab = Window:CreateTab("Scrap")

    ScrapTab:CreateSection("Scrap")

    ScrapTab:CreateToggle({
        Name = "Run Scrap",
        CurrentValue = Autofarm.scrapFarm == true,
        Flag = "terra_af_scrap_farm",
        Callback = function(value)
            if S._configLoading then
                return
            end
            -- Defer: Rayfield crashes if callback yields or re-Sets this flag ("error in error handling").
            S.runRayfieldSafeCallback("terra_af_scrap_farm", function()
                S.setScrapFarm(value == true)
            end)
        end,
    })

    ScrapTab:CreateDropdown({
        Name = "Scrap Ore Types",
        Options = SCRAP_ORE_OPTIONS,
        CurrentOption = Autofarm.scrapOreTypes or { "Gold" },
        MultipleOptions = true,
        Flag = "terra_af_scrap_ore_types",
        Callback = function(options)
            S.setScrapOreTypes(options or {})
        end,
    })
end

function S.buildLootTab(Window)
    local LootTab = Window:CreateTab("Auto Loot")
    LootTab:CreateSection("Bag Loot (Max Range)")

    LootTab:CreateToggle({
        Name = "Auto Loot",
        CurrentValue = false,
        Flag = "terra_auto_loot",
        Callback = function(value)
            S.setAutoLoot(value)
            S.notify(HUB_NAME, value and "Auto loot ON" or "Auto loot OFF", 3)
        end,
    })

    LootTab:CreateToggle({
        Name = "Auto Drop Bag After Loot",
        CurrentValue = false,
        Flag = "terra_auto_drop_loot",
        Callback = function(value)
            Loot.autoDropAfterLoot = value
        end,
    })

    LootTab:CreateToggle({
        Name = "Skip Loot On Truck",
        CurrentValue = Loot.skipTruckLoot,
        Flag = "terra_loot_skip_truck",
        Callback = function(value)
            Loot.skipTruckLoot = value
        end,
    })

    LootTab:CreateSection("Filters")

    LootTab:CreateToggle({
        Name = "Use Blacklist",
        CurrentValue = false,
        Flag = "terra_loot_blacklist_toggle",
        Callback = function(value)
            Loot.useBlacklist = value
        end,
    })

    LootTab:CreateDropdown({
        Name = "Blacklist",
        Options = BLACKLIST_OPTIONS,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = "terra_loot_blacklist",
        Callback = function(options)
            Loot.blacklistCategories = options or {}
        end,
    })

    LootTab:CreateToggle({
        Name = "Min Coins Only",
        CurrentValue = false,
        Flag = "terra_loot_min_coins_toggle",
        Callback = function(value)
            Loot.useMinCoins = value
        end,
    })

    LootTab:CreateInput({
        Name = "Min coin value",
        PlaceholderText = "off unless Min Coins Only is on",
        RemoveTextAfterFocusLost = false,
        Flag = "terra_loot_min_coins",
        Callback = function(text)
            Loot.minCoins = tonumber(text) or 0
        end,
    })
end

function S.buildAutoBuyTab(Window)
    local BuyTab = Window:CreateTab("Shop")

    Upgrades.tab = BuyTab
                task.defer(function()
        Upgrades.tabPage = S.findRayfieldTabPage("Shop")
    end)
    BuyTab:CreateSection("Upgrades")
    BuyTab:CreateToggle({
        Name = "Auto Buy Upgrades",
        CurrentValue = false,
        Flag = "terra_auto_upgrades",
        Callback = function(value)
            S.setAutoUpgrade(value)
            S.notify("Upgrades", value and "Auto buy ON" or "Auto buy OFF", 3)
        end,
    })
    S.applyPriorityElementLayout("Auto Buy Upgrades", UPGRADE_PRIORITY_ADD_LAYOUT - 2)
    BuyTab:CreateButton({
        Name = UPGRADE_PRIORITY_ADD_BUTTON,
        Callback = function()
            S.addUpgradePrioritySlot(BuyTab)
        end,
    })
    S.applyPriorityElementLayout(UPGRADE_PRIORITY_ADD_BUTTON, UPGRADE_PRIORITY_ADD_LAYOUT)
    for _ = 1, 3 do
        S.createUpgradePrioritySlot(BuyTab, "None")
    end
    task.defer(function()
        S.relayoutUpgradePrioritySlots()
    end)

    BuyTab:CreateSection("Buy Ammo")
    BuyTab:CreateDropdown({
        Name = "Ammo Types",
        Options = { "All Ammo", "Pistol_Ammo", "Rifle_Ammo", "Shotgun_Ammo", "Special_Ammo" },
        CurrentOption = AmmoBuy.types,
        MultipleOptions = true,
        Flag = "terra_ammo_buy_types",
        Callback = function(options)
            AmmoBuy.types = options or {}
        end,
    })
    BuyTab:CreateButton({
        Name = "List Ammo In Shop",
        Callback = function()
            pcall(S.debugAmmoStock)
        end,
    })
    BuyTab:CreateButton({
        Name = "Buy Ammo Now",
        Callback = function()
            task.spawn(function()
                pcall(S.buyAmmoNow)
            end)
        end,
    })
end

function S.buildPickaxeTab(Window)
    local PickaxeTab = Window:CreateTab("Pickaxe")
    PickaxeTab:CreateSection("Equipment")

    PickaxeTab:CreateToggle({
        Name = "Auto Equip Pickaxe",
        CurrentValue = false,
        Flag = "terra_auto_equip_pickaxe",
        Callback = function(value)
            S.setAutoEquipPickaxe(value)
            S.notify("Pickaxe", value and "Auto equip pickaxe ON" or "Auto equip pickaxe OFF", 3)
        end,
    })

    PickaxeTab:CreateSection("Auto Mine")

    PickaxeTab:CreateToggle({
        Name = "Auto Mine Ores (Far)",
        CurrentValue = false,
        Flag = "terra_auto_mine",
        Callback = function(value)
            S.setAutoMine(value)
            S.notify("Pickaxe", value and "Auto mine ON" or "Auto mine OFF", 3)
        end,
    })

    PickaxeTab:CreateButton({
        Name = "Mine Once",
        Callback = function()
            if not Services.ToolService then
                S.notify(HUB_NAME, "Game services not ready yet", 4)
                return
            end
            S.notify("Pickaxe", "Mined " .. tostring(S.mineSwing()) .. " ores", 3)
        end,
    })
end

function S.buildTeleportTab(Window)
    local TeleportTab = Window:CreateTab("Teleport")
    TeleportTab:CreateSection("Nearest (Entrance)")

    TeleportTab:CreateButton({
        Name = "Village / Trade Post",
        Callback = function()
            S.teleportHubToNearest("village")
        end,
    })

    TeleportTab:CreateButton({
        Name = "Dungeon",
        Callback = function()
            S.teleportHubToNearest("dungeon")
        end,
    })

    TeleportTab:CreateButton({
        Name = "Mine",
        Callback = function()
            S.teleportHubToNearest("mine")
        end,
    })

    TeleportTab:CreateSection("Server")

    TeleportTab:CreateButton({
        Name = "Rejoin Same Server",
        Callback = function()
            S.rejoinSameServer()
        end,
    })
end

function S.buildUpgradesTab(Window)
    local UpgradesTab = Window:CreateTab("Upgrades")
    Upgrades.tab = UpgradesTab
    task.defer(function()
        Upgrades.tabPage = S.findRayfieldTabPage("Upgrades")
    end)

    UpgradesTab:CreateSection("Auto Buy (by name, any tier)")

    UpgradesTab:CreateToggle({
        Name = "Auto Buy Upgrades",
        CurrentValue = false,
        Flag = "terra_auto_upgrades",
        Callback = function(value)
            S.setAutoUpgrade(value)
            S.notify("Upgrades", value and "Auto buy ON" or "Auto buy OFF", 3)
        end,
    })
    S.applyPriorityElementLayout("Auto Buy Upgrades", UPGRADE_PRIORITY_ADD_LAYOUT - 2)

    UpgradesTab:CreateButton({
        Name = UPGRADE_PRIORITY_ADD_BUTTON,
        Callback = function()
            S.addUpgradePrioritySlot(UpgradesTab)
        end,
    })
    S.applyPriorityElementLayout(UPGRADE_PRIORITY_ADD_BUTTON, UPGRADE_PRIORITY_ADD_LAYOUT)

    for _ = 1, 3 do
        S.createUpgradePrioritySlot(UpgradesTab, "None")
    end

    task.defer(function()
        S.relayoutUpgradePrioritySlots()
    end)
end

function S.buildDrillTab(Window)
    local DrillTab = Window:CreateTab("Drill")
    DrillTab:CreateSection("Teleport")

    DrillTab:CreateButton({
        Name = "Teleport to Drill (Void)",
        Callback = function()
            if S.teleportToDrillViaVoid() then
                S.notify("Drill", "Sent to void - you respawn at drill", 4)
            else
                S.notify("Drill", "Character not found", 3)
            end
        end,
    })

    DrillTab:CreateSection("Auto Fuel")

    DrillTab:CreateToggle({
        Name = "Auto Fuel Drill",
        CurrentValue = false,
        Flag = "terra_auto_fuel",
        Callback = function(value)
            S.setAutoFuel(value)
            S.notify("Drill", value and "Auto fuel ON" or "Auto fuel OFF", 3)
        end,
    })

    DrillTab:CreateSlider({
        Name = "Stop Fuel At % Tank",
        Range = { 50, 100 },
        Increment = 5,
        CurrentValue = math.floor(Loot.fuelThreshold * 100),
        Flag = "terra_fuel_threshold",
        Callback = function(value)
            Loot.fuelThreshold = value / 100
        end,
    })

    DrillTab:CreateButton({
        Name = "Fuel Once Now",
        Callback = function()
            S.runRayfieldSafeCallback("terra_fuel_once", function()
                if not Services.DragService then
                    S.notify(HUB_NAME, "Game services not ready yet", 4)
                    return
                end
                local count = S.runFuelCycle()
                S.notify("Drill", "Deposited " .. tostring(count) .. " fuel items", 4)
            end)
        end,
    })

    DrillTab:CreateParagraph({
        Title = "Sack fuel lock",
        Content = "Unload fuel from sack + Weld (Z) lives on Autofarm → Sell / Fuel Lock (runs before sell).",
    })

    DrillTab:CreateSection("Drive")

    DrillTab:CreateToggle({
        Name = "Auto Drive",
        CurrentValue = AutoDrive.enabled,
        Flag = "terra_auto_drive",
        Callback = function(value)
            if value then
                S.setAutoDrive(true)
            else
                S.setAutoDrive(false)
                S.notify("Drill", "Auto Drive OFF", 3)
            end
        end,
    })

    DrillTab:CreateParagraph({
        Title = "Auto Drive",
        Content = "Sits in the cabin, claims driver, holds throttle 1. Game requires the seat — float/height drive does not work.",
    })

    DrillTab:CreateButton({
        Name = "Start Driving",
        Callback = function()
            S.safeCall("StartDriving", function()
                Services.DrillService:StartDriving():andThen(function(ok)
                    S.notify("Drill", ok and "You are now the driver" or "Failed - get near drill seat", 4)
                end)
            end)
        end,
    })

    DrillTab:CreateButton({
        Name = "Stop Driving",
        Callback = function()
            S.safeCall("StopDriving", function()
                Services.DrillService:UpdateDriverThrottle(0)
                Services.DrillService:StopDriving()
                S.notify("Drill", "Stopped driving", 3)
            end)
        end,
    })

    DrillTab:CreateSection("Truck Lock (Z / Attach)")

    DrillTab:CreateParagraph({
        Title = "Same as Z",
        Content = "Uses DragService:Weld — same as pressing Z on truck items (Attach/Detach).",
    })

    DrillTab:CreateToggle({
        Name = "Auto Lock Items On Truck",
        CurrentValue = false,
        Flag = "terra_auto_lock_truck",
        Callback = function(value)
            S.setAutoLockTruck(value)
            S.notify("Drill", value and "Auto lock ON - welds drops on truck" or "Auto lock OFF", 3)
        end,
    })

    DrillTab:CreateButton({
        Name = "Lock All Items On Truck",
        Callback = function()
            S.runRayfieldSafeCallback("terra_lock_truck_once", function()
                if not Services.DragService then
                    S.notify("Drill", "DragService not ready", 3)
                    return
                end
                local count = S.lockTruckItems(true)
                S.notify("Drill", "Locked " .. tostring(count) .. " truck items", 3)
            end)
        end,
    })

    DrillTab:CreateButton({
        Name = "Unlock All Items On Truck",
        Callback = function()
            S.runRayfieldSafeCallback("terra_unlock_truck_once", function()
                if not Services.DragService then
                    S.notify("Drill", "DragService not ready", 3)
                    return
                end
                local count = S.lockTruckItems(false)
                S.notify("Drill", "Unlocked " .. tostring(count) .. " truck items", 3)
            end)
        end,
    })
end

function S.buildEspTab(Window)
    local EspTab = Window:CreateTab("ESP")
    EspTab:CreateSection("General")

    EspTab:CreateSlider({
        Name = "Max Range (studs)",
        Range = { 100, 3000 },
        Increment = 50,
        CurrentValue = Esp.maxRange,
        Flag = "jpax_esp_range",
        Callback = function(value)
            Esp.maxRange = value
            Loot.range = value -- sack reach = ESP reach
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateToggle({
        Name = "Show Names",
        CurrentValue = true,
        Flag = "jpax_esp_names",
        Callback = function(value)
            Esp.showNames = value
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Flag = "jpax_esp_distance",
        Callback = function(value)
            Esp.showDistance = value
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateToggle({
        Name = "Tracers",
        CurrentValue = false,
        Flag = "jpax_esp_tracers",
        Callback = function(value)
            Esp.tracers = value
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateSection("Loot Highlight")

    EspTab:CreateToggle({
        Name = "Loot ESP",
        CurrentValue = false,
        Flag = "jpax_esp_loot",
        Callback = function(value)
            Esp.lootEnabled = value
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateDropdown({
        Name = "Loot Categories (only selected)",
        Options = ESP_LOOT_OPTIONS,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = "jpax_esp_loot_categories",
        Callback = function(options)
            Esp.lootCategories = options or {}
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateSection("Entities")

    EspTab:CreateToggle({
        Name = "Mobs",
        CurrentValue = false,
        Flag = "jpax_esp_mobs",
        Callback = function(value)
            Esp.mobsEnabled = value
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateToggle({
        Name = "Ores",
        CurrentValue = false,
        Flag = "jpax_esp_ores",
        Callback = function(value)
            Esp.oresEnabled = value
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateButton({
        Name = "Debug Nearby Ores (120m)",
        Callback = function()
            S.debugNearbyOres(120)
        end,
    })

    EspTab:CreateToggle({
        Name = "Chests",
        CurrentValue = false,
        Flag = "jpax_esp_chests",
        Callback = function(value)
            Esp.chestsEnabled = value
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateSection("Locations")

    EspTab:CreateToggle({
        Name = "Dungeons",
        CurrentValue = false,
        Flag = "jpax_esp_dungeons",
        Callback = function(value)
            Esp.dungeonsEnabled = value
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateToggle({
        Name = "Mines",
        CurrentValue = false,
        Flag = "jpax_esp_mines",
        Callback = function(value)
            Esp.minesEnabled = value
            S.refreshEspIfNeeded()
        end,
    })

    EspTab:CreateToggle({
        Name = "Villages / Trade Post",
        CurrentValue = false,
        Flag = "jpax_esp_villages",
        Callback = function(value)
            Esp.villagesEnabled = value
            S.refreshEspIfNeeded()
        end,
    })
end

function S.buildCombatTab(Window)
    S.ensureFaceWormGuard()
    local CombatTab = Window:CreateTab("Combat")
    CombatTab:CreateSection("Kill Aura")

    CombatTab:CreateParagraph({
        Title = "Kill Aura",
        Content = "Hits mobs in range only. Pauses while mining. DeathWorms use sword only.",
    })

    CombatTab:CreateToggle({
        Name = "Kill Aura",
        CurrentValue = false,
        Flag = "terra_kill_aura",
        Callback = function(value)
            S.setKillAura(value)
            S.notify("Combat", value and ("Kill aura ON — " .. tostring(Combat.auraRange) .. " studs") or "Kill aura OFF", 3)
        end,
    })

    CombatTab:CreateSlider({
        Name = "Aura Range (studs)",
        Range = { 15, 200 },
        Increment = 5,
        CurrentValue = Combat.auraRange or 50,
        Flag = "terra_kill_aura_range",
        Callback = function(value)
            Combat.auraRange = math.clamp(tonumber(value) or 50, 15, 200)
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Equip Best Damage Tool",
        CurrentValue = Combat.autoEquipBestDamage,
        Flag = "terra_combat_auto_equip_damage",
        Callback = function(value)
            Combat.autoEquipBestDamage = value
            if value then
                local best = S.findBestDamageCombatTool()
                if best then
                    S.ensureBestDamageTool()
                    S.notify("Combat", "Auto equip ON - best: " .. best.Name .. " (" .. math.floor(S.getToolDamage(best)) .. " DMG)", 4)
                else
                    S.notify("Combat", "Auto equip ON - no combat tool in inventory", 3)
                end
            else
                S.notify("Combat", "Auto equip OFF", 3)
            end
        end,
    })

    CombatTab:CreateToggle({
        Name = "Gun Auto Headshot (Aim at Head)",
        CurrentValue = Combat.gunHeadshotAim,
        Flag = "terra_gun_headshot_aim",
        Callback = function(value)
            Combat.gunHeadshotAim = value == true
            S.notify("Combat", value and "Gun headshot aim ON" or "Gun headshot aim OFF", 3)
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Kill Face Worms",
        CurrentValue = Combat.autoKillFaceWorms,
        Flag = "terra_auto_kill_face_worms",
        Callback = function(value)
            Combat.autoKillFaceWorms = value == true
            S.notify("Combat", value and "Face worms: pickaxe client swing ON" or "Face worm auto-kill OFF", 4)
        end,
    })

    CombatTab:CreateSection("Defense")

    CombatTab:CreateToggle({
        Name = "Dodge Mob Attack Hitboxes",
        CurrentValue = false,
        Flag = "terra_dodge_hitbox",
        Callback = function(value)
            S.setDodgeHitbox(value)
            S.notify("Combat", value and ("Dodge ON - mode: " .. tostring(Combat.dodgeMode)) or "Dodge OFF", 3)
        end,
    })

    CombatTab:CreateDropdown({
        Name = "Dodge Mode",
        Options = { "Flee", "Above", "Under" },
        CurrentOption = { Combat.dodgeMode },
        MultipleOptions = false,
        Flag = "terra_dodge_mode",
        Callback = function(option)
            local mode = S.resolveDropdownChoice(option)
            if mode ~= "Flee" and mode ~= "Above" and mode ~= "Under" then
                mode = "Flee"
            end
            Combat.dodgeMode = mode
            if Combat.dodgeHitbox then
                S.notify("Combat", "Dodge mode: " .. mode, 3)
            end
        end,
    })

    CombatTab:CreateSlider({
        Name = "Above Height (studs)",
        Range = { 4, 16 },
        Increment = 1,
        CurrentValue = Combat.dodgeAboveHeight,
        Flag = "terra_dodge_above_height",
        Callback = function(value)
            Combat.dodgeAboveHeight = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Under Depth (studs)",
        Range = { 3, 14 },
        Increment = 1,
        CurrentValue = Combat.dodgeUnderDepth,
        Flag = "terra_dodge_under_depth",
        Callback = function(value)
            Combat.dodgeUnderDepth = value
        end,
    })
end

function S.buildAutoCombatTab(Window)
    local Tab = Window:CreateTab("Auto Combat")
    Tab:CreateSection("Ride")
    Tab:CreateParagraph({
        Title = "Auto Jump",
        Content = "While sitting on the drill / a seat, jump when a mob is close. Uses your Dodge settings if Dodge is on.",
    })
    Tab:CreateToggle({
        Name = "Auto Jump While Riding",
        CurrentValue = Combat.rideAutoJump == true,
        Flag = "terra_ride_auto_jump",
        Callback = function(value)
            S.setRideAutoJump(value == true)
            S.notify("Auto Combat", value and "Ride jump ON" or "Ride jump OFF", 3)
        end,
    })
    Tab:CreateSlider({
        Name = "Jump when mob within (studs)",
        Range = { 10, 80 },
        Increment = 2,
        CurrentValue = Combat.rideJumpRange or 28,
        Flag = "terra_ride_jump_range",
        Callback = function(value)
            Combat.rideJumpRange = math.clamp(tonumber(value) or 28, 10, 80)
        end,
    })
    Tab:CreateSection("Defense")
    Tab:CreateToggle({
        Name = "Dodge Mob Attack Hitboxes",
        CurrentValue = Combat.dodgeHitbox == true,
        Flag = "terra_dodge_hitbox",
        Callback = function(value)
            S.setDodgeHitbox(value)
            S.notify("Combat", value and ("Dodge ON — " .. tostring(Combat.dodgeMode)) or "Dodge OFF", 3)
        end,
    })
    Tab:CreateDropdown({
        Name = "Dodge Mode",
        Options = { "Flee", "Above", "Under" },
        CurrentOption = { Combat.dodgeMode },
        MultipleOptions = false,
        Flag = "terra_dodge_mode",
        Callback = function(option)
            local mode = S.resolveDropdownChoice(option)
            if mode ~= "Flee" and mode ~= "Above" and mode ~= "Under" then
                mode = "Flee"
            end
            Combat.dodgeMode = mode
        end,
    })
end

function S.buildKeybindsTab(Window)
    local KeybindsTab = Window:CreateTab("Keybinds")
    KeybindsTab:CreateSection("Toggle Binds")
    KeybindsTab:CreateParagraph({
        Title = "How to use",
        Content = "Unbound by default (shows Unknown). Click a row, press a key to bind. That key toggles the feature.",
    })

    Keybinds.list = {}

    local binds = {
        { name = "Kill Aura", flag = "terra_kill_aura" },
        { name = "Dodge Attack Hitboxes", flag = "terra_dodge_hitbox" },
        { name = "Auto Equip Best Damage", flag = "terra_combat_auto_equip_damage" },
        { name = "Auto Loot", flag = "terra_auto_loot" },
        { name = "Auto Drop Bag After Loot", flag = "terra_auto_drop_loot" },
        { name = "Auto Fuel Drill", flag = "terra_auto_fuel" },
        { name = "Auto Lock Truck Items", flag = "terra_auto_lock_truck" },
        { name = "Auto Equip Pickaxe", flag = "terra_auto_equip_pickaxe" },
        { name = "Auto Mine", flag = "terra_auto_mine" },
        { name = "Speed Hack", flag = "terra_speed" },
        { name = "Fly", flag = "terra_fly" },
        { name = "Noclip", flag = "terra_noclip" },
        { name = "Fullbright", flag = "terra_fullbright" },
        { name = "Auto Buy Upgrades", flag = "terra_auto_upgrades" },
        { name = "Autofarm", flag = "terra_autofarm" },
    }

    for _, bind in ipairs(binds) do
        -- Rayfield crashes on Enum.KeyCode[""] — never pass empty string.
        local settings = KeybindsTab:CreateKeybind({
            Name = bind.name,
            CurrentKeybind = "Unknown",
            HoldToInteract = false,
            Flag = "terra_kb_" .. bind.flag,
            Callback = function(key)
                if type(key) == "string" and (key == "" or key == "None") then
                    if settings and settings.Set then
                        pcall(function()
                            settings:Set("Unknown")
                        end)
                    end
                end
            end,
        })
        table.insert(Keybinds.list, {
            flag = bind.flag,
            settings = settings,
        })
        if settings then
            S.registerRayfieldFlag(settings)
        end
    end

    S.startKeybindListener()
end

function S.buildWorldTab(Window)
    local WorldTab = Window:CreateTab("World")

    WorldTab:CreateSection("Teleport")
    WorldTab:CreateButton({
        Name = "Village",
        Callback = function()
            S.teleportHubToNearest("village")
        end,
    })
    WorldTab:CreateButton({
        Name = "Dungeon",
        Callback = function()
            S.teleportHubToNearest("dungeon")
        end,
    })
    WorldTab:CreateButton({
        Name = "Mine",
        Callback = function()
            S.teleportHubToNearest("mine")
        end,
    })
    WorldTab:CreateButton({
        Name = "Rejoin",
        Callback = function()
            S.rejoinSameServer()
        end,
    })

    WorldTab:CreateSection("Layer Village")
    for _, layer in ipairs(S.WorldLayers) do
        WorldTab:CreateButton({
            Name = layer.label,
            Callback = function()
                S.teleportToLayerVillage(layer)
            end,
        })
    end

    WorldTab:CreateSection("Drill")
    WorldTab:CreateButton({
        Name = "TP to Drill",
        Callback = function()
            if S.teleportToDrillViaVoid() then
                S.notify("Drill", "Sent to void - you respawn at drill", 4)
            else
                S.notify("Drill", "Character not found", 3)
            end
        end,
    })
    WorldTab:CreateToggle({
        Name = "Auto Fuel",
        CurrentValue = false,
        Flag = "terra_auto_fuel",
        Callback = function(value)
            S.setAutoFuel(value)
        end,
    })
    WorldTab:CreateToggle({
        Name = "Auto Drive",
        CurrentValue = AutoDrive.enabled,
        Flag = "terra_auto_drive",
        Callback = function(value)
            S.setAutoDrive(value == true)
        end,
    })
    WorldTab:CreateToggle({
        Name = "Lock Truck (Z)",
        CurrentValue = false,
        Flag = "terra_auto_lock_truck",
        Callback = function(value)
            S.setAutoLockTruck(value)
        end,
    })

    WorldTab:CreateSection("Depth")
    S.bindDepthReadout("drill", WorldTab:CreateSlider({
        Name = "Drill depth",
        Range = { 0, 100000 },
        Increment = 1,
        CurrentValue = 0,
        Flag = "jpax_dtec_drill_depth_m",
        Callback = function() end,
    }))
    S.bindDepthReadout("you", WorldTab:CreateSlider({
        Name = "Your depth",
        Range = { 0, 100000 },
        Increment = 1,
        CurrentValue = 0,
        Flag = "jpax_dtec_player_depth_m",
        Callback = function() end,
    }))
end

function S.buildPlayerTab(Window)
    local PlayerTab = Window:CreateTab("Player")
    PlayerTab:CreateSection("Movement")

    PlayerTab:CreateToggle({
        Name = "Speed Hack",
        CurrentValue = false,
        Flag = "terra_speed",
        Callback = function(value)
            S.setSpeedHack(value)
        end,
    })

    PlayerTab:CreateSlider({
        Name = "Speed Boost",
        Range = { 0, 200 },
        Increment = 5,
        CurrentValue = State.speedBoost,
        Flag = "terra_speed_boost",
        Callback = function(value)
            State.speedBoost = value
            if State.speedHack then
                S.applySpeed()
            end
        end,
    })

    PlayerTab:CreateSlider({
        Name = "Speed Multiplier",
        Range = { 1, 10 },
        Increment = 0.5,
        CurrentValue = State.speedMultiplier,
        Flag = "terra_speed_mult",
        Callback = function(value)
            State.speedMultiplier = value
            if State.speedHack then
                S.applySpeed()
            end
        end,
    })

    PlayerTab:CreateSlider({
        Name = "Jump Power",
        Range = { 50, 200 },
        Increment = 5,
        CurrentValue = State.jumpPower,
        Flag = "terra_jump",
        Callback = function(value)
            State.jumpPower = value
            S.applySpeed()
        end,
    })

    PlayerTab:CreateToggle({
        Name = "Fly",
        CurrentValue = false,
        Flag = "terra_fly",
        Callback = function(value)
            S.setFly(value)
        end,
    })

    PlayerTab:CreateSlider({
        Name = "Fly Speed (IY)",
        Range = { 1, 10 },
        Increment = 0.5,
        CurrentValue = State.flySpeed,
        Flag = "terra_fly_speed",
        Callback = function(value)
            State.flySpeed = value
        end,
    })

    PlayerTab:CreateToggle({
        Name = "Noclip",
        CurrentValue = false,
        Flag = "terra_noclip",
        Callback = function(value)
            S.setNoclip(value)
        end,
    })

    PlayerTab:CreateSection("Visual")

    PlayerTab:CreateToggle({
        Name = "Fullbright",
        CurrentValue = true,
        Flag = "terra_fullbright",
        Callback = function(value)
            S.setFullbright(value)
        end,
    })

    PlayerTab:CreateSection("Actions")

    PlayerTab:CreateButton({
        Name = "Self Revive (Kit / Robux)",
        Callback = function()
            S.requestSelfRevive()
        end,
    })

    PlayerTab:CreateButton({
        Name = "Exit Spectate",
        Callback = function()
            S.safeCall("ExitSpectate", function()
                Services.SpectateService:ExitSpectate()
            end)
        end,
    })

    PlayerTab:CreateSection("Keybinds")
    Keybinds.list = {}
    local binds = {
        { name = "Run", flag = "terra_autofarm" },
        { name = "Kill Aura", flag = "terra_kill_aura" },
        { name = "Auto Loot", flag = "terra_auto_loot" },
        { name = "Speed", flag = "terra_speed" },
        { name = "Fly", flag = "terra_fly" },
        { name = "Noclip", flag = "terra_noclip" },
    }
    for _, bind in ipairs(binds) do
        local settings = PlayerTab:CreateKeybind({
            Name = bind.name,
            CurrentKeybind = "Unknown",
            HoldToInteract = false,
            Flag = "terra_kb_" .. bind.flag,
            Callback = function() end,
        })
        table.insert(Keybinds.list, {
            flag = bind.flag,
            settings = settings,
        })
        if settings then
            S.registerRayfieldFlag(settings)
        end
    end
    S.startKeybindListener()
end

function S.buildConfigTab(Window)
    local ConfigTab = Window:CreateTab("Config")
    ConfigTab:CreateSection("Profiles")

    local initialNames = S.configListNames()
    if #initialNames == 0 then
        table.insert(initialNames, "default")
    end
    if not table.find(initialNames, Config.selectedName) then
        Config.selectedName = initialNames[1]
    end

    S.configLoadAutoloadSettings()

    local configNameInput = ConfigTab:CreateInput({
        Name = "Config Name",
        PlaceholderText = "default",
        RemoveTextAfterFocusLost = false,
        Flag = "jpax_config_name",
        Callback = function(text)
            Config.newName = S.configSanitizeName(text)
            Config.selectedName = Config.newName
        end,
    })
    S.registerRayfieldFlag(configNameInput)

    local configDropdown = ConfigTab:CreateDropdown({
        Name = "Saved Configs",
        Options = initialNames,
        CurrentOption = Config.selectedName,
        Flag = "jpax_config_select",
        Callback = function(option)
            Config.selectedName = S.configSanitizeName(S.resolveDropdownChoice(option))
            Config.newName = Config.selectedName
        end,
    })
    S.registerRayfieldFlag(configDropdown)

    ConfigTab:CreateButton({
        Name = "Refresh List",
        Callback = function()
            local names = S.configRefreshDropdownOptions()
            if #names == 0 then
                S.notify("Config", "No saved configs yet", 3)
            else
                S.notify("Config", "Configs: " .. table.concat(names, ", "), 4)
            end
        end,
    })

    ConfigTab:CreateButton({
        Name = "Create Config",
        Callback = function()
            local name = S.configGetInputName()
            local ok, err = S.configCreateProfile(name)
            if ok then
                local names = S.configRefreshDropdownOptions()
                S.notify("Config", "Created: " .. name .. " (" .. #names .. " total)", 4)
            else
                S.notify("Config", tostring(err), 5)
            end
        end,
    })

    ConfigTab:CreateButton({
        Name = "Save Config",
        Callback = function()
            local name = S.configGetSelectedName()
            local ok, err = S.configSaveProfile(name)
            if ok then
                local names = S.configRefreshDropdownOptions()
                S.notify("Config", "Saved: " .. name .. " (" .. #names .. " total)", 4)
            else
                S.notify("Config", tostring(err), 5)
            end
        end,
    })

    ConfigTab:CreateButton({
        Name = "Load Config",
        Callback = function()
            local name = S.configGetSelectedName()
            local ok, err = S.configLoadProfile(name)
            if ok then
                S.notify("Config", "Loaded: " .. name, 3)
            else
                S.notify("Config", tostring(err), 5)
            end
        end,
    })

    ConfigTab:CreateButton({
        Name = "Delete Config",
        Callback = function()
            local name = S.configGetSelectedName()
            local ok, err = S.configDeleteProfile(name)
            if ok then
                S.notify("Config", "Deleted: " .. name, 3)
            else
                S.notify("Config", tostring(err), 5)
            end
        end,
    })

    ConfigTab:CreateSection("Autoload")

    ConfigTab:CreateParagraph({
        Title = "Default behavior",
        Content = "With Autoload OFF the hub starts on defaults. Select a config and press Load Config when you want.",
    })

    local autoloadToggle = ConfigTab:CreateToggle({
        Name = "Autoload Selected Config",
        CurrentValue = Config.autoloadEnabled,
        Flag = "jpax_config_autoload",
        Callback = function(value)
            S.configSetAutoload(value)
            if value then
                Config.autoloadName = S.configGetSelectedName()
                S.configSaveAutoloadSettings()
                S.notify("Config", "Autoload ON: " .. Config.autoloadName, 3)
            else
                S.notify("Config", "Autoload OFF - next run uses defaults", 3)
            end
        end,
    })
    S.registerRayfieldFlag(autoloadToggle)

    ConfigTab:CreateButton({
        Name = "Set Autoload To Selected",
        Callback = function()
            Config.autoloadName = S.configGetSelectedName()
            S.configSaveAutoloadSettings()
            S.notify("Config", "Autoload target: " .. Config.autoloadName, 3)
        end,
    })

    task.defer(function()
        S.configRefreshDropdownOptions()
    end)
end

function S.coreBootAutoload()
    pcall(S.corePullLoadedFlags)
    if game.PlaceId ~= JPAX.placeId then
        return
    end
    if S.coreToggleOn("dtec_core_open") or CoreFarm.openAll == true then
        if not CoreFarm._runStarted and not CoreFarm._applying then
            CoreFarm.openAll = true
            CoreFarm._ownedRun = true
            S.coreApplyRun()
        end
        return
    end
    if S.coreToggleOn("terra_af_scrap_farm") then
        S.setScrapFarm(true)
        return
    end
    if S.coreToggleOn("terra_autofarm") then
        S.setAutofarm(true)
    end
end

function S.buildUI()
    S._configLoading = true
    S.hubLog("CreateWindow...")
    Autofarm.depthHudVisible = false
    pcall(S.destroyDepthGui)
    local Window = Rayfield:CreateWindow({})

    local function safeTab(name, fn)
        local ok, err = pcall(fn)
        if not ok then
            S.hubLog("TAB FAIL " .. name .. ": " .. tostring(err))
            S.notify("UI", name .. " failed: " .. tostring(err), 8)
        end
    end

    safeTab("Lobby", function()
        S.buildLobbyTab(Window)
    end)
    safeTab("Core", function()
        S.buildCoreTab(Window)
    end)
    safeTab("Farm", function()
    S.buildAutofarmTab(Window)
    end)
    safeTab("Scrap", function()
        S.buildScrapTab(Window)
    end)
    safeTab("Combat", function()
    S.buildCombatTab(Window)
    end)
    safeTab("Auto Combat", function()
        S.buildAutoCombatTab(Window)
    end)
    safeTab("ESP", function()
    S.buildEspTab(Window)
    end)
    safeTab("World", function()
        S.buildWorldTab(Window)
    end)
    safeTab("Player", function()
    S.buildPlayerTab(Window)
    end)
    safeTab("Shop", function()
        S.buildAutoBuyTab(Window)
    end)

    pcall(function()
        if S._jpaxHub and S._jpaxHub.complete then
            S._jpaxHub.complete(S._jpaxWindow, S._jpaxLibrary, S._jpaxSave, S._jpaxTheme, {
                ToggleKeybind = "RightControl",
                Game = JPAX.game,
                Version = JPAX.version,
            })
        end
    end)

    S._configLoading = false
    task.defer(function()
        S._configLoading = false
        pcall(S.coreBootAutoload)
    end)
    S.hubLog("UI ready")
    pcall(function()
        S.setFullbright(true)
        S.trySetRayfieldFlag("terra_fullbright", true, true)
    end)
    S.notify(HUB_NAME, "UI loaded successfully", 5)
    S._uiReady = true
end

task.spawn(function()
    S.hubLog("Waiting for the match...")
    local readyOk, readyErr = S.waitForGameReady()
    S._knitReady = true
    if not readyOk then
        S.hubLog("Match wait: " .. tostring(readyErr))
    end
    S.hubLog("Building UI...")

    local buildOk, buildErr = pcall(S.buildUI)
    if not buildOk then
        S._configLoading = false
        S.hubLog("UI ERROR: " .. tostring(buildErr))
        S.notify(HUB_NAME, "UI error: " .. tostring(buildErr), 10)
        S._uiReady = true
        return
    end

    S.connectServicesAsync()
end)

-- Character respawn hooks
local respawnPlayer = LocalPlayer or Players.LocalPlayer
if respawnPlayer then
respawnPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    if State.connections.speed then
        S.applySpeed()
    end
    if Autofarm.enabled then
        S.setAutofarmPlatformStand(true)
        S.ensureAutofarmAntiFall(true)
        S.lockAutofarmHover(true)
        S.setAutofarmPose(Autofarm.distance or 0)
    elseif game.PlaceId == JPAX.placeId and type(CoreFarm) == "table" and CoreFarm.openAll then
        CoreFarm._applying = false
        CoreFarm._runStarted = false
        task.spawn(function()
            pcall(S.coreApplyRun)
        end)
    end
end)
end

S.hubLog(HUB_NAME .. " started | PlaceId " .. game.PlaceId)

workspace:GetAttributeChangedSignal("InCutScene"):Connect(function()
    if workspace:GetAttribute("InCutScene") == true then
        task.defer(function()
            pcall(S.coreSkipCutscene)
        end)
    end
end)

task.spawn(function()
    while true do
        task.wait(0.25)
        pcall(S.coreSkipCutscene)
    end
end)

function S.coreToggleOn(flagName)
    local flags = Rayfield and Rayfield.Flags
    local flag = flags and flags[flagName]
    if flag and flag._obsidian and flag._obsidian.Value ~= nil then
        return flag._obsidian.Value == true
    end
    if flag and flag.CurrentValue == true then
        return true
    end
    local lib = S._jpaxLibrary
    local toggle = lib and lib.Toggles and lib.Toggles[flagName]
    return toggle ~= nil and toggle.Value == true
end

function S.corePullLoadedFlags()
    local flags = Rayfield and Rayfield.Flags
    if type(flags) ~= "table" then
        return
    end
    if flags.dtec_lobby_auto then
        CoreFarm.enabled = S.coreToggleOn("dtec_lobby_auto")
    end
    local mode = flags.dtec_lobby_mode
    if mode and type(mode.CurrentValue) == "string" then
        CoreFarm.mode = mode.CurrentValue == "Ranked" and "Ranked" or "Unranked"
    end
    local size = flags.dtec_lobby_size
    if size and tonumber(size.CurrentValue) then
        CoreFarm.partySize = math.clamp(math.floor(tonumber(size.CurrentValue)), 1, 8)
    end
    if flags.dtec_core_open then
        CoreFarm.openAll = S.coreToggleOn("dtec_core_open")
    end
    if flags.dtec_core_save_well then
        CoreFarm.saveAtWell = S.coreToggleOn("dtec_core_save_well")
    end
    local rescans = flags.dtec_core_rescan
    if rescans and tonumber(rescans.CurrentValue) then
        CoreFarm.rescans = math.clamp(math.floor(tonumber(rescans.CurrentValue)), 1, 10)
    end
    local dungeon = flags.dtec_core_dungeon
    if dungeon then
        CoreFarm.joinDungeon = dungeon.CurrentValue == true
    end
    local mines = flags.dtec_core_mines
    if mines then
        CoreFarm.joinMines = mines.CurrentValue == true
    end
    local types = flags.dtec_core_chest_types
    local pickedTypes = types and S.chestSelectionList(types.CurrentValue or (types._obsidian and types._obsidian.Value))
    if pickedTypes and #pickedTypes > 0 then
        CoreFarm.chestTypes = pickedTypes
    end
    if flags.dtec_lobby_chest_auto_buy then
        LobbyChestWatch.autoBuy = S.coreToggleOn("dtec_lobby_chest_auto_buy")
    end
    local chestTiers = flags.dtec_lobby_chest_tiers
    local tierPick = chestTiers and S.lobbyChestWatchListFromDropdown(chestTiers.CurrentValue or (chestTiers._obsidian and chestTiers._obsidian.Value))
    if tierPick and #tierPick > 0 then
        LobbyChestWatch.watchTiers = tierPick
    end
end

task.spawn(function()
    while true do
        local waitSec = 1.0
        if LobbyChestWatch.autoBuy then
            waitSec = 0.65
        end
        task.wait(waitSec)
        pcall(S.tickLobbyChestWatch)
    end
end)

task.spawn(function()
    while not S._uiReady do
        task.wait(0.2)
    end
    task.wait(0.4)
    pcall(S.corePullLoadedFlags)
    while true do
        task.wait(1.5)
        if S._configLoading then
            continue
        end
        if game.PlaceId == LOBBY_PLACE and CoreFarm.saveAtWell and CoreFarm._pendingWellSave then
            if not CoreFarm._wellSaving then
                task.spawn(S.coreRunPendingWellSave)
            end
        elseif game.PlaceId == LOBBY_PLACE and not CoreFarm._starting then
            if S.coreToggleOn("dtec_lobby_auto") then
                CoreFarm.enabled = true
                local flags = Rayfield and Rayfield.Flags
                local modeFlag = flags and flags.dtec_lobby_mode
                local modeObs = modeFlag and modeFlag._obsidian
                local modeVal = (modeObs and modeObs.Value) or (modeFlag and modeFlag.CurrentValue)
                if type(modeVal) == "string" then
                    CoreFarm.mode = modeVal == "Ranked" and "Ranked" or "Unranked"
                end
                local sizeFlag = flags and flags.dtec_lobby_size
                local sizeObs = sizeFlag and sizeFlag._obsidian
                local sizeVal = (sizeObs and sizeObs.Value) or (sizeFlag and sizeFlag.CurrentValue)
                if tonumber(sizeVal) then
                    CoreFarm.partySize = math.clamp(math.floor(tonumber(sizeVal)), 1, 8)
                end
            end
            if CoreFarm.enabled then
                if S.corePartyIsLeaving() then
                    CoreFarm._partyStarted = true
                elseif not CoreFarm._partyStarted then
                    task.spawn(function()
                        pcall(S.coreStartLobby)
                    end)
                else
                    local knit = S.getKnit()
                    local ctrl
                    if knit then
                        pcall(function()
                            ctrl = knit.GetController("PartyCreateController")
                        end)
                    end
                    if not ctrl or not ctrl.Zone then
                        CoreFarm._partyStarted = false
                    end
                end
            end
        elseif game.PlaceId == JPAX.placeId then
            if CoreFarm._leaving and os.clock() - (CoreFarm._leavingAt or 0) < 240 then
                -- Laps selesai: sedang terbang ke Church / simpan di Altar / balik lobby.
                -- JANGAN restart farm atau nyalakan lagi Auto Chest dari loop ini.
                Autofarm.openChests = false
            elseif CoreFarm._userStop then
                CoreFarm.openAll = false
                CoreFarm._ownedRun = false
                CoreFarm._runStarted = false
                CoreFarm._applying = false
                if Autofarm.enabled then
                    S.setAutofarm(false)
                end
                if S.coreToggleOn("dtec_core_open") then
                    S.trySetRayfieldFlag("dtec_core_open", false)
                end
                if S.coreToggleOn("terra_autofarm") then
                    S.trySetRayfieldFlag("terra_autofarm", false)
                end
                if not Autofarm.enabled and not S.coreToggleOn("dtec_core_open") and not S.coreToggleOn("terra_autofarm") then
                    CoreFarm._userStop = false
                end
            elseif S.coreToggleOn("dtec_core_open") then
                CoreFarm.openAll = true
            end
            local farmOn = Autofarm.enabled == true and typeof(Autofarm.origin) == "Vector3"
            if CoreFarm._applying and not farmOn and os.clock() - (CoreFarm._applySince or 0) > 5 then
                CoreFarm._applying = false
                CoreFarm._runStarted = false
            end
            if not CoreFarm._userStop and CoreFarm.openAll and not farmOn and not CoreFarm._applying then
                CoreFarm._runStarted = false
                CoreFarm._ownedRun = true
                task.spawn(function()
                    pcall(S.coreApplyRun)
                end)
            elseif CoreFarm.openAll and farmOn then
                pcall(S.coreHoldChestRun)
                pcall(S.coreUnstickRun)
            end
        end
    end
end)
