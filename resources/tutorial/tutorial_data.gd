extends Resource
class_name TutorialData

## TutorialData — A single just-in-time tutorial prompt.
##
## Create .tres files from this resource to configure tutorial prompts
## in the Inspector. Drag them into TutorialManager's `tutorials` array.
##
## Fields:
##   mechanic_id     — Unique identifier string (e.g. "notebook", "sprint").
##   prompt_text     — The text shown to the player (e.g. "Press [J] to open...").
##   trigger_moment  — When to auto-trigger: "enter_cabin", "first_dark", "first_item", etc.
##                     Leave empty for manual triggering only.
##   prerequisite    — mechanic_id that must be learned first (empty = none).
##   one_shot        — If true, never shows again after first display.
##   day_one_only    — If true, only shows during NightManager.current_night == 1.

## Unique identifier for this mechanic (e.g. "notebook", "interact", "sprint").
@export var mechanic_id: String = ""

## The prompt string shown to the player.
@export var prompt_text: String = ""

## Auto-trigger moment (optional). Matched by TutorialManager's trigger callbacks.
## Known values: "enter_cabin", "first_interactable", "first_dark", "first_entity", "first_item"
@export var trigger_moment: String = ""

## Optional: the player must have learned this mechanic_id before this prompt appears.
@export var prerequisite: String = ""

## If true, this prompt is hidden forever after being shown once.
@export var one_shot: bool = true

## If true, only shows during night 1 (checked against NightManager.current_night).
@export var day_one_only: bool = true