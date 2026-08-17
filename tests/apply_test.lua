-- Apply, end to end: keep the ring, then grow the next one around it. Two
-- Applies must leave two rings on two layers, not one layer drawn twice.
-- Run from the project root: aseprite -b --script tests/apply_test.lua

local ROOT = app.fs.currentPath
package.path = app.fs.joinPath(ROOT, "src", "?.lua") .. ";" .. package.path

local apply = require("apply")
local layers = require("layers")
local matrix = require("matrix")
local targets = require("targets")

local OPT = {
  hue = 234, hueShift = 45, darken = 38 / 100, saturate = 18 / 100,
  thickness = 1, place = "outside", alpha = 255,
  offsets = matrix.offsets(matrix.PRESETS.square),
}

local sprite = Sprite(16, 16, ColorMode.RGB)
sprite.layers[1].name = "art"
local art = sprite.layers[1]

local img = Image(3, 3, ColorMode.RGB)
for y = 0, 2 do for x = 0, 2 do
  img:drawPixel(x, y, app.pixelColor.rgba(200, 200, 210, 255))
end end
for _, c in ipairs(sprite.cels) do sprite:deleteCel(c) end
sprite:newCel(art, 1, img, Point(6, 6))
app.sprite = sprite

--- One pass of what the dialog's render() does.
local function pass(list, generation)
  local written = {}
  for _, t in ipairs(list) do
    local shape, at = t.image, t.position
    if not shape then
      local cel = t.layer:cel(t.frame)
      assert(cel, "target has no cel on frame " .. t.frame)
      shape, at = cel.image, cel.position
    end

    local ring, ringAt = apply.forImage(shape, at, sprite, OPT)
    assert(ring, "pass " .. generation .. " drew nothing")
    local layer = layers.outlineFor(
      sprite, t.layer, targets.nameFor(t.base, generation), false)
    local existing = layer:cel(t.frame)
    if existing then sprite:deleteCel(existing) end
    sprite:newCel(layer, t.frame, ring, ringAt)

    local grown, grownAt = apply.union(shape, at, ring, ringAt)
    written[#written + 1] = {
      layer = layer, frame = t.frame, base = t.base,
      image = grown, position = grownAt,
    }
  end
  return written
end

local function bounds(layer)
  local cel = layer:cel(1)
  return cel.bounds
end

local function opaque(layer)
  local n = 0
  for it in layer:cel(1).image:pixels() do
    if app.pixelColor.rgbaA(it()) > 0 then n = n + 1 end
  end
  return n
end

local function names()
  local out = {}
  for _, l in ipairs(sprite.layers) do out[#out + 1] = l.name end
  return table.concat(out, " < ")
end

local snap = targets.snapshot(art, 1, {})

print("=== first Apply ===")
local first = pass(targets.forScope(sprite, snap, "cel"), 1)
print("  " .. names())
assert(#sprite.layers == 2, ("layer count %d, wanted 2"):format(#sprite.layers))
local ring1 = first[1].layer
assert(ring1.name == "art outline", ring1.name)
assert(opaque(ring1) == 16, ("ring 1 has %d px, wanted 16"):format(opaque(ring1)))
print(("  ring 1: %s, %d px"):format(tostring(bounds(ring1)), opaque(ring1)))

print("=== second Apply grows around the first ===")
local second = pass(targets.advance(first), 2)
print("  " .. names())
assert(#sprite.layers == 3, ("layer count %d, wanted 3"):format(#sprite.layers))
local ring2 = second[1].layer
assert(ring2.name == "art outline 2", ring2.name)
assert(ring2 ~= ring1, "the second ring overwrote the first")
assert(opaque(ring1) == 16, "the first ring was disturbed")
assert(opaque(ring2) == 24, ("ring 2 has %d px, wanted 24"):format(opaque(ring2)))
print(("  ring 2: %s, %d px"):format(tostring(bounds(ring2)), opaque(ring2)))

local b1, b2 = bounds(ring1), bounds(ring2)
assert(b2.width == b1.width + 2 and b2.height == b1.height + 2,
  "the second ring should be one pixel wider on each side")
assert(b2.x == b1.x - 1 and b2.y == b1.y - 1, "the second ring is off centre")

print("=== the rings do not overlap ===")
local img1, img2 = ring1:cel(1).image, ring2:cel(1).image
local overlaps = 0
for it in img2:pixels() do
  if app.pixelColor.rgbaA(it()) > 0 then
    local x, y = it.x + b2.x - b1.x, it.y + b2.y - b1.y
    if x >= 0 and x < img1.width and y >= 0 and y < img1.height
       and app.pixelColor.rgbaA(img1:getPixel(x, y)) > 0 then
      overlaps = overlaps + 1
    end
  end
end
assert(overlaps == 0, ("%d px of ring 2 land on ring 1"):format(overlaps))
print("  ok")

print("=== each ring is darker than the one inside it ===")
local function sample(layer)
  for it in layer:cel(1).image:pixels() do
    local v = it()
    if app.pixelColor.rgbaA(v) > 0 then
      return app.pixelColor.rgbaR(v) + app.pixelColor.rgbaG(v) + app.pixelColor.rgbaB(v)
    end
  end
end
local lum1, lum2 = sample(ring1), sample(ring2)
print(("  ring 1 sums to %d, ring 2 to %d"):format(lum1, lum2))
assert(lum2 < lum1, "the outer ring should be darker, being shaded off the inner one")

print("ok")
