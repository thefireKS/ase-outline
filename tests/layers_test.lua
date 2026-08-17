-- Where the outline layer ends up. Outward outlines render behind the art and
-- inward ones in front, so the placement has to be right in both directions
-- and has to survive being flipped from one to the other.
-- Run from the project root: aseprite -b --script tests/layers_test.lua

local ROOT = app.fs.currentPath
package.path = app.fs.joinPath(ROOT, "src", "?.lua") .. ";" .. package.path

local layers = require("layers")

local NAME = "art outline"

local function names(parent)
  local out = {}
  for _, l in ipairs(parent.layers) do out[#out + 1] = l.name end
  return table.concat(out, " < ")
end

local sprite = Sprite(8, 8, ColorMode.RGB)
sprite.layers[1].name = "art"
local art = sprite.layers[1]

print("=== created below for an outward outline ===")
local below = layers.outlineFor(sprite, art, NAME, false)
print("  " .. names(sprite))
assert(below.name == "art outline", "wrong name: " .. below.name)
assert(below.stackIndex == art.stackIndex - 1,
  ("outline at %d, art at %d"):format(below.stackIndex, art.stackIndex))

print("=== flipped above for an inward outline, same layer reused ===")
local above = layers.outlineFor(sprite, art, NAME, true)
print("  " .. names(sprite))
assert(above == below, "a second call must reuse the layer, not add one")
assert(#sprite.layers == 2, ("layer count grew to %d"):format(#sprite.layers))
assert(above.stackIndex == art.stackIndex + 1,
  ("outline at %d, art at %d"):format(above.stackIndex, art.stackIndex))

print("=== and back down again ===")
local back = layers.outlineFor(sprite, art, NAME, false)
print("  " .. names(sprite))
assert(#sprite.layers == 2, "flipping back must not add a layer")
assert(back.stackIndex == art.stackIndex - 1, "did not return below the art")

print("=== crossing works with other layers in the stack ===")
local under = sprite:newLayer()
under.name = "background"
under.stackIndex = 1
local over = sprite:newLayer()
over.name = "fx"
print("  " .. names(sprite))
assert(layers.stackNextTo(back, art, true), "could not park above the art")
print("  above -> " .. names(sprite))
assert(back.stackIndex == art.stackIndex + 1)
assert(layers.stackNextTo(back, art, false), "could not park below the art")
print("  below -> " .. names(sprite))
assert(back.stackIndex == art.stackIndex - 1)
assert(#sprite.layers == 4, "stack lost or gained a layer while moving")

print("=== a second source gets its own outline layer ===")
local other = sprite:newLayer()
other.name = "cape"
local capeOutline = layers.outlineFor(sprite, other, "cape outline", false)
print("  " .. names(sprite))
assert(capeOutline.name == "cape outline")
assert(capeOutline ~= back, "outlines for different layers must not collide")
assert(capeOutline.stackIndex == other.stackIndex - 1)

print("ok")
