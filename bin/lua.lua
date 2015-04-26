local component = require("component")
local term = require("term")

local env = setmetatable({}, {__index = _ENV})

local function optrequire(...)
  local success, module = pcall(require, ...)
  if success then
    return module
  end
end
setmetatable(env, {__index = function(t, k)
  return _ENV[k] or optrequire(k)
end})

local history = {}

local gpu = component.proxy(component.list("gpu",true)())

gpu.setForeground(0xFFFFFF)
term.write("Lua 5.2.3 Copyright (C) 1994-2013 Lua.org, PUC-Rio\n")
gpu.setForeground(0xFFFF00)
term.write("Enter a statement and hit enter to evaluate it.\n")
term.write("Prefix an expression with '=' to show its value.\n")
term.write("Press Ctrl+C to exit the interpreter.\n")
gpu.setForeground(0xFFFFFF)

while term.isAvailable() do
  local foreground = gpu.setForeground(0x00FF00)
  term.write(tostring(env._PROMPT or "lua> "))
  gpu.setForeground(foreground)
  local command = term.read(history)
  if command == nil then -- eof
    return
  end
  while #history > 10 do
    table.remove(history, 1)
  end
  local code, reason
  if string.sub(command, 1, 1) == "=" then
    code, reason = load("return " .. string.sub(command, 2), "=stdin", "t", env)
  else
    code, reason = load(command, "=stdin", "t", env)
  end
  if code then
    local result = table.pack(xpcall(code, debug.traceback))
    if not result[1] then
      if type(result[2]) == "table" and result[2].reason == "terminated" then
        os.exit(result[2].code)
      end
      term.write(tostring(result[2]) .. "\n")
    else
      for i = 2, result.n do
		--TODO: serialization.serialize(result[i], true) instead of tostring
        term.write(tostring(result[i]) .. "\t", true)
      end
      if term.getCursor() > 1 then
        term.write("\n")
      end
    end
  else
    term.write(tostring(reason) .. "\n")
  end
end
