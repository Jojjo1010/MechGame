extends RefCounted
class_name UITheme

# Single source of truth for the OW-inspired UI style. Reference all colors,
# fonts, and spacings from here so the visual language stays consistent.
#
# Reference frames pulled from Overwatch screenshots:
# - Hairline cyan borders (1.5–2 px, never thick fills)
# - Uppercase white headings with letter-spacing
# - Per-mech "team color" used as accent on that mech's UI
# - Cyan = interactive / hover, Yellow = selected / action

# ── Colors ───────────────────────────────────────────────────────────────────

const COLOR_DEEP        := Color("#04101a")    # darkest panel back
const COLOR_PANEL       := Color("#0a1c2a")    # panel fill
const COLOR_PANEL_ALPHA := Color(0.04, 0.10, 0.16, 0.86)   # over-world panel

const COLOR_ACCENT_CYAN   := Color("#2dd9ff")  # interactive / hover / "live" UI
const COLOR_ACCENT_YELLOW := Color("#ffce32")  # selected / action / "this is the answer"
const COLOR_ACCENT_RED    := Color("#ff4d5a")  # danger / repair urgency

const COLOR_BORDER_HAIR   := Color("#4a8aa0")  # 1.5 px hairline borders
const COLOR_BORDER_BRIGHT := Color("#7ec8e0")  # active hairline

const COLOR_TEXT_PRIMARY   := Color("#ffffff")
const COLOR_TEXT_SECONDARY := Color("#b0c4d4")
const COLOR_TEXT_MUTED     := Color("#5e7888")
const COLOR_TEXT_BLACK     := Color("#0a0a0a")  # for use on bright (yellow) chips

# ── Typography ───────────────────────────────────────────────────────────────

const FONT_HEADING_XL := 72   # screen-dominant titles ("ATTACK")
const FONT_HEADING_L  := 44   # subject titles ("TRACER", "LEVEL UP")
const FONT_HEADING_M  := 28   # section titles
const FONT_LABEL_CAPS := 20   # uppercase action labels ("ULTIMATE", "OFFENSE")
const FONT_BODY       := 18   # body text
const FONT_MICRO_CAPS := 13   # uppercase micro labels ("MATCH TIME")

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

const PAD_S := 6
const PAD_M := 12
const PAD_L := 22
const PAD_XL := 36

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

# Apply the OW heading style to a Label in one call.
static func style_heading(label: Label, font_size: int = FONT_HEADING_L,
		color: Color = COLOR_TEXT_PRIMARY) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color",         color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size",    OUTLINE_HEADING)
	label.text = label.text.to_upper()

# Apply the OW caps-label style — uppercase, tracked, hairline outline.
static func style_label_caps(label: Label, font_size: int = FONT_LABEL_CAPS,
		color: Color = COLOR_TEXT_PRIMARY) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color",         color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size",    OUTLINE_LABEL)
	label.text = label.text.to_upper()

# Apply the OW body text style — mixed case, soft outline.
static func style_body(label: Label, color: Color = COLOR_TEXT_SECONDARY) -> void:
	label.add_theme_font_size_override("font_size", FONT_BODY)
	label.add_theme_color_override("font_color",         color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size",    OUTLINE_BODY)
