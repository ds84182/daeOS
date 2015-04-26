--filesystem module!--

local filesystem = {}
local mounts = {}

local function splitPath(path)
	local pt = {}
	for p in path:gmatch("[^/]+") do
		if p == ".." then
			pt[#pt] = nil
		elseif p ~= "." and p ~= "" then
			pt[#pt+1] = p
		end
	end
	return pt
end

function filesystem.combine(...)
	local np = {}
	for i, v in ipairs({...}) do
		checkArg(i, v, "string")
		for i, v in ipairs(splitPath(v)) do
			np[#np+1] = v
		end
	end
	return "/"..table.concat(np,"/")
end

function filesystem.fixPath(path)
	checkArg(1, path, "string")
	local sp = splitPath(path)
	return "/"..table.concat(sp,"/"), sp
end

function filesystem.childOf(parent,child)
	local parent, sparent = filesystem.fixPath(parent)
	local child, schild = filesystem.fixPath(child)
	return child:sub(1,#parent) == parent, #schild-#sparent, schild, sparent
end

function filesystem.canModify(path)
	if not ps.isKernelMode() then
		local allow,levelsDeep = false,#splitPath(path)
		for i, v in pairs(config.filesystem.allowed) do
			local ischild, levels = filesystem.childOf(v,path)
			if ischild and levelsDeep > levels then
				levelsDeep = levels
				allow = true
			end
		end
		for i, v in pairs(config.filesystem.disallowed) do
			local ischild, levels = filesystem.childOf(v,path)
			if ischild and levelsDeep > levels then
				levelsDeep = levels
				allow = false
			end
		end
		return allow
	end
	return true
end

function filesystem.mount(path,fsobj)
	checkArg(1, path, "string")
	checkArg(2, fsobj, "table")
	local spath
	path,spath = filesystem.fixPath(path)
	if not filesystem.canModify(path) then return false, "permission denied" end
	if mounts[path] then return false, "another filesystem is already mounted here" end
	if path ~= "/" and not filesystem.isDirectory("/"..table.concat({table.unpack(spath,1,#spath-1)},"/")) then--check if the parent is made--
		return false, "parent is not a directory"
	end
	mounts[path] = fsobj
	return true
end

function filesystem.unmount(path)
	checkArg(1, path, "string")
	if not filesystem.canModify(path) then return false, "permission denied" end
	mounts[filesystem.fixPath(path)] = nil
	return true
end

local function getMountAndPath(path)
	local spath
	path,spath = filesystem.fixPath(path)
	if mounts[path] then
		return mounts[path], "/"
	else
		for i=#spath-1, 1, -1 do
			local npath = "/"..table.concat({table.unpack(spath,1,i)},"/")
			if mounts[npath] then
				return mounts[npath], "/"..table.concat({table.unpack(spath,i+1)},"/")
			end
		end
	end
	return mounts["/"], path
end

function filesystem.open(path,mode)
	checkArg(1, path, "string")
	checkArg(2, mode, "nil", "string")
	if (mode:find("w") or mode:find("a")) and not filesystem.canModify(path) then return nil, "permission denied" end
	local mount,path = getMountAndPath(path)
	local handle, err = mount.open(path,mode or "r")
	if not handle then return nil, err end
	return {
		read = function(number)
			return mount.read(handle,number)
		end,
		write = function(data)
			return mount.write(handle,data)
		end,
		seek = function(whence,offset)
			return mount.seek(handle,whence,offset)
		end,
		close = function()
			return mount.close(handle)
		end,
		ioctl = function(request, ...)
			if not mount.ioctl then
				return false, "filesystem does not support ioctl"
			end
			return mount.ioctl(handle,request,table.pack(...))
		end
	}
end

function filesystem.makeDirectory(path)
	checkArg(1, path, "string")
	if not filesystem.canModify(path) then return false, "permission denied" end
	local mount,path = getMountAndPath(path)
	return mount.makeDirectory(path)
end

function filesystem.exists(path)
	checkArg(1, path, "string")
	local mount,path = getMountAndPath(path)
	return mount.exists(path)
end

function filesystem.isReadOnly(path) --TODO: Path permissions!
	checkArg(1, path, "string")
	if not filesystem.canModify(path) then return true end
	local mount,path = getMountAndPath(path)
	return mount.isReadOnly()
end

function filesystem.spaceTotal(path)
	checkArg(1, path, "string")
	local mount,path = getMountAndPath(path)
	return mount.spaceTotal()
end

function filesystem.isDirectory(path)
	checkArg(1, path, "string")
	local mount,path = getMountAndPath(path)
	return mount.isDirectory(path)
end

function filesystem.rename(from,to)
	checkArg(1, from, "string")
	checkArg(2, to, "string")
	if not filesystem.canModify(from) then return false, "permission denied" end
	if not filesystem.canModify(to) then return false, "permission denied" end
	local frommount,from = getMountAndPath(from)
	local tomount,to = getMountAndPath(to)
	if frommount == tomount then
		return frommount.rename(from,to)
	else
		--file copy!
		local fromhandle = frommount.open(from,"rb")
		local tohandle = tomount.open(to,"wb")
		local data = frommount.read(fromhandle,math.huge)
		while data do
			tomount.write(tohandle,data)
			data = frommount.read(fromhandle,math.huge)
		end
		frommount.close(fromhandle)
		tomount.close(tohandle)
		frommount.remove(from)
		return true
	end
end

function filesystem.list(path)
	checkArg(1, path, "string")
	local oldpath = path
	local mount,path = getMountAndPath(path)
	local list, err = mount.list(path)
	if not list then
		return nil, err
	end
	
	--add mounts that are just under this directory
	for i, v in pairs(mounts) do
		local ischild, levels, schild = filesystem.childOf(oldpath,i)
		
		if levels == 1 then
			list[#list+1] = schild[#schild].."/"
		end
	end
	table.sort(list)
	list.n = #list
	return list
end

function filesystem.lastModified(path)
	checkArg(1, path, "string")
	local mount,path = getMountAndPath(path)
	return mount.lastModified(path)
end

function filesystem.getLabel(path)
	checkArg(1, path, "string")
	local mount,path = getMountAndPath(path)
	return mount.getLabel()
end

function filesystem.remove(path)
	checkArg(1, path, "string")
	if not filesystem.canModify(path) then return false, "permission denied" end
	local mount,path = getMountAndPath(path)
	return mount.remove(path)
end

function filesystem.size(path)
	checkArg(1, path, "string")
	local mount,path = getMountAndPath(path)
	return mount.size(path)
end

function filesystem.setLabel(path,label)
	checkArg(1, path, "string")
	checkArg(2, label, "string")
	local mount,path = getMountAndPath(path)
	return mount.setLabel(label)
end

function filesystem.read(path) --reads an entire file in one go
	checkArg(1, path, "string")
	local mount,path = getMountAndPath(path)
	local fh = mount.open(path,"r")
	local sbsrc = {}
	local sbseg = mount.read(fh, math.huge)
	while sbseg do
		sbsrc[#sbsrc+1] = sbseg
		sbseg = mount.read(fh, math.huge)
	end
	mount.close(fh)
	return table.concat(sbsrc,"")
end

filesystem.mount("/",component.proxy(computer.getBootAddress()))
filesystem.mount("/tmp",component.proxy(computer.tmpAddress()))

function filesystem.makeDeviceTree(dev)
	checkArg(1, dev, "table")
	local fs = {}
	
	function fs.spaceUsed()
		return 0
	end
	
	local openHandles = {}
	
	function fs.open(path,mode)
		local p = splitPath(path)
		local traverse = dev
		local i = 1
		while p[i] do
			traverse = traverse[p[i]]
			if not traverse then
				return nil, "no such file or directory"
			end
			i = i+1
		end
		if not traverse then
			return nil, "file not found"
		end
		
		if type(traverse) == "table" then
			return nil, "is a directory"
		end
		
		if not traverse("open",mode) then
			return nil, "open failed"
		end
		
		local handle = math.random(1,99999)
		while openHandles[handle] do handle = math.random(1,99999) end
		openHandles[handle] = traverse
		
		return handle
	end
	
	function fs.read(handle, number)
		return openHandles[handle]("read", number)
	end
	
	function fs.write(handle, data)
		return openHandles[handle]("write", data)
	end
	
	function fs.seek(handle, whence, offset)
		return openHandles[handle]("seek", whence, offset)
	end
	
	function fs.ioctl(handle, request, args)
		return openHandles[handle]("ioctl", request, args)
	end
	
	function fs.close(handle)
		openHandles[handle] = nil
	end
	
	function fs.makeDirectory()
		return nil, "mkdir failure"
	end
	
	function fs.exists(path)
		local p = splitPath(path)
		local traverse = dev
		local i = 1
		while p[i] do
			traverse = traverse[p[i]]
			if not traverse then
				return nil, "no such file or directory"
			end
			i = i+1
		end
		
		return not not traverse
	end
	
	function fs.isReadOnly()
		return false
	end
	
	function fs.spaceTotal()
		return 0
	end
	
	function fs.isDirectory(path)
		local p = splitPath(path)
		local traverse = dev
		local i = 1
		while p[i] do
			traverse = traverse[p[i]]
			if not traverse then
				return nil, "no such file or directory"
			end
			i = i+1
		end
		
		return type(traverse) == "table"
	end
	
	function fs.rename()
		return false, "cannot rename files"
	end
	
	function fs.list(path)
		local p = splitPath(path)
		local traverse = dev
		local i = 1
		while p[i] do
			traverse = traverse[p[i]]
			if not traverse then
				return nil, "no such file or directory"
			end
			i = i+1
		end
		
		if type(traverse) ~= "table" then
			return nil, "not a directory"
		end
		
		local lst = {}
		for i, v in pairs(traverse) do
			if type(v) == "table" then
				lst[#lst+1] = i.."/"
			else
				lst[#lst+1] = i
			end
		end
		return lst
	end
	
	function fs.lastModified()
		return 0
	end
	
	function fs.getLabel()
		return "dev"
	end
	
	function fs.setLabel()
		return nil, "cannot set label"
	end
	
	function fs.size()
		return 0 --todo: get size from actual things
	end
	
	return fs
end

local dev = {}
filesystem.mount("/dev",filesystem.makeDeviceTree(dev))

function dev.stdin(mode, data)
	if mode == "read" then
		--get process, invoke stdin func--
		local stdin = ps.getSTDIN()
		if stdin then
			return stdin(data)
		else
			return nil, "no such device"
		end
	elseif mode == "open" then
		return not not data:find("r")
	elseif mode == "close" then
		return true
	else
		return nil, "bad file descriptor"
	end
end

function dev.stdout(mode, data)
	if mode == "write" then
		--get process, invoke stdin func--
		local stdout = ps.getSTDOUT()
		if stdout then
			return stdout(data)
		else
			return nil, "no such device"
		end
	elseif mode == "open" then
		return not not data:find("w")
	elseif mode == "close" then
		return true
	else
		return nil, "bad file descriptor"
	end
end

function dev.stderr(mode, data)
	if mode == "write" then
		--get process, invoke stdin func--
		local stderr = ps.getSTDERR()
		if stderr then
			return stderr(data)
		else
			return nil, "no such device"
		end
	elseif mode == "open" then
		return not not data:find("w")
	elseif mode == "close" then
		return true
	else
		return nil, "bad file descriptor"
	end
end

local computer = component.proxy(component.list("computer")())
function dev.beep(mode, request, args)
	if mode == "ioctl" then
		if request == "beep" then
			computer.beep(args[1], args[2])
		else
			return false, "invalid request"
		end
		return true
	elseif mode == "open" then
		return true
	elseif mode == "close" then
		return true
	else
		return nil, "bad file descriptor"
	end
end

ks.filesystem_dev = dev

ks.exposeAPI("filesystem",filesystem)
