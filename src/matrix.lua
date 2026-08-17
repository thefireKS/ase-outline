--- The 3x3 side mask, the same model the built-in Outline uses.
--
-- Aseprite stores it in aseprite.ini as a 9-bit number, row-major, with the
-- centre at bit 4 -- `Matrix = 495` is 0b111101111, every neighbour but the
-- middle. The presets below are that same encoding, so a mask read out of
-- Aseprite's own config drops straight in here.
--
-- Reading convention: a lit cell is **where the outline goes**, not which
-- neighbour gets probed. Light the top cell and the contour appears above the
-- shape. Probing is the mirror of that -- to put a pixel above the art you ask
-- whether the pixel below you is opaque -- and mirroring happens in `offsets`
-- so the dialog can be taken at face value. For the four presets, which are
-- all symmetric, the two readings coincide.

local matrix = {}

matrix.PRESETS = {
  circle     = 170, -- 0b010101010
  square     = 495, -- 0b111101111
  horizontal = 40,  -- 0b000101000
  vertical   = 130, -- 0b010000010
}

matrix.CENTRE = 4
matrix.DEFAULT = matrix.PRESETS.circle

function matrix.has(mask, cell)
  return (mask >> cell) & 1 == 1
end

function matrix.set(mask, cell, on)
  if cell == matrix.CENTRE then return mask end
  if on then return mask | (1 << cell) end
  return mask & ~(1 << cell)
end

--- Which preset a mask corresponds to, or nil for a hand-made one.
function matrix.presetName(mask)
  for name, value in pairs(matrix.PRESETS) do
    if value == mask then return name end
  end
  return nil
end

--- Turn the mask into probe offsets with vote weights.
--
-- An orthogonal neighbour says more about which shape an outline pixel belongs
-- to than a diagonal one, so it votes twice: on a corner where a white sleeve
-- meets dark armour, the contour keeps the colour of the side it runs along
-- instead of averaging into mud.
function matrix.offsets(mask)
  local list = {}
  for cell = 0, 8 do
    if cell ~= matrix.CENTRE and matrix.has(mask, cell) then
      local dx, dy = cell % 3 - 1, cell // 3 - 1
      local weight = (dx == 0 or dy == 0) and 2 or 1
      list[#list + 1] = { -dx, -dy, weight }
    end
  end
  return list
end

return matrix
