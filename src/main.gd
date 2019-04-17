extends Control

const USEC_PER_SEC = 1000000.0
const SEC_PER_MIN = 60
const MIN_PER_HOUR = 60
const HOUR_PER_DAY = 24
const SEC_PER_HOUR = SEC_PER_MIN * MIN_PER_HOUR
const SEC_PER_DAY = (SEC_PER_HOUR * HOUR_PER_DAY)
const NORMALIZED_SECOND = 1.0 / (SEC_PER_DAY)

enum SYS_CLK_MODE {MODE_AMPM, MODE_24HR, MODE_WORK, MODE_COUNT}

onready var time_now_raw = find_node("time_now_raw")
onready var time_now = find_node("time_now")
onready var ampm_label = find_node("ampm_label")
onready var clock_mode_buttons = find_node("clock_mode_buttons")
onready var schedule = find_node("schedule")
onready var new_time = find_node("new_time")
onready var seconds_factor = find_node("seconds_factor")

onready var wake_nodes = [find_node("wake_hour"), find_node("wake_minute"), find_node("wake_ampm")]
onready var work_nodes = [find_node("work_hour"), find_node("work_minute"), find_node("work_ampm")]
onready var free_nodes = [find_node("free_hour"), find_node("free_minute"), find_node("free_ampm")]
onready var sleep_nodes = [find_node("sleep_hour"), find_node("sleep_minute"), find_node("sleep_ampm")]


onready var new_hours_per_day = find_node("new_hours_per_day")
onready var new_minutes_per_hour = find_node("new_minutes_per_hour")
onready var new_seconds_per_minute = find_node("new_seconds_per_minute")

var clock_mode = SYS_CLK_MODE.MODE_24HR
var now = {"hour": 0, "minute": 0, "second": 0}
var now_sec = 0

var acc = 0
var usec_at_sec = 0
var prev_sec = 0

func _ready():
	now = OS.get_time()
	now_sec = time_to_sec(now)
	prev_sec = now.second
	usec_at_sec = OS.get_ticks_usec()
	
	for node_list in [wake_nodes, work_nodes, free_nodes, sleep_nodes]:
		node_list[0].get_line_edit().max_length = 2
		node_list[0].get_line_edit().expand_to_text_length = true
	
	for i in range(SYS_CLK_MODE.MODE_COUNT):
		clock_mode_buttons.get_child(i).connect("pressed", self, "set_clock_mode", [i])
	
	set_clock_mode(clock_mode)

func _process(delta):
	now = OS.get_time()
#	now = get_test_clock()
	now_sec = time_to_sec(now)
	
	if(now.second != prev_sec):
		usec_at_sec = OS.get_ticks_usec()
		prev_sec = now.second
	
	# Calculate and update time
	time_now_raw.text = "%02d:%02d:%02d" % [now.hour, now.minute, now.second]
	ampm_label.visible = false
	match(clock_mode):
		SYS_CLK_MODE.MODE_24HR:
			time_now.text = "%02d:%02d:%02d" % [now.hour, now.minute, now.second]
			
		SYS_CLK_MODE.MODE_AMPM:
			ampm_label.visible = true
			if now.hour >= 12:
				ampm_label.text = "PM"
			else:
				ampm_label.text = "AM"
			now.hour = (now.hour - 1) % 12 + 1
			time_now.text = "%02d:%02d:%02d" % [now.hour, now.minute, now.second]
			
		SYS_CLK_MODE.MODE_WORK:
			var home_wake_time = get_time_val(wake_nodes)
			var work_start_time = get_time_val(work_nodes)
			var work_stop_time = get_time_val(free_nodes)
			var home_sleep_time = get_time_val(sleep_nodes)
			if(now_sec < home_wake_time):
				time_now.text = "AM SLEEP"
			elif(now_sec < work_start_time):
				var prep_secs = now_sec - home_wake_time
				var pct = 100.0 * (float(prep_secs) / float(work_start_time - home_wake_time))
				var ipart = floor(pct)
				var rpart = int((pct - float(ipart)) * 100.0)
				time_now.text = "PREP " + ("%02d.%02d" % [ipart, rpart]) + "%"
			elif(now_sec < work_stop_time):
				var work_secs = now_sec - work_start_time
				var pct = 100.0 * (float(work_secs) / float(work_stop_time - work_start_time))
				var ipart = floor(pct)
				var rpart = int((pct - float(ipart)) * 100.0)
				time_now.text = "WORK " + ("%02d.%02d" % [ipart, rpart]) + "%"
			elif(now_sec < home_sleep_time):
				var post_work_secs = now_sec - work_stop_time
				var pct = 100.0 * (float(post_work_secs) / float(home_sleep_time - work_stop_time))
				var ipart = floor(pct)
				var rpart = int((pct - float(ipart)) * 100.0)
				time_now.text = "FREE " + ("%02d.%02d" % [ipart, rpart]) + "%"
			elif(now_sec < SEC_PER_DAY):
				time_now.text = "PM SLEEP"
			else:
				time_now.text = "Unknown State"
	
	calc_and_set_new_time()

func get_hpd():
	return new_hours_per_day.value

func get_mph():
	return new_minutes_per_hour.value

func get_spm():
	return new_seconds_per_minute.value

func calc_and_set_new_time():
	var usec = OS.get_ticks_usec()
	var day_normalized = (now_sec + (float(usec - usec_at_sec) / (1000000.0))) / float(SEC_PER_DAY)
	
#	print(day_normalized)
	var h = floor(day_normalized * get_hpd())
	var normalized_hour = 1.0 / get_hpd()
	var m = floor((day_normalized - (h * normalized_hour)) * get_mph() * get_hpd())
	var normalized_minute = 1.0 / (get_hpd() * get_mph())
	var rem_norm_time = (day_normalized - (h * normalized_hour) - (m * normalized_minute))
	var s = rem_norm_time * get_spm() * get_mph() * get_hpd()
	
	var new_normalized_second = 1.0 / (get_hpd() * get_mph() * get_spm())
	var new_second_factor = new_normalized_second / NORMALIZED_SECOND
	
	seconds_factor.text = "%.5f" % new_second_factor
	
	set_new_time(h, m, s)
	
func set_new_time(h, m, s):
	var h_fmt = "%0" + str(len(str(get_hpd() - 1))) + "d"
	var m_fmt = "%0" + str(len(str(get_mph() - 1))) + "d"
	var s_fmt = "%0" + str(len(str(get_spm() - 1))) + "d"
	var fmt = h_fmt + ":" + m_fmt + ":" + s_fmt
	new_time.text = fmt % [int(h), int(m), int(s)]

func get_test_clock():
	acc += 50
	acc = acc % SEC_PER_DAY
	var test_clock = {}
	test_clock.hour = acc / SEC_PER_HOUR
	test_clock.minute = (acc - (test_clock.hour * SEC_PER_HOUR)) / SEC_PER_MIN
	test_clock.second = (acc - (test_clock.hour * SEC_PER_HOUR) - (test_clock.minute * SEC_PER_MIN))
	return(test_clock)

func set_clock_mode(new_mode):
	clock_mode = new_mode
	for i in range(SYS_CLK_MODE.MODE_COUNT):
		clock_mode_buttons.get_child(i).pressed = false
	clock_mode_buttons.get_child(new_mode).pressed = true
	schedule.visible = (clock_mode == SYS_CLK_MODE.MODE_WORK)

func get_time_val(nodes):
	var h_node = nodes[0]
	var m_node = nodes[1]
	var ampm_node = nodes[2]
	var secs = (h_node.value * SEC_PER_HOUR) + (m_node.value * SEC_PER_MIN) + (ampm_node.selected * 12 * SEC_PER_HOUR)
	return(secs)

func time_to_sec(time):
	return(time.hour * SEC_PER_HOUR + time.minute * SEC_PER_MIN + time.second)

















