--- Aseprite extension entry point: adds "Colored Outline" to Edit > FX.
--
-- The outline takes its colour from the art it touches instead of from a
-- swatch, so a white sleeve and dark armour on the same silhouette come out
-- with contours that belong to each of them.
--
-- The dialog follows the built-in Outline: a 3x3 side mask with the same four
-- presets, Outside/Inside placement, a live preview, and OK/Apply/Cancel.

local apply, matrix, layers, targets, Preview

local function loadModules(plugin)
  if apply then return end
  package.path = table.concat({
    app.fs.joinPath(plugin.path, "src", "?.lua"),
    package.path,
  }, ";")
  matrix = require("matrix")
  layers = require("layers")
  targets = require("targets")
  apply = require("apply")
  Preview = require("preview")
end

local SCOPE_CEL = "Active cel"
local SCOPE_RANGE = "Selected cels"
local SCOPE_ALL = "All cels"

local SCOPE_KEY = {
  [SCOPE_CEL] = "cel",
  [SCOPE_RANGE] = "range",
  [SCOPE_ALL] = "all",
}

local PLACE_OUTSIDE, PLACE_INSIDE = "Outside", "Inside"

-- A cool violet-blue: the hue most pixel art shadows drift toward, and the one
-- that turns the neutral greys in armour into something that still reads as a
-- colour rather than as soot.
local DEFAULTS = {
  tintR = 60, tintG = 70, tintB = 160,
  hueShift = 45,
  darken = 38,
  saturate = 18,
  thickness = 1,
  mask = 170, -- circle
  place = PLACE_OUTSIDE,
  snap = false,
  scope = SCOPE_CEL,
  preview = true,
}

--- How long to sit still before recomputing. Long enough that dragging a
-- slider does not queue a render per pixel of travel, short enough to feel live.
local SETTLE = 0.12

--- Side of one mask cell, in dialog pixels.
local CELL = 15

local function pref(plugin, key)
  local v = plugin.preferences[key]
  if v == nil then return DEFAULTS[key] end
  return v
end

--- Theme lookups, guarded on alpha rather than on error.
--
-- An id the theme does not define comes back as a fully transparent colour, not
-- as a failure, so a pcall alone never reaches the fallback and the widget
-- paints in nothing at all. Every id used below is one that exists in
-- data/extensions/aseprite-theme/theme.xml; the alpha check is what catches the
-- day one of them is renamed.
local function themeColor(name, fallback)
  local ok, c = pcall(function() return app.theme.color[name] end)
  if ok and c and c.alpha > 0 then return c end
  return fallback
end

local function optionsFrom(data, sprite, mask)
  local tint = data.tint
  return {
    hue = tint.hsvHue,
    hueShift = data.hueShift,
    darken = data.darken / 100,
    saturate = data.saturate / 100,
    thickness = data.thickness,
    offsets = matrix.offsets(mask),
    place = (data.place == PLACE_INSIDE) and "inside" or "outside",
    snap = data.snap,
    selection = sprite.selection,
    alpha = 255,
  }
end

--- Draw every target. Returns how many cels were drawn and, for each, the
-- layer it landed on -- Apply needs those to grow the next ring around them.
--
-- The active layer is put back afterwards: `sprite:newLayer()` moves it, and
-- leaving it moved both hijacks the user's selection and would poison the next
-- pass's idea of what to outline.
local function render(sprite, data, list, mask, generation)
  local opt = optionsFrom(data, sprite, mask)
  local above = data.place == PLACE_INSIDE
  local active = app.layer
  local drawn, written = 0, {}

  for _, t in ipairs(list) do
    -- After an Apply the target carries the accumulated silhouette -- art plus
    -- every ring so far -- so the next ring grows around all of it. On the
    -- first pass there is nothing accumulated yet and the cel is the shape.
    local shape, at = t.image, t.position
    if not shape then
      local cel = t.layer:cel(t.frame)
      if cel then shape, at = cel.image, cel.position end
    end

    if shape then
      local ring, ringAt = apply.forImage(shape, at, sprite, opt)
      if ring then
        local layer = layers.outlineFor(
          sprite, t.layer, targets.nameFor(t.base, generation), above)
        local existing = layer:cel(t.frame)
        if existing then sprite:deleteCel(existing) end
        sprite:newCel(layer, t.frame, ring, ringAt)
        drawn = drawn + 1

        local grown, grownAt = apply.union(shape, at, ring, ringAt)
        written[#written + 1] = {
          layer = layer, frame = t.frame, base = t.base,
          image = grown, position = grownAt,
        }
      end
    end
  end

  if active then app.layer = active end
  return drawn, written
end

local function savePrefs(plugin, data, mask)
  local prefs = plugin.preferences
  prefs.tintR, prefs.tintG, prefs.tintB = data.tint.red, data.tint.green, data.tint.blue
  prefs.mask = mask
  for _, key in ipairs{ "hueShift", "darken", "saturate", "thickness",
                        "place", "snap", "scope", "preview" } do
    prefs[key] = data[key]
  end
end

local function showDialog(plugin)
  local sprite = app.sprite
  if not sprite then
    return app.alert("Open a sprite first.")
  end

  -- Frozen now, before a single layer is created. See src/targets.lua for why
  -- reading the live selection later does not work.
  local snap = targets.snapshot(
    app.layer,
    app.frame and app.frame.frameNumber or 1,
    app.range.cels)

  -- Declared up front so the dialog's own onclose can reach them: the closure
  -- captures the locals, not their values at construction time.
  local dlg, timer
  local settled = false
  local mask = pref(plugin, "mask")
  local generation = 1
  local committed = nil -- set by Apply: the ring the next pass grows around
  local lastDrawn, lastConsidered, lastWritten = 0, 0, {}

  local function currentTargets(data)
    if committed then return committed end
    return targets.forScope(sprite, snap, SCOPE_KEY[data.scope] or "cel")
  end

  local preview = Preview.new(function()
    local data = dlg.data
    local list = currentTargets(data)
    lastConsidered = #list
    lastDrawn, lastWritten = render(sprite, data, list, mask, generation)
    return lastDrawn > 0
  end)

  --- Every control funnels here. The timer collapses a burst of changes into
  -- one render, which is what keeps a dragged slider from queueing dozens.
  local function schedule()
    if not settled then return end
    if not dlg.data.preview then
      preview:rollback()
      return
    end
    timer:stop()
    timer:start()
  end

  timer = Timer{
    interval = SETTLE,
    ontick = function()
      timer:stop()
      preview:update()
    end,
  }

  dlg = Dialog{
    title = "Colored Outline",
    onclose = function()
      if timer then timer:stop() end
      preview:rollback()
    end,
  }

  local tint = Color{
    r = pref(plugin, "tintR"),
    g = pref(plugin, "tintG"),
    b = pref(plugin, "tintB"),
  }

  dlg:color{ id = "tint", label = "Shadow tint:", color = tint, onchange = schedule }
     :slider{ id = "hueShift", label = "Hue shift:", min = 0, max = 180,
              value = pref(plugin, "hueShift"), onchange = schedule }
     :slider{ id = "darken", label = "Darken:", min = 0, max = 90,
              value = pref(plugin, "darken"), onchange = schedule }
     :slider{ id = "saturate", label = "Saturate:", min = 0, max = 60,
              value = pref(plugin, "saturate"), onchange = schedule }
     :separator{ text = "Shape" }
     :combobox{ id = "place", label = "Place:", option = pref(plugin, "place"),
                options = { PLACE_OUTSIDE, PLACE_INSIDE }, onchange = schedule }
     :slider{ id = "thickness", label = "Thickness:", min = 1, max = 4,
              value = pref(plugin, "thickness"), onchange = schedule }

  -- The 3x3 side mask, drawn rather than assembled out of checkboxes: nine
  -- checkboxes will not hold a grid, and this is the shape the built-in dialog
  -- uses anyway. A lit cell is where the contour goes, so lighting the bottom
  -- row outlines the underside; the centre stands for the art itself and is
  -- not clickable.
  -- A dialog canvas stretches to the width of the dialog and cannot be told
  -- not to, so the grid is centred inside whatever width it is handed and the
  -- surround is painted in the dialog's own face colour. The widget then reads
  -- as a grid sitting on the dialog rather than as a wide coloured slab.
  local grid = { cell = CELL, x = 0, y = 0 }
  local hover = nil

  local function cellAt(x, y)
    local col = (x - grid.x) // grid.cell
    local row = (y - grid.y) // grid.cell
    if col < 0 or col > 2 or row < 0 or row > 2 then return nil end
    return row * 3 + col
  end

  dlg:canvas{
    id = "sides",
    label = "Sides:",
    width = CELL * 3,
    height = CELL * 3,
    onpaint = function(ev)
      local gc = ev.context
      local w = gc.width or CELL * 3
      local h = gc.height or CELL * 3

      local cell = math.max(6, math.min(w, h) // 3)
      grid.cell = cell
      grid.x = (w - cell * 3) // 2
      grid.y = (h - cell * 3) // 2

      local face = themeColor("face", Color{ r = 202, g = 196, b = 186 })
      local off = themeColor("editor_face", Color{ r = 108, g = 96, b = 108 })
      local on = themeColor("selected", Color{ r = 60, g = 100, b = 180 })
      local art = themeColor("text", Color{ r = 20, g = 20, b = 24 })

      gc.color = face
      gc:fillRect(Rectangle(0, 0, w, h))

      for c = 0, 8 do
        local col, row = c % 3, c // 3
        local r = Rectangle(grid.x + col * cell + 1, grid.y + row * cell + 1,
                            cell - 2, cell - 2)
        gc.color = (c == matrix.CENTRE) and art
                or (matrix.has(mask, c) and on or off)
        gc:fillRect(r)

        -- The cell under the pointer gets an outline, so it is obvious what a
        -- click is about to toggle.
        if c == hover and c ~= matrix.CENTRE then
          gc.color = art
          gc:strokeRect(r)
        end
      end
    end,
    onmousemove = function(ev)
      local c = cellAt(ev.x, ev.y)
      if c == matrix.CENTRE then c = nil end
      if c ~= hover then
        hover = c
        dlg:repaint()
      end
    end,
    onmousedown = function(ev)
      local c = cellAt(ev.x, ev.y)
      if not c or c == matrix.CENTRE then return end
      mask = matrix.set(mask, c, not matrix.has(mask, c))
      dlg:repaint()
      schedule()
    end,
  }

  local function setMask(value)
    mask = value
    dlg:repaint()
    schedule()
  end

  dlg:button{ text = "Circle", onclick = function() setMask(matrix.PRESETS.circle) end }
     :button{ text = "Square", onclick = function() setMask(matrix.PRESETS.square) end }
     :newrow()
     :button{ text = "Horiz.", onclick = function() setMask(matrix.PRESETS.horizontal) end }
     :button{ text = "Vert.", onclick = function() setMask(matrix.PRESETS.vertical) end }
     :separator()
     :check{ id = "snap", text = "Snap to palette",
             selected = pref(plugin, "snap"), onclick = schedule }
     :combobox{ id = "scope", label = "Apply to:", option = pref(plugin, "scope"),
                options = { SCOPE_CEL, SCOPE_RANGE, SCOPE_ALL }, onchange = schedule }
     :separator()
     :check{ id = "preview", text = "Preview", selected = pref(plugin, "preview"),
             onclick = schedule }

  --- Turn what is on screen into pixels the user owns. With preview off there
  -- is nothing on screen yet, so draw it now.
  local function commit()
    if preview.pending then
      preview:commit()
    else
      local data = dlg.data
      local list = currentTargets(data)
      lastConsidered = #list
      app.transaction("Colored Outline", function()
        lastDrawn, lastWritten = render(sprite, data, list, mask, generation)
      end)
      app.refresh()
    end
    savePrefs(plugin, dlg.data, mask)
    return lastDrawn
  end

  local function report()
    if lastConsidered == 0 then
      app.alert("Nothing to outline: the layer this dialog opened on is not an "
              .. "editable image layer.")
    elseif lastDrawn == 0 then
      app.alert("Nothing was drawn: the cels in scope are empty, or the "
              .. "selection does not overlap where the outline would go.")
    end
  end

  dlg:button{
    text = "OK",
    focus = true,
    onclick = function()
      commit()
      report()
      dlg:close()
    end,
  }
  dlg:button{
    text = "Apply",
    onclick = function()
      local drawn = commit()
      report()
      if drawn > 0 then
        -- The ring just kept becomes the shape the next one grows around, on
        -- its own layer, so Apply twice gives two rings rather than one
        -- redrawn twice.
        committed = targets.advance(lastWritten)
        generation = generation + 1
        schedule()
      end
    end,
  }
  dlg:button{
    text = "Cancel",
    onclick = function() dlg:close() end,
  }

  dlg:show{ wait = false }

  -- Only now may callbacks touch the sprite: `schedule` runs during layout as
  -- widgets are added, and rendering against a half-built dialog would read
  -- fields that do not exist yet.
  settled = true
  schedule()
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
