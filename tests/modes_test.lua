-- Colour modes, the empty-cel refusal, and palette snapping. The dialog is not
-- reachable under -b, so this also just parses main.lua and checks the one
-- Color property it depends on.
-- Run from the project root: aseprite -b --script tests/modes_test.lua

local ROOT = app.fs.currentPath
package.path = app.fs.joinPath(ROOT, "src", "?.lua") .. ";" .. package.path

local apply = require("apply")
local outline = require("outline")
local color = require("color")

local OUT = app.fs.joinPath(ROOT, "out")
if not app.fs.isDirectory(OUT) then app.fs.makeDirectory(OUT) end

local ok, err = loadfile(app.fs.joinPath(ROOT, "main.lua"))
assert(ok, "main.lua does not parse: " .. tostring(err))
print("main.lua: parses")

local probe = Color{ r = 60, g = 70, b = 160 }
assert(type(probe.hsvHue) == "number", "Dialog colour has no hsvHue")
print(("Color.hsvHue = %s"):format(tostring(probe.hsvHue)))

local OPT = {
  hue = 234, hueShift = 45, darken = 0.38, saturate = 0.18,
  thickness = 1, matrix = outline.MATRIX.circle, alpha = 255,
}

--- A ten-wide blob with clipped corners, light on top and dark below.
local function blob(image, put)
  for y = 2, 11 do
    for x = 2, 11 do
      if not ((x == 2 or x == 11) and (y == 2 or y == 11)) then
        put(image, x, y, (y < 7) and 1 or 2)
      end
    end
  end
end

-- INDEXED: the outline has nowhere to go but the existing ramp, and must never
-- land on the transparent index.
local sprite = Sprite(16, 16, ColorMode.INDEXED)
local pal = Palette(6)
pal:setColor(0, Color{ r = 0, g = 0, b = 0, a = 0 })
pal:setColor(1, Color{ r = 200, g = 200, b = 210 })
pal:setColor(2, Color{ r = 120, g = 120, b = 130 })
pal:setColor(3, Color{ r = 70, g = 76, b = 105 })
pal:setColor(4, Color{ r = 42, g = 46, b = 70 })
pal:setColor(5, Color{ r = 20, g = 22, b = 36 })
sprite:setPalette(pal)
sprite.transparentColor = 0

local img = Image(16, 16, ColorMode.INDEXED)
img:clear(0)
blob(img, function(im, x, y, v) im:drawPixel(x, y, v) end)
for _, cel in ipairs(sprite.cels) do sprite:deleteCel(cel) end
sprite:newCel(sprite.layers[1], 1, img, Point(0, 0))

local out, pos = apply.forCel(sprite.cels[1], OPT)
assert(out, "indexed: no outline")
assert(out.colorMode == ColorMode.INDEXED, "indexed: outline changed colour mode")

local used = {}
for it in out:pixels() do
  local v = it()
  if v ~= sprite.transparentColor then used[v] = (used[v] or 0) + 1 end
end
local indices = {}
for k in pairs(used) do indices[#indices + 1] = k end
table.sort(indices)
assert(#indices > 0, "indexed: outline is empty")
for _, i in ipairs(indices) do
  assert(i ~= sprite.transparentColor, "indexed: outline landed on the transparent index")
end
print("indexed outline uses palette indices: " .. table.concat(indices, ", "))

local layer = sprite:newLayer()
layer.stackIndex = 1
sprite:newCel(layer, 1, out, pos)
app.command.SpriteSize{ ui = false, scale = 10, method = "nearest" }
sprite:saveCopyAs(app.fs.joinPath(OUT, "indexed.png"))

-- GRAYSCALE
local gs = Sprite(16, 16, ColorMode.GRAY)
local gimg = Image(16, 16, ColorMode.GRAY)
gimg:clear(0)
blob(gimg, function(im, x, y, v)
  im:drawPixel(x, y, app.pixelColor.graya(v == 1 and 210 or 130, 255))
end)
for _, cel in ipairs(gs.cels) do gs:deleteCel(cel) end
gs:newCel(gs.layers[1], 1, gimg, Point(0, 0))

local gout = apply.forCel(gs.cels[1], OPT)
assert(gout and gout.colorMode == ColorMode.GRAY, "gray: bad outline")
print("gray: ok")

-- An empty cel is refused, not crashed on.
local blank = Sprite(8, 8, ColorMode.RGB)
local bimg = Image(8, 8, ColorMode.RGB)
bimg:clear(0)
for _, cel in ipairs(blank.cels) do blank:deleteCel(cel) end
blank:newCel(blank.layers[1], 1, bimg, Point(0, 0))
assert(apply.forCel(blank.cels[1], OPT) == nil, "empty cel should yield nothing")
print("empty cel: refused")

-- Snapping lands on a real entry and skips the transparent one.
local snap = color.paletteSnapper(pal, 0)
local r, g, b, i = snap(66, 72, 100)
assert(i == 3, ("snap picked index %d, expected 3"):format(i))
print(("snap(66,72,100) -> index %d = %d,%d,%d"):format(i, r, g, b))

print("ok")
