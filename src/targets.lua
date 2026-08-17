--- What the next pass outlines, and what the layer it writes is called.
--
-- The reason this is a module and not two lines in the dialog: `sprite:newLayer()`
-- steals the active layer. By the time the first preview has run, `app.cel`
-- points at the outline rather than at the art, so re-reading the live
-- selection on each pass finds a layer this extension made, drops it as
-- self-outlining, and reports an empty scope -- which is what OK and Apply
-- both did before. The user's intent is captured once, up front, and every
-- later pass resolves against that snapshot.

local targets = {}

targets.SUFFIX = " outline"

--- Generation 1 is "art outline"; Apply moves to "art outline 2" and so on, so
-- each ring keeps its own layer instead of overwriting the last.
function targets.nameFor(base, generation)
  if generation <= 1 then return base .. targets.SUFFIX end
  return base .. targets.SUFFIX .. " " .. generation
end

--- Does this layer look like something we produced?
function targets.isOurs(name)
  return name:find(targets.SUFFIX .. "$") ~= nil
      or name:find(targets.SUFFIX .. " %d+$") ~= nil
end

--- Freeze the selection before anything is drawn. Frames are stored as numbers
-- and layers as objects: layers survive the preview's undo, individual Cel
-- objects need not.
function targets.snapshot(activeLayer, activeFrame, rangeCels)
  local snap = { layer = activeLayer, frame = activeFrame or 1, range = {} }
  for _, cel in ipairs(rangeCels or {}) do
    snap.range[#snap.range + 1] = {
      layer = cel.layer, frame = cel.frameNumber, base = cel.layer.name,
    }
  end
  return snap
end

--- Drop what cannot be drawn on, and what we drew ourselves.
function targets.usable(list)
  local out = {}
  for _, t in ipairs(list) do
    local layer = t.layer
    if layer and layer.isEditable and layer.isImage and not targets.isOurs(layer.name) then
      out[#out + 1] = t
    end
  end
  return out
end

--- scope is "cel", "range" or "all".
function targets.forScope(sprite, snap, scope)
  local list = {}

  if scope == "all" then
    for _, cel in ipairs(sprite.cels) do
      list[#list + 1] = {
        layer = cel.layer, frame = cel.frameNumber, base = cel.layer.name,
      }
    end
  elseif scope == "range" and #snap.range > 0 then
    for _, t in ipairs(snap.range) do list[#list + 1] = t end
  elseif snap.layer then
    list[1] = { layer = snap.layer, frame = snap.frame, base = snap.layer.name }
  end

  return targets.usable(list)
end

--- After Apply, the ring just written becomes the shape the next ring grows
-- around. These are our own layers, so the self-outlining guard is deliberately
-- not applied -- that is the whole point.
function targets.advance(written)
  local out = {}
  for _, t in ipairs(written) do
    if t.layer and t.layer.isEditable then out[#out + 1] = t end
  end
  return out
end

return targets
