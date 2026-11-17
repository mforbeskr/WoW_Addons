-- Generator: builds random outfits, weighted by what you've liked and disliked before.
-- Every item has a weight (default 1). Liking an outfit multiplies the weight of each of its
-- items by LIKE_FACTOR, disliking by DISLIKE_FACTOR, so liked items show up more often.

local _, ns = ...

local LIKE_FACTOR, DISLIKE_FACTOR = 1.5, 0.7
local MIN_WEIGHT, MAX_WEIGHT = 0.1, 20

local function Weight(id)
  return ns.db.weights[id] or 1
end

-- Picks one id from the list; an item with weight 2 is twice as likely as one with weight 1
local function PickWeighted(list)
  local total = 0
  for _, id in ipairs(list) do total = total + Weight(id) end
  local roll = math.random() * total
  for _, id in ipairs(list) do
    roll = roll - Weight(id)
    if roll <= 0 then return id end
  end
  return list[#list]
end

-- Returns outfit[slotIndex] = itemID, or 0 for an empty slot.
-- Locked slots keep their item from `current`.
function ns.Generate(pool, current, locked)
  local outfit = {}
  for i, slot in ipairs(ns.SLOTS) do
    if locked[i] and current then
      outfit[i] = current[i]
    elseif slot.skip or #pool[i] == 0 or (slot.optional and math.random() < slot.optional) then
      outfit[i] = 0
    else
      outfit[i] = PickWeighted(pool[i])
    end
  end

  -- A two-hander leaves no room for an off-hand
  local main = outfit[ns.MAIN_HAND]
  if main ~= 0 and select(9, GetItemInfo(main)) == "INVTYPE_2HWEAPON" and not locked[ns.OFF_HAND] then
    outfit[ns.OFF_HAND] = 0
  end
  return outfit
end

-- Learn from a rating. Locked items are skipped on a dislike: you picked them on purpose.
function ns.Rate(outfit, liked, locked)
  local factor = liked and LIKE_FACTOR or DISLIKE_FACTOR
  for i, id in ipairs(outfit) do
    if id ~= 0 and (liked or not locked[i]) then
      ns.db.weights[id] = math.max(MIN_WEIGHT, math.min(MAX_WEIGHT, Weight(id) * factor))
    end
  end
end

-- Saves a liked outfit to our favorites, and to DressMe's saved looks if DressMe is installed.
-- Returns the outfit's name and whether it went into DressMe.
function ns.SaveFavorite(outfit)
  local items = {}
  for i = 1, #ns.SLOTS do items[i] = outfit[i] or 0 end
  local name = "Studio " .. UnitName("player") .. " " .. (#ns.db.favorites + 1)
  table.insert(ns.db.favorites, { name = name, items = items })

  -- DressMe reads its list at login, so the new look shows there after a /reload
  local inDressMe = false
  if type(DressMeSavedLooks) == "table" then
    table.insert(DressMeSavedLooks, { name = name, items = items })
    inDressMe = true
  end
  return name, inDressMe
end
