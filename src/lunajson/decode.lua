local byte = string.byte
local char = string.char
local find = string.find
local gsub = string.gsub
local len = string.len
local match = string.match
local sub = string.sub
local concat = table.concat
local floor = math.floor
local tonumber = tonumber

local function decode(json, pos, nullv)
	local _
	local jsonlen = len(json)
	local dodecode

	-- helper
	local function decodeerror(errmsg)
		error("parse error at " .. pos .. ": " .. errmsg)
	end

	-- parse constants
	local function f_nul()
		local str = sub(json, pos, pos+2)
		if str == 'ull' then
			pos = pos+3
			return nullv
		end
		decodeerror('invalid value')
	end

	local function f_fls()
		local str = sub(json, pos, pos+3)
		if str == 'alse' then
			pos = pos+4
			return false
		end
		decodeerror('invalid value')
	end

	local function f_tru()
		local str = sub(json, pos, pos+2)
		if str == 'rue' then
			pos = pos+3
			return true
		end
		decodeerror('invalid value')
	end

	-- parse numbers
	local radixmark = match(tostring(0.5), '[^0-9]')
	local fixedtonumber = tonumber
	if radixmark ~= '.' then
		if find(radixmark, '%W') then
			radixmark = '%' .. radixmark
		end
		fixedtonumber = function(s)
			return tonumber(gsub(s, '.', radixmark))
		end
	end

	local function cont_number(mns, newpos)
		local expc = byte(json, newpos+1)
		if expc == 0x45 or expc == 0x65 then -- e or E?
			_, newpos = find(json, '^[+-]?[0-9]+', newpos+2)
			if not newpos then
				decodeerror('invalid number')
			end
		end
		local num = fixedtonumber(sub(json, pos-1, newpos))
		if mns then
			num = -num
		end
		pos = newpos+1
		return num
	end

	local function f_zro(mns)
		local _, newpos = find(json, '^%.[0-9]+', pos)
		if newpos then
			return cont_number(mns, newpos)
		end
		return 0
	end

	local function f_num(mns)
		local _, newpos = find(json, '^[0-9]*%.?[0-9]*', pos)
		if byte(json, newpos) ~= 0x2E then -- check that num is not ended by comma
			return cont_number(mns, newpos)
		end
		decodeerror('invalid number')
	end

	local function f_mns()
		local c = byte(json, pos)
		if c then
			pos = pos+1
			if c > 0x30 then
				if c < 0x3A then
					return f_num(true)
				end
			else
				if c > 0x2F then
					return f_zro(true)
				end
			end
		end
		decodeerror('invalid number')
	end

	-- parse strings
	local f_str_surrogateprev = 0

	local f_str_tbl = {
		['"']  = '"',
		['\\'] = '\\',
		['/']  = '/',
		['b']  = '\b',
		['f']  = '\f',
		['n']  = '\n',
		['r']  = '\r',
		['t']  = '\t'
	}

	local function f_str_subst(ch, rest)
		-- 0.000003814697265625 = 2^-18
		-- 0.000244140625 = 2^-12
		-- 0.015625 = 2^-6
		local u8
		if ch == 'u' then
			local l = len(rest)
			local ucode = match(rest, '^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]')
			if not ucode then
				decodeerror("invalid unicode charcode")
			end
			ucode = tonumber(ucode, 16)
			rest = sub(rest, 5)
			if ucode < 0x80 then -- 1byte
				u8 = char(ucode)
			elseif ucode < 0x800 then -- 2byte
				u8 = char(0xC0 + floor(ucode * 0.015625) % 0x10000, 0x80 + ucode % 0x40)
			elseif ucode < 0xD800 or 0xE000 <= ucode then -- 3byte
				u8 = char(0xE0 + floor(ucode * 0.000244140625) % 0x10000, 0x80 + floor(ucode * 0.015625) % 0x40, 0x80 + ucode % 0x40)
			elseif 0xD800 <= ucode and ucode < 0xDC00 then -- surrogate pair 1st
				if f_str_surrogateprev == 0 then
					f_str_surrogateprev = ucode
					if rest == '' then
						return ''
					end
				end
			else -- surrogate pair 2nd
				if f_str_surrogateprev == 0 then
					f_str_surrogateprev = 1
				else
					ucode = 0x10000 + (f_str_surrogateprev - 0xD800) * 0x400 + (ucode - 0xDC00)
					f_str_surrogateprev = 0
					u8 = char(0xF0 + floor(ucode * 0.000003814697265625), 0x80 + floor(ucode * 0.000244140625) % 0x40, 0x80 + ucode * 0.015625 % 0x40, 0x80 + ucode % 0x40)
				end
			end
		end
		if f_str_surrogateprev ~= 0 then
			decodeerror("invalid surrogate pair")
		end
		return (u8 or f_str_tbl[ch] or decodeerror("invalid escape sequence")) .. rest
	end

	local function f_str()
		local newpos = pos-2
		local pos2
		repeat
			pos2 = newpos+2
			newpos = find(json, '[\\"]', pos2)
			if not newpos then
				decodeerror("unterminated string")
			end
		until byte(json, newpos) == 0x22

		local str = sub(json, pos, newpos-1)
		if pos2 ~= pos then
			str = gsub(str, '\\(.)([^\\]*)', f_str_subst)
			if f_str_surrogateprev ~= 0 then
				decodeerror("invalid surrogate pair")
			end
		end

		pos = newpos+1
		return str
	end

	-- parse arrays
	local function f_ary()
		local ary = {}

		_, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1
		if byte(json, pos) ~= 0x5D then
			local newpos = pos-1

			local i = 0
			repeat
				i = i+1
				pos = newpos+1
				ary[i] = dodecode()
				_, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
			until not newpos

			_, newpos = find(json, '^[ \n\r\t]*%]', pos)
			if not newpos then
				decodeerror("no closing bracket of an array")
			end
			pos = newpos
		end

		pos = pos+1
		return ary
	end

	-- parse objects
	local function f_obj()
		local obj = {}

		_, pos = find(json, '^[ \n\r\t]*', pos)
		pos = pos+1
		if byte(json, pos) ~= 0x7D then
			local newpos = pos-1

			repeat
				pos = newpos+1
				if byte(json, pos) ~= 0x22 then
					decodeerror("not key")
				end
				pos = pos+1
				local key = f_str()
				_, newpos = find(json, '^[ \n\r\t]*:[ \n\r\t]*', pos)
				if not newpos then
					decodeerror("no colon after a key")
				end
				pos = newpos+1
				obj[key] = dodecode()
				_, newpos = find(json, '^[ \n\r\t]*,[ \n\r\t]*', pos)
			until not newpos

			_, newpos = find(json, '^[ \n\r\t]*}', pos)
			if not newpos then
				decodeerror("no closing bracket of an object")
			end
			pos = newpos
		end

		pos = pos+1
		return obj
	end

	local dispatcher = {
		false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
		false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
		false, false, f_str, false, false, false, false, false, false, false, false, false, false, f_mns, false, false,
		f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, f_num, false, false, false, false, false, false,
		false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
		false, false, false, false, false, false, false, false, false, false, false, f_ary, false, false, false, false,
		false, false, false, false, false, false, f_fls, false, false, false, false, false, false, false, f_nul, false,
		false, false, false, false, f_tru, false, false, false, false, false, false, f_obj, false, false, false, false,
	}

	function dodecode()
		local c = byte(json, pos)
		if not c then
			decodeerror("unexpected termination")
		end
		local f = dispatcher[c+1]
		if not f then
			decodeerror("invalid value")
		end
		pos = pos+1
		return f()
	end

	_, pos = find(json, '^[ \n\r\t]*', pos)
	pos = pos+1
	local v = dodecode()
	return v, pos
end

return decode
