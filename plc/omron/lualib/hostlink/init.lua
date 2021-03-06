local class = require 'middleclass'
local data_area = require 'hostlink.data_area'
local encode = require 'hostlink.encode'

local hl = class("OMRON_HOSTLINK_FRAME")


function hl:initialize(dev_addr)
	self._addr = dev_addr
	self._encode = encode:new()
end

local xor_check = function(data)
	local xor;

	local function initXor()
		xor = 0x00;
	end
	local function updXor(byte)
		if _VERSION == 'Lua 5.3' then
			xor = xor ~ byte
			xor = xor % 0xFF
		else
			local bit32 = require 'bit'
			xor = bit32.bxor(xor, byte);
			xor = xor % 0xFF
		end
	end

	local function getXor(adu)
		initXor();
		for i = 1, #adu  do
			updXor(adu:byte(i));
		end
		return xor;
	end
	return getXor(adu);
end

function hl:make_frame(frame)
	local xor = xor_check(frame)
	local frame_end = string.format('%02d*\r', xor)

	return frame .. frame_end
end

function hl:make_read(area, offset, length)
	local fmt = '@%02dR%c%04d%04d'
	local frame = string.format(fmt, self._addr, data_area[area], offset, length)

	return self:make_frame(frame)
end

function hl:make_abort()
	local frame = string.format('@%02dXZ', self._addr)
	return self:make_frame(frame)
end

function hl:make_set_monitor_mode()
	local frame = string.format('@%02dSC%c%c', self._addr, string.char(0x30), string.char(0x32))
	return self:make_frame(frame)
end

function hl:make_write(area, offset, raw)
	local fmt = '@%02dW%c%04d%z'
	return self:make_frame(string.format(fmt, self._addr, offset, raw))
end

function hl:make_write_bit(value)
	if type(value) == 'boolean' then
		value = value and '1' or '0'
	elseif type(value) == 'number' then
		value = value == 0 and '0' or '1'
	else
		return nil, "Incorrect value type"
	end
	return self:make_write(value)
end

function hl:make_write_words(area, offset, value_type, value)
	local raw, err = self._encode(value_type, value)
	if not raw then
		return nil, err
	end
	return self:make_write(area, offset, raw)
end


--- Return
--	1. whether the raw has valid frame
--	2. the drop length of raw (valid frame or invalid frame)
--  3. the raw data or error message (depends on first return boolean)
function hl:unpack_frame(raw)
	-- TODO: drop the incorrect raw stream data
	--
	local bn, addr, code, raw  = string.find(raw, '^(.-)@(%d%d)([WR]%W)(.+)%*\r')
	if not bn or not addr then
		return false, 0, "Not valid input"
	end

	local bn_len = string.len(bn)

	if string.len(raw) <= 2 then
		return false, bn_len + 7, "Invalid Input"
	end

	if tonumber(addr) ~= tonumber(self._addr) then
		return false, bn_len + 7, "Not for current device"
	end

	local xor = xor_check(string.format('@%02d%s%s', addr, code, string.sub(raw, 1, string.len(raw) - 3)))
	if xor ~= string.sub(raw, string.len(raw) - 2) then
		return false, bn_len + 7, "Invalid Xor check sum"
	end

	return true, bn_len + string.len(raw) + 7, raw
end

return hl

