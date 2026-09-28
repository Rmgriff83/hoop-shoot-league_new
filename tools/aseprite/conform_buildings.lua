-- Conform Sam Grady's Low Poly Buildings Pack atlas (art/third_party/buildings,
-- CC BY 4.0) for the city court: assets/textures/city_facades.png (the atlas
-- as PNG, the pure-blue padding filled with a neutral wall grey so a stray UV
-- never shows blue) and city_facades_lit.png (a WINDOW MASK derived from it:
-- facade pixels darker than their 8x8 block's mean, outside the railing and
-- padding regions, cleaned to whole 4x4 cells — white = a pane the
-- windows.gdshader may light at dusk). Deterministic, no math.random.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/conform_buildings.lua

local ROOT = app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2))))
local SRC = app.fs.joinPath(ROOT, "art/third_party/buildings")
local OUT = app.fs.joinPath(ROOT, "assets/textures")
local pc = app.pixelColor

local function save(spr, name)
  spr:saveCopyAs(app.fs.joinPath(OUT, name))
  print("wrote " .. name)
end

local diffuse = Sprite{ fromFile = app.fs.joinPath(SRC, "diffuse_.jpg") }
local alpha = Sprite{ fromFile = app.fs.joinPath(SRC, "alpha_.jpg") }
local W, H = diffuse.width, diffuse.height
local img = Image(diffuse.cels[1].image)
if img.colorMode ~= ColorMode.RGB then
  app.command.ChangePixelFormat{ format = "rgb" }
  img = Image(diffuse.cels[1].image)
end
local aimg = Image(alpha.cels[1].image)

local function lum(c) return 0.299 * pc.rgbaR(c) + 0.587 * pc.rgbaG(c) + 0.114 * pc.rgbaB(c) end
local function is_pad(c) return pc.rgbaR(c) < 60 and pc.rgbaG(c) < 60 and pc.rgbaB(c) > 180 end
local function is_railing(x, y)
  local a = aimg:getPixel(x, y)
  return lum(a) < 128
end

-- city_facades.png: the atlas, padding filled.
local out = Sprite(W, H, ColorMode.RGB)
local oimg = out.cels[1].image
for y = 0, H - 1 do
  for x = 0, W - 1 do
    local c = img:getPixel(x, y)
    if is_pad(c) then c = pc.rgba(122, 118, 112, 255) end
    oimg:drawPixel(x, y, pc.rgba(pc.rgbaR(c), pc.rgbaG(c), pc.rgbaB(c), 255))
  end
end
save(out, "city_facades.png")

-- city_facades_lit.png: the window mask.
local BLOCK, CELL = 8, 4
local mask = Sprite(W, H, ColorMode.RGB)
local mimg = mask.cels[1].image
local dark = {}
for by = 0, H / BLOCK - 1 do
  for bx = 0, W / BLOCK - 1 do
    local sum, n = 0, 0
    for y = by * BLOCK, by * BLOCK + BLOCK - 1 do
      for x = bx * BLOCK, bx * BLOCK + BLOCK - 1 do
        local c = img:getPixel(x, y)
        if not is_pad(c) then sum = sum + lum(c); n = n + 1 end
      end
    end
    local mean = n > 0 and sum / n or 0
    for y = by * BLOCK, by * BLOCK + BLOCK - 1 do
      for x = bx * BLOCK, bx * BLOCK + BLOCK - 1 do
        local c = img:getPixel(x, y)
        local l = lum(c)
        dark[y * W + x] = (not is_pad(c)) and (not is_railing(x, y)) and l < mean * 0.72 and l < 105
      end
    end
  end
end
local panes = 0
for cy = 0, H / CELL - 1 do
  for cx = 0, W / CELL - 1 do
    local n = 0
    for y = cy * CELL, cy * CELL + CELL - 1 do
      for x = cx * CELL, cx * CELL + CELL - 1 do
        if dark[y * W + x] then n = n + 1 end
      end
    end
    local on = n >= CELL * CELL / 2
    if on then panes = panes + 1 end
    for y = cy * CELL, cy * CELL + CELL - 1 do
      for x = cx * CELL, cx * CELL + CELL - 1 do
        mimg:drawPixel(x, y, on and pc.rgba(255, 255, 255, 255) or pc.rgba(0, 0, 0, 255))
      end
    end
  end
end
print(string.format("window cells: %d of %d", panes, (W / CELL) * (H / CELL)))
save(mask, "city_facades_lit.png")
