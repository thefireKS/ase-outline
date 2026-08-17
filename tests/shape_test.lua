-- The geometry half: what the 3x3 mask means, where Outside and Inside put
-- pixels, how far the image grows, and that a selection clips the result.
-- Run from the project root: aseprite -b --script tests/shape_test.lua

local ROOT = app.fs.currentPath
package.path = app.fs.joinPath(ROOT, "src", "?.lua") .. ";" .. package.path

local outline = require("outline")
local matrix = require("matrix")
local apply = require("apply")

local SHADE = { hue = 234, hueShift = 45, darken = 0.38, saturate = 0.18 }

local function opts(over)
  local o = {}
  for k, v in pairs(SHADE) do o[k] = v end
  o.thickness, o.place, o.alpha = 1, "outside", 255
  for k, v in pairs(over or {}) do o[k] = v end
  return o
end

--- A solid block of one colour, as the flat array outline.build takes.
local function block(w, h, colour)
  local src = {}
  for i = 1, w * h do src[i] = colour or 0xFFFFFF end
  return src, w, h
end

--- Render source + outline to ASCII: '#' art, 'o' outline, '.' empty.
local function picture(src, w, h, out, W, H, offX, offY)
  local rows = {}
  for y = 0, H - 1 do
    local row = {}
    for x = 0, W - 1 do
      local ch = "."
      if out[y * W + x + 1] then
        ch = "o"
      else
        local sx, sy = x + offX, y + offY
        if sx >= 0 and sx < w and sy >= 0 and sy < h and src[sy * w + sx + 1] then
          ch = "#"
        end
      end
      row[#row + 1] = ch
    end
    rows[#rows + 1] = table.concat(row)
  end
  return rows
end

local function show(label, rows)
  print(label)
  for _, r in ipairs(rows) do print("   " .. r) end
end

local function check(label, rows, expected)
  show(label, rows)
  local got, want = table.concat(rows, "/"), table.concat(expected, "/")
  assert(got == want, ("%s\n  expected %s\n  got      %s"):format(label, want, got))
end

local function run(mask, over)
  local src, w, h = block(3, 3)
  local o = opts(over)
  o.offsets = matrix.offsets(mask)
  local out, W, H, offX, offY = outline.build(src, w, h, o)
  return picture(src, w, h, out, W, H, offX, offY), W, H
end

print("=== mask encoding ===")
assert(matrix.PRESETS.square == 495, "square must match Aseprite's stored 495")
assert(matrix.presetName(495) == "square")
assert(matrix.presetName(170) == "circle")
assert(matrix.presetName(0) == nil)
assert(not matrix.has(495, matrix.CENTRE), "the centre is never lit")
assert(matrix.set(0, matrix.CENTRE, true) == 0, "the centre cannot be lit")
print("  presets: circle=170 square=495 horizontal=40 vertical=130  ok")

print("=== a lit cell is where the contour goes ===")
-- cell 7 is bottom-centre
check("bottom only", run(1 << 7), { "###", "###", "###", "ooo" })
check("top only", run(1 << 1), { "ooo", "###", "###", "###" })
check("left only", run(1 << 3), { "o###", "o###", "o###" })
check("right only", run(1 << 5), { "###o", "###o", "###o" })

print("=== presets ===")
check("circle", run(matrix.PRESETS.circle),
  { ".ooo.", "o###o", "o###o", "o###o", ".ooo." })
check("square", run(matrix.PRESETS.square),
  { "ooooo", "o###o", "o###o", "o###o", "ooooo" })
check("horizontal", run(matrix.PRESETS.horizontal),
  { "o###o", "o###o", "o###o" })
-- "Vertical" names the axis the contour runs along, so it lands top and
-- bottom -- matching what the built-in command produces for the same preset.
check("vertical", run(matrix.PRESETS.vertical),
  { "ooo", "###", "###", "###", "ooo" })

print("=== growth is per side ===")
local _, W, H = run(matrix.PRESETS.horizontal)
assert(W == 5 and H == 3, ("horizontal grew to %dx%d, wanted 5x3"):format(W, H))
local _, W2, H2 = run(1 << 7)
assert(W2 == 3 and H2 == 4, ("bottom-only grew to %dx%d, wanted 3x4"):format(W2, H2))
print("  horizontal 3x3 -> 5x3, bottom-only 3x3 -> 3x4  ok")

print("=== thickness ===")
check("circle, thickness 2", run(matrix.PRESETS.circle, { thickness = 2 }),
  { "..ooo..", ".ooooo.", "oo###oo", "oo###oo", "oo###oo", ".ooooo.", "..ooo.." })

print("=== inside ===")
local src5, w5, h5 = block(5, 5)
local oIn = opts{ place = "inside" }
oIn.offsets = matrix.offsets(matrix.PRESETS.square)
local out5, W5, H5, ox5, oy5 = outline.build(src5, w5, h5, oIn)
check("inside, square, thickness 1",
  picture(src5, w5, h5, out5, W5, H5, ox5, oy5),
  { "ooooo", "o###o", "o###o", "o###o", "ooooo" })
assert(W5 == 5 and H5 == 5, "an inward outline must not grow the image")

local oIn2 = opts{ place = "inside", thickness = 2 }
oIn2.offsets = matrix.offsets(matrix.PRESETS.square)
local out5b, W5b, H5b, ox5b, oy5b = outline.build(src5, w5, h5, oIn2)
check("inside, square, thickness 2",
  picture(src5, w5, h5, out5b, W5b, H5b, ox5b, oy5b),
  { "ooooo", "ooooo", "oo#oo", "ooooo", "ooooo" })

print("=== an empty mask draws nothing ===")
local outNone = outline.build(block(3, 3), 3, 3, opts{ offsets = {} })
assert(next(outNone) == nil, "no lit cells must mean no pixels")
print("  ok")

print("=== selection clips the result ===")
local sprite = Sprite(9, 9, ColorMode.RGB)
local img = Image(3, 3, ColorMode.RGB)
for y = 0, 2 do for x = 0, 2 do
  img:drawPixel(x, y, app.pixelColor.rgba(200, 200, 210, 255))
end end
for _, c in ipairs(sprite.cels) do sprite:deleteCel(c) end
sprite:newCel(sprite.layers[1], 1, img, Point(3, 3))

local o = opts()
o.offsets = matrix.offsets(matrix.PRESETS.square)

local full = apply.forCel(sprite.cels[1], o)
local countFull = 0
for it in full:pixels() do if app.pixelColor.rgbaA(it()) > 0 then countFull = countFull + 1 end end
assert(countFull == 16, ("unclipped square outline should be 16 px, got %d"):format(countFull))

-- Keep only the rows above the block's middle; the lower half must vanish.
o.selection = Selection(Rectangle(0, 0, 9, 4))
local clipped = apply.forCel(sprite.cels[1], o)
local countClipped, lowest = 0, -1
for it in clipped:pixels() do
  if app.pixelColor.rgbaA(it()) > 0 then
    countClipped = countClipped + 1
    lowest = math.max(lowest, it.y)
  end
end
print(("  unclipped %d px, clipped %d px, lowest row %d"):format(countFull, countClipped, lowest))
assert(countClipped < countFull, "the selection did not remove anything")
assert(lowest + 2 <= 3, "outline survived below the selection")

-- A selection that misses the outline entirely yields nothing at all.
o.selection = Selection(Rectangle(0, 0, 1, 1))
assert(apply.forCel(sprite.cels[1], o) == nil,
  "a selection with no overlap should produce no cel")
print("  a non-overlapping selection produces no cel  ok")

print("ok")
