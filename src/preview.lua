--- Live preview on the real canvas.
--
-- One transaction per update, rolled back with app.undo() before the next one,
-- so a session of dragging sliders leaves the undo stack exactly where it
-- started. This is the same shape as GuideLayer in animation-suite, with one
-- addition: the rollback only fires if the previous pass actually drew
-- something. A transaction that changed nothing may push no undo entry at all,
-- and undoing on that assumption would eat whatever the user did last.

local Preview = {}
Preview.__index = Preview

--- `render` runs inside the transaction and returns true if it touched the
-- sprite.
function Preview.new(render)
  return setmetatable({ render = render, pending = false }, Preview)
end

--- Undo restores the frame that was active when the transaction was made, so
-- put the user's frame back afterwards.
function Preview:rollback()
  if not self.pending then return end
  local frame = app.frame
  app.undo()
  self.pending = false
  if frame then app.frame = frame end
  app.refresh()
end

function Preview:update()
  self:rollback()
  local drew = false
  app.transaction("Colored Outline preview", function()
    drew = self.render() and true or false
  end)
  self.pending = drew
  app.refresh()
  return drew
end

--- Keep what is on screen: the last transaction stops being provisional and
-- becomes an ordinary undo step the user owns.
function Preview:commit()
  self.pending = false
end

return Preview
