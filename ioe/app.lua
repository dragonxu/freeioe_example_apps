local class = require 'middleclass'
local snax = require 'skynet.snax'
local datacenter = require 'skynet.datacenter'
local sysinfo = require 'utils.sysinfo'
local gcom = require 'utils.gcom'
local leds = require 'utils.leds'
local event = require 'app.event'
local sum = require 'summation'
local ioe = require 'ioe'
local lfs = require 'lfs'
-- own libs
local disk = require 'disk'
local netinfo = require 'netinfo'

local app = class("FREEIOE_SYS_APP_CLASS")
app.API_VER = 1

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf or {}
	self._api = self._sys:data_api()
	self._log = sys:logger()
	self._cancel_timers = {}
	self._apps_cache = {}
end

function app:start()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			print('on_output', app, sn, output, prop, value)
			return true, "done"
		end,
		on_command = function(app, sn, command, param)
			if command == 'cfg_crash_ack' then
				return self:cfg_crash_ack()
			end
			print('on_command', app, sn, command, param)
			return true, "eee"
		end,
		on_ctrl = function(app, command, param, ...)
			print('on_ctrl', app, command, param, ...)
		end,
	})

	local inputs = {
		{
			name = 'cpuload',
			desc = 'CPU Load Avg_15'
		},
		{
			name = 'cpu_temp',
			desc = 'CPU Temperature'
		},
		{
			name = 'mem_total',
			desc = 'Memory total size',
		},
		{
			name = 'mem_used',
			desc = 'Memory used size',
			vt = "int",
		},
		--[[
		{
			name = 'mem_free',
			desc = 'System memory free size',
			vt = "int",
		},
		]]--
		{
			name = "uptime",
			desc = "System uptime",
			vt = "int",
		},
		{
			name = "starttime",
			desc = "FreeIOE start time in UTC",
			vt = "int",
		},
		{
			name = "version",
			desc = "FreeIOE Version",
			vt = "int",
		},
		{
			name = "skynet_version",
			desc = "Skynet Platform Version",
			vt = "int",
		},
		{
			name = "platform",
			desc = "Skynet Platform type",
			vt = "string",
		},
		{
			name = "firmware_version",
			desc = "OS firmware version",
			vt = "string",
		},
		{
			name = "data_upload",
			desc = "Data upload flag",
			vt = "int",
		},
		{
			name = "data_upload_cov",
			desc = "Data upload COV setting",
			vt = "int",
		},
		{
			name = "data_upload_cov_ttl",
			desc = "Data upload COV TTL",
			vt = "int",
		},
		{
			name = "data_upload_period",
			desc = "Data upload period",
			vt = "int",
		},
		{
			name = "stat_upload",
			desc = "Statictis data upload flag",
			vt = "int",
		},
		{
			name = "comm_upload",
			desc = "Comms upload end time",
			vt = "int",
		},
		{
			name = "log_upload",
			desc = "Logs upload end time",
			vt = "int",
		},
		{
			name = "event_upload",
			desc = "Event upload min level",
			vt = "int"
		},
		{
			name = "enable_beta",
			desc = "Device beta mode flag",
			vt = "int",
		},
		--[[
		{
			name = 'disk_tmp_used',
			desc = "Disk /tmp used percent",
		}
		]]--
	}
	local sys_id = self._sys:hw_id()
	local id = self._sys:id()
	if string.sub(sys_id, 1, 8) == '2-30002-' then
		self._gcom = true
		self._cpu_temp = true
		local gcom_inputs = {
			{
				name = 'ccid',
				desc = 'SIM card ID',
				vt = "string",
			},
			{
				name = 'csq',
				desc = 'GPRS/LTE sginal strength',
				vt = "int",
			},
			{
				name = 'cpsi',
				desc = 'GPRS/LTE work mode',
				vt = "string",
			},
			{
				name = 'wan_s',
				desc = 'GPRS/LET network send bytes (kB)',
				vt = 'int',
			},
			{
				name = 'wan_r',
				desc = 'GPRS/LET network receive bytes (kB)',
				vt = 'int',
			},
		}

		for _,v in ipairs(gcom_inputs) do
			inputs[#inputs + 1] = v
		end
		self._wan_sum = sum:new({
			file = true,
			save_span = 60 * 5, -- five minutes
			key = 'wan',
			span = 'month',
			path = '/root', -- Q102's data/cache partition
		})
	end

	-- for apps
	local apps = datacenter.get("APPS")
	for k, v in pairs(apps) do
		self._apps_cache[k] = {
			name = v.name,
			version = v.version,
			sn = v.sn,
			auto = v.auto
		}
		inputs[#inputs + 1] = {
			name = 'app_run_'..k,
			desc = 'Status for app '..k,
			vt = "int",
		}
	end
	if not self._apps_cache['ioe'] then
		self._apps_cache['ioe'] = {
			name = 'freeioe',
		}
	end

	local cmds = {
		{
			name = "cfg_crash_ack",
			desc = "Configuration file crash acknowledgement",
		},
	}

	local meta = self._api:default_meta()
	meta.name = "ThingsLink"
	meta.description = "ThingsLink IOE Device"
	meta.series = "FreeIOE" -- TODO:
	--
	meta.platform = sysinfo.platform() or "unknown"
	meta.firmware = sysinfo.firmware_version()
	meta.version = sysinfo.version()
	meta.skynet = sysinfo.skynet_version()

	self._dev = self._api:add_device(id, meta, inputs, nil, cmds)
	self._dev:cov({ttl=60})

	if leds.cloud then
		leds.cloud:brightness(0)
	end

	-- detect ubus
	if lfs.attributes('/var/run/ubus.sock', 'mode') then
		local lsocket_loaded, lsocket = pcall(require, 'lsocket')
		if lsocket_loaded  then
			--- Ubus is depends on lsocket
			self._log:notice("Starts ubus service!!!")
			local ubus = snax.uniqueservice('ubus')
		else
			self._log:notice("Module lsocket is not found, ubus service will not be started!!!")
		end
	else
		self._log:notice("Unix socket for ubus not found, ubus service will not be started!!!")
		--local ubus = snax.uniqueservice('ubus', '172.30.11.230', 11000)
		--local ubus = snax.uniqueservice('ubus', '/tmp/ubus.sock')
	end

	return true
end

function app:close(reason)
	--print(self._name, reason)
	for name, cancel_timer in pairs(self._cancel_timers) do
		cancel_timer()
	end
	self._cancel_timers = {}
end

function app:cfg_crash_check()
	if 'file' == lfs.attributes("cfg.json.crash", 'mode') then
		local err = "System configuration file error found!"
		self._log:error(err)

		local report_crash = nil
		report_crash = function()
			self._log:debug("Fire cfg crash event")
			local sys_id = self._sys:id()
			self._dev:fire_event(event.LEVEL_FATAL, event.EVENT_SYS, err, {sn=sys_id})
			-- Reset timer
			self._cancel_timers['cfg_crash'] = self._sys:cancelable_timeout(60 * 60 * 1000, report_crash)
		end
		report_crash()
	end
end

function app:cfg_crash_ack()
	os.execute("rm cfg.json.crash")
	if self._cancel_timers.cfg_crash then
		self._cancel_timers.cfg_crash()
		self._cancel_timers.cfg_crash = nil
	end
	return true
end

function app:first_run()
	self._start_time = self._sys:start_time()
	local v, gv = sysinfo.version()
	self._log:notice("System Version:", v, gv)
	local sv, sgv = sysinfo.skynet_version()
	self._log:notice("Skynet Platform Version:", sv, sgv)
	local plat = sysinfo.platform() or "unknown"
	self._version = v
	--self._git_version = gv
	self._skynet_version = sv
	--self._skynet_git_version = sgv
	self._plat = plat

	self._firmware_version = sysinfo.firmware_version()

	--- Calculate uptime/mem stuff/tmp_disk for earch 60 seconds
	local calc_tmp_disk = nil
	local tmp_disk_frep = self._conf.tmp_disk_frep or (1000 * 60)
	calc_tmp_disk = function()
		-- Reset timer
		self._cancel_timers['tmp_disk'] = self._sys:cancelable_timeout(tmp_disk_frep, calc_tmp_disk)

		--- System uptime
		local uptime = sysinfo.uptime()
		self._dev:set_input_prop('uptime', "value", math.floor(uptime))
		--- System memory usage
		local mem = sysinfo.meminfo()
		self._dev:set_input_prop('mem_total', 'value', tonumber(mem.total))
		self._dev:set_input_prop('mem_used', 'value', tonumber(mem.used))
		--self._dev:set_input_prop('mem_free', 'value', tonumber(mem.free))

		-- temp disk usage
		local r, err = disk.df('/tmp')
		if r then
			--self._dev:set_input_prop('disk_tmp_used', 'value', r.used_percent)

			if self._tmp_event_fired then
				if os.time() - self._tmp_event_fired > 3600 then
					self._tmp_event_fired = nil
				end
			end
			-- Check used percent limitation
			if not self._tmp_event_fired and r.used_percent > 98 then
				local info = "/tmp disk is nearly full!!!"
				self._log:error(info)
				self._dev:fire_event(event.LEVEL_ERROR, event.EVENT_SYS, info, r)
				self._tmp_event_fired = os.time()
			end
		end
	end
	calc_tmp_disk()

	if self._gcom then
		self:read_wan_sr()
		local calc_gcom = nil
		local gcom_frep = self._conf.gcom_frep or (1000 * 60)
		calc_gcom = function()
			-- Reset timer
			self._cancel_timers['gcom'] = self._sys:cancelable_timeout(gcom_frep, calc_gcom)

			local ccid, err = gcom.get_ccid()
			if ccid then
				self._dev:set_input_prop('ccid', "value", ccid)
			end
			local csq, err = gcom.get_csq()
			if csq then
				self._dev:set_input_prop('csq', "value", tonumber(csq))
				self:lte_strength(csq)
			end
			local cpsi, err = gcom.get_cpsi()
			if cpsi then
				self._dev:set_input_prop('cpsi', "value", cpsi)
			end

			self._dev:set_input_prop('wan_r', "value", self._wan_sum:get('recv'))
			self._dev:set_input_prop('wan_s', "value", self._wan_sum:get('send'))
		end
		calc_gcom()
	end

	self._sys:timeout(100, function()
		self._log:debug("Fire system started event")
		local sys_id = self._sys:id()
		self._dev:fire_event(event.LEVEL_INFO, event.EVENT_SYS, "System Started!", {sn=sys_id})
	end)

	self._sys:timeout(100, function()
		self:cfg_crash_check()
	end)

	local check_cloud = function()
		self:check_cloud_status()
		-- Reset timer
		self._cancel_timers['cloud_led'] = self._sys:cancelable_timeout(1000, check_cloud)
	end
	check_cloud()
end

function app:check_time_diff()
	if math.abs(os.time() - self._sys:time()) > 1.49 then
		self._log:error("Time diff found, system will be rebooted in five seconds. ", os.time(), self._sys:time())
		self._dev:fire_event(event.LEVEL_FATAL, event.EVENT_SYS, "Time diff found!", {os_time = os.time(), time=self._sys:time()}, os.time())
		self._sys:timeout(500, function()
			self._sys:abort()
		end)
	else
		--print(os.time() - self._sys:time())
	end
end

--- For wan statistics
function app:read_wan_sr()
	if self._gcom then
		local info, err = netinfo.proc_net_dev('3g-wan')
		if info and #info == 16 then
			self._wan_sum:set('recv', math.floor(info[1] / 1000))
			self._wan_sum:set('send', math.floor(info[9] / 1000))
		end
	end
end

function app:check_symlink()
	if lfs.attributes("/etc/rc.d/S22symlink", 'mode') then
		return true
	end
	return false
end

--- For cloud led
function app:check_cloud_status()
	if self:check_symlink() then
		return
	end

	-- Cloud LED
	if leds.cloud then
		local cloud = snax.uniqueservice('cloud')
		local cloud_status, cloud_status_last = cloud.req.get_status()
		if cloud_status then
			leds.cloud:brightness(1)
		else
			leds.cloud:brightness(0)
		end
	end
end

--- For signal strength
function app:lte_strength(csq)
	if self:check_symlink() then
		return
	end

	if leds.bs then
		leds.bs:brightness( (csq > 0 and csq < 18) and 1 or 0)
	end
	if leds.gs then
		leds.gs:brightness( (csq >= 18 and csq < 32) and 1 or 0)
	end
end

function app:run(tms)
	if not self._start_time then
		self:first_run()
	end
	self:check_time_diff()
	self:read_wan_sr()

	self._dev:set_input_prop('starttime', "value", self._start_time)
	self._dev:set_input_prop('version', "value", self._version)
	--self._dev:set_input_prop('version', "git_version", self._git_version)
	self._dev:set_input_prop('skynet_version', "value", self._skynet_version)
	--self._dev:set_input_prop('skynet_version', "git_version", self._skynet_git_version)
	self._dev:set_input_prop('platform', "value", self._plat)
	--- System Firmware Version
	self._dev:set_input_prop('firmware_version', "value", self._firmware_version or "UNKNOWN")

	--- CPU load avg
	local loadavg = sysinfo.loadavg()
	self._dev:set_input_prop('cpuload', "value", tonumber(loadavg.lavg_15))

	--- CPU temperature
	local cpu_temp = self._cpu_temp and sysinfo.cpu_temperature() or nil
	if cpu_temp then
		self._dev:set_input_prop('cpu_temp', "value", tonumber(cpu_temp))
	else
		self._dev:set_input_prop('cpu_temp', "value", 0, nil, 1)
	end

	-- cloud flags
	--
	local enable_data_upload = datacenter.get("CLOUD", "DATA_UPLOAD")
	local data_upload_cov = datacenter.get("CLOUD", "COV") or true
	local data_upload_cov_ttl = datacenter.get("CLOUD", "COV_TTL") or 60
	local data_upload_period = datacenter.get("CLOUD", "DATA_UPLOAD_PERIOD") or (enable_data_upload and 1000 or 60 * 1000)
	local enable_stat_upload = datacenter.get("CLOUD", "STAT_UPLOAD")
	local enable_comm_upload = datacenter.get("CLOUD", "COMM_UPLOAD")
	local enable_log_upload = datacenter.get("CLOUD", "LOG_UPLOAD")
	local enable_event_upload = datacenter.get("CLOUD", "EVENT_UPLOAD")
	local enable_beta = ioe.beta()

	self._dev:set_input_prop('data_upload', 'value', enable_data_upload and 1 or 0)
	self._dev:set_input_prop('data_upload_cov', 'value', data_upload_cov and 1 or 0)
	self._dev:set_input_prop('data_upload_cov_ttl', 'value', math.floor(data_upload_cov_ttl))
	self._dev:set_input_prop('data_upload_period', 'value', math.floor(data_upload_period))
	self._dev:set_input_prop('stat_upload', 'value', enable_stat_upload  and 1 or 0)
	self._dev:set_input_prop('comm_upload', 'value', enable_comm_upload or 0)
	self._dev:set_input_prop('log_upload', 'value', enable_log_upload or 0)
	self._dev:set_input_prop('event_upload', 'value', enable_event_upload or 99)
	self._dev:set_input_prop('enable_beta', 'value', enable_beta and 1 or 0)

	-- Application run status
	local appmgr = snax.uniqueservice('appmgr')
	local applist = appmgr.req.list()
	applist['ioe'] = nil
	for k, v in pairs(applist) do
		if not self._apps_cache[k] then
			local app = datacenter.get("APPS", k) or {name='REMOVED', version=0, sn='REMOVED'}
			self._apps_cache[k] = {
				name = app.name,
				version = app.version,
				sn = app.sn,
				auto = app.auto
			}
			self._dev:add({{name = "app_run_"..k, desc = 'Application status for '..k, vt="int"}})
		end
		local run = 0
		if v.inst and (self._sys:time() - v.last < 10) then
			run = 1
		end
		self._dev:set_input_prop('app_run_'..k, 'value', run)
	end
	for k, v in pairs(self._apps_cache) do
		if not applist[k] then
			self._dev:set_input_prop('app_run_'..k, 'value', 0)
		end
	end

	--- fifteen seconds by default
	return self._conf.run_frep or 1000
end

function app:on_post_fire_event(msg, lvl, tp, data)
	assert(msg and lvl and tp and data)
	data.time = data.time or self._sys:time()
	self._dev:fire_event(lvl, tp, msg, data)
end

return app
