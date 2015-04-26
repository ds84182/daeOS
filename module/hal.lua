--hardware abstraction layer (another word for component security) module!--

local hal = {}

--implement the functions that component has!--
for i, v in pairs(component) do
	hal[i] = v
end

function hal.proxy(address)
	local type = component.type(address)
	for i, v in pairs(config.hal.blacklist) do
		if v == type then
			return false, "Component type is blacklisted"
		end
	end
	--TODO: Method proxies
	return component.proxy(address)
end

function hal.invoke(address,method,...)
	local type = component.type(address)
	for i, v in pairs(config.hal.blacklist) do
		if v == type then
			error("Component type is blacklisted")
		end
	end
	if config.hal.methodBlacklist[type] and config.hal.methodBlacklist[type][method] then
		error("Component method is blacklisted")
	end
	return component.invoke(address,method,...)
end

ks.exposeAPI("hal",hal)
ks.exposeAPI("component",hal) --backwards compatibility
