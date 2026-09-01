class_name TrackBuilderCore
## Runtime + headless track builder: builds a painted toy-racing circuit scene
## (spline corridor, island prop, walls, gates, grid, props) from a theme spec,
## a room shape, and a seed. Pure runtime code — no SceneTree/editor deps — so
## the race can generate any arbitrary seed on demand.

const CHECKPOINT_SCENE := "res://scenes/race/checkpoint.tscn"
const HALF_WIDTH := 125.0
const SAMPLE_COUNT := 260
const GATE_COUNT := 8
const RECOVERY_LANE_HALF_LENGTH := 230.0
const RECOVERY_LANE_HALF_WIDTH := 48.0
const SHORTCUT_HALF_SPAN := 10
const SHORTCUT_LANE_OFFSET := 70.0
const SHORTCUT_LANE_HALF_WIDTH := 26.0
const SAFE_RACING_LINE_OFFSET := 58.0
const FINISH_APPROACH_SPAN := 20

static var ROOM_SHAPES := {
	"classic": PackedVector2Array([Vector2(-875, -575), Vector2(875, -575), Vector2(875, 575), Vector2(-875, 575)]),
	"wide": PackedVector2Array([Vector2(-1175, -600), Vector2(1175, -600), Vector2(1175, 600), Vector2(-1175, 600)]),
	"tall": PackedVector2Array([Vector2(-575, -725), Vector2(575, -725), Vector2(575, 725), Vector2(-575, 725)]),
	"el": PackedVector2Array([Vector2(-1200, -700), Vector2(360, -700), Vector2(360, -60), Vector2(1200, -60), Vector2(1200, 700), Vector2(-1200, 700)]),
	"long": PackedVector2Array([Vector2(-1300, -550), Vector2(1300, -550), Vector2(1300, 550), Vector2(-1300, 550)]),
	"square": PackedVector2Array([Vector2(-750, -750), Vector2(750, -750), Vector2(750, 750), Vector2(-750, 750)]),
}

static var ISLAND_VIGNETTES := {
	&"kitchen": [
		[
			{"tex": "res://assets/textures/imagine/teapot_top.png", "pos": Vector2(-0.15, -0.25), "rot": 0.2},
			{"tex": "res://assets/textures/imagine/mug_top.png", "pos": Vector2(0.35, -0.3), "rot": -0.4},
			{"tex": "res://assets/textures/kitchen/mug_blue.png", "pos": Vector2(0.55, -0.15), "rot": 0.9},
			{"tex": "res://assets/textures/imagine/plate_stack.png", "pos": Vector2(-0.45, 0.3), "rot": 0.05},
			{"tex": "res://assets/textures/kitchen/fork_cartoon.png", "pos": Vector2(-0.28, 0.42), "rot": -0.6},
			{"tex": "res://assets/textures/kitchen/spoon_bridge.png", "pos": Vector2(-0.1, 0.48), "rot": -0.5},
			{"tex": "res://assets/textures/imagine/teacup_saucer.png", "pos": Vector2(0.15, -0.45), "rot": 0.3},
			{"tex": "res://assets/textures/imagine/salt_shaker.png", "pos": Vector2(0.5, 0.35), "rot": 0.1},
			{"tex": "res://assets/textures/imagine/crumb_cluster.png", "pos": Vector2(-0.3, 0.05), "rot": 0.0, "decal": true},
			{"tex": "res://assets/textures/imagine/stain_ring.png", "pos": Vector2(0.35, -0.1), "rot": 0.0, "decal": true},
		],
		[
			{"tex": "res://assets/textures/imagine/watermelon.png", "pos": Vector2(0.1, 0.2), "rot": 0.4},
			{"tex": "res://assets/textures/imagine/vase_top.png", "pos": Vector2(-0.4, -0.25), "rot": 0.0},
			{"tex": "res://assets/textures/kitchen/mug_hero.png", "pos": Vector2(0.5, -0.3), "rot": -0.2},
			{"tex": "res://assets/textures/imagine/plate_stack.png", "pos": Vector2(-0.15, 0.35), "rot": -0.1},
			{"tex": "res://assets/textures/kitchen/spoon_bridge.png", "pos": Vector2(-0.05, 0.45), "rot": -0.8},
			{"tex": "res://assets/textures/imagine/teacup_saucer.png", "pos": Vector2(0.55, 0.15), "rot": 0.6},
			{"tex": "res://assets/textures/imagine/crumb_cluster.png", "pos": Vector2(0.2, -0.4), "rot": 0.0, "decal": true},
			{"tex": "res://assets/textures/imagine/stain_ring.png", "pos": Vector2(-0.45, 0.15), "rot": 0.0, "decal": true},
		],
	],
	&"workshop": [
		[
			{"tex": "res://assets/textures/imagine/barrel_wood.png", "pos": Vector2(0.25, 0.15), "rot": 0.1},
			{"tex": "res://assets/textures/imagine/workshop_paint_can.png", "pos": Vector2(-0.4, -0.2), "rot": -0.3},
			{"tex": "res://assets/textures/imagine/workshop_paint_can.png", "pos": Vector2(-0.25, -0.4), "rot": 0.5},
			{"tex": "res://assets/textures/imagine/hose_coil.png", "pos": Vector2(-0.35, 0.35), "rot": -0.2},
			{"tex": "res://assets/textures/imagine/wrench.png", "pos": Vector2(0.5, -0.35), "rot": 1.2},
			{"tex": "res://assets/textures/imagine/hammer.png", "pos": Vector2(0.15, -0.45), "rot": -1.0},
			{"tex": "res://assets/textures/imagine/screwdriver.png", "pos": Vector2(0.55, 0.05), "rot": -0.7},
			{"tex": "res://assets/textures/imagine/sawdust_patch.png", "pos": Vector2(-0.05, 0.05), "rot": 0.0, "decal": true},
			{"tex": "res://assets/textures/imagine/oil_stain.png", "pos": Vector2(0.4, 0.4), "rot": 0.0, "decal": true},
		],
		[
			{"tex": "res://assets/textures/imagine/teapot_top.png", "pos": Vector2(-0.3, -0.15), "rot": 0.0},
			{"tex": "res://assets/textures/imagine/flower_pot.png", "pos": Vector2(0.45, -0.25), "rot": 0.2},
			{"tex": "res://assets/textures/imagine/basketball.png", "pos": Vector2(0.15, 0.4), "rot": 0.0},
			{"tex": "res://assets/textures/imagine/workshop_paint_can.png", "pos": Vector2(-0.5, 0.25), "rot": 0.4},
			{"tex": "res://assets/textures/imagine/hammer.png", "pos": Vector2(0.0, -0.45), "rot": 1.4},
			{"tex": "res://assets/textures/imagine/screwdriver.png", "pos": Vector2(0.55, 0.3), "rot": -0.4},
			{"tex": "res://assets/textures/imagine/sawdust_patch.png", "pos": Vector2(0.2, -0.15), "rot": 0.0, "decal": true},
			{"tex": "res://assets/textures/imagine/oil_stain.png", "pos": Vector2(-0.15, 0.3), "rot": 0.0, "decal": true},
		],
	],
	&"office": [
		[
			{"tex": "res://assets/textures/imagine/lamp_desk.png", "pos": Vector2(-0.35, -0.3), "rot": 0.0},
			{"tex": "res://assets/textures/imagine/mug_top.png", "pos": Vector2(0.3, -0.4), "rot": 0.4},
			{"tex": "res://assets/textures/imagine/book_top.png", "pos": Vector2(0.5, 0.2), "rot": -0.3},
			{"tex": "res://assets/textures/imagine/remote_control.png", "pos": Vector2(-0.15, 0.45), "rot": 0.15},
			{"tex": "res://assets/textures/imagine/pencil.png", "pos": Vector2(0.05, -0.2), "rot": -0.9},
			{"tex": "res://assets/textures/imagine/stapler_top.png", "pos": Vector2(-0.5, 0.05), "rot": 0.6},
			{"tex": "res://assets/textures/imagine/paper_sheet.png", "pos": Vector2(0.1, 0.15), "rot": 0.1, "decal": true},
			{"tex": "res://assets/textures/imagine/stain_ring.png", "pos": Vector2(0.35, 0.35), "rot": 0.0, "decal": true},
		],
		[
			{"tex": "res://assets/textures/imagine/tape_roll.png", "pos": Vector2(0.45, -0.3), "rot": 0.3},
			{"tex": "res://assets/textures/imagine/plate_stack.png", "pos": Vector2(-0.35, 0.3), "rot": 0.0},
			{"tex": "res://assets/textures/imagine/bottle_top.png", "pos": Vector2(-0.15, -0.4), "rot": 0.0},
			{"tex": "res://assets/textures/imagine/mug_top.png", "pos": Vector2(0.2, 0.4), "rot": -0.3},
			{"tex": "res://assets/textures/imagine/scissors_top.png", "pos": Vector2(0.55, 0.1), "rot": 0.9},
			{"tex": "res://assets/textures/imagine/pencil.png", "pos": Vector2(-0.5, -0.1), "rot": 0.5},
			{"tex": "res://assets/textures/imagine/paper_sheet.png", "pos": Vector2(-0.1, 0.05), "rot": -0.15, "decal": true},
			{"tex": "res://assets/textures/imagine/stain_ring.png", "pos": Vector2(0.4, -0.05), "rot": 0.0, "decal": true},
		],
	],
}


## Generated tracks use one complete scene kit.  Unlike the legacy static-track
## pools below, every asset in a kit belongs to the same household story.
static var STORY_KITS := {
	&"kitchen": [
		{
			"id": &"breakfast_service",
			"island": [
				{"asset": "res://assets/textures/imagine/stove_top.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/imagine/teacup_saucer.png", "quantity": &"few", "count": 3, "formation": &"arc", "offset": Vector2(66, -12)},
				{"asset": "res://assets/textures/imagine/kitchen_cereal_orange.png", "quantity": &"many", "count": 10, "formation": &"cluster", "offset": Vector2(16, 78)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/kitchen_fork.png", "count": 10},
			"delimiter": {"asset": "res://assets/textures/imagine/kitchen_spoon.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/teapot_top.png", "res://assets/textures/imagine/plate_stack.png"],
			"surfaces": [
				{"name": &"breakfast crumbs", "grip": 0.82, "speed": 0.76, "decal": "res://assets/textures/imagine/crumb_cluster.png"},
				{"name": &"tea spill", "grip": 0.56, "speed": 0.88, "decal": "res://assets/textures/kitchen/wet_spill.png"},
			],
		},
		{
			"id": &"vegetable_prep",
			"island": [
				{"asset": "res://assets/textures/kitchen/cutting_board.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-28, 0)},
				{"asset": "res://assets/textures/imagine/frying_pan.png", "quantity": &"few", "count": 2, "formation": &"arc", "offset": Vector2(70, -22)},
				{"asset": "res://assets/textures/kitchen/lime_cartoon.png", "quantity": &"many", "count": 12, "formation": &"cluster", "offset": Vector2(12, 78)},
			],
			"object_line": {"asset": "res://assets/textures/kitchen/apple_cartoon.png", "count": 12},
			"delimiter": {"asset": "res://assets/textures/imagine/kitchen_fork.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/stove_top.png", "res://assets/textures/imagine/watermelon.png"],
			"surfaces": [
				{"name": &"prep crumbs", "grip": 0.8, "speed": 0.74, "decal": "res://assets/textures/kitchen/crumb_cluster_02.png"},
				{"name": &"chopping spill", "grip": 0.6, "speed": 0.86, "decal": "res://assets/textures/kitchen/spill_decal.png"},
			],
		},
		{
			"id": &"afternoon_tea",
			"island": [
				{"asset": "res://assets/textures/imagine/teapot_top.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-30, -8)},
				{"asset": "res://assets/textures/imagine/teacup_saucer.png", "quantity": &"few", "count": 3, "formation": &"arc", "offset": Vector2(66, -6)},
				{"asset": "res://assets/textures/imagine/strawberry.png", "quantity": &"many", "count": 14, "formation": &"arc", "offset": Vector2(4, 74)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/kitchen_spoon.png", "count": 10},
			"delimiter": {"asset": "res://assets/textures/imagine/kitchen_fork.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/stove_top.png", "res://assets/textures/imagine/plate_stack.png"],
			"surfaces": [
				{"name": &"tea biscuits", "grip": 0.84, "speed": 0.78, "decal": "res://assets/textures/imagine/crumb_cluster.png"},
				{"name": &"saucer spill", "grip": 0.54, "speed": 0.9, "decal": "res://assets/textures/kitchen/wet_spill.png"},
			],
		},
		{
			"id": &"counter_cleanup",
			"island": [
				{"asset": "res://assets/textures/imagine/plate_stack.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/kitchen/sponge_wet.png", "quantity": &"few", "count": 3, "formation": &"line", "offset": Vector2(62, -12)},
				{"asset": "res://assets/textures/kitchen/cup_cartoon.png", "quantity": &"many", "count": 8, "formation": &"cluster", "offset": Vector2(8, 78)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/kitchen_fork.png", "count": 10},
			"delimiter": {"asset": "res://assets/textures/kitchen/napkin.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/stove_top.png", "res://assets/textures/imagine/teapot_top.png"],
			"surfaces": [
				{"name": &"cleanup suds", "grip": 0.62, "speed": 0.82, "decal": "res://assets/textures/kitchen/spill_decal.png"},
				{"name": &"wipe crumbs", "grip": 0.86, "speed": 0.8, "decal": "res://assets/textures/kitchen/crumb_cluster_01.png"},
			],
		},
	],
	&"workshop": [
		{
			"id": &"carpentry_bench",
			"island": [
				{"asset": "res://assets/textures/imagine/island_tool_tray.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/imagine/hammer.png", "quantity": &"few", "count": 2, "formation": &"line", "offset": Vector2(70, -8)},
				{"asset": "res://assets/textures/imagine/screw.png", "quantity": &"many", "count": 16, "formation": &"cluster", "offset": Vector2(8, 76)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/screw.png", "count": 16},
			"delimiter": {"asset": "res://assets/textures/imagine/plank_wood.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/bucket_stack.png", "res://assets/textures/imagine/barrel_wood.png"],
			"surfaces": [
				{"name": &"carpentry sawdust", "grip": 0.76, "speed": 0.7, "decal": "res://assets/textures/imagine/sawdust_patch.png"},
				{"name": &"bench oil", "grip": 0.46, "speed": 0.9, "decal": "res://assets/textures/imagine/oil_stain.png"},
			],
		},
		{
			"id": &"paint_station",
			"island": [
				{"asset": "res://assets/textures/imagine/bucket_stack.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/imagine/workshop_paint_can.png", "quantity": &"few", "count": 3, "formation": &"arc", "offset": Vector2(70, -8)},
				{"asset": "res://assets/textures/imagine/bolt.png", "quantity": &"many", "count": 12, "formation": &"arc", "offset": Vector2(4, 78)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/bolt.png", "count": 14},
			"delimiter": {"asset": "res://assets/textures/imagine/plank_wood.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/workshop_paint_can.png", "res://assets/textures/imagine/hose_coil.png"],
			"surfaces": [
				{"name": &"paint dust", "grip": 0.74, "speed": 0.72, "decal": "res://assets/textures/imagine/sawdust_patch.png"},
				{"name": &"paint station oil", "grip": 0.44, "speed": 0.88, "decal": "res://assets/textures/imagine/oil_stain.png"},
			],
		},
		{
			"id": &"repair_job",
			"island": [
				{"asset": "res://assets/textures/imagine/island_tool_tray.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/imagine/wrench.png", "quantity": &"few", "count": 3, "formation": &"arc", "offset": Vector2(70, -8)},
				{"asset": "res://assets/textures/imagine/screw.png", "quantity": &"many", "count": 14, "formation": &"cluster", "offset": Vector2(4, 78)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/screw.png", "count": 14},
			"delimiter": {"asset": "res://assets/textures/imagine/plank_wood.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/bucket_stack.png", "res://assets/textures/imagine/hose_coil.png"],
			"surfaces": [
				{"name": &"repair oil", "grip": 0.43, "speed": 0.9, "decal": "res://assets/textures/imagine/oil_stain.png"},
				{"name": &"repair sawdust", "grip": 0.78, "speed": 0.7, "decal": "res://assets/textures/imagine/sawdust_patch.png"},
			],
		},
		{
			"id": &"garage_sort",
			"island": [
				{"asset": "res://assets/textures/imagine/hose_coil.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/imagine/bucket_stack.png", "quantity": &"few", "count": 2, "formation": &"arc", "offset": Vector2(72, -8)},
				{"asset": "res://assets/textures/imagine/bolt.png", "quantity": &"many", "count": 10, "formation": &"cluster", "offset": Vector2(4, 80)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/bolt.png", "count": 12},
			"delimiter": {"asset": "res://assets/textures/imagine/plank_wood.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/barrel_wood.png", "res://assets/textures/imagine/workshop_paint_can.png"],
			"surfaces": [
				{"name": &"garage oil", "grip": 0.42, "speed": 0.88, "decal": "res://assets/textures/imagine/oil_stain.png"},
				{"name": &"garage dust", "grip": 0.75, "speed": 0.68, "decal": "res://assets/textures/imagine/sawdust_patch.png"},
			],
		},
	],
	&"office": [
		{
			"id": &"dual_workstation",
			"island": [
				{"asset": "res://assets/textures/imagine/monitor_top.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/imagine/island_keyboard.png", "quantity": &"few", "count": 2, "formation": &"line", "offset": Vector2(72, -8)},
				{"asset": "res://assets/textures/imagine/paperclip.png", "quantity": &"many", "count": 16, "formation": &"cluster", "offset": Vector2(4, 78)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/paperclip.png", "count": 16},
			"delimiter": {"asset": "res://assets/textures/imagine/hazard_office_cable.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/lamp_desk.png", "res://assets/textures/imagine/book_top.png"],
			"surfaces": [
				{"name": &"workstation papers", "grip": 0.82, "speed": 0.76, "decal": "res://assets/textures/imagine/paper_sheet.png"},
				{"name": &"workstation coffee", "grip": 0.6, "speed": 0.86, "decal": "res://assets/textures/imagine/stain_ring.png"},
			],
		},
		{
			"id": &"mail_sort",
			"island": [
				{"asset": "res://assets/textures/imagine/book_top.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/imagine/stapler_top.png", "quantity": &"few", "count": 3, "formation": &"arc", "offset": Vector2(70, -8)},
				{"asset": "res://assets/textures/imagine/paperclip.png", "quantity": &"many", "count": 14, "formation": &"cluster", "offset": Vector2(4, 78)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/paperclip.png", "count": 14},
			"delimiter": {"asset": "res://assets/textures/imagine/hazard_office_cable.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/monitor_top.png", "res://assets/textures/imagine/tape_roll.png"],
			"surfaces": [
				{"name": &"mail papers", "grip": 0.8, "speed": 0.74, "decal": "res://assets/textures/imagine/paper_sheet.png"},
				{"name": &"mailroom coffee", "grip": 0.58, "speed": 0.86, "decal": "res://assets/textures/imagine/stain_ring.png"},
			],
		},
		{
			"id": &"sketch_session",
			"island": [
				{"asset": "res://assets/textures/imagine/crayons.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/imagine/scissors_top.png", "quantity": &"few", "count": 2, "formation": &"arc", "offset": Vector2(70, -8)},
				{"asset": "res://assets/textures/imagine/pencil.png", "quantity": &"many", "count": 10, "formation": &"arc", "offset": Vector2(4, 80)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/pencil.png", "count": 10},
			"delimiter": {"asset": "res://assets/textures/imagine/hazard_office_cable.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/monitor_top.png", "res://assets/textures/imagine/lamp_desk.png"],
			"surfaces": [
				{"name": &"sketch papers", "grip": 0.83, "speed": 0.75, "decal": "res://assets/textures/imagine/paper_sheet.png"},
				{"name": &"sketch coffee", "grip": 0.61, "speed": 0.85, "decal": "res://assets/textures/imagine/stain_ring.png"},
			],
		},
		{
			"id": &"coffee_break",
			"island": [
				{"asset": "res://assets/textures/imagine/mug_top.png", "quantity": &"unique", "count": 1, "formation": &"focal", "offset": Vector2(-34, -8)},
				{"asset": "res://assets/textures/imagine/book_top.png", "quantity": &"few", "count": 2, "formation": &"line", "offset": Vector2(70, -8)},
				{"asset": "res://assets/textures/imagine/office_keycap.png", "quantity": &"many", "count": 12, "formation": &"cluster", "offset": Vector2(4, 78)},
			],
			"object_line": {"asset": "res://assets/textures/imagine/paperclip.png", "count": 12},
			"delimiter": {"asset": "res://assets/textures/imagine/hazard_office_cable.png", "count": 2},
			"landmarks": ["res://assets/textures/imagine/monitor_top.png", "res://assets/textures/imagine/lamp_desk.png"],
			"surfaces": [
				{"name": &"coffee papers", "grip": 0.81, "speed": 0.75, "decal": "res://assets/textures/imagine/paper_sheet.png"},
				{"name": &"coffee ring", "grip": 0.55, "speed": 0.84, "decal": "res://assets/textures/imagine/stain_ring.png"},
			],
		},
	],
}


static var PROP_SHAPES := {
	"ruler_plank.png": {"shape": "rect", "size": Vector2(110.0, 34.0)},
	"kitchen_ruler.png": {"shape": "rect", "size": Vector2(110.0, 34.0)},
	"plank_wood.png": {"shape": "rect", "size": Vector2(100.0, 38.0)},
	"book_top.png": {"shape": "rect", "size": Vector2(84.0, 62.0)},
	"remote_control.png": {"shape": "rect", "size": Vector2(76.0, 42.0)},
	"hazard_office_cable.png": {"shape": "rect", "size": Vector2(96.0, 26.0)},
	"hazard_workshop_socket.png": {"shape": "rect", "size": Vector2(96.0, 26.0)},
	"cutting_board.png": {"shape": "rect", "size": Vector2(96.0, 60.0)},
	"screwdriver.png": {"shape": "rect", "size": Vector2(56.0, 20.0)},
	"stapler_top.png": {"shape": "rect", "size": Vector2(60.0, 32.0)},
	"pencil.png": {"shape": "rect", "size": Vector2(52.0, 16.0)},
	"crayons.png": {"shape": "rect", "size": Vector2(44.0, 28.0)},
	"scissors_top.png": {"shape": "rect", "size": Vector2(52.0, 36.0)},
	"matchbox.png": {"shape": "rect", "size": Vector2(36.0, 26.0)},
	"fork_cartoon.png": {"shape": "rect", "size": Vector2(44.0, 14.0)},
	"kitchen_fork.png": {"shape": "rect", "size": Vector2(44.0, 14.0)},
	"spoon_bridge.png": {"shape": "rect", "size": Vector2(40.0, 13.0)},
	"kitchen_spoon.png": {"shape": "rect", "size": Vector2(40.0, 13.0)},
	"frying_pan.png": {"shape": "circle", "size": Vector2(74.0, 74.0)},
	"barrel_wood.png": {"shape": "circle", "size": Vector2(140.0, 140.0)},
	"flower_pot.png": {"shape": "circle", "size": Vector2(98.0, 98.0)},
	"basketball.png": {"shape": "circle", "size": Vector2(112.0, 112.0)},
	"soccer_ball.png": {"shape": "circle", "size": Vector2(92.0, 92.0)},
	"football.png": {"shape": "circle", "size": Vector2(96.0, 96.0)},
	"watermelon.png": {"shape": "circle", "size": Vector2(102.0, 102.0)},
	"hose_coil.png": {"shape": "circle", "size": Vector2(122.0, 122.0)},
	"teapot_top.png": {"shape": "circle", "size": Vector2(96.0, 96.0)},
	"mug_top.png": {"shape": "circle", "size": Vector2(44.0, 44.0)},
	"bottle_top.png": {"shape": "circle", "size": Vector2(42.0, 42.0)},
	"plate_stack.png": {"shape": "circle", "size": Vector2(64.0, 64.0)},
	"vase_top.png": {"shape": "circle", "size": Vector2(56.0, 56.0)},
	"lamp_desk.png": {"shape": "circle", "size": Vector2(58.0, 58.0)},
	"plant_small.png": {"shape": "circle", "size": Vector2(56.0, 56.0)},
	"tape_roll.png": {"shape": "circle", "size": Vector2(40.0, 40.0)},
	"teacup_saucer.png": {"shape": "circle", "size": Vector2(46.0, 46.0)},
	"salt_shaker.png": {"shape": "circle", "size": Vector2(30.0, 30.0)},
	"cup_cartoon.png": {"shape": "circle", "size": Vector2(36.0, 36.0)},
	"kitchen_cup.png": {"shape": "circle", "size": Vector2(36.0, 36.0)},
	"mug_blue.png": {"shape": "circle", "size": Vector2(44.0, 44.0)},
	"kitchen_mug_blue.png": {"shape": "circle", "size": Vector2(44.0, 44.0)},
	"kitchen_mug_hero.png": {"shape": "circle", "size": Vector2(44.0, 44.0)},
	"cereal_tower_green.png": {"shape": "circle", "size": Vector2(48.0, 48.0)},
	"kitchen_cereal_green.png": {"shape": "circle", "size": Vector2(48.0, 48.0)},
	"kitchen_cereal_orange.png": {"shape": "circle", "size": Vector2(48.0, 48.0)},
	"apple_cartoon.png": {"shape": "circle", "size": Vector2(28.0, 28.0)},
	"hazard_kitchen_apple.png": {"shape": "circle", "size": Vector2(28.0, 28.0)},
	"lime_cartoon.png": {"shape": "circle", "size": Vector2(26.0, 26.0)},
	"kitchen_lime.png": {"shape": "circle", "size": Vector2(26.0, 26.0)},
	"strawberry.png": {"shape": "circle", "size": Vector2(20.0, 20.0)},
	"bolt.png": {"shape": "circle", "size": Vector2(22.0, 22.0)},
	"screw.png": {"shape": "circle", "size": Vector2(16.0, 16.0)},
	"coin.png": {"shape": "circle", "size": Vector2(12.0, 12.0)},
	"paperclip.png": {"shape": "circle", "size": Vector2(14.0, 14.0)},
	"office_keycap.png": {"shape": "circle", "size": Vector2(32.0, 32.0)},
	"keys_ring.png": {"shape": "circle", "size": Vector2(24.0, 24.0)},
	"napkin.png": {"shape": "circle", "size": Vector2(38.0, 38.0)},
	"sponge_wet.png": {"shape": "circle", "size": Vector2(40.0, 40.0)},
	"kitchen_sponge.png": {"shape": "circle", "size": Vector2(40.0, 40.0)},
	"wrench.png": {"shape": "rect", "size": Vector2(48.0, 20.0)},
	"hammer.png": {"shape": "rect", "size": Vector2(50.0, 24.0)},
	"workshop_paint_can.png": {"shape": "circle", "size": Vector2(52.0, 52.0)},
	"island_tool_tray.png": {"shape": "rect", "size": Vector2(150.0, 150.0)},
	"island_keyboard.png": {"shape": "rect", "size": Vector2(150.0, 150.0)},
	"workshop_toolbox_top_bright.jpg": {"shape": "circle", "size": Vector2(130.0, 130.0)},
	"office_keyboard_top_bright.jpg": {"shape": "circle", "size": Vector2(130.0, 130.0)},
	"plate_large.png": {"shape": "circle", "size": Vector2(130.0, 130.0)},
	"stove_top.png": {"shape": "rect", "size": Vector2(190.0, 190.0)},
	"bucket_stack.png": {"shape": "circle", "size": Vector2(152.0, 152.0)},
	"monitor_top.png": {"shape": "rect", "size": Vector2(168.0, 126.0)},
}

const LAYOUTS := {
	&"kitchen": {
		"scene": "res://scenes/tracks/kitchen_circuit.tscn",
		"root_name": "KitchenGraybox",
		"controls": [
			Vector2(640, 370), Vector2(300, 370), Vector2(-300, 370), Vector2(-640, 370),
			Vector2(-640, 200), Vector2(-640, -200), Vector2(-640, -370), Vector2(-300, -370),
			Vector2(300, -370), Vector2(640, -370), Vector2(640, -200), Vector2(640, 200),
		],
		"floor": Color("3a332c"),
		"highlight": Color("4a4238"),
		"island": Color("4a4038"),
		"asphalt": Color("2e2c28"),
		"apron": Color("3f3830"),
		"track_texture": "res://assets/textures/imagine/track_cloth.png",
		"track_tile_modulate": 1.0,
		"floor_texture": "res://assets/textures/imagine/floor_cloth.png",
		"prop_texture": "res://assets/textures/imagine/island_plate.png",
		"prop_label": "Plate",
		"edge_texture": "res://assets/textures/kitchen/counter_edge.png",
		"island_expansion": 10.0,
		"scatter_textures": [
			"res://assets/textures/kitchen/fork_cartoon.png",
			"res://assets/textures/kitchen/spoon_bridge.png",
			"res://assets/textures/kitchen/cup_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
		],
		"island_fill_textures": [
			"res://assets/textures/kitchen/fork_cartoon.png",
			"res://assets/textures/kitchen/spoon_bridge.png",
			"res://assets/textures/kitchen/cup_cartoon.png",
			"res://assets/textures/kitchen/mug_blue.png",
			"res://assets/textures/kitchen/cereal_tower_green.png",
			"res://assets/textures/imagine/frying_pan.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/teacup_saucer.png",
			"res://assets/textures/imagine/salt_shaker.png",
			"res://assets/textures/imagine/mug_top.png",
		],
		"island_fill_huge": [
			"res://assets/textures/imagine/teapot_top.png",
			"res://assets/textures/imagine/watermelon.png",
			"res://assets/textures/imagine/plate_stack.png",
			"res://assets/textures/imagine/frying_pan.png",
			"res://assets/textures/imagine/vase_top.png",
		],
		"island_fill_big": [
			"res://assets/textures/imagine/hose_coil.png",
			"res://assets/textures/kitchen/cutting_board.png",
			"res://assets/textures/imagine/watermelon.png",
			"res://assets/textures/imagine/frying_pan.png",
			"res://assets/textures/imagine/teapot_top.png",
			"res://assets/textures/imagine/vase_top.png",
			"res://assets/textures/imagine/plate_stack.png",
		],
		"island_fill_small": [
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/imagine/strawberry.png",
			"res://assets/textures/imagine/bolt.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/keys_ring.png",
		],
		"island_fill_tiny": [
			"res://assets/textures/imagine/paperclip.png",
			"res://assets/textures/kitchen/napkin.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
		],
		"boundary_long": [
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/imagine/plank_wood.png",
			"res://assets/textures/imagine/hazard_workshop_socket.png",
		],
		"boundary_corner": [
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/plant_small.png",
		],
		"corner_giants": [
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/workshop_paint_can.png",
			"res://assets/textures/imagine/hose_coil.png",
		],
		"decals": [
			"res://assets/textures/imagine/crumb_cluster.png",
			"res://assets/textures/imagine/stain_ring.png",
			"res://assets/textures/kitchen/wet_spill.png",
			"res://assets/textures/kitchen/spill_decal.png",
			"res://assets/textures/kitchen/wood_scratch.png",
			"res://assets/textures/kitchen/water_droplet_01.png",
			"res://assets/textures/kitchen/water_droplet_02.png",
			"res://assets/textures/kitchen/cereal_scatter.png",
		],
		"ground_sections": [
			{"asset": "res://assets/textures/ground_dressing/kitchen_tablecloth_patch.png", "size": 330.0, "alpha": 0.92},
			{"asset": "res://assets/textures/ground_dressing/kitchen_dish_towel_blue.png", "size": 270.0, "alpha": 0.96},
			{"asset": "res://assets/textures/ground_dressing/kitchen_cleaning_rag_yellow.png", "size": 220.0, "alpha": 0.94},
			{"asset": "res://assets/textures/ground_dressing/kitchen_oven_mitt_red.png", "size": 205.0, "alpha": 0.96},
		],
		"obstacles": {
			"MugA": {"pos": Vector2(-300, 290), "r": 36.0, "tex": "res://assets/textures/imagine/kitchen_mug_hero.png"},
			"MugB": {"pos": Vector2(-60, 500), "r": 36.0, "tex": "res://assets/textures/imagine/kitchen_mug_blue.png"},
			"Apple": {"pos": Vector2(-500, 35), "r": 36.0, "tex": "res://assets/textures/kitchen/apple_cartoon.png"},
			"Lime": {"pos": Vector2(-390, 120), "r": 36.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			"Cup": {"pos": Vector2(-510, 520), "r": 36.0, "tex": "res://assets/textures/kitchen/cup_cartoon.png"},
		},
	},
	&"workshop": {
		"scene": "res://scenes/tracks/workshop_workbench.tscn",
		"root_name": "WorkshopWorkbench",
		"controls": [
			Vector2(640, 370), Vector2(300, 370), Vector2(-300, 370), Vector2(-735, 330),
			Vector2(-735, 0), Vector2(-735, -250), Vector2(-600, -420), Vector2(-300, -470),
			Vector2(0, -480), Vector2(300, -470), Vector2(600, -420), Vector2(735, -250),
			Vector2(735, 0), Vector2(735, 370),
		],
		"floor": Color("7a5a3f"),
		"highlight": Color("8a6a4f"),
		"island": Color("4a4038"),
		"asphalt": Color("2e2c28"),
		"apron": Color("5c4638"),
		"track_texture": "res://assets/textures/imagine/track_wood.png",
		"track_tile_modulate": 1.0,
		"floor_texture": "res://assets/textures/imagine/floor_wood.png",
		"prop_texture": "res://assets/textures/imagine/island_tool_tray.png",
		"prop_label": "Toolbox",
		"edge_texture": "res://assets/textures/imagine/workshop_edge_bright.png",
		"scatter_textures": [
			"res://assets/textures/imagine/workshop_paint_can.png",
			"res://assets/textures/imagine/hazard_workshop_socket.png",
			"res://assets/textures/kitchen/fork_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/kitchen/ruler_plank.png",
		],
		"island_fill_textures": [
			"res://assets/textures/imagine/plank_wood.png",
			"res://assets/textures/imagine/workshop_paint_can.png",
			"res://assets/textures/imagine/hazard_workshop_socket.png",
			"res://assets/textures/kitchen/fork_cartoon.png",
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/imagine/wrench.png",
			"res://assets/textures/imagine/hammer.png",
			"res://assets/textures/imagine/remote_control.png",
			"res://assets/textures/imagine/screwdriver.png",
			"res://assets/textures/imagine/tape_roll.png",
			"res://assets/textures/imagine/matchbox.png",
		],
		"island_fill_huge": [
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/workshop_paint_can.png",
			"res://assets/textures/imagine/hose_coil.png",
			"res://assets/textures/imagine/basketball.png",
			"res://assets/textures/imagine/teapot_top.png",
			"res://assets/textures/imagine/flower_pot.png",
		],
		"island_fill_big": [
			"res://assets/textures/imagine/hose_coil.png",
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/basketball.png",
			"res://assets/textures/imagine/soccer_ball.png",
			"res://assets/textures/imagine/football.png",
			"res://assets/textures/imagine/lamp_desk.png",
			"res://assets/textures/imagine/bottle_top.png",
			"res://assets/textures/imagine/teapot_top.png",
		],
		"island_fill_small": [
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/imagine/strawberry.png",
			"res://assets/textures/imagine/bolt.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/keys_ring.png",
		],
		"island_fill_tiny": [
			"res://assets/textures/imagine/paperclip.png",
			"res://assets/textures/kitchen/napkin.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
		],
		"boundary_long": [
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/kitchen/spoon_bridge.png",
		],
		"boundary_corner": [
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/kitchen/cup_cartoon.png",
		],
		"corner_giants": [
			"res://assets/textures/imagine/mug_top.png",
			"res://assets/textures/imagine/teapot_top.png",
			"res://assets/textures/imagine/vase_top.png",
		],
		"decals": [
			"res://assets/textures/imagine/sawdust_patch.png",
			"res://assets/textures/imagine/oil_stain.png",
			"res://assets/textures/imagine/stain_ring.png",
			"res://assets/textures/kitchen/wood_scratch.png",
		],
		"ground_sections": [
			{"asset": "res://assets/textures/ground_dressing/workshop_dropcloth_patch.png", "size": 340.0, "alpha": 0.90},
			{"asset": "res://assets/textures/ground_dressing/workshop_shop_rag_red.png", "size": 220.0, "alpha": 0.94},
			{"asset": "res://assets/textures/ground_dressing/workshop_cardboard_scrap.png", "size": 270.0, "alpha": 0.96},
			{"asset": "res://assets/textures/ground_dressing/workshop_sandpaper_sheet.png", "size": 210.0, "alpha": 0.95},
		],
		"island_expansion": 10.0,
		"obstacles": {
			"CerealA": {"pos": Vector2(300, 430), "r": 38.0, "tex": "res://assets/textures/imagine/workshop_paint_can.png"},
			"MugA": {"pos": Vector2(-300, 290), "r": 36.0, "tex": "res://assets/textures/imagine/workshop_paint_can.png"},
			"MugB": {"pos": Vector2(-60, 500), "r": 36.0, "tex": "res://assets/textures/imagine/workshop_paint_can.png"},
			"Sponge": {"pos": Vector2(-180, 300), "r": 34.0, "tex": "res://assets/textures/kitchen/sponge_wet.png"},
			"Ruler": {"pos": Vector2(-60, 290), "r": 32.0, "tex": "res://assets/textures/kitchen/ruler_plank.png"},
			"Fork": {"pos": Vector2(-820, -330), "r": 34.0, "tex": "res://assets/textures/kitchen/fork_cartoon.png"},
			"Spoon": {"pos": Vector2(830, -80), "r": 36.0, "tex": "res://assets/textures/imagine/hazard_workshop_socket.png"},
			"Apple": {"pos": Vector2(-500, 35), "r": 36.0, "tex": "res://assets/textures/kitchen/apple_cartoon.png"},
			"Lime": {"pos": Vector2(-390, 120), "r": 36.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			"Cup": {"pos": Vector2(-510, 520), "r": 36.0, "tex": "res://assets/textures/kitchen/cup_cartoon.png"},
			"CerealB": {"pos": Vector2(200, -60), "r": 36.0, "tex": "res://assets/textures/kitchen/cereal_tower_green.png"},
		},
		"apron_props": [
															{"pos": Vector2(-560, -260), "r": 26.0, "tex": "res://assets/textures/kitchen/apple_cartoon.png"},
			{"pos": Vector2(-450, -300), "r": 24.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			{"pos": Vector2(-510, -180), "r": 22.0, "tex": "res://assets/textures/kitchen/sponge_wet.png"},
			{"pos": Vector2(120, -520), "r": 30.0, "tex": "res://assets/textures/imagine/hazard_workshop_socket.png"},
			{"pos": Vector2(260, -560), "r": 26.0, "tex": "res://assets/textures/imagine/workshop_paint_can.png"},
		],
	},
	&"office": {
		"scene": "res://scenes/tracks/office_desk.tscn",
		"root_name": "OfficeDesk",
		"controls": [
			Vector2(640, 370), Vector2(300, 370), Vector2(-300, 370), Vector2(-400, 340),
			Vector2(-700, 260), Vector2(-820, 215), Vector2(-750, 180), Vector2(-600, 112),
			Vector2(-400, 22), Vector2(-200, -67), Vector2(0, -157), Vector2(200, -246),
			Vector2(400, -336), Vector2(600, -420), Vector2(735, -300), Vector2(735, 0),
			Vector2(735, 370),
		],
		"floor": Color("5a6170"),
		"highlight": Color("6a7180"),
		"island": Color("4a505c"),
		"asphalt": Color("272b31"),
		"apron": Color("4a5060"),
		"track_texture": "res://assets/textures/imagine/track_pad.png",
		"track_tile_modulate": 1.0,
		"floor_texture": "res://assets/textures/imagine/floor_pad.png",
		"prop_texture": "res://assets/textures/imagine/island_keyboard.png",
		"prop_label": "Keyboard",
		"edge_texture": "res://assets/textures/imagine/office_edge_bright.png",
		"scatter_textures": [
			"res://assets/textures/imagine/office_keycap.png",
			"res://assets/textures/imagine/hazard_office_cable.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
		],
		"island_fill_textures": [
			"res://assets/textures/imagine/book_top.png",
			"res://assets/textures/imagine/plank_wood.png",
			"res://assets/textures/imagine/office_keycap.png",
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/imagine/remote_control.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/stapler_top.png",
			"res://assets/textures/imagine/pencil.png",
			"res://assets/textures/imagine/crayons.png",
			"res://assets/textures/imagine/scissors_top.png",
			"res://assets/textures/imagine/tape_roll.png",
		],
		"island_fill_huge": [
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/teapot_top.png",
			"res://assets/textures/imagine/lamp_desk.png",
			"res://assets/textures/imagine/plate_stack.png",
			"res://assets/textures/imagine/watermelon.png",
		],
		"island_fill_big": [
			"res://assets/textures/imagine/hose_coil.png",
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/lamp_desk.png",
			"res://assets/textures/imagine/mug_top.png",
			"res://assets/textures/imagine/plate_stack.png",
		],
		"island_fill_small": [
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/imagine/strawberry.png",
			"res://assets/textures/imagine/bolt.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/keys_ring.png",
		],
		"island_fill_tiny": [
			"res://assets/textures/imagine/paperclip.png",
			"res://assets/textures/kitchen/napkin.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
		],
		"boundary_long": [
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/imagine/office_keycap.png",
			"res://assets/textures/imagine/hazard_office_cable.png",
		],
		"boundary_corner": [
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/plant_small.png",
		],
		"corner_giants": [
			"res://assets/textures/imagine/lamp_desk.png",
			"res://assets/textures/imagine/tape_roll.png",
			"res://assets/textures/imagine/mug_top.png",
		],
		"decals": [
			"res://assets/textures/imagine/paper_sheet.png",
			"res://assets/textures/imagine/stain_ring.png",
			"res://assets/textures/imagine/crumb_cluster.png",
		],
		"ground_sections": [
			{"asset": "res://assets/textures/ground_dressing/office_desk_pad_patch.png", "size": 330.0, "alpha": 0.88},
			{"asset": "res://assets/textures/ground_dressing/office_envelope_stack.png", "size": 255.0, "alpha": 0.96},
			{"asset": "res://assets/textures/ground_dressing/office_sticky_notes.png", "size": 220.0, "alpha": 0.96},
			{"asset": "res://assets/textures/ground_dressing/office_notepad_page.png", "size": 245.0, "alpha": 0.96},
		],
		"island_expansion": 4.0,
		"gate_fractions": [0.0, 0.125, 0.25, 0.43, 0.55, 0.67, 0.72, 0.74],
		"obstacles": {
			"CerealA": {"pos": Vector2(300, 430), "r": 38.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
			"MugA": {"pos": Vector2(-300, 500), "r": 36.0, "tex": "res://assets/textures/imagine/kitchen_mug_hero.png"},
			"MugB": {"pos": Vector2(-60, 520), "r": 36.0, "tex": "res://assets/textures/imagine/kitchen_mug_blue.png"},
			"Sponge": {"pos": Vector2(-180, 300), "r": 34.0, "tex": "res://assets/textures/kitchen/sponge_wet.png"},
			"Ruler": {"pos": Vector2(-60, 200), "r": 32.0, "tex": "res://assets/textures/kitchen/ruler_plank.png"},
			"Fork": {"pos": Vector2(-820, -330), "r": 34.0, "tex": "res://assets/textures/kitchen/fork_cartoon.png"},
			"Spoon": {"pos": Vector2(830, 120), "r": 36.0, "tex": "res://assets/textures/imagine/hazard_office_cable.png"},
			"Apple": {"pos": Vector2(-470, 60), "r": 36.0, "tex": "res://assets/textures/kitchen/apple_cartoon.png"},
			"Lime": {"pos": Vector2(-410, 170), "r": 36.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			"Cup": {"pos": Vector2(-560, 540), "r": 36.0, "tex": "res://assets/textures/kitchen/cup_cartoon.png"},
			"CerealB": {"pos": Vector2(200, -60), "r": 36.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
		},
		"apron_props": [
			{"pos": Vector2(-300, -340), "r": 24.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
			{"pos": Vector2(-500, -420), "r": 22.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
			{"pos": Vector2(-180, -480), "r": 26.0, "tex": "res://assets/textures/kitchen/sponge_wet.png"},
			{"pos": Vector2(-420, -560), "r": 24.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			{"pos": Vector2(180, -560), "r": 22.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
		],
	},
}


static func build_packed(theme: StringName, room_shape: StringName, seed: int) -> Dictionary:
	var spec: Dictionary = LAYOUTS[theme]
	var room_polygon: PackedVector2Array = ROOM_SHAPES[room_shape]
	var used_seed := seed
	if seed >= 0:
		var room_params := {
			"margin": 150.0,
			"min_point_distance": 210.0,
			"max_angle_deg": 80.0,
			"min_self_distance": 250.0,
			"min_loop_length": 1900.0,
			"room_polygon": room_polygon,
			"room_shape": room_shape,
		}
		match room_shape:
			&"tall":
				room_params["displacement_scale"] = 0.55
			&"el":
				room_params["displacement_scale"] = 0.5
				room_params["min_loop_length"] = 1500.0
			&"long":
				room_params["displacement_scale"] = 1.0
				room_params["min_loop_length"] = 2000.0
			&"square":
				room_params["displacement_scale"] = 1.0
				room_params["min_loop_length"] = 2200.0
		var gen := TrackSeedGen.generate_with_retries(seed, Rect2(-940, -540, 1880, 1080), room_params)
		if gen["points"].is_empty():
			push_error("TrackBuilderCore: could not generate a valid circuit near seed " + str(seed))
			return {"scene": null, "seed": seed}
		spec = spec.duplicate()
		spec["controls"] = gen["points"]
		spec["seed_obstacles"] = true
		spec["seed"] = int(gen["seed"])
		spec["requested_seed"] = seed
		spec["family"] = StringName(gen["family"])
		spec["realization"] = StringName(gen.get("realization", gen["family"]))
		spec["generation_attempt"] = int(gen.get("attempt", 0))
		spec["generation_fallback"] = bool(gen.get("fallback", false))
		spec["loop_length"] = float(gen["length"])
		var kits: Array = STORY_KITS.get(theme, STORY_KITS[&"kitchen"])
		var kit_index := posmod(_mix_seed(seed, String(theme)), kits.size())
		spec["story_kit"] = (kits[kit_index] as Dictionary).duplicate(true)
		spec["story_id"] = StringName(spec["story_kit"]["id"])
		spec["island_expansion"] = 10.0
		spec.erase("gate_fractions")
		used_seed = int(gen["seed"])
	var root := Node2D.new()
	root.name = String(spec["root_name"])
	root.add_to_group("track", true)
	if spec.get("seed_obstacles", false):
		root.set_meta("generated_track", true)
		root.set_meta("requested_seed", int(spec["requested_seed"]))
		root.set_meta("family", StringName(spec["family"]))
		root.set_meta("realization", StringName(spec["realization"]))
		root.set_meta("generation_attempt", int(spec["generation_attempt"]))
		root.set_meta("generation_fallback", bool(spec["generation_fallback"]))
		root.set_meta("story_id", StringName(spec["story_id"]))
		root.set_meta("loop_length", float(spec["loop_length"]))
		root.set_meta("theme", theme)
		root.set_meta("room_shape", room_shape)
	var centerline := _sample_centerline(spec["controls"])
	var edges := _corridor_edges(centerline)
	_build_scene(root, spec, centerline, edges, room_polygon, theme)
	_mark_owned(root)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return {"scene": packed, "seed": used_seed}


static func _sample_centerline(controls: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in SAMPLE_COUNT:
		points.append(_catmull_rom_closed(controls, float(index) / float(SAMPLE_COUNT)))
	return points


static func _catmull_rom_closed(points: Array, t: float) -> Vector2:
	var count := points.size()
	var scaled := t * float(count)
	var i := int(floor(scaled))
	var local := scaled - float(i)
	var p0: Vector2 = points[posmod(i - 1, count)]
	var p1: Vector2 = points[posmod(i, count)]
	var p2: Vector2 = points[posmod(i + 1, count)]
	var p3: Vector2 = points[posmod(i + 2, count)]
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * local
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * local * local
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * local * local * local
	)


static func _corridor_edges(centerline: PackedVector2Array) -> Dictionary:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var count := centerline.size()
	for index in count:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var normal := tangent.rotated(PI * 0.5)
		left.append(centerline[index] + normal * HALF_WIDTH)
		right.append(centerline[index] - normal * HALF_WIDTH)
	return {"left": left, "right": right, "centerline": centerline}


static func _build_scene(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, edges: Dictionary, room_polygon: PackedVector2Array, theme: StringName) -> void:
	var left: PackedVector2Array = edges["left"]
	var right: PackedVector2Array = edges["right"]

	# Floor: center the backdrop on the selected room so follow-camera overscan
	# never exposes an asymmetric black void around wide or L-shaped canvases.
	var floor_texture := String(spec.get("floor_texture", ""))
	var room_bounds := _polygon_bounds_rect(room_polygon)
	var backdrop := room_bounds.grow(760.0)
	_add_polygon(root, "Floor", _rect_points(backdrop.get_center(), backdrop.size), spec["floor"], -22)
	if not floor_texture.is_empty():
		var floor_columns := maxi(4, int(ceil(backdrop.size.x / 520.0)))
		var floor_rows := maxi(3, int(ceil(backdrop.size.y / 520.0)))
		_add_floor_tiles(root, floor_texture, backdrop.position, backdrop.size, floor_columns, floor_rows, Vector2(1.0, 1.0))
	var room_surface := _expand_loop(room_polygon, 26.0)
	_add_textured_polygon(root, "RoomSurface", room_surface, floor_texture, spec["highlight"], -20)

	# Painted track ribbon (visual only — no collision)
	var corridor := PackedVector2Array()
	corridor.append_array(left)
	for index in range(right.size() - 1, -1, -1):
		corridor.append(right[index])
	var clipped_pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(room_polygon, corridor)
	var clipped := PackedVector2Array()
	for piece: PackedVector2Array in clipped_pieces:
		if piece.size() > clipped.size():
			clipped = piece
	if not spec.get("seed_obstacles", false):
		# Canonical tracks retain their authored painted base. Generated tracks use
		# the themed TrackSurface directly; a translucent annular overlay produces
		# visible triangulation fans in deep notches and L-shaped routes.
		_add_polygon(root, "TrackRibbon", clipped, Color(1.0, 0.96, 0.88, 0.17), -10)
	var track_texture := String(spec.get("track_texture", ""))
	if not track_texture.is_empty():
		_add_centerline_tiles(root, centerline, track_texture, Vector2(0.30, 0.30), float(spec.get("track_tile_modulate", 1.35)))

	# No painted delimitation lines: the ribbon, island prop, and placed props
	# define the course
	var outer_loop := left if absf(_polygon_area(left)) > absf(_polygon_area(right)) else right
	var inner_loop := left if absf(_polygon_area(left)) < absf(_polygon_area(right)) else right
	if spec.get("seed_obstacles", false):
		inner_loop = _simple_island_loop(inner_loop)
	# Generated centerlines are clearance-validated, so their inner offset is the
	# authoritative island boundary. Boolean subtraction represents the annular
	# ribbon as nested outer/hole polygons and can otherwise select the whole room
	# as a solid collision body.
	var island_region := inner_loop.duplicate() if spec.get("seed_obstacles", false) else _island_region(room_polygon, clipped, inner_loop)
	_build_island_prop(root, spec, island_region, inner_loop, centerline)

	# Legacy authored tracks keep their fixed room-corner dressing. Generated
	# tracks choose landmarks from geometry-aware story moments below.
	if not spec.get("seed_obstacles", false):
		_add_corner_set_pieces(root, spec, room_polygon, clipped)

	# Room walls (real furniture edges along the room outline)
	var edge_texture := String(spec.get("edge_texture", "res://assets/textures/kitchen/counter_edge.png"))
	var wall_index := 0
	for index in room_polygon.size():
		var from: Vector2 = room_polygon[index]
		var to: Vector2 = room_polygon[(index + 1) % room_polygon.size()]
		var mid := (from + to) * 0.5
		var edge_vector := to - from
		var length := edge_vector.length()
		if length < 1.0:
			continue
		_add_wall_segment(root, "Wall%d" % wall_index, mid, length, atan2(edge_vector.y, edge_vector.x), edge_texture)
		wall_index += 1

	# Checkpoints along the arc, aligned to the tangent. The last lap gate sits
	# slightly past the corner rejoin so its recovery point stays on a straight.
	var gate_fractions: Array = spec.get("gate_fractions", [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.84])
	var arc := _arc_lengths(centerline)
	var total := arc[arc.size() - 1]
	var start := centerline[0]
	var start_tangent := (centerline[1] - centerline[centerline.size() - 1]).normalized()
	var gate_samples := PackedVector2Array()
	for gate_index in GATE_COUNT:
		var fraction: float = gate_fractions[gate_index]
		var sample := _sample_at_arc(centerline, arc, total * fraction)
		gate_samples.append(sample)
		var tangent := _tangent_at_arc(centerline, arc, total * fraction)
		var rotation := atan2(-tangent.y, -tangent.x)
		var is_finish := gate_index == 0
		var name := "Checkpoint0Finish" if is_finish else "Checkpoint%d" % gate_index
		_add_cp(root, name, sample, rotation, gate_index, is_finish, atan2(tangent.x, -tangent.y))

	# Bold checker strip at the finish gate (two alternating rows across the corridor)
	var finish_normal := start_tangent.rotated(PI * 0.5)
	var strip_half := Vector2(finish_normal.y, -finish_normal.x) * HALF_WIDTH
	var checker_white := PackedVector2Array()
	var checker_black := PackedVector2Array()
	var checker_count := 6
	var cell_half := Vector2(finish_normal.y, -finish_normal.x) * (HALF_WIDTH / float(checker_count))
	for row in 2:
		var row_center := start + finish_normal * (30.0 - float(row) * 60.0)
		for column in checker_count:
			var cell_center := row_center + cell_half * (float(column) * 2.0 - float(checker_count - 1))
			var cell_color := Color("f5eec8") if (column + row) % 2 == 0 else Color("0d0f14")
			var target: PackedVector2Array = checker_white if (column + row) % 2 == 0 else checker_black
			target.append(cell_center + finish_normal * 30.0 + cell_half)
			target.append(cell_center + finish_normal * 30.0 - cell_half)
			target.append(cell_center - finish_normal * 30.0 - cell_half)
			target.append(cell_center - finish_normal * 30.0 + cell_half)
	_add_polygon(root, "StartFinishWhite", checker_white, Color("f5eec8"), -7)
	_add_polygon(root, "StartFinishBlack", checker_black, Color("0d0f14"), -6)

	# Follow the centerline arc rather than extending one start tangent through a
	# nearby corner. This keeps every grid slot inside the drivable corridor on
	# technical layouts in both directions.
	var forward_positions: Array[Vector2] = []
	var forward_rotations: Array[float] = []
	for grid_distance: float in [100.0, 220.0]:
		var grid_sample := _sample_at_arc(centerline, arc, grid_distance)
		var grid_tangent := _tangent_at_arc(centerline, arc, grid_distance)
		var grid_normal := grid_tangent.rotated(PI * 0.5)
		forward_positions.append(grid_sample - grid_normal * 45.0)
		forward_positions.append(grid_sample + grid_normal * 45.0)
		forward_rotations.append(atan2(grid_tangent.x, -grid_tangent.y))
		forward_rotations.append(atan2(grid_tangent.x, -grid_tangent.y))
	_add_grid(root, "GridForward", 0.0, forward_positions, forward_rotations)
	var reverse_positions: Array[Vector2] = []
	var reverse_rotations: Array[float] = []
	for grid_distance: float in [45.0, 120.0]:
		var target_arc := maxf(total - grid_distance, 0.0)
		var grid_sample := _sample_at_arc(centerline, arc, target_arc)
		var grid_tangent := _tangent_at_arc(centerline, arc, target_arc)
		var grid_normal := grid_tangent.rotated(PI * 0.5)
		reverse_positions.append(grid_sample - grid_normal * 45.0)
		reverse_positions.append(grid_sample + grid_normal * 45.0)
		reverse_rotations.append(atan2(-grid_tangent.x, grid_tangent.y))
		reverse_rotations.append(atan2(-grid_tangent.x, grid_tangent.y))
	_add_grid(root, "GridReverse", 0.0, reverse_positions, reverse_rotations)

	var generated_moments := {}
	if spec.get("seed_obstacles", false):
		generated_moments = _analyze_track_moments(centerline, gate_samples)

	# Racing line the AI follows (curvature-offset ideal path, stored invisibly).
	# Generated AI stays on the safe side of the optional risk shortcut.
	_build_racing_line(root, centerline, generated_moments)

	if spec.get("seed_obstacles", false):
		_compose_generated_story(root, spec, centerline, inner_loop, outer_loop, room_polygon, gate_samples, generated_moments)
	else:
		# Canonical/static tracks retain their authored legacy dressing.
		_fill_island(root, spec, inner_loop, centerline)
		if not OS.get_environment("PC_NO_BOUNDARY") == "1":
			_line_boundary_props(root, spec, centerline, outer_loop, clipped, room_polygon)
		_add_paperclip_line(root, spec, centerline, outer_loop, room_polygon)
		var decal_rng := RandomNumberGenerator.new()
		decal_rng.seed = int(spec.get("seed", 0)) * 31 + 7
		_scatter_decals(root, spec, room_polygon, corridor, decal_rng)

		# Track obstacles (real props with collision)
		var obstacles: Dictionary = spec["obstacles"]
		for obstacle_name: String in obstacles:
			var data: Dictionary = obstacles[obstacle_name]
			_add_obstacle(root, obstacle_name, data["pos"], float(data["r"]), String(data["tex"]))

		# Apron furniture: real objects off the racing line, some with collision
		var apron_props: Array = spec.get("apron_props", [])
		for prop: Dictionary in apron_props:
			_add_prop_with_collision(root, prop["pos"], float(prop["r"]), String(prop["tex"]))

		# The old cross-theme hardware edge belongs only to canonical static tracks.
		var outer_loop2 := left if absf(_polygon_area(left)) > absf(_polygon_area(right)) else right
		var prop_textures := [
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/imagine/hazard_workshop_socket.png",
			"res://assets/textures/kitchen/sponge_wet.png",
		]
		var hardware_index := 0
		for index in range(24, centerline.size() - 24, 6):
			var tangent := (centerline[(index + 1) % centerline.size()] - centerline[(index - 1 + centerline.size()) % centerline.size()]).normalized()
			if absf(tangent.x) < 0.45 or absf(tangent.y) < 0.45:
				continue
			var outward := (outer_loop2[index] - centerline[index]).normalized()
			var prop_position := centerline[index] + outward * 175.0
			if not Geometry2D.is_point_in_polygon(prop_position, room_polygon):
				continue
			if not Geometry2D.is_point_in_polygon(prop_position, corridor):
				_add_prop_with_collision(root, prop_position, 30.0, prop_textures[hardware_index % prop_textures.size()])
				hardware_index += 1


	# Start banner above the finish line
	_add_start_banner(root, start, start_tangent, corridor)


static func _build_island_prop(root: Node2D, spec: Dictionary, region: PackedVector2Array, inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> void:
	var expanded := PackedVector2Array()
	if spec.get("seed_obstacles", false):
		# Geometry2D already returns a simple central polygon. Procedural concave
		# loops can make a naively offset inner centerline self-intersect, which is
		# not a valid CollisionPolygon2D; use the clipped island itself instead.
		expanded = region.duplicate()
	else:
		var last := Vector2(INF, INF)
		for index in inner_loop.size():
			var toward_track := (centerline[index] - inner_loop[index]).normalized()
			var point := inner_loop[index] + toward_track * float(spec.get("island_expansion", 10.0))
			if point.distance_to(last) > 3.0:
				expanded.append(point)
				last = point
	var barrier := StaticBody2D.new()
	barrier.name = "InnerBarrier"
	barrier.collision_layer = 2
	barrier.set_meta("boundary_polygon", expanded)
	root.add_child(barrier)
	if spec.get("seed_obstacles", false):
		# A generated inner offset can be concave enough that solid polygon
		# decomposition fails. A closed concave segment chain is valid on a static
		# body and still makes the household island a physical boundary.
		var segments := PackedVector2Array()
		for index in expanded.size():
			segments.append(expanded[index])
			segments.append(expanded[(index + 1) % expanded.size()])
		var boundary_shape := ConcavePolygonShape2D.new()
		boundary_shape.segments = segments
		var boundary_collision := CollisionShape2D.new()
		boundary_collision.name = "BoundaryCollision"
		boundary_collision.shape = boundary_shape
		barrier.add_child(boundary_collision)
	else:
		var barrier_collision := CollisionPolygon2D.new()
		barrier_collision.polygon = expanded
		barrier.add_child(barrier_collision)

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in region:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))

	var visual := Polygon2D.new()
	visual.name = "IslandProp"
	visual.z_index = -9
	visual.polygon = region
	var prop_texture := String(spec.get("prop_texture", ""))
	var texture := load(prop_texture) as Texture2D if not prop_texture.is_empty() else null
	if texture:
		visual.texture = texture
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		visual.modulate = Color(1.2, 1.2, 1.2)
		var uvs := PackedVector2Array()
		for point: Vector2 in region:
			uvs.append(Vector2(
				(point.x - min_point.x) / maxf(max_point.x - min_point.x, 1.0),
				(point.y - min_point.y) / maxf(max_point.y - min_point.y, 1.0)
			))
		visual.uv = uvs
	else:
		visual.color = spec["island"]
	root.add_child(visual)


static func _island_region(room_polygon: PackedVector2Array, ribbon: PackedVector2Array, hint_polygon: PackedVector2Array) -> PackedVector2Array:
	var pieces: Array[PackedVector2Array] = Geometry2D.clip_polygons(room_polygon, ribbon)
	var hint_centroid := Vector2.ZERO
	for point: Vector2 in hint_polygon:
		hint_centroid += point
	hint_centroid /= float(hint_polygon.size())
	var best := PackedVector2Array()
	var best_score := -1.0
	for piece: PackedVector2Array in pieces:
		var score := 0.0
		for sample in 40:
			var index := int(float(sample) * float(hint_polygon.size()) / 40.0)
			var hint_point: Vector2 = hint_polygon[index].lerp(hint_centroid, 0.3)
			if Geometry2D.is_point_in_polygon(hint_point, piece):
				score += 1.0
		if score > best_score:
			best_score = score
			best = piece
	return best


static func _rounded_rect_points(center: Vector2, size: Vector2, radius: float, corner_segments: int) -> PackedVector2Array:
	var half := size * 0.5 - Vector2(radius, radius)
	var points := PackedVector2Array()
	for corner: Dictionary in [
		{"c": center + Vector2(half.x, half.y), "start": 0.0},
		{"c": center + Vector2(-half.x, half.y), "start": PI * 0.5},
		{"c": center - half, "start": PI},
		{"c": center + Vector2(half.x, -half.y), "start": PI * 1.5},
	]:
		for seg in corner_segments + 1:
			var angle: float = corner["start"] + PI * 0.5 * float(seg) / float(corner_segments)
			points.append(corner["c"] + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var next := (index + 1) % points.size()
		total += points[index].x * points[next].y - points[next].x * points[index].y
	return total * 0.5


static func _simple_island_loop(points: PackedVector2Array) -> PackedVector2Array:
	# Normal offsets fold over themselves at concave corners. Running the contour
	# through Clipper splits those folds into simple polygons; the largest contour
	# is the central island and the smaller pieces are offset artifacts.
	var pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(points, points)
	var result := PackedVector2Array()
	var largest_area := 0.0
	for piece: PackedVector2Array in pieces:
		var area := absf(_polygon_area(piece))
		if piece.size() >= 3 and area > largest_area:
			result = piece
			largest_area = area
	return result if not result.is_empty() else points


static func _arc_lengths(centerline: PackedVector2Array) -> PackedFloat32Array:
	var arc := PackedFloat32Array()
	arc.append(0.0)
	var running := 0.0
	for index in range(1, centerline.size()):
		running += centerline[index].distance_to(centerline[index - 1])
		arc.append(running)
	return arc


static func _sample_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	for index in range(1, arc.size()):
		if arc[index] >= target:
			var fraction := (target - arc[index - 1]) / maxf(arc[index] - arc[index - 1], 0.001)
			return centerline[index - 1].lerp(centerline[index], fraction)
	return centerline[centerline.size() - 1]


static func _tangent_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	for index in range(1, arc.size()):
		if arc[index] >= target:
			return (centerline[index] - centerline[index - 1]).normalized()
	return (centerline[0] - centerline[centerline.size() - 1]).normalized()


static func _rect_points(center: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	])


static func _add_polygon(parent: Node, node_name: String, points: PackedVector2Array, color: Color, z: int) -> void:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	polygon.color = color
	polygon.z_index = z
	parent.add_child(polygon)


static func spec_wall_side() -> Color:
	return Color("3a4656")


static func _add_wall_segment(parent: Node, node_name: String, position: Vector2, length: float, rotation: float, edge_texture_path: String) -> void:
	var wall := StaticBody2D.new()
	wall.name = node_name
	wall.position = position
	wall.rotation = rotation
	wall.collision_layer = 2
	parent.add_child(wall)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length + 60.0, 50.0)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	wall.add_child(cs)
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = _rect_points(Vector2.ZERO, Vector2(length + 60.0, 50.0))
	visual.color = Color("0e1524")
	wall.add_child(visual)
	var side_face := Polygon2D.new()
	side_face.name = "SideFace"
	side_face.polygon = _rect_points(Vector2(0.0, -14.0), Vector2(length + 60.0, 22.0))
	side_face.color = Color("262e3a")
	wall.add_child(side_face)
	var edge_texture_side := load(edge_texture_path) as Texture2D
	if edge_texture_side:
		var side_strip := Sprite2D.new()
		side_strip.name = "SideStrip"
		side_strip.texture = edge_texture_side
		side_strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		side_strip.position = Vector2(0.0, -14.0)
		var side_tiles := maxi(1, int(ceil((length + 60.0) / 1024.0)))
		side_strip.scale = Vector2((length + 60.0) / (1024.0 * float(side_tiles)), 34.0 / 220.0)
		side_strip.modulate = Color(0.85, 0.85, 0.85)
		wall.add_child(side_strip)
	var top_lip := Polygon2D.new()
	top_lip.name = "TopLip"
	top_lip.polygon = _rect_points(Vector2(0.0, -28.0), Vector2(length + 60.0, 5.0))
	top_lip.color = Color("e8d9b8", 0.85)
	wall.add_child(top_lip)
	var edge_texture := load(edge_texture_path) as Texture2D
	if edge_texture:
		var tile_count := maxi(1, int(ceil((length + 60.0) / 1024.0)))
		for tile in tile_count:
			var strip := Sprite2D.new()
			strip.name = "EdgeStrip"
			strip.texture = edge_texture
			strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var offset := (float(tile) - float(tile_count - 1) * 0.5) * ((length + 60.0) / float(tile_count))
			strip.position = Vector2(offset, 0.0)
			strip.scale = Vector2((length + 60.0) / (1024.0 * float(tile_count)), 50.0 / 220.0)
			wall.add_child(strip)


static func _add_cp(parent: Node, node_name: String, position: Vector2, rotation: float, index: int, is_finish: bool, recovery_rotation: float) -> void:
	var cp := (load(CHECKPOINT_SCENE) as PackedScene).instantiate()
	cp.name = node_name
	cp.position = position
	cp.rotation = rotation
	cp.set("checkpoint_index", index)
	cp.set("is_finish_line", is_finish)
	cp.set("recovery_rotation", recovery_rotation)
	cp.set("recovery_offset", 70.0)
	if not is_finish:
		var collision := cp.get_node("CollisionShape2D") as CollisionShape2D
		var forgiving := RectangleShape2D.new()
		forgiving.size = Vector2(70.0, 300.0)
		collision.shape = forgiving
	parent.add_child(cp)


static func _add_grid(parent: Node, node_name: String, rotation: float, positions: Array, rotations: Array = []) -> void:
	var grid := Node2D.new()
	grid.name = node_name
	parent.add_child(grid)
	for index in positions.size():
		var marker := Node2D.new()
		marker.name = str(index)
		marker.position = positions[index]
		marker.rotation = float(rotations[index]) if index < rotations.size() else rotation
		grid.add_child(marker)


static func _scatter_decals(root: Node2D, spec: Dictionary, room_polygon: PackedVector2Array, corridor: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var decals: Array = spec.get("decals", [])
	if decals.is_empty():
		return
	for decal in 26:
		var position := Vector2(rng.randf_range(-830.0, 830.0), rng.randf_range(-530.0, 530.0))
		if not Geometry2D.is_point_in_polygon(position, room_polygon):
			continue
		if Geometry2D.is_point_in_polygon(position, corridor):
			continue
		var sprite := Sprite2D.new()
		sprite.name = "Decal"
		sprite.texture = load(String(decals[rng.randi_range(0, decals.size() - 1)])) as Texture2D
		if sprite.texture == null:
			sprite.free()
			continue
		sprite.scale = Vector2.ONE * rng.randf_range(0.5, 1.1)
		sprite.rotation = rng.randf_range(0.0, TAU)
		sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.4, 0.9))
		sprite.z_index = -15
		root.add_child(sprite)


static func _scatter_seed_props(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, corridor: PackedVector2Array, gate_samples: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var textures: Array = spec.get("scatter_textures", [])
	if textures.is_empty():
		return
	var count := centerline.size()

	var clear_of_gates := _seed_clear_of_gates.bind(gate_samples)

	# a) corridor slalom: a few props on straights, offset from the racing line
	var corridor_props := PackedVector2Array()
	for attempt in 200:
		var index := rng.randi_range(0, count - 1)
		var sample := centerline[index]
		if sample.distance_to(centerline[0]) < 380.0:
			continue
		if not clear_of_gates.call(sample):
			continue
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var normal := tangent.rotated(PI * 0.5)
		var candidate := sample + normal * (95.0 if rng.randf() < 0.5 else -95.0)
		var too_close := false
		for placed: Vector2 in corridor_props:
			if placed.distance_to(candidate) < 240.0:
				too_close = true
				break
		if too_close or not Geometry2D.is_point_in_polygon(candidate, corridor):
			continue
		corridor_props.append(candidate)
		if corridor_props.size() >= 3:
			break
	for position: Vector2 in corridor_props:
		_add_scatter_prop(root, position, 34.0, String(textures[rng.randi_range(0, textures.size() - 1)]))

	# b) apron clutter outside the loop
	var apron_props := PackedVector2Array()
	for attempt in 400:
		var candidate := Vector2(rng.randf_range(-830.0, 830.0), rng.randf_range(-530.0, 530.0))
		if not Geometry2D.is_point_in_polygon(candidate, room_polygon):
			continue
		if Geometry2D.is_point_in_polygon(candidate, corridor):
			continue
		if _point_in_loop(candidate, centerline):
			continue
		if not clear_of_gates.call(candidate):
			continue
		var too_close := false
		for placed: Vector2 in apron_props:
			if placed.distance_to(candidate) < 90.0:
				too_close = true
				break
		if too_close:
			continue
		apron_props.append(candidate)
		if apron_props.size() >= 10:
			break
	for position: Vector2 in apron_props:
		_add_prop_with_collision(root, position, 30.0, String(textures[rng.randi_range(0, textures.size() - 1)]))


static func _compose_generated_story(
		root: Node2D,
		spec: Dictionary,
		centerline: PackedVector2Array,
		inner_loop: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		moments: Dictionary
) -> void:
	var story: Dictionary = spec["story_kit"]
	var container := Node2D.new()
	container.name = "GeneratedMoments"
	container.set_meta("story_id", StringName(story["id"]))
	root.add_child(container)

	var occupied: Array[Dictionary] = []
	var opening_index := _build_opening_landmark(
		container,
		story,
		spec,
		centerline,
		outer_loop,
		room_polygon,
		gate_samples,
		occupied
	)
	var reserved_unique_assets := {}
	for formation_data: Dictionary in story["island"]:
		if StringName(formation_data["quantity"]) == &"unique":
			reserved_unique_assets[String(formation_data["asset"])] = true
	var opening := container.get_node("OpeningLandmark")
	if int(opening.get_meta("placed_count", 0)) == 1:
		reserved_unique_assets[String(opening.get_meta("asset_path", ""))] = true
	_build_island_story(container, story, spec, centerline, inner_loop, room_polygon, gate_samples, occupied)
	_build_track_formation(
		container,
		"ObjectLine",
		story["object_line"],
		&"many",
		int(moments["longest_straight"]),
		centerline,
		outer_loop,
		room_polygon,
		gate_samples,
		occupied
	)
	_build_track_formation(
		container,
		"SparseDelimiter",
		story["delimiter"],
		&"few",
		int(moments["early_conflict_forward"]),
		centerline,
		outer_loop,
		room_polygon,
		gate_samples,
		occupied
	)
	_build_corner_landmarks(container, story, spec, moments["corners"], centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied)
	_build_room_dressing(container, story, spec, centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied)
	_build_generated_surfaces(root, container, story, moments, centerline)
	_build_finish_moments(container, centerline)

	var hazard_paths := {}
	for direction: String in ["forward", "reverse"]:
		var hazard_index := int(moments["early_conflict_%s" % direction])
		var hazard_path := _crossing_path(centerline, hazard_index, 82.0)
		var conflict := Node2D.new()
		conflict.name = "EarlyConflict%s" % direction.capitalize()
		conflict.position = centerline[hazard_index]
		conflict.set_meta("moment_kind", &"early_conflict")
		conflict.set_meta("direction", StringName(direction))
		conflict.set_meta("centerline_index", hazard_index)
		conflict.set_meta("lap_fraction", float(moments["early_conflict_%s_fraction" % direction]))
		conflict.set_meta("path", hazard_path)
		container.add_child(conflict)
		hazard_paths[direction] = hazard_path
	root.set_meta("generated_hazard_paths", hazard_paths)
	root.set_meta("generated_hazard_path", hazard_paths["forward"])
	root.set_meta("generated_moment_indices", {
		"opening": opening_index,
		"early_conflict_forward": int(moments["early_conflict_forward"]),
		"early_conflict_reverse": int(moments["early_conflict_reverse"]),
		"longest_straight": int(moments["longest_straight"]),
		"second_straight": int(moments["second_straight"]),
		"corners": moments["corners"],
		"shortcut": int(moments["shortcut"]),
		"technical": int(moments["technical"]),
		"speed": 0,
		"finish": 0,
		"hazard": int(moments["early_conflict_forward"]),
	})


static func _analyze_track_moments(centerline: PackedVector2Array, gate_samples: PackedVector2Array) -> Dictionary:
	var count := centerline.size()
	var arc_positions := _centerline_arc_positions(centerline)
	var total_length := arc_positions[arc_positions.size() - 1] + centerline[centerline.size() - 1].distance_to(centerline[0])
	var conflict_forward := _pick_conflict_candidate(centerline, gate_samples, arc_positions, total_length, 0.14, 0.23)
	var conflict_reverse := _pick_conflict_candidate(centerline, gate_samples, arc_positions, total_length, 0.77, 0.86)
	var straight_candidates: Array[Dictionary] = []
	var corner_candidates: Array[Dictionary] = []
	for index in range(0, count, 2):
		var turn := _turn_strength(centerline, index, 9)
		var chord := centerline[posmod(index + 16, count)].distance_to(centerline[posmod(index - 16, count)])
		straight_candidates.append({"index": index, "score": chord - turn * 720.0})
		corner_candidates.append({"index": index, "score": turn})
	straight_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]) if is_equal_approx(float(a["score"]), float(b["score"])) else float(a["score"]) > float(b["score"]))
	corner_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]) if is_equal_approx(float(a["score"]), float(b["score"])) else float(a["score"]) > float(b["score"]))

	var longest := _pick_straight_candidate(straight_candidates, centerline, gate_samples, [0], 30)
	var second := _pick_straight_candidate(straight_candidates, centerline, gate_samples, [0, longest], 48)
	var corners := PackedInt32Array()
	for candidate: Dictionary in corner_candidates:
		var index := int(candidate["index"])
		if _cyclic_index_distance(index, 0, count) < 24:
			continue
		if _cyclic_index_distance(index, conflict_forward, count) < 24 or _cyclic_index_distance(index, conflict_reverse, count) < 24:
			continue
		var separated := true
		for chosen: int in corners:
			if _cyclic_index_distance(index, chosen, count) < 38:
				separated = false
				break
		if not separated:
			continue
		corners.append(index)
		if corners.size() >= 4:
			break
	for fallback_fraction: float in [0.25, 0.5, 0.75]:
		if corners.size() >= 2:
			break
		var fallback := int(round(float(count) * fallback_fraction)) % count
		var separated := _cyclic_index_distance(fallback, conflict_forward, count) >= 24 and _cyclic_index_distance(fallback, conflict_reverse, count) >= 24
		for chosen: int in corners:
			if _cyclic_index_distance(fallback, chosen, count) < 38:
				separated = false
		if separated:
			corners.append(fallback)
	while corners.size() < 2:
		corners.append(posmod(72 + corners.size() * 96, count))

	var shortcut := int(corners[0])
	var shortcut_gain := -INF
	for corner: int in corners:
		var geometry := _shortcut_lane_geometry(centerline, corner)
		var gain := float(geometry["safe_length"]) - float(geometry["shortcut_length"])
		if gain > shortcut_gain:
			shortcut_gain = gain
			shortcut = corner
	var technical := int(corners[0])
	for corner: int in corners:
		if corner != shortcut:
			technical = corner
			break
	return {
		"opening": 0,
		"early_conflict_forward": conflict_forward,
		"early_conflict_reverse": conflict_reverse,
		"early_conflict_forward_fraction": arc_positions[conflict_forward] / maxf(total_length, 1.0),
		"early_conflict_reverse_fraction": 1.0 - arc_positions[conflict_reverse] / maxf(total_length, 1.0),
		"longest_straight": longest,
		"second_straight": second,
		"corners": corners,
		"shortcut": shortcut,
		"technical": technical,
	}


static func _centerline_arc_positions(centerline: PackedVector2Array) -> PackedFloat32Array:
	var positions := PackedFloat32Array([0.0])
	for index in range(1, centerline.size()):
		positions.append(positions[index - 1] + centerline[index - 1].distance_to(centerline[index]))
	return positions


static func _pick_conflict_candidate(
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		arc_positions: PackedFloat32Array,
		total_length: float,
		minimum_fraction: float,
		maximum_fraction: float
) -> int:
	var best_index := int(round(float(centerline.size()) * (minimum_fraction + maximum_fraction) * 0.5))
	var best_score := -INF
	for index in range(0, centerline.size(), 2):
		var fraction := arc_positions[index] / maxf(total_length, 1.0)
		if fraction < minimum_fraction or fraction > maximum_fraction:
			continue
		var turn := _turn_strength(centerline, index, 7)
		var chord := centerline[posmod(index + 10, centerline.size())].distance_to(centerline[posmod(index - 10, centerline.size())])
		var gate_clearance := INF
		for gate: Vector2 in gate_samples:
			gate_clearance = minf(gate_clearance, centerline[index].distance_to(gate))
		var score := chord - turn * 540.0 + minf(gate_clearance, 180.0) * 0.35
		if score > best_score or (is_equal_approx(score, best_score) and index < best_index):
			best_score = score
			best_index = index
	return best_index


static func _build_opening_landmark(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> int:
	var opening := Node2D.new()
	opening.name = "OpeningLandmark"
	parent.add_child(opening)
	var assets: Array = story["landmarks"]
	var asset_index := posmod(_mix_seed(int(spec["requested_seed"]), "opening_asset"), assets.size())
	var asset_path := String(assets[asset_index])
	opening.set_meta("asset_path", asset_path)
	opening.set_meta("semantic_quantity", &"unique")
	opening.set_meta("requested_count", 1)
	var base_radius := _asset_radius(asset_path, 64.0)
	var size_scale := minf(1.0, 72.0 / maxf(base_radius, 1.0))
	var radius := base_radius * size_scale
	var preferred := int(round(float(centerline.size()) * 0.11))
	var selected_index := preferred
	var placed_count := 0
	# Search the first quarter of the lap rather than trusting one index; long
	# landmarks do not fit on the outer side of every narrow-room opening.
	for index_attempt in 18:
		var index_offset := (index_attempt + 1) / 2 * 4
		var index_direction := -1 if index_attempt % 2 == 0 else 1
		var index := posmod(preferred + index_offset * index_direction, centerline.size())
		var tangent := _sample_tangent(centerline, index)
		var outward := (outer_loop[index] - centerline[index]).normalized()
		for placement_attempt in 12:
			var side := 1.0 if placement_attempt % 2 == 0 else -1.0
			var along := tangent * (float(placement_attempt / 4) - 1.0) * 30.0
			var offset := HALF_WIDTH + radius + 18.0 + float((placement_attempt / 2) % 2) * 12.0
			var candidate := centerline[index] + outward * side * offset + along
			if not _inside_polygon_with_radius(candidate, radius, room_polygon):
				continue
			if _distance_to_centerline(candidate, centerline) < HALF_WIDTH + radius + 7.0:
				continue
			if not _clear_of_points(candidate, gate_samples, 24.0 + radius):
				continue
			if not _clear_of_recovery_lanes(candidate, radius, centerline, gate_samples):
				continue
			if not _clear_of_occupied(candidate, radius, occupied):
				continue
			_add_generated_prop(opening, "Focal", candidate, asset_path, tangent.angle(), &"opening", &"unique", 0, size_scale)
			occupied.append({"position": candidate, "radius": radius})
			selected_index = index
			placed_count = 1
			break
		if placed_count == 1:
			break
	if placed_count == 0:
		var exhaustive := _best_trackside_position(preferred, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
		if bool(exhaustive["found"]):
			var candidate: Vector2 = exhaustive["position"]
			selected_index = int(exhaustive["index"])
			_add_generated_prop(opening, "Focal", candidate, asset_path, _sample_tangent(centerline, selected_index).angle(), &"opening", &"unique", 0, size_scale)
			occupied.append({"position": candidate, "radius": radius})
			placed_count = 1
	opening.set_meta("centerline_index", selected_index)
	opening.set_meta("placed_count", placed_count)
	return selected_index


static func _pick_straight_candidate(
		candidates: Array[Dictionary],
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		excluded: Array,
		minimum_separation: int
) -> int:
	for candidate: Dictionary in candidates:
		var index := int(candidate["index"])
		var allowed := true
		for excluded_index: int in excluded:
			if _cyclic_index_distance(index, excluded_index, centerline.size()) < minimum_separation:
				allowed = false
				break
		if not allowed or not _clear_of_points(centerline[index], gate_samples, 175.0):
			continue
		return index
	return posmod(minimum_separation * maxi(excluded.size(), 1), centerline.size())


static func _turn_strength(centerline: PackedVector2Array, index: int, span: int) -> float:
	var count := centerline.size()
	var behind := (centerline[index] - centerline[posmod(index - span, count)]).normalized()
	var ahead := (centerline[posmod(index + span, count)] - centerline[index]).normalized()
	return absf(behind.angle_to(ahead))


static func _cyclic_index_distance(first: int, second: int, count: int) -> int:
	var direct := absi(first - second)
	return mini(direct, count - direct)


static func _safe_moment_index(centerline: PackedVector2Array, preferred: int, gate_samples: PackedVector2Array, clearance: float) -> int:
	var count := centerline.size()
	for distance in range(0, 31, 2):
		for direction in [-1, 1]:
			var index := posmod(preferred + distance * direction, count)
			if _cyclic_index_distance(index, 0, count) < 26:
				continue
			if _clear_of_points(centerline[index], gate_samples, clearance):
				return index
	return preferred


static func _build_island_story(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		centerline: PackedVector2Array,
		inner_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> void:
	var cluster := Node2D.new()
	cluster.name = "IslandFocalCluster"
	cluster.set_meta("story_id", StringName(story["id"]))
	parent.add_child(cluster)
	var anchor := _island_anchor(inner_loop, centerline)
	var island_bounds := _polygon_bounds_rect(inner_loop)
	var scene_angle := -PI * 0.5 if island_bounds.size.x > island_bounds.size.y else 0.0
	if _mix_seed(int(spec["requested_seed"]), String(story["id"])) % 2 == 1:
		scene_angle += PI
	var placement_region := &"island"
	var focal_data: Dictionary = story["island"][0]
	var focal_path := String(focal_data["asset"])
	var focal_base_radius := _asset_radius(focal_path, 24.0)
	var focal_scale := minf(1.0, 72.0 / maxf(focal_base_radius, 1.0))
	var focal_radius := focal_base_radius * focal_scale
	var focal_offset: Vector2 = focal_data.get("offset", Vector2.ZERO)
	var focal_preferred := anchor + focal_offset.rotated(scene_angle)
	var island_fit := _best_island_position(focal_preferred, focal_radius, room_polygon, inner_loop, occupied)
	if not bool(island_fit["found"]):
		var apron_fit := _best_offtrack_position(focal_preferred, focal_radius, room_polygon, centerline, gate_samples, occupied)
		if bool(apron_fit["found"]):
			placement_region = &"apron"
			anchor += (apron_fit["position"] as Vector2) - focal_preferred
	cluster.set_meta("placement_region", placement_region)
	for formation_data: Dictionary in story["island"]:
		var quantity := StringName(formation_data["quantity"])
		var requested_count := _bounded_quantity_count(quantity, int(formation_data["count"]))
		var formation := Node2D.new()
		formation.name = "Formation%s" % String(quantity).to_pascal_case()
		formation.set_meta("semantic_quantity", quantity)
		formation.set_meta("requested_count", requested_count)
		formation.set_meta("asset_path", String(formation_data["asset"]))
		cluster.add_child(formation)
		var asset_path := String(formation_data["asset"])
		var base_radius := _asset_radius(asset_path, 24.0)
		var maximum_radius := 72.0 if quantity == &"unique" else (42.0 if quantity == &"few" else 18.0)
		var size_scale := minf(1.0, maximum_radius / maxf(base_radius, 1.0))
		var radius := base_radius * size_scale
		var authored_offset: Vector2 = formation_data.get("offset", Vector2.ZERO)
		var semantic_spread := 1.45 if quantity == &"many" else (1.65 if quantity == &"few" else 1.0)
		var target: Vector2 = anchor + (authored_offset * semantic_spread).rotated(scene_angle)
		var placed_count := 0
		for item_index in requested_count:
			var local_offset := _semantic_formation_offset(StringName(formation_data["formation"]), item_index, requested_count, radius)
			var placed := false
			var preferred := target + local_offset.rotated(scene_angle)
			for attempt in 36:
				var fallback_distance := float((attempt + 3) / 4) * maxf(radius * 0.6, 20.0)
				var fallback_angle := scene_angle + float(attempt) * 2.399963 + float(item_index) * 0.41
				var fallback := Vector2.ZERO if attempt == 0 else Vector2.RIGHT.rotated(fallback_angle) * fallback_distance
				var candidate := preferred + fallback
				var safe := _placement_is_safe(candidate, radius, room_polygon, inner_loop, occupied) if placement_region == &"island" else _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied)
				if not safe:
					continue
				_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, placement_region, quantity, item_index, size_scale)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
				break
			if not placed:
				var exhaustive := _best_island_position(preferred, radius, room_polygon, inner_loop, occupied) if placement_region == &"island" else _best_offtrack_position(preferred, radius, room_polygon, centerline, gate_samples, occupied)
				if bool(exhaustive["found"]):
					var candidate: Vector2 = exhaustive["position"]
					_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, placement_region, quantity, item_index, size_scale)
					occupied.append({"position": candidate, "radius": radius})
					placed_count += 1
					placed = true
			if not placed and placement_region == &"island":
				var apron_fit := _best_offtrack_position(preferred, radius, room_polygon, centerline, gate_samples, occupied)
				if bool(apron_fit["found"]):
					var candidate: Vector2 = apron_fit["position"]
					_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, &"apron", quantity, item_index, size_scale)
					occupied.append({"position": candidate, "radius": radius})
					placed_count += 1
					placed = true
					cluster.set_meta("placement_region", &"mixed")
			if not placed and quantity == &"unique":
				break
		formation.set_meta("placed_count", placed_count)


static func _bounded_quantity_count(quantity: StringName, requested: int) -> int:
	match quantity:
		&"unique":
			return 1
		&"few":
			return clampi(requested, 2, 3)
		&"many":
			return clampi(requested, 8, 20)
	return clampi(requested, 1, 20)


static func _semantic_formation_offset(formation: StringName, index: int, count: int, radius: float) -> Vector2:
	var spacing := maxf(radius * 2.0 + 9.0, 25.0)
	match formation:
		&"line":
			return Vector2((float(index) - float(count - 1) * 0.5) * spacing, 0.0)
		&"arc":
			var arc_angle := lerpf(-1.05, 1.05, float(index) / maxf(float(count - 1), 1.0))
			var arc_radius := maxf(54.0, spacing * float(count) * 0.27)
			return Vector2(cos(arc_angle), sin(arc_angle)) * arc_radius - Vector2(arc_radius * 0.55, 0.0)
		&"cluster":
			var columns := ceili(sqrt(float(count)))
			var row := index / columns
			var column := index % columns
			var rows := ceili(float(count) / float(columns))
			return Vector2(
				(float(column) - float(columns - 1) * 0.5) * spacing,
				(float(row) - float(rows - 1) * 0.5) * spacing
			)
	return Vector2.ZERO


static func _island_anchor(inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> Vector2:
	var average := Vector2.ZERO
	var bounds := Rect2(inner_loop[0], Vector2.ZERO)
	for point: Vector2 in inner_loop:
		average += point
		bounds = bounds.expand(point)
	average /= float(inner_loop.size())
	if Geometry2D.is_point_in_polygon(average, inner_loop):
		return average
	var best := average
	var best_clearance := -INF
	for x in 7:
		for y in 7:
			var candidate := bounds.position + Vector2(bounds.size.x * (float(x) + 0.5) / 7.0, bounds.size.y * (float(y) + 0.5) / 7.0)
			if not Geometry2D.is_point_in_polygon(candidate, inner_loop):
				continue
			var clearance := _distance_to_centerline(candidate, centerline)
			if clearance > best_clearance:
				best_clearance = clearance
				best = candidate
	return best


static func _polygon_bounds_rect(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


static func _build_track_formation(
		parent: Node2D,
		node_name: String,
		data: Dictionary,
		quantity: StringName,
		moment_index: int,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> void:
	var formation := Node2D.new()
	formation.name = node_name
	formation.set_meta("semantic_quantity", quantity)
	formation.set_meta("centerline_index", moment_index)
	formation.set_meta("asset_path", String(data["asset"]))
	parent.add_child(formation)
	var requested_count := _bounded_quantity_count(quantity, int(data["count"]))
	formation.set_meta("requested_count", requested_count)
	var asset_path := String(data["asset"])
	var radius := _asset_radius(asset_path, 18.0)
	var sample_step := (5 if radius > 20.0 else (4 if radius > 12.0 else 3)) if quantity == &"many" else maxi(6, ceili((radius * 2.0 + 10.0) / 10.0))
	var placed_count := 0
	for item_index in requested_count:
		var sample_offset := int(round((float(item_index) - float(requested_count - 1) * 0.5) * float(sample_step)))
		var placed := false
		for adjustment_attempt in 17:
			var adjustment_magnitude := (adjustment_attempt + 1) / 2
			var adjustment_direction := -1 if adjustment_attempt % 2 == 0 else 1
			var adjustment := 0 if adjustment_attempt == 0 else adjustment_magnitude * adjustment_direction
			var index := posmod(moment_index + sample_offset + adjustment, centerline.size())
			var tangent := _sample_tangent(centerline, index)
			var outward := (outer_loop[index] - centerline[index]).normalized()
			for attempt in 8:
				var side := 1.0 if attempt % 2 == 0 else -1.0
				var direction := outward * side
				var offset := HALF_WIDTH + radius + 10.0 + float(attempt / 2) * 8.0
				var candidate := centerline[index] + direction * offset
				if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
					continue
				_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, tangent.angle(), &"trackside", quantity, item_index)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
				break
			if placed:
				break
		if not placed:
			var exhaustive := _best_trackside_position(moment_index + sample_offset, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
			if bool(exhaustive["found"]):
				var candidate: Vector2 = exhaustive["position"]
				var index := int(exhaustive["index"])
				_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, _sample_tangent(centerline, index).angle(), &"trackside", quantity, item_index)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
		if not placed:
			continue
	formation.set_meta("placed_count", placed_count)


static func _build_corner_landmarks(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		corner_indices: PackedInt32Array,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		reserved_unique_assets: Dictionary,
		occupied: Array[Dictionary]
) -> void:
	var landmarks := Node2D.new()
	landmarks.name = "CornerLandmarks"
	parent.add_child(landmarks)
	var assets: Array = story["landmarks"]
	var asset_start := posmod(_mix_seed(int(spec["requested_seed"]), "landmark_asset"), assets.size())
	var available_assets: Array[String] = []
	for asset_offset in assets.size():
		var asset_path := String(assets[(asset_start + asset_offset) % assets.size()])
		if not reserved_unique_assets.has(asset_path):
			available_assets.append(asset_path)
	var target_count := mini(1 + posmod(_mix_seed(int(spec["requested_seed"]), "landmarks"), 2), available_assets.size())
	landmarks.set_meta("requested_count", target_count)
	var placed_count := 0
	for corner_slot in corner_indices.size():
		if placed_count >= target_count:
			break
		var index := int(corner_indices[corner_slot])
		var asset_path := available_assets[placed_count]
		var base_radius := _asset_radius(asset_path, 64.0)
		var size_scale := minf(1.0, 72.0 / maxf(base_radius, 1.0))
		var radius := base_radius * size_scale
		var outward := (outer_loop[index] - centerline[index]).normalized()
		for attempt in 12:
			var side := 1.0 if attempt % 2 == 0 else -1.0
			var along := _sample_tangent(centerline, index) * (float(attempt / 4) - 1.0) * 28.0
			var offset := HALF_WIDTH + radius + 18.0 + float((attempt / 2) % 2) * 12.0
			var candidate := centerline[index] + outward * side * offset + along
			if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
				continue
			_add_generated_prop(landmarks, "Landmark%02d" % placed_count, candidate, asset_path, float(corner_slot) * 0.37, &"corner", &"unique", placed_count, size_scale)
			occupied.append({"position": candidate, "radius": radius})
			reserved_unique_assets[asset_path] = true
			placed_count += 1
			break
	while placed_count < target_count:
		var asset_path := available_assets[placed_count]
		var base_radius := _asset_radius(asset_path, 64.0)
		var size_scale := minf(1.0, 72.0 / maxf(base_radius, 1.0))
		var radius := base_radius * size_scale
		var preferred_index := int(corner_indices[mini(placed_count, corner_indices.size() - 1)])
		var exhaustive := _best_trackside_position(preferred_index, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
		if not bool(exhaustive["found"]):
			break
		var candidate: Vector2 = exhaustive["position"]
		var index := int(exhaustive["index"])
		_add_generated_prop(landmarks, "Landmark%02d" % placed_count, candidate, asset_path, _sample_tangent(centerline, index).angle(), &"corner", &"unique", placed_count, size_scale)
		occupied.append({"position": candidate, "radius": radius})
		reserved_unique_assets[asset_path] = true
		placed_count += 1
	landmarks.set_meta("placed_count", placed_count)


static func _build_room_dressing(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		reserved_unique_assets: Dictionary,
		occupied: Array[Dictionary]
) -> void:
	var dressing := Node2D.new()
	dressing.name = "RoomDressing"
	dressing.set_meta("moment_kind", &"ambient")
	dressing.set_meta("semantic_quantity", &"many")
	parent.add_child(dressing)
	var asset_pool := _room_dressing_assets(story, spec, reserved_unique_assets)
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix_seed(int(spec["requested_seed"]), "room_dressing:%s" % String(story["id"]))
	var room_area := absf(_polygon_area(room_polygon))
	var target_pockets := clampi(int(round(room_area / 450000.0)), 4, 6)
	var target_count := target_pockets * 3
	dressing.set_meta("requested_count", target_count)
	var anchors := _room_dressing_anchors(room_polygon, centerline, gate_samples, occupied, target_pockets, rng)
	var placed_count := 0
	for pocket_index in anchors.size():
		var pocket := Node2D.new()
		pocket.name = "Pocket%02d" % pocket_index
		pocket.set_meta("semantic_quantity", &"few")
		dressing.add_child(pocket)
		var anchor: Vector2 = anchors[pocket_index]
		var base_angle := rng.randf_range(0.0, TAU)
		var pocket_count := mini(3, target_count - placed_count)
		var pocket_placed := 0
		for item_index in pocket_count:
			if asset_pool.is_empty():
				break
			var asset_path := String(asset_pool[(placed_count + pocket_index * 3) % asset_pool.size()])
			var base_radius := _asset_radius(asset_path, 24.0)
			var size_scale := minf(1.0, 16.0 / maxf(base_radius, 1.0)) * rng.randf_range(0.86, 1.0)
			var radius := base_radius * size_scale
			var placed := false
			for attempt in 12:
				var ring := 30.0 + float(attempt / 6) * 10.0
				var angle := base_angle + TAU * float(item_index) / float(pocket_count) + TAU * float(attempt % 6) / 18.0
				var candidate := anchor + Vector2.RIGHT.rotated(angle) * ring
				if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
					continue
				_add_generated_prop(pocket, "Item%02d" % item_index, candidate, asset_path, rng.randf_range(0.0, TAU), &"ambient", &"few", placed_count, size_scale)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				pocket_placed += 1
				placed = true
				break
			if not placed:
				continue
		pocket.set_meta("placed_count", pocket_placed)
	var ground_section_count := _build_room_ground_sections(dressing, story, spec, centerline, outer_loop, room_polygon)
	var decal_count := _build_room_floor_details(dressing, spec, centerline, room_polygon, occupied, rng)
	dressing.set_meta("placed_count", placed_count)
	dressing.set_meta("pocket_count", anchors.size())
	dressing.set_meta("ground_section_count", ground_section_count)
	dressing.set_meta("decal_count", decal_count)


static func _room_dressing_assets(story: Dictionary, spec: Dictionary, reserved_unique_assets: Dictionary) -> Array[String]:
	var assets: Array[String] = []
	for asset_path: String in spec.get("island_fill_textures", []):
		if not reserved_unique_assets.has(asset_path) and asset_path not in assets:
			assets.append(asset_path)
	for formation: Dictionary in story["island"]:
		var asset_path := String(formation["asset"])
		if StringName(formation["quantity"]) != &"unique" and asset_path not in assets:
			assets.append(asset_path)
	for field: String in ["object_line", "delimiter"]:
		var asset_path := String(story[field]["asset"])
		if asset_path not in assets:
			assets.append(asset_path)
	return assets


static func _room_dressing_anchors(
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		target_count: int,
		rng: RandomNumberGenerator
) -> PackedVector2Array:
	var bounds := _polygon_bounds_rect(room_polygon)
	var candidates: Array[Dictionary] = []
	for x in 17:
		for y in 11:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 17.0,
				bounds.size.y * (float(y) + 0.5) / 11.0
			)
			if not _trackside_placement_is_safe(candidate, 47.0, room_polygon, centerline, gate_samples, occupied):
				continue
			var occupied_clearance := 260.0
			for entry: Dictionary in occupied:
				occupied_clearance = minf(occupied_clearance, candidate.distance_to(entry["position"]) - float(entry["radius"]))
			var score := minf(_distance_to_centerline(candidate, centerline), 360.0)
			score += minf(occupied_clearance, 260.0) * 0.65
			score += rng.randf_range(0.0, 18.0)
			candidates.append({
				"position": candidate,
				"score": score,
				"sector": Vector2i(clampi(int(float(x) / 17.0 * 3.0), 0, 2), clampi(int(float(y) / 11.0 * 2.0), 0, 1)),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var anchors := PackedVector2Array()
	var occupied_sectors := {}
	# First claim the best blank pocket in each coarse room sector. A second pass
	# fills any remaining slots without forcing unsafe scenery into tight rooms.
	for candidate_data: Dictionary in candidates:
		var sector: Vector2i = candidate_data["sector"]
		if occupied_sectors.has(sector):
			continue
		var candidate: Vector2 = candidate_data["position"]
		if not _clear_of_points(candidate, anchors, 210.0):
			continue
		anchors.append(candidate)
		occupied_sectors[sector] = true
		if anchors.size() >= target_count:
			break
	if anchors.size() < target_count:
		for candidate_data: Dictionary in candidates:
			var candidate: Vector2 = candidate_data["position"]
			if not _clear_of_points(candidate, anchors, 210.0):
				continue
			anchors.append(candidate)
			if anchors.size() >= target_count:
				break
	return anchors


static func _build_room_ground_sections(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array
) -> int:
	var definitions: Array = spec.get("ground_sections", [])
	if definitions.is_empty():
		return 0
	var sections := Node2D.new()
	sections.name = "GroundSections"
	sections.set_meta("moment_kind", &"ambient_ground")
	parent.add_child(sections)
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix_seed(int(spec["requested_seed"]), "ground_sections:%s" % String(story["id"]))
	var room_area := absf(_polygon_area(room_polygon))
	var target_count := clampi(int(round(room_area / 750000.0)), 2, 4)
	sections.set_meta("requested_count", target_count)
	var bounds := _polygon_bounds_rect(room_polygon)
	var placements: Array[Dictionary] = []
	var occupied_sectors := {}
	var asset_offset := rng.randi_range(0, definitions.size() - 1)
	for section_index in target_count:
		var definition: Dictionary = definitions[(asset_offset + section_index) % definitions.size()]
		var asset_path := String(definition["asset"])
		var texture := load(asset_path) as Texture2D
		if texture == null:
			continue
		var base_world_size := float(definition.get("size", 240.0)) * rng.randf_range(0.90, 1.08)
		var alpha := float(definition.get("alpha", 0.94))
		for attempt in 520:
			var size_factor := 1.0 - float(attempt / 180) * 0.08
			var world_size := base_world_size * maxf(size_factor, 0.82)
			var footprint_radius := world_size * 0.40
			var candidate := Vector2(
				rng.randf_range(bounds.position.x, bounds.end.x),
				rng.randf_range(bounds.position.y, bounds.end.y)
			)
			if Geometry2D.is_point_in_polygon(candidate, outer_loop):
				continue
			if not _inside_polygon_with_radius(candidate, minf(footprint_radius * 0.82, 92.0), room_polygon):
				continue
			if _distance_to_centerline(candidate, centerline) < HALF_WIDTH + footprint_radius * 0.14:
				continue
			var normalized: Vector2 = (candidate - bounds.position) / bounds.size
			var sector := Vector2i(clampi(int(normalized.x * 3.0), 0, 2), clampi(int(normalized.y * 2.0), 0, 1))
			if attempt < 300 and occupied_sectors.has(sector):
				continue
			var clear := true
			for placement: Dictionary in placements:
				if candidate.distance_to(placement["position"]) < (footprint_radius + float(placement["radius"])) * 0.72:
					clear = false
					break
			if not clear:
				continue
			var sprite := Sprite2D.new()
			sprite.name = "Section%02d" % placements.size()
			sprite.texture = texture
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			sprite.position = candidate
			sprite.rotation = rng.randf_range(-PI, PI)
			var longest := maxf(texture.get_width(), texture.get_height())
			sprite.scale = Vector2.ONE * (world_size / maxf(longest, 1.0))
			sprite.modulate = Color(1.0, 1.0, 1.0, alpha)
			sprite.z_index = -17
			sprite.set_meta("asset_path", asset_path)
			sprite.set_meta("moment_kind", &"ambient_ground")
			sprite.set_meta("world_size", world_size)
			sprite.set_meta("footprint_radius", footprint_radius)
			sections.add_child(sprite)
			placements.append({"position": candidate, "radius": footprint_radius})
			occupied_sectors[sector] = true
			break
	sections.set_meta("placed_count", placements.size())
	return placements.size()


static func _build_room_floor_details(
		parent: Node2D,
		spec: Dictionary,
		centerline: PackedVector2Array,
		room_polygon: PackedVector2Array,
		occupied: Array[Dictionary],
		rng: RandomNumberGenerator
) -> int:
	var decals: Array = spec.get("decals", [])
	if decals.is_empty():
		return 0
	var details := Node2D.new()
	details.name = "FloorDetails"
	parent.add_child(details)
	var bounds := _polygon_bounds_rect(room_polygon)
	var target_count := clampi(int(round(absf(_polygon_area(room_polygon)) / 110000.0)), 12, 20)
	var positions := PackedVector2Array()
	for attempt in 420:
		var candidate := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if not _inside_polygon_with_radius(candidate, 22.0, room_polygon):
			continue
		if _distance_to_centerline(candidate, centerline) < HALF_WIDTH + 22.0:
			continue
		if not _clear_of_points(candidate, positions, 82.0):
			continue
		var texture_path := String(decals[rng.randi_range(0, decals.size() - 1)])
		var texture := load(texture_path) as Texture2D
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.name = "Detail%02d" % positions.size()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.position = candidate
		sprite.rotation = rng.randf_range(0.0, TAU)
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (rng.randf_range(58.0, 96.0) / maxf(longest, 1.0))
		sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.38, 0.72))
		sprite.z_index = -15
		sprite.set_meta("asset_path", texture_path)
		sprite.set_meta("moment_kind", &"ambient_decal")
		details.add_child(sprite)
		positions.append(candidate)
		if positions.size() >= target_count:
			break
	details.set_meta("placed_count", positions.size())
	return positions.size()


static func _build_generated_surfaces(root: Node2D, parent: Node2D, story: Dictionary, moments: Dictionary, centerline: PackedVector2Array) -> void:
	var definitions: Array[Dictionary] = []
	var surfaces: Array = story["surfaces"]

	var shortcut_surface_index := 0 if float((surfaces[0] as Dictionary)["grip"]) <= float((surfaces[1] as Dictionary)["grip"]) else 1
	var technical_surface_index := 1 - shortcut_surface_index
	var technical_data: Dictionary = surfaces[technical_surface_index]
	var technical_index := int(moments["technical"])
	var technical_polygon := _surface_strip(centerline, technical_index, 6, 92.0)
	var technical_definition := {
		"name": StringName(technical_data["name"]),
		"role": &"technical",
		"lane": &"full",
		"grip": float(technical_data["grip"]),
		"speed": float(technical_data["speed"]),
		"points": technical_polygon,
		"decal": String(technical_data["decal"]),
		"centerline_index": technical_index,
	}
	definitions.append(technical_definition)
	var technical := Node2D.new()
	technical.name = "TechnicalSurfaceMoment"
	technical.set_meta("moment_kind", &"technical")
	technical.set_meta("surface_name", technical_definition["name"])
	technical.set_meta("grip", technical_definition["grip"])
	technical.set_meta("speed", technical_definition["speed"])
	technical.set_meta("polygon", technical_polygon)
	technical.set_meta("decal_texture", technical_definition["decal"])
	technical.set_meta("centerline_index", technical_index)
	parent.add_child(technical)
	_add_surface_decals(technical, centerline, technical_index, 6, String(technical_data["decal"]))

	var shortcut_data: Dictionary = surfaces[shortcut_surface_index]
	var shortcut_index := int(moments["shortcut"])
	var shortcut_geometry := _shortcut_lane_geometry(centerline, shortcut_index)
	var shortcut_path: PackedVector2Array = shortcut_geometry["shortcut_path"]
	var safe_path: PackedVector2Array = shortcut_geometry["safe_path"]
	var shortcut_polygon := _lane_strip(shortcut_path, SHORTCUT_LANE_HALF_WIDTH)
	var shortcut_definition := {
		"name": StringName(shortcut_data["name"]),
		"role": &"shortcut",
		"lane": &"inside",
		"grip": float(shortcut_data["grip"]),
		"speed": maxf(float(shortcut_data["speed"]), 1.06),
		"points": shortcut_polygon,
		"decal": String(shortcut_data["decal"]),
		"centerline_index": shortcut_index,
		"inside_sign": float(shortcut_geometry["inside_sign"]),
	}
	definitions.append(shortcut_definition)
	var shortcut := Node2D.new()
	shortcut.name = "ShortcutDecision"
	shortcut.set_meta("moment_kind", &"shortcut")
	shortcut.set_meta("surface_name", shortcut_definition["name"])
	shortcut.set_meta("grip", shortcut_definition["grip"])
	shortcut.set_meta("speed", shortcut_definition["speed"])
	shortcut.set_meta("polygon", shortcut_polygon)
	shortcut.set_meta("decal_texture", shortcut_definition["decal"])
	shortcut.set_meta("centerline_index", shortcut_index)
	shortcut.set_meta("inside_sign", shortcut_definition["inside_sign"])
	shortcut.set_meta("shortcut_path", shortcut_path)
	shortcut.set_meta("safe_path", safe_path)
	shortcut.set_meta("shortcut_length", float(shortcut_geometry["shortcut_length"]))
	shortcut.set_meta("safe_length", float(shortcut_geometry["safe_length"]))
	parent.add_child(shortcut)
	_add_surface_decals(shortcut, centerline, shortcut_index, SHORTCUT_HALF_SPAN, String(shortcut_data["decal"]), float(shortcut_geometry["inside_sign"]) * SHORTCUT_LANE_OFFSET)
	root.set_meta("generated_surfaces", definitions)


static func _surface_strip(centerline: PackedVector2Array, center_index: int, half_span: int, half_width: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for offset in range(-half_span, half_span + 1, 2):
		var index := posmod(center_index + offset, centerline.size())
		var normal := _sample_tangent(centerline, index).rotated(PI * 0.5)
		left.append(centerline[index] + normal * half_width)
		right.append(centerline[index] - normal * half_width)
	var polygon := PackedVector2Array()
	polygon.append_array(left)
	for index in range(right.size() - 1, -1, -1):
		polygon.append(right[index])
	var hull := Geometry2D.convex_hull(polygon)
	if hull.size() > 2 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.resize(hull.size() - 1)
	return hull


static func _add_surface_decals(
		parent: Node2D,
		centerline: PackedVector2Array,
		center_index: int,
		half_span: int,
		texture_path: String,
		lateral_offset: float = 0.0
) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var decal_count := 4
	for decal_index in decal_count:
		var fraction := float(decal_index) / float(decal_count - 1)
		var offset := int(round(lerpf(float(-half_span), float(half_span), fraction)))
		var index := posmod(center_index + offset, centerline.size())
		var sprite := Sprite2D.new()
		sprite.name = "CenterlineDecal%02d" % decal_index
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var normal := _sample_tangent(centerline, index).rotated(PI * 0.5)
		sprite.position = centerline[index] + normal * lateral_offset
		sprite.rotation = _sample_tangent(centerline, index).angle() + float(decal_index % 2) * 0.31
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (88.0 / maxf(longest, 1.0))
		sprite.modulate = Color(1.0, 1.0, 1.0, 0.78)
		sprite.z_index = -6
		sprite.set_meta("asset_path", texture_path)
		parent.add_child(sprite)


static func _shortcut_lane_geometry(centerline: PackedVector2Array, center_index: int) -> Dictionary:
	var positive := _offset_section_path(centerline, center_index, SHORTCUT_HALF_SPAN, SHORTCUT_LANE_OFFSET)
	var negative := _offset_section_path(centerline, center_index, SHORTCUT_HALF_SPAN, -SHORTCUT_LANE_OFFSET)
	var positive_length := _open_path_length(positive)
	var negative_length := _open_path_length(negative)
	if positive_length <= negative_length:
		return {
			"inside_sign": 1.0,
			"shortcut_path": positive,
			"safe_path": negative,
			"shortcut_length": positive_length,
			"safe_length": negative_length,
		}
	return {
		"inside_sign": -1.0,
		"shortcut_path": negative,
		"safe_path": positive,
		"shortcut_length": negative_length,
		"safe_length": positive_length,
	}


static func _offset_section_path(
		centerline: PackedVector2Array,
		center_index: int,
		half_span: int,
		lateral_offset: float
) -> PackedVector2Array:
	var path := PackedVector2Array()
	for offset in range(-half_span, half_span + 1):
		var index := posmod(center_index + offset, centerline.size())
		var normal := _sample_tangent(centerline, index).rotated(PI * 0.5)
		path.append(centerline[index] + normal * lateral_offset)
	return path


static func _lane_strip(path: PackedVector2Array, half_width: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in path.size():
		var before := path[maxi(index - 1, 0)]
		var after := path[mini(index + 1, path.size() - 1)]
		var normal := before.direction_to(after).rotated(PI * 0.5)
		left.append(path[index] + normal * half_width)
		right.append(path[index] - normal * half_width)
	var polygon := PackedVector2Array()
	polygon.append_array(left)
	for index in range(right.size() - 1, -1, -1):
		polygon.append(right[index])
	var hull := Geometry2D.convex_hull(polygon)
	if hull.size() > 2 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.resize(hull.size() - 1)
	return hull


static func _open_path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += path[index - 1].distance_to(path[index])
	return total


static func _crossing_path(centerline: PackedVector2Array, center_index: int, half_width: float) -> PackedVector2Array:
	var normal := _sample_tangent(centerline, center_index).rotated(PI * 0.5)
	return PackedVector2Array([
		centerline[center_index] - normal * half_width,
		centerline[center_index] + normal * half_width,
	])


static func _build_finish_moments(parent: Node2D, centerline: PackedVector2Array) -> void:
	var forward_path := PackedVector2Array()
	var reverse_path := PackedVector2Array()
	for offset in range(-FINISH_APPROACH_SPAN, 1):
		forward_path.append(centerline[posmod(offset, centerline.size())])
	for offset in range(FINISH_APPROACH_SPAN, -1, -1):
		reverse_path.append(centerline[posmod(offset, centerline.size())])

	var speed := Node2D.new()
	speed.name = "SpeedSection"
	speed.position = centerline[0]
	speed.set_meta("moment_kind", &"speed")
	speed.set_meta("centerline_index", 0)
	speed.set_meta("forward_path", forward_path)
	speed.set_meta("reverse_path", reverse_path)
	speed.set_meta("forward_length", _open_path_length(forward_path))
	speed.set_meta("reverse_length", _open_path_length(reverse_path))
	speed.set_meta("reserved_clear", true)
	parent.add_child(speed)

	var finish := Node2D.new()
	finish.name = "DramaticFinish"
	finish.position = centerline[0]
	finish.set_meta("moment_kind", &"finish")
	finish.set_meta("centerline_index", 0)
	finish.set_meta("forward_approach", forward_path)
	finish.set_meta("reverse_approach", reverse_path)
	finish.set_meta("finish_gate", NodePath("../../Checkpoint0Finish"))
	finish.set_meta("checker_white", NodePath("../../StartFinishWhite"))
	finish.set_meta("checker_black", NodePath("../../StartFinishBlack"))
	parent.add_child(finish)


static func _sample_tangent(centerline: PackedVector2Array, index: int) -> Vector2:
	return (centerline[posmod(index + 1, centerline.size())] - centerline[posmod(index - 1, centerline.size())]).normalized()


static func _placement_is_safe(
		candidate: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		allowed_polygon: PackedVector2Array,
		occupied: Array[Dictionary]
) -> bool:
	if not _inside_polygon_with_radius(candidate, radius, room_polygon):
		return false
	if not _inside_polygon_with_radius(candidate, radius, allowed_polygon):
		return false
	return _clear_of_occupied(candidate, radius, occupied)


static func _best_island_position(
		preferred: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		island_polygon: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	var bounds := _polygon_bounds_rect(island_polygon)
	var best_position := Vector2.ZERO
	var best_score := INF
	# A deterministic dense scan is the final placement path for strongly
	# concave islands where an authored local formation lands in a bay or waist.
	for x in 17:
		for y in 17:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 17.0,
				bounds.size.y * (float(y) + 0.5) / 17.0
			)
			if not _placement_is_safe(candidate, radius, room_polygon, island_polygon, occupied):
				continue
			var score := candidate.distance_squared_to(preferred)
			if score < best_score:
				best_score = score
				best_position = candidate
	return {"found": best_score < INF, "position": best_position}


static func _best_offtrack_position(
		preferred: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	var bounds := _polygon_bounds_rect(room_polygon)
	var best_position := Vector2.ZERO
	var best_score := INF
	for x in 25:
		for y in 17:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 25.0,
				bounds.size.y * (float(y) + 0.5) / 17.0
			)
			if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
				continue
			var score := candidate.distance_squared_to(preferred)
			if score < best_score:
				best_score = score
				best_position = candidate
	return {"found": best_score < INF, "position": best_position}


static func _trackside_placement_is_safe(
		candidate: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> bool:
	if not _inside_polygon_with_radius(candidate, radius, room_polygon):
		return false
	if _distance_to_centerline(candidate, centerline) < HALF_WIDTH + radius + 7.0:
		return false
	if candidate.distance_to(centerline[0]) < 245.0 + radius:
		return false
	if not _clear_of_points(candidate, gate_samples, 24.0 + radius):
		return false
	if not _clear_of_recovery_lanes(candidate, radius, centerline, gate_samples):
		return false
	return _clear_of_occupied(candidate, radius, occupied)


static func _best_trackside_position(
		preferred_index: int,
		radius: float,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	var best_position := Vector2.ZERO
	var best_index := 0
	var best_score := INF
	for index in range(0, centerline.size(), 2):
		var outward := (outer_loop[index] - centerline[index]).normalized()
		for attempt in 8:
			var side := 1.0 if attempt % 2 == 0 else -1.0
			var offset := HALF_WIDTH + radius + 10.0 + float(attempt / 2) * 8.0
			var candidate := centerline[index] + outward * side * offset
			if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
				continue
			var score := float(_cyclic_index_distance(index, posmod(preferred_index, centerline.size()), centerline.size())) + float(attempt) * 0.01
			if score < best_score:
				best_score = score
				best_position = candidate
				best_index = index
	return {"found": best_score < INF, "position": best_position, "index": best_index}


static func _inside_polygon_with_radius(point: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if polygon.is_empty() or not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	for sample in 8:
		var test_point := point + Vector2.RIGHT.rotated(TAU * float(sample) / 8.0) * radius
		if not Geometry2D.is_point_in_polygon(test_point, polygon):
			return false
	return true


static func _clear_of_points(point: Vector2, points: PackedVector2Array, clearance: float) -> bool:
	for other: Vector2 in points:
		if point.distance_to(other) < clearance:
			return false
	return true


static func _clear_of_recovery_lanes(
		point: Vector2,
		radius: float,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array
) -> bool:
	for gate: Vector2 in gate_samples:
		var nearest_index := 0
		var nearest_distance := INF
		for index in centerline.size():
			var distance := gate.distance_squared_to(centerline[index])
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_index = index
		var tangent := _sample_tangent(centerline, nearest_index)
		var lane_from := gate - tangent * RECOVERY_LANE_HALF_LENGTH
		var lane_to := gate + tangent * RECOVERY_LANE_HALF_LENGTH
		if _point_to_segment_distance(point, lane_from, lane_to) < RECOVERY_LANE_HALF_WIDTH + radius:
			return false
	return true


static func _point_to_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	if segment.length_squared() < 0.001:
		return point.distance_to(from)
	var fraction := clampf((point - from).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(from + segment * fraction)


static func _clear_of_occupied(point: Vector2, radius: float, occupied: Array[Dictionary]) -> bool:
	for entry: Dictionary in occupied:
		if point.distance_to(entry["position"]) < radius + float(entry["radius"]) + 7.0:
			return false
	return true


static func _asset_radius(texture_path: String, fallback_radius: float) -> float:
	return minf(_prop_visual_size(texture_path, fallback_radius * 2.0) * 0.5, 96.0)


static func _add_generated_prop(
		parent: Node2D,
		node_name: String,
		position: Vector2,
		texture_path: String,
		rotation: float,
		moment_kind: StringName,
		quantity: StringName,
		formation_index: int,
		size_scale: float = 1.0
) -> void:
	var prop := StaticBody2D.new()
	prop.name = node_name
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	prop.set_meta("asset_path", texture_path)
	prop.set_meta("moment_kind", moment_kind)
	prop.set_meta("semantic_quantity", quantity)
	prop.set_meta("formation_index", formation_index)
	prop.set_meta("size_scale", size_scale)
	parent.add_child(prop)
	var radius := _asset_radius(texture_path, 24.0) * size_scale
	_add_shape_collision(prop, texture_path, radius, size_scale)
	_add_contact_shadow(prop, radius * 1.12)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (_prop_visual_size(texture_path, 48.0) * size_scale / maxf(longest, 1.0))
		prop.add_child(sprite)


static func _mix_seed(seed: int, stream: String) -> int:
	var value := (seed ^ int(stream.hash()) ^ 0x6D2B79F5) & 0x7FFFFFFF
	value = ((value ^ (value >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	value = ((value ^ (value >> 15)) * 0x45D9F3B) & 0x7FFFFFFF
	return (value ^ (value >> 16)) & 0x7FFFFFFF


static func _fill_island(root: Node2D, spec: Dictionary, inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> void:
	# The island hosts one authored VIGNETTE per theme (a designed scene, not a
	# random scatter): focal props at hand-authored offsets from the centroid,
	# plus a scatter of tiny many-items for life. The vignette is chosen by the
	# seed so it stays procedural but always reads as a scene.
	var vignettes: Array = []
	match String(spec.get("root_name", "")):
		"WorkshopWorkbench":
			vignettes = ISLAND_VIGNETTES[&"workshop"]
		"OfficeDesk":
			vignettes = ISLAND_VIGNETTES[&"office"]
		_:
			vignettes = ISLAND_VIGNETTES[&"kitchen"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var vignette: Array = vignettes[posmod(int(spec.get("seed", 0)), vignettes.size())]
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in inner_loop:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var centroid := (min_point + max_point) * 0.5
	var half_extent := (max_point - min_point) * 0.5
	for entry: Dictionary in vignette:
		var offset: Vector2 = entry["pos"]
		var position := centroid + Vector2(offset.x * half_extent.x, offset.y * half_extent.y)
		if not Geometry2D.is_point_in_polygon(position, inner_loop):
			continue
		var center_distance := _distance_to_centerline(position, centerline)
		if center_distance < 125.0 + 40.0:
			continue
		var texture_path := String(entry["tex"])
		if bool(entry.get("decal", false)):
			var sprite := Sprite2D.new()
			sprite.name = "VignetteDecal"
			sprite.texture = load(texture_path) as Texture2D
			if sprite.texture == null:
				sprite.free()
				continue
			sprite.position = position
			sprite.rotation = float(entry.get("rot", 0.0))
			sprite.scale = Vector2.ONE * rng.randf_range(0.7, 1.2)
			sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.55, 0.8))
			sprite.z_index = -13
			root.add_child(sprite)
			continue
		var visual := _prop_visual_size(texture_path, 36.0)
		var radius := minf(visual * 0.5, 52.0)
		_add_fill_prop(root, position, radius, texture_path, float(entry.get("rot", 0.0)))
	# Life: a scatter of tiny many-items (paperclips, coins, screws) around the vignette
	var many_pool: Array = spec.get("island_fill_tiny", [])
	if many_pool.is_empty():
		many_pool = ["res://assets/textures/imagine/paperclip.png", "res://assets/textures/imagine/coin.png"]
	for scatter in 12:
		var position := centroid + Vector2(rng.randf_range(-0.85, 0.85) * half_extent.x, rng.randf_range(-0.85, 0.85) * half_extent.y)
		if not Geometry2D.is_point_in_polygon(position, inner_loop):
			continue
		if _distance_to_centerline(position, centerline) < 125.0 + 40.0:
			continue
		var texture_path := String(many_pool[rng.randi_range(0, many_pool.size() - 1)])
		var visual := _prop_visual_size(texture_path, 18.0)
		_add_fill_prop(root, position, minf(visual * 0.5, 20.0), texture_path, rng.randf_range(0.0, TAU))


static func _cell_clear_of_corridor(center: Vector2, radius: float, corridor: PackedVector2Array) -> bool:
	for sample in 8:
		var angle := TAU * float(sample) / 8.0
		if Geometry2D.is_point_in_polygon(center + Vector2(cos(angle), sin(angle)) * (radius + 40.0), corridor):
			return false
	return true


static func _line_boundary_props(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, outer_loop: PackedVector2Array, corridor: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	# Props delimiting the OUTER side of the track: long flat props on straights,
	# bulky props on corners, placed just outside the painted corridor. The
	# corridor-band test is distance-to-centerline (polygon membership is
	# unreliable inside the corridor's fold regions).
	var long_pool: Array = spec.get("boundary_long", [])
	var corner_pool: Array = spec.get("boundary_corner", [])
	if long_pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var count := centerline.size()
	var index := 0
	while index < count - 1:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var ahead := centerline[(index + 8) % count] - centerline[(index - 8 + count) % count]
		var turn := tangent.angle_to(ahead.normalized())
		var is_corner := absf(turn) > 0.16
		var offset := 78.0 if is_corner else 65.0
		var radius := 34.0 if is_corner else 27.0
		var position := outer_loop[index] + (outer_loop[index] - centerline[index]).normalized() * offset
		if position.distance_to(centerline[0]) < 230.0:
			index += 7
			continue
		if not Geometry2D.is_point_in_polygon(position, room_polygon):
			index += 7
			continue
		if _distance_to_centerline(position, centerline) < 150.0:
			index += 7
			continue
		var pool := corner_pool if is_corner else long_pool
		var texture_path := String(pool[rng.randi_range(0, pool.size() - 1)])
		var prop_rotation := rng.randf_range(0.0, TAU) if is_corner else tangent.angle()
		_add_boundary_prop(root, position, radius, texture_path, prop_rotation)
		index += 7


static func _build_racing_line(root: Node2D, centerline: PackedVector2Array, moments: Dictionary = {}) -> void:
	var count := centerline.size()
	var line_points := PackedVector2Array()
	var shortcut_index := int(moments.get("shortcut", -1))
	var shortcut_inside_sign := 0.0
	if shortcut_index >= 0:
		shortcut_inside_sign = float(_shortcut_lane_geometry(centerline, shortcut_index)["inside_sign"])
	for index in count:
		var tangent_behind := (centerline[index] - centerline[(index - 12 + count) % count]).normalized()
		var tangent_ahead := (centerline[(index + 12) % count] - centerline[index]).normalized()
		var turn := tangent_behind.angle_to(tangent_ahead)
		var normal := tangent_behind.rotated(PI * 0.5)
		var inward := normal if turn > 0.0 else -normal
		var offset := clampf(absf(turn) * 210.0, 0.0, 40.0)
		var target := centerline[index] + inward * offset
		if shortcut_index >= 0:
			var shortcut_distance := _cyclic_index_distance(index, shortcut_index, count)
			var taper_span := SHORTCUT_HALF_SPAN + 6
			if shortcut_distance <= taper_span:
				var influence := 1.0 - smoothstep(float(SHORTCUT_HALF_SPAN), float(taper_span), float(shortcut_distance))
				var safe_target := centerline[index] - normal * shortcut_inside_sign * SAFE_RACING_LINE_OFFSET
				target = target.lerp(safe_target, influence)
		line_points.append(target)
	var line := Line2D.new()
	line.name = "RacingLine"
	line.points = line_points
	line.closed = true
	line.width = 2.0
	line.visible = false
	root.add_child(line)


static func _add_corner_set_pieces(root: Node2D, spec: Dictionary, room_polygon: PackedVector2Array, corridor: PackedVector2Array) -> void:
	var giants: Array = spec.get("corner_giants", [])
	if giants.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0)) * 7 + 3
	var candidates := PackedVector2Array()
	var count := room_polygon.size()
	for index in count:
		var corner: Vector2 = room_polygon[index]
		var toward_center := Vector2.ZERO
		for point: Vector2 in room_polygon:
			toward_center += point
		toward_center /= float(count)
		var inward := (toward_center - corner).normalized()
		candidates.append(corner + inward * 190.0)
	var placed := 0
	for candidate: Vector2 in candidates:
		if placed >= 3:
			break
		if Geometry2D.is_point_in_polygon(candidate, corridor):
			continue
		if _distance_to_centerline(candidate, _sample_centerline(spec["controls"])) < 200.0:
			continue
		var texture_path := String(giants[placed % giants.size()])
		var texture := load(texture_path) as Texture2D
		if texture == null:
			continue
		var prop := StaticBody2D.new()
		prop.name = "CornerGiant"
		prop.position = candidate
		prop.rotation = rng.randf_range(0.0, TAU)
		prop.collision_layer = 4
		root.add_child(prop)
		var shape := CircleShape2D.new()
		shape.radius = 64.0
		var cs := CollisionShape2D.new()
		cs.shape = shape
		prop.add_child(cs)
		_add_contact_shadow(prop, 84.0)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (215.0 / maxf(longest, 1.0))
		prop.add_child(sprite)
		placed += 1


static func _island_apexes(inner_loop: PackedVector2Array) -> PackedVector2Array:
	var apexes := PackedVector2Array()
	var count := inner_loop.size()
	for index in count:
		var behind := (inner_loop[index] - inner_loop[(index - 12 + count) % count]).normalized()
		var ahead := (inner_loop[(index + 12) % count] - inner_loop[index]).normalized()
		var turn := behind.angle_to(ahead)
		if absf(turn) > 0.18 and (apexes.is_empty() or apexes[apexes.size() - 1].distance_to(inner_loop[index]) > 120.0):
			apexes.append(inner_loop[index])
	return apexes


static func _add_paperclip_line(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, outer_loop: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	var count := centerline.size()
	var best_start := 0
	var best_straight := -1.0
	for index in count:
		var chord := centerline[(index + 20) % count].distance_to(centerline[(index + count - 20) % count])
		if chord > best_straight:
			best_straight = chord
			best_start = index
	var index := best_start
	var placed := 0
	var attempts := 0
	while placed < 18 and attempts < count:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var position := outer_loop[index] + (outer_loop[index] - centerline[index]).normalized() * 58.0
		if Geometry2D.is_point_in_polygon(position, room_polygon) and _distance_to_centerline(position, centerline) >= 165.0:
			var clip := StaticBody2D.new()
			clip.name = "PaperclipLine"
			clip.position = position
			clip.rotation = tangent.angle()
			clip.collision_layer = 16
			root.add_child(clip)
			var shape := RectangleShape2D.new()
			shape.size = Vector2(16.0, 7.0)
			var cs := CollisionShape2D.new()
			cs.shape = shape
			clip.add_child(cs)
			var texture := load("res://assets/textures/imagine/paperclip.png") as Texture2D
			if texture:
				var sprite := Sprite2D.new()
				sprite.texture = texture
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				sprite.scale = Vector2.ONE * (16.0 / maxf(texture.get_width(), texture.get_height()))
				clip.add_child(sprite)
			placed += 1
		index = (index + 2) % count
		attempts += 1


static func _distance_to_centerline(point: Vector2, centerline: PackedVector2Array) -> float:
	var best := 999999.0
	for sample: Vector2 in centerline:
		best = minf(best, point.distance_to(sample))
	return best


static func _prop_visual_size(texture_path: String, fallback_diameter: float) -> float:
	var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
	var size: Vector2 = entry.get("size", Vector2.ZERO)
	if size.x > 0.0 or size.y > 0.0:
		return maxf(size.x, size.y)
	return fallback_diameter


static func _add_shape_collision(parent: Node, texture_path: String, scale_radius: float, size_scale: float = 1.0) -> void:
	var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
	if entry.get("shape", "circle") == "rect":
		var rect := RectangleShape2D.new()
		rect.size = (entry["size"] as Vector2) * size_scale
		var rect_cs := CollisionShape2D.new()
		rect_cs.shape = rect
		parent.add_child(rect_cs)
		return
	var circle := CircleShape2D.new()
	circle.radius = scale_radius
	var circle_cs := CollisionShape2D.new()
	circle_cs.shape = circle
	parent.add_child(circle_cs)


static func _add_boundary_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	var prop := StaticBody2D.new()
	prop.name = "BoundaryProp"
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	parent.add_child(prop)
	_add_shape_collision(prop, texture_path, radius)
	_add_contact_shadow(prop, radius * 1.15)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.2 / maxf(longest, 1.0))
		prop.add_child(sprite)


static var fill_prop_calls := 0

static func _add_fill_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	var prop := StaticBody2D.new()
	prop.name = "IslandFill"
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	parent.add_child(prop)
	_add_contact_shadow(prop, radius * 1.15)
	_add_shape_collision(prop, texture_path, radius)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var visual := _prop_visual_size(texture_path, radius * 2.2)
		sprite.scale = Vector2.ONE * (visual / maxf(longest, 1.0))
		prop.add_child(sprite)


static func _add_contact_shadow(parent: Node, radius: float) -> void:
	var shadow := Sprite2D.new()
	shadow.name = "ContactShadow"
	shadow.texture = _contact_shadow_texture()
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shadow.scale = Vector2.ONE * (radius * 2.4 / 128.0)
	shadow.modulate = Color(0.06, 0.05, 0.05, 0.45)
	shadow.z_index = -1
	parent.add_child(shadow)


static var _cached_contact_shadow: Texture2D = null


static func _contact_shadow_texture() -> Texture2D:
	if _cached_contact_shadow != null:
		return _cached_contact_shadow
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var dx := (float(x) - 63.5) / 58.0
			var dy := (float(y) - 63.5) / 58.0
			var falloff := clampf(1.0 - (dx * dx + dy * dy), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, falloff * falloff))
	_cached_contact_shadow = ImageTexture.create_from_image(image)
	return _cached_contact_shadow


static func _add_scatter_prop(parent: Node, position: Vector2, radius: float, texture_path: String) -> void:
	var prop := StaticBody2D.new()
	prop.name = "SeedCorridor"
	prop.position = position
	prop.collision_layer = 16
	parent.add_child(prop)
	_add_shape_collision(prop, texture_path, radius)
	_add_contact_shadow(prop, radius * 1.15)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.2 / maxf(longest, 1.0))
		prop.add_child(sprite)


static func _seed_clear_of_gates(point: Vector2, gate_samples: PackedVector2Array) -> bool:
	for gate: Vector2 in gate_samples:
		if point.distance_to(gate) < 160.0:
			return false
	return true


static func _point_in_loop(point: Vector2, loop: PackedVector2Array) -> bool:
	var inside := false
	var count := loop.size()
	for index in count:
		var a := loop[index]
		var b := loop[(index + 1) % count]
		if ((a.y > point.y) != (b.y > point.y)) and (point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
	return inside


static func _add_obstacle(parent: Node, node_name: String, position: Vector2, radius: float, texture_path: String) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.name = node_name
	obstacle.position = position
	obstacle.collision_layer = 2
	parent.add_child(obstacle)
	_add_shape_collision(obstacle, texture_path, radius)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.4 / maxf(longest, 1.0))
		obstacle.add_child(sprite)


static func _add_prop_with_collision(parent: Node, position: Vector2, radius: float, texture_path: String) -> void:
	var prop := StaticBody2D.new()
	prop.name = "ApronProp"
	prop.position = position
	prop.collision_layer = 2
	parent.add_child(prop)
	var shape := CircleShape2D.new()
	shape.radius = radius
	var cs := CollisionShape2D.new()
	cs.shape = shape
	prop.add_child(cs)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.4 / maxf(longest, 1.0))
		prop.add_child(sprite)


static func _add_prop(parent: Node, texture_path: String, position: Vector2, scale: float, rotation: float, z: int) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.position = position
	sprite.rotation = rotation
	sprite.scale = Vector2.ONE * scale
	sprite.z_index = z
	parent.add_child(sprite)


static func _add_sticky_notes(parent: Node, center: Vector2, rotation: float) -> void:
	for offset: Vector2 in [Vector2(-30, -14), Vector2(0, 8), Vector2(26, -6)]:
		var note := Polygon2D.new()
		note.polygon = PackedVector2Array([
			Vector2(-34, -30), Vector2(34, -30), Vector2(34, 30), Vector2(-34, 30),
		])
		note.color = Color("f4bf3a") if offset.x < 0.0 else Color("f2ead7")
		note.position = center + offset
		note.rotation = rotation + (0.1 if offset.x == 0.0 else 0.0)
		note.z_index = -12
		parent.add_child(note)


static func _add_cable_line(parent: Node, points: Array) -> void:
	var line := Line2D.new()
	var packed := PackedVector2Array()
	for point: Vector2 in points:
		packed.append(point)
	line.points = packed
	line.width = 9.0
	line.default_color = Color("6f91b8")
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_index = -12
	parent.add_child(line)


static func _add_textured_polygon(parent: Node, node_name: String, points: PackedVector2Array, texture_path: String, fallback_color: Color, z: int) -> void:
	var visual := Polygon2D.new()
	visual.name = node_name
	visual.z_index = z
	visual.polygon = points
	var texture := load(texture_path) as Texture2D if not texture_path.is_empty() else null
	if texture:
		visual.texture = texture
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var min_point := Vector2(INF, INF)
		for point: Vector2 in points:
			min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		var uvs := PackedVector2Array()
		for point: Vector2 in points:
			uvs.append((point - min_point) / 512.0)
		visual.uv = uvs
	else:
		visual.color = fallback_color
	parent.add_child(visual)


static func _expand_loop(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var count := points.size()
	var result := PackedVector2Array()
	for index in count:
		var prev := points[(index - 1 + count) % count]
		var next := points[(index + 1) % count]
		var tangent := (next - prev).normalized()
		var normal := tangent.rotated(-PI * 0.5)
		var centroid := Vector2.ZERO
		for point: Vector2 in points:
			centroid += point
		centroid /= float(count)
		if normal.dot(centroid - points[index]) < 0.0:
			normal = -normal
		result.append(points[index] + normal * distance)
	return result


static func _add_dashed_centerline(parent: Node, centerline: PackedVector2Array) -> void:
	var line := Line2D.new()
	line.name = "CenterlineDashes"
	line.width = 5.0
	line.default_color = Color("f2ead7", 0.8)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_index = -8
	var count := centerline.size()
	var dash := 0
	var dash_length := 34.0
	var dash_gap := 30.0
	while dash < count - 2:
		var start := centerline[dash]
		var target := centerline[dash + 1]
		var segment_length := start.distance_to(target)
		if segment_length <= dash_gap:
			dash += 1
			continue
		line.add_point(start)
		var ratio := minf(dash_length / segment_length, 1.0)
		line.add_point(start.lerp(target, ratio))
		dash += 1
	parent.add_child(line)


static func _add_edge_line(parent: Node, points: PackedVector2Array, color: Color) -> void:
	var line := Line2D.new()
	line.points = points
	line.closed = true
	line.width = 8.0
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_index = -7
	parent.add_child(line)


static func _add_centerline_tiles(parent: Node, centerline: PackedVector2Array, texture_path: String, scale: Vector2, modulate_value: float = 1.35) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	# A single textured ribbon avoids the overlapping square cards that made
	# every circuit read as the same scalloped chain of floor tiles.
	var surface := Line2D.new()
	surface.name = "TrackSurface"
	surface.points = centerline
	surface.closed = true
	surface.width = HALF_WIDTH * 1.82
	surface.texture = texture
	surface.texture_mode = Line2D.LINE_TEXTURE_TILE
	surface.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	surface.default_color = Color(modulate_value, modulate_value, modulate_value, 0.52)
	surface.joint_mode = Line2D.LINE_JOINT_ROUND
	surface.begin_cap_mode = Line2D.LINE_CAP_ROUND
	surface.end_cap_mode = Line2D.LINE_CAP_ROUND
	surface.antialiased = true
	surface.z_index = -9
	parent.add_child(surface)


static func _add_floor_tiles(parent: Node, texture_path: String, rect_origin: Vector2, rect_size: Vector2, columns: int, rows: int, scale: Vector2) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var tiles := Node2D.new()
	tiles.name = "FloorTiles"
	tiles.z_index = -21
	parent.add_child(tiles)
	var tile_width := rect_size.x / float(columns)
	var tile_height := rect_size.y / float(rows)
	for column in columns:
		for row in rows:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			sprite.position = rect_origin + Vector2(tile_width * (column + 0.5), tile_height * (row + 0.5))
			sprite.scale = Vector2(tile_width / 1024.0, tile_height / 1024.0) * scale * 0.98
			sprite.modulate = Color(1.35, 1.35, 1.35)
			tiles.add_child(sprite)


static func _add_start_banner(parent: Node, start: Vector2, tangent: Vector2, corridor: PackedVector2Array) -> void:
	var normal := tangent.rotated(PI * 0.5)
	var along := Vector2(tangent.y, -tangent.x)
	if Geometry2D.is_point_in_polygon(start + normal * (HALF_WIDTH + 60.0), corridor):
		normal = -normal
	var banner_center := start - normal * (HALF_WIDTH + 46.0)
	for block in 6:
		var center := banner_center + along * (float(block) - 2.5) * 22.0
		_add_polygon(parent, "BannerBlock%d" % block, PackedVector2Array([
			center - tangent * 22.0 - along * 11.0,
			center + tangent * 22.0 - along * 11.0,
			center + tangent * 22.0 + along * 11.0,
			center - tangent * 22.0 + along * 11.0,
		]), Color("f2ead7") if block % 2 == 0 else Color("c94f38"), -8)


static func _mark_owned(root: Node) -> void:
	for child in root.get_children():
		child.owner = root
		if child.scene_file_path.is_empty():
			_assign_owners(child, root)


static func _assign_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_assign_owners(child, owner)
