--- Grows a coloured outline around a silhouette.
--
-- Works on plain Lua arrays of packed rgb (or nil for transparent), not on
-- Aseprite Images, so the pixel logic is testable headless and the caller
-- stays responsible for colour-mode conversion.

local color = require("color")

local outline = {}

local floor = math.floor

--- Offsets with a vote weight. An orthogonal neighbour says more about which
-- shape an outline pixel belongs to than a diagonal one, so it counts double:
-- on a corner where a white arm meets dark armour, the contour keeps the
-- colour of the side it actually runs along.
local ORTHO = { { 1, 0, 2 }, { -1, 0, 2 }, { 0, 1, 2 }, { 0, -1, 2 } }
local DIAG = { { 1, 1, 1 }, { 1, -1, 1 }, { -1, 1, 1 }, { -1, -1, 1 } }

local ROUND, SQUARE = {}, {}
for i, n in ipairs(ORTHO) do ROUND[i] = n; SQUARE[i] = n end
for i, n in ipairs(DIAG) do SQUARE[#ORTHO + i] = n end

outline.MATRIX = { circle = ROUND, square = SQUARE }

--- One dilation step. Every opaque pixel votes for its transparent
-- neighbours; each of those becomes an outline pixel in the colour that won.
--
-- Ties break toward the lower packed value so a rerun on the same art gives
-- the same pixels -- `pairs` order alone would not.
local function ring(filled, w, h, matrix)
  local votes, touched, count = {}, {}, 0

  for idx, c in pairs(filled) do
    local i = idx - 1
    local x, y = i % w, floor(i / w)
    for _, n in ipairs(matrix) do
      local nx, ny = x + n[1], y + n[2]
      if nx >= 0 and nx < w and ny >= 0 and ny < h then
        local ni = ny * w + nx + 1
        if filled[ni] == nil then
          local t = votes[ni]
          if not t then
            t = {}
            votes[ni] = t
            count = count + 1
            touched[count] = ni
          end
          t[c] = (t[c] or 0) + n[3]
        end
      end
    end
  end

  local won = {}
  for i = 1, count do
    local ni = touched[i]
    local best, bestWeight = nil, -1
    for c, weight in pairs(votes[ni]) do
      if weight > bestWeight or (weight == bestWeight and c < best) then
        best, bestWeight = c, weight
      end
    end
    won[ni] = best
  end
  return won
end

--- Build the outline for a silhouette.
--
-- `src` is a 1-based flat array of w*h packed rgb values (r<<16|g<<8|b), nil
-- where transparent. Returns a same-shaped array holding only the outline
-- pixels, sized for the padded canvas, plus its dimensions.
--
-- opt: hue (0..360), pull, darken, saturate (0..1), thickness, matrix.
function outline.build(src, w, h, opt)
  local t = opt.thickness
  local W, H = w + 2 * t, h + 2 * t
  local matrix = opt.matrix or SQUARE

  local filled = {}
  for y = 0, h - 1 do
    local row, prow = y * w, (y + t) * W + t
    for x = 0, w - 1 do
      local c = src[row + x + 1]
      if c then filled[prow + x + 1] = c end
    end
  end

  -- Cache the shading per (source colour, ring): art tends to hold a few dozen
  -- distinct colours, so this collapses the per-pixel HSV round trip.
  local shaded = {}
  for i = 1, t do shaded[i] = {} end

  local out = {}
  for r = 1, t do
    local grown = ring(filled, W, H, matrix)
    local cache = shaded[r]
    for idx, c in pairs(grown) do
      filled[idx] = c
      local hit = cache[c]
      if not hit then
        local sr, sg, sb = color.shade(
          floor(c / 65536) % 256, floor(c / 256) % 256, c % 256,
          opt, r)
        hit = sr * 65536 + sg * 256 + sb
        cache[c] = hit
      end
      out[idx] = hit
    end
  end

  return out, W, H
end

return outline
