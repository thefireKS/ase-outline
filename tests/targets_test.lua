-- What the next pass outlines. The regression this file exists for: creating
-- the outline layer moves Aseprite's active layer onto it, so anything that
-- re-reads the live selection later finds our own layer, drops it as
-- self-outlining, and reports an empty scope. OK and Apply both did that.
-- Run from the project root: aseprite -b --script tests/targets_test.lua

local ROOT = app.fs.currentPath
package.path = app.fs.joinPath(ROOT, "src", "?.lua") .. ";" .. package.path

local targets = require("targets")

print("=== naming ===")
assert(targets.nameFor("art", 1) == "art outline", targets.nameFor("art", 1))
assert(targets.nameFor("art", 2) == "art outline 2", targets.nameFor("art", 2))
assert(targets.nameFor("art", 3) == "art outline 3")
assert(targets.isOurs("art outline"))
assert(targets.isOurs("art outline 2"))
assert(not targets.isOurs("art"))
assert(not targets.isOurs("outlined armour"))
print("  art -> art outline -> art outline 2, all recognised as ours  ok")

local sprite = Sprite(8, 8, ColorMode.RGB)
sprite.layers[1].name = "art"
local art = sprite.layers[1]
local img = Image(4, 4, ColorMode.RGB)
for y = 0, 3 do for x = 0, 3 do
  img:drawPixel(x, y, app.pixelColor.rgba(200, 200, 200, 255))
end end
for _, c in ipairs(sprite.cels) do sprite:deleteCel(c) end
sprite:newCel(art, 1, img, Point(2, 2))
app.sprite = sprite
app.layer = art

print("=== the snapshot survives newLayer stealing the active layer ===")
local snap = targets.snapshot(app.layer, 1, app.range.cels)
assert(snap.layer == art, "snapshot did not capture the art layer")

local stolen = sprite:newLayer()
stolen.name = targets.nameFor("art", 1)
sprite:newCel(stolen, 1, Image(2, 2, ColorMode.RGB), Point(0, 0))
print(("  app.layer is now %q"):format(app.layer.name))
assert(app.layer == stolen, "precondition failed: newLayer no longer steals focus")

local list = targets.forScope(sprite, snap, "cel")
assert(#list == 1, ("scope resolved to %d targets, wanted 1"):format(#list))
assert(list[1].layer == art, "resolved to " .. list[1].layer.name .. ", wanted art")
assert(list[1].base == "art")
print("  scope still resolves to the art  ok")

print("=== All cels skips what we made ===")
local all = targets.forScope(sprite, snap, "all")
for _, t in ipairs(all) do
  assert(not targets.isOurs(t.layer.name), "All cels picked up " .. t.layer.name)
end
assert(#all == 1, ("All cels gave %d targets, wanted 1"):format(#all))
print("  ok")

print("=== locked and non-image layers are dropped ===")
art.isEditable = false
assert(#targets.forScope(sprite, snap, "cel") == 0, "a locked layer must be dropped")
art.isEditable = true
local group = sprite:newGroup()
group.name = "folder"
assert(#targets.usable{ { layer = group, frame = 1, base = "folder" } } == 0,
  "a group is not something to outline")
print("  ok")

print("=== Apply moves onto the ring it just wrote ===")
local advanced = targets.advance{ { layer = stolen, frame = 1, base = "art" } }
assert(#advanced == 1, "advance dropped our own layer")
assert(advanced[1].layer == stolen)
assert(advanced[1].base == "art", "the base name must stay the original")
-- The name for the next generation is built from that base, not from the ring.
assert(targets.nameFor(advanced[1].base, 2) == "art outline 2")
print("  art outline -> next ring lands on art outline 2  ok")

print("=== the timeline range is captured by value ===")
local snap2 = targets.snapshot(art, 1, { { layer = art, frameNumber = 1 } })
assert(#snap2.range == 1 and snap2.range[1].layer == art)
local ranged = targets.forScope(sprite, snap2, "range")
assert(#ranged == 1 and ranged[1].layer == art)
print("  ok")

print("ok")
