local META = ... or prototype.GetRegistered("material", "model")

local path_translate = {
	{"AlbedoTexture", "basetexture"},
	{"Albedo2Texture", "basetexture2"},
	{"NormalTexture", "bumpmap"},
	{"Normal2Texture", "bumpmap2"},
	{"MetallicTexture", "envmapmask"},
	{"RoughnessTexture", "phongexponenttexture"},
	--{"SelfIlluminationTexture", "selfillummask"},
}

local property_translate = {
	--{"IlluminationColor", {"selfillumtint"}},
	{"AlphaTest", {"alphatest", function(num) return num == 1 end}},
	{"SSBump", {"ssbump", function(num) return num == 1 end}},
	{"NoCull", {"nocull"}},
	{"Translucent", {"alphatest", "translucent", function(num) return num == 1 end}},
	{"NormalAlphaMetallic", {"normalmapalphaenvmapmask", function(num) return num == 1 end}},
	{"AlbedoAlphaMetallic", {"basealphaenvmapmask", function(num) return num == 1 end}},
	{"RoughnessMultiplier", {"phongexponent", function(num) return 1/(-num+1)^3 end}},
	{"MetallicMultiplier", {"envmaptint", function(num) return type(num) == "number" and num or typex(num) == "vec3" and num.x or typex(num) == "color" and num.r end}},
	--{"SelfIllumination", {"selfillum", function(num) return num end}},
}

local special_textures = {
	_rt_fullframefb = "error",
	[1] = "error", -- huh
}

function META:LoadVMT(path)
	self:SetName(path)

	resource.Download(
		path,
		function(path)
			if path:endswith(".vtf") then
				self:SetAlbedoTexture(render.CreateTextureFromPath(path, true))
				-- default normal map?
				return
			end

			local vmt, err = utility.VDFToTable(vfs.Read(path), function(key) return (key:lower():gsub("%$", "")) end)

			if err then
				self:SetError(path .. " utility.VDFToTable : " .. err)
				return
			end

			local k,v = next(vmt)

			if type(k) ~= "string" or type(v) ~= "table" then
				self:SetError("bad material " .. path)
				table.print(vmt)
				return
			end

			if k == "patch" then
				if not vfs.IsFile(v.include) then
					v.include = vfs.FindMixedCasePath(v.include) or v.include
				end

				local vmt2, err2 = utility.VDFToTable(vfs.Read(v.include), function(key) return (key:lower():gsub("%$", "")) end)

				if err2 then
					self:SetError(err2)
					return
				end

				local k2,v2 = next(vmt2)

				if type(k2) ~= "string" or type(v2) ~= "table" then
					self:SetError("bad material " .. path)
					table.print(vmt)
					return
				end

				table.merge(vmt2, v.replace)

				vmt = vmt2
				v = v2
				k = k2
			end

			vmt = v
			vmt.shader = k
			vmt.fullpath = path

			for _, v in ipairs(property_translate) do
				local key, info = v[1], v[2]
				for _,v in ipairs(info) do
					local val = vmt[v]
					if val then
						local func = info[#info]

						if self["Set" .. key] then
							self["Set" .. key](self, (type(func) == "function" and func(val)) or val)
						end

						break
					end
				end
			end

			for k, v in pairs(vmt) do
				if type(v) == "string" and (special_textures[v] or special_textures[v:lower()]) then
					vmt[k] = special_textures[v]
				end
			end

			if not vmt.bumpmap and vmt.basetexture and not special_textures[vmt.basetexture] then
				local new_path = vfs.FixPathSlashes(vmt.basetexture)
				if not new_path:endswith(".vtf") then
					new_path = new_path .. ".vtf"
				end
				new_path = new_path:gsub("%.vtf", "_normal.vtf")
				if vfs.IsFile("materials/" .. new_path) then
					vmt.bumpmap = new_path
				else
					new_path = new_path:lower()
					if vfs.IsFile("materials/" .. new_path) then
						vmt.bumpmap = new_path
					end
				end
			end

			--material:SetRoughnessTexture(render.GetWhiteTexture())
			--material:SetMetallicTexture(render.GetGreyTexture())
			--material:SetRoughnessMetallicInvert(true)

			for _, v in ipairs(path_translate) do
				local key, field = v[1], v[2]

				if vmt[field] and (not special_textures[vmt[field]] and not special_textures[vmt[field]:lower()]) then
					local new_path = vfs.FixPathSlashes("materials/" .. vmt[field])
					if not new_path:endswith(".vtf") then
						new_path = new_path .. ".vtf"
					end
					resource.Download(
						new_path,
						function(path)
							if key == "AlbedoTexture" or key == "Albedo2Texture" then
								self["Set" .. key](self, render.CreateTextureFromPath(path, true))
							else
								self["Set" .. key](self, render.CreateTextureFromPath(path, false)) -- not srgb
							end
						end, nil, nil, true
					)
				end
			end

			--material:SetRoughnessTexture(math.clamp(material:GetRoughnessTexture(), 0.05, 0.95))

			self.vmt = vmt
		end,
		function()
			self:SetError("material "..path.." not found")
		end,
		nil,
		true
	)
end

if RELOAD then
	for _,v in pairs(prototype.GetCreated()) do
		if v.Type == "material" and v.ClassName == "model" and v.vmt then
			--v:SetMetallicMultiplier(v:GetMetallicMultiplier()/3)
		end
	end
end