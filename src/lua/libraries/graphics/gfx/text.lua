local gfx = (...) or _G.gfx

function gfx.GetDefaultFont()
	return fonts.default_font
end

function gfx.SetFont(font)
	fonts.current_font = font or gfx.GetDefaultFont()
end

function gfx.GetFont()
	return fonts.current_font or gfx.GetDefaultFont()
end

local X, Y = 0, 0

function gfx.DrawText(str, x, y, w)
	local ux,uy,uw,uh,usx,usy = surface.GetRectUV()
	local old_tex = surface.GetTexture()
	local r,g,b,a = surface.GetColor()

	x = x or X
	y = y or Y

	local font = gfx.GetFont()

	if not font then
		surface.SetTexture(render.GetErrorTexture())
		surface.DrawRect(x,y,32,32)
	elseif not font:IsReady() then
		surface.SetTexture(render.GetLoadingTexture())
		surface.DrawRect(x,y,32,32)
	else
		font:DrawString(str, x, y, w)
	end

	surface.SetRectUV(ux,uy,uw,uh,usx,usy)
	surface.SetTexture(old_tex)
	surface.SetColor(r,g,b,a)
end

function gfx.SetTextPosition(x, y)
	X = x or X
	Y = y or Y
end

function gfx.GetTextPosition()
	return X, Y
end

do
	local cache = utility.CreateWeakTable()

	function gfx.GetTextSize(str)
		str = str or "|"

		local font = gfx.GetFont()

		if not font then
			return 0,0
		end

		if not font:IsReady() then
			return font.Size, font.Size
		end

		if cache[font] and cache[font][str] then
			return cache[font][str][1], cache[font][str][2]
		end

		local x, y = font:GetTextSize(str)

		cache[font] = cache[font] or utility.CreateWeakTable()
		cache[font][str] = cache[font][str] or utility.CreateWeakTable()
		cache[font][str][1] = x
		cache[font][str][2] = y

		return x, y
	end

	function gfx.InvalidateFontSizeCache(font)
		if font then
			cache[font] = nil
		else
			cache = {}
		end
	end
end

do -- text wrap

	local function wrap_1(str, max_width)
		local lines = {}
		local i = 1

		local last_pos = 0
		local line_width = 0

		local space_pos
		local tbl = str:utotable()

		--local pos = 1
		--for _ = 1, 10000 do
		--	local char = tbl[pos]
		--	if not char then break end
		for pos, char in ipairs(tbl) do
			local w = gfx.GetTextSize(char)

			if char:find("%s") then
				space_pos = pos
			end

			if line_width + w >= max_width then

				if space_pos then
					lines[i] = str:usub(last_pos + 1, space_pos)
					last_pos = space_pos
				else
					lines[i] = str:usub(last_pos + 1, pos)
					last_pos = pos
				end

				i = i + 1

				line_width = 0
				space_pos = nil
			end

			line_width = line_width + w
			--pos = pos + 1
		end

		if lines[1] then
			lines[i] = str:usub(last_pos+1)
			return table.concat(lines, "\n")
		end

		return str
	end

	local function wrap_2(str, max_width)
		local tbl = str:utotable()
		local lines = {}
		local chars = {}
		local i = 1

		local width = 0
		local width_before_last_space = 0
		local width_of_trailing_space = 0

		while i < #tbl do
			local c = tbl[i]

			local char_width = gfx.GetTextSize(c)
			local new_width = width + char_width

			if c == "\n" then
				table.insert(lines, table.concat(chars))
				table.clear(chars)

				width = 0
				width_before_last_space = 0
				width_of_trailing_space = 0

				prev_char = nil
				last_space_index = -1
				i = i + 1
			elseif char ~= " " and width > max_width then
				if #chars == 0 then
					i = i + 1
				elseif last_space_index ~= -1 then
					for i = #chars, 1, -1 do
						if chars[i] == " " then
							break
						end
						table.remove(chars, i)
					end

					width = width_before_last_space
					i = last_space_index
					i = i + 1
				end

				table.insert(lines, table.concat(chars))
				table.clear(chars)

				prev_char = nil
				width = char_width
				width_before_last_space = 0
				width_of_trailing_space = 0
				last_space_index = -1
			else
				if prev_char ~= " " and c == " " then
					width_before_last_space = width
				end

				width = new_width
				prev_char = c

				table.insert(chars, c)

				if c == " " then
					last_space_index = i
				elseif c ~= "\n" then
					width_of_trailing_space = 0
				end

				i = i + 1
			end
		end

		if #chars ~= 0 then
			table.insert(lines, table.concat(chars))
		end

		return table.concat(lines, "\n")
	end

	local cache = utility.CreateWeakTable()

	function gfx.WrapString(str, max_width)
		local font = gfx.GetFont()

		if cache[str] and cache[str][max_width] and cache[str][max_width][font] then
			return cache[str][max_width][font]
		end

		if max_width < gfx.GetTextSize() then
			return table.concat(str:split(""), "\n")
		end
		if max_width > gfx.GetTextSize(str) then
			return str
		end

		local res = wrap_2(str, max_width)
		cache[str] = cache[str] or {}
		cache[str][max_width] = cache[str][max_width] or {}
		cache[str][max_width][font] = res

		return res
	end
end
