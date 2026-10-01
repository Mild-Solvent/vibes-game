extends SubViewport
## A tiny 2D "TV channel" for the screens around the studio: other channels' shows, looping
## forever with tweens. Cheap (2D only, small). Use `texture()` on a monitor.

enum Kind { WEATHER, COOKING, TELESHOP, SPORTS, CARTOON }

const W := 320
const H := 180

var kind := Kind.WEATHER


## Call after adding to the tree (tweens need it).
func start(new_kind: Kind) -> void:
	kind = new_kind
	size = Vector2i(W, H)
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	match kind:
		Kind.WEATHER:
			_weather()
		Kind.COOKING:
			_cooking()
		Kind.TELESHOP:
			_teleshop()
		Kind.SPORTS:
			_sports()
		Kind.CARTOON:
			_cartoon()


func texture() -> ViewportTexture:
	return get_texture()


func _weather() -> void:
	_rect(Color(0.15, 0.35, 0.75), Rect2(0, 0, W, H))
	_rect(Color(0.3, 0.65, 0.3), Rect2(40, 30, 150, 110))
	_rect(Color(0.3, 0.65, 0.3), Rect2(170, 70, 90, 70))
	_text("CH 2  WEATHER", 14, Rect2(6, 4, 200, 20))
	var sun := _text("SUN", 22, Rect2(60, 50, 70, 30))
	sun.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
	var temp := _text("23°", 30, Rect2(200, 90, 80, 40))
	var tween := create_tween().set_loops()
	tween.tween_property(sun, "position:x", 190.0, 3.0)
	tween.tween_callback(func(): temp.text = "-4°")
	tween.tween_property(sun, "position:x", 60.0, 3.0)
	tween.tween_callback(func(): temp.text = "38°")


func _cooking() -> void:
	_rect(Color(0.85, 0.5, 0.2), Rect2(0, 0, W, H))
	_rect(Color(0.95, 0.9, 0.8), Rect2(0, 120, W, 60))
	_text("CH 3  COOKING WITH GRANDMA", 14, Rect2(6, 4, 300, 20))
	var pot := _rect(Color(0.25, 0.25, 0.28), Rect2(130, 80, 70, 45))
	var steam := _text("~ ~ ~", 22, Rect2(135, 45, 70, 30))
	var caption := _text("Step 1: potato", 18, Rect2(10, 140, 300, 30))
	var tween := create_tween().set_loops()
	tween.tween_property(steam, "position:y", 30.0, 1.0)
	tween.tween_property(steam, "position:y", 48.0, 1.0)
	tween.tween_callback(func(): caption.text = "Step 2: more potato")
	tween.tween_property(pot, "rotation", 0.15, 0.5)
	tween.tween_property(pot, "rotation", 0.0, 0.5)
	tween.tween_callback(func(): caption.text = "Step 3: it is on fire")


func _teleshop() -> void:
	_rect(Color(0.5, 0.1, 0.55), Rect2(0, 0, W, H))
	_text("CH 9  TELESHOP", 14, Rect2(6, 4, 200, 20))
	_text("THE POTATO 3000", 26, Rect2(10, 40, 300, 36))
	var price := _text("ONLY 99.99!", 30, Rect2(40, 90, 260, 40))
	price.add_theme_color_override("font_color", Color(1, 0.95, 0.2))
	var call := _text("CALL NOW  0800-POTATO", 16, Rect2(40, 140, 260, 24))
	var tween := create_tween().set_loops()
	tween.tween_property(price, "scale", Vector2(1.15, 1.15), 0.4)
	tween.tween_property(price, "scale", Vector2.ONE, 0.4)
	tween.tween_property(call, "modulate:a", 0.2, 0.3)
	tween.tween_property(call, "modulate:a", 1.0, 0.3)


func _sports() -> void:
	_rect(Color(0.85, 0.9, 0.95), Rect2(0, 0, W, H))
	_rect(Color(0.2, 0.3, 0.8), Rect2(0, 0, W, 26))
	_text("CH 5  CURLING: THE FINAL", 14, Rect2(6, 4, 300, 20))
	var stone := _rect(Color(0.8, 0.15, 0.15), Rect2(20, 95, 24, 24))
	_rect(Color(0.2, 0.3, 0.8), Rect2(250, 85, 44, 44))
	var score := _text("SVK 0 : 0 CAN", 18, Rect2(90, 145, 200, 24))
	var tween := create_tween().set_loops()
	tween.tween_property(stone, "position:x", 262.0, 6.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func(): score.text = "SVK 1 : 0 CAN  !!!")
	tween.tween_interval(1.5)
	tween.tween_callback(func():
		stone.position.x = 20.0
		score.text = "SVK 1 : 0 CAN")


func _cartoon() -> void:
	_rect(Color(0.4, 0.8, 0.95), Rect2(0, 0, W, H))
	_rect(Color(0.35, 0.75, 0.3), Rect2(0, 140, W, 40))
	_text("CH 7  CARTOONS", 14, Rect2(6, 4, 200, 20))
	var hero := _rect(Color(1, 0.6, 0.1), Rect2(40, 100, 40, 40))
	var tween := create_tween().set_loops()
	tween.tween_property(hero, "position", Vector2(140, 30), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(hero, "position", Vector2(240, 100), 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(hero, "position", Vector2(140, 30), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(hero, "position", Vector2(40, 100), 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _rect(color: Color, rect: Rect2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = rect.position
	r.size = rect.size
	r.pivot_offset = rect.size / 2.0
	add_child(r)
	return r


func _text(text: String, font_size: int, rect: Rect2) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 4)
	label.position = rect.position
	label.size = rect.size
	label.pivot_offset = rect.size / 2.0
	add_child(label)
	return label
