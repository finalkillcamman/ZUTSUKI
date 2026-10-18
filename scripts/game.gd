extends Node3D

# ZUTSUKI! - single-script, importable Godot 4 prototype.
# All game settings can be changed live with F1, and saved to user://settings.cfg.
const TRACK_LENGTH := 480.0
const TRACK_HALF_WIDTH := 11.0
const GATE_Z := [-32.0, -65.0, -98.0, -131.0, -195.0, -225.0, -255.0, -285.0, -350.0, -380.0, -410.0, -440.0]
const DEFAULTS := {"speed": 12.0, "camera": 20.0, "daruma": 1, "leaves": 85, "glow": true}
var settings := DEFAULTS.duplicate()
var player: CharacterBody3D
var player_visual: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var gates: Array = []
var darumas: Array = []
var particles: Array = []
var distance_label: Label
var status_label: Label
var settings_panel: PanelContainer
var sliders := {}
var glow_check: CheckBox
var paused := false
var finished := false
var attack_time := 0.0
var dash_time := 0.0
var clock := 0.0
var terrain_mesh: MeshInstance3D
var status_timer := 0.0
var combo := 0
var combo_time := 0.0
var score := 0
var run_time := 0.0
var best_time := 0.0
var guards: Array = []
var shortcuts: Array = []
var trophy: Node3D
var stage_label: Label
var combo_label: Label
var win_panel: PanelContainer
var win_text: Label
var golden_kabuto: MeshInstance3D
var bonk_cooldown := 0.0

func _ready() -> void:
	load_settings()
	build_world()
	build_ui()
	restart()

func mat(color: Color, rough: float = 0.9, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.7
	return m

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.material_override = mat(color)
	n.position = pos
	parent.add_child(n)
	return n

func sphere(parent: Node3D, pos: Vector3, scale3: Vector3, color: Color, emissive: bool = false) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radial_segments = 24
	mesh.rings = 12
	n.mesh = mesh
	n.material_override = mat(color, 0.8, color * 0.5 if emissive else Color.BLACK)
	n.position = pos
	n.scale = scale3
	parent.add_child(n)
	return n

func build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("a7d8e5")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("d6d9e4")
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	# Sloping earth: elevation descends along negative Z.
	var ground := StaticBody3D.new()
	ground.name = "Mount Fuji Trail"
	add_child(ground)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(27, 1, 500)
	shape.shape = b
	shape.position = Vector3(0, -0.65, -236)
	ground.add_child(shape)
	box(ground, Vector3(0, -0.68, -236), Vector3(27, 1, 500), Color("77614c"))
	# Stone patches, grass clumps, trees and side railings.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2211
	for i in range(570):
		var z := rng.randf_range(-480, 5)
		var x := rng.randf_range(-10.5, 10.5)
		box(self, Vector3(x, -0.15, z), Vector3(rng.randf_range(0.2, 1.2), 0.04, rng.randf_range(0.2, 1.0)), Color("9b876b") if i % 3 else Color("60734b"))
	for side in [-1, 1]:
		for i in range(128):
			var z := 4.0 - i * 3.8
			var x := side * 12.5
			box(self, Vector3(x, 0.9, z), Vector3(0.25, 1.9, 0.25), Color("c1a35d"))
			box(self, Vector3(x, 1.35, z - 1.7), Vector3(0.15, 0.15, 3.6), Color("a98a4e"))
			if i % 3 == 0:
				box(self, Vector3(side * 15, 1.1, z), Vector3(0.45, 2.3, 0.45), Color("66543c"))
				sphere(self, Vector3(side * 15, 2.9, z), Vector3(1.8, 1.7, 1.8), Color("cf84aa"))
	# Player uses provided samurai artwork as a billboard in the 3D scene.
	player = CharacterBody3D.new()
	player.name = "Purple Samurai"
	player.position = Vector3(0, 0.8, 0)
	add_child(player)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.52
	capsule.height = 1.6
	collision.shape = capsule
	player.add_child(collision)
	player_visual = Node3D.new()
	player.add_child(player_visual)
	var sprite := Sprite3D.new()
	sprite.texture = load("res://assets/samurai.png")
	sprite.pixel_size = 0.002
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = false
	sprite.position.y = 0.75
	player_visual.add_child(sprite)
	cam = Camera3D.new()
	cam.current = true
	cam.fov = 60
	add_child(cam)
	# Four bamboo barriers with one correct gate per row.
	for idx in range(GATE_Z.size()):
		var wall := Node3D.new()
		wall.name = "Bamboo Gate %d" % (idx + 1)
		wall.position.z = GATE_Z[idx]
		add_child(wall)
		var doors: Array = []
		for lane in range(5):
			var x := (lane - 2) * 4.5
			var root := Node3D.new()
			root.position.x = x
			wall.add_child(root)
			for stick in range(8):
				box(root, Vector3(-1.9 + stick * 0.54, 1.25, 0), Vector3(0.44, 2.5, 0.4), Color("6a9a4a") if stick % 2 else Color("92bb65"))
			box(root, Vector3(0, 2.55, 0), Vector3(4.35, 0.22, 0.55), Color("c3a66b"))
			var marker := sphere(root, Vector3(0, 3.05, 0), Vector3(0.34, 0.34, 0.34), Color("73ff8b"), true)
			marker.visible = false
			doors.append({"root": root, "marker": marker})
			if idx < 4 and (lane == 0 or lane == 4):
				root.visible = false
		gates.append({"node": wall, "doors": doors, "correct": (idx % 3) + 1 if idx < 4 else (idx * 3 + 1) % 5, "broken": false, "lanes": 3 if idx < 4 else 5, "stage": mini(2, int(idx / 4))})
	# Finish line.
	box(self, Vector3(0, 0.04, -477), Vector3(22, 0.1, 1.5), Color("f5d266"))
	box(self, Vector3(-11, 2.0, -477), Vector3(0.5, 4, 0.5), Color("92354c"))
	box(self, Vector3(11, 2.0, -477), Vector3(0.5, 4, 0.5), Color("92354c"))
	box(self, Vector3(0, 4.0, -477), Vector3(22, 0.6, 0.5), Color("92354c"))
	# Three distinct course districts, all inside one continuous race.
	for i in range(32):
		var z2 := -165.0 - float(i) * 5.0
		box(self, Vector3(-11.2, 0.02, z2), Vector3(0.35, 0.12, 3.0), Color("e5b4c8"))
		box(self, Vector3(11.2, 0.02, z2), Vector3(0.35, 0.12, 3.0), Color("e5b4c8"))
	for i in range(32):
		var z3 := -324.0 - float(i) * 5.0
		box(self, Vector3(-11.2, 0.02, z3), Vector3(0.35, 0.12, 3.0), Color("8a6cbb"))
		box(self, Vector3(11.2, 0.02, z3), Vector3(0.35, 0.12, 3.0), Color("8a6cbb"))
	for z_guard in [-207.0, -268.0, -365.0, -422.0]:
		var guard := Node3D.new()
		guard.position = Vector3(0, 0, z_guard)
		add_child(guard)
		sphere(guard, Vector3(0, 2.25, 0), Vector3(1.2, 1.6, 0.85), Color("40385f"))
		sphere(guard, Vector3(0, 4.15, 0), Vector3(1.0, 1.0, 0.95), Color("f2bf8e"))
		box(guard, Vector3(0, 4.95, 0), Vector3(2.3, 0.45, 1.8), Color("c29b2d"))
		sphere(guard, Vector3(0, 3.0, -0.83), Vector3(0.42, 0.42, 0.25), Color("ff8b26"), true)
		guards.append({"node":guard, "z":z_guard, "defeated":false, "phase":float(guards.size()) * 1.7})
	# Purple, cracked side walls mark optional shortcut gates.
	for shortcut_z in [-239.0, -395.0]:
		var sc := Node3D.new()
		sc.position = Vector3(9.5, 0, shortcut_z)
		add_child(sc)
		box(sc, Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 0.8), Color("8052bb"))
		sphere(sc, Vector3(0, 2.7, -0.2), Vector3(0.42, 0.42, 0.22), Color("ffda69"), true)
		shortcuts.append({"node":sc, "broken":false, "skip":20.0})
	# Golden Kabuto reward at the castle finish.
	trophy = Node3D.new()
	trophy.position = Vector3(0, 1.2, -477)
	add_child(trophy)
	golden_kabuto = sphere(trophy, Vector3(0, 1.2, 0), Vector3(1.1, 0.8, 1.0), Color("ffd44c"), true)
	box(trophy, Vector3(0, 0.4, 0), Vector3(2.6, 0.25, 2.6), Color("7651a1"))


func make_daruma() -> Node3D:
	var root := Node3D.new()
	root.name = "Waradaruma - Laughing Boulder"
	add_child(root)
	var body := Node3D.new()
	body.name = "Wobbling body"
	root.add_child(body)
	sphere(body, Vector3.ZERO, Vector3(1.65, 1.9, 1.45), Color("a92424"))
	sphere(body, Vector3(0, 0.28, -1.24), Vector3(1.14, 1.06, 0.28), Color("f5dfb5"))
	for side in [-1, 1]:
		sphere(body, Vector3(side * 0.53, 0.66, -1.47), Vector3(0.28, 0.32, 0.15), Color("ff8a20"), true)
		sphere(body, Vector3(side * 0.53, 0.66, -1.6), Vector3(0.09, 0.13, 0.05), Color("171015"))
		box(body, Vector3(side * 0.52, 1.09, -1.45), Vector3(0.76, 0.18, 0.18), Color("201313")).rotation.z = side * 0.32
	var mouth := sphere(body, Vector3(0, -0.28, -1.49), Vector3(0.72, 0.43, 0.14), Color("230d16"))
	for i in range(7):
		box(body, Vector3(-0.48 + i * 0.16, -0.05, -1.64), Vector3(0.13, 0.13, 0.06), Color("fff0c9"))
	for i in range(16):
		var a := float(i) / 16.0 * TAU
		sphere(body, Vector3(sin(a) * 1.4, cos(a) * 1.6, 0.12), Vector3(0.22, 0.24, 0.23), Color("51483e"))
	root.set_meta("body", body)
	root.set_meta("mouth", mouth)
	return root

func build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var hud := VBoxContainer.new()
	hud.position = Vector2(20, 15)
	ui.add_child(hud)
	var title := Label.new()
	title.text = "ZUTSUKI!  |  BAMBOO DOWNHILL"
	title.add_theme_font_size_override("font_size", 26)
	hud.add_child(title)
	distance_label = Label.new()
	hud.add_child(distance_label)
	stage_label = Label.new()
	stage_label.add_theme_font_size_override("font_size", 21)
	hud.add_child(stage_label)
	combo_label = Label.new()
	combo_label.add_theme_font_size_override("font_size", 19)
	hud.add_child(combo_label)
	status_label = Label.new()
	status_label.text = "WASD / Arrows: Move  •  Space: Headbutt  •  Shift: Dash  •  F1: Settings  •  R: Restart"
	hud.add_child(status_label)
	settings_panel = PanelContainer.new()
	settings_panel.position = Vector2(25, 100)
	settings_panel.custom_minimum_size = Vector2(390, 0)
	ui.add_child(settings_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	settings_panel.add_child(vb)
	var heading := Label.new()
	heading.text = "DEVELOPER SETTINGS  [F1]"
	heading.add_theme_font_size_override("font_size", 22)
	vb.add_child(heading)
	add_slider(vb, "Samurai speed", "speed", 4, 30, 1)
	add_slider(vb, "Camera distance", "camera", 10, 40, 1)
	add_slider(vb, "Daruma count", "daruma", 0, 10, 1)
	add_slider(vb, "Bamboo explosion leaves", "leaves", 0, 200, 5)
	glow_check = CheckBox.new()
	glow_check.text = "Breakable door glow"
	glow_check.button_pressed = settings["glow"]
	glow_check.toggled.connect(func(value: bool): settings["glow"] = value; update_markers())
	vb.add_child(glow_check)
	var buttons := HBoxContainer.new()
	vb.add_child(buttons)
	var save := Button.new()
	save.text = "Save settings"
	save.pressed.connect(save_settings)
	buttons.add_child(save)
	var defaults := Button.new()
	defaults.text = "Restore defaults"
	defaults.pressed.connect(restore_defaults)
	buttons.add_child(defaults)
	var reset := Button.new()
	reset.text = "Restart run"
	reset.pressed.connect(restart)
	buttons.add_child(reset)
	var help := Label.new()
	help.text = "Live adjustments. Save to remember them next launch."
	vb.add_child(help)
	settings_panel.visible = false
	win_panel = PanelContainer.new()
	win_panel.position = Vector2(375, 165)
	win_panel.custom_minimum_size = Vector2(520, 210)
	ui.add_child(win_panel)
	var finish_box := VBoxContainer.new()
	win_panel.add_child(finish_box)
	win_text = Label.new()
	win_text.add_theme_font_size_override("font_size", 25)
	finish_box.add_child(win_text)
	var again := Button.new()
	again.text = "PLAY AGAIN  [R]"
	again.pressed.connect(restart)
	finish_box.add_child(again)
	win_panel.visible = false

func add_slider(parent: VBoxContainer, label_text: String, key: String, min_v: float, max_v: float, step_v: float) -> void:
	var label := Label.new()
	parent.add_child(label)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.value = settings[key]
	s.custom_minimum_size = Vector2(340, 25)
	parent.add_child(s)
	sliders[key] = {"slider": s, "label": label}
	s.value_changed.connect(func(value: float):
		settings[key] = int(value) if key in ["daruma", "leaves"] else value
		update_slider_label(key)
		if key == "daruma": refresh_darumas()
	)
	update_slider_label(key)

func update_slider_label(key: String) -> void:
	var entry: Dictionary = sliders[key]
	entry["label"].text = "%s: %s" % [{"speed":"Samurai speed", "camera":"Camera distance", "daruma":"Daruma count", "leaves":"Bamboo explosion leaves"}[key], str(settings[key])]

func update_markers() -> void:
	for gate in gates:
		for i in range(5):
			gate["doors"][i]["marker"].visible = settings["glow"] and not gate["broken"] and i == gate["correct"]

func restart() -> void:
	finished = false
	combo = 0
	combo_time = 0.0
	score = 0
	run_time = 0.0
	bonk_cooldown = 0.0
	if win_panel != null: win_panel.visible = false
	for guard in guards:
		guard["defeated"] = false
		guard["node"].visible = true
	for sc in shortcuts:
		sc["broken"] = false
		sc["node"].visible = true
	attack_time = 0
	dash_time = 0
	player.position = Vector3(0, 0.8, 0)
	for gate in gates:
		gate["broken"] = false
		for j in range(gate["doors"].size()):
			gate["doors"][j]["root"].visible = gate["lanes"] == 5 or (j > 0 and j < 4)
	update_markers()
	refresh_darumas()
	show_status("Find the glowing gate, then press SPACE to headbutt!", 4.0)

func refresh_darumas() -> void:
	for d in darumas:
		if is_instance_valid(d): d.queue_free()
	darumas.clear()
	for i in range(int(settings["daruma"])):
		var d := make_daruma()
		d.position = Vector3(-6.0 + (i % 4) * 3.8, 1.8, -10.0 - i * 15.0)
		d.set_meta("start_z", d.position.z)
		d.set_meta("index", i)
		darumas.append(d)

func show_status(msg: String, duration: float = 2.0) -> void:
	status_label.text = msg
	status_timer = duration

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			settings_panel.visible = not settings_panel.visible
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			restart()
		elif event.keycode == KEY_SPACE and not settings_panel.visible and not finished and bonk_cooldown <= 0:
			headbutt()
		elif event.keycode == KEY_SHIFT and not settings_panel.visible:
			dash_time = 0.35

func award_bonk(base_points: int) -> void:
	combo += 1
	combo_time = 4.0
	score += base_points * combo
	show_status("BONK COMBO x%d!  +%d" % [combo, base_points * combo], 2.0)

func headbutt() -> void:
	attack_time = 0.3
	bonk_cooldown = 0.33
	for sc in shortcuts:
		if sc["broken"]: continue
		if abs(player.position.z - sc["node"].position.z) < 4.0 and abs(player.position.x - sc["node"].position.x) < 3.0:
			sc["broken"] = true
			sc["node"].visible = false
			award_bonk(250)
			spawn_leaves(sc["node"].position + Vector3(0, 1.2, 0))
			player.position.z -= sc["skip"]
			show_status("SECRET SHORTCUT!  -20m  +250 x COMBO", 3.0)
			return
	for guard in guards:
		if guard["defeated"]: continue
		var n: Node3D = guard["node"]
		if player.position.distance_to(n.position) < 4.0:
			guard["defeated"] = true
			n.visible = false
			award_bonk(300)
			spawn_leaves(n.position + Vector3(0, 2.0, 0))
			show_status("GIANT GUARD BONKED!  Weak spot hit!", 2.0)
			return
	for gate in gates:
		if gate["broken"]: continue
		if abs(player.position.z - gate["node"].position.z) > 4.2: continue
		var lane := clampi(int(round(player.position.x / 4.5)) + 2, 0, 4)
		if lane == gate["correct"]:
			gate["broken"] = true
			gate["doors"][lane]["root"].visible = false
			spawn_leaves(Vector3((lane - 2) * 4.5, 1.6, gate["node"].position.z))
			award_bonk(100)
		else:
			player.position.z += 2.0
			combo = 0
			combo_time = 0.0
			show_status("WRONG DOOR! Watch for cracks and glowing clues.", 2.0)
		update_markers()
		return
	show_status("HEADBUTT!", 0.5)

func spawn_leaves(pos: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	for i in range(int(settings["leaves"])):
		var n := box(self, pos, Vector3(0.13, 0.035, 0.25), Color("81c958") if i % 2 else Color("b6df5e"))
		var velocity := Vector3(rng.randf_range(-7, 7), rng.randf_range(3, 10), rng.randf_range(-7, 7))
		particles.append({"node": n, "vel": velocity, "life": rng.randf_range(0.8, 2.0)})

func _process(delta: float) -> void:
	clock += delta
	if not finished and not settings_panel.visible: run_time += delta
	bonk_cooldown = maxf(0.0, bonk_cooldown - delta)
	if combo_time > 0:
		combo_time -= delta
		if combo_time <= 0: combo = 0
	if trophy != null: trophy.rotation.y += delta * 0.7
	for guard in guards:
		if not guard["defeated"]:
			var gnode: Node3D = guard["node"]
			gnode.position.x = sin(clock * 1.3 + guard["phase"]) * 6.5
			if not settings_panel.visible and not finished and player.position.distance_to(gnode.position) < 2.0:
				player.position.z += delta * 9.0
				combo = 0
				show_status("GUARD SMASH! BONK the glowing chest!", 0.4)
	if status_timer > 0:
		status_timer -= delta
		if status_timer <= 0:
			status_label.text = "WASD: Move  |  Space: Headbutt  |  Shift: Dash  |  F1: Settings  |  R: Restart"
	if attack_time > 0: attack_time -= delta
	if dash_time > 0: dash_time -= delta
	if not settings_panel.visible and not finished:
		var direction := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): direction.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): direction.y += 1
		if direction.length() > 1: direction = direction.normalized()
		var multiplier := 2.0 if dash_time > 0 else 1.0
		var motion := Vector3(direction.x, 0, direction.y) * float(settings["speed"]) * multiplier * delta
		var candidate := player.position + motion
		candidate.x = clampf(candidate.x, -9.7, 9.7)
		candidate.z = clampf(candidate.z, -479, 2)
		for gate in gates:
			if gate["broken"]: continue
			if player.position.z > gate["node"].position.z and candidate.z < gate["node"].position.z + 1.2:
				candidate.z = gate["node"].position.z + 1.2
		player.position = candidate
		if player.position.z < -476:
			finished = true
			var cfg := ConfigFile.new()
			cfg.load("user://settings.cfg")
			var previous := float(cfg.get_value("records", "best_time", 0.0))
			if previous <= 0.0 or run_time < previous:
				cfg.set_value("records", "best_time", run_time)
				cfg.save("user://settings.cfg")
			win_text.text = "GOLDEN KABUTO UNLOCKED!\nTIME: %.1fs    SCORE: %d\nBONK CHAMPION! Confetti victory!" % [run_time, score]
			win_panel.visible = true
			for i in range(120):
				spawn_confetti()
			show_status("THE CASTLE IS YOURS! Press R to race again.", 999.0)
	player_visual.rotation.z = sin(clock * 12) * 0.045 if not settings_panel.visible else 0.0
	player_visual.rotation.x = -0.2 if attack_time > 0 else 0.0
	var cam_distance := float(settings["camera"])
	var desired := player.position + Vector3(0, cam_distance * 0.78, cam_distance * 0.78)
	cam.position = cam.position.lerp(desired, minf(1, delta * 5))
	cam.look_at(player.position + Vector3(0, 0, -8), Vector3.UP)
	for d in darumas:
		if not is_instance_valid(d): continue
		var i := int(d.get_meta("index"))
		d.position.z -= delta * (5.0 + i * 0.3)
		if d.position.z < -480: d.position.z = 5
		var body: Node3D = d.get_meta("body")
		body.rotation.x -= delta * 2.7
		body.rotation.z = sin(clock * 5.0 + i) * 0.15
		var mouth: Node3D = d.get_meta("mouth")
		mouth.scale.y = 0.6 + abs(sin(clock * 7.0 + i)) * 0.6
		if d.position.distance_to(player.position) < 2.4 and not finished:
			player.position.z += 4.0 * delta
			show_status("WARADARUMA IS LAUGHING AT YOU!", 0.5)
	for j in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[j]
		p["life"] -= delta
		if p["life"] <= 0:
			p["node"].queue_free()
			particles.remove_at(j)
		else:
			p["vel"].y -= 12 * delta
			p["node"].position += p["vel"] * delta
			p["node"].rotation += Vector3(delta * 3, delta * 4, delta * 2)
	var stage := clampi(int(-player.position.z / 160.0), 0, 2)
	stage_label.text = ["LEVEL 1  •  BAMBOO DOWNHILL", "LEVEL 2  •  GUARD GAUNTLET", "LEVEL 3  •  CASTLE CHAOS"][stage]
	combo_label.text = "BONK COMBO x%d   |   SCORE %d   |   TIME %.1fs" % [combo, score, run_time]
	distance_label.text = "ROAD TO CASTLE: %dm / 477m    |    DOORS: %d / 12    |    WARADARUMA: %d" % [int(-player.position.z), count_broken(), darumas.size()]
	for gate in gates:
		if not gate["broken"] and settings["glow"]:
			var marker: Node3D = gate["doors"][gate["correct"]]["marker"]
			marker.scale = Vector3.ONE * (0.8 + 0.18 * sin(clock * 5))

func spawn_confetti() -> void:
	var rng := RandomNumberGenerator.new()
	var colors := [Color("ffd447"), Color("d17dfb"), Color("72e3c6"), Color("ff6e92")]
	var pos := player.position + Vector3(rng.randf_range(-7, 7), rng.randf_range(3, 8), rng.randf_range(-5, 5))
	var n := box(self, pos, Vector3(0.22, 0.04, 0.3), colors[rng.randi_range(0, 3)])
	particles.append({"node":n, "vel":Vector3(rng.randf_range(-3, 3), rng.randf_range(0, 4), rng.randf_range(-3, 3)), "life":rng.randf_range(1.0, 3.0)})

func count_broken() -> int:
	var result := 0
	for gate in gates:
		if gate["broken"]: result += 1
	return result

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		for key in DEFAULTS.keys():
			settings[key] = cfg.get_value("developer", key, DEFAULTS[key])

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings.keys(): cfg.set_value("developer", key, settings[key])
	cfg.save("user://settings.cfg")
	show_status("Developer settings saved!", 2.0)

func restore_defaults() -> void:
	settings = DEFAULTS.duplicate()
	for key in sliders.keys():
		sliders[key]["slider"].value = settings[key]
		update_slider_label(key)
	glow_check.button_pressed = settings["glow"]
	refresh_darumas()
	update_markers()
