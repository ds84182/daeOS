for i, v in pairs(require "filesystem".list(ps.getEnv("PWD"))) do
	if i ~= "n" then
		print(v)
	end
end
