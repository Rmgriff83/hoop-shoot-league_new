-- Power-up card textures. Only card_back.png (the empty / unknown fallback)
-- is generated here now: the real faces (card_ice.png, card_fire7.png,
-- card_vortex6.png) and their sprite loops (fx_*.png) come from the design
-- project's "Card Icons" export (docs/CARDS.md → Art) and are checked in.
-- 96x128, pixel art in the game's palette.
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

-- glyph_vortex.png 14x14 RGBA (assets/ui/cards) — the Vortex card's small
-- glyph for the tray tag and the deal caption: a teal funnel, wide at the
-- top, with a pale spiral band. Sits beside glyph_fire / glyph_ice from the
-- design export.
do
  local W, H = 14, 14
  local spr = Sprite(W, H, ColorMode.RGB)
  local img = spr.cels[1].image
  local none = pc.rgba(0, 0, 0, 0)
  local teal = pc.rgba(46, 150, 132, 255)
  local dark = pc.rgba(24, 84, 74, 255)
  local pale = pc.rgba(214, 240, 232, 255)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      img:drawPixel(x, y, none)
    end
  end
  -- funnel: half-width shrinks from 6 at y=1 to 1 at y=12
  for y = 1, 12 do
    local hw = math.floor(6 - (y - 1) * 5 / 11 + 0.5)
    for x = 7 - hw, 6 + hw do
      local band = ((x + y * 2) % 5 == 0)
      img:drawPixel(x, y, band and pale or teal)
    end
    img:drawPixel(7 - hw, y, dark)
    img:drawPixel(6 + hw, y, dark)
  end
  -- the cloud lip
  for x = 1, 12 do img:drawPixel(x, 0, pale) end
  img:drawPixel(7, 13, dark)
  local out_ui = app.fs.joinPath(app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2)))), "assets/ui/cards")
  app.fs.makeDirectory(out_ui)
  spr:saveCopyAs(app.fs.joinPath(out_ui, "glyph_vortex.png"))
  print("wrote glyph_vortex.png")
end
