-- Skins for the city court's chain-net hoop (tools/blender/build_chain_hoop.py).
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_chain_hoop_textures.lua
-- hoop_chain.png: a diamond lattice of steel links (the nylon net's layout,
-- so NetSim's cords are the same, but every cord is a run of link ovals).
-- city_board.png: a white perforated-steel board with a red target square
-- (the West 4th kind). The rim reuses hoop_rim.png. Deterministic.

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
  for y = math.max(0, y0), math.min(img.height - 1, y1) do
    for x = math.max(0, x0), math.min(img.width - 1, x1) do
      img:drawPixel(x, y, c)
    end
  end
end

local function save(spr, name)
  spr:saveCopyAs(app.fs.joinPath(OUT, name))
  print("wrote " .. name)
end

-- hoop_chain.png 64x48 RGBA — the nylon lattice's diagonals ((x+y)%16 and
-- (x-y)%16) drawn as steel links: 3 px wide runs with a bright top edge, a
-- dark underside and a 1 px gap every 6 px so each cord reads as a chain.
do
  local W, H = 64, 48
  local spr, img = newImage(W, H)
  local none = pc.rgba(0, 0, 0, 0)
  local hi = pc.rgba(232, 236, 240, 255)
  local mid = pc.rgba(170, 176, 186, 255)
  local lo = pc.rgba(92, 98, 108, 255)
  fill(img, 0, 0, W - 1, H - 1, none)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local a = (x + y) % 16
      local b = (x - y) % 16
      local on_a = a <= 2
      local on_b = b <= 2
      if on_a or on_b then
        -- link gaps: a bite out of every sixth pixel along the run
        local along = on_a and (x - y) or (x + y)
        if along % 6 ~= 5 then
          local shade = (on_a and a or b)
          local c = (shade == 0) and hi or ((shade == 1) and mid or lo)
          img:drawPixel(x, y, c)
        end
      end
    end
  end
  save(spr, "hoop_chain.png")
end

-- city_board.png 384x224 — 1.83 x 1.05 m (~210 px/m). White perforated
-- steel: a 4 px hole grid over off-white, a grey 12 px frame, a red 0.59 x
-- 0.45 m target square 0.15 m up from the bottom, rust specks near the rim.
do
  local W, H = 384, 224
  local spr, img = newImage(W, H)
  local frame = pc.rgba(112, 118, 128, 255)
  local red = pc.rgba(214, 58, 44, 255)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local v = 226 + noise(x // 3, y // 3, 301) * 14
      local hole = (x % 8 == 3 or x % 8 == 4) and (y % 8 == 3 or y % 8 == 4)
      if hole then v = v - 60 end
      local rust = noise(x, y, 302)
      if rust > 0.985 then
        img:drawPixel(x, y, pc.rgba(150, 90, 50, 255))
      else
        img:drawPixel(x, y, pc.rgba(math.floor(v), math.floor(v), math.floor(v - 4), 255))
      end
    end
  end
  fill(img, 0, 0, W - 1, 11, frame); fill(img, 0, H - 12, W - 1, H - 1, frame)
  fill(img, 0, 0, 11, H - 1, frame); fill(img, W - 12, 0, W - 1, H - 1, frame)
  local sq_w, sq_h = math.floor(0.59 / 1.83 * W + 0.5), math.floor(0.45 / 1.05 * H + 0.5)
  local bottom = H - 1 - math.floor(0.15 / 1.05 * H + 0.5)
  local top = bottom - sq_h + 1
  local left = math.floor((W - sq_w) / 2)
  local right = left + sq_w - 1
  fill(img, left, top, right, top + 5, red); fill(img, left, bottom - 5, right, bottom, red)
  fill(img, left, top, left + 5, bottom, red); fill(img, right - 5, top, right, bottom, red)
  save(spr, "city_board.png")
end
