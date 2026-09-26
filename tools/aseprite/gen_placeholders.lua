-- Placeholder texture generator for Hoop Shoot.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_placeholders.lua
-- Every sprite here is a stand-in at final size: hand-drawn art later replaces
-- the PNG at the same path/dimensions with zero scene changes.

local OUT = app.fs.joinPath(app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2)))), "assets/textures")
local pc = app.pixelColor

-- Deterministic tiny hash noise (no math.random — reproducible builds).
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

-- ball.png 32x32 — orange ball, black seams (visible seams make backspin readable).
do
  local spr, img = newImage(32, 32)
  local cx, cy, r = 15.5, 15.5, 15.0
  local orange = pc.rgba(255, 138, 61, 255)
  local dark = pc.rgba(200, 95, 35, 255)
  local seam = pc.rgba(40, 24, 16, 255)
  for y = 0, 31 do
    for x = 0, 31 do
      local dx, dy = x - cx, y - cy
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= r then
        local c = orange
        if dy > 4 and d > 10 then c = dark end -- cheap bottom shading
        -- seams: vertical, horizontal, two side arcs
        if math.abs(dx) < 1.0 or math.abs(dy) < 1.0 then c = seam end
        local ad = math.abs(math.sqrt((dx * 1.6) * (dx * 1.6) + dy * dy) - 14)
        if ad < 0.9 then c = seam end
        if d > r - 1.2 then c = seam end -- outline
        img:drawPixel(x, y, c)
      end
    end
  end
  save(spr, "ball.png")
end

-- rim.png 16x16 — orange-red band with shading (wraps the torus).
do
  local spr, img = newImage(16, 16)
  for y = 0, 15 do
    for x = 0, 15 do
      local c
      if y < 3 then c = pc.rgba(255, 120, 90, 255)
      elseif y < 10 then c = pc.rgba(255, 93, 61, 255)
      else c = pc.rgba(205, 65, 40, 255) end
      img:drawPixel(x, y, c)
    end
  end
  save(spr, "rim.png")
end

-- backboard.png 96x64 — white board, gray trim, red shooter square.
do
  local spr, img = newImage(96, 64)
  local white = pc.rgba(240, 244, 248, 255)
  local trim = pc.rgba(120, 130, 150, 255)
  local red = pc.rgba(230, 60, 50, 255)
  fill(img, 0, 0, 95, 63, white)
  -- outer trim
  fill(img, 0, 0, 95, 2, trim)
  fill(img, 0, 61, 95, 63, trim)
  fill(img, 0, 0, 2, 63, trim)
  fill(img, 93, 0, 95, 63, trim)
  -- shooter square: centered horizontally, lower half (rim sits at its bottom edge)
  local sx0, sy0, sx1, sy1 = 33, 30, 62, 55
  fill(img, sx0, sy0, sx1, sy0 + 2, red)
  fill(img, sx0, sy1 - 2, sx1, sy1, red)
  fill(img, sx0, sy0, sx0 + 2, sy1, red)
  fill(img, sx1 - 2, sy0, sx1, sy1, red)
  save(spr, "backboard.png")
end

-- net.png 32x32 — transparent with white diagonal cross-hatch.
do
  local spr, img = newImage(32, 32)
  local cord = pc.rgba(235, 235, 235, 220)
  for y = 0, 31 do
    for x = 0, 31 do
      if (x + y) % 8 == 0 or (x - y) % 8 == 0 then
        img:drawPixel(x, y, cord)
      end
    end
  end
  save(spr, "net.png")
end

-- court_floor.png 128x128 — maple planks.
do
  local spr, img = newImage(128, 128)
  for y = 0, 127 do
    local plank = math.floor(y / 16)
    for x = 0, 127 do
      local base = (plank % 2 == 0) and { 255, 206, 138 } or { 242, 190, 120 }
      local n = noise(x, plank, 7) * 14 - 7
      local c = pc.rgba(
        math.max(0, math.min(255, base[1] + n)),
        math.max(0, math.min(255, base[2] + n * 0.8)),
        math.max(0, math.min(255, base[3] + n * 0.6)), 255)
      if y % 16 == 15 then c = pc.rgba(196, 150, 95, 255) end -- plank seam
      -- staggered butt joints
      local joint = (math.floor(x / 64) + plank * 37) % 2
      if x % 64 == (joint * 32) % 64 and x % 64 < 1 then c = pc.rgba(196, 150, 95, 255) end
      img:drawPixel(x, y, c)
    end
  end
  save(spr, "court_floor.png")
end

-- crowd_wall.png 128x64 — dark arcade backdrop with dithered glow dots.
do
  local spr, img = newImage(128, 64)
  for y = 0, 63 do
    for x = 0, 127 do
      local c = pc.rgba(38, 44, 66, 255)
      local n = noise(x, y, 21)
      if n > 0.965 then c = pc.rgba(90, 100, 140, 255)
      elseif n > 0.93 then c = pc.rgba(60, 68, 98, 255) end
      if y > 58 then c = pc.rgba(30, 35, 52, 255) end
      img:drawPixel(x, y, c)
    end
  end
  save(spr, "crowd_wall.png")
end

-- ui_panel.png 48x48 — cream 9-slice panel with navy border.
do
  local spr, img = newImage(48, 48)
  local cream = pc.rgba(255, 248, 235, 255)
  local navy = pc.rgba(53, 64, 92, 255)
  fill(img, 0, 0, 47, 47, cream)
  fill(img, 0, 0, 47, 2, navy)
  fill(img, 0, 45, 47, 47, navy)
  fill(img, 0, 0, 2, 47, navy)
  fill(img, 45, 0, 47, 47, navy)
  -- knock out corners for a rounded read
  img:drawPixel(0, 0, pc.rgba(0, 0, 0, 0))
  img:drawPixel(47, 0, pc.rgba(0, 0, 0, 0))
  img:drawPixel(0, 47, pc.rgba(0, 0, 0, 0))
  img:drawPixel(47, 47, pc.rgba(0, 0, 0, 0))
  save(spr, "ui_panel.png")
end

-- banner_strip.png 64x24 — navy strip, mint border (transient banner background).
do
  local spr, img = newImage(64, 24)
  local navy = pc.rgba(53, 64, 92, 235)
  local mint = pc.rgba(67, 217, 163, 255)
  fill(img, 0, 0, 63, 23, navy)
  fill(img, 0, 0, 63, 1, mint)
  fill(img, 0, 22, 63, 23, mint)
  save(spr, "banner_strip.png")
end

print("placeholder textures done")
