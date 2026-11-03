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

local function clamp(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
local function rgb(r, g, b) return pc.rgba(clamp(r), clamp(g), clamp(b), 255) end
local function hex(h) return rgb(tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)) end
local function round(v) return math.floor(v + 0.5) end
-- A clipped rectangle fill (the LED chevron's dots run off the tile's edge).
local function rect(img, x0, y0, w, h, c)
  for y = math.max(0, y0), math.min(img.height - 1, y0 + h - 1) do
    for x = math.max(0, x0), math.min(img.width - 1, x0 + w - 1) do img:drawPixel(x, y, c) end
  end
end
-- The design's seeded LCG (same numbers as the concept's canvas recipes).
local function lcg(seed)
  local s = seed
  return function() s = (s * 16807) % 2147483647; return s / 2147483647 end
end

-- cage_mesh_slate.png / cage_mesh_galv.png 32x32 RGBA — the design's
-- chain-link (Arcade Cage Concept 32a): two diagonal wire families -> 16 px
-- diamonds, a light upper edge and a dark lower one; the sides matte slate,
-- the roof rough galvanised with pitting. Tiled 2.5 repeats/m -> 20 cm cells.
local function fence(name, wire, hi, lo, spots)
  local W, H = 32, 32
  local spr = Sprite(W, H, ColorMode.RGBA)
  local img = spr.cels[1].image
  local r = lcg(37)
  fill(img, 0, 0, W - 1, H - 1, pc.rgba(0, 0, 0, 0))
  for yy = 0, H - 1 do
    for xx = 0, W - 1 do
      local u = (xx + yy) % 16
      local v = (xx - yy + 32) % 16
      if not (u > 1 and v > 1) then
        local col = wire
        if u == 0 or v == 0 then col = hi elseif u == 1 and v == 1 then col = lo end
        if spots > 0 and r() < spots then
          if r() < 0.5 then col = lo else col = "#8A8A86" end
        end
        img:drawPixel(xx, yy, hex(col))
      end
    end
  end
  save(spr, name)
end
fence("cage_mesh_slate.png", "#454E58", "#5E6872", "#2C333B", 0)
fence("cage_mesh_galv.png", "#C4C8CC", "#ECEFF2", "#7E8388", 0.08)

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

-- cage_hardwood.png 128x128 — the design's maple court boards (128 px = 1 m):
-- ~9 cm boards along u with staggered butt joints, a few grain streaks per
-- board, a slight tone shift board to board, a dark seam row and a lit edge.
-- Deck and Ramp wear it at 0.68 repeats/m so the boards run down the slope.
do
  local S = 128
  local spr, img = newImage(S, S)
  local r = lcg(53)
  local TONE = {{196, 142, 86}, {184, 130, 76}, {204, 152, 94}, {176, 122, 70}, {192, 138, 82}, {208, 158, 100}, {186, 134, 80}, {198, 146, 88}}
  local boards = {}
  for b = 0, S / 8 - 1 do
    local joints = {}
    local at = math.floor(r() * 64)
    while at < S do joints[#joints + 1] = at; at = at + 48 + math.floor(r() * 56) end
    local grain = {}
    for g = 1, 3 do grain[g] = {1 + math.floor(r() * 6), math.floor(r() * S), 10 + math.floor(r() * 30)} end
    boards[b] = {tone = TONE[math.floor(r() * #TONE) + 1], joints = joints, grain = grain}
  end
  for yy = 0, S - 1 do
    for xx = 0, S - 1 do
      local b = boards[math.floor(yy / 8)]
      local row = yy % 8
      local k = 1 + (r() - 0.5) * 0.05
      if row == 0 then k = 0.55 elseif row == 1 then k = k * 1.08 elseif row == 7 then k = k * 0.9 end
      for _, gr in ipairs(b.grain) do
        if row == gr[1] and ((xx - gr[2] + S) % S) < gr[3] then k = k * 0.86 end
      end
      for _, j in ipairs(b.joints) do if xx == j then k = 0.6 end end
      img:drawPixel(xx, yy, rgb(b.tone[1] * k, b.tone[2] * k, b.tone[3] * k))
    end
  end
  save(spr, "cage_hardwood.png")
end

-- cage_rug.png 32x16 — the hall's dark runner in front of the cabinet row
-- (HallRug, 16 px = 1 m along its length, tiled): a faint diamond weave, a
-- thin orange border.
do
  local W, L = 32, 16
  local spr, img = newImage(W, L)
  for v = 0, L - 1 do
    for u = 0, W - 1 do
      local col = (((u + v) % 8 == 0) or ((u - v + 64) % 8 == 0)) and "#26222E" or "#1A1720"
      if u == 1 or u == W - 2 then col = "#B8562A" elseif u == 0 or u == W - 1 or u == 2 or u == W - 3 then col = "#14121A" end
      img:drawPixel(u, v, hex(col))
    end
  end
  save(spr, "cage_rug.png")
end

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

-- cage_neon_carpet.png 128x128 — the hall floor's blacklight carpet (Ross's
-- "Arcade Cage Concept" 32a, 2026-11-02): near-black with neon specks, squiggles,
-- rings, triangles, squares and plus-stars. A pixel-exact port of the design's
-- canvas code, so the draws keep its order, its seed and JS Math.round. Tiles
-- every 1.6 m; build_cage.py uses it as albedo and emissive map. NEON_DIM turns
-- the coloured specks down from the design's (Ross, 2026-11-02); the base stays.
do
  local S = 128
  local NEON_DIM = 0.8
  local spr, img = newImage(S, S)
  local seed = 911
  local function r()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647
  end
  fill(img, 0, 0, S - 1, S - 1, pc.rgba(7, 6, 12, 255))
  local pile1, pile2 = pc.rgba(20, 16, 30, 255), pc.rgba(14, 11, 22, 255)
  for i = 1, 260 do                                  -- pile texture
    local col = (r() < 0.5) and pile1 or pile2
    local X = math.floor(r() * S)
    local Y = math.floor(r() * S)
    img:drawPixel(X, Y, col)
  end
  local function neon(R, G, B)                       -- the design's neon, turned down
    local D = NEON_DIM
    return pc.rgba(math.floor(R * D + 0.5), math.floor(G * D + 0.5), math.floor(B * D + 0.5), 255)
  end
  local pink, green = neon(255, 46, 154), neon(61, 255, 110)
  local NEON = { pink, green, neon(255, 242, 58), neon(46, 200, 255),
                 neon(255, 138, 30), neon(180, 77, 255), pink, green }
  local function px(X, Y, col)
    img:drawPixel(math.floor(X + 0.5) % S, math.floor(Y + 0.5) % S, col)
  end
  local function pick() return NEON[math.floor(r() * #NEON) + 1] end
  for i = 1, 90 do                                   -- specks + chunky dots
    local col = pick()
    local X = r() * S
    local Y = r() * S
    px(X, Y, col)
    if r() < 0.35 then px(X + 1, Y, col); px(X, Y + 1, col); px(X + 1, Y + 1, col) end
  end
  for i = 1, 8 do                                    -- squiggles
    local col = pick()
    local X = r() * S
    local Y = r() * S
    local L = 9 + r() * 9
    local a = r() * math.pi
    local amp = 1.5 + r() * 1.5
    local f = 0.6 + r() * 0.4
    local t = 0.0
    while t <= L do
      local w = math.sin(t * f) * amp
      px(X + math.cos(a) * t - math.sin(a) * w, Y + math.sin(a) * t + math.cos(a) * w, col)
      t = t + 0.5
    end
  end
  for i = 1, 4 do                                    -- rings
    local col = pick()
    local X = r() * S
    local Y = r() * S
    local R = 2 + math.floor(r() * 2)
    for k = 0, 23 do
      local a = k / 24 * math.pi * 2
      px(X + math.cos(a) * R, Y + math.sin(a) * R, col)
    end
  end
  for i = 1, 3 do                                    -- triangles
    local col = pick()
    local X = math.floor(r() * S)
    local Y = math.floor(r() * S)
    for yy = 0, 3 do
      for xx = -yy, yy do px(X + xx, Y + yy, col) end
    end
  end
  for i = 1, 3 do                                    -- squares / hollow squares
    local col = pick()
    local X = math.floor(r() * S)
    local Y = math.floor(r() * S)
    local hollow = r() < 0.5
    for yy = 0, 2 do
      for xx = 0, 2 do
        if not hollow or yy ~= 1 or xx ~= 1 then px(X + xx, Y + yy, col) end
      end
    end
  end
  for i = 1, 2 do                                    -- little plus-stars
    local col = pick()
    local X = math.floor(r() * S)
    local Y = math.floor(r() * S)
    px(X, Y, col); px(X + 1, Y, col); px(X - 1, Y, col); px(X, Y + 1, col); px(X, Y - 1, col)
  end
  save(spr, "cage_neon_carpet.png")
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

-- cage_neon.png 4x3 — the neon line along the back wall (HallNeon), the same
-- rows cage_hall.png paints: two of orange, one of its glow below.
do
  local W, H = 4, 3
  local spr, img = newImage(W, H)
  fill(img, 0, 0, W - 1, 1, pc.rgba(220, 90, 50, 255))
  fill(img, 0, 2, W - 1, 2, pc.rgba(70, 30, 20, 255))
  save(spr, "cage_neon.png")
end


-- cage_pad.png 32x32 — the design's open-cell foam over the egg-crate pad:
-- a near-white speckle with pores and a few bright cells, pre-multiplied by
-- the pad's charcoal #3A3532 (three.js multiplied the texture over the
-- material colour; Godot gets the product). Mapped from position
-- (build_cage.py add_pad world_uv 0.45) so it runs across the pyramids.
do
  local T = 32
  local spr, img = newImage(T, T)
  local r = lcg(91)
  for i = 0, T * T - 1 do
    local v = 214 + (r() - 0.5) * 34
    local n = r()
    if n < 0.24 then v = v - (60 + r() * 40) elseif n > 0.94 then v = 255 end
    v = math.max(0, math.min(255, math.floor(v / 12 + 0.5) * 12))
    local f = v / 255
    img:drawPixel(i % T, math.floor(i / T), rgb(58 * f, 53 * f, 50 * f))
  end
  save(spr, "cage_pad.png")
end

-- cage_arrow.png 64x64 RGBA — the design's LED chevron (DeckArrow%02dL/R
-- decals, lit in succession by ArcadeFx.chase()): a dark housing with two
-- rows of nine LED dots, the tip toward -u (the shooter). The dim / lit
-- state is the shader's (deck_arrow.gdshader): white cores read as the lit
-- LEDs under its glow.
do
  local S = 64
  local spr = Sprite(S, S, ColorMode.RGBA)
  local img = spr.cels[1].image
  fill(img, 0, 0, S - 1, S - 1, pc.rgba(0, 0, 0, 0))
  local function chev(t, off)
    local v = (t < 0.5) and (t * 2) or ((1 - t) * 2)
    return 50 - off - v * 26, 6 + t * 52
  end
  for i = 0, 60 do local u, v = chev(i / 60, 0); rect(img, round(u) - 5, round(v) - 3, 17, 7, hex("#1C1A1A")) end
  for i = 0, 60 do local u, v = chev(i / 60, 0); rect(img, round(u) - 4, round(v) - 2, 15, 5, hex("#2E2A28")) end
  for _, off in ipairs({0, 7}) do
    for i = 0, 8 do
      local u, v = chev(i / 8, off)
      local U, V = round(u), round(v)
      rect(img, U - 2, V - 2, 4, 4, hex("#9A9A9A"))
      rect(img, U - 1, V - 1, 2, 2, hex("#FFFFFF"))
    end
  end
  save(spr, "cage_arrow.png")
end

