-- Every theme colour id the dialog asks for must actually exist.
--
-- The bug this file exists for: `app.theme.color.button_normal_face` is not a
-- real id. Aseprite answers an unknown id with a fully transparent colour
-- rather than an error, so the guard around the lookup never fired, the
-- fallback never ran, and eight of the nine mask cells were painted in nothing
-- at all -- a widget that looked empty and gave no feedback.
--
-- Checking against the live theme is not an option here: under `-b` no theme is
-- loaded and every id, valid or not, comes back transparent. So the ids are
-- read out of main.lua and checked against the theme's own XML.
-- Run from the project root: aseprite -b --script tests/theme_test.lua

local ROOT = app.fs.currentPath

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

--- data/ sits beside the binary on Linux and Windows, and inside the bundle on
-- macOS.
local function themeXmlPath()
  local exe = app.fs.appPath
  local dir = app.fs.filePath(exe)
  local candidates = {
    app.fs.joinPath(app.fs.filePath(dir), "Resources", "data"),
    app.fs.joinPath(dir, "data"),
  }
  for _, data in ipairs(candidates) do
    local path = app.fs.joinPath(data, "extensions", "aseprite-theme", "theme.xml")
    if app.fs.isFile(path) then return path end
  end
  return nil
end

local source = assert(read(app.fs.joinPath(ROOT, "main.lua")), "cannot read main.lua")

local ids, seen = {}, {}
for id in source:gmatch('themeColor%("([%w_]+)"') do
  if not seen[id] then
    seen[id] = true
    ids[#ids + 1] = id
  end
end
assert(#ids > 0, "found no themeColor() calls -- has the helper been renamed?")

local path = themeXmlPath()
if not path then
  print("theme.xml not found next to " .. tostring(app.fs.appPath) .. " -- skipping")
  print("ok")
  return
end

local xml = assert(read(path), "cannot read " .. path)
local colours = xml:match("<colors>(.-)</colors>")
assert(colours, "no <colors> block in " .. path)

local known = {}
for id in colours:gmatch('id="([%w_]+)"') do known[id] = true end
assert(next(known), "parsed no colour ids out of " .. path)

print(("checking %d ids against %s"):format(#ids, path))
local bad = {}
for _, id in ipairs(ids) do
  print(("  %-24s %s"):format(id, known[id] and "ok" or "MISSING"))
  if not known[id] then bad[#bad + 1] = id end
end

assert(#bad == 0, "the theme defines no colour called: " .. table.concat(bad, ", "))

-- Guard the guard: the names that caused the original bug must still be absent,
-- so this test cannot quietly stop meaning anything.
for _, gone in ipairs{ "button_normal_face", "button_selected_face" } do
  assert(not known[gone],
    gone .. " exists now -- the regression this test protects has changed shape")
end
print("  button_normal_face / button_selected_face still do not exist  ok")

print("ok")
