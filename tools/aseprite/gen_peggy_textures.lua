-- PEGGY, the drop machine (docs/LOCKER.md): the v2 carnival cabinet's skins
-- for tools/blender/build_peggy.py, plus the UI's ticket icon. Deterministic
-- hash noise (no math.random) so rebuilds are byte-identical. Every texture
-- is drawn per pixel from the design's canvas recipes (peggy-cabinet-v2.js).
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b --script tools/aseprite/gen_peggy_textures.lua

local ROOT = app.fs.filePath(app.fs.filePath(app.fs.filePath(debug.getinfo(1).source:sub(2))))
local OUT = app.fs.joinPath(ROOT, "assets/textures")
local UI = app.fs.joinPath(ROOT, "assets/ui")
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
    for x = math.max(0, x0), math.min(img.width - 1, x1) do
      img:drawPixel(x, y, c)
    end
  end
end

local function save(spr, dir, name)
  spr:saveCopyAs(app.fs.joinPath(dir, name))
  print("wrote " .. name)
end

local CLEAR = pc.rgba(0, 0, 0, 0)
local INK = "#221C18"
local INK2 = "#1A1618"
local CREAM = "#F1E8D0"
local GOLD = "#F0B84A"
local ORANGE = "#E8703A"
local TEAL = "#3F8C7A"
local RAR = { common = "#8FC1E3", rare = "#3F8C7A", epic = "#E0457B", legend = "#F0B84A", refund = "#5A514A" }

-- A 3x5 pixel font for the few words the cabinet carries.
local FONT = {
  A = {"010", "101", "111", "101", "101"}, C = {"011", "100", "100", "100", "011"},
  D = {"110", "101", "101", "101", "110"}, E = {"111", "100", "110", "100", "111"},
  G = {"011", "100", "101", "101", "011"}, H = {"101", "101", "111", "101", "101"},
  I = {"111", "010", "010", "010", "111"}, K = {"101", "101", "110", "101", "101"},
  L = {"100", "100", "100", "100", "111"}, M = {"101", "111", "111", "101", "101"},
  N = {"110", "101", "101", "101", "101"}, O = {"010", "101", "101", "101", "010"},
  P = {"110", "101", "110", "100", "100"}, R = {"110", "101", "110", "101", "101"},
  S = {"011", "100", "010", "001", "110"}, T = {"111", "010", "010", "010", "010"},
  U = {"101", "101", "101", "101", "111"}, V = {"101", "101", "101", "101", "010"},
  Y = {"101", "101", "010", "010", "010"}, ["?"] = {"110", "001", "010", "000", "010"},
  ["0"] = {"111", "101", "101", "101", "111"}, ["2"] = {"111", "001", "111", "100", "111"},
  ["4"] = {"101", "101", "111", "001", "001"}, ["6"] = {"111", "100", "111", "101", "111"},
  [" "] = {"000", "000", "000", "000", "000"},
}

local function text(img, s, x0, y0, scale, c)
  local x = x0
  for i = 1, #s do
    local g = FONT[s:sub(i, i)]
    if g then
      for row = 1, 5 do
        for col = 1, 3 do
          if g[row]:sub(col, col) == "1" then
            fill(img, x + (col - 1) * scale, y0 + (row - 1) * scale,
                 x + col * scale - 1, y0 + row * scale - 1, c)
          end
        end
      end
    end
    x = x + 4 * scale
  end
  return x - x0 - scale
end

local function text_w(s, scale) return #s * 4 * scale - scale end

local function text_c(img, s, cx, y0, scale, c)
  text(img, s, math.floor(cx - text_w(s, scale) / 2), y0, scale, c)
end

-- Outlined text: the word in `c` with a one-scale ring of `o` around it.
local function text_o(img, s, cx, y0, scale, c, o)
  local x0 = math.floor(cx - text_w(s, scale) / 2)
  for _, d in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) do
    text(img, s, x0 + d[1] * scale, y0 + d[2] * scale, scale, o)
  end
  text(img, s, x0, y0, scale, c)
end

-- peggy_face.png 176x388 (RGBA) — the cabinet face: wavy sunburst wings
-- around a dark board window, the orange marquee strip, PEGGY on top.
-- Alpha-cut in the model; the window and everything outside the wings is
-- clear. Mirrors the design's canvas recipe (FW 1.12 x FH 2.46 metres).
do
  local W, H = 176, 388
  local FW, FH = 1.12, 2.46
  local spr, img = newImage(W, H, true)
  local cx = W / 2
  local bx0, bx1 = W * (0.5 - 0.39 / FW), W * (0.5 + 0.39 / FW)
  local byT, byB = H * (1 - 2.00 / FH), H * (1 - 0.48 / FH)
  local function edge(yy, side)
    local t = yy / H
    if side < 0 then return 6 + 9 * math.sin(t * 7.2 + 0.4) + 6 * t end
    return W - 6 - 9 * math.sin(t * 6.4 + 1.6) - 4 * t
  end
  local function archTop(xx)
    local u = (xx - cx) / (W / 2)
    return 10 + 22 * u * u - 8 * math.cos(u * 6.5) * (1 - math.abs(u))
  end
  local cols = {ORANGE, INK, TEAL, ORANGE, INK, ORANGE, TEAL, INK}
  local hubs = {{-1, bx0}, {1, bx1}}
  local oy = (byT + byB) / 2
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local px, py = x + 0.5, y + 0.5
      local inside = px > edge(py, -1) and px < edge(py, 1) and py > archTop(px) and py < H - 4
      local c = CLEAR
      if inside then
        c = hex(INK)
        -- the sunburst: 8 wedges of 15° from each wing's hub, gold ray lines
        for _, hub in ipairs(hubs) do
          local side, ox = hub[1], hub[2]
          local dx, dy = (px - ox) * side, py - oy
          local ang = math.deg(math.atan(dy, dx))
          if dx > 0 and ang >= -60 and ang < 60 then
            local k = math.floor((ang + 60) / 15)
            c = hex(cols[k + 1])
            local a0 = (-60 + k * 15)
            local d = math.abs(math.rad(ang - a0)) * math.sqrt(dx * dx + dy * dy)
            if d < 1.5 then c = hex(GOLD) end
          end
        end
        -- the marquee strip over the window, its gold rule
        if px >= bx0 - 12 and px <= bx1 + 12 and py < byT + 4 then c = hex(ORANGE) end
        if px >= bx0 - 12 and px <= bx1 + 12 and py >= byT - 6 and py < byT - 3 then c = hex(GOLD) end
        -- the window
        if px >= bx0 - 5 and px <= bx1 + 5 and py >= byT - 2 and py <= byB + 2 then c = CLEAR end
        -- the outline
        local onEdge = px < edge(py, -1) + 2 or px > edge(py, 1) - 2 or py < archTop(px) + 2 or py > H - 6
        if onEdge and c ~= CLEAR then c = hex(INK2) end
      end
      img:drawPixel(x, y, c)
    end
  end
  -- the title, gold outline on ink
  text_o(img, "PEGGY", cx, math.floor(byT * 0.62) - 10, 4, hex(INK), hex(GOLD))
  save(spr, OUT, "peggy_face.png")
end

-- peggy_board.png 72x124 — the dark speckled board with a gold glow at the top.
do
  local W, H = 72, 124
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, 701)
      local c = n < 0.025 and "#272020" or (n > 0.975 and "#3A302C" or "#2E2624")
      local col = hex(c)
      if y < 22 then
        local g = (1 - y / 22) * 0.45
        local r = tonumber(c:sub(2, 3), 16) * (1 - g) + 240 * g
        local gg = tonumber(c:sub(4, 5), 16) * (1 - g) + 184 * g
        local b = tonumber(c:sub(6, 7), 16) * (1 - g) + 74 * g
        col = rgb(r, gg, b)
      end
      img:drawPixel(x, y, col)
    end
  end
  save(spr, OUT, "peggy_board.png")
end

-- peggy_deck.png 160x64 — the console deck: ◀ MOVE ▶ and DROP, a gold frame.
do
  local W, H = 160, 64
  local spr, img = newImage(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      img:drawPixel(x, y, noise(x, y, 711) < 0.03 and hex("#3A3036") or hex("#2A2228"))
    end
  end
  fill(img, 3, 3, W - 4, 4, hex(GOLD)); fill(img, 3, H - 5, W - 4, H - 4, hex(GOLD))
  fill(img, 3, 3, 4, H - 4, hex(GOLD)); fill(img, W - 5, 3, W - 4, H - 4, hex(GOLD))
  fill(img, W / 2 - 1, 10, W / 2, H - 11, hex(GOLD))
  local cr = hex(CREAM)
  text_c(img, "MOVE", W * 0.27, H - 12, 1, cr)
  -- the arrows
  local ax = math.floor(W * 0.27 - text_w("MOVE", 1) / 2) - 8
  for i = 0, 2 do fill(img, ax + i, H - 10 + i, ax + i, H - 10 + 4 - i, cr) end
  ax = math.floor(W * 0.27 + text_w("MOVE", 1) / 2) + 5
  for i = 0, 2 do fill(img, ax + 2 - i, H - 10 + i, ax + 2 - i, H - 10 + 4 - i, cr) end
  text_c(img, "DROP", W * 0.73, H - 12, 1, cr)
  save(spr, OUT, "peggy_deck.png")
end

-- peggy_big_ticket.png 160x80 (RGBA) — the roll ticket that flies into the
-- slot: orange, notched corners, scalloped short edges, an inset frame,
-- serials up both stubs, HOOP SHOOT / LEAGUE / TICKET.
do
  local W, H = 160, 80
  local spr, img = newImage(W, H, true)
  local R = 11
  local function inside(px, py, l, t, r, b, rad, scal)
    if px < l or px > r or py < t or py > b then return false end
    -- notched corners
    for _, cn in ipairs({{l, t}, {r, t}, {l, b}, {r, b}}) do
      if (px - cn[1]) ^ 2 + (py - cn[2]) ^ 2 < rad * rad then return false end
    end
    -- scalloped short edges
    if scal then
      for _, ex in ipairs({l, r}) do
        local yy = t + rad + 3
        while yy < b - rad do
          if (px - ex) ^ 2 + (py - yy) ^ 2 < 9 then return false end
          yy = yy + 6
        end
      end
    end
    return true
  end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local px, py = x + 0.5, y + 0.5
      local c = CLEAR
      if inside(px, py, 1, 1, W - 1, H - 1, R, true) then
        local n = noise(x, y, 721)
        c = hex(ORANGE)
        if n < 0.1 then c = rgb(242, 150, 92) elseif n > 0.92 then c = rgb(200, 90, 44) end
        local f = inside(px, py, 24, 8, W - 24, H - 8, 7, false)
        local f2 = inside(px, py, 26, 10, W - 26, H - 10, 6, false)
        if f and not f2 then c = hex("#A8421C") end
      end
      img:drawPixel(x, y, c)
    end
  end
  local ink = hex(INK)
  text_c(img, "HOOP SHOOT", W / 2, H / 2 - 21, 2, ink)
  text_c(img, "LEAGUE", W / 2, H / 2 - 6, 3, ink)
  text_c(img, "TICKET", W / 2, H / 2 + 13, 2, ink)
  -- serials up the stubs (rotated: drawn as a column of glyphs)
  local serial = "466002"
  local dk = hex("#5A2410")
  for i = 1, #serial do
    local ch = serial:sub(i, i)
    text(img, ch, 9, H - 14 - (i - 1) * 7, 1, dk)
    text(img, ch, W - 13, 6 + (i - 1) * 7, 1, dk)
  end
  save(spr, OUT, "peggy_big_ticket.png")
end

-- peggy_glow.png 32x32 (RGBA) — a bulb's star glow: radial falloff with a cross.
do
  local W, H = 32, 32
  local spr, img = newImage(W, H, true)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local dx, dy = x + 0.5 - 16, y + 0.5 - 16
      local d = math.sqrt(dx * dx + dy * dy) / 16
      local a = d < 0.25 and 1 - (d / 0.25) * 0.5 or math.max(0, 0.5 * (1 - (d - 0.25) / 0.75))
      if x == 15 or x == 16 or y == 15 or y == 16 then a = math.max(a, 0.7) end
      img:drawPixel(x, y, pc.rgba(255, 255, 255, clamp(a * 255)))
    end
  end
  save(spr, OUT, "peggy_glow.png")
end

-- peggy_mystery_<ball|net>_<rarity>.png 32x32 (RGBA) — a hidden prize: the
-- generic ball or net outline, a gold "?" and the rarity dot in the corner.
for _, kind in ipairs({"ball", "net"}) do
  for _, rar in ipairs({"common", "rare", "epic", "legend"}) do
    local W, H = 32, 32
    local spr, img = newImage(W, H, true)
    local cream = hex(CREAM)
    local tint = hex(CREAM, 36)
    local function inNet(px, py)
      -- a trapezoid (4,6)-(28,6)-(23,27)-(9,27)
      if py < 6 or py > 27 then return false end
      local t = (py - 6) / 21
      local l, r = 4 + 5 * t, 28 - 5 * t
      return px >= l and px <= r
    end
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        local px, py = x + 0.5, y + 0.5
        local c = CLEAR
        if kind == "ball" then
          local d = math.sqrt((px - 16) ^ 2 + (py - 16) ^ 2)
          if d <= 12 then c = tint end
          if d > 10.5 and d <= 12 then c = cream end
          if d < 10.5 and (math.abs(px - 16) < 0.6 or math.abs(py - 16) < 0.6) then c = hex(CREAM, 128) end
        else
          if inNet(px, py) then
            c = tint
            local t = (py - 6) / 21
            local l, r = 4 + 5 * t, 28 - 5 * t
            if px - l < 1.5 or r - px < 1.5 or py < 7.5 or py > 25.5 then c = cream end
            -- the diagonal cords
            for k = 0, 3 do
              local xa, xb = 4 + k * 8, 9 + k * 4.7
              local xl = xa + (xb - xa) * t
              if math.abs(px - xl) < 0.6 then c = hex(CREAM, 140) end
              local xa2, xb2 = 28 - k * 8, 23 - k * 4.7
              local xr = xa2 + (xb2 - xa2) * t
              if math.abs(px - xr) < 0.6 then c = hex(CREAM, 140) end
            end
            if py >= 5 and py < 7 and px >= 3 and px <= 29 then c = cream end
          end
        end
        img:drawPixel(x, y, c)
      end
    end
    text_o(img, "?", 16, 11, 2, hex(GOLD), hex(INK))
    fill(img, 23, 1, 30, 8, hex(INK)); fill(img, 24, 2, 29, 7, hex(RAR[rar]))
    save(spr, OUT, "peggy_mystery_" .. kind .. "_" .. rar .. ".png")
  end
end

-- icon_ticket.png 22x14 (RGBA) — the UI's ticket: a gold stub with notches.
do
  local W, H = 22, 14
  local spr, img = newImage(W, H, true)
  fill(img, 0, 0, W - 1, H - 1, CLEAR)
  local ink = hex(INK)
  local gold = hex(GOLD)
  local hi = rgb(250, 220, 140)
  fill(img, 1, 1, W - 2, H - 2, ink)
  fill(img, 2, 2, W - 3, H - 3, gold)
  fill(img, 2, 2, W - 3, 2, hi)
  for _, x in ipairs({0, 1, W - 2, W - 1}) do
    fill(img, x, 5, x, 8, CLEAR)
  end
  fill(img, 2, 5, 2, 8, ink); fill(img, W - 3, 5, W - 3, 8, ink)
  for y = 3, H - 4, 2 do
    img:drawPixel(7, y, ink); img:drawPixel(W - 8, y, ink)
  end
  save(spr, UI, "icon_ticket.png")
end
