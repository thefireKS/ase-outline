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
-- nil if there is nothing to draw. An outward outline grows the image only on
-- the sides the mask actually reaches, so the cel does not gain a transparent
-- margin in a direction nothing was drawn.
--
-- `opt.selection`, when set and non-empty, clips the result the way every
-- Aseprite filter clips: the shape is read whole, but only pixels inside the
-- selection are written.
function apply.forCel(cel, opt)
  return apply.forImage(cel.image, cel.position, cel.sprite, opt)
end

--- The union of two placed images, as one placed image.
--
-- Applying twice has to grow the second ring around the art *and* the first
-- ring. Growing it around the ring alone would also fill the ring's hollow
-- centre, because from the ring's point of view the art's own footprint is
-- empty space -- 32 pixels where 24 were wanted.
function apply.union(a, aPos, b, bPos)
  local x0, y0 = math.min(aPos.x, bPos.x), math.min(aPos.y, bPos.y)
  local x1 = math.max(aPos.x + a.width, bPos.x + b.width)
  local y1 = math.max(aPos.y + a.height, bPos.y + b.height)

  local out = Image(x1 - x0, y1 - y0, a.colorMode)
  out:clear(0)
  out:drawImage(a, Point(aPos.x - x0, aPos.y - y0))
  out:drawImage(b, Point(bPos.x - x0, bPos.y - y0))
  return out, Point(x0, y0)
end

function apply.forImage(image, position, sprite, opt)
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

  local out, W, H, offX, offY = outline.build(src, w, h, opt)

  local origin = Point(position.x + offX, position.y + offY)
  local selection = opt.selection
  if selection and selection.isEmpty then selection = nil end

  local dst = Image(W, H, image.colorMode)
  dst:clear(image.colorMode == ColorMode.INDEXED and sprite.transparentColor or 0)

  local write = writer(image, sprite, opt)
  local drawn = false
  for idx, c in pairs(out) do
    local i = idx - 1
    local x, y = i % W, floor(i / W)
    if not selection or selection:contains(origin.x + x, origin.y + y) then
      dst:drawPixel(x, y, write(floor(c / 65536) % 256, floor(c / 256) % 256, c % 256))
      drawn = true
    end
  end
  if not drawn then return nil end

  return dst, origin
end

return apply
