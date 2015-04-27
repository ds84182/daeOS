local term = require "term"

local total = computer.totalMemory()..""
local free = computer.freeMemory()..""
local used = (total-free)..""

function padRight(value, length)
	checkArg(1, value, "string", "nil")
	checkArg(2, length, "number")
	if not value or unicode.wlen(value) == 0 then
		return string.rep(" ", length)
	else
		return value .. string.rep(" ", length - unicode.wlen(value))
	end
end

print(padRight("Total",#total).." "..padRight("Used",#used).." Free")
print(total.." "..(total-free).." "..free)
