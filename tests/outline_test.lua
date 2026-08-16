-- Renders a small figure with several distinct colours before and after the
-- outline, at 8x, so the result can be judged by eye rather than by assertion.
-- Run from the project root: aseprite -b --script tests/outline_test.lua

local ROOT = app.fs.currentPath
package.path = app.fs.joinPath(ROOT, "src", "?.lua") .. ";" .. package.path

local apply = require("apply")
local outline = require("outline")

local OUT = app.fs.joinPath(ROOT, "out")
if not app.fs.isDirectory(OUT) then app.fs.makeDirectory(OUT) end

local ART = {
  "......hhhh......",
  ".....hhhhhh.....",
  ".....hkkkkh.....",
  ".....hkkkkh.....",
  ".....kkkkkk.....",
  "......kkkk......",
  "...wwaaaaaaAA...",
  "..wwwaabbbaAAA..",
  "..wwwaabbbaAAA..",
  "..wwwaaaaaaAAA..",
  "..ww.aaaaaa.AA..",
  ".....aaaaaa.....",
  ".....aaaaaa.....",
  ".....aaaaaa.....",
  ".....aa..aa.....",
  ".....aa..aa.....",
  ".....AA..AA.....",
  ".....AA..AA.....",
  "....www..www....",
  "....www..www....",
}

-- Deliberately mixed: warm hair and skin next to neutral greys next to a
-- saturated blue, because those three behave differently under the hue rule.
local PALETTE = {
  h = Color{ r = 107, g = 74, b = 47 },
  k = Color{ r = 242, g = 214, b = 168 },
  w = Color{ r = 232, g = 232, b = 240 },
  a = Color{ r = 168, g = 168, b = 176 },
  A = Color{ r = 110, g = 110, b = 120 },
  b = Color{ r = 90, g = 180, b = 224 },
}

local W, H = #ART[1], #ART

local function buildSprite()
  local sprite = Sprite(W + 6, H + 6, ColorMode.RGB)
  local image = Image(W, H, ColorMode.RGB)
  image:clear(0)
  for y = 1, H do
    for x = 1, W do
      local c = PALETTE[ART[y]:sub(x, x)]
      if c then image:drawPixel(x - 1, y - 1, c) end
    end
  end
  for _, cel in ipairs(sprite.cels) do sprite:deleteCel(cel) end
  sprite:newCel(sprite.layers[1], 1, image, Point(3, 3))
  return sprite
end

local function save(sprite, name)
  app.command.SpriteSize{ ui = false, scale = 8, method = "nearest" }
  sprite:saveCopyAs(app.fs.joinPath(OUT, name))
end

local function outlined(opt)
  local sprite = buildSprite()
  local cel = sprite.cels[1]
  local image, position = apply.forCel(cel, opt)
  assert(image, "forCel returned nothing for a non-empty cel")

  local layer = sprite:newLayer()
  layer.name = "outline"
  layer.stackIndex = cel.layer.stackIndex
  assert(layer.stackIndex < cel.layer.stackIndex, "outline must sit under the art")
  sprite:newCel(layer, 1, image, position)
  return sprite, image, position
end

local BASE = {
  hue = 234, hueShift = 45, darken = 0.38, saturate = 0.18,
  thickness = 1, matrix = outline.MATRIX.circle, alpha = 255,
}

local function with(over)
  local o = {}
  for k, v in pairs(BASE) do o[k] = v end
  for k, v in pairs(over) do o[k] = v end
  return o
end

local before = buildSprite()
save(before, "before.png")
before:close()

local sprite, image, position = outlined(BASE)
print(("thin: %dx%d at %d,%d"):format(image.width, image.height, position.x, position.y))
assert(image.width == W + 2 and image.height == H + 2, "thickness 1 grows by one on each side")
assert(position.x == 2 and position.y == 2, "outline cel shifts back by the thickness")
save(sprite, "after.png")

local thick = outlined(with{ thickness = 2, matrix = outline.MATRIX.square })
save(thick, "after_thick.png")

-- The hue cap is the whole reason `hueShift` is in degrees: brown hair must
-- not come out magenta.
local color = require("color")
local hr, hg, hb = color.shade(107, 74, 47, BASE, 1)
local hh = color.rgbToHsv(hr, hg, hb)
assert(hh > 300 or hh < 60, ("brown outline drifted to hue %.0f"):format(hh))
print(("brown 107,74,47 -> %d,%d,%d (hue %.0f)"):format(hr, hg, hb, hh))

-- A neutral has no hue to defend and should land on the tint outright.
local gr, gg, gb = color.shade(168, 168, 176, BASE, 1)
print(("grey 168,168,176 -> %d,%d,%d"):format(gr, gg, gb))
assert(gb > gr, "grey should come out cooler than it went in")

print("ok")
