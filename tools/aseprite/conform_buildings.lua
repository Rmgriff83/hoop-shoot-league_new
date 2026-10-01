-- Conform Sam Grady's Low Poly Buildings Pack atlas (art/third_party/buildings,
-- CC BY 4.0) for the city court: assets/textures/city_facades.png (the atlas
-- as PNG, the pure-blue padding filled with a neutral wall grey so a stray UV
-- never shows blue). Deterministic. (The window mask / id maps and their
-- shader were removed 2026-10-01: the window lights lagged the phone.)
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
