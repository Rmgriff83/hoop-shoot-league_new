-- Power-up card fronts (game/screens/league_hub_screen.gd LOADOUT/SHOP tabs,
-- the in-heat card tray and the card toast). 96x128 each, pixel art in the
-- game's palette. One block per card id in data/cards.json.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_card_textures.lua
local OUT = app.fs.joinPath(app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2)))), "assets/textures/cards")
local pc = app.pixelColor
app.fs.makeDirectory(OUT)

local function newImage(w, h)
  local spr = Sprite(w, h, ColorMode.RGB)
  return spr, spr.cels[1].image
end
local function save(spr, name)
  spr:saveCopyAs(app.fs.joinPath(OUT, name))
  print("wrote " .. name)
end
local function hash(x, y, s)
  local h = (x * 374761393 + y * 668265263 + s * 1442695041) % 2147483647
  h = (h ~ (h >> 13)) * 1274126177 % 2147483647
  return (h % 1000) / 1000
end

-- Shared card frame: rounded dark plate, double border in the card's colour,
-- a title band at the bottom.
local function frame(img, W, H, border, plate)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local ex = math.min(x, W - 1 - x)
      local ey = math.min(y, H - 1 - y)
      local corner = (ex < 3 and ey < 3) and ((ex == 0 and ey < 2) or (ey == 0 and ex < 2) or (ex == 0 and ey == 0))
      if corner then
        img:drawPixel(x, y, pc.rgba(0, 0, 0, 0))
      elseif ex <= 1 or ey <= 1 then
        img:drawPixel(x, y, border)
      elseif ex == 3 or ey == 3 then
        img:drawPixel(x, y, pc.rgba(pc.rgbaR(border) // 2 + 40, pc.rgbaG(border) // 2 + 40, pc.rgbaB(border) // 2 + 40, 255))
      else
        img:drawPixel(x, y, plate)
      end
    end
  end
  -- title band
  for y = H - 26, H - 5 do
    for x = 5, W - 6 do
      img:drawPixel(x, y, pc.rgba(18, 20, 30, 255))
    end
  end
end

-- 3x5 pixel font for the title band (2x3 blocks, 8 px advance; space = gap).
local FONT = {
  F = {"###", "#..", "##.", "#..", "#.."}, R = {"##.", "#.#", "##.", "#.#", "#.#"},
  E = {"###", "#..", "##.", "#..", "###"}, Z = {"###", "..#", ".#.", "#..", "###"},
  I = {"###", ".#.", ".#.", ".#.", "###"}, H = {"#.#", "#.#", "###", "#.#", "#.#"},
  A = {".#.", "#.#", "###", "#.#", "#.#"}, T = {"###", ".#.", ".#.", ".#.", ".#."},
  ["0"] = {"###", "#.#", "#.#", "#.#", "###"}, ["1"] = {".#.", "##.", ".#.", ".#.", "###"},
  ["2"] = {"###", "..#", "###", "#..", "###"}, ["3"] = {"###", "..#", "###", "..#", "###"},
  ["4"] = {"#.#", "#.#", "###", "..#", "..#"}, ["5"] = {"###", "#..", "###", "..#", "###"},
  ["6"] = {"###", "#..", "###", "#.#", "###"}, ["7"] = {"###", "..#", ".#.", ".#.", ".#."},
  ["8"] = {"###", "#.#", "###", "#.#", "###"}, ["9"] = {"###", "#.#", "###", "..#", "###"},
}
local function title(img, W, H, text, colour)
  local x0 = (W - #text * 8) // 2 + 1
  for i = 1, #text do
    local g = FONT[text:sub(i, i)]
    if g then
      for r = 1, 5 do
        for c = 1, 3 do
          if g[r]:sub(c, c) == "#" then
            local px, py = x0 + (i - 1) * 8 + (c - 1) * 2, H - 22 + (r - 1) * 3
            for yy = 0, 2 do for xx = 0, 1 do img:drawPixel(px + xx, py + yy, colour) end end
          end
        end
      end
    end
  end
end

-- Target badge in the top-right corner: red disc + arrow = played against the
-- opponent; green disc + plus = a boost for yourself.
local function badge(img, W, kind)
  local cx, cy = W - 13, 13
  local fill = (kind == "self") and pc.rgba(60, 185, 95, 255) or pc.rgba(225, 60, 50, 255)
  local ring = pc.rgba(14, 16, 24, 255)
  for y = cy - 8, cy + 8 do
    for x = cx - 8, cx + 8 do
      local d = (x - cx) * (x - cx) + (y - cy) * (y - cy)
      if d <= 36 then img:drawPixel(x, y, fill)
      elseif d <= 56 then img:drawPixel(x, y, ring) end
    end
  end
  local white = pc.rgba(255, 255, 255, 255)
  if kind == "self" then
    for k = -3, 3 do
      img:drawPixel(cx + k, cy, white); img:drawPixel(cx + k, cy - 1, white)
      img:drawPixel(cx, cy + k, white); img:drawPixel(cx - 1, cy + k, white)
    end
  else
    for k = -4, 2 do img:drawPixel(cx + k, cy, white); img:drawPixel(cx + k, cy - 1, white) end
    for st = 0, 2 do
      img:drawPixel(cx + 3 - st, cy - 1 - st, white); img:drawPixel(cx + 3 - st, cy + st, white)
      img:drawPixel(cx + 2 - st, cy - 1 - st, white); img:drawPixel(cx + 2 - st, cy + st, white)
    end
  end
end

-- card_ice.png — Deep Freeze: a frosted rim with a jagged ice ring, snowflake glints.
do
  local W, H = 96, 128
  local spr, img = newImage(W, H)
  local border = pc.rgba(150, 215, 255, 255)
  frame(img, W, H, border, pc.rgba(22, 40, 70, 255))
  -- cold gradient sky in the art window
  for y = 6, H - 30 do
    for x = 6, W - 7 do
      local t = (y - 6) / (H - 36)
      local r = math.floor(20 + 30 * (1 - t))
      local g = math.floor(48 + 70 * (1 - t))
      local b = math.floor(90 + 90 * (1 - t))
      img:drawPixel(x, y, pc.rgba(r, g, b, 255))
    end
  end
  -- rim: an ellipse ring, orange steel frosted white on top
  local cx, cy = 48, 62
  for y = 6, H - 30 do
    for x = 6, W - 7 do
      local dx = (x - cx) / 30
      local dy = (y - cy) / 12
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 0.86 and d < 1.0 then
        img:drawPixel(x, y, pc.rgba(235, 90, 40, 255))
      end
    end
  end
  -- ice ring: jagged pale slab sitting on the rim, reaching inward
  for y = 6, H - 30 do
    for x = 6, W - 7 do
      local dx = (x - cx) / 30
      local dy = (y - cy + 3) / 12
      local ang = math.atan(dy, dx)
      local jag = 0.10 * math.sin(ang * 7) + 0.06 * math.sin(ang * 13 + 1)
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 0.55 + jag and d < 1.02 then
        local n = hash(x, y, 3)
        local v = 200 + math.floor(55 * n)
        img:drawPixel(x, y, pc.rgba(v - 30, v, 255, 255))
      end
    end
  end
  -- icicles hanging below the rim
  for i, ix in ipairs({30, 44, 58, 70}) do
    local len = 6 + (i % 3) * 3
    for k = 0, len do
      local w = math.max(0, 2 - k // 3)
      for x = ix - w, ix + w do
        img:drawPixel(x, cy + 12 + k, pc.rgba(190, 230, 255, 255))
      end
    end
  end
  -- sparkles
  for _, p in ipairs({{20, 20}, {74, 16}, {84, 40}, {14, 48}, {62, 30}}) do
    local x, y = p[1], p[2]
    img:drawPixel(x, y, pc.rgba(255, 255, 255, 255))
    img:drawPixel(x - 1, y, pc.rgba(220, 240, 255, 255))
    img:drawPixel(x + 1, y, pc.rgba(220, 240, 255, 255))
    img:drawPixel(x, y - 1, pc.rgba(220, 240, 255, 255))
    img:drawPixel(x, y + 1, pc.rgba(220, 240, 255, 255))
  end
  title(img, W, H, "FREEZE", border)
  badge(img, W, "opponent")
  save(spr, "card_ice.png")
end

-- card_fire7.png — Heat Check: the rim ablaze, flames licking up, embers.
do
  local W, H = 96, 128
  local spr, img = newImage(W, H)
  local border = pc.rgba(255, 170, 60, 255)
  frame(img, W, H, border, pc.rgba(70, 30, 14, 255))
  -- warm dusk gradient in the art window
  for y = 6, H - 30 do
    for x = 6, W - 7 do
      local t = (y - 6) / (H - 36)
      img:drawPixel(x, y, pc.rgba(math.floor(50 + 40 * t), math.floor(16 + 18 * t), math.floor(12 + 6 * t), 255))
    end
  end
  local cx, cy = 48, 70
  -- flames: tongues rising from the rim line, yellow at the base to red tips
  for x = 14, W - 15 do
    local u = (x - 14) / (W - 29)
    local hgt = 12 + 18 * math.abs(math.sin(u * 9.4 + 0.6)) + 8 * math.abs(math.sin(u * 23.0)) + 6 * hash(x, 0, 5)
    local base = cy - 3 + math.floor(4 * math.sin(u * 3.14159))
    for y = math.floor(base - hgt), base do
      local k = (base - y) / hgt
      local n = hash(x, y, 7)
      if n > k * 0.55 then
        local col
        if k < 0.3 then col = pc.rgba(255, 235, 110, 255)
        elseif k < 0.6 then col = pc.rgba(255, 160, 40, 255)
        elseif k < 0.85 then col = pc.rgba(230, 80, 25, 255)
        else col = pc.rgba(170, 40, 20, 255) end
        img:drawPixel(x, y, col)
      end
    end
  end
  -- embers drifting up
  for _, p in ipairs({{22, 18}, {70, 14}, {80, 30}, {30, 10}, {58, 22}, {40, 26}, {86, 46}}) do
    img:drawPixel(p[1], p[2], pc.rgba(255, 210, 90, 255))
    img:drawPixel(p[1] + 1, p[2] + 1, pc.rgba(230, 120, 40, 255))
  end
  -- rim: an ellipse ring, glowing steel
  for y = 6, H - 30 do
    for x = 6, W - 7 do
      local dx = (x - cx) / 30
      local dy = (y - cy) / 12
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 0.86 and d < 1.0 then
        img:drawPixel(x, y, (y < cy) and pc.rgba(255, 140, 60, 255) or pc.rgba(235, 90, 40, 255))
      end
    end
  end
  -- net hint below the rim
  for k = 0, 12 do
    for _, nx in ipairs({28, 40, 56, 68}) do
      local x = nx + ((nx < cx) and k // 3 or -(k // 3))
      if k % 2 == 0 then img:drawPixel(x, cy + 12 + k, pc.rgba(230, 220, 200, 255)) end
    end
  end
  title(img, W, H, "FIRE 7", border)
  badge(img, W, "self")
  save(spr, "card_fire7.png")
end

-- card_back.png — a generic back for empty slots / unknown cards.
do
  local W, H = 96, 128
  local spr, img = newImage(W, H)
  frame(img, W, H, pc.rgba(120, 125, 150, 255), pc.rgba(30, 32, 44, 255))
  for y = 8, H - 32 do
    for x = 8, W - 9 do
      if (x + y) % 8 == 0 or (x - y) % 8 == 0 then
        img:drawPixel(x, y, pc.rgba(50, 54, 72, 255))
      end
    end
  end
  save(spr, "card_back.png")
end
