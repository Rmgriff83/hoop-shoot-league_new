-- Soft particle sprites for the rim fire (game/view/rim_fire.gd).
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_fx_textures.lua
local OUT = app.fs.joinPath(app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2)))), "assets/textures")
local pc = app.pixelColor

local function newImage(w, h)
  local spr = Sprite(w, h, ColorMode.RGB)
  return spr, spr.cels[1].image
end
local function save(spr, name)
  spr:saveCopyAs(app.fs.joinPath(OUT, name))
  print("wrote " .. name)
end

-- fx_flame.png 32x32 — white teardrop, bright core, soft alpha edge (tinted by the ramp).
do
  local W, H = 32, 32
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local dx = (x + 0.5 - 16) / 12
      local dy = (y + 0.5 - 19) / 15
      -- narrower toward the top (teardrop)
      local squeeze = 1.0 + math.max(0, -dy) * 0.9
      local d = math.sqrt((dx * squeeze) ^ 2 + dy ^ 2)
      local a = math.max(0, 1 - d)
      a = a * a
      local v = 200 + 55 * math.min(1, a * 1.6)
      img:drawPixel(x, y, pc.rgba(255, v, math.floor(v * 0.8), math.floor(255 * a + 0.5)))
    end
  end
  save(spr, "fx_flame.png")
end

-- fx_smoke.png 32x32 — soft round puff.
do
  local W, H = 32, 32
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local dx = (x + 0.5 - 16) / 15
      local dy = (y + 0.5 - 16) / 15
      local d = math.sqrt(dx * dx + dy * dy)
      local a = math.max(0, 1 - d)
      a = a * a * (3 - 2 * a)
      img:drawPixel(x, y, pc.rgba(230, 230, 234, math.floor(255 * a + 0.5)))
    end
  end
  save(spr, "fx_smoke.png")
end
