local class = require 'middleclass'
local mosq = require 'mosquitto'
local huawei_http = require 'huawei_http'
local cjson = require 'cjson.safe'

local categories = {
	"event",
	"data",
	"rawData",
	"alarm",
	"command",
	"reply",
	"response",
}
local mqtt_reconnect_timeout = 1000

local function huawei_timestamp(timestamp)
	return os.date("%Y%m%dT%H%M%SZ", math.floor(timestamp))
end

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("HUAWEI_IOT_CLOUD")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	--- 获取数据接口
	self._api = sys:data_api()
	--- 获取日志接口
	self._log = sys:logger()
	self._nodes = {}

	self._device_id = conf.device_id or "6bcfe38c-936b-4ffb-9913-54ef2232ba9a"
	self._secret = conf.secret or "2efe9e3c6d7ca4317c18"

	--- HTTP Configruation
	local host = conf.server or "117.78.47.188"
	local port = conf.port or "8943"
	local app_id = conf.app_id or "fxfB_JFz_rvuihHjxOj_kpWcgjQb"

	self._huawei_http = huawei_http:new(self._sys, host, port, app_id)

	self._close_connection = false
end

-- @param app: 应用实例对象
local function create_handler(app)
	local api = app._api
	local server = app._server
	local log = app._log
	local self = app
	return {
		--- 处理设备对象添加消息
		on_add_device = function(app, sn, props)
			return self:fire_devices(1000)
		end,
		--- 处理设备对象删除消息
		on_del_device = function(app, sn)
			return self:fire_devices(1000)
		end,
		--- 处理设备对象修改消息
		on_mod_device = function(app, sn, props)
			return self:fire_devices()
		end,
		--- 处理设备输入项数值变更消息
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			return self:handle_input(app, sn, input, prop, value, timestamp, quality)
		end,
		on_event = function(app, sn, level, data, timestamp)
			return self:handle_event(app, sn, level, data, timestamp)
		end,
		on_stat = function(app, sn, stat, prop, value, timestamp)
			return self:handle_stat(app, sn, stat, prop, value, timestamp)
		end,
	}
end

function app:start_reconnect()
	self._mqtt_client = nil
	self._sys:timeout(mqtt_reconnect_timeout, function() self:connect_proc() end)
	mqtt_reconnect_timeout = mqtt_reconnect_timeout * 2
	if mqtt_reconnect_timeout > 10 * 60 * 1000 then
		mqtt_reconnect_timeout = 1000
	end
end

function app:create_event_msg(app, sn, level, data, timestamp)
	return {
		header = {
			eventType = "event",
			from = "/devices/"..self._device_id.."/services/"..sn,
			to = "/event/v1.1.0/devices/"..self._device_id.."/services/"..sn,
			access_token = self._refresh_token,
			timestamp = huawei_timestamp(timestamp),
			eventTime = huawei_timestamp(timestamp),
		},
		body = {
			app = app,
			sn = sn,
			level = level,
			data = data,
			timestamp = timestamp
		},
	}
end

function app:create_data_msg(app, sn, input, prop, value, timestamp, quality)
	return {
		header = {
			method = "PUT",
			from = "/device/"..sn,
			to = "/data/v1.1.0/devices/"..sn.."/services/data",
			access_token = self._refresh_token,
			timestamp = huawei_timestamp(timestamp),
			eventTime = huawei_timestamp(timestamp),
		},
		body = {
			app = app,
			sn = sn,
			input = input,
			prop = prop,
			value = value,
			timestamp = timestamp,
			quality = quality
		}
	}
end

function app:handle_input(app, sn, input, prop, value, timestamp, quality)
	local msg = self:create_data_msg(app, sn, input, prop, value, timestamp, quality)
	if self._mqtt_client then
		self._mqtt_client:publish(".cloud.signaltrans.v2.categories.data", cjson.encode(msg), 1, false)
	end
end

function app:handle_event(app, sn, level, data, timestamp)
	local msg = self:create_event_msg("event", app, sn, level, data, timestamp)
	if self._mqtt_client then
		self._mqtt_client:publish(".cloud.signaltrans.v2.categories.event", cjson.encode(msg), 1, false)
	end
end

function app:handle_stat(app, sn, stat, prop, value, timestamp)
end

function app:fire_devices(timeout)
	local timeout = timeout or 100
	if self._fire_device_timer  then
		return
	end

	self._fire_device_timer = function()
		local devs = self._api:list_devices() or {}
		local r, err = self._huawei_http:sync_devices(devs)
		if not r then
			self._log:error("Sync device failed", err)
		else
			self._log:debug("Sync device return", cjson.encode(r))
		end
	end

	self._sys:timeout(timeout, function()
		if self._fire_device_timer then
			self._fire_device_timer()
			self._fire_device_timer = nil
		end
	end)
end

function app:connect_proc()
	local log = self._log
	local sys = self._sys

	local mqtt_id = self._mqtt_id
	local mqtt_host = self._mqtt_host
	local mqtt_port = self._mqtt_port
	local clean_session = self._clean_session or true
	local username = self._device_id
	local password = self._secret

	-- 创建MQTT客户端实例
	local client = assert(mosq.new(mqtt_id, clean_session))
	client:version_set(mosq.PROTOCOL_V311)
	client:login_set(username, password)
	client:tls_set(sys:app_dir().."/rootcert.pem")
	client:tls_opts_set(0)
	client:tls_insecure_set(1)

	-- 注册回调函数
	client.ON_CONNECT = function(success, rc, msg) 
		if success then
			log:notice("ON_CONNECT", success, rc, msg) 
			--client:publish(mqtt_id.."/status", "ONLINE", 1, true)
			self._mqtt_client = client
			self._mqtt_client_last = sys:time()
			for _, v in ipairs(categories) do
				client:subscribe("/gws/"..self._device_id.."/signaltrans/v2/categories/"..v, 1)
			end
			--client:subscribe("+/#", 1)
			--
			mqtt_reconnect_timeout = 1000
			self:fire_devices(1000)
		else
			log:warning("ON_CONNECT", success, rc, msg) 
			self:start_reconnect()
		end
	end
	client.ON_DISCONNECT = function(success, rc, msg) 
		log:warning("ON_DISCONNECT", success, rc, msg) 
		if self._mqtt_client then
			self:start_reconnect()
		end
	end
	client.ON_LOG = function(...)
		--print(...)
	end
	client.ON_MESSAGE = function(...)
		print(...)
	end

	--client:will_set(self._mqtt_id.."/status", "OFFLINE", 1, true)

	self._close_connection = false
	local r, err
	local ts = 1
	while not r do
		r, err = client:connect(mqtt_host, mqtt_port, mqtt_keepalive)
		if not r then
			log:error(string.format("Connect to broker %s:%d failed!", mqtt_host, mqtt_port), err)
			sys:sleep(ts * 500)
			ts = ts * 2
			if ts >= 64 then
				client:destroy()
				sys:timeout(100, function() self:connect_proc() end)
				-- We meet bug that if client reconnect to broker with lots of failures, it's socket will be broken. 
				-- So we will re-create the client
				return
			end
		end
	end

	self._mqtt_client = client

	--- Worker thread
	while self._mqtt_client and not self._close_connection do
		sys:sleep(0)
		if self._mqtt_client then
			self._mqtt_client:loop(50, 1)
		else
			sys:sleep(50)
		end
	end
	if self._close_connection then
		self._mqtt_client = nil
	end
	if client then
		client:disconnect()
		log:notice("Cloud Connection Closed!")
		client:destroy()
	end
end

function app:disconnect()
	if not self._mqtt_client then
		return
	end

	self._log:debug("Cloud Connection Closing!")
	self._close_connection = true
	while self._mqtt_client do
		self._sys:sleep(10)
	end
	return true
end

function app:huawei_http_login()
	self:disconnect()
	local r, err = self._huawei_http:login(self._device_id, self._secret)
	if r then
		if r and r.refreshToken then
			self._retry_login = 100

			self._log:notice("HuaWei login done!", cjson.encode(r))
			self._huawei_http:set_access_token(r.accessToken)
			self._mqtt_id = r.mqttClientId
			self._mqtt_host = r.addrHAServer
			self._mqtt_port = 8883
			self._refresh_token = r.refreshToken
			self._refresh_token_timeout = os.time() + (r.timeout or 43199)

			self._sys:timeout(10, function() self:connect_proc() end)
			return
		end
	end

	self._refresh_token = nil
	self._refresh_token_timeout = nil
	self._log:error("Refresh token failed!", r, err)

	-- Retry login
	if not self._retry_login or self._retry_login > 1000 * 128 then
		self._retry_login = 100
	end
	self._sys:timeout(self._retry_login, function() self:huawei_http_login() end)
	self._retry_login = self._retry_login * 2
end

function app:huawei_http_refresh_token()
	local r, err = self._huawei_http:refresh_token(self._refresh_token)
	if r then
		if r and r.refreshToken then
			self._log:notice("Refresh token done!", cjson.encode(r))
			self._huawei_http:set_access_token(r.accessToken)
			self._refresh_token = r.refreshToken
			self._refresh_token_timeout = os.time() + (r.timeout or 43199)
			return
		end
	end
	-- TODO: disconnect mqtt
	self._refresh_token = nil
	self._refresh_token_timeout = nil
	self._log:error("Refresh token failed!", r, err)
	self._sys:timeout(10, function() self:huawei_http_login() end)
end

--- 应用启动函数
function app:start()
	--- 设定回调处理对象
	self._handler = create_handler(self)
	self._api:set_handler(self._handler, true)

	self._sys:fork(function()
		self:huawei_http_login()
	end)
	
	return true
end

--- 应用退出函数
function app:close(reason)
	mosq.cleanup()
end

--- 应用运行入口
function app:run(tms)
	if self._refresh_token_timeout and self._refresh_token_timeout - os.time() < 60  then
		self:huawei_http_refresh_token()
	end

	return 1000 * 10 -- 10 seconds
end

--- 返回应用对象
return app

