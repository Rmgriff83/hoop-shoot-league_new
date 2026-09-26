-- Pixel-art skins for the arcade cage arena (tools/blender/build_cage.py).
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_cage_textures.lua
-- Deterministic hash noise (no math.random) so rebuilds are byte-identical.
-- Palette: classic arcade — black steel, red-orange accents (the rim's family),
-- cream + warm-bulb marquee, charcoal deck, muted brown/amber hall. No neon.

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

-- cage_mesh.png 64x64 RGBA — chain-link lattice, 16 px diamond cells.
-- Two-pixel light cords with a darker lower edge; everything else transparent
-- (Godot alpha-scissors it). Tiled 2 repeats/m → 8 cm cells.
do
  local W, H = 64, 64
  local spr, img = newImage(W, H)
  local clear = pc.rgba(0, 0, 0, 0)
  local cord  = pc.rgba(176, 172, 164, 255)
  local dark  = pc.rgba(98, 94, 90, 255)
  fill(img, 0, 0, W - 1, H - 1, clear)
  local CELL = 16
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local u, v = x % CELL, y % CELL
      -- Two diagonals per cell: v == u and v == CELL-1-u (plus a 1 px neighbour).
      local d1 = (v == u) or (v == u + 1)
      local d2 = (v == CELL - 1 - u) or (v == CELL - u)
      if d1 or d2 then
        img:drawPixel(x, y, cord)
      end
    end
  end
  -- Darker lower edge: any cord pixel whose neighbour below is clear.
  for y = 0, H - 2 do
    for x = 0, W - 1 do
      if img:getPixel(x, y) == cord and img:getPixel(x, y + 1) == clear then
        img:drawPixel(x, y, dark)
      end
    end
  end
  save(spr, "cage_mesh.png")
end

-- cage_tube.png 32x8 — cool steel band wrapping the frame boxes.
do
  local spr, img = newImage(32, 8)
  local hi  = pc.rgba(96, 96, 100, 255)
  local mid = pc.rgba(44, 44, 48, 255)
  local sh  = pc.rgba(18, 18, 20, 255)
  fill(img, 0, 0, 31, 1, hi)
  fill(img, 0, 2, 31, 5, mid)
  fill(img, 0, 6, 31, 7, sh)
  for x = 0, 31 do
    if noise(x, 0, 21) < 0.12 then img:drawPixel(x, 3, hi) end
  end
  save(spr, "cage_tube.png")
end

-- cage_deck.png / cage_ramp.png 128x128 — rubber tread with two orange
-- chevrons per tile pointing toward -u (the shooter). The ramp variant is a
-- lighter gray so the raised return reads against the dark back panel.
local function tread(name, rubber, dot, dip)
  local W, H = 128, 128
  local spr, img = newImage(W, H)
  local yellow = pc.rgba(236, 110, 48, 255)   -- orange chevrons (rim family)
  local ydark  = pc.rgba(160, 70, 30, 255)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local c = rubber
      if (x % 4 == 0) and (y % 4 == 0) then c = dot end
      if noise(x, y, 31) < 0.03 then c = dip end
      img:drawPixel(x, y, c)
    end
  end
  -- Chevrons: apex at x = 20 and x = 84, arms sweep back (toward +u) 24 px.
  for _, apex in ipairs({20, 84}) do
    for i = 0, 24 do
      for t = 0, 3 do
        local x = apex + i
        local yu = 64 - i - t
        local yd = 64 + i + t
        if x < W then
          img:drawPixel(x, yu, (t == 3) and ydark or yellow)
          img:drawPixel(x, yd, (t == 3) and ydark or yellow)
        end
      end
    end
  end
  save(spr, name)
end
tread("cage_deck.png", pc.rgba(36, 34, 34, 255), pc.rgba(48, 46, 45, 255), pc.rgba(26, 24, 24, 255))
tread("cage_ramp.png", pc.rgba(78, 74, 72, 255), pc.rgba(92, 88, 86, 255), pc.rgba(62, 58, 56, 255))

-- cage_carpet.png 128x128 — navy 90s arcade carpet with dithered confetti.
do
  local W, H = 128, 128
  local spr, img = newImage(W, H)
  local navy    = pc.rgba(40, 22, 20, 255)    -- dark maroon carpet
  local navy2   = pc.rgba(46, 26, 23, 255)
  local magenta = pc.rgba(150, 60, 40, 255)   -- rust
  local cyan    = pc.rgba(190, 140, 60, 255)  -- amber
  local yellow  = pc.rgba(120, 90, 50, 255)   -- tan
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 41)
      local c = navy
      if ((x + y) % 2 == 0) then c = navy2 end
      img:drawPixel(x, y, c)
    end
  end
  -- Sparse 2x2 confetti (dense 1 px specks shimmer badly at distance).
  for y = 0, H - 2, 2 do
    for x = 0, W - 2, 2 do
      local n = noise(x, y, 45)
      local c = nil
      if n > 0.994 then c = magenta
      elseif n > 0.989 then c = cyan
      elseif n > 0.985 then c = yellow end
      if c ~= nil then fill(img, x, y, x + 1, y + 1, c) end
    end
  end
  -- A few 3-px squiggles so it reads as a pattern, not static.
  for i = 0, 23 do
    local sx = math.floor(noise(i, 7, 43) * (W - 4))
    local sy = math.floor(noise(i, 9, 43) * (H - 4))
    local col = (i % 3 == 0) and magenta or ((i % 3 == 1) and cyan or yellow)
    img:drawPixel(sx, sy, col); img:drawPixel(sx + 1, sy + 1, col); img:drawPixel(sx + 2, sy + 1, col)
  end
  save(spr, "cage_carpet.png")
end

-- cage_hall.png 256x64 — black hall wall with six arcade cabinets in
-- silhouette (glowing screens) and a neon line along the top. Tiled 4x.
do
  local W, H = 256, 64
  local spr, img = newImage(W, H)
  local black  = pc.rgba(8, 6, 6, 255)
  local wall   = pc.rgba(22, 18, 18, 255)
  local cab    = pc.rgba(34, 30, 30, 255)
  local cab2   = pc.rgba(50, 42, 40, 255)
  local cyan   = pc.rgba(230, 170, 70, 255)   -- amber screens
  local mag    = pc.rgba(220, 90, 50, 255)    -- orange screens
  local glow   = pc.rgba(70, 50, 24, 255)
  local glowm  = pc.rgba(70, 30, 20, 255)
  fill(img, 0, 0, W - 1, H - 1, wall)
  fill(img, 0, H - 2, W - 1, H - 1, black)          -- skirting
  fill(img, 0, 4, W - 1, 5, mag)                    -- neon line
  fill(img, 0, 6, W - 1, 6, glowm)
  for i = 0, 5 do
    local x0 = 4 + i * 42
    local cw = 36
    local top = 14 + ((i % 2 == 0) and 0 or 3)
    fill(img, x0, top, x0 + cw - 1, H - 3, cab)
    fill(img, x0 + 2, top + 2, x0 + cw - 3, top + 4, cab2)          -- marquee slab
    local sc = (i % 2 == 0) and cyan or mag
    local gl = (i % 2 == 0) and glow or glowm
    fill(img, x0 + 4, top + 7, x0 + cw - 5, top + 20, gl)           -- screen glow
    fill(img, x0 + 6, top + 9, x0 + cw - 7, top + 18, sc)           -- screen
    for y = top + 9, top + 18 do
      for x = x0 + 6, x0 + cw - 7 do
        if noise(x, y, 51 + i) < 0.35 then img:drawPixel(x, y, gl) end
      end
    end
    fill(img, x0 + 4, top + 24, x0 + cw - 5, top + 25, cab2)        -- control panel
  end
  save(spr, "cage_hall.png")
end

