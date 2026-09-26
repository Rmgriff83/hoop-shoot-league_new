-- Skin for the street hoop's regulation board (tools/blender/build_street_hoop.py).
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_street_hoop_textures.lua
-- Dark graphite board (contrast against the white net), pale frame, orange
-- shooter square. Rim and net reuse hoop_rim.png / hoop_net.png. Deterministic.

local OUT = app.fs.joinPath(app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2)))), "assets/textures")
local pc = app.pixelColor

local function noise(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + seed * 982451653) % 2147483647
  n = (n * n * 15731 + n * 789221 + 1376312589) % 2147483647
  return (n % 1000) / 1000.0
end

local function vnoise(x, y, cell, seed)
  local gx, gy = x / cell, y / cell
  local x0, y0 = math.floor(gx), math.floor(gy)
  local fx, fy = gx - x0, gy - y0
  fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
  local a, b = noise(x0, y0, seed), noise(x0 + 1, y0, seed)
  local c, d = noise(x0, y0 + 1, seed), noise(x0 + 1, y0 + 1, seed)
  local top = a + (b - a) * fx
  return top + ((c + (d - c) * fx) - top) * fy
end

local function newImage(w, h)
  local spr = Sprite(w, h, ColorMode.RGB)
  return spr, spr.cels[1].image
end

local function fill(img, x0, y0, x1, y1, c)
  for y = y0, y1 do
    for x = x0, x1 do
      img:drawPixel(x, y, c)
    end
  end
end

local function save(spr, name)
  spr:saveCopyAs(app.fs.joinPath(OUT, name))
  print("wrote " .. name)
end

-- street_board.png 384x224 — 1.83 x 1.05 m (~210 px/m). Graphite face with a
-- faint sheen, 12 px pale frame + 3 px seam, orange 0.59 x 0.45 m shooter
-- square whose bottom edge is 0.15 m above the board bottom.
do
  local W, H = 384, 224
  local spr, img = newImage(W, H)
  local frame = pc.rgba(226, 228, 232, 255)
  local seam  = pc.rgba(120, 126, 136, 255)
  local red   = pc.rgba(236, 96, 44, 255)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local sheen = vnoise(x, y, 48, 61) * 12 + (1 - y / H) * 6
      local v = 46 + sheen
      img:drawPixel(x, y, pc.rgba(math.floor(v), math.floor(v + 3), math.floor(v + 9), 255))
    end
  end
  fill(img, 0, 0, W - 1, 11, frame); fill(img, 0, H - 12, W - 1, H - 1, frame)
  fill(img, 0, 0, 11, H - 1, frame); fill(img, W - 12, 0, W - 1, H - 1, frame)
  fill(img, 12, 12, W - 13, 14, seam); fill(img, 12, H - 15, W - 13, H - 13, seam)
  fill(img, 12, 12, 14, H - 13, seam); fill(img, W - 15, 12, W - 13, H - 13, seam)
  local sq_w, sq_h = math.floor(0.59 / 1.83 * W + 0.5), math.floor(0.45 / 1.05 * H + 0.5)
  local bottom = H - 1 - math.floor(0.15 / 1.05 * H + 0.5)
  local top = bottom - sq_h + 1
  local left = math.floor((W - sq_w) / 2)
  local right = left + sq_w - 1
  fill(img, left, top, right, top + 5, red); fill(img, left, bottom - 5, right, bottom, red)
  fill(img, left, top, left + 5, bottom, red); fill(img, right - 5, top, right, bottom, red)
  save(spr, "street_board.png")
end
