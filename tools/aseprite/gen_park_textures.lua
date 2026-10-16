-- The park (docs/BLENDER_101.md → The park): the winter court's skins for
-- tools/blender/build_park.py and build_park_hoop.py, from the design's
-- canvas recipes ("Park Area Concept"). Deterministic hash noise (no
-- math.random) so rebuilds are byte-identical.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_park_textures.lua

local ROOT = app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2))))
local OUT = app.fs.joinPath(ROOT, "assets/textures")
local pc = app.pixelColor

local function noise(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + seed * 982451653) % 2147483647
  n = (n * n * 15731 + n * 789221 + 1376312589) % 2147483647
  return (n % 1000) / 1000.0
end

local function newImage(w, h, rgba)
  local spr = Sprite(w, h, rgba and ColorMode.RGBA or ColorMode.RGB)
  return spr, spr.cels[1].image
end

local function clamp(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
local function rgb(r, g, b, a) return pc.rgba(clamp(r), clamp(g), clamp(b), a or 255) end
local function hex(h, a)
  return rgb(tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16), a)
end
local function fill(img, x0, y0, x1, y1, c)
  for y = math.max(0, y0), math.min(img.height - 1, y1) do
    for x = math.max(0, x0), math.min(img.width - 1, x1) do img:drawPixel(x, y, c) end
  end
end
local function save(spr, name) spr:saveCopyAs(app.fs.joinPath(OUT, name)); print("wrote " .. name) end
local CLEAR = pc.rgba(0, 0, 0, 0)

-- park_asphalt.png 64x64 — grey blacktop with a speckle and one wandering crack.
do
  local W, H = 64, 64
  local spr, img = newImage(W, H)
  local cols = {"#53575B", "#686C70", "#74777A", "#4B4F53"}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 11)
      img:drawPixel(x, y, n < 0.22 and hex(cols[math.floor(n * 1000) % 4 + 1]) or hex("#5E6266"))
    end
  end
  local cy = 38
  for cx = 0, W - 1 do
    img:drawPixel(cx, cy, hex("#3E4144"))
    local n = noise(cx, 7, 12)
    if n < 0.3 then cy = cy + ((n < 0.15) and -1 or 1) end
    cy = math.max(2, math.min(H - 3, cy))
  end
  save(spr, "park_asphalt.png")
end

-- park_grass.png 64x64 — winter lawn: dull greens with pale frost flecks.
do
  local W, H = 64, 64
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = math.sin(x * 0.31 + math.sin(y * 0.17) * 2) + math.sin(y * 0.27 + x * 0.07) + (noise(x, y, 21) - 0.5) * 0.9
      local c
      if n > 1.55 then c = "#E6ECEF"
      elseif n > 1.4 then c = ((x + y) % 2 == 1) and "#C9CFC8" or "#9A9A6A"
      else
        local m = noise(x, y, 22)
        c = m < 0.5 and "#7E8452" or (m < 0.75 and "#8F8A5C" or "#6C7646")
      end
      img:drawPixel(x, y, hex(c))
    end
  end
  save(spr, "park_grass.png")
end

-- park_snow.png 32x32 — lying snow, a faint speckle.
do
  local W, H = 32, 32
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 31)
      img:drawPixel(x, y, n < 0.06 and hex("#DCE6EC") or (n < 0.1 and hex("#FFFFFF") or (n < 0.13 and hex("#D2DEE6") or hex("#EEF3F6"))))
    end
  end
  save(spr, "park_snow.png")
end

-- park_pole.png 8x64 — the black pole: rust flecks near the foot and the top, a highlight stripe.
do
  local W, H = 8, 64
  local spr, img = newImage(W, H)
  fill(img, 0, 0, W - 1, H - 1, hex("#1F1F21"))
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 41)
      local rusty = (y >= 48 and n < 0.28) or (y < 20 and n < 0.14)
      if rusty then img:drawPixel(x, y, noise(x, y, 42) < 0.5 and hex("#5A3A26") or hex("#3A2C24")) end
    end
    img:drawPixel(2, y, hex("#34363A"))
  end
  save(spr, "park_pole.png")
end

-- park_board.png 128x96 — the white park board: black edge band, the black
-- shooting square just above the rim, rust under the bolts, a smudge
-- cluster round the square, a chipped corner, a faded orange sticker.
do
  local W, H = 128, 96
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 51)
      img:drawPixel(x, y, n < 0.12 and hex("#E2E3DF") or (n < 0.2 and hex("#F6F6F3") or (n < 0.26 and hex("#D9DAD6") or hex("#EDEDEA"))))
    end
  end
  local ink = hex("#1C1C1E")
  fill(img, 0, 0, W - 1, 3, ink); fill(img, 0, H - 4, W - 1, H - 1, ink); fill(img, 0, 0, 3, H - 1, ink); fill(img, W - 4, 0, W - 1, H - 1, ink)
  local sw, sh = 55, 42
  local sx, sy = math.floor((W - sw) / 2), H - 13 - sh
  fill(img, sx, sy, sx + sw - 1, sy + 3, ink); fill(img, sx, sy, sx + 3, sy + sh - 1, ink)
  fill(img, sx + sw - 4, sy, sx + sw - 1, sy + sh - 1, ink); fill(img, sx, sy + sh - 4, sx + sw - 1, sy + sh - 1, ink)
  -- rust streaks under the two bolts
  for _, bx in ipairs({22, W - 24}) do
    local len = 11 + math.floor(noise(bx, 1, 52) * 11)
    for y = 7, 7 + len do img:drawPixel(bx, y, hex("#9C6A48")); img:drawPixel(bx + 1, y, hex("#B07A54")) end
  end
  -- the smudge cluster round the square
  for i = 1, 40 do
    local a = noise(i, 3, 53) * 6.28
    local r = 8 + noise(i, 4, 53) * 24
    local px, py = math.floor(W / 2 + math.cos(a) * r * 1.3), math.floor(H - 32 + math.sin(a) * r * 0.8)
    fill(img, px, py, px + 2, py + 2, hex("#C9C5BF"))
  end
  -- the chipped corner and the sticker
  fill(img, W - 4, 0, W - 1, 5, hex("#9A9A96"))
  fill(img, 10, H - 22, 22, H - 15, hex("#E8945A")); fill(img, 12, H - 20, 17, H - 19, hex("#F1E8D0"))
  save(spr, "park_board.png")
end

-- park_sky_clouds.png 128x128 — a tileable cloud mask (four octaves of value
-- noise, quantised) the sky shader samples: 0 = clear, 1 = cloud.
do
  local W, H = 128, 128
  local spr, img = newImage(W, H)
  local function vn(x, y, seed, period)
    local gx, gy = x / period, y / period
    local ix, iy = math.floor(gx), math.floor(gy)
    local fx, fy = gx - ix, gy - iy
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
    local n = W / period
    local function h(a, b) return noise(a % n, b % n, seed) end
    local a = h(ix, iy) + (h(ix + 1, iy) - h(ix, iy)) * fx
    local b = h(ix, iy + 1) + (h(ix + 1, iy + 1) - h(ix, iy + 1)) * fx
    return a + (b - a) * fy
  end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local v = 0.5 * vn(x, y, 61, 64) + 0.25 * vn(x, y, 62, 32) + 0.125 * vn(x, y, 63, 16) + 0.0625 * vn(x, y, 64, 8)
      local q = math.floor(v * 8) / 8
      local g = clamp(q * 255)
      img:drawPixel(x, y, rgb(g, g, g))
    end
  end
  save(spr, "park_sky_clouds.png")
end

-- park_treeline_strip.png 512x96 (RGBA) — three hazed rows of pines and
-- rounded trees, palest at the back, hard-cut alpha; wraps on a ring at the
-- horizon so the far distance reads as more woods.
do
  local W, H = 512, 96
  local spr, img = newImage(W, H, true)
  fill(img, 0, 0, W - 1, H - 1, CLEAR)
  local function tri(cx, top, base, w, c)
    for y = top, base do
      local t = (y - top) / math.max(1, base - top)
      local hw = w * 0.5 * t
      fill(img, math.floor(cx - hw), y, math.floor(cx + hw), y, c)
    end
  end
  local function blob(cx, cy, rx, ry, c)
    for y = math.floor(cy - ry), math.floor(cy + ry) do
      for x = math.floor(cx - rx), math.floor(cx + rx) do
        local dx, dy = (x - cx) / rx, (y - cy) / ry
        if dx * dx + dy * dy <= 1 then img:drawPixel(((x % W) + W) % W, y, c) end
      end
    end
  end
  local function row(col, snow, base, hmin, hmax, step, seed)
    local px = -20
    local i = 0
    while px < W + 20 do
      i = i + 1
      local th = hmin + noise(i, 1, seed) * (hmax - hmin)
      local w = th * (noise(i, 2, seed) < 0.55 and 0.42 or 0.7)
      local pine = noise(i, 3, seed) < 0.6
      for _, o in ipairs({0, -W, W}) do
        local X = px + o
        if pine then
          tri(X, base - th, base, w, hex(col))
          if snow then tri(X, base - th, base - th * 0.7, w * 0.28, hex(snow)) end
        else
          blob(X, base - th * 0.55, w / 2, th * 0.5, hex(col))
          fill(img, X - 1, base - th * 0.2, X + 1, base, hex(col))
        end
      end
      px = px + step * (0.6 + noise(i, 4, seed) * 0.8)
    end
  end
  row("#AFC0CE", "#D8E2EA", 80, 30, 58, 14, 71)
  row("#8FA3B2", "#CCD8E2", 88, 22, 44, 11, 72)
  row("#74899A", "#C2CFDA", 96, 16, 34, 9, 73)
  fill(img, 0, 92, W - 1, 95, hex("#C9D4DC"))
  save(spr, "park_treeline_strip.png")
end
