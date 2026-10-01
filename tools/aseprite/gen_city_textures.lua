-- Skins for the city court (tools/blender/build_city.py): a dusk inner-city
-- cage court — teal blacktop with yellow lines, a wet asphalt street, brick
-- tenements with painted dark-glass windows (no window-light shader since 2026-10-01), glass
-- towers, a dusk sky, billboard trees, a painted wall and the floodlight heads.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_city_textures.lua
-- Deterministic hash noise (no math.random) so rebuilds are byte-identical.
-- The fence reuses cage_mesh.png, the sidewalk beach_concrete.png and the
-- hoop pole beach_pole.png.

local OUT = app.fs.joinPath(app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2)))), "assets/textures")
local pc = app.pixelColor

local function noise(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + seed * 982451653) % 2147483647
  n = (n * n * 15731 + n * 789221 + 1376312589) % 2147483647
  return (n % 1000) / 1000.0
end

local function vnoise(x, y, cell, seed)
  local gx, gy = x / cell, y / cell
  local x0, y0 = math.floor(gx), math.floor(gy)
  local fx, fy = gx - x0, gy - y0
  fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
  local a, b = noise(x0, y0, seed), noise(x0 + 1, y0, seed)
  local c, d = noise(x0, y0 + 1, seed), noise(x0 + 1, y0 + 1, seed)
  return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
end

local function newImage(w, h)
  local spr = Sprite(w, h, ColorMode.RGB)
  return spr, spr.cels[1].image
end

local function clamp(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
local function rgb(r, g, b, a) return pc.rgba(clamp(r), clamp(g), clamp(b), a or 255) end

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

local function arc(img, cx, cy, r, a0, a1, c, thick)
  local steps = math.max(16, math.floor(r * 10))
  for i = 0, steps do
    local a = a0 + (a1 - a0) * i / steps
    local x = math.floor(cx + r * math.cos(a) + 0.5)
    local y = math.floor(cy + r * math.sin(a) + 0.5)
    fill(img, x, y, x + thick - 1, y + thick - 1, c)
  end
end

-- city_court.png 480x512 — a full half court, 14.6 x 15.2 m (32.9 px/m).
-- u = 0 at sim x = -9.9, u = 1 at x = 4.7 (the baseline side); v runs across
-- the court, z -7.6..7.6. Rim centre at x 3.625 (SimGeometry.CITY_DIST), z 0;
-- the baseline sits 1 m behind it at x 4.6. Teal blacktop, a darker lane,
-- yellow lines, rain streaks and a few leaves.
do
  local W, H = 480, 512
  local spr, img = newImage(W, H)
  local px = W / 14.6
  local function col(x) return math.floor((x + 9.9) * px + 0.5) end
  local function row(z) return math.floor((z + 7.6) * px + 0.5) end
  local line = rgb(232, 196, 74)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = vnoise(x, y, 28, 171) * 0.55 + noise(x, y, 172) * 0.25 + vnoise(x, y, 90, 173) * 0.2
      -- wet sheen: long streaks along u
      local wet = math.max(0, vnoise(x, y * 4, 40, 174) - 0.62) * 1.6
      local v = 62 + n * 20 + wet * 30
      img:drawPixel(x, y, rgb(v * 0.55, v * 1.05, v * 0.98))
    end
  end
  local hoop_c, base_c, ft_c, half_c = col(3.625), col(4.6), col(3.625 - 4.2), col(-9.75)
  local mid = row(0)
  local lane_half = math.floor(2.45 * px + 0.5)
  for y = mid - lane_half, mid + lane_half do
    for x = ft_c, base_c do
      local c = img:getPixel(x, y)
      img:drawPixel(x, y, rgb(pc.rgbaR(c) * 0.8, pc.rgbaG(c) * 0.86, pc.rgbaB(c) * 0.9))
    end
  end
  -- leaves: small warm blobs
  for i = 0, 70 do
    local lx = math.floor(noise(i, 1, 175) * (W - 4))
    local ly = math.floor(noise(i, 2, 175) * (H - 4))
    local warm = noise(i, 3, 175)
    local leaf = rgb(120 + warm * 80, 70 + warm * 40, 30)
    fill(img, lx, ly, lx + 1 + math.floor(warm * 2), ly + 1, leaf)
  end
  fill(img, base_c, row(-7.5), base_c + 1, row(7.5), line)
  fill(img, half_c, row(-7.5), half_c + 1, row(7.5), line)
  fill(img, half_c, row(-7.5), base_c, row(-7.5) + 1, line)
  fill(img, half_c, row(7.5) - 1, base_c, row(7.5), line)
  fill(img, ft_c, mid - lane_half, base_c, mid - lane_half + 1, line)
  fill(img, ft_c, mid + lane_half - 1, base_c, mid + lane_half, line)
  fill(img, ft_c, mid - lane_half, ft_c + 1, mid + lane_half, line)
  arc(img, ft_c, mid, 1.8 * px, math.pi / 2, 3 * math.pi / 2, line, 2)
  arc(img, hoop_c, mid, 1.25 * px, math.pi / 2, 3 * math.pi / 2, line, 2)
  local r3 = 6.75 * px
  local zc = 6.6 * px
  local xoff = math.sqrt(r3 * r3 - zc * zc)
  local a0 = math.atan(zc, -xoff)
  arc(img, hoop_c, mid, r3, a0, 2 * math.pi - a0, line, 2)
  local x_join = hoop_c - math.floor(xoff + 0.5)
  fill(img, x_join, mid - math.floor(zc), base_c, mid - math.floor(zc) + 1, line)
  fill(img, x_join, mid + math.floor(zc) - 1, base_c, mid + math.floor(zc), line)
  arc(img, half_c, mid, 1.8 * px, -math.pi / 2, math.pi / 2, line, 2)
  save(spr, "city_court.png")
end

-- city_asphalt.png 128x128 — wet dark asphalt: fine speckle, a few patches.
do
  local W, H = 128, 128
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    do
      for x = 0, W - 1 do
        local n = noise(x, y, 181) * 0.35 + vnoise(x, y, 16, 182) * 0.4 + vnoise(x, y, 48, 183) * 0.25
        local v = 34 + n * 22
        img:drawPixel(x, y, rgb(v, v + 1, v + 5))
      end
    end
  end
  save(spr, "city_asphalt.png")
end

-- city_kerb.png 64x16 — concrete kerb: a pale top, a darker face.
do
  local W, H = 64, 16
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 191) * 14
      local v = (y < 6) and 150 + n or 108 + n
      img:drawPixel(x, y, rgb(v, v - 2, v - 6))
    end
  end
  save(spr, "city_kerb.png")
end

-- city_brick.png 128x128 — a tenement wall: dark red brick, pale mortar, a
-- few odd bricks. 8 rows of 16 px bricks, staggered.
do
  local W, H = 128, 128
  local spr, img = newImage(W, H)
  local mortar = rgb(86, 74, 68)
  fill(img, 0, 0, W - 1, H - 1, mortar)
  local BW, BH = 32, 16
  for by = 0, H / BH - 1 do
    local off = (by % 2) * (BW / 2)
    for bx = -1, W / BW do
      local x0 = bx * BW + off
      local y0 = by * BH
      local t = noise(bx + 100, by, 201)
      local r, g, b = 118 + t * 30, 52 + t * 18, 40 + t * 12
      if t > 0.9 then r, g, b = 70, 44, 40 end
      for y = y0 + 1, y0 + BH - 2 do
        for x = x0 + 1, x0 + BW - 2 do
          if x >= 0 and x < W then
            local n = noise(x, y, 202) * 10
            img:drawPixel(x, y, rgb(r + n, g + n * 0.6, b + n * 0.4))
          end
        end
      end
    end
  end
  save(spr, "city_brick.png")
end

-- city_windows.png 128x128 — the same brick with a 4 x 4 grid of window
-- holes (dark glass, a pale sill). Painted only; a tile = 4 x 4 windows, read by
-- its UV cell index, so a tile = 4 x 4 windows.
do
  local W, H = 128, 128
  local spr, img = newImage(W, H)
  local mortar = rgb(86, 74, 68)
  fill(img, 0, 0, W - 1, H - 1, mortar)
  local BW, BH = 32, 16
  for by = 0, H / BH - 1 do
    local off = (by % 2) * (BW / 2)
    for bx = -1, W / BW do
      local x0, y0 = bx * BW + off, by * BH
      local t = noise(bx + 300, by, 211)
      local r, g, b = 118 + t * 30, 52 + t * 18, 40 + t * 12
      for y = y0 + 1, y0 + BH - 2 do
        for x = math.max(0, x0 + 1), math.min(W - 1, x0 + BW - 2) do
          local n = noise(x, y, 212) * 10
          img:drawPixel(x, y, rgb(r + n, g + n * 0.6, b + n * 0.4))
        end
      end
    end
  end
  local CELL = 32
  local glass = rgb(26, 32, 52)
  local frame = rgb(150, 140, 128)
  local sill = rgb(170, 160, 146)
  for cy = 0, 3 do
    for cx = 0, 3 do
      local x0, y0 = cx * CELL + 8, cy * CELL + 6
      local x1, y1 = cx * CELL + 23, cy * CELL + 25
      fill(img, x0 - 1, y0 - 1, x1 + 1, y1 + 1, frame)
      fill(img, x0, y0, x1, y1, glass)
      fill(img, x0 - 2, y1 + 2, x1 + 2, y1 + 3, sill)
      -- a mullion
      fill(img, (x0 + x1) // 2, y0, (x0 + x1) // 2, y1, frame)
    end
  end
  save(spr, "city_windows.png")
end

-- city_tower.png 64x128 — a glass tower: 4 x 8 panes per tile in dark steel
-- mullions. Painted only (one pane = one cell).
do
  local W, H = 64, 128
  local spr, img = newImage(W, H)
  local steel = rgb(52, 56, 66)
  fill(img, 0, 0, W - 1, H - 1, steel)
  local glass = rgb(30, 40, 66)
  for cy = 0, 7 do
    for cx = 0, 3 do
      local x0, y0 = cx * 16 + 2, cy * 16 + 2
      for y = y0, y0 + 11 do
        for x = x0, x0 + 11 do
          local n = vnoise(x, y, 6, 221) * 14
          img:drawPixel(x, y, rgb(pc.rgbaR(glass) + n, pc.rgbaG(glass) + n, pc.rgbaB(glass) + n * 1.4))
        end
      end
    end
  end
  save(spr, "city_tower.png")
end

-- city_sky.png 512x256 — midday (2026-10-01, was 7 pm): a clear blue
-- overhead fading to a pale haze at the horizon all round. v = 0 is the
-- horizon.
do
  local W, H = 512, 256
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    local t = 1 - y / (H - 1)         -- 1 at the horizon (bottom row is v = 0 in Godot)
    for x = 0, W - 1 do
      local r, g, b
      if t < 0.55 then
        local k = t / 0.55
        r, g, b = 122 + (170 - 122) * k, 174 + (206 - 174) * k, 234 + (242 - 234) * k
      else
        local k = (t - 0.55) / 0.45
        r, g, b = 170 + (226 - 170) * k, 206 + (236 - 206) * k, 242 + (246 - 242) * k
      end
      local n = noise(x, y, 231) * 4
      img:drawPixel(x, y, rgb(r + n, g + n, b + n))
    end
  end
  save(spr, "city_sky.png")
end

-- city_tree.png 128x192 RGBA — a street tree at dusk: a dark trunk, a lumpy
-- deep-green canopy with a warm rim from the floodlights. Billboarded.
do
  local W, H = 128, 192
  local spr = Sprite(W, H, ColorMode.RGB)
  local img = spr.cels[1].image
  local clear = pc.rgba(0, 0, 0, 0)
  fill(img, 0, 0, W - 1, H - 1, clear)
  local trunk = rgb(48, 36, 30)
  fill(img, 58, 120, 69, H - 1, trunk)
  fill(img, 54, 168, 73, H - 1, trunk)
  local cx, cy = 64, 76
  for y = 0, 150 do
    for x = 0, W - 1 do
      local dx, dy = (x - cx) / 58, (y - cy) / 66
      local d = math.sqrt(dx * dx + dy * dy)
      local lump = vnoise(x, y, 14, 241) * 0.35
      if d + lump < 1.0 then
        local shade = 0.55 + 0.45 * math.max(0, 1 - d) * (0.6 + 0.4 * vnoise(x, y, 8, 242))
        local rim = math.max(0, d - 0.7) * 1.2 * (y < cy and 1 or 0.4)
        img:drawPixel(x, y, rgb(28 * shade + 60 * rim, 62 * shade + 40 * rim, 34 * shade + 10 * rim))
      end
    end
  end
  save(spr, "city_tree.png")
end

-- city_mural.png 256x128 — a painted wall panel: brick under a big teal
-- shape, an orange ring and a stripe of bold blocks, all weathered.
do
  local W, H = 256, 128
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local t = noise(x // 16, y // 8, 251)
      local n = noise(x, y, 252) * 8
      img:drawPixel(x, y, rgb(110 + t * 28 + n, 50 + t * 14 + n * 0.5, 40 + n * 0.4))
    end
  end
  local function blob(cx, cy, rx, ry, c)
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        local dx, dy = (x - cx) / rx, (y - cy) / ry
        if dx * dx + dy * dy < 1 and noise(x, y, 253) > 0.08 then img:drawPixel(x, y, c) end
      end
    end
  end
  blob(96, 64, 70, 46, rgb(40, 130, 120))
  blob(96, 64, 44, 28, rgb(232, 196, 74))
  for i = 0, 5 do
    local c = (i % 2 == 0) and rgb(220, 90, 50) or rgb(240, 232, 210)
    fill(img, 176 + i * 12, 30 + (i % 3) * 8, 184 + i * 12, 100 - (i % 2) * 10, c)
  end
  arc(img, 200, 64, 34, 0, 2 * math.pi, rgb(232, 120, 60), 4)
  save(spr, "city_mural.png")
end

-- city_flood.png 32x32 RGBA — a floodlight head seen from the court: a hot
-- white-yellow core with a soft warm edge.
do
  local W, H = 32, 32
  local spr = Sprite(W, H, ColorMode.RGB)
  local img = spr.cels[1].image
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local dx, dy = (x + 0.5 - 16) / 15, (y + 0.5 - 16) / 15
      local d = math.sqrt(dx * dx + dy * dy)
      local a = math.max(0, 1 - d)
      a = a * a
      local v = 200 + 55 * math.min(1, a * 2)
      img:drawPixel(x, y, pc.rgba(clamp(v), clamp(v * 0.95), clamp(v * 0.7), clamp(255 * math.min(1, a * 1.8))))
    end
  end
  save(spr, "city_flood.png")
end

-- city_poster.png 192x128 RGB — the bus shelter's lit billboard (3:2, 3.0 x
-- 2.0 m, its back wall): a ball over a chain hoop on a hot orange field,
-- bold title bars. Unshaded in-game, so it glows across the street.
do
  local W, H = 192, 128
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local t = y / H
      img:drawPixel(x, y, rgb(232 - t * 40, 112 - t * 30, 58 - t * 10))
    end
  end
  fill(img, 0, 0, W - 1, 3, rgb(34, 28, 24)); fill(img, 0, H - 4, W - 1, H - 1, rgb(34, 28, 24))
  fill(img, 0, 0, 3, H - 1, rgb(34, 28, 24)); fill(img, W - 4, 0, W - 1, H - 1, rgb(34, 28, 24))
  local cx, cy, r = 52, 62, 32
  for y = cy - r, cy + r do
    for x = cx - r, cx + r do
      local dx, dy = x - cx, y - cy
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= r then
        local shade = 1 - 0.35 * math.max(0, (dx + dy) / r)
        local seam = (math.abs(dx) < 2) or (math.abs(dy) < 2) or (math.abs(math.sqrt(dx * dx + (dy + r * 0.7) * (dy + r * 0.7)) - r * 1.1) < 2)
        img:drawPixel(x, y, seam and rgb(40, 24, 16) or rgb(214 * shade, 96 * shade, 40 * shade))
        if d > r - 2 then img:drawPixel(x, y, rgb(40, 24, 16)) end
      end
    end
  end
  -- the hoop right of the ball: a rim line and hanging chains
  fill(img, 100, 50, 176, 53, rgb(226, 230, 236))
  for i = 0, 8 do
    local x0 = 102 + i * 9
    for y = 54, 86 - (i % 2) * 4 do
      if (y // 3) % 2 == 0 then img:drawPixel(x0 + (y - 54) // 6, y, rgb(226, 230, 236)) end
    end
  end
  -- title bars (bold blocks read as lettering from the court)
  fill(img, 12, 10, 180, 26, rgb(241, 232, 208))
  fill(img, 18, 14, 174, 22, rgb(34, 28, 24))
  for i = 0, 10 do fill(img, 20 + i * 14, 15, 28 + i * 14, 21, rgb(241, 232, 208)) end
  fill(img, 100, 96, 180, 108, rgb(241, 232, 208))
  for i = 0, 3 do fill(img, 104 + i * 20, 99, 118 + i * 20, 105, rgb(34, 28, 24)) end
  for i = 0, 5 do fill(img, 14 + i * 28, 114, 34 + i * 28, 116, rgb(60, 40, 30)) end
  save(spr, "city_poster.png")
end

-- city_sign.png 64x32 RGB — the shelter's lit roof sign: a bus pictogram
-- on blue, a pale border.
do
  local W, H = 64, 32
  local spr, img = newImage(W, H)
  fill(img, 0, 0, W - 1, H - 1, rgb(28, 66, 140))
  fill(img, 0, 0, W - 1, 1, rgb(230, 234, 240)); fill(img, 0, H - 2, W - 1, H - 1, rgb(230, 234, 240))
  fill(img, 0, 0, 1, H - 1, rgb(230, 234, 240)); fill(img, W - 2, 0, W - 1, H - 1, rgb(230, 234, 240))
  -- the bus: a body, three windows, two wheels
  fill(img, 10, 8, 40, 22, rgb(236, 238, 242))
  for i = 0, 2 do fill(img, 13 + i * 9, 11, 19 + i * 9, 16, rgb(28, 66, 140)) end
  fill(img, 14, 22, 18, 25, rgb(230, 234, 240)); fill(img, 32, 22, 36, 25, rgb(230, 234, 240))
  -- "BUS" as three bold blocks
  for i = 0, 2 do fill(img, 46 + i * 5, 10, 49 + i * 5, 21, rgb(236, 238, 242)) end
  save(spr, "city_sign.png")
end
