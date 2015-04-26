local component = require("component")
local term = require("term")

local args = ps.getArguments()
if #args == 0 then
  local w, h = component.invoke(component.list("gpu",true)(),"getResolution")
  term.write(w .. " " .. h .. "\n")
  return
end

if #args < 2 then
  term.write("Usage: resolution [<width> <height>]\n")
  return
end

local w = tonumber(args[1])
local h = tonumber(args[2])
if not w or not h then
  term.write("invalid width or height\n")
  return
end

local result, reason = component.invoke(component.list("gpu",true)(),"setResolution", w, h)
if not result then
  if reason then -- otherwise we didn't change anything
    term.write(reason.."\n")
  end
  return
end
term.clear()
