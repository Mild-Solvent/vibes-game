extends Control
## Flat low-poly pictograms drawn in code (no image files): set `kind` and a minimum size.
## Everything is drawn in a 100x100 box scaled to fit the control, circles as 7-9 sided polygons.
## Kinds: mushroom, mystery, basket, friends, babka, taste, fero, hag, wolf, flashlight, police,
## witch, walkie, tick, wait, host.

const T := preload("res://scripts/ui/theme.gd")

const CAP_RED := Color("c3462c")
const STEM := Color("efe2c2")
const SKIN := Color("e8b48c")
const DARK := Color("1b140c")
const BROWN := Color("8a5a32")
const SCARF := Color("b8324a")
const MOON := Color("f2e6a8")
const GREY := Color("7d8a8f")
const GREEN := Color("6fa84a")

@export var kind := "mushroom":
	set(v):
		kind = v
		queue_redraw()

var _scale := 1.0
var _off := Vector2.ZERO


func _init(k := "mushroom", min_size := 96.0) -> void:
	kind = k
	custom_minimum_size = Vector2(min_size, min_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	_scale = s / 100.0
	_off = (size - Vector2(s, s)) * 0.5
	match kind:
		"mushroom": _mushroom(Vector2(50, 56), 1.0, CAP_RED, true)
		"mystery": _mystery()
		"basket": _basket()
		"friends": _friends()
		"babka": _babka()
		"taste": _taste()
		"fero": _fero()
		"hag": _hag()
		"wolf": _wolf()
		"flashlight": _flashlight()
		"police": _police()
		"witch": _witch()
		"walkie": _walkie()
		"tick": _tick()
		"wait": _wait()
		"host": _host()


# --- primitives (100x100 space) ----------------------------------------------------


func _v(x: float, y: float) -> Vector2:
	return _off + Vector2(x, y) * _scale


func _poly(points: Array, c: Color) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(_v(p.x, p.y))
	draw_colored_polygon(pts, c)


func _ngon(center: Vector2, r: float, c: Color, sides := 8, rot := 0.0) -> void:
	var pts := []
	for i in sides:
		var a := rot + TAU * i / sides
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	_poly(pts, c)


func _half(center: Vector2, rx: float, ry: float, c: Color, sides := 7) -> void:
	var pts := []
	for i in sides + 1:
		var a := PI + PI * i / sides
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	_poly(pts, c)


func _rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	_poly([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)], c)


func _line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	draw_line(_v(a.x, a.y), _v(b.x, b.y), c, w * _scale, true)


func _arc(center: Vector2, r: float, from: float, to: float, c: Color, w: float) -> void:
	draw_arc(_v(center.x, center.y), r * _scale, from, to, 10, c, w * _scale, true)


func _shadow(x: float, y: float, rx: float) -> void:
	var pts := []
	for i in 10:
		var a := TAU * i / 10.0
		pts.append(Vector2(x + cos(a) * rx, y + sin(a) * rx * 0.22))
	_poly(pts, Color(0, 0, 0, 0.3))


# --- pictograms --------------------------------------------------------------------


func _mushroom(at: Vector2, k: float, cap: Color, dots: bool) -> void:
	_shadow(at.x, at.y + 30 * k, 22 * k)
	_poly([at + Vector2(-9, -2) * k, at + Vector2(9, -2) * k, at + Vector2(12, 30) * k,
		at + Vector2(-12, 30) * k], STEM)
	_poly([at + Vector2(-9, -2) * k, at + Vector2(9, -2) * k, at + Vector2(9, 6) * k,
		at + Vector2(-9, 6) * k], STEM.darkened(0.15))
	_half(at + Vector2(0, 0), 32 * k, 30 * k, cap, 7)
	_half(at + Vector2(-6, -2) * k, 18 * k, 22 * k, cap.lightened(0.15), 5)
	if dots:
		_ngon(at + Vector2(-14, -12) * k, 4.5 * k, STEM, 6)
		_ngon(at + Vector2(4, -20) * k, 5.0 * k, STEM, 6)
		_ngon(at + Vector2(17, -9) * k, 3.8 * k, STEM, 6)


func _mystery() -> void:
	_mushroom(Vector2(50, 58), 1.0, BROWN, false)
	_ngon(Vector2(74, 22), 17, T.CREAM, 8)
	_arc(Vector2(74, 18), 6, PI, TAU + 0.6, T.INK, 4)
	_line(Vector2(76, 23), Vector2(74, 27), T.INK, 4)
	_ngon(Vector2(74, 32), 2.4, T.INK, 6)


func _basket() -> void:
	_shadow(50, 86, 36)
	_arc(Vector2(50, 50), 26, PI, TAU, T.WOOD_DARK, 7)
	_poly([Vector2(16, 48), Vector2(84, 48), Vector2(74, 86), Vector2(26, 86)], T.WOOD)
	for i in 4:
		var y := 56.0 + i * 8.0
		_line(Vector2(19 + i * 2.3, y), Vector2(81 - i * 2.3, y), T.WOOD_DARK, 2.5)
	_rect(14, 44, 72, 7, T.WOOD_LIGHT)
	_half(Vector2(38, 46), 11, 10, CAP_RED, 6)
	_half(Vector2(58, 45), 12, 12, BROWN, 6)


func _person(x: float, y: float, k: float, shirt: Color) -> void:
	_half(Vector2(x, y + 34 * k), 16 * k, 20 * k, shirt, 6)
	_ngon(Vector2(x, y), 11 * k, SKIN, 8, 0.2)
	_half(Vector2(x, y - 2 * k), 11 * k, 9 * k, DARK.lightened(0.15), 6)


func _friends() -> void:
	_shadow(50, 88, 44)
	_person(22, 44, 0.9, Color("e6194b"))
	_person(41, 38, 1.0, Color("3cb44b"))
	_person(60, 40, 1.0, Color("ffe119").darkened(0.15))
	_person(78, 46, 0.88, Color("4363d8"))
	_poly([Vector2(6, 86), Vector2(94, 86), Vector2(94, 96), Vector2(6, 96)], T.WOOD_DARK)


func _babka() -> void:
	_rect(4, 64, 92, 32, T.WOOD)
	_rect(4, 64, 92, 6, T.WOOD_LIGHT)
	_half(Vector2(38, 64), 22, 22, Color("5b6e8a"), 6)
	_ngon(Vector2(38, 32), 13, SKIN, 8)
	_poly([Vector2(22, 34), Vector2(26, 16), Vector2(38, 10), Vector2(50, 16), Vector2(54, 34),
		Vector2(48, 24), Vector2(28, 24)], SCARF)
	_poly([Vector2(30, 38), Vector2(46, 38), Vector2(42, 48), Vector2(34, 48)], SCARF.darkened(0.2))
	_half(Vector2(72, 64), 12, 12, CAP_RED, 6)
	_ngon(Vector2(72, 48), 7, T.GOLD, 7)
	_line(Vector2(72, 44), Vector2(72, 52), T.WOOD_DARK, 2)


func _taste() -> void:
	_mushroom(Vector2(40, 58), 0.9, Color("d98a2b"), false)
	_poly([Vector2(58, 34), Vector2(68, 40), Vector2(66, 54), Vector2(56, 50)], Color("2c3a24"))
	for i in 3:
		_arc(Vector2(76, 22), 6 + i * 6, 0.3 + i, 3.6 + i, [T.GOLD, Color("a86ad8"), GREEN][i], 3.5)


func _fero() -> void:
	_shadow(46, 92, 34)
	_half(Vector2(44, 92), 30, 36, Color("2b2b33"), 6)
	_poly([Vector2(38, 58), Vector2(50, 58), Vector2(44, 80)], T.CREAM)
	_ngon(Vector2(44, 38), 16, SKIN, 8)
	_rect(34, 44, 20, 4, DARK)
	_rect(22, 22, 44, 5, DARK)
	_poly([Vector2(30, 23), Vector2(58, 23), Vector2(54, 6), Vector2(34, 6)], DARK.lightened(0.1))
	_ngon(Vector2(78, 64), 15, T.GOLD, 8)
	_ngon(Vector2(78, 64), 10, T.GOLD.darkened(0.2), 8)
	_arc(Vector2(80, 64), 6, 0.9, TAU - 0.9, T.INK, 2.5)
	_line(Vector2(72, 62), Vector2(80, 62), T.INK, 2)
	_line(Vector2(72, 66), Vector2(80, 66), T.INK, 2)


func _hag() -> void:
	_poly([Vector2(16, 96), Vector2(30, 40), Vector2(56, 40), Vector2(70, 96)], Color("1a1a22"))
	_ngon(Vector2(43, 36), 11, Color("8ea07a"), 7)
	_ngon(Vector2(39, 35), 2.2, Color("f2d24a"), 5)
	_ngon(Vector2(48, 35), 2.2, Color("f2d24a"), 5)
	_poly([Vector2(20, 30), Vector2(66, 30), Vector2(52, 22), Vector2(46, 2), Vector2(36, 22)], Color("24242e"))
	for i in 3:
		_arc(Vector2(70, 40), 8 + i * 8, -0.7, 0.7, Color(T.CREAM, 0.9 - i * 0.25), 3.5)


func _wolf() -> void:
	_ngon(Vector2(74, 22), 15, MOON, 9)
	_poly([Vector2(22, 40), Vector2(30, 14), Vector2(40, 34), Vector2(60, 34), Vector2(70, 14), Vector2(78, 40),
		Vector2(74, 64), Vector2(50, 88), Vector2(26, 64)], GREY)
	_poly([Vector2(40, 60), Vector2(60, 60), Vector2(50, 88)], GREY.lightened(0.35))
	_poly([Vector2(32, 46), Vector2(44, 48), Vector2(36, 52)], Color("f2d24a"))
	_poly([Vector2(68, 46), Vector2(56, 48), Vector2(64, 52)], Color("f2d24a"))
	_ngon(Vector2(50, 82), 5, DARK, 6)


func _flashlight() -> void:
	_poly([Vector2(46, 40), Vector2(96, 14), Vector2(96, 86), Vector2(46, 60)], Color(MOON, 0.35))
	_rect(8, 42, 30, 16, Color("3a3f44"))
	_poly([Vector2(38, 38), Vector2(48, 34), Vector2(48, 66), Vector2(38, 62)], Color("5a6168"))
	_rect(14, 46, 6, 8, T.GOLD)
	_rect(22, 70, 22, 12, T.CREAM)
	_rect(44, 73, 3, 6, T.CREAM)
	_rect(24, 72, 10, 8, GREEN)


func _police() -> void:
	_shadow(50, 88, 42)
	_poly([Vector2(8, 82), Vector2(10, 62), Vector2(26, 58), Vector2(36, 42), Vector2(68, 42), Vector2(80, 58),
		Vector2(92, 62), Vector2(92, 82)], Color("e9edf0"))
	_rect(8, 66, 84, 6, Color("2f6bd0"))
	_poly([Vector2(40, 46), Vector2(64, 46), Vector2(72, 58), Vector2(34, 58)], Color("6a8aa8"))
	_ngon(Vector2(26, 84), 8, DARK, 8)
	_ngon(Vector2(74, 84), 8, DARK, 8)
	_rect(42, 34, 9, 8, Color("2f6bd0"))
	_rect(51, 34, 9, 8, CAP_RED)
	_poly([Vector2(46, 34), Vector2(30, 14), Vector2(40, 12)], Color(Color("5a8cff"), 0.5))
	_poly([Vector2(56, 34), Vector2(70, 12), Vector2(60, 12)], Color(CAP_RED, 0.5))


func _witch() -> void:
	_poly([Vector2(20, 30), Vector2(30, 22), Vector2(36, 34)], Color(GREEN, 0.7))
	_ngon(Vector2(44, 22), 6, Color(GREEN, 0.6), 7)
	_ngon(Vector2(62, 14), 4.5, Color(GREEN, 0.5), 7)
	_shadow(50, 90, 38)
	_poly([Vector2(16, 44), Vector2(84, 44), Vector2(80, 70), Vector2(66, 88), Vector2(34, 88), Vector2(20, 70)],
		Color("26262c"))
	_rect(12, 40, 76, 8, Color("3a3a44"))
	_poly([Vector2(20, 44), Vector2(80, 44), Vector2(74, 50), Vector2(26, 50)], GREEN)
	_poly([Vector2(26, 90), Vector2(34, 88), Vector2(30, 98)], Color("ff8a2b"))
	_poly([Vector2(44, 88), Vector2(56, 88), Vector2(50, 99)], Color("ffb02b"))
	_poly([Vector2(66, 88), Vector2(74, 90), Vector2(70, 98)], Color("ff8a2b"))


func _walkie() -> void:
	_line(Vector2(62, 30), Vector2(62, 6), Color("2b2b2b"), 5)
	_poly([Vector2(32, 28), Vector2(70, 28), Vector2(70, 92), Vector2(32, 92)], Color("e0a020"))
	_rect(38, 36, 26, 18, Color("33402a"))
	for i in 3:
		_rect(38, 62 + i * 8, 26, 3, Color("6b4a0a"))
	for i in 2:
		_arc(Vector2(70, 18), 10 + i * 9, -1.0, 0.2, T.CREAM, 3)


func _tick() -> void:
	_ngon(Vector2(50, 50), 44, T.FOREST_HOVER, 8, PI / 8)
	_line(Vector2(28, 52), Vector2(44, 68), T.CREAM, 11)
	_line(Vector2(42, 69), Vector2(74, 32), T.CREAM, 11)


func _wait() -> void:
	_ngon(Vector2(50, 50), 44, Color("4a4033"), 8, PI / 8)
	for i in 3:
		_ngon(Vector2(30 + i * 20, 52), 6, T.CREAM_DIM, 6)


func _host() -> void:
	_poly([Vector2(14, 78), Vector2(10, 30), Vector2(32, 52), Vector2(50, 18), Vector2(68, 52), Vector2(90, 30),
		Vector2(86, 78)], T.GOLD)
	_rect(14, 78, 72, 10, T.GOLD.darkened(0.25))
	_ngon(Vector2(50, 64), 6, CAP_RED, 6)
