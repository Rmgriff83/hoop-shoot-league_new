-- Chalkboard face for the beach league board (game/view/league_banner.gd,
-- chalk style): dark slate with chalk-dust smears and streaks, a worn wooden
-- frame, and a chalk tray along the bottom. 512x320.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_chalkboard.lua
local OUT = app.fs.joinPath(app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2)))), "assets/textures")
local pc = app.pixelColor
local function hash(x, y, s)
  local h = (x * 374761393 + y * 668265263 + s * 1442695041) % 2147483647
  h = (h ~ (h >> 13)) * 1274126177 % 2147483647
  return (h % 1000) / 1000
end
local function vnoise(x, y, s)   -- smooth value noise
  local xi, yi = math.floor(x), math.floor(y)
  local fx, fy = x - xi, y - yi
  fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
  local a, b = hash(xi, yi, s), hash(xi + 1, yi, s)
  local c, d = hash(xi, yi + 1, s), hash(xi + 1, yi + 1, s)
  return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy
end
local W, H = 512, 320
local FRAME = 14
local spr = Sprite(W, H, ColorMode.RGB)
local img = spr.cels[1].image
for y = 0, H - 1 do
  for x = 0, W - 1 do
    local ex, ey = math.min(x, W - 1 - x), math.min(y, H - 1 - y)
    local e = math.min(ex, ey)
    if e < FRAME then
      -- wooden frame: warm brown with grain along the long axis
      local along = (ex < ey) and y or x
      local grain = vnoise(along / 9.0, e / 3.0, 5) * 0.35 + vnoise(along / 37.0, e / 5.0, 6) * 0.65
      local shade = 0.75 + 0.4 * grain
      if e < 2 or e > FRAME - 3 then shade = shade * 0.7 end   -- bevel edges
      img:drawPixel(x, y, pc.rgba(math.floor(96 * shade), math.floor(64 * shade), math.floor(38 * shade), 255))
    else
      -- slate: dark green-black, faint dust, a few diagonal wipe streaks
      local dust = vnoise(x / 28.0, y / 22.0, 1) * 0.6 + vnoise(x / 7.0, y / 6.0, 2) * 0.4
      local wipe = 0.5 + 0.5 * math.sin((x * 0.6 + y * 1.1) / 23.0 + vnoise(x / 60.0, y / 60.0, 3) * 4.0)
      local v = 0.06 + 0.11 * dust * wipe
      local r = math.floor(28 + 70 * v)
      local g = math.floor(44 + 90 * v)
      local b = math.floor(38 + 80 * v)
      if hash(x, y, 9) > 0.992 then r, g, b = r + 40, g + 40, b + 38 end   -- chalk specks
      img:drawPixel(x, y, pc.rgba(r, g, b, 255))
    end
  end
end
-- chalk tray: a lighter wooden ledge just above the bottom frame with two chalk sticks
for y = H - FRAME - 10, H - FRAME - 1 do
  for x = FRAME + 20, W - FRAME - 21 do
    local shade = 0.9 + 0.2 * vnoise(x / 15.0, 0, 7)
    img:drawPixel(x, y, pc.rgba(math.floor(120 * shade), math.floor(84 * shade), math.floor(50 * shade), 255))
  end
end
for _, cx in ipairs({W * 0.42, W * 0.58}) do
  for y = H - FRAME - 9, H - FRAME - 6 do
    for x = math.floor(cx), math.floor(cx) + 22 do
      img:drawPixel(x, y, pc.rgba(238, 236, 226, 255))
    end
  end
end
spr:saveCopyAs(app.fs.joinPath(OUT, "chalkboard.png"))
print("wrote chalkboard.png")
