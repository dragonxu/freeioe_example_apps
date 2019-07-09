return {
	{
		name = "working_mode",
		desc = "工作模式",
		vt = "int",
		cmd = "state",
		decode_mode = 1,
	},
	{
		name = "working_frequency",
		desc = "工作频率",
		vt = "int",
		unit = "khz",
		rate = 0.001,
		cmd = "tf",
		rp = "trigfreq",
		decode_mode = 1,
	},		
	{
		name = "trigger_mode",
		desc = "触发模式",
		vt = "int",
		cmd = "trig",
		decode_mode = 1,
	},
	{
		name = "scaling_down_setting",
		desc = "分频设置",
		vt = "int",
		cmd = "eaom_div",
		rp = "eaomdiv",
		decode_mode = 1,
	},
	{
		name = "power_setting",
		desc = "功率设置",
		vt = "int",
		unit = "%",
		rate = 0.1,
		cmd  ="pf",
		rp = "powerfactor",
		decode_mode = 1,
    },
	{
		name = "report_errors",
		desc = "错误信息",
		vt = "string",
		cmd = "geterrors",
		decode_mode = 1,
	},
	{
		name = "report_warnings",
		desc = "警告信息",
		vt = "string",
		decode_mode = 1,
	},
-- 	{
-- 		name = "Command_Table",
-- 		desc = "显示激光器命令表",
-- 		vt = "string",
-- 		cmd = "display\n",
-- 		decode_mode = 0,
-- 	},
	{
		name = "run_status",
		desc = "运行状态",
		vt = "string",
		cmd = "k\n",
		decode_mode = 0,
	},
	{
		name = "soft_version",
		desc = "激光器软件版本号",
		vt = "string",
		cmd = "Copyright",
		decode_mode = 1,
	},
	{
		name = "on_time",
		desc = "State 2状态总时长",
		vt = "string",
		cmd = "ontime",
		decode_mode = 1,
	},
	{
		name = "sleep_time",
		desc = "State 1状态总时长",
		vt = "string",
		cmd = "sleeptime",
		decode_mode = 1,
	},
	{
		name = "standby_time",
		desc = "State 0状态总时长",
		vt = "string",
		cmd = "standbytime",
		decode_mode = 1,
	},
	{
		name = "poweron_time",
		desc = "激光器开机总时长",
		vt = "string",
		cmd = "powerontime",
		decode_mode = 1,
	},
	{
		name = "output_power",
		desc = "输出功率",
		vt = "float",
		decode_mode = 1,
	},
	{
		name = "pulse_energy",
		desc = "脉冲能量",
		vt = "float",
		decode_mode = 1,
	},
	{
		name = "burst",
		desc = "Burst Channel",
		vt = "int",
		decode_mode = 1,
	},
	{
		name = "rep_rate",
		desc = "Burst Channel",
		vt = "int",
		unit = 'Hz',
		decode_mode = 1,
	},
	{
		name = "C",
		desc = "C",
		vt = "int",
		decode_mode = 1,
	},
	{
		name = "D",
		desc = "D",
		vt = "int",
		decode_mode = 1,
	},
	{
		name = "A",
		desc = "A",
		vt = "int",
		decode_mode = 1,
	},
	{
		name = "S",
		desc = "S",
		vt = "int",
		decode_mode = 1,
	},
}

