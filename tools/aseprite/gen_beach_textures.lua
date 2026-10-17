-- Skins for the beach arena (tools/blender/build_beach.py). Smoother than the
-- cage set: higher resolution, continuous gradients, linear filtering in-game.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_beach_textures.lua
-- Deterministic hash noise (no math.random) so rebuilds are byte-identical.

local OUT = app.fs.joinPath(app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2)))), "assets/textures")
local pc = app.pixelColor

local function noise(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + seed * 982451653) % 2147483647
  n = (n * n * 15731 + n * 789221 + 1376312589) % 2147483647
  return (n % 1000) / 1000.0
end

-- Smooth value noise: bilinear blend of hash noise on a coarse grid.
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

-- beach_court.png 480x512 — a full half court, 14.2 x 15.2 m (33.8 px/m).
-- u = 0 at sim x = -9.9 (half-court line side), u = 1 at x = 4.3 (baseline side);
-- v runs across the court, z -7.6..7.6. Rim centre at x 3.4075, z 0.
do
  local W, H = 480, 512
  local spr, img = newImage(W, H)
  local px = W / 14.2
  local function col(x) return math.floor((x + 9.9) * px + 0.5) end
  local function row(z) return math.floor((z + 7.6) * px + 0.5) end
  local line = rgb(236, 232, 214)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = vnoise(x, y, 24, 71) * 0.6 + noise(x, y, 72) * 0.4
      local v = 84 + n * 18
      img:drawPixel(x, y, rgb(v, v + 4, v + 14))
    end
  end
  local hoop_c, base_c, ft_c, half_c = col(3.4075), col(4.25), col(3.4075 - 4.2), col(-9.75)
  local mid = row(0)
  local lane_half = math.floor(2.45 * px + 0.5)
  -- Sand blown onto the court in a few patches (Ross, 2026-10-02): blobs
  -- near the edges, the corners and the baseline side, ragged by noise,
  -- the asphalt blended toward the sand's colour with a lighter grain.
  -- (The lines are painted after, then sand re-covers them inside a blob.)
  local PATCHES = {
    {col(4.0), row(-6.6), 58}, {col(3.6), row(6.9), 50}, {col(-2.0), row(7.1), 42},
    {col(-8.6), row(-6.4), 52}, {col(-5.5), row(-7.0), 34}, {col(0.8), row(-7.2), 32},
    -- …and around the key and the elbows, where the shooter stands (Ross, 2026-10-02)
    {col(-0.9), row(0.9), 30}, {col(0.7), row(-2.0), 34}, {col(1.6), row(2.6), 30},
    {col(2.3), row(-0.6), 26}, {col(-0.3), row(3.4), 30}, {col(0.2), row(-3.6), 28},
  }
  local function sand_at(x, y)
    local best = 0.0
    for i, pch in ipairs(PATCHES) do
      local dx, dy = x - pch[1], y - pch[2]
      local r = pch[3] * (0.75 + vnoise(x, y, 14, 300 + i) * 0.5)
      local d = math.sqrt(dx * dx + dy * dy) / r
      if d < 1.0 then
        local a = (1.0 - d) * (1.0 - d) * 2.0
        if a > best then best = math.min(1.0, a) end
      end
    end
    return best
  end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local a = sand_at(x, y)
      if a > 0.04 then
        local n = vnoise(x, y, 8, 311) * 0.7 + noise(x, y, 312) * 0.3
        local sr, sg, sb = 214 + n * 24, 194 + n * 22, 150 + n * 22
        local c = img:getPixel(x, y)
        img:drawPixel(x, y, rgb(pc.rgbaR(c) + (sr - pc.rgbaR(c)) * a, pc.rgbaG(c) + (sg - pc.rgbaG(c)) * a, pc.rgbaB(c) + (sb - pc.rgbaB(c)) * a))
      end
    end
  end
  for y = mid - lane_half, mid + lane_half do
    for x = ft_c, base_c do
      local c = img:getPixel(x, y)
      img:drawPixel(x, y, rgb(pc.rgbaR(c) + 14, pc.rgbaG(c) + 6, pc.rgbaB(c) - 6))
    end
  end
  -- boundary: baseline, sidelines, half-court line
  fill(img, base_c, row(-7.5), base_c + 1, row(7.5), line)
  fill(img, half_c, row(-7.5), half_c + 1, row(7.5), line)
  fill(img, half_c, row(-7.5), base_c, row(-7.5) + 1, line)
  fill(img, half_c, row(7.5) - 1, base_c, row(7.5), line)
  -- lane + free-throw line + semicircle (toward the shooter)
  fill(img, ft_c, mid - lane_half, base_c, mid - lane_half + 1, line)
  fill(img, ft_c, mid + lane_half - 1, base_c, mid + lane_half, line)
  fill(img, ft_c, mid - lane_half, ft_c + 1, mid + lane_half, line)
  arc(img, ft_c, mid, 1.8 * px, math.pi / 2, 3 * math.pi / 2, line, 2)
  -- restricted arc
  arc(img, hoop_c, mid, 1.25 * px, math.pi / 2, 3 * math.pi / 2, line, 2)
  -- three-point line: 6.75 m arc joined to straight corner lines at z ±6.6
  local r3 = 6.75 * px
  local zc = 6.6 * px
  local xoff = math.sqrt(r3 * r3 - zc * zc)      -- how far in front of the rim the arc meets z = ±6.6
  local a0 = math.atan(zc, -xoff)               -- ≈102°: the arc sweeps the shooter's side through 180°
  arc(img, hoop_c, mid, r3, a0, 2 * math.pi - a0, line, 2)
  local x_join = hoop_c - math.floor(xoff + 0.5)
  fill(img, x_join, mid - math.floor(zc), base_c, mid - math.floor(zc) + 1, line)
  fill(img, x_join, mid + math.floor(zc) - 1, base_c, mid + math.floor(zc), line)
  -- centre circle (half of it shows on this side of the half-court line)
  arc(img, half_c, mid, 1.8 * px, -math.pi / 2, math.pi / 2, line, 2)
  -- sand over the paint inside the blobs' hearts
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local a = sand_at(x, y)
      if a > 0.55 then
        local c = img:getPixel(x, y)
        if pc.rgbaR(c) > 200 and pc.rgbaG(c) > 200 and pc.rgbaB(c) > 190 then   -- a line pixel
          local n = vnoise(x, y, 8, 311)
          local k = (a - 0.55) / 0.45
          img:drawPixel(x, y, rgb(pc.rgbaR(c) + (214 + n * 24 - pc.rgbaR(c)) * k, pc.rgbaG(c) + (194 + n * 22 - pc.rgbaG(c)) * k, pc.rgbaB(c) + (150 + n * 22 - pc.rgbaB(c)) * k))
        end
      end
    end
  end
  -- Production pass (design "Beach Concept" 34a, 2026-10-16): the asphalt
  -- weathered. Aggregate speckle (single lighter / darker grains over the
  -- plain asphalt), a few meandering cracks with a branch each (dark random
  -- walks that keep out of the key), and paint wear: the lines thinned and
  -- faded toward the asphalt by noise along their length.
  local function is_line(c) return pc.rgbaR(c) > 200 and pc.rgbaG(c) > 200 and pc.rgbaB(c) > 190 end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local c = img:getPixel(x, y)
      if sand_at(x, y) < 0.04 and not is_line(c) then
        local n = noise(x, y, 401)
        if n > 0.94 then
          img:drawPixel(x, y, rgb(pc.rgbaR(c) + 14, pc.rgbaG(c) + 13, pc.rgbaB(c) + 10))
        elseif n < 0.05 then
          img:drawPixel(x, y, rgb(pc.rgbaR(c) - 12, pc.rgbaG(c) - 12, pc.rgbaB(c) - 10))
        end
      end
    end
  end
  local CRACKS = {
    {40, 60, 0.3, 110}, {120, 400, -1.2, 90}, {300, 30, 2.2, 80}, {430, 300, 1.9, 100},
    {200, 490, 0.1, 70}, {60, 250, -0.6, 120}, {380, 470, 3.0, 85},
  }
  local function in_key(x, y) return x >= ft_c - 8 and x <= base_c and y >= mid - lane_half - 8 and y <= mid + lane_half + 8 end
  local function crack(x, y, a, len, seed)
    for i = 0, len do
      a = a + (noise(i, seed, 402) - 0.5) * 0.9
      x = x + math.cos(a); y = y + math.sin(a)
      local px_, py_ = math.floor(x + 0.5), math.floor(y + 0.5)
      if px_ < 0 or py_ < 0 or px_ >= W or py_ >= H or in_key(px_, py_) then return end
      local c = img:getPixel(px_, py_)
      local k = 0.55 + noise(i, seed, 403) * 0.35
      img:drawPixel(px_, py_, rgb(pc.rgbaR(c) + (70 - pc.rgbaR(c)) * k, pc.rgbaG(c) + (71 - pc.rgbaG(c)) * k, pc.rgbaB(c) + (79 - pc.rgbaB(c)) * k))
      if i == math.floor(len * 0.55) and seed < 100 then crack(x, y, a + 1.1, math.floor(len * 0.4), seed + 100) end
    end
  end
  for i, cr in ipairs(CRACKS) do crack(cr[1], cr[2], cr[3], cr[4], i) end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local c = img:getPixel(x, y)
      if is_line(c) then
        local w = vnoise(x, y, 6, 404) * 0.55 + vnoise(x, y, 26, 405) * 0.45
        local edge = math.max(0, 1 - math.min(x, W - 1 - x, y, H - 1 - y) / 70) * 0.15
        local k = math.max(0, math.min(1, (w + edge - 0.6) / 0.3)) * 0.85
        if k > 0 then
          local n = vnoise(x, y, 24, 71) * 0.6 + noise(x, y, 72) * 0.4
          local v = 84 + n * 18
          img:drawPixel(x, y, rgb(pc.rgbaR(c) + (v - pc.rgbaR(c)) * k, pc.rgbaG(c) + (v + 4 - pc.rgbaG(c)) * k, pc.rgbaB(c) + (v + 14 - pc.rgbaB(c)) * k))
        end
      end
    end
  end
  save(spr, "beach_court.png")
end

-- beach_sand.png 256x256 — soft pale sand with gentle drifts.
do
  local W, H = 256, 256
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = vnoise(x, y, 32, 81) * 0.7 + vnoise(x, y, 8, 82) * 0.3
      -- 2026-10-16 production pass: diagonal wind ripples (a sine warped by
      -- value noise), fine grain, and the odd shell bit, bright or dark.
      local ripple = math.sin(((x + y) * 0.7 / W + vnoise(x, y, 40, 84) * 0.12) * 2 * math.pi * 6) * 9
      local grain = (noise(x, y, 85) - 0.5) * 14
      local r, g, b = 214 + n * 24 + ripple + grain, 194 + n * 22 + ripple * 0.9 + grain, 150 + n * 22 + ripple * 0.7 + grain
      local sh = noise(math.floor(x / 2), math.floor(y / 2), 86)
      if sh > 0.994 then r, g, b = 248, 240, 226 elseif sh < 0.004 then r, g, b = 150, 132, 110 end
      img:drawPixel(x, y, rgb(r, g, b))
    end
  end
  save(spr, "beach_sand.png")
end

-- beach_water.png 128x128 — teal with soft, tileable ripple bands.
do
  local W, H = 128, 128
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      -- one soft diagonal swell plus broad value noise (two crossed bands read as plaid)
      local r1 = 0.5 + 0.5 * math.sin((x + 2 * y) / W * 2 * math.pi * 2)
      local n = vnoise(x, y, 20, 91) * 0.5 + vnoise(x, y, 6, 92) * 0.2
      local t = r1 * 0.45 + n
      img:drawPixel(x, y, rgb(30 + t * 50, 110 + t * 60, 140 + t * 55))
    end
  end
  save(spr, "beach_water.png")
end

-- beach_foam.png 128x32 RGBA — soft foam, dense at the top fading to clear.
do
  local W, H = 128, 32
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    local fade = math.max(0, 1 - (y / (H - 1)) ^ 1.4)
    for x = 0, W - 1 do
      local n = vnoise(x, y, 10, 93)
      local a = math.floor(255 * fade * math.max(0, math.min(1, (n - 0.35) * 2.2)) + 0.5)
      img:drawPixel(x, y, rgb(248, 250, 252, a))
    end
  end
  save(spr, "beach_foam.png")
end

-- beach_sky.png 512x256 — smooth dusk gradient with the warm glow pooled at the
-- right edge (the real sun is off-frame in the east-north-east; no drawn disc),
-- lit cloud streaks, and a hazy sea strip below the horizon (row 232 ≈ eye level).
do
  local W, H = 512, 256
  local spr, img = newImage(W, H)
  local HZ = 241   -- horizon sits just above the water plane (y ≈ 0.05 m on the 53 m cylinder)
  -- A quieter dusk: slate blue overhead, dusty mauve, soft peach, pale gold at
  -- the waterline. Desaturated on purpose (no neon magenta/orange).
  local stops = {
    {0.00, 52, 58, 96},
    {0.30, 112, 92, 124},
    {0.62, 190, 136, 118},
    {0.85, 226, 178, 132},
    {1.00, 238, 206, 160},
  }
  local function grad(t)
    local i = 1
    while i < #stops - 1 and stops[i + 1][1] <= t do i = i + 1 end
    local s0, s1 = stops[i], stops[i + 1]
    local u = (t - s0[1]) / (s1[1] - s0[1])
    return s0[2] + (s1[2] - s0[2]) * u, s0[3] + (s1[3] - s0[3]) * u, s0[4] + (s1[4] - s0[4]) * u
  end
  local sx, sy = W + 40, HZ - 8    -- glow centre past the right edge: the sun is off-frame
  for y = 0, HZ do
    local r, g, b = grad(y / HZ)
    for x = 0, W - 1 do
      local d = math.sqrt((x - sx) ^ 2 + ((y - sy) * 1.4) ^ 2)
      local glow = math.max(0, 1 - d / 260) ^ 2
      local haze = vnoise(x, y, 40, 95) * 6
      img:drawPixel(x, y, rgb(r + glow * 34 + haze, g + glow * 24 + haze, b + glow * 6))
    end
  end
  -- lit cloud streaks
  local function streak(x0, x1, y0, thick, hi)
    for x = x0, x1 do
      local e = math.min(1, (x - x0) / 30) * math.min(1, (x1 - x) / 30)
      local h = math.floor(thick * e + 0.5)
      for y = y0 - h, y0 + h do
        local c = img:getPixel(x, y)
        local k = hi and 1 or -1
        img:drawPixel(x, y, rgb(pc.rgbaR(c) + 14 * k, pc.rgbaG(c) + 8 * k, pc.rgbaB(c) - 2 * k))
      end
    end
  end
  -- the texture wraps 360° around the sky cylinder, so keep streaks short (≈30-45° of sky)
  streak(20, 70, 70, 2, false); streak(150, 215, 58, 2, false); streak(300, 350, 104, 2, false); streak(430, 490, 88, 2, false)
  streak(90, 150, 150, 3, true); streak(250, 300, 166, 2, true); streak(380, 445, 156, 3, true); streak(0, 40, 176, 2, true)
  for y = HZ + 1, H - 1 do
    for x = 0, W - 1 do
      -- the sliver below the horizon is hidden by the water plane; keep it the
      -- fogged-water tone in case a wave trough shows it
      img:drawPixel(x, y, rgb(150, 140, 140))
    end
  end
  save(spr, "beach_sky.png")
end

-- The 3D coconut palms (design "Beach Concept" 34a, 2026-10-16;
-- build_beach.py builds the model, BeachFx instances it):
-- beach_bark.png 32x64 — grey-brown bark with flecks and a dark ring line
-- plus a highlight row every 16 px. The trunk's UV runs AROUND in u and
-- ALONG in v (×9), so the rows read as rings.
do
  local W, H = 32, 64
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local c = rgb(106, 90, 72)
      local n = noise(x, y, 201)
      if n < 0.08 then c = rgb(98, 82, 64) elseif n > 0.92 then c = rgb(114, 98, 80) end
      if y % 16 == 0 then c = rgb(70, 56, 40) elseif y % 16 == 1 then c = rgb(122, 106, 88) end
      img:drawPixel(x, y, c)
    end
  end
  save(spr, "beach_bark.png")
end

-- beach_frond.png 64x256 RGBA — one frond: a midrib down the centre and a
-- leaflet every 3 px on each side, 2 px strokes in three greens, longest
-- midway along and drooping more toward the tip. v = 0 at the frond's base.
do
  local W, H = 64, 256
  local spr, img = newImage(W, H)
  fill(img, 0, 0, W - 1, H - 1, pc.rgba(0, 0, 0, 0))
  local greens = {rgb(44, 94, 32), rgb(56, 110, 40), rgb(70, 126, 46)}
  for y = 6, H - 1, 3 do
    local k = y / H
    local len = 30 * math.sin(math.pi * math.min(1, k * 1.05)) * (1 - 0.35 * k) + 2
    local droop = 10 + k * 8
    for _, sgn in ipairs({-1, 1}) do
      local c = greens[math.floor(noise(y, sgn + 2, 202) * 3) + 1]
      local x0, y0 = 32, y
      local cx, cy = 32 + sgn * len * 0.5, y + droop * 0.25
      local x1, y1 = 32 + sgn * len, y + droop
      local steps = math.max(4, math.floor(len + droop))
      for i = 0, steps do
        local t = i / steps
        local xx = (1 - t) * (1 - t) * x0 + 2 * (1 - t) * t * cx + t * t * x1
        local yy = (1 - t) * (1 - t) * y0 + 2 * (1 - t) * t * cy + t * t * y1
        local ix, iy = math.floor(xx), math.floor(yy)
        for oy = 0, 1 do for ox = 0, 1 do
          if ix + ox >= 0 and ix + ox < W and iy + oy >= 0 and iy + oy < H then img:drawPixel(ix + ox, iy + oy, c) end
        end end
      end
    end
  end
  fill(img, 31, 0, 32, H - 1, rgb(126, 124, 60))
  save(spr, "beach_frond.png")
end

-- beach_dither.png 8x8 — the umbrellas' faint dither over their vertex colours.
do
  local spr, img = newImage(8, 8)
  for y = 0, 7 do
    for x = 0, 7 do
      img:drawPixel(x, y, ((x + y) % 4 == 0) and rgb(220, 220, 220) or rgb(255, 255, 255))
    end
  end
  save(spr, "beach_dither.png")
end

-- beach_concrete.png 128x128 — board-formed concrete (design "Beach Concept"
-- 34a, 2026-10-16): six horizontal courses of ~21 px with the wood's grain
-- printed in (long low-contrast streaks), a light row and a dark row at each
-- seam, tie-hole dots, and a darker speckled damp base. One texture height =
-- the wall's 0.45 m (build_beach.py maps the walls' UVs from position).
do
  local W, H = 128, 128
  local spr, img = newImage(W, H)
  local COURSE = H / 6
  for y = 0, H - 1 do
    local course = math.floor(y / COURSE)
    local yy = y - course * COURSE
    for x = 0, W - 1 do
      local grain = vnoise(x + course * 37, y * 5, 18, 101 + course) * 0.5 + vnoise(x, y * 3, 6, 102) * 0.3 + noise(x, y, 103) * 0.2
      local v = 146 + grain * 24
      if yy < 1 then v = v + 20 elseif yy >= COURSE - 1 then v = v - 26 end
      if y >= H - 20 then
        v = v - 22 - (y - (H - 20)) * 0.4
        local sp = noise(x, y, 104)
        if sp > 0.93 then v = v + 18 elseif sp < 0.07 then v = v - 16 end
      end
      img:drawPixel(x, y, rgb(v + 4, v, v - 10))
    end
  end
  for _, h in ipairs({{16, 10}, {112, 10}, {16, 74}, {112, 74}, {64, 52}}) do
    fill(img, h[1] - 1, h[2] - 1, h[1] + 1, h[2] + 1, rgb(112, 108, 100))
    img:drawPixel(h[1], h[2], rgb(96, 92, 84))
  end
  save(spr, "beach_concrete.png")
end

-- beach_curb.png 64x64 — pale cast concrete, fine speckle: the wall caps and
-- the apron between the lined slab and the wall (2026-10-16).
do
  local W, H = 64, 64
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = vnoise(x, y, 12, 111) * 0.35 + noise(x, y, 112) * 0.65
      local v = 173 + (n - 0.5) * 30
      img:drawPixel(x, y, rgb(v, v - 2, v - 11))
    end
  end
  save(spr, "beach_curb.png")
end

-- beach_pole.png 32x8 — galvanised steel bands.
do
  local spr, img = newImage(32, 8)
  fill(img, 0, 0, 31, 1, rgb(150, 154, 160)); fill(img, 0, 2, 31, 5, rgb(96, 100, 106)); fill(img, 0, 6, 31, 7, rgb(58, 60, 64))
  save(spr, "beach_pole.png")
end

-- beach_bird.png 128x24 — a 4-frame gull flap (32x24 each): wings up, mid,
-- down, mid. Dark silhouette with alpha; BeachFx billboards it in the sky.
do
  local FW, FH, N = 32, 24, 4
  local spr, img = newImage(FW * N, FH)
  fill(img, 0, 0, FW * N - 1, FH - 1, pc.rgba(0, 0, 0, 0))
  local ink = pc.rgba(38, 34, 40, 255)
  local lift = {6, 2, -4, 2}          -- wing-tip height relative to the body per frame (+ = up)
  for f = 0, N - 1 do
    local ox = f * FW
    local cx, cy = ox + 16, 13
    -- body: a small blob
    fill(img, cx - 2, cy - 1, cx + 2, cy + 1, ink)
    img:drawPixel(cx + 3, cy, ink)     -- beak
    local tip = lift[f + 1]
    for side = -1, 1, 2 do
      for d = 1, 13 do
        local u = d / 13
        -- wing curve: rises toward the tip when up, bows when down
        local y = cy - math.floor(tip * (u * u) + 0.5) - math.floor(1.5 * math.sin(u * 3.14159) + 0.5)
        local x = cx + side * d
        img:drawPixel(x, y, ink)
        if d < 9 then img:drawPixel(x, y + 1, ink) end
      end
    end
  end
  save(spr, "beach_bird.png")
end

-- beach_pelican.png 192x32 — a 4-frame pelican flap (48x32 each), Ross's
-- 2026-10-03 ask: a bigger, slower, solo bird. White body and inner wings,
-- black primaries on the outer third, a long orange bill held level, feet
-- tucked. Faces +u like the gull (BeachFx mirrors it with `facing`). The
-- wings sweep back from the shoulders and are drawn FIRST, so the neck, head
-- and bill read in front of them whatever the frame.
do
  local FW, FH, N = 48, 32, 4
  local spr, img = newImage(FW * N, FH)
  fill(img, 0, 0, FW * N - 1, FH - 1, pc.rgba(0, 0, 0, 0))
  local white = pc.rgba(236, 234, 228, 255)
  local shade = pc.rgba(190, 188, 184, 255)
  local black = pc.rgba(36, 32, 34, 255)
  local bill  = pc.rgba(238, 150, 46, 255)
  local eye   = pc.rgba(30, 28, 30, 255)
  local lift = {9, 3, -5, 3}
  for f = 0, N - 1 do
    local ox = f * FW
    local cx, cy = ox + 24, 20
    -- wings: shoulders at cx - 2, span 19 each side, swept back 4 px; white
    -- for the inner 12, black primaries beyond
    local tip = lift[f + 1]
    for side = -1, 1, 2 do
      for d = 1, 19 do
        local u = d / 19
        local y = cy - 2 - math.floor(tip * (u * u) + 0.5) - math.floor(2.0 * math.sin(u * 3.14159) + 0.5)
        local x = cx - 2 + side * d - ((side > 0) and math.floor(u * 4) or 0)
        local c = (d > 12) and black or white
        img:drawPixel(x, y, c)
        if d < 16 then img:drawPixel(x, y + 1, (d > 12) and black or shade) end
        if d < 8 then img:drawPixel(x, y + 2, shade) end
      end
    end
    -- body: a plump teardrop, shaded underneath
    fill(img, cx - 7, cy - 2, cx + 3, cy + 2, white)
    fill(img, cx - 5, cy + 3, cx + 1, cy + 3, shade)
    img:drawPixel(cx - 8, cy - 1, white); img:drawPixel(cx - 8, cy, white)   -- tail
    img:drawPixel(cx - 9, cy, shade)
    -- neck + head, forward and up (over the wing roots)
    fill(img, cx + 3, cy - 5, cx + 5, cy - 1, white)
    fill(img, cx + 5, cy - 7, cx + 8, cy - 4, white)
    img:drawPixel(cx + 7, cy - 6, eye)
    -- bill: long, level, a little heavier at the base — drawn last
    for d = 0, 10 do
      img:drawPixel(cx + 8 + d, cy - 5, bill)
      if d < 7 then img:drawPixel(cx + 8 + d, cy - 4, bill) end
    end
  end
  -- A one-pixel ink outline around everything: a white bird on a sunset sky
  -- otherwise disappears (only its bill and wingtips showed in QA).
  local ink = pc.rgba(58, 52, 54, 255)
  local edge = {}
  for y = 0, FH - 1 do
    for x = 0, FW * N - 1 do
      if pc.rgbaA(img:getPixel(x, y)) == 0 then
        for _, o in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
          local nx, ny = x + o[1], y + o[2]
          if nx >= 0 and ny >= 0 and nx < FW * N and ny < FH and pc.rgbaA(img:getPixel(nx, ny)) ~= 0
             and (nx % FW) ~= 0 and (x % FW) ~= 0 and ((x + 1) % FW) ~= 0 then
            edge[#edge + 1] = {x, y}
            break
          end
        end
      end
    end
  end
  for _, e in ipairs(edge) do img:drawPixel(e[1], e[2], ink) end
  save(spr, "beach_pelican.png")
end


-- Local helpers for the horizon sprites below (px/limb are not used elsewhere).
local function px(img, x, y, c)
  if x >= 0 and y >= 0 and x < img.width and y < img.height then img:drawPixel(x, y, c) end
end
local function limb(img, x0, y0, x1, y1, c, w)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.max(math.abs(dx), math.abs(dy))
  if n < 1 then n = 1 end
  for i = 0, n do
    local t = i / n
    local x, y = x0 + dx * t, y0 + dy * t
    for oy = 0, w - 1 do
      for ox = 0, w - 1 do px(img, math.floor(x) + ox, math.floor(y) + oy, c) end
    end
  end
end

-- ---- beach_ship.png --------------------------------------------------------
-- A modern CRUISE ship for the far horizon: long and low, many thin decks, a
-- small funnel set well aft. The first attempt read as a steamboat because the
-- hull was short and deep and the funnel sat amidships and tall.
-- One frame; BeachFx yaws the quad side-on rather than billboarding it.
do
  local W, H = 224, 32
  local spr, img = newImage(W, H)
  fill(img, 0, 0, W - 1, H - 1, pc.rgba(0, 0, 0, 0))
  local hull  = rgb(240, 238, 234)
  local shade = rgb(198, 196, 196)
  local dark  = rgb(46, 54, 76)
  local deck  = rgb(250, 249, 246)
  local port  = rgb(255, 216, 152)
  local wl = 25                               -- waterline row
  local x0, x1 = 6, W - 7

  -- Hull: LOW (only 5 px of freeboard over a 210 px length) with a long raked
  -- bow at the right and a cut-away stern at the left.
  for x = x0, x1 do
    local t = (x - x0) / (x1 - x0)
    local top = wl - 5
    if t > 0.90 then top = top + math.floor((t - 0.90) / 0.10 * 4) end   -- bow rake
    if t < 0.04 then top = top + math.floor((0.04 - t) / 0.04 * 2) end   -- stern
    fill(img, x, top, x, wl, hull)
  end
  fill(img, x0, wl, x1, wl, shade)             -- waterline shadow
  fill(img, x0 + 2, wl - 5, x1 - 8, wl - 5, dark)   -- boot/sheer stripe

  -- Superstructure: five thin stacked decks, each inset a little more, so the
  -- silhouette tapers instead of forming one tall block.
  local decks = { {16, 10, 6}, {22, 16, 9}, {30, 24, 12}, {40, 34, 15}, {54, 48, 17} }
  for _, d in ipairs(decks) do
    fill(img, x0 + d[1], wl - d[3], x1 - d[2], wl - d[3] + 2, deck)
    fill(img, x0 + d[1], wl - d[3] + 3, x1 - d[2], wl - d[3] + 3, shade)
  end
  -- Funnel: small, aft of centre.
  fill(img, x0 + 60, wl - 23, x0 + 72, wl - 17, dark)
  fill(img, x0 + 60, wl - 23, x0 + 72, wl - 22, rgb(206, 86, 62))

  -- Lit portholes and window strips.
  for x = x0 + 6, x1 - 10, 4 do fill(img, x, wl - 3, x, wl - 2, port) end
  for _, d in ipairs(decks) do
    for x = x0 + d[1] + 3, x1 - d[2] - 3, 5 do fill(img, x, wl - d[3] + 1, x, wl - d[3] + 1, port) end
  end
  save(spr, "beach_ship.png")
end

-- ---- beach_plane.png -------------------------------------------------------
-- A high airliner: a small dark shape with a faint contrail. One frame.
do
  local W, H = 64, 16
  local spr, img = newImage(W, H)
  fill(img, 0, 0, W - 1, H - 1, pc.rgba(0, 0, 0, 0))
  local ink = rgb(58, 54, 66)
  local cy = 9
  fill(img, 40, cy, 57, cy + 1, ink)              -- fuselage
  fill(img, 56, cy - 2, 58, cy, ink)              -- tail fin
  limb(img, 47, cy, 43, cy - 4, ink, 1)           -- swept wings
  limb(img, 47, cy + 1, 43, cy + 5, ink, 1)
  -- Contrail, fading behind.
  for x = 4, 39 do
    local a = math.floor(150 * (x - 4) / 35)
    px(img, x, cy, pc.rgba(246, 236, 228, a))
    if x > 20 then px(img, x, cy + 1, pc.rgba(246, 236, 228, math.floor(a * 0.5))) end
  end
  save(spr, "beach_plane.png")
end
