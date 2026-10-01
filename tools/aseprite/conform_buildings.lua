-- Conform Sam Grady's Low Poly Buildings Pack atlas (art/third_party/buildings,
-- CC BY 4.0) for the city court: assets/textures/city_facades.png (the atlas
-- as PNG, the pure-blue padding filled with a neutral wall grey so a stray UV
-- never shows blue), city_facades_lit.png (a WINDOW MASK: white = a pane the
-- windows.gdshader may light at dusk) and city_facades_id.png (one id per
-- window, R + 256 G), both from the authored WINDOWS table. Deterministic.
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

-- city_facades_lit.png + city_facades_id.png: the windows, AUTHORED. The
-- atlas is an 8 x 8 grid of 32 px tiles and its windows are 5-25 px wide:
-- too small for a darkness test to tell glass from a lintel's shadow, so
-- every pane is a rectangle in this table (atlas px: x, y, w, h), read off
-- the atlas at 4x. One rectangle = one window = one id in the shader.
local WINDOWS = {
  -- RECTANGULAR windows only: the arched ones (the ornate stone column, the
  -- tall arch, the col-5 arch) sit under curved frames the glow cannot follow.
  -- col 0: the shop at the foot (the tall dark window above it and col 1's
  -- tall black one are mapped off their frames on the models — left dark)
  {5, 230, 25, 20},
  -- col 1: a plain window, a curtained one
  {42, 10, 12, 18}, {40, 100, 14, 15},
  -- col 2: a small one, the industrial row, a small one
  {75, 104, 11, 13}, {69, 163, 18, 15}, {75, 229, 12, 11},
  -- col 3 / 4: windows, the industrial row's other two panes
  {104, 10, 13, 18}, {108, 104, 9, 13}, {140, 104, 10, 13}, {100, 163, 25, 15}, {132, 163, 23, 15},
  -- col 4 / 5: the stained glass at the foot
  {130, 228, 27, 24}, {162, 228, 28, 24},
  -- col 5: the tall blue strip, the teal shop front
  {172, 98, 8, 50}, {165, 163, 25, 17}, {165, 195, 25, 25},
  -- col 6 / 7: a small square window, the blue strip, the shop fronts
  {200, 75, 15, 8}, {202, 105, 8, 20}, {197, 135, 13, 15}, {212, 135, 38, 15}, {197, 165, 58, 25}, {193, 198, 62, 24},
}
local label = {}
for i, r in ipairs(WINDOWS) do
  for y = r[2], r[2] + r[4] - 1 do
    for x = r[1], r[1] + r[3] - 1 do
      if x >= 0 and x < W and y >= 0 and y < H then label[y * W + x] = i end
    end
  end
end
local mask = Sprite(W, H, ColorMode.RGB)
local mimg = mask.cels[1].image
local panes = 0
for y = 0, H - 1 do
  for x = 0, W - 1 do
    local id = label[y * W + x] or 0
    if id > 0 then panes = panes + 1 end
    mimg:drawPixel(x, y, id > 0 and pc.rgba(255, 255, 255, 255) or pc.rgba(0, 0, 0, 255))
  end
end
print(string.format("windows: %d authored, pane pixels %d", #WINDOWS, panes))
save(mask, "city_facades_lit.png")
local ids = Sprite(W, H, ColorMode.RGB)
local iimg = ids.cels[1].image
for y = 0, H - 1 do
  for x = 0, W - 1 do
    local id = label[y * W + x] or 0
    iimg:drawPixel(x, y, pc.rgba(id % 256, id // 256, 0, 255))
  end
end
save(ids, "city_facades_id.png")
