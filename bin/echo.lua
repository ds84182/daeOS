local args = ps.getArguments()
local term = require "term"

term.write(table.concat(args," "))
term.write("\n")
