-- Pixel-art skins for the Blender hoop assembly (tools/blender/build_hoop.py).
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_hoop_textures.lua
-- Palette matches gen_placeholders.lua so the court stays one style.

local OUT = app.fs.joinPath(app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2)))), "assets/textures")
local pc = app.pixelColor

local function noise(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + seed * 982451653) % 2147483647
  n = (n * n * 15731 + n * 789221 + 1376312589) % 2147483647
  return (n % 1000) / 1000.0
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

-- hoop_board.png 128x80 — front face of the 1.22 x 0.76 m junior board (~105 px/m).
-- Shooter square 0.59 x 0.45 m with its bottom edge at rim height (0.15 m up).
do
  local W, H = 128, 80
  local spr, img = newImage(W, H)
  local white = pc.rgba(240, 244, 248, 255)
  local grain = pc.rgba(230, 235, 242, 255)
  local trim  = pc.rgba(120, 130, 150, 255)
  local red   = pc.rgba(230, 60, 50, 255)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      img:drawPixel(x, y, (noise(x, y, 11) < 0.08) and grain or white)
    end
  end
  fill(img, 0, 0, W - 1, 2, trim); fill(img, 0, H - 3, W - 1, H - 1, trim)
  fill(img, 0, 0, 2, H - 1, trim); fill(img, W - 3, 0, W - 1, H - 1, trim)
  local sq_w, sq_h = math.floor(0.59 / 1.22 * W + 0.5), math.floor(0.45 / 0.76 * H + 0.5)
  local bottom = H - 1 - math.floor(0.15 / 0.76 * H + 0.5)
  local top = bottom - sq_h + 1
  local left = math.floor((W - sq_w) / 2)
  local right = left + sq_w - 1
  fill(img, left, top, right, top + 2, red); fill(img, left, bottom - 2, right, bottom, red)
  fill(img, left, top, left + 2, bottom, red); fill(img, right - 2, top, right, bottom, red)
  save(spr, "hoop_board.png")
end

-- hoop_rim.png 32x8 — wraps the rim tube: highlight on top, shadow underneath.
do
  local spr, img = newImage(32, 8)
  for y = 0, 7 do
    local c
    if y < 2 then c = pc.rgba(255, 120, 90, 255)
    elseif y < 6 then c = pc.rgba(255, 93, 61, 255)
    else c = pc.rgba(205, 65, 40, 255) end
    for x = 0, 31 do img:drawPixel(x, y, c) end
  end
  save(spr, "hoop_rim.png")
end

-- hoop_net.png 64x48 — transparent diamond lattice that simply ends at the
-- bottom (no solid cord: on the model that read as a white ring under the hoop).
do
  local W, H = 64, 48
  local spr, img = newImage(W, H)
  -- 2 px bright cords so the net reads against dusk skies and the dim cage.
  local cord = pc.rgba(255, 255, 255, 255)
  local none = pc.rgba(0, 0, 0, 0)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local a = (x + y) % 16
      local b = (x - y) % 16
      local on = (a == 0 or a == 1) or (b == 0 or b == 1)
      img:drawPixel(x, y, on and cord or none)
    end
  end
  save(spr, "hoop_net.png")
end

-- hoop_led_off.png 192x32 — 48x8 LED matrix, every LED off (dim dark red dots).
do
  local W, H = 192, 32
  local spr, img = newImage(W, H)
  local bg = pc.rgba(12, 10, 14, 255)
  local off = pc.rgba(40, 10, 10, 255)
  fill(img, 0, 0, W - 1, H - 1, bg)
  for r = 0, 7 do
    for c = 0, 47 do
      fill(img, c * 4, r * 4, c * 4 + 2, r * 4 + 2, off)
    end
  end
  save(spr, "hoop_led_off.png")
end

-- hoop_band.png 64x4 — light-strip segments: white where lit (tinted at runtime).
do
  local spr, img = newImage(64, 4)
  local seg = pc.rgba(255, 255, 255, 255)
  local gap = pc.rgba(30, 30, 34, 255)
  for y = 0, 3 do
    for x = 0, 63 do
      img:drawPixel(x, y, (x % 8 < 6) and seg or gap)
    end
  end
  save(spr, "hoop_band.png")
end
