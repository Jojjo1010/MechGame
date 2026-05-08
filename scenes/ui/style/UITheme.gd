extends RefCounted
class_name UITheme

# Single source of truth for the UI style. Reference all colors, fonts, and
# spacings from here so the visual language stays consistent.
#
# Inspired by Marathon's UI:
# - True-black backgrounds with hairline lime borders
# - Solid-color fills for selected state (lime panel + black text)
# - Lime = interactive / live UI, Hot pink = selected / action
# - Per-mech "team color" overrides the lime accent on that mech's UI

# ── Colors ───────────────────────────────────────────────────────────────────

const COLOR_DEEP        := Color("#0a0a0a")               # darkest panel back
const COLOR_PANEL       := Color("#101410")               # panel fill
const COLOR_PANEL_ALPHA := Color(0.04, 0.05, 0.04, 0.72)  # over-world panel — see-through enough that the world reads through

const COLOR_ACCENT_LIME := Color("#b0e632")  # interactive / hover / "live" UI
const COLOR_ACCENT_HOT  := Color("#ff2d6e")  # selected / action / "this is the answer"
const COLOR_ACCENT_WARN := Color("#ff5a3c")  # danger / repair urgency

const COLOR_BORDER_HAIR   := Color("#5a7a1a")  # 1.5 px hairline borders (dim lime)
const COLOR_BORDER_BRIGHT := Color("#c8ff58")  # active hairline (bright lime)

const COLOR_TEXT_PRIMARY   := Color("#ffffff")
const COLOR_TEXT_SECONDARY := Color("#a8b39c")
const COLOR_TEXT_MUTED     := Color("#5e6858")
const COLOR_TEXT_INVERSE   := Color("#0a0a0a")  # for use on bright (lime) fills

# ── Typography ───────────────────────────────────────────────────────────────
# Type scale also runs on the 8 px ladder, with 4 allowed as a half-step for
# the smallest "micro" tier where 8 px would be illegible.

const FONT_HEADING_XL := 72   # screen-dominant titles ("ATTACK")        — 9×8
const FONT_HEADING_L  := 48   # subject titles ("TRACER", "LEVEL UP")     — 6×8
const FONT_HEADING_M  := 32   # section titles                            — 4×8
const FONT_LABEL_CAPS := 24   # uppercase action labels ("ULTIMATE")      — 3×8
const FONT_BODY       := 16   # body text                                 — 2×8
const FONT_MICRO_CAPS := 12   # uppercase micro labels ("MATCH TIME")     — 1.5×8 (half-step)

# Letter-spacing constants (Godot uses per-character pixel offset in theme).
# Positive values widen; negative tightens.
const TRACK_HEADING := 4    # bold uppercase headings
const TRACK_LABEL   := 3    # caps labels
const TRACK_MICRO   := 4    # micro caps

# Outline width for headings/labels (gives the OW glow-on-dark look)
const OUTLINE_HEADING := 4
const OUTLINE_LABEL   := 3
const OUTLINE_BODY    := 2
const COLOR_OUTLINE   := Color(0.0, 0.0, 0.0, 0.85)

# ── Shapes ───────────────────────────────────────────────────────────────────

const HEX_BORDER_W      := 1.8
const PANEL_BORDER_W    := 2.0
const PANEL_CORNER_R    := 4
const HAIR_DIVIDER_H    := 1.5

# Card slant — degrees the parallelogram leans. ~12° matches OW reference.
const CARD_SLANT_DEG    := 12.0

# ── Spacing ──────────────────────────────────────────────────────────────────
# 8 px design system: every spacing token is a multiple of 8, with 4 as a
# half-step for fine-grained adjustments. Component sizes follow the same scale.

const PAD_S := 8
const PAD_M := 16
const PAD_L := 24
const PAD_XL := 32

# ── Helpers ──────────────────────────────────────────────────────────────────

# StyleBoxFlat with the OW panel treatment: dark fill + hairline cyan border.
# `accent` is the per-mech team color or null to use the default cyan hairline.
static func panel_stylebox(accent: Color = COLOR_BORDER_HAIR) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color                = COLOR_PANEL_ALPHA
	sb.border_color            = accent
	sb.border_width_left       = int(PANEL_BORDER_W)
	sb.border_width_right      = int(PANEL_BORDER_W)
	sb.border_width_top        = int(PANEL_BORDER_W)
	sb.border_width_bottom     = int(PANEL_BORDER_W)
	sb.set_corner_radius_all(PANEL_CORNER_R)
	sb.content_margin_left   = PAD_L
	sb.content_margin_right  = PAD_L
	sb.content_margin_top    = PAD_M
	sb.content_margin_bottom = PAD_M
	return sb

# Apply the heading style to a Label in one call. No text outline.
static func style_heading(label: Label, font_size: int = FONT_HEADING_L,
		color: Color = COLOR_TEXT_PRIMARY) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color",    color)
	label.add_theme_constant_override("outline_size", 0)
	label.text = label.text.to_upper()

# Apply the caps-label style — uppercase, tracked. No text outline.
static func style_label_caps(label: Label, font_size: int = FONT_LABEL_CAPS,
		color: Color = COLOR_TEXT_PRIMARY) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color",    color)
	label.add_theme_constant_override("outline_size", 0)
	label.text = label.text.to_upper()

# Apply the body text style — mixed case. No text outline.
static func style_body(label: Label, color: Color = COLOR_TEXT_SECONDARY) -> void:
	label.add_theme_font_size_override("font_size", FONT_BODY)
	label.add_theme_color_override("font_color",    color)
	label.add_theme_constant_override("outline_size", 0)

static func focus_outline_box(corner_radius: int = PANEL_CORNER_R) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = COLOR_BORDER_BRIGHT
	box.set_border_width_all(2)
	box.set_corner_radius_all(corner_radius)
	return box

# Primary button styling — solid hot-pink fill, no border, darker on hover.
# Uppercase white caps label. The caller owns sizing, pivot, and motion wiring.
static func apply_primary_button(btn: Button, label_text: String,
		corner_radius: int = PANEL_CORNER_R) -> void:
	btn.text = label_text.to_upper()
	btn.add_theme_font_size_override("font_size", FONT_LABEL_CAPS)
	btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	btn.add_theme_constant_override("outline_size", 0)
	btn.add_theme_stylebox_override("focus", focus_outline_box(corner_radius))

	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_ACCENT_HOT
	normal.set_border_width_all(0)
	normal.set_corner_radius_all(corner_radius)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = COLOR_ACCENT_HOT.lerp(COLOR_DEEP, 0.22)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = COLOR_ACCENT_HOT.lerp(COLOR_DEEP, 0.40)
	btn.add_theme_stylebox_override("pressed", pressed)
