extends Control

const COLS := 4
const MAX_PLOTS := 16
const START_PLOTS := 4

# base: 타일 번호(싹). 성장 단계는 base, base+2, base+4(수확)
var crops := [
	{"name": "당근", "base": 4, "unlock": 0, "seed": 2, "sell": 6, "time": 4.0},
	{"name": "순무", "base": 16, "unlock": 150, "seed": 12, "sell": 40, "time": 8.0},
	{"name": "옥수수", "base": 28, "unlock": 800, "seed": 60, "sell": 250, "time": 15.0},
	{"name": "토마토", "base": 40, "unlock": 4000, "seed": 300, "sell": 1400, "time": 25.0},
	{"name": "양배추", "base": 52, "unlock": 20000, "seed": 1500, "sell": 8000, "time": 40.0},
]

# kind: plot / farmer / speed / price / animal
var upgrades := [
	{"id": "plot", "name": "밭 넓히기", "desc": "밭 1칸 추가", "icon": 96, "base": 40.0, "mult": 1.5, "max": MAX_PLOTS - START_PLOTS},
	{"id": "farmer", "name": "농부 고용", "desc": "수확·재파종을 자동으로", "icon": 108, "base": 150.0, "mult": 1.6, "max": 20},
	{"id": "speed", "name": "비료", "desc": "성장 시간 -10%", "icon": 84, "base": 100.0, "mult": 2.0, "max": 10},
	{"id": "price", "name": "시장 단골", "desc": "판매가 +25%", "icon": 125, "base": 120.0, "mult": 2.2, "max": 10},
	{"id": "chicken", "name": "닭", "desc": "초당 +0.5코인", "icon": 122, "base": 60.0, "mult": 1.25, "max": 50, "income": 0.5},
	{"id": "sheep", "name": "양", "desc": "초당 +4코인", "icon": 120, "base": 500.0, "mult": 1.3, "max": 50, "income": 4.0},
	{"id": "cow", "name": "소", "desc": "초당 +30코인", "icon": 121, "base": 4000.0, "mult": 1.35, "max": 50, "income": 30.0},
]

var coins := 10.0
var levels := {}
var unlocked := [true, false, false, false, false]
var selected := 0

var plot_crop: Array = []
var plot_prog: Array = []
var plot_btns: Array = []
var plot_bars: Array = []

var farmer_acc := 0.0
var ui_acc := 0.0
var income_window: Array = []  # 최근 수입 기록 (초당 코인 계산용)
var earned_acc := 0.0
var rate_acc := 0.0
var rate_shown := 0.0

var coin_label: Label
var rate_label: Label
var crop_btns: Array = []
var upg_btns := {}
var tex_cache := {}


func _ready() -> void:
	for u in upgrades:
		levels[u.id] = 0
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR", "NanumGothic", "sans-serif"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	_build_ui()
	plot_crop.resize(MAX_PLOTS)
	plot_prog.resize(MAX_PLOTS)
	for i in MAX_PLOTS:
		plot_crop[i] = -1
		plot_prog[i] = 0.0
	_refresh()


func tex(i: int) -> Texture2D:
	if not tex_cache.has(i):
		tex_cache[i] = load("res://Tiles/tile_%04d.png" % i)
	return tex_cache[i]


func fmt(n: float) -> String:
	var s := str(int(floor(n)))
	var out := ""
	var cnt := 0
	for k in range(s.length() - 1, -1, -1):
		out = s[k] + out
		cnt += 1
		if cnt % 3 == 0 and k > 0:
			out = "," + out
	return out


func cost_of(u: Dictionary) -> float:
	return floor(u.base * pow(u.mult, levels[u.id]))


func plots_open() -> int:
	return START_PLOTS + levels["plot"]


func grow_time(c: int) -> float:
	return crops[c].time * pow(0.9, levels["speed"])


func sell_price(c: int) -> float:
	return crops[c].sell * (1.0 + 0.25 * levels["price"])


func income_per_sec() -> float:
	var t := 0.0
	for u in upgrades:
		if u.has("income"):
			t += u.income * levels[u.id]
	return t


func gain(n: float) -> void:
	coins += n
	earned_acc += n


# ---------- UI ----------
func _panel_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	sb.border_color = Color("5a3a22")
	sb.set_border_width_all(3)
	return sb


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("8cc063")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	# 왼쪽: 농장
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)

	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", _panel_style(Color("f4e1b5")))
	left.add_child(head)
	var hh := HBoxContainer.new()
	head.add_child(hh)
	var coin_icon := TextureRect.new()
	coin_icon.texture = tex(97)
	coin_icon.custom_minimum_size = Vector2(40, 40)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hh.add_child(coin_icon)
	coin_label = Label.new()
	coin_label.add_theme_font_size_override("font_size", 28)
	coin_label.add_theme_color_override("font_color", Color("4a2c14"))
	hh.add_child(coin_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(sp)
	rate_label = Label.new()
	rate_label.add_theme_color_override("font_color", Color("4a2c14"))
	hh.add_child(rate_label)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	left.add_child(seed_row)
	for i in crops.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.icon = tex(crops[i].base + 4)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 36)
		b.pressed.connect(_on_crop_pressed.bind(i))
		seed_row.add_child(b)
		crop_btns.append(b)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(center)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	center.add_child(grid)
	for i in MAX_PLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(104, 104)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 72)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(_on_plot_pressed.bind(i))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("a8703f")
		sb.set_corner_radius_all(8)
		sb.border_color = Color("5a3a22")
		sb.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", sb)
		var sh := sb.duplicate()
		sh.bg_color = Color("c18a52")
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		var sd := sb.duplicate()
		sd.bg_color = Color("6f7f5a")
		sd.border_color = Color("4d5a3f")
		b.add_theme_stylebox_override("disabled", sd)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.anchor_right = 1.0
		bar.offset_left = 8
		bar.offset_right = -8
		bar.offset_top = -14
		bar.offset_bottom = -6
		b.add_child(bar)
		grid.add_child(b)
		plot_btns.append(b)
		plot_bars.append(bar)

	var hint := Label.new()
	hint.text = "빈 밭을 누르면 씨를 뿌리고, 다 자란 작물을 누르면 수확해요."
	hint.add_theme_color_override("font_color", Color("2f4a1a"))
	left.add_child(hint)

	# 오른쪽: 업그레이드
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.add_theme_stylebox_override("panel", _panel_style(Color("f4e1b5")))
	root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	var title := Label.new()
	title.text = "농장 키우기"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("4a2c14"))
	rv.add_child(title)
	for u in upgrades:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 62)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = tex(u.icon)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 40)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_on_upgrade_pressed.bind(u.id))
		rv.add_child(b)
		upg_btns[u.id] = b


# ---------- 입력 ----------
func _on_crop_pressed(i: int) -> void:
	if not unlocked[i]:
		var c: float = crops[i].unlock
		if coins < c:
			return
		coins -= c
		unlocked[i] = true
	selected = i
	_refresh()


func _on_plot_pressed(i: int) -> void:
	if i >= plots_open():
		return
	if plot_crop[i] == -1:
		_plant(i, selected)
	elif plot_prog[i] >= 1.0:
		_harvest(i, true)
	_refresh()


func _on_upgrade_pressed(id: String) -> void:
	for u in upgrades:
		if u.id == id:
			if levels[id] >= u.max:
				return
			var c := cost_of(u)
			if coins < c:
				return
			coins -= c
			levels[id] += 1
	_refresh()


# ---------- 게임 로직 ----------
func _plant(i: int, c: int) -> bool:
	var seed_cost: float = crops[c].seed
	if coins < seed_cost:
		return false
	coins -= seed_cost
	plot_crop[i] = c
	plot_prog[i] = 0.0
	return true


func _harvest(i: int, popup: bool) -> void:
	var c: int = plot_crop[i]
	var v := sell_price(c)
	gain(v)
	plot_crop[i] = -1
	plot_prog[i] = 0.0
	if popup:
		_float_text(plot_btns[i], "+" + fmt(v))


func _float_text(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color("fff3b0"))
	l.add_theme_color_override("font_outline_color", Color("4a2c14"))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(24, 20)
	parent.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", -10.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(l.queue_free)


func _process(delta: float) -> void:
	for i in plots_open():
		if plot_crop[i] != -1 and plot_prog[i] < 1.0:
			plot_prog[i] = minf(1.0, plot_prog[i] + delta / grow_time(plot_crop[i]))

	gain(income_per_sec() * delta)

	var farmers: int = levels["farmer"]
	if farmers > 0:
		farmer_acc += delta * farmers
		while farmer_acc >= 1.0:
			farmer_acc -= 1.0
			_farmer_work()

	rate_acc += delta
	if rate_acc >= 1.0:
		rate_shown = earned_acc / rate_acc
		earned_acc = 0.0
		rate_acc = 0.0

	ui_acc += delta
	if ui_acc >= 0.1:
		ui_acc = 0.0
		_refresh()


func _farmer_work() -> void:
	for i in plots_open():
		if plot_crop[i] != -1 and plot_prog[i] >= 1.0:
			var c: int = plot_crop[i]
			_harvest(i, true)
			_plant(i, selected if coins >= crops[selected].seed else c)
			return
	for i in plots_open():
		if plot_crop[i] == -1:
			if _plant(i, selected):
				return


func _refresh() -> void:
	coin_label.text = " " + fmt(coins)
	rate_label.text = "초당 약 %s 코인" % fmt(rate_shown)

	for i in crops.size():
		var b: Button = crop_btns[i]
		if unlocked[i]:
			b.text = "%s\n씨앗 %s" % [crops[i].name, fmt(crops[i].seed)]
			b.modulate = Color.WHITE
			b.disabled = false
		else:
			b.text = "%s 해금\n%s" % [crops[i].name, fmt(crops[i].unlock)]
			b.modulate = Color(1, 1, 1, 1) if coins >= crops[i].unlock else Color(0.7, 0.7, 0.7, 1)
		if i == selected:
			b.text = "▶ " + b.text

	for i in MAX_PLOTS:
		var b: Button = plot_btns[i]
		var bar: ProgressBar = plot_bars[i]
		if i >= plots_open():
			b.disabled = true
			b.icon = null
			bar.visible = false
			continue
		b.disabled = false
		var c: int = plot_crop[i]
		if c == -1:
			b.icon = null
			bar.visible = false
		else:
			var p: float = plot_prog[i]
			var base: int = crops[c].base
			if p >= 1.0:
				b.icon = tex(base + 4)
			elif p >= 0.5:
				b.icon = tex(base + 2)
			else:
				b.icon = tex(base)
			bar.visible = p < 1.0
			bar.value = p

	for u in upgrades:
		var b: Button = upg_btns[u.id]
		var lv: int = levels[u.id]
		if lv >= u.max:
			b.text = "%s  Lv.%d (최대)\n%s" % [u.name, lv, u.desc]
			b.disabled = true
		else:
			b.text = "%s  Lv.%d  -  %s코인\n%s" % [u.name, lv, fmt(cost_of(u)), u.desc]
			b.disabled = coins < cost_of(u)
