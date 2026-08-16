--- Bridges the pixel logic to Aseprite: reads a cel through whatever colour
-- mode the sprite happens to be in, grows the outline, and hands back an image
-- ready to drop on a layer.

local color = require("color")
local outline = require("outline")

local apply = {}

local floor = math.floor

--- Packs a cel pixel into rgb, or nil where the silhouette has a hole.
-- Semi-transparent pixels count as part of the shape: art with soft edges
-- should still get a contour, and the alpha itself is not carried over.
local function reader(image, sprite)
  local pc = app.pixelColor
  local mode = image.colorMode

  if mode == ColorMode.RGB then
    return function(v)
      if pc.rgbaA(v) == 0 then return nil end
      return pc.rgbaR(v) * 65536 + pc.rgbaG(v) * 256 + pc.rgbaB(v)
    end
  elseif mode == ColorMode.GRAY then
    return function(v)
      if pc.grayaA(v) == 0 then return nil end
      local g = pc.grayaV(v)
      return g * 65536 + g * 256 + g
    end
  end

  local palette, skip = sprite.palettes[1], sprite.transparentColor
  return function(v)
    if v == skip then return nil end
    local c = palette:getColor(v)
    if c.alpha == 0 then return nil end
    return c.red * 65536 + c.green * 256 + c.blue
  end
end

--- Turns a computed rgb back into a pixel value. Indexed sprites snap to the
-- palette whether or not the option is on -- there is nowhere else to put a
-- colour -- which is also why an indexed run can only ever be as good as the
-- ramp already in the file.
local function writer(image, sprite, opt)
  local pc = app.pixelColor
  local mode = image.colorMode

  if mode == ColorMode.INDEXED then
    local snap = color.paletteSnapper(sprite.palettes[1], sprite.transparentColor)
    return function(r, g, b)
      local _, _, _, index = snap(r, g, b)
      return index
    end
  elseif mode == ColorMode.GRAY then
    return function(r, g, b)
      return pc.graya(floor(0.299 * r + 0.587 * g + 0.114 * b + 0.5), opt.alpha)
    end
  end

  local snap = opt.snap
      and color.paletteSnapper(sprite.palettes[1], sprite.transparentColor)
      or nil
  return function(r, g, b)
    if snap then r, g, b = snap(r, g, b) end
    return pc.rgba(r, g, b, opt.alpha)
  end
end

--- Returns the outline image for one cel and the position it belongs at, or
-- nil for an empty cel. The image is grown by `thickness` on every side, so
-- the outline is free to sit outside the cel's old bounds.
function apply.forCel(cel, opt)
  local sprite = cel.sprite
  local image = cel.image
  local w, h = image.width, image.height

  local read = reader(image, sprite)
  local src, any = {}, false
  for it in image:pixels() do
    local c = read(it())
    if c then
      src[it.y * w + it.x + 1] = c
      any = true
    end
  end
  if not any then return nil end

  local out, W, H = outline.build(src, w, h, opt)

  local dst = Image(W, H, image.colorMode)
  dst:clear(image.colorMode == ColorMode.INDEXED and sprite.transparentColor or 0)

  local write = writer(image, sprite, opt)
  for idx, c in pairs(out) do
    local i = idx - 1
    dst:drawPixel(i % W, floor(i / W),
      write(floor(c / 65536) % 256, floor(c / 256) % 256, c % 256))
  end

  local t = opt.thickness
  return dst, Point(cel.position.x - t, cel.position.y - t)
end

return apply
