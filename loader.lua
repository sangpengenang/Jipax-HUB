-- LOADER: link ke file ini yang kamu bagikan. Jangan perlu diubah lagi.
local BASE = "https://raw.githubusercontent.com/sangpengenang/Jipax-HUB/main/"

local HttpService = game:GetService("HttpService")

local function fetch(path)
    local safePath = path:gsub(" ", "%%20")
    local ok, body = pcall(function()
        return game:HttpGet(BASE .. safePath, true)
    end)
    if ok and type(body) == "string" and #body > 0 then
        return body
    end
    return nil
end

-- 1. Ambil daftar game
local raw = fetch("games.json")
if not raw then
    warn("[Loader] Gagal mengambil games.json")
    return
end
local okJson, games = pcall(function()
    return HttpService:JSONDecode(raw)
end)
if not okJson or type(games) ~= "table" then
    warn("[Loader] games.json tidak valid")
    return
end

-- 2. Cari script yang cocok (cek GameId dulu, lalu PlaceId)
local file = games[tostring(game.GameId)] or games[tostring(game.PlaceId)]
if not file then
    warn("[Loader] Game ini belum didukung. GameId: " .. tostring(game.GameId))
    return
end

-- 3. Unduh dan jalankan
local code = fetch(file)
if not code then
    warn("[Loader] Gagal mengunduh " .. file)
    return
end
local fn, err = loadstring(code)
if not fn then
    warn("[Loader] Error pada " .. file .. ": " .. tostring(err))
    return
end
fn()
