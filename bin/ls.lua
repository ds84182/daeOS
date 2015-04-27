local filesystem = require "filesystem"

local dir = ...
dir = dir or "."
if dir:sub(1,1) ~= "/" then
	dir = filesystem.fixPath(ps.getEnv("PWD").."/"..dir)
end

if filesystem.isDirectory(dir) then
	for i, v in ipairs(filesystem.list(dir)) do
		print(v)
	end
else
	print(dir)
end
