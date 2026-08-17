--- Grows a coloured outline around (or just inside) a silhouette.
--
-- Works on plain Lua arrays of packed rgb -- nil for transparent -- rather than
-- on Aseprite Images, so the pixel logic is testable headless and the caller
-- stays responsible for colour-mode conversion and clipping.

local color = require("color")

local outline = {}

local floor = math.floor

local function unpackRgb(c)
  return floor(c / 65536) % 256, floor(c / 256) % 256, c % 256
end

--- Memoised shading, keyed by source colour and ring. Art holds a few dozen
-- distinct colours at most, so this collapses the per-pixel HSV round trip.
local function shader(opt)
  local rings = {}
  return function(c, ring)
    local cache = rings[ring]
    if not cache then cache = {}; rings[ring] = cache end
    local hit = cache[c]
    if not hit then
      local sr, sg, sb = unpackRgb(c)
      local r, g, b = color.shade(sr, sg, sb, opt, ring)
      hit = r * 65536 + g * 256 + b
      cache[c] = hit
    end
    return hit
  end
end

--- How far the outline reaches past the art, per side.
--
-- An outline pixel at p is there because art sits at p + offset, so the contour
-- extends against each offset. A horizontal-only mask therefore needs no room
-- above or below, and the cel does not grow in a direction nothing was drawn.
local function padding(offsets, thickness)
  local left, right, top, bottom = 0, 0, 0, 0
  for _, o in ipairs(offsets) do
    local ox, oy = o[1], o[2]
    if ox > 0 then left = math.max(left, ox) end
    if ox < 0 then right = math.max(right, -ox) end
    if oy > 0 then top = math.max(top, oy) end
    if oy < 0 then bottom = math.max(bottom, -oy) end
  end
  return left * thickness, right * thickness, top * thickness, bottom * thickness
end

--- One outward step. Every opaque pixel votes for the neighbours the mask
-- points at; each of those becomes an outline pixel in the colour that won.
--
-- Ties break toward the lower packed value so a rerun on the same art gives the
-- same pixels -- `pairs` order alone would not.
local function grow(filled, w, h, offsets)
  local votes, touched, count = {}, {}, 0

  for idx, c in pairs(filled) do
    local i = idx - 1
    local x, y = i % w, floor(i / w)
    for _, o in ipairs(offsets) do
      local nx, ny = x - o[1], y - o[2]
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
          t[c] = (t[c] or 0) + o[3]
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

--- One inward step: opaque pixels that the mask says are on the rim, because
-- what they point at is empty or has already been eaten by an earlier ring.
--
-- Off-image counts as empty. Cels are trimmed to their art, so a pixel on the
-- image border really is on the silhouette's edge.
local function erode(remaining, w, h, offsets)
  local rim = {}
  for idx, c in pairs(remaining) do
    local i = idx - 1
    local x, y = i % w, floor(i / w)
    for _, o in ipairs(offsets) do
      local nx, ny = x - o[1], y - o[2]
      if nx < 0 or nx >= w or ny < 0 or ny >= h
         or remaining[ny * w + nx + 1] == nil then
        rim[idx] = c
        break
      end
    end
  end
  return rim
end

--- Build the outline for a silhouette.
--
-- `src` is a 1-based flat array of w*h packed rgb values, nil where
-- transparent. Returns the outline pixels in the same flat form, the
-- dimensions of the image they belong in, and the offset of that image from
-- the source's origin (negative when the contour grew outward).
--
-- opt: hue, hueShift, darken, saturate, thickness, offsets, place.
function outline.build(src, w, h, opt)
  local thickness = opt.thickness
  local offsets = opt.offsets
  local shade = shader(opt)
  local out = {}

  if #offsets == 0 then return out, w, h, 0, 0 end

  if opt.place == "inside" then
    local remaining = {}
    for idx, c in pairs(src) do remaining[idx] = c end

    for ring = 1, thickness do
      local rim = erode(remaining, w, h, offsets)
      local empty = true
      for idx, c in pairs(rim) do
        empty = false
        remaining[idx] = nil
        out[idx] = shade(c, ring)
      end
      if empty then break end
    end
    return out, w, h, 0, 0
  end

  local left, right, top, bottom = padding(offsets, thickness)
  local W, H = w + left + right, h + top + bottom

  local filled = {}
  for y = 0, h - 1 do
    local row, prow = y * w, (y + top) * W + left
    for x = 0, w - 1 do
      local c = src[row + x + 1]
      if c then filled[prow + x + 1] = c end
    end
  end

  for ring = 1, thickness do
    local ground = grow(filled, W, H, offsets)
    local empty = true
    for idx, c in pairs(ground) do
      empty = false
      filled[idx] = c
      out[idx] = shade(c, ring)
    end
    if empty then break end
  end

  return out, W, H, -left, -top
end

return outline
