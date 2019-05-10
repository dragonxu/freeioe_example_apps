local class = require 'middleclass'
local app_port = require 'app.port'

local serial = class("PORT_TEST_PAIR_SERIAL")

function serial:initialize(app)
	self._app = app
	self._sys = app._sys
end

---- The port_a is serial options: e.g. { port = "/dev/ttymxc1", baudrate=115200 }
function serial:open(port_a, port_b)
	self._port_a = app_port.new_serial(port_a)
	self._port_b = app_port.new_serial(port_b)
end

function serial:close()
	self._port_a:close()
	self._port_b:close()
	self._port_a = nil
	self._port_b = nil
end

--- Block run
function serial:run(test_case)
	local r, err = test_case:start(self._port_a, self._port_b)
	if not r then
		return nil, err
	end

	while not self._abort and not test_case:finished() do
		local r, err = test_case:run()
		if not r then
			return nil, err
		end
		self._sys:sleep(r, self)
	end
	if self._abort then
		return nil, "Aborted"
	end

	return true, test_case:report()
end

--- Abort block run
function serial:abort()
	if not self._abort then
		self._abort = true
		self._sys:wakeup(self)
		return true
	end
	return false, "Aborting"
end

return serial
