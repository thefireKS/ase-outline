--- Finding and parking the layer the outline is drawn on.

local layers = {}

function layers.find(parent, name)
  for _, layer in ipairs(parent.layers) do
    if layer.name == name and layer.isImage then return layer end
  end
  return nil
end

--- Park `layer` directly above or below `source`.
--
-- Aseprite renumbers the stack as a layer is pulled out and reinserted, so a
-- single assignment can overshoot by one when the layer has to cross the
-- source. Aim, look, aim again -- it settles in two passes, and the loop is
-- bounded so a surprise cannot spin here.
function layers.stackNextTo(layer, source, above)
  local wanted = above and 1 or -1
  for _ = 1, 4 do
    if layer.stackIndex - source.stackIndex == wanted then return true end
    layer.stackIndex = source.stackIndex + (above and 1 or 0)
  end
  return layer.stackIndex - source.stackIndex == wanted
end

--- An outward outline renders behind the art; an inward one replaces the art's
-- own rim and so has to sit in front of it. Either way the source pixels are
-- never touched, and re-running reuses the layer instead of stacking a new one
-- per attempt.
function layers.outlineFor(sprite, source, name, above)
  local layer = layers.find(source.parent, name)
  if not layer then
    layer = sprite:newLayer()
    layer.name = name
    layer.parent = source.parent
  end
  layers.stackNextTo(layer, source, above)
  return layer
end

return layers
