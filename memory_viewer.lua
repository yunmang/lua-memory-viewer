--[[
File : memory_viewer.lua
Author : yunmang
Email : yunmang@gmail.com
--]]

local getmetatable = getmetatable
local rawget = rawget
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local type = type
local debug = debug
local collectgarbage = collectgarbage

local huge = math.huge

-- Object map which will not be visited
IgnoreMap = {
	--[[
	[object] = true,
	--]]
}

--------------------------------------------------------------------------------
-- Debug
local function getFunctionPath(func)
	local info = debug.getinfo(func, "Sl")
	return string.format("%s+%d", info.source, info.linedefined)
end

local function dumpFunction(func, value)
	print(getFunctionPath(func), value)
end

local function dumpTable(t, value, count)
	print("dump:", t, " value:", value)
	count = count or 10
	for k, v in pairs(t) do
		print("\t", k, v)
		count = count - 1
		if count <= 0 then
			break
		end
	end
end

local function dumpPath(object, node)
	local str = defaultNodeToString(node)
	local parentNode = node.ParentNode
	while parentNode do
		str = string.format("%s.%s", defaultNodeToString(parentNode), str)
		parentNode = parentNode.ParentNode
	end
	print("type:", type(object), str)
end

--------------------------------------------------------------------------------
-- Utils
function GetCurrentMemoryUsage()
	return collectgarbage("count") / 1024 -- KB to MB
end

function BytesToMB(size)
	return size / 1024 / 1024
end

function BytesToKB(size)
	return size / 1024
end

--------------------------------------------------------------------------------
-- Defaults
local function defaultCheckRoot(object)
	return false
end

local function defaultNodeToString(node)
	return node.Info
end

--------------------------------------------------------------------------------
-- Traverse
local traverseObject -- function
local traverseHandlerMap = {
	["table"] = function (object, visitFunction, parent, info)
		local metatable = getmetatable(object)
		local isWeakKey, isWeakValue
		if metatable then
			local mode = rawget(metatable, "__mode")
			if mode then
				if "v" == mode then
					isWeakValue = true
				elseif "k" == mode then
					isWeakKey = true
				elseif "kv" == mode then
					isWeakKey = true
					isWeakValue = true
				end
			end
			traverseObject(metatable, visitFunction, object, "m:")
		end
		for k, v in pairs(object) do
			if not isWeakKey then
				traverseObject(k, visitFunction, object, "v:" .. tostring(v))
			end
			if not isWeakValue then
				traverseObject(v, visitFunction, object, "k:" .. tostring(k))
			end
		end
	end,
	["function"] = function (object, visitFunction, parent, info)
		local index = 1
		while true do
			local name, upvalue = debug.getupvalue(object, index)
			if name == nil then
				break
			end
			traverseObject(upvalue, visitFunction, object, "u:" .. name)
			index = index + 1
		end
	end,
}

function traverseObject(object, visitFunction, parent, info)
	if object == nil or IgnoreMap[object] then
		return
	end

	local interrupt = visitFunction(object, parent, info)
	if interrupt then
		return
	end

	local objectType = type(object)
	local handler = traverseHandlerMap[objectType]
	if not handler then
		return
	end

	handler(object, visitFunction, parent, info)
end

--------------------------------------------------------------------------------
-- Snapshot
local function makeNode(object)
	return {
		Object = object,
		Children = {},
		Level = huge,
	}
end

local function resetLevel(node, level)
	node.Level = level
	for child, childNode in pairs(node.Children) do
		resetLevel(childNode, level + 1)
	end
end

local function findPath(node)
	local path = {node}
	local parentNode = node.ParentNode
	while parentNode do
		table.insert(path, 1, parentNode)
		parentNode = parentNode.ParentNode
	end
	return path
end

local function hasSamePath(node, ForestCacheMap)
	local path = findPath(node)
	
	for i, pathNode in ipairs(path) do
		local pathInfo = pathNode.Info
		-- do not check for table key, as table value may be the same.
		if string.sub(pathInfo, 1, 1) == "v" then
			return false
		end
	end

	local rootNode = path[1]
	local cachedRootNode = ForestCacheMap[rootNode.Object]
	if not cachedRootNode then
		return false
	end

	local currentNode = cachedRootNode
	local hasSamePath = true
	for i = 2, #path do
		local pathInfo = path[i].Info

		local foundChild
		for _, childNode in pairs(currentNode.Children) do
			if childNode.Info == pathInfo then
				foundChild = true
				currentNode = childNode
				break
			end
		end
		if not foundChild then
			hasSamePath = false
			break
		end
	end

	return hasSamePath
end

local ForestCacheMap = false
function ForestSnapshot(root, checkRoot)
	root = root or debug.getregistry()
	checkRoot = checkRoot or defaultCheckRoot

	local indexMap = {}
	local rootMap = {
		[root] = true,
	}

	traverseObject(root, function (object, parent, info)
		local node = indexMap[object]
		local visited = not not node
		if not node then
			node = makeNode(object, parent)
			indexMap[object] = node
		end

		local isRoot
		if rootMap[object] then
			isRoot = true
		elseif checkRoot(object) then
			rootMap[object] = true
			isRoot = true
		end

		if isRoot then
			node.Parent = nil
			node.ParentNode = nil
			node.Info = info
			resetLevel(node, 0)
		else
			local parentNode = indexMap[parent]
			local thisLevel = parentNode.Level + 1
			if node.Level > thisLevel then
				local oldParentNode = node.ParentNode
				if oldParentNode then
					oldParentNode.Children[object] = nil
				end
				parentNode.Children[object] = node
				node.Parent = parent
				node.ParentNode = parentNode
				node.Info = info
				resetLevel(node, thisLevel)
			end
		end

		return visited
	end, nil, "root")

	local newObjectMap
	if ForestCacheMap then
		newObjectMap = {}

		-- Find new objects
		for object, node in pairs(indexMap) do
			if not ForestCacheMap[object] then
				newObjectMap[object] = node
			end
		end

		-- Filter same position
		for object, node in pairs(newObjectMap) do
			if hasSamePath(node, ForestCacheMap) then
				newObjectMap[object] = nil
			end
		end

		-- Filter subtree node
		for object, node in pairs(newObjectMap) do
			local parent = node.Parent
			if newObjectMap[parent] then
				node.HasNewParent = true
			end
		end

		for object, node in pairs(newObjectMap) do
			if node.HasNewParent then
				newObjectMap[object] = nil
			end
		end
	end

	IgnoreMap[ForestCacheMap] = nil
	ForestCacheMap = indexMap
	IgnoreMap[ForestCacheMap] = true

	return indexMap, newObjectMap, rootMap
end
IgnoreMap[ForestSnapshot] = true

--------------------------------------------------------------------------------
-- Analysis
function Summary(objectMap, formater, valuer)
	local typeAmountMap = {}
	for object, value in pairs(objectMap) do
		local t = formater(object, value)
		if t then
			if not typeAmountMap[t] then
				typeAmountMap[t] = 0
			end
			local value = valuer and valuer(object, _) or 1
			typeAmountMap[t] = typeAmountMap[t] + value
		end
	end
	return typeAmountMap
end

local function applyFilter(objectMap, filter)
	if not filter then
		return objectMap
	end

	local targetMap = {}
	for object, value in pairs(objectMap) do
		if filter(object, value) then
			targetMap[object] = value
		end
	end

	return targetMap
end

function SampleAmount(objectMap, amount, filter)
	amount = amount or 1

	local targetMap = applyFilter(objectMap, filter)
			
	local sampleMap = {}
	for object, value in pairs(targetMap) do
		sampleMap[object] = targetMap[object]
		amount = amount - 1
		if amount == 0 then
			break
		end
	end

	return sampleMap
end

function SampleAndDump(objectMap, amount, filter, dumper)
	local sampleMap = SampleAmount(objectMap, amount, filter)
	dumper = dumper or print
	for object, value in pairs(sampleMap) do
		dumper(object, value)
	end
end

--------------------------------------------------------------------------------
-- Memory statistics
local function doubleMax(size)
	local num = 1
	while num < size do
		num = num * 2
	end
	return num
end

-- Inaccurate numbers, for analysis only
local function getRawMemorySize(object)
	local t = type(object)

	local size = 4
	if t == "table" then
		size = 56
		local n = 0
		for k, v in pairs(object) do
			n = n + 1
		end
		local max = doubleMax(n)
		size = size + 32 * max
	elseif t == "function" then
		size = 72
	elseif t == "string" then
		size = string.len(object)
	end

	return size
end

function SumMemory(objectMap)
	local total = 0
	local memMap = {}
	for object, _ in pairs(objectMap) do
		local t = type(object)
		local size = getRawMemorySize(object)

		memMap[object] = size
		total = total + size
	end

	return total, memMap
end

--------------------------------------------------------------------------------
return {
	GetCurrentMemoryUsage = GetCurrentMemoryUsage,
	Snapshot = ForestSnapshot,
	ForestSnapshot = ForestSnapshot,
	Summary = Summary,
	SampleAndDump = SampleAndDump,
}
