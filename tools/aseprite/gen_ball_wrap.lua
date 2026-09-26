-- Every basketball skin in the game, from one style table.
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_ball_wrap.lua
--
-- Writes assets/textures/balls/<id>.png for each entry in STYLES, plus
-- assets/balls/ball_manifest.json, which is what tools/gen_ball_sets.py and
-- tools/blender/build_ball_lineup.py read. STYLES is the single source of truth
-- for the whole roster -- ids, names and prices included -- so nothing is typed
-- out twice.
--
-- `classic` is also written to the legacy assets/textures/ball_wrap.png, because
-- BallPool's SphereMesh fallback loads that path directly.
--
-- THE BALL BREAKS THE HOUSE STYLE on purpose (docs/BLENDER_101.md section 7):
-- smooth-shaded and linear-filtered where every other prop is flat-shaded pixel
-- art. It is the thing the player stares at all game and the only truly
-- spherical prop. Do not "fix" it back to flat.
--
-- Layout (512x256, 2:1): x = longitude, y = latitude +90 (top) .. -90, which is
-- exactly a UV sphere's built-in map.
--
-- Seams, 8 panels:
--   equator    great circle at lat 0
--   meridian   great circle through the poles, in the x=0 plane
--   two loops  bowed circles around +x / -x
-- The meridian sits BETWEEN the loops rather than through them, which is what
-- makes the count land on 8: V=6, E=12, F = 2 - 6 + 12 = 8.
--
-- BETA is the loops' angular radius (cos(BETA) is how far off-centre they sit, so
-- a SMALLER angle pushes them out toward the silhouette). BOW warps each loop off
-- its plane: a circle lying flat projects to a PERFECTLY STRAIGHT LINE edge-on,
-- and the ball tumbles constantly, so a planar loop reads as a straight bar from
-- a view that comes up all the time. BOW = 0 reproduces that flat circle.

local ROOT = app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2))))
local TEX_DIR = app.fs.joinPath(ROOT, "assets/textures/balls")
local LEGACY = app.fs.joinPath(ROOT, "assets/textures/ball_wrap.png")
local MANIFEST = app.fs.joinPath(ROOT, "assets/balls/ball_manifest.json")
local pc = app.pixelColor

local W, H = 512, 256
local BETA = math.rad(52)
local BOW = math.rad(14)
local SEAM_DEG = 5.0
local LINE = math.max(2, math.floor(SEAM_DEG * W / 360 + 0.5))
local DOT_STEP_DEG = 2.8
local DOT_R_DEG = 1.25
local DOT_H = 1.0
local PX_PER_LON = W / 360.0
local PX_PER_LAT = H / 180.0

-- ---------------------------------------------------------------------------
-- The roster. `panels` cycles over the 8 panels; `kind` picks a decorator.
-- Prices must all be > 0: CosmeticLibrary.starter_ball() returns the first set
-- priced 0, and a test asserts that is still `classic`.
-- ---------------------------------------------------------------------------
local LEATHER = {226, 118, 47}
local DARK = {36, 22, 15}

local STYLES = {
  {id="classic", name="Classic", price=0, panels={LEATHER}, seam=DARK},

  {id="globetrotters", name="Globetrotters", price=900, kind="panel",
   panels={{206, 32, 48}, {245, 245, 245}, {28, 58, 140}, {245, 245, 245}},
   seam={30, 30, 38}, stars=true},

  {id="aba", name="ABA Tri-Color", price=750, kind="panel",
   panels={{214, 48, 52}, {242, 240, 232}, {32, 66, 150}},
   seam={40, 34, 30}},

  {id="blacktop", name="Blacktop", price=250, kind="panel",
   panels={{112, 110, 106}, {96, 94, 90}}, seam={44, 44, 46}, grain=0.22},

  {id="midnight", name="Midnight", price=600, kind="panel",
   panels={{34, 38, 58}, {26, 29, 46}}, seam={12, 13, 22}},

  {id="neon", name="Neon", price=800, kind="panel",
   panels={{240, 42, 150}, {26, 226, 224}}, seam={22, 18, 40}},

  {id="sunset", name="Sunset", price=700, kind="gradient",
   ramp={{250, 186, 60}, {236, 96, 52}, {96, 40, 128}}, seam={52, 26, 48}},

  {id="lime", name="Lime", price=400, kind="panel",
   panels={{150, 214, 48}}, seam={46, 62, 22}},

  {id="bubblegum", name="Bubblegum", price=500, kind="panel",
   panels={{244, 140, 190}, {250, 240, 244}}, seam={120, 60, 96}},

  {id="gold", name="Gold", price=1500, kind="gradient",
   ramp={{246, 216, 120}, {206, 158, 48}, {150, 104, 24}}, seam={64, 44, 12}},

  {id="chrome", name="Chrome", price=1400, kind="gradient",
   ramp={{238, 242, 248}, {168, 178, 194}, {96, 108, 126}}, seam={48, 54, 64}},

  {id="camo", name="Camo", price=650, kind="blotch",
   palette={{86, 96, 58}, {62, 70, 42}, {112, 108, 74}, {44, 50, 34}},
   seam={34, 38, 26}},

  {id="beach", name="Beach Ball", price=350, kind="wedges",
   palette={{240, 60, 60}, {250, 250, 245}, {245, 200, 50}, {60, 140, 220}},
   wedges=8, seams=false, pebble=0.0, grain=0.0},

  {id="eightball", name="Eight Ball", price=1000, kind="disc",
   base={22, 22, 26}, disc={245, 245, 245}, disc_deg=26, seams=false,
   pebble=0.02, grain=0.0},

  {id="watermelon", name="Watermelon", price=450, kind="stripes",
   base={86, 168, 66}, stripe={34, 88, 40}, stripes=14, seam={46, 92, 44}},

  {id="ice", name="Ice", price=700, kind="gradient",
   ramp={{238, 250, 255}, {168, 212, 240}, {104, 158, 206}}, seam={70, 106, 140}},

  {id="fire", name="Fire", price=900, kind="gradient",
   ramp={{252, 232, 120}, {242, 120, 36}, {176, 32, 28}}, seam={54, 20, 14}},

  {id="galaxy", name="Galaxy", price=1200, kind="blotch",
   palette={{38, 24, 66}, {58, 32, 98}, {26, 18, 48}, {86, 48, 132}},
   seam={16, 12, 30}, sparkle=true},

  {id="retro", name="Retro 70s", price=550, kind="panel",
   panels={{214, 156, 52}, {142, 84, 40}}, seam={72, 44, 24}},

  {id="varsity", name="Varsity", price=600, kind="panel",
   panels={{26, 44, 96}, {240, 240, 244}}, seam={18, 26, 54}},

  {id="tiger", name="Tiger", price=850, kind="stripes",
   base={236, 150, 40}, stripe={38, 28, 22}, stripes=18, wobble=true,
   seam={40, 28, 18}},
}

-- ---------------------------------------------------------------------------

local function noise(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + seed * 982451653) % 2147483647
  n = (n * n * 15731 + n * 789221 + 1376312589) % 2147483647
  return (n % 1000) / 1000.0
end

-- Smooth-ish value noise on the sphere, for camo and galaxy.
local function vnoise(x, y, scale, seed)
  local fx, fy = x / scale, y / scale
  local ix, iy = math.floor(fx), math.floor(fy)
  local tx, ty = fx - ix, fy - iy
  tx = tx * tx * (3 - 2 * tx)
  ty = ty * ty * (3 - 2 * ty)
  local a = noise(ix, iy, seed)
  local b = noise(ix + 1, iy, seed)
  local c = noise(ix, iy + 1, seed)
  local d = noise(ix + 1, iy + 1, seed)
  return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty
end

local function lerp3(a, b, t)
  return {a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t}
end

local function ramp_at(ramp, t)
  if #ramp == 1 then return ramp[1] end
  local f = t * (#ramp - 1)
  local i = math.min(math.floor(f) + 1, #ramp - 1)
  return lerp3(ramp[i], ramp[i + 1], f - (i - 1))
end

local function clamp8(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end

-- Which of the 8 panels a sphere point falls in. Three sign tests: north of the
-- equator, which side of the meridian plane, and inside or outside that half's
-- bowed loop.
local function panel_of(px, py, pz)
  local north = pz > 0.0
  local east = px > 0.0
  local cx = east and 1.0 or -1.0
  local axial = math.max(-1.0, math.min(1.0, px * cx))
  local theta = math.acos(axial)
  -- Where round the loop this direction sits, so we can ask the loop how wide
  -- it is THERE -- the radius breathes twice per turn.
  local t = math.atan(py * cx, pz)
  local inside = theta < (BETA + BOW * math.cos(2 * t))
  return (north and 4 or 0) + (east and 2 or 0) + (inside and 1 or 0)
end

local function shade_for(st, px, py, pz, lat, lon, x, y)
  local kind = st.kind or "panel"
  if kind == "gradient" then
    -- Pole to pole, mirrored so both halves read the same tumbling.
    return ramp_at(st.ramp, math.abs(lat) / 90.0)
  elseif kind == "wedges" then
    local n = st.wedges or 6
    local i = math.floor(((lon + 180.0) / 360.0) * n) % n
    return st.palette[i % #st.palette + 1]
  elseif kind == "disc" then
    -- A cap centred on the -y equatorial point, NOT on a pole: at a pole the
    -- equirect map smears it into a wedge, and it would never face the camera.
    local d = math.acos(math.max(-1.0, math.min(1.0, -py)))
    if math.deg(d) < (st.disc_deg or 26) then return st.disc end
    return st.base
  elseif kind == "stripes" then
    local n = st.stripes or 12
    local u = (lon + 180.0) / 360.0
    if st.wobble then u = u + vnoise(x, y, 46, 21) * 0.06 end
    local f = (u * n) % 1.0
    -- Tapered toward the poles, like a real stripe wrapping a sphere.
    local w = 0.34 + 0.16 * math.cos(math.rad(lat))
    if f < w then return st.stripe end
    return st.base
  elseif kind == "blotch" then
    local a = vnoise(x, y, 34, 5)
    local b = vnoise(x, y, 13, 11) * 0.45
    local v = math.max(0.0, math.min(0.999, a * 0.75 + b))
    return st.palette[math.floor(v * #st.palette) + 1]
  end
  local cols = st.panels or {LEATHER}
  return cols[panel_of(px, py, pz) % #cols + 1]
end

local function render(st)
  local spr = Sprite(W, H, ColorMode.RGB)
  local img = spr.cels[1].image
  local seam_rgb = st.seam or DARK
  local pebble = st.pebble or 0.085
  local grain = st.grain
  if grain == nil then grain = 0.10 end
  local draw_seams = st.seams ~= false

  local height, seam_cov = {}, {}
  for i = 0, W * H - 1 do height[i] = 0.0 end

  local function wrap(x, y)
    -- Past a pole the sphere continues over the top and out the far side, so y
    -- REFLECTS and x jumps half the image. Clamping would silently truncate.
    if y < 0 then
      y = -y - 1
      x = x + W / 2
    elseif y >= H then
      y = 2 * H - y - 1
      x = x + W / 2
    end
    return x % W, y
  end

  local SEAM_R = LINE * 0.5
  local FEATHER = 1.1
  -- `xs` stretches the brush horizontally. The map crowds columns toward the
  -- poles, so a fixed-pixel brush lays a seam that narrows in real arc terms the
  -- higher it climbs; 1/cos(lat) holds it at constant width on the ball.
  local function dot(cx, cy, xs)
    xs = xs or 1.0
    local ry = SEAM_R + FEATHER
    local rx = ry * xs
    for y = math.floor(cy - ry), math.ceil(cy + ry) do
      for x = math.floor(cx - rx), math.ceil(cx + rx) do
        local dx, dy = (x + 0.5 - cx) / xs, y + 0.5 - cy
        local a = 1.0 - (math.sqrt(dx * dx + dy * dy) - SEAM_R) / FEATHER
        if a > 0.0 then
          if a > 1.0 then a = 1.0 end
          local px, py = wrap(x, y)
          local i = py * W + px
          if (seam_cov[i] or 0.0) < a then seam_cov[i] = a end
        end
      end
    end
  end

  -- lon 0 sits at the image CENTRE: that is what the glb maps (longitude 0 ->
  -- u 0.5, checked against the mesh's TEXCOORD_0).
  local function plot(px, py, pz)
    local lon = math.atan(py, px)
    local lat = math.asin(math.max(-1, math.min(1, pz)))
    local u = (0.5 + lon / (2 * math.pi)) % 1.0
    local v = 0.5 - lat / math.pi
    dot(u * W, v * H, math.min(1.0 / math.max(math.cos(lat), 0.001), 3.5))
  end

  -- Pebbling. Fewer dots per row as the rows shrink, and each dome stretched by
  -- 1/cos(lat), so the grain is even on the BALL rather than in the image.
  if pebble > 0.0 then
    local row, lat = 0, -90.0 + DOT_STEP_DEG * 0.5
    while lat < 90.0 do
      local clat = math.cos(math.rad(lat))
      if clat > 0.03 then
        local per_row = math.max(3, math.floor(360.0 * clat / DOT_STEP_DEG + 0.5))
        local ry = DOT_R_DEG * PX_PER_LAT
        local rx = math.min(DOT_R_DEG * PX_PER_LON / clat, W * 0.25)
        local cy = (0.5 - lat / 180.0) * H
        for k = 0, per_row - 1 do
          local jx = (noise(k, row, 3) - 0.5) * DOT_STEP_DEG * 0.5
          local jy = (noise(k, row, 9) - 0.5) * DOT_STEP_DEG * 0.5
          local cx = (((k + (row % 2) * 0.5) * 360.0 / per_row + jx) / 360.0) * W
          local cyj = cy + jy * PX_PER_LAT
          for y = math.floor(cyj - ry), math.ceil(cyj + ry) do
            for x = math.floor(cx - rx), math.ceil(cx + rx) do
              local ddx, ddy = (x + 0.5 - cx) / rx, (y + 0.5 - cyj) / ry
              local d2 = ddx * ddx + ddy * ddy
              if d2 < 1.0 then
                local wx, wy = wrap(x, y)
                local i = wy * W + wx
                height[i] = height[i] + DOT_H * (1.0 - d2)
              end
            end
          end
        end
      end
      lat = lat + DOT_STEP_DEG
      row = row + 1
    end
  end

  if draw_seams then
    local step = math.max(1, math.floor(SEAM_R * 0.5))
    for x = 0, W - 1, step do dot(x + 0.5, H / 2) end
    for i = 0, 5999 do
      local t = i / 6000 * 2 * math.pi
      plot(0.0, math.sin(t), math.cos(t))
    end
    -- Close the pole: at the pole a texture row IS a single point, so even a
    -- compensated brush narrows to nothing and leaves a pinhole.
    local cap = math.max(3, math.floor(SEAM_R * 1.3))
    for r = 0, cap - 1 do
      for x = 0, W - 1 do
        seam_cov[r * W + x] = 1.0
        seam_cov[(H - 1 - r) * W + x] = 1.0
      end
    end
    for _, cx in ipairs({1, -1}) do
      for i = 0, 5999 do
        local t = i / 6000 * 2 * math.pi
        local b = BETA + BOW * math.cos(2 * t)
        local cb, sb = math.cos(b), math.sin(b)
        plot(cb * cx, sb * math.sin(t) * cx, sb * math.cos(t))
      end
    end
  end

  local peak = 0.0
  for i = 0, W * H - 1 do
    if height[i] > peak then peak = height[i] end
  end
  if peak <= 0.0 then peak = 1.0 end

  for y = 0, H - 1 do
    local lat = 90.0 - (y + 0.5) * 180.0 / H
    local clat = math.cos(math.rad(lat))
    local slat = math.sin(math.rad(lat))
    for x = 0, W - 1 do
      local lon = (x + 0.5) * 360.0 / W - 180.0
      local rlon = math.rad(lon)
      local col = shade_for(st, clat * math.cos(rlon), clat * math.sin(rlon), slat,
                            lat, lon, x, y)
      local i = y * W + x
      -- Pebble tops a touch lighter, the gaps a touch darker. No baked light
      -- direction: the ball tumbles, so a painted highlight would swing wrong.
      local k = 1.0 + ((height[i] / peak) * 2.0 - 1.0) * pebble
      if grain > 0.0 and noise(x, y, 7) < grain then k = k - 0.045 end
      local r, g, b = col[1] * k, col[2] * k, col[3] * k
      if st.sparkle and noise(x, y, 31) > 0.994 then
        r, g, b = 236, 232, 250
      end
      if st.stars and noise(math.floor(x / 9), math.floor(y / 9), 17) > 0.972 then
        r, g, b = 250, 248, 240
      end
      local cov = seam_cov[i]
      if cov then
        r = r + (seam_rgb[1] - r) * cov
        g = g + (seam_rgb[2] - g) * cov
        b = b + (seam_rgb[3] - b) * cov
      end
      img:drawPixel(x, y, pc.rgba(clamp8(r), clamp8(g), clamp8(b), 255))
    end
  end
  return spr
end

local rows = {}
for _, st in ipairs(STYLES) do
  local sp = render(st)
  local path = app.fs.joinPath(TEX_DIR, st.id .. ".png")
  sp:saveCopyAs(path)
  if st.id == "classic" then sp:saveCopyAs(LEGACY) end
  sp:close()
  rows[#rows + 1] = string.format(
    '  {"id": "%s", "name": "%s", "price": %d, "skin": "res://assets/textures/balls/%s.png"}',
    st.id, st.name, st.price or 0, st.id)
  print("  " .. st.id)
end

local f = io.open(MANIFEST, "w")
f:write("[\n" .. table.concat(rows, ",\n") .. "\n]\n")
f:close()
print(string.format("wrote %d skins -> %s", #STYLES, TEX_DIR))
print("manifest -> " .. MANIFEST)
