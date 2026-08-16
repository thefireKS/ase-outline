--- Aseprite extension entry point: adds "Colored Outline" to Edit > FX.
--
-- The outline takes its colour from the art it touches instead of from a
-- swatch, so a white sleeve and dark armour on the same silhouette come out
-- with contours that belong to each of them.

local apply, outline

local function loadModules(plugin)
  if apply then return end
  package.path = table.concat({
    app.fs.joinPath(plugin.path, "src", "?.lua"),
    package.path,
  }, ";")
  outline = require("outline")
  apply = require("apply")
end

local SCOPE_CEL = "Active cel"
local SCOPE_LAYER = "This layer, all frames"
local SCOPE_RANGE = "Timeline selection"

-- A cool violet-blue: the hue most pixel art shadows drift toward, and the
-- one that turns the neutral greys in armour into something that still reads
-- as a colour rather than as soot.
local DEFAULTS = {
  tintR = 60, tintG = 70, tintB = 160,
  hueShift = 45,
  darken = 38,
  saturate = 18,
  thickness = 1,
  matrix = "circle",
  snap = false,
  scope = SCOPE_CEL,
}

local function pref(plugin, key)
  local v = plugin.preferences[key]
  if v == nil then return DEFAULTS[key] end
  return v
end

--- Which cels to work on. Anything empty or on a locked layer is dropped
-- here rather than in the middle of the transaction.
local function celsFor(sprite, scope)
  local cels = {}

  if scope == SCOPE_RANGE and #app.range.cels > 0 then
    for _, cel in ipairs(app.range.cels) do cels[#cels + 1] = cel end
  elseif scope == SCOPE_LAYER and app.layer then
    for _, cel in ipairs(app.layer.cels) do cels[#cels + 1] = cel end
  elseif app.cel then
    cels[1] = app.cel
  end

  local usable = {}
  for _, cel in ipairs(cels) do
    if cel.layer.isEditable and cel.layer.isImage then usable[#usable + 1] = cel end
  end
  return usable
end

local OUTLINE_SUFFIX = " outline"

--- The outline goes on its own layer directly under the art, so the original
-- pixels are never touched and the result can be tweaked or thrown away on
-- its own. Re-running reuses that layer instead of stacking a new one per
-- attempt -- otherwise tuning the sliders leaves a pile of layers behind.
local function outlineLayerFor(sprite, source)
  local name = source.name .. OUTLINE_SUFFIX
  local parent = source.parent
  local below = source.stackIndex - 1

  if below >= 1 then
    local existing = parent.layers[below]
    if existing and existing.name == name and existing.isImage then
      return existing
    end
  end

  local layer = sprite:newLayer()
  layer.name = name
  layer.parent = parent
  layer.stackIndex = source.stackIndex
  return layer
end

local function optionsFrom(data)
  local tint = data.tint
  return {
    hue = tint.hsvHue,
    hueShift = data.hueShift,
    darken = data.darken / 100,
    saturate = data.saturate / 100,
    thickness = data.thickness,
    matrix = outline.MATRIX[data.matrix] or outline.MATRIX.circle,
    snap = data.snap,
    alpha = 255,
  }
end

local function run(sprite, data)
  local cels = celsFor(sprite, data.scope)
  if #cels == 0 then
    return 0, "Nothing to outline: pick a cel with art on an editable layer."
  end

  local opt = optionsFrom(data)
  local done = 0

  app.transaction("Colored Outline", function()
    for _, cel in ipairs(cels) do
      local image, position = apply.forCel(cel, opt)
      if image then
        local layer = outlineLayerFor(sprite, cel.layer)
        local existing = layer:cel(cel.frameNumber)
        if existing then sprite:deleteCel(existing) end
        sprite:newCel(layer, cel.frameNumber, image, position)
        done = done + 1
      end
    end
  end)

  return done
end

local function showDialog(plugin)
  local sprite = app.sprite
  if not sprite then
    return app.alert("Open a sprite first.")
  end

  local dlg = Dialog("Colored Outline")

  local tint = Color{
    r = pref(plugin, "tintR"),
    g = pref(plugin, "tintG"),
    b = pref(plugin, "tintB"),
  }

  dlg:color{ id = "tint", label = "Shadow tint:", color = tint }
     :slider{ id = "hueShift", label = "Hue shift:", min = 0, max = 180, value = pref(plugin, "hueShift") }
     :slider{ id = "darken", label = "Darken:", min = 0, max = 90, value = pref(plugin, "darken") }
     :slider{ id = "saturate", label = "Saturate:", min = 0, max = 60, value = pref(plugin, "saturate") }
     :separator()
     :slider{ id = "thickness", label = "Thickness:", min = 1, max = 4, value = pref(plugin, "thickness") }
     :combobox{ id = "matrix", label = "Corners:", option = pref(plugin, "matrix"),
                options = { "circle", "square" } }
     :check{ id = "snap", label = "", text = "Snap to palette", selected = pref(plugin, "snap") }
     :separator()
     :combobox{ id = "scope", label = "Apply to:", option = pref(plugin, "scope"),
                options = { SCOPE_CEL, SCOPE_LAYER, SCOPE_RANGE } }
     :separator()
     :button{ id = "ok", text = "Outline", focus = true }
     :button{ text = "Cancel" }

  dlg:show()
  local data = dlg.data
  if not data.ok then return end

  local prefs = plugin.preferences
  prefs.tintR, prefs.tintG, prefs.tintB = data.tint.red, data.tint.green, data.tint.blue
  for _, key in ipairs{ "hueShift", "darken", "saturate", "thickness", "matrix", "snap", "scope" } do
    prefs[key] = data[key]
  end

  local done, problem = run(sprite, data)
  if problem then
    app.alert(problem)
  elseif done == 0 then
    app.alert("Every selected cel was empty, so there was nothing to outline.")
  else
    app.refresh()
  end
end

function init(plugin)
  plugin:newCommand{
    id = "ColoredOutline",
    title = "Colored Outline...",
    group = "edit_fx",
    onclick = function()
      loadModules(plugin)
      showDialog(plugin)
    end,
  }
end

function exit(plugin) end
