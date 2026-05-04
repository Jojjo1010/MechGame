extends RefCounted
class_name KeyChip

# Static factory for keyboard key-cap chips. Both ControlsLegend (the persistent
# left-side legend) and TutorialPrompts (the HOW TO PLAY director) build their
# chips from here so the two stay visually identical.
#
# Each cap is a PanelContainer with a dark fill, white border, and a slightly
# thicker bottom edge to imply the key cap's beveled lip. The WASD cluster
# stacks W above an A/S/D row using a 3-column grid with two spacers.

const KEY_SIZE := 40.0   # square cap (W/A/S/D, Q, etc.)
const KEY_GAP  :=  4     # gap between caps in the WASD cluster
const SHIFT_W  := 80.0   # wide cap (SHIFT, LMB, etc.)
const SHIFT_H  := 40.0

static func make_key_cap(text: String, w: float, h: float, font_size: int) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cap.custom_minimum_size = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color            = UITheme.COLOR_PANEL_ALPHA
	sb.border_color        = UITheme.COLOR_TEXT_PRIMARY
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 4
	sb.set_corner_radius_all(4)
	cap.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text.to_upper()
	UITheme.style_label_caps(lbl, font_size, UITheme.COLOR_TEXT_PRIMARY)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	cap.add_child(lbl)
	return cap

# Two-row keyboard cluster: W centered above the A/S/D row.
static func make_wasd_cluster(font_size: int = UITheme.FONT_LABEL_CAPS) -> Control:
	return _make_dpad_cluster(["W", "A", "S", "D"], font_size)

# Same shape as the WASD cluster but with arrow glyphs — for surfaces that
# need to show the arrow-key alternative explicitly.
static func make_arrow_cluster(font_size: int = UITheme.FONT_LABEL_CAPS) -> Control:
	return _make_dpad_cluster(["↑", "←", "↓", "→"], font_size)

# Combined chip used wherever movement is taught (controls legend, tutorial
# prompt). Two clusters with a small "OR" between so the player sees both
# input options at once instead of having to hunt for it.
static func make_movement_cluster(font_size: int = UITheme.FONT_LABEL_CAPS) -> Control:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", KEY_GAP * 2)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(make_wasd_cluster(font_size))

	var sep := Label.new()
	sep.text = "OR"
	UITheme.style_label_caps(sep, UITheme.FONT_BODY, UITheme.COLOR_TEXT_SECONDARY)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(sep)

	hbox.add_child(make_arrow_cluster(font_size))

	# Same min-size pattern as the single cluster — give the chip-holder caller
	# (TutorialPrompts) a real width at insert time so it doesn't read 0.
	var cluster_w: float = 3.0 * KEY_SIZE + 2.0 * KEY_GAP
	hbox.custom_minimum_size = Vector2(2.0 * cluster_w + 64.0, 2.0 * KEY_SIZE + KEY_GAP)
	return hbox

# Internal helper — the WASD and arrow clusters share an identical 3-column
# d-pad layout (top centered, bottom row of three), so the only difference
# is the four glyph strings. Pass them top → left → down → right.
static func _make_dpad_cluster(glyphs: Array, font_size: int) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", KEY_GAP)
	grid.add_theme_constant_override("v_separation", KEY_GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Without an explicit minimum here, callers that read `custom_minimum_size`
	# at insert time (TutorialPrompts' chip holder) get 0 — the grid only
	# auto-sizes once it's been laid out, which is too late, and the chip
	# spills into the action icon / label downstream.
	grid.custom_minimum_size = Vector2(3.0 * KEY_SIZE + 2.0 * KEY_GAP, 2.0 * KEY_SIZE + KEY_GAP)
	grid.add_child(_make_spacer())
	grid.add_child(make_key_cap(String(glyphs[0]), KEY_SIZE, KEY_SIZE, font_size))
	grid.add_child(_make_spacer())
	grid.add_child(make_key_cap(String(glyphs[1]), KEY_SIZE, KEY_SIZE, font_size))
	grid.add_child(make_key_cap(String(glyphs[2]), KEY_SIZE, KEY_SIZE, font_size))
	grid.add_child(make_key_cap(String(glyphs[3]), KEY_SIZE, KEY_SIZE, font_size))
	return grid

static func _make_spacer() -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(KEY_SIZE, KEY_SIZE)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s
