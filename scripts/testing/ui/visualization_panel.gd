class_name VisualizationPanel
extends Control
## Panel for displaying test result visualizations

signal tab_changed(tab_name: String)

var current_report: SessionReport
var current_tab: String = "overview"

# Tab buttons
var tab_container: HBoxContainer
var content_container: Control
var overview_panel: Control
var champions_panel: Control
var cards_panel: Control
var damage_panel: Control


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Main vertical layout
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Tab bar
	tab_container = HBoxContainer.new()
	tab_container.add_theme_constant_override("separation", 5)
	vbox.add_child(tab_container)

	_add_tab_button("overview", "Overview", true)
	_add_tab_button("champions", "Champions", false)
	_add_tab_button("cards", "Cards", false)
	_add_tab_button("damage", "Damage", false)

	# Spacer after tabs
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.add_child(spacer)

	# Content area
	content_container = Control.new()
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_container)

	# Create tab panels
	overview_panel = _create_overview_panel()
	champions_panel = _create_champions_panel()
	cards_panel = _create_cards_panel()
	damage_panel = _create_damage_panel()

	# Initially show overview
	_switch_tab("overview")


func _add_tab_button(tab_id: String, label: String, active: bool) -> void:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.button_pressed = active
	btn.custom_minimum_size = Vector2(100, 32)
	btn.name = "tab_" + tab_id
	btn.pressed.connect(_on_tab_pressed.bind(tab_id))

	if active:
		btn.add_theme_color_override("font_color", Color.WHITE)
	else:
		btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	tab_container.add_child(btn)


func _on_tab_pressed(tab_id: String) -> void:
	_switch_tab(tab_id)


func _switch_tab(tab_id: String) -> void:
	current_tab = tab_id

	# Update button states
	for child in tab_container.get_children():
		if child is Button and child.name.begins_with("tab_"):
			var btn_id := child.name.substr(4)  # Remove "tab_" prefix
			child.button_pressed = (btn_id == tab_id)
			if btn_id == tab_id:
				child.add_theme_color_override("font_color", Color.WHITE)
			else:
				child.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	# Show correct panel
	overview_panel.visible = (tab_id == "overview")
	champions_panel.visible = (tab_id == "champions")
	cards_panel.visible = (tab_id == "cards")
	damage_panel.visible = (tab_id == "damage")

	tab_changed.emit(tab_id)


func set_report(report: SessionReport) -> void:
	current_report = report
	_update_all_panels()


func _update_all_panels() -> void:
	if current_report == null:
		return

	_update_overview_panel()
	_update_champions_panel()
	_update_cards_panel()
	_update_damage_panel()


# ============== OVERVIEW PANEL ==============

func _create_overview_panel() -> Control:
	var panel := ScrollContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "overview_content"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	return panel


func _update_overview_panel() -> void:
	var vbox := overview_panel.get_node("overview_content") as VBoxContainer
	if not vbox:
		return

	# Clear existing content
	for child in vbox.get_children():
		child.queue_free()

	# Title
	var title := Label.new()
	title.text = "Test Session Overview"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)

	# Summary stats row
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 20)
	vbox.add_child(stats_row)

	_add_stat_card(stats_row, "Matches", str(current_report.matches_completed), Color(0.3, 0.7, 1.0))
	_add_stat_card(stats_row, "P1 Wins", "%d (%.0f%%)" % [current_report.player1_wins, current_report.p1_win_rate * 100], Color(0.3, 0.9, 0.3))
	_add_stat_card(stats_row, "P2 Wins", "%d (%.0f%%)" % [current_report.player2_wins, current_report.p2_win_rate * 100], Color(0.9, 0.3, 0.3))
	_add_stat_card(stats_row, "Draws", str(current_report.draws), Color(0.7, 0.7, 0.7))
	_add_stat_card(stats_row, "Avg Rounds", "%.1f" % current_report.avg_rounds_per_match, Color(1.0, 0.8, 0.3))

	# Win/Loss/Draw pie chart placeholder
	vbox.add_child(HSeparator.new())
	var pie_title := Label.new()
	pie_title.text = "Match Results Distribution"
	pie_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(pie_title)

	var pie_chart := PieChart.new()
	pie_chart.custom_minimum_size = Vector2(300, 200)
	pie_chart.set_data([
		{"label": "P1 Wins", "value": current_report.player1_wins, "color": Color(0.3, 0.9, 0.3)},
		{"label": "P2 Wins", "value": current_report.player2_wins, "color": Color(0.9, 0.3, 0.3)},
		{"label": "Draws", "value": current_report.draws, "color": Color(0.5, 0.5, 0.5)}
	])
	vbox.add_child(pie_chart)

	# No-op summary
	if not current_report.high_noop_cards.is_empty():
		vbox.add_child(HSeparator.new())
		var noop_title := Label.new()
		noop_title.text = "High No-Op Cards (cards that often do nothing)"
		noop_title.add_theme_font_size_override("font_size", 18)
		vbox.add_child(noop_title)

		var noop_chart := BarChart.new()
		noop_chart.custom_minimum_size = Vector2(0, 200)
		noop_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var noop_data: Array[Dictionary] = []
		for card: Dictionary in current_report.high_noop_cards.slice(0, 8):
			noop_data.append({
				"label": str(card.get("card_name", "?")).substr(0, 15),
				"value": card.get("noop_rate", 0) * 100,
				"color": Color(1.0, 0.5, 0.2)
			})
		noop_chart.set_data(noop_data, "No-Op Rate %")
		vbox.add_child(noop_chart)


func _add_stat_card(parent: Control, label: String, value: String, color: Color) -> void:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(lbl)

	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 22)
	val.add_theme_color_override("font_color", color)
	vbox.add_child(val)


# ============== CHAMPIONS PANEL ==============

func _create_champions_panel() -> Control:
	var panel := ScrollContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.visible = false
	content_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "champions_content"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	return panel


func _update_champions_panel() -> void:
	var vbox := champions_panel.get_node("champions_content") as VBoxContainer
	if not vbox:
		return

	for child in vbox.get_children():
		child.queue_free()

	# Title
	var title := Label.new()
	title.text = "Champion Win Rates"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)

	if current_report.win_rate_by_champion.is_empty():
		var no_data := Label.new()
		no_data.text = "No champion data available"
		no_data.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(no_data)
		return

	# Sort champions by win rate
	var champs: Array = current_report.win_rate_by_champion.keys()
	champs.sort_custom(func(a, b): return current_report.win_rate_by_champion[b] < current_report.win_rate_by_champion[a])

	# Create bar chart
	var chart := BarChart.new()
	chart.custom_minimum_size = Vector2(0, 400)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var data: Array[Dictionary] = []
	for champ: String in champs:
		var rate: float = current_report.win_rate_by_champion[champ]
		var color := Color(0.3, 0.9, 0.3) if rate > 0.52 else (Color(0.9, 0.3, 0.3) if rate < 0.48 else Color(0.7, 0.7, 0.7))
		data.append({
			"label": champ,
			"value": rate * 100,
			"color": color
		})

	chart.set_data(data, "Win Rate %", 100.0)
	vbox.add_child(chart)

	# Champion stats table
	vbox.add_child(HSeparator.new())
	var table_title := Label.new()
	table_title.text = "Champion Statistics"
	table_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(table_title)

	# Table header
	var header := _create_table_row(["Champion", "Picks", "Wins", "Losses", "Win Rate", "K/D"], true)
	vbox.add_child(header)

	for champ: String in champs:
		var stats: Dictionary = current_report.champion_statistics.get(champ, {})
		var row := _create_table_row([
			champ,
			str(stats.get("times_picked", 0)),
			str(stats.get("wins", 0)),
			str(stats.get("losses", 0)),
			"%.1f%%" % (stats.get("win_rate", 0.5) * 100),
			"%.2f" % stats.get("kd_ratio", 0.0)
		], false)
		vbox.add_child(row)


func _create_table_row(values: Array, is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var widths := [120, 60, 60, 60, 80, 60]

	for i in range(values.size()):
		var lbl := Label.new()
		lbl.text = str(values[i])
		lbl.custom_minimum_size.x = widths[i] if i < widths.size() else 80
		lbl.add_theme_font_size_override("font_size", 14 if is_header else 13)

		if is_header:
			lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		else:
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

		row.add_child(lbl)

	return row


# ============== CARDS PANEL ==============

func _create_cards_panel() -> Control:
	var panel := ScrollContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.visible = false
	content_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "cards_content"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	return panel


func _update_cards_panel() -> void:
	var vbox := cards_panel.get_node("cards_content") as VBoxContainer
	if not vbox:
		return

	for child in vbox.get_children():
		child.queue_free()

	# Title
	var title := Label.new()
	title.text = "Card Statistics"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)

	# Most played cards
	if not current_report.card_statistics.is_empty():
		var played_title := Label.new()
		played_title.text = "Most Played Cards"
		played_title.add_theme_font_size_override("font_size", 18)
		vbox.add_child(played_title)

		# Get sorted cards by times_played
		var cards: Array = current_report.card_statistics.keys()
		cards.sort_custom(func(a, b):
			var a_plays: int = current_report.card_statistics[a].get("times_played", 0)
			var b_plays: int = current_report.card_statistics[b].get("times_played", 0)
			return a_plays > b_plays
		)

		var chart := BarChart.new()
		chart.custom_minimum_size = Vector2(0, 250)
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var data: Array[Dictionary] = []
		for card: String in cards.slice(0, 10):
			var stats: Dictionary = current_report.card_statistics[card]
			data.append({
				"label": card.substr(0, 15),
				"value": stats.get("times_played", 0),
				"color": Color(0.3, 0.6, 1.0)
			})

		chart.set_data(data, "Times Played")
		vbox.add_child(chart)

	# High no-op cards
	if not current_report.high_noop_cards.is_empty():
		vbox.add_child(HSeparator.new())
		var noop_title := Label.new()
		noop_title.text = "High No-Op Cards (>20%)"
		noop_title.add_theme_font_size_override("font_size", 18)
		vbox.add_child(noop_title)

		# Table header
		var header := _create_table_row(["Card", "Played", "No-Op", "Rate", "Reason"], true)
		vbox.add_child(header)

		for card: Dictionary in current_report.high_noop_cards.slice(0, 15):
			var row := _create_table_row([
				str(card.get("card_name", "?")).substr(0, 18),
				str(card.get("times_played", 0)),
				str(card.get("noop_count", 0)),
				"%.0f%%" % (card.get("noop_rate", 0) * 100),
				str(card.get("common_reason", "")).substr(0, 20)
			], false)
			vbox.add_child(row)

	# Never played cards (if available)
	if not current_report.never_played_cards.is_empty():
		vbox.add_child(HSeparator.new())
		var never_title := Label.new()
		never_title.text = "Never Played Cards (drawn but not used)"
		never_title.add_theme_font_size_override("font_size", 18)
		never_title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		vbox.add_child(never_title)

		var header := _create_table_row(["Card", "Drawn", "Held", "Discarded"], true)
		vbox.add_child(header)

		for card: Dictionary in current_report.never_played_cards.slice(0, 10):
			var row := _create_table_row([
				str(card.get("card_name", "?")).substr(0, 18),
				str(card.get("times_drawn", 0)),
				str(card.get("times_held", 0)),
				str(card.get("times_discarded", 0))
			], false)
			vbox.add_child(row)

	# Low usage cards
	if not current_report.low_usage_cards.is_empty():
		vbox.add_child(HSeparator.new())
		var low_title := Label.new()
		low_title.text = "Low Usage Cards (<30% of draws played)"
		low_title.add_theme_font_size_override("font_size", 18)
		low_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		vbox.add_child(low_title)

		var header := _create_table_row(["Card", "Drawn", "Played", "Usage %"], true)
		vbox.add_child(header)

		for card: Dictionary in current_report.low_usage_cards.slice(0, 10):
			var row := _create_table_row([
				str(card.get("card_name", "?")).substr(0, 18),
				str(card.get("times_drawn", 0)),
				str(card.get("times_played", 0)),
				"%.0f%%" % (card.get("usage_rate", 0) * 100)
			], false)
			vbox.add_child(row)


# ============== DAMAGE PANEL ==============

func _create_damage_panel() -> Control:
	var panel := ScrollContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.visible = false
	content_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "damage_content"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	return panel


func _update_damage_panel() -> void:
	var vbox := damage_panel.get_node("damage_content") as VBoxContainer
	if not vbox:
		return

	for child in vbox.get_children():
		child.queue_free()

	# Title
	var title := Label.new()
	title.text = "Damage Statistics"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)

	if current_report.champion_statistics.is_empty():
		var no_data := Label.new()
		no_data.text = "No damage data available"
		no_data.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(no_data)
		return

	# Sort by damage dealt
	var champs: Array = current_report.champion_statistics.keys()
	champs.sort_custom(func(a, b):
		var a_dmg: int = current_report.champion_statistics[a].get("total_damage_dealt", 0)
		var b_dmg: int = current_report.champion_statistics[b].get("total_damage_dealt", 0)
		return a_dmg > b_dmg
	)

	# Damage dealt chart
	var dmg_title := Label.new()
	dmg_title.text = "Total Damage Dealt by Champion"
	dmg_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(dmg_title)

	var dmg_chart := BarChart.new()
	dmg_chart.custom_minimum_size = Vector2(0, 300)
	dmg_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var dmg_data: Array[Dictionary] = []
	for champ: String in champs:
		var stats: Dictionary = current_report.champion_statistics[champ]
		dmg_data.append({
			"label": champ,
			"value": stats.get("total_damage_dealt", 0),
			"color": Color(0.9, 0.3, 0.3)
		})

	dmg_chart.set_data(dmg_data, "Damage Dealt")
	vbox.add_child(dmg_chart)

	# Damage taken chart
	vbox.add_child(HSeparator.new())
	var taken_title := Label.new()
	taken_title.text = "Total Damage Taken by Champion"
	taken_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(taken_title)

	# Sort by damage taken
	champs.sort_custom(func(a, b):
		var a_dmg: int = current_report.champion_statistics[a].get("total_damage_taken", 0)
		var b_dmg: int = current_report.champion_statistics[b].get("total_damage_taken", 0)
		return a_dmg > b_dmg
	)

	var taken_chart := BarChart.new()
	taken_chart.custom_minimum_size = Vector2(0, 300)
	taken_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var taken_data: Array[Dictionary] = []
	for champ: String in champs:
		var stats: Dictionary = current_report.champion_statistics[champ]
		taken_data.append({
			"label": champ,
			"value": stats.get("total_damage_taken", 0),
			"color": Color(0.3, 0.3, 0.9)
		})

	taken_chart.set_data(taken_data, "Damage Taken")
	vbox.add_child(taken_chart)


# ============== CHART CLASSES ==============

class BarChart extends Control:
	var data: Array[Dictionary] = []
	var label_text: String = ""
	var max_value: float = 0.0

	func set_data(chart_data: Array[Dictionary], label: String = "", max_val: float = 0.0) -> void:
		data = []
		for d in chart_data:
			data.append(d)
		label_text = label
		max_value = max_val

		# Auto-calculate max if not provided
		if max_value <= 0:
			for item: Dictionary in data:
				max_value = maxf(max_value, float(item.get("value", 0)))
			max_value = max_value * 1.1  # Add 10% padding

		queue_redraw()

	func _draw() -> void:
		if data.is_empty():
			return

		var rect := get_rect()
		var left_margin := 120.0
		var right_margin := 20.0
		var top_margin := 30.0
		var bottom_margin := 10.0
		var bar_height := 25.0
		var bar_spacing := 5.0

		# Background
		draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.1, 0.1, 0.12))

		# Label
		if not label_text.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(left_margin, 20), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.6))

		var chart_width := rect.size.x - left_margin - right_margin
		var y := top_margin

		for item: Dictionary in data:
			var value: float = float(item.get("value", 0))
			var bar_width: float = (value / max_value) * chart_width if max_value > 0 else 0
			var color: Color = item.get("color", Color(0.3, 0.6, 1.0))
			var label: String = str(item.get("label", ""))

			# Label
			draw_string(ThemeDB.fallback_font, Vector2(5, y + bar_height * 0.7), label.substr(0, 14), HORIZONTAL_ALIGNMENT_LEFT, int(left_margin - 10), 12, Color(0.7, 0.7, 0.7))

			# Bar background
			draw_rect(Rect2(left_margin, y, chart_width, bar_height), Color(0.15, 0.15, 0.18))

			# Bar fill
			if bar_width > 0:
				draw_rect(Rect2(left_margin, y, bar_width, bar_height), color)

			# Value text
			var value_str: String
			if value == int(value):
				value_str = str(int(value))
			else:
				value_str = "%.1f" % value
			draw_string(ThemeDB.fallback_font, Vector2(left_margin + bar_width + 5, y + bar_height * 0.7), value_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8))

			y += bar_height + bar_spacing


class PieChart extends Control:
	var data: Array[Dictionary] = []

	func set_data(chart_data: Array[Dictionary]) -> void:
		data = []
		for d in chart_data:
			data.append(d)
		queue_redraw()

	func _draw() -> void:
		if data.is_empty():
			return

		var rect := get_rect()
		var center := Vector2(rect.size.x * 0.35, rect.size.y * 0.5)
		var radius := minf(rect.size.x * 0.25, rect.size.y * 0.4)

		# Calculate total
		var total := 0.0
		for item: Dictionary in data:
			total += float(item.get("value", 0))

		if total <= 0:
			draw_string(ThemeDB.fallback_font, Vector2(10, rect.size.y / 2), "No data", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.5))
			return

		# Draw slices
		var start_angle := -PI / 2
		for item: Dictionary in data:
			var value: float = float(item.get("value", 0))
			var sweep := (value / total) * TAU
			var color: Color = item.get("color", Color.WHITE)

			if sweep > 0.01:
				_draw_arc_filled(center, radius, start_angle, start_angle + sweep, color)

			start_angle += sweep

		# Legend
		var legend_x := rect.size.x * 0.65
		var legend_y := 20.0

		for item: Dictionary in data:
			var value: float = float(item.get("value", 0))
			var pct: float = (value / total) * 100.0 if total > 0 else 0.0
			var color: Color = item.get("color", Color.WHITE)
			var label: String = str(item.get("label", ""))

			draw_rect(Rect2(legend_x, legend_y, 15, 15), color)
			draw_string(ThemeDB.fallback_font, Vector2(legend_x + 20, legend_y + 12), "%s: %.0f%%" % [label, pct], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.7))
			legend_y += 25

	func _draw_arc_filled(center: Vector2, radius: float, start: float, end: float, color: Color) -> void:
		var points := PackedVector2Array()
		points.append(center)

		var steps := int(abs(end - start) / 0.1) + 2
		for i in range(steps + 1):
			var angle := start + (end - start) * float(i) / float(steps)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)

		if points.size() >= 3:
			draw_polygon(points, PackedColorArray([color]))
