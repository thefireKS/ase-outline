--- Colour maths for the outline: sRGB <-> HSV, the shading rule that turns an
-- inner colour into the colour of the pixel outlining it, and nearest-palette
-- snapping for sprites that must stay inside a fixed ramp.
--
-- Nothing here touches the Aseprite API, so it runs the same under `-b`.

local color = {}

local floor, abs = math.floor, math.abs
local max, min = math.max, math.min

local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

--- h in 0..360, s and v in 0..1.
function color.rgbToHsv(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = max(r, g, b), min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then
      h = ((g - b) / d) % 6
    elseif mx == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
    h = h * 60
  end
  return h, (mx > 0) and (d / mx) or 0, mx
end

function color.hsvToRgb(h, s, v)
  h = h % 360
  local c = v * s
  local x = c * (1 - abs((h / 60) % 2 - 1))
  local m = v - c
  local r, g, b
  if h < 60 then r, g, b = c, x, 0
  elseif h < 120 then r, g, b = x, c, 0
  elseif h < 180 then r, g, b = 0, c, x
  elseif h < 240 then r, g, b = 0, x, c
  elseif h < 300 then r, g, b = x, 0, c
  else r, g, b = c, 0, x end
  return floor((r + m) * 255 + 0.5),
         floor((g + m) * 255 + 0.5),
         floor((b + m) * 255 + 0.5)
end

--- Step `limit` degrees along the shorter arc toward `to`, no further.
--
-- A plain fraction of the way there is wrong: brown hair pulled 55% toward a
-- blue tint lands in magenta, because the short arc from warm to cool runs
-- through pink. A hard ceiling in degrees keeps warm colours warm while still
-- letting neutrals travel the whole way -- which is the shift artists actually
-- mean when they say a shadow is "hue shifted".
local function stepHue(from, to, limit)
  local d = (to - from + 540) % 360 - 180
  if d > limit then d = limit elseif d < -limit then d = -limit end
  return (from + d) % 360
end

--- The whole rule, in three moves an artist makes by hand when picking a
-- shadow off a base colour: drop the value, add a little saturation, pull the
-- hue toward a cool tint.
--
-- `ring` is 1 for the pixel touching the art, 2 for the one behind it and so
-- on, so a thick outline keeps falling off instead of reading as a flat band.
--
-- A fully desaturated source has no hue to defend, so it adopts the tint's
-- hue outright -- that is what turns grey armour into a blue-grey contour.
function color.shade(r, g, b, opt, ring)
  local h, s, v = color.rgbToHsv(r, g, b)
  if s < 0.02 then
    h = opt.hue
  else
    h = stepHue(h, opt.hue, opt.hueShift * ring)
  end
  s = clamp(s + opt.saturate * ring, 0, 1)
  v = clamp(v * (1 - opt.darken) ^ ring, 0, 1)
  return color.hsvToRgb(h, s, v)
end

--- Cheap perceptual weighting: green errors read worse than blue ones.
local function distance(dr, dg, db)
  return 2 * dr * dr + 4 * dg * dg + 3 * db * db
end

--- Returns a function mapping an arbitrary rgb to the closest entry in
-- `palette`, memoised -- pixel art has few distinct colours, so the second
-- lookup onward is free. `skip` is the transparent index, excluded from the
-- search so an outline never lands on "invisible".
function color.paletteSnapper(palette, skip)
  local n = #palette
  local pr, pg, pb, idx = {}, {}, {}, {}
  local count = 0
  for i = 0, n - 1 do
    if i ~= skip then
      local c = palette:getColor(i)
      count = count + 1
      pr[count], pg[count], pb[count], idx[count] = c.red, c.green, c.blue, i
    end
  end

  local cache = {}
  return function(r, g, b)
    local key = r * 65536 + g * 256 + b
    local hit = cache[key]
    if hit then return hit[1], hit[2], hit[3], hit[4] end

    local best, bestD = 1, math.huge
    for i = 1, count do
      local d = distance(r - pr[i], g - pg[i], b - pb[i])
      if d < bestD then best, bestD = i, d end
    end
    local found = { pr[best], pg[best], pb[best], idx[best] }
    cache[key] = found
    return found[1], found[2], found[3], found[4]
  end
end

return color
