-- Path of Building
--
-- Module: Build Compare
-- State capture and diff logic for build comparison.
--
local t_insert = table.insert
local t_sort = table.sort
local pairs = pairs
local tostring = tostring

local buildCompare = { }

-- Capture a snapshot of the build's input state (tree, items, config)
function buildCompare.captureState(build)
	local state = { }

	-- Allocated tree nodes: { [nodeId] = nodeName }
	state.allocNodeIds = { }
	if build.spec and build.spec.allocNodes then
		for nodeId, node in pairs(build.spec.allocNodes) do
			state.allocNodeIds[nodeId] = node.dn or node.name or tostring(nodeId)
		end
	end

	-- Equipped items per slot: { [slotName] = itemName }
	state.slotItems = { }
	if build.itemsTab and build.itemsTab.slots then
		for slotName, slot in pairs(build.itemsTab.slots) do
			local itemId = slot.selItemId
			if itemId and itemId ~= 0 and build.itemsTab.items[itemId] then
				state.slotItems[slotName] = build.itemsTab.items[itemId].name or "Unknown"
			end
		end
	end

	-- Config options: shallow copy of configTab.input
	state.config = { }
	if build.configTab and build.configTab.input then
		for k, v in pairs(build.configTab.input) do
			state.config[k] = v
		end
	end

	return state
end

-- Diff two captured states, returning lists of changes
function buildCompare.diffStates(stateA, stateB)
	local diffs = {
		addedNodes = { },
		removedNodes = { },
		changedSlots = { },
		changedConfig = { },
	}

	-- Tree node diffs (nodes in B but not A = added, nodes in A but not B = removed)
	if stateA.allocNodeIds and stateB.allocNodeIds then
		for nodeId, name in pairs(stateB.allocNodeIds) do
			if not stateA.allocNodeIds[nodeId] then
				t_insert(diffs.addedNodes, name)
			end
		end
		for nodeId, name in pairs(stateA.allocNodeIds) do
			if not stateB.allocNodeIds[nodeId] then
				t_insert(diffs.removedNodes, name)
			end
		end
		t_sort(diffs.addedNodes)
		t_sort(diffs.removedNodes)
	end

	-- Item slot diffs
	if stateA.slotItems and stateB.slotItems then
		local allSlots = { }
		for slotName in pairs(stateA.slotItems) do allSlots[slotName] = true end
		for slotName in pairs(stateB.slotItems) do allSlots[slotName] = true end
		for slotName in pairs(allSlots) do
			local fromItem = stateA.slotItems[slotName]
			local toItem = stateB.slotItems[slotName]
			if fromItem ~= toItem then
				t_insert(diffs.changedSlots, { slot = slotName, from = fromItem, to = toItem })
			end
		end
		t_sort(diffs.changedSlots, function(a, b) return a.slot < b.slot end)
	end

	-- Config diffs
	if stateA.config and stateB.config then
		local allKeys = { }
		for k in pairs(stateA.config) do allKeys[k] = true end
		for k in pairs(stateB.config) do allKeys[k] = true end
		for k in pairs(allKeys) do
			local fromVal = stateA.config[k]
			local toVal = stateB.config[k]
			if fromVal ~= toVal then
				t_insert(diffs.changedConfig, { key = k, from = fromVal, to = toVal })
			end
		end
		t_sort(diffs.changedConfig, function(a, b) return a.key < b.key end)
	end

	return diffs
end

return buildCompare
