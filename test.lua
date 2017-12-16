--[[
File : test.lua
Author : yunmang
Email : yunmang@gmail.com
--]]

local viewer = require("memory_viewer")
local snapshot = viewer.Snapshot
local summary = viewer.Summary
local sampleAndDump = viewer.SampleAndDump

function IsTable(object)
	return type(object) == "table"
end

function IsFunction(object)
	return type(object) == "function"
end

local __id = 10000
local function genId()
	__id = __id + 1
	return __id
end

local function tableToString(t)
	local msg = ""
	for key, value in pairs(t) do
		msg = string.format("%s | %s: %s", msg, tostring(key), tostring(value))
	end
	return msg
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

local function getFunctionPath(func)
	local info = debug.getinfo(func, "Sl")
	return string.format("%s+%d", info.source, info.linedefined)
end

local function dumpFunction(func, value)
	print(getFunctionPath(func), value)
end

local function nodeToString(node)
	local info = node.Info
	if not info then
		return ""
	end

	local ret = info
	local object = node.Object
	if IsTable(object) and object._className then
		ret = string.format("%s<cls:%s>", ret, object._className)
	end

	return ret
end

local function dumpPath(object, node)
	local str = nodeToString(node)
	local parentNode = node.ParentNode
	while parentNode do
		str = string.format("%s.%s", nodeToString(parentNode), str)
		parentNode = parentNode.ParentNode
	end
	print("type:", type(object), object, str)
end

local root = {}
local function genTree()
	root._className = "clsRoot" -- make table non-array

	root[1] = 1
	root[genId()] = 1 -- will be found

	root[2] = "string"
	root[genId()] = "string" -- will be found

	-- table
	root[3] = {["name"] = "normal"}
	root[genId()] = {["name"] = "genId"} -- will be found

	-- closure
	local v1 = {
		["name"] = "closure",
		[genId()] = {1},
	}
	local function f()
		local v2 = v1
		return function ()
			return v2
		end
	end
	root[4] = f()

	-- path
	root[5] = {
		["key"] = {
			[genId()] = {["name"] = "path"},
		},
	}

	-- table as key
	local key = {
		["key"] = {
			[1] = {["name"] = "path"},
		},
	}
	root[6] = "table as key"
	root[key] = "table as key"
end

local lastSize = false
local function dumpSnapshot()
	collectgarbage("collect")
	collectgarbage("collect")
	local currentSize = collectgarbage("count") * 1024
	print("current:", currentSize)
	if lastSize then
		print("diff:", currentSize - lastSize)
	end
	lastSize = currentSize

	local indexMap, newObjectMap = snapshot(root)

	local visitSummaryMap = summary(indexMap, type)
	print("all:", tableToString(visitSummaryMap))

	if newObjectMap then
		local newObjectSummaryMap = summary(newObjectMap, type)
		print("new:", tableToString(newObjectSummaryMap))

		-- sampleAndDump(newObjectMap, 100, IsTable, dumpTable)
		-- sampleAndDump(newObjectMap, 100, IsFunction, dumpFunction)

		sampleAndDump(newObjectMap, 100, nil, dumpPath)
	end
end

function Test()
	genTree()
	dumpSnapshot()
	__id = 20000
	genTree()
	dumpSnapshot()
end

Test()
