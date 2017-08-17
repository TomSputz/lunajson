local util = require('util')


function bench(encode, fn)
	local data = util.load('data/' .. fn .. '.lua')
	local acc = 0
	for i = 1, 100 do
		local t1 = os.clock()
		encode(data)
		local t2 = os.clock()
		local t = t2-t1
		acc = acc+t
	end
	return acc
end


local encoders = loader('encoders.lua')
local data = loader('data.lua')

for _, encoder in ipairs(encoders) do
	print(encoder .. ': ')
	local encode = util.load('encode/' .. encoder .. '.lua')
	for _, fn in ipairs(data) do
		local t =  bench(encode, fn)
		print('  ' .. fn .. ':' .. string.format("%.03f", t))
	end
end