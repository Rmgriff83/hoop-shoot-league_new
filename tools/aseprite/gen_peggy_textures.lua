-- PEGGY, the locker's drop machine (docs/LOCKER.md): the cabinet's skins for
-- tools/blender/build_peggy.py, plus the UI's ticket icon. Deterministic hash
-- noise (no math.random) so rebuilds are byte-identical.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_peggy_textures.lua

local ROOT = app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2))))
local OUT = app.fs.joinPath(ROOT, "assets/textures")
local UI = app.fs.joinPath(ROOT, "assets/ui")
local pc = app.pixelColor

local function noise(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + seed * 982451653) % 2147483647
  n = (n * n * 15731 + n * 789221 + 1376312589) % 2147483647
  return (n % 1000) / 1000.0
end

local function newImage(w, h, rgba)
  local spr = Sprite(w, h, rgba and ColorMode.RGBA or ColorMode.RGB)
  return spr, spr.cels[1].image
end

local function clamp(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
local function rgb(r, g, b, a) return pc.rgba(clamp(r), clamp(g), clamp(b), a or 255) end

local function fill(img, x0, y0, x1, y1, c)
  for y = math.max(0, y0), math.min(img.height - 1, y1) do
    for x = math.max(0, x0), math.min(img.width - 1, x1) do
      img:drawPixel(x, y, c)
    end
  end
end

local function save(spr, dir, name)
  spr:saveCopyAs(app.fs.joinPath(dir, name))
  print("wrote " .. name)
end

local RED = {179, 38, 30}
local RED_DK = {128, 24, 20}
local CREAM = {241, 232, 208}
local INK = {26, 22, 24}
local GOLD = {240, 184, 74}
local NAVY = {27, 36, 64}
local TIER = {
  common = {184, 174, 150}, rare = {127, 174, 198}, epic = {232, 112, 58}, legend = {240, 184, 74},
}

-- A 3x5 pixel font for the few words the cabinet carries.
local FONT = {
  A = {"010", "101", "111", "101", "101"}, C = {"011", "100", "100", "100", "011"},
  D = {"110", "101", "101", "101", "110"}, E = {"111", "100", "110", "100", "111"},
  G = {"011", "100", "101", "101", "011"}, I = {"111", "010", "010", "010", "111"},
  L = {"100", "100", "100", "100", "111"}, M = {"101", "111", "111", "101", "101"},
  N = {"110", "101", "101", "101", "101"}, O = {"010", "101", "101", "101", "010"},
  P = {"110", "101", "110", "100", "100"}, R = {"110", "101", "110", "101", "101"},
  Y = {"101", "101", "010", "010", "010"}, T = {"111", "010", "010", "010", "010"},
  K = {"101", "101", "110", "101", "101"}, S = {"011", "100", "010", "001", "110"},
}

local function text(img, s, x0, y0, scale, c)
  local x = x0
  for i = 1, #s do
    local ch = s:sub(i, i)
    local g = FONT[ch]
    if g then
      for row = 1, 5 do
        for col = 1, 3 do
          if g[row]:sub(col, col) == "1" then
            fill(img, x + (col - 1) * scale, y0 + (row - 1) * scale,
                 x + col * scale - 1, y0 + row * scale - 1, c)
          end
        end
      end
    end
    x = x + 4 * scale
  end
  return x - x0 - scale
end

local function text_w(s, scale) return #s * 4 * scale - scale end

-- peggy_cabinet.png 128x256 — red panels with a cream trim band, a little grain.
do
  local W, H = 128, 256
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 501) * 14 - 7
      local v = (y % 64 < 4 or x % 64 < 4) and 1 or 0
      local c = v == 1 and CREAM or RED
      img:drawPixel(x, y, rgb(c[1] + n, c[2] + n * 0.8, c[3] + n * 0.6))
    end
  end
  save(spr, OUT, "peggy_cabinet.png")
end

-- peggy_marquee.png 256x64 — PEGGY in cream pixel caps on red, a gold bulb border.
do
  local W, H = 256, 64
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 511) * 10 - 5
      img:drawPixel(x, y, rgb(RED[1] + n, RED[2] + n * 0.6, RED[3] + n * 0.6))
    end
  end
  fill(img, 0, 0, W - 1, 3, rgb(CREAM[1], CREAM[2], CREAM[3]))
  fill(img, 0, H - 4, W - 1, H - 1, rgb(CREAM[1], CREAM[2], CREAM[3]))
  local s = 8
  local w = text_w("PEGGY", s)
  local x0 = math.floor((W - w) / 2)
  text(img, "PEGGY", x0 + 3, 15, s, rgb(RED_DK[1], RED_DK[2], RED_DK[3]))
  text(img, "PEGGY", x0, 12, s, rgb(CREAM[1], CREAM[2], CREAM[3]))
  for x = 10, W - 10, 18 do
    fill(img, x - 2, 5, x + 1, 8, rgb(GOLD[1], GOLD[2], GOLD[3]))
    fill(img, x - 2, H - 9, x + 1, H - 6, rgb(GOLD[1], GOLD[2], GOLD[3]))
  end
  save(spr, OUT, "peggy_marquee.png")
end

-- peggy_board.png 128x128 — navy with a cream dot grid at the peg pitch.
do
  local W, H = 128, 128
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 521) * 10 - 5
      img:drawPixel(x, y, rgb(NAVY[1] + n, NAVY[2] + n, NAVY[3] + n))
    end
  end
  for y = 8, H - 1, 16 do
    for x = 8, W - 1, 16 do
      fill(img, x - 1, y - 1, x, y, rgb(96, 104, 140))
    end
  end
  save(spr, OUT, "peggy_board.png")
end

-- peggy_button_up.png / peggy_button_down.png 32x32 — the red dome's cap.
for _, state in ipairs({"up", "down"}) do
  local W, H = 32, 32
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local dx, dy = (x + 0.5 - 16) / 16, (y + 0.5 - 16) / 16
      local d = math.sqrt(dx * dx + dy * dy)
      local c
      if d > 0.97 then c = INK
      elseif d > 0.86 then c = RED_DK
      else
        local hl = state == "up" and math.max(0, 1 - math.sqrt((dx + 0.35) ^ 2 + (dy + 0.35) ^ 2) * 2.2) or 0
        c = {RED[1] + 30 + hl * 60, RED[2] + 10 + hl * 50, RED[3] + 8 + hl * 40}
        if state == "down" then c = {RED[1] - 20, RED[2] - 6, RED[3] - 4} end
      end
      img:drawPixel(x, y, rgb(c[1], c[2], c[3]))
    end
  end
  save(spr, OUT, "peggy_button_" .. state .. ".png")
end

-- peggy_ticket.png 48x24 — a cream stub: gold band, perforations, TICKET.
do
  local W, H = 48, 24
  local spr, img = newImage(W, H)
  fill(img, 0, 0, W - 1, H - 1, rgb(INK[1], INK[2], INK[3]))
  fill(img, 1, 1, W - 2, H - 2, rgb(CREAM[1], CREAM[2], CREAM[3]))
  fill(img, 1, 1, W - 2, 4, rgb(GOLD[1], GOLD[2], GOLD[3]))
  fill(img, 1, H - 5, W - 2, H - 2, rgb(GOLD[1], GOLD[2], GOLD[3]))
  for y = 2, H - 3, 3 do
    img:drawPixel(10, y, rgb(INK[1], INK[2], INK[3]))
    img:drawPixel(W - 11, y, rgb(INK[1], INK[2], INK[3]))
  end
  text(img, "TKT", 14, 9, 2, rgb(INK[1], INK[2], INK[3]))
  save(spr, OUT, "peggy_ticket.png")
end

-- peggy_plate_<rarity>.png 48x24 — the slot plate in the tier colour.
for _, r in ipairs({"common", "rare", "epic", "legend"}) do
  local W, H = 48, 24
  local spr, img = newImage(W, H)
  local c = TIER[r]
  fill(img, 0, 0, W - 1, H - 1, rgb(INK[1], INK[2], INK[3]))
  fill(img, 1, 1, W - 2, H - 2, rgb(c[1], c[2], c[3]))
  fill(img, 1, 1, W - 2, 1, rgb(c[1] + 40, c[2] + 40, c[3] + 40))
  local label = r:upper()
  local s = 2
  local w = text_w(label, s)
  text(img, label, math.floor((W - w) / 2), 7, s, rgb(INK[1], INK[2], INK[3]))
  save(spr, OUT, "peggy_plate_" .. r .. ".png")
end

-- peggy_plate_refund.png — the ticket glyph plate ("+150" is drawn in 3D text).
do
  local W, H = 48, 24
  local spr, img = newImage(W, H)
  fill(img, 0, 0, W - 1, H - 1, rgb(INK[1], INK[2], INK[3]))
  fill(img, 1, 1, W - 2, H - 2, rgb(70, 66, 72))
  text(img, "TKTS", 8, 7, 2, rgb(GOLD[1], GOLD[2], GOLD[3]))
  save(spr, OUT, "peggy_plate_refund.png")
end

-- peggy_light.png 16x4 — a warm bulb strip over each slot.
do
  local spr, img = newImage(16, 4)
  for y = 0, 3 do
    for x = 0, 15 do
      local v = (y == 0 or y == 3) and 0.7 or 1.0
      img:drawPixel(x, y, rgb(255 * v, 232 * v, 170 * v))
    end
  end
  save(spr, OUT, "peggy_light.png")
end

-- icon_ticket.png 22x14 (RGBA) — the UI's ticket: a gold stub with notches.
do
  local W, H = 22, 14
  local spr, img = newImage(W, H, true)
  fill(img, 0, 0, W - 1, H - 1, pc.rgba(0, 0, 0, 0))
  local ink = rgb(INK[1], INK[2], INK[3])
  local gold = rgb(GOLD[1], GOLD[2], GOLD[3])
  local hi = rgb(250, 220, 140)
  fill(img, 1, 1, W - 2, H - 2, ink)
  fill(img, 2, 2, W - 3, H - 3, gold)
  fill(img, 2, 2, W - 3, 2, hi)
  -- side notches
  for _, x in ipairs({0, 1, W - 2, W - 1}) do
    fill(img, x, 5, x, 8, pc.rgba(0, 0, 0, 0))
  end
  fill(img, 2, 5, 2, 8, ink); fill(img, W - 3, 5, W - 3, 8, ink)
  -- perforation
  for y = 3, H - 4, 2 do
    img:drawPixel(7, y, ink); img:drawPixel(W - 8, y, ink)
  end
  save(spr, UI, "icon_ticket.png")
end
