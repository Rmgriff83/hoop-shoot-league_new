-- Hand-sized UI icons the design project does not ship (docs/HOME.md):
-- icon_lock.png (the area archive's locked areas). Deterministic.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_ui_icons.lua

local ROOT = app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2))))
local UI = app.fs.joinPath(ROOT, "assets/ui")
local pc = app.pixelColor

local function fill(img, x0, y0, x1, y1, c)
  for y = math.max(0, y0), math.min(img.height - 1, y1) do
    for x = math.max(0, x0), math.min(img.width - 1, x1) do
      img:drawPixel(x, y, c)
    end
  end
end

-- icon_lock.png 30x36 RGBA (drawn at 60x72): a cream padlock — a shackle
-- arch, a body with a dark keyhole, ink outlines.
do
  local W, H = 30, 36
  local spr = Sprite(W, H, ColorMode.RGBA)
  local img = spr.cels[1].image
  local none = pc.rgba(0, 0, 0, 0)
  local ink = pc.rgba(34, 28, 24, 255)
  local cream = pc.rgba(241, 232, 208, 255)
  local shade = pc.rgba(205, 191, 156, 255)
  fill(img, 0, 0, W - 1, H - 1, none)
  -- shackle: outer arch 20 wide, 4 thick, from y 0 to 16
  for y = 0, 15 do
    for x = 5, 24 do
      local dx = (x - 14.5) / 10
      local dy = (y - 10) / 10
      local d = math.sqrt(dx * dx + dy * dy)
      local on = (y <= 10 and d <= 1.0 and d >= 0.52) or (y > 10 and (x <= 9 or x >= 20))
      if on then
        local edge = (y <= 10 and (d > 0.9 or d < 0.62)) or (y > 10 and (x == 5 or x == 9 or x == 20 or x == 24))
        img:drawPixel(x, y, edge and ink or cream)
      end
    end
  end
  -- body: 30x20 at y 16, ink outline, cream face, a shaded right edge
  fill(img, 0, 16, W - 1, H - 1, ink)
  fill(img, 2, 18, W - 3, H - 3, cream)
  fill(img, W - 6, 18, W - 3, H - 3, shade)
  fill(img, 2, H - 5, W - 3, H - 3, shade)
  -- keyhole
  fill(img, 12, 22, 17, 26, ink)
  fill(img, 13, 27, 16, 30, ink)
  spr:saveCopyAs(app.fs.joinPath(UI, "icon_lock.png"))
  print("wrote icon_lock.png")
end
