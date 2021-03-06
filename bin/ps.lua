--list the running processes--
local term = require "term"

local args = ps.getArguments()
args[1] = args[1] or "info"

local psrun = {}

function psrun.info(...)
	local reqpid = table.pack(...)
	local columnWidth = {}
	local column = {}
	local corder = {}
	local function addString(col,str)
		columnWidth[col] = math.max(columnWidth[col] or 0, #str)
		if not column[col] then
			corder[#corder+1] = col
		end
		column[col] = column[col] or {}
		column[col][#column[col]+1] = str
	end

	local function padRight(value, length)
		checkArg(1, value, "string", "nil")
		checkArg(2, length, "number")
		if not value or unicode.wlen(value) == 0 then
			return string.rep(" ", length)
		else
			return value .. string.rep(" ", length - unicode.wlen(value))
		end
	end

	addString("ID","ID")
	addString("Name","Name")
	addString("Status","Status")
	addString("Kernel","Kernel")
	addString("Parent","Parent")
	local proc = ps.listProcesses()
	local info = {}
	local reqpidmap = {}
	for i, v in ipairs(reqpid) do
		if v == "current" then
			v = ps.getCurrentProcess()
		end
		reqpidmap[v] = true
	end
	for i, v in pairs(proc) do
		if #reqpid == 0 or reqpidmap[v] then
			ps.getInfo(v,info)
			addString("ID",tostring(v))
			addString("Name",info.name)
			addString("Status",info.status)
			addString("Kernel",info.kernelspace and "kernel" or "user")
			addString("Parent",tostring(info.parent) or "None")
		end
	end

	for i=1, #column.ID do
		for _, v in ipairs(corder) do
			io.write(padRight(column[v][i],columnWidth[v]+1))
		end
		io.write("\n")
	end
end

function psrun.kill(...)
	local info = {}
	for i, v in pairs({...}) do
		v = tonumber(v)
		local s, e = ps.remove(v)
		print(s and "killed sucessfully" or "kill failed: "..e)
	end
end

function psrun.error(...)
	local info = {}
	for i, v in pairs({...}) do
		v = tonumber(v)
		ps.getInfo(v,info)
		print(v..":")
		print(info.error or "not finished")
	end
end

psrun[table.remove(args,1)](table.unpack(args))
