class_name GameFonts
extends RefCounted
## The game's two typefaces, bundled (assets/fonts, with their licences):
##   Courier Prime: the UI's own (project setting gui/theme/custom_font),
##     and its italic for the player's thoughts;
##   Special Elite: a worn typewriter, for titles (the title card, the main
##     menu, the endings, the death screen).
## The phone and the Windows 95 computer keep their own looks.

const BODY := "res://assets/fonts/CourierPrime-Regular.ttf"
const ITALIC := "res://assets/fonts/CourierPrime-Italic.ttf"
const TITLE := "res://assets/fonts/SpecialElite-Regular.ttf"


static func body() -> Font:
	return _load(BODY)


static func italic() -> Font:
	return _load(ITALIC)


static func title() -> Font:
	return _load(TITLE)


## Puts the title face on `control` (a Label or Button).
static func use_title(control: Control) -> void:
	var font := title()
	if font:
		control.add_theme_font_override("font", font)


static func _load(path: String) -> Font:
	return load(path) as Font if ResourceLoader.exists(path) else ThemeDB.fallback_font
