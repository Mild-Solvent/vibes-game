extends RefCounted
## Builders for the read-only menu pages: Controls (every key), How to Play (illustrated pages)
## and Credits (CREDITS.md files, with a hardcoded summary for exported builds where .md is gone).

const T := preload("res://scripts/ui/theme.gd")
const Icon := preload("res://scripts/ui/icons.gd")

## [keys, what it does]; "/" in keys splits into separate key caps.
const CONTROLS := [
	["W A S D", "Move"],
	["Shift", "Sprint"],
	["Space", "Jump / swim up / brake in the car"],
	["E", "Grab, use, get in the car, lift the car, free a stuck friend"],
	["Q", "Throw what you hold / shove someone (empty hands)"],
	["F", "Taste what you hold / use"],
	["R / Wheel", "Turn the held item"],
	["H", "Medkit (on the friend you look at, else yourself)"],
	["T", "Flashlight / force-feed a friend (spam it)"],
	["G", "Use pocket item: flare, wine, duck, lottery ticket"],
	["B", "Whistle"],
	["V", "Walkie-talkie (hold to talk)"],
	["M", "Mute / unmute your mic"],
	["J", "Field journal (while holding the field guide)"],
	["Esc", "Pause menu (the game keeps running)"],
]

## [icon, heading, text]; two per page.
const HOW_TO := [
	["friends", "Four broke friends",
		"You all lost your jobs on the same Monday. Now you live in a junk camp in the forest. "
		+ "The forest is full of mushrooms. The village pays for the good ones."],
	["mystery", "Nobody knows the names",
		"Pick mushrooms with E and drop them in the basket. Their names are hidden: "
		+ "a red one with dots could be dinner, or it could be the last thing you eat."],
	["babka", "Babka Hela knows",
		"Drive the basket to the village and put the mushrooms on Babka Hela's counter. "
		+ "She names every one for the whole team and buys the good ones."],
	["taste", "Tasting is a gamble",
		"F tastes what you hold and tells you what it was... eventually. Effects kick in later: "
		+ "fine, tripping, passed out, or poisoned. Poisoned? Medkit (H), fast."],
	["fero", "Uncle Fero wants his money",
		"Every 3 days Uncle Fero comes to collect. Have the cash at the end of his day "
		+ "or it is game over. The amount only goes up."],
	["hag", "The hag hunts by sound",
		"She hears footsteps, shouting and your voice in the voice chat. If she catches you, "
		+ "hand her a mushroom. No mushroom? No you."],
	["wolf", "Nights are for wolves",
		"After dark the wolves come out. Stay together, stay near the light, and do not "
		+ "wander off for one more porcini."],
	["flashlight", "Share the batteries",
		"T is your flashlight. All flashlights eat from one shared battery stash, "
		+ "so the one who leaves it on all night is not popular."],
	["police", "Don't get lost",
		"If a friend is missing for too long, somebody calls the police. "
		+ "That costs money and dignity. Use the walkie (V) and find them."],
	["witch", "The witch cures the sick",
		"Bring her the patient and the ingredient from a scary place: the sanatorium, the mine, "
		+ "the crypt or the lake island. She can even bring the dead back."],
]

const CREDIT_FILES := ["res://CREDITS.md", "res://assets/sfx/CREDITS-sfx.md"]
const CREDITS_SUMMARY := """[b]Mushroom Foraging[/b]
Made by the vibes-game crew.

[b]Art[/b]
Kenney (kenney.nl) - nature, car, survival, city, town, arcade, graveyard and character kits (CC0)
Quaternius (quaternius.com) - low-poly models (CC0 / CC-BY)
Polygonal Mind - low-poly models (CC0)
Aya Kawa - models (CC-BY)

[b]Sound[/b]
Kenney - impact, RPG, interface and sci-fi sound packs (CC0)
Forest ambience, owls, wolves and the rest synthesised for this project (CC0)

[b]Engine[/b]
Godot Engine (godotengine.org) - MIT licence, (c) the Godot Engine contributors
"""


## Shown above the keyboard list on phones (the on-screen buttons have these labels).
const TOUCH_CONTROLS := [
	["Left thumb", "Move (a joystick appears where you touch)"],
	["Right side", "Drag to look around"],
	["JUMP", "Jump / swim up / brake in the car / hold to prise a bear trap"],
	["E", "Grab, use, get in the car; hold on a stuck friend to pull"],
	["Q", "Throw what you hold / shove someone"],
	["EAT", "Taste what you hold / use"],
	["LIGHT", "Flashlight / force-feed a friend (spam it)"],
	["RUN", "Sprint on / off"],
	["MIC", "Mute your voice"],
	["II", "Pause menu"],
	["Tap L / R", "Stuck in mud: tap the left and right halves in turn"],
]


static func controls() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 10)
	var entries: Array = (TOUCH_CONTROLS + CONTROLS) if OS.has_feature("mobile") else CONTROLS
	for entry in entries:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 6)
		caps.alignment = BoxContainer.ALIGNMENT_END
		caps.custom_minimum_size = Vector2(220, 0)
		var parts: PackedStringArray = entry[0].split(" / ")
		for i in parts.size():
			if i > 0:
				var or_label := Label.new()
				or_label.text = "or"
				or_label.theme_type_variation = "Small"
				caps.add_child(or_label)
			caps.add_child(keycap(parts[i]))
		grid.add_child(caps)
		var what := Label.new()
		what.text = entry[1]
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(what)
	return grid


static func keycap(text: String) -> Control:
	var cap := PanelContainer.new()
	cap.theme_type_variation = "KeyCap"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "KeyLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(22, 0)
	cap.add_child(l)
	return cap


## One page of the guide: two illustrated cards side by side.
static func how_to_page(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	for k in 2:
		var i := index * 2 + k
		if i >= HOW_TO.size():
			break
		row.add_child(_how_card(HOW_TO[i]))
	return row


static func how_to_pages() -> int:
	return ceili(HOW_TO.size() / 2.0)


static func _how_card(entry: Array) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var art := PanelContainer.new()
	art.theme_type_variation = "Inset"
	box.add_child(art)
	var icon := Icon.new(entry[0], 140.0)
	art.add_child(icon)
	var h := Label.new()
	h.text = entry[1]
	h.theme_type_variation = "Heading"
	h.add_theme_font_size_override("font_size", 26)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(h)
	var body := Label.new()
	body.text = entry[2]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.custom_minimum_size = Vector2(300, 0)
	body.add_theme_font_size_override("font_size", 19)
	box.add_child(body)
	return card


## BBCode for the credits page: the summary, then the credit files if they are readable.
static func credits_bbcode() -> String:
	var text := CREDITS_SUMMARY
	for path in CREDIT_FILES:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		text += "\n[color=#%s]────────────────────────[/color]\n" % T.WOOD_LIGHT.to_html(false)
		text += _markdown_to_bbcode(f.get_as_text())
	return text


static func _markdown_to_bbcode(md: String) -> String:
	var out := PackedStringArray()
	var link := RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	var bold := RegEx.create_from_string("\\*\\*([^*]+)\\*\\*")
	var code := RegEx.create_from_string("`([^`]+)`")
	var gold := T.GOLD.to_html(false)
	var dim := T.CREAM_DIM.to_html(false)
	for raw in md.split("\n"):
		var line := raw.strip_edges()
		line = line.replace("[", "[lb]") if not line.contains("](") else line
		line = link.sub(line, "$1", true)
		line = bold.sub(line, "[b]$1[/b]", true)
		line = code.sub(line, "[color=#%s]$1[/color]" % dim, true)
		if line.begins_with("#"):
			var title := line.lstrip("#").strip_edges()
			out.append("\n[b][color=#%s]%s[/color][/b]" % [gold, title])
		elif line.begins_with("|"):
			var cells := line.trim_prefix("|").trim_suffix("|").split("|")
			if cells.size() > 0 and cells[0].strip_edges().begins_with("---"):
				if out.size() > 0:
					out.remove_at(out.size() - 1)  # the row above was the table header
				continue
			var parts := PackedStringArray()
			for c in cells:
				parts.append(c.strip_edges())
			out.append("  • [b]%s[/b]  [color=#%s]%s[/color]" % [parts[0], dim, "  ·  ".join(parts.slice(1))])
		elif line.is_empty():
			out.append("")
		else:
			out.append(line)
	return "\n".join(out)
