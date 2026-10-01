-- Skins for the city court's chain-net hoop (tools/blender/build_chain_hoop.py),
-- after the references Ross picked (2026-09-27): a weathered galvanised steel
-- board with a riveted rolled edge, a bare steel ring, a net of real chain
-- links, and the gooseneck pole's steel.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_chain_hoop_textures.lua
-- Deterministic hash noise (no math.random) so rebuilds are byte-identical.

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
  local top = a + (b - a) * fx
  return top + ((c + (d - c) * fx) - top) * fy
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

-- city_board.png 512x294 — 1.83 x 1.05 m (280 px/m). A WHITE board gone
-- DINGY (Ross, 2026-10-01): greyed paint under a heavy mottle, grime
-- streaks running down, and the dirt where the ball actually hits — a
-- broad smudge centred on the target square (heaviest at its middle and
-- along its top edge, the bank-shot spot), a bloom under the rim mount,
-- and the lower corners. The chamfered lower corners are cut by the mesh;
-- here they are frame too so nothing odd shows at the cut.
do
  local W, H = 512, 294
  local spr, img = newImage(W, H)
  local px = W / 1.83
  -- the target square (also drawn below), so the dirt can find it
  local sq_w0, sq_h0 = math.floor(0.59 * px + 0.5), math.floor(0.45 * px + 0.5)
  local sq_bottom = H - 1 - math.floor(0.15 * px + 0.5)
  local sq_top = sq_bottom - sq_h0 + 1
  local sq_cx, sq_cy = W / 2, (sq_top + sq_bottom) / 2
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local mottle = vnoise(x, y, 22, 401) * 0.6 + vnoise(x, y, 60, 402) * 0.4
      local streak = math.max(0, vnoise(x * 5, y, 36, 404) - 0.5) * 0.8 * (0.3 + 0.7 * y / H)
      local v = 196 + mottle * 22 - streak * 60
      -- grime under the rim mount (bottom centre) and in the lower corners
      local dx, dy = (x - W / 2) / (0.26 * px), (H - 1 - y) / (0.26 * px)
      local grime = math.max(0, 1 - math.sqrt(dx * dx + dy * dy * 0.6)) * (0.5 + 0.5 * vnoise(x, y, 7, 405))
      local cx = math.min(x, W - 1 - x) / (0.3 * px)
      local corner = math.max(0, 1 - math.sqrt(cx * cx + dy * dy)) * 0.5 * vnoise(x, y, 9, 406)
      -- the ball's dirt: a wide smudge on the square, heaviest at its centre
      -- and along its top edge, smeared a little above it
      local tx, ty = (x - sq_cx) / (0.42 * px), (y - sq_cy) / (0.30 * px)
      local hit = math.max(0, 1 - math.sqrt(tx * tx + ty * ty))
      local ex, ey = (x - sq_cx) / (0.36 * px), (y - sq_top) / (0.10 * px)
      local edge = math.max(0, 1 - math.sqrt(ex * ex + ey * ey))
      local smudge = (hit * hit * 0.9 + edge * 0.7) * (0.55 + 0.45 * vnoise(x, y, 11, 408))
      local d = grime * 0.6 + corner + smudge
      local r, g, b = v - d * 78, v - d * 74, v - d * 66
      img:drawPixel(x, y, rgb(r, g, b))
    end
  end
  -- target: a faint dark rectangle 0.59 x 0.45 m, its bottom 0.15 m up
  local sq_w, sq_h = math.floor(0.59 * px + 0.5), math.floor(0.45 * px + 0.5)
  local bottom = H - 1 - math.floor(0.15 * px + 0.5)
  local top = bottom - sq_h + 1
  local left = math.floor((W - sq_w) / 2)
  local right = left + sq_w - 1
  local function darken(x0, y0, x1, y1)
    for y = y0, y1 do
      for x = x0, x1 do
        local c = img:getPixel(x, y)
        img:drawPixel(x, y, rgb(pc.rgbaR(c) * 0.3, pc.rgbaG(c) * 0.3, pc.rgbaB(c) * 0.32))
      end
    end
  end
  darken(left, top, right, top + 5); darken(left, bottom - 5, right, bottom)
  darken(left, top, left + 5, bottom); darken(right - 5, top, right, bottom)
  -- rolled-edge frame, 5 cm, pale grey steel with a bright inner lip
  local F = math.floor(0.05 * px + 0.5)
  local function frame(x0, y0, x1, y1)
    for y = y0, y1 do
      for x = x0, x1 do
        local n = noise(x, y, 407) * 10
        img:drawPixel(x, y, rgb(176 + n, 180 + n, 186 + n))
      end
    end
  end
  frame(0, 0, W - 1, F - 1); frame(0, H - F, W - 1, H - 1); frame(0, 0, F - 1, H - 1); frame(W - F, 0, W - 1, H - 1)
  fill(img, F, F, W - F - 1, F, rgb(236, 238, 242)); fill(img, F, F, F, H - F - 1, rgb(236, 238, 242))
  -- rivets every ~10 cm along the frame's centre line
  local step = math.floor(0.10 * px + 0.5)
  local function rivet(x, y)
    fill(img, x - 2, y - 2, x + 2, y + 2, rgb(120, 124, 132))
    fill(img, x - 1, y - 1, x + 1, y + 1, rgb(196, 200, 208))
    img:drawPixel(x - 1, y - 1, rgb(236, 238, 242))
  end
  for x = F // 2 + step // 2, W - F // 2, step do rivet(x, F // 2); rivet(x, H - 1 - F // 2) end
  for y = F // 2 + step // 2, H - F // 2, step do rivet(F // 2, y); rivet(W - 1 - F // 2, y) end
  save(spr, "city_board.png")
end

-- hoop_rim_steel.png 32x8 — the ring tube, painted a dark orange-red
-- (Ross, 2026-10-01), worn lighter on top and near-black underneath.
do
  local spr, img = newImage(32, 8)
  for y = 0, 7 do
    local c
    if y < 2 then c = rgb(198, 84, 46)
    elseif y < 6 then c = rgb(150, 50, 28)
    else c = rgb(78, 24, 14) end
    for x = 0, 31 do
      local n = noise(x, y, 411) * 10
      img:drawPixel(x, y, rgb(pc.rgbaR(c) + n, pc.rgbaG(c) + n, pc.rgbaB(c) + n))
    end
  end
  save(spr, "hoop_rim_steel.png")
end

-- city_steel.png 32x8 — the gooseneck pole's tube wrap.
do
  local spr, img = newImage(32, 8)
  for y = 0, 7 do
    local t = y / 7
    local v = 176 - t * 90
    for x = 0, 31 do
      local n = vnoise(x, y, 6, 421) * 14
      img:drawPixel(x, y, rgb(v + n, v + n + 2, v + n + 8))
    end
  end
  save(spr, "city_steel.png")
end

-- hoop_chain.png 256x192 RGBA — the nylon lattice's diamonds (4 cells
-- across, 3 down, the same layout NetSim's mesh is UV'd for) drawn as runs
-- of real chain links along both diagonals: 12 px ovals, 5 px wide, a 2 px
-- steel wall with a bright top edge and a dark underside, a 2 px gap
-- between links, every other link turned edge-on (narrower). Clear elsewhere.
do
  local W, H = 256, 192
  local spr = Sprite(W, H, ColorMode.RGB)
  local img = spr.cels[1].image
  local none = pc.rgba(0, 0, 0, 0)
  fill(img, 0, 0, W - 1, H - 1, none)
  local CELL = 64
  local LINK, GAP = 14, 2
  -- slate links (Ross, 2026-10-01): a cool dark grey, not bright steel
  local hi, mid, lo = rgb(176, 184, 198), rgb(104, 112, 126), rgb(44, 50, 60)
  local function paint(x, y, c)
    if x >= 0 and x < W and y >= 0 and y < H then img:drawPixel(x, y, c) end
  end
  -- Along a diagonal direction (dx, dy) through every lattice line, walk in
  -- link steps and stamp an oval per link.
  local function run(sx, sy, dx, dy)
    -- s runs along the diagonal; the diagonal's length is CELL*sqrt2 per cell
    local n = 0
    local s = 0
    local len = W * 1.5
    while s < len do
      local cx, cy = sx + dx * s, sy + dy * s
      local edge = (n % 2 == 1)
      local half_w = edge and 2.2 or 3.6
      for t = -LINK / 2, LINK / 2 do
        for u = -4, 4 do
          local ax, ay = cx + dx * t - dy * u, cy + dy * t + dx * u
          local ix, iy = math.floor(ax + 0.5), math.floor(ay + 0.5)
          -- oval wall: |u| between half_w-1.4 and half_w, or the rounded ends
          local end_t = math.abs(t) > LINK / 2 - 2.5
          local on = (math.abs(u) <= half_w and math.abs(u) >= half_w - 2.0) or (end_t and math.abs(u) <= half_w)
          if on then
            local c = (u < -0.5) and hi or ((u > 0.5) and lo or mid)
            paint(ix % W, iy % H, c)
          end
        end
      end
      s = s + LINK + GAP
      n = n + 1
    end
  end
  local d = 1 / math.sqrt(2)
  for k = -4, 8 do
    run(k * CELL, 0, d, d)        -- x + y = const lines
    run(k * CELL, 0, d, -d)       -- x - y = const lines
  end
  save(spr, "hoop_chain.png")
end
