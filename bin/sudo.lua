local sudo = require "sudo"
local filesystem = require "filesystem"
local args = ps.getArguments()

sudo.spawnElevated(filesystem.read("/bin/shell.lua"),exec,args,ps.getSTDIN(),ps.getSTDOUT(),ps.getSTDERR(),ps.listEnv())
