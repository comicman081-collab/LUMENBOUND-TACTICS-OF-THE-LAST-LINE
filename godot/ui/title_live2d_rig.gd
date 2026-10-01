extends RefCounted

## Rig numbers for the title "shader puppet" (ui/title_live2d.gd, ui/shaders/title_puppet.gdshader).
## Every coordinate is in source pixels of the hero illustration, measured on the art the
## masks were cut for (tools/art/build_title_live2d.py writes the masks and a manifest with
## the source hashes). Re-measure these if the illustration is ever replaced.

const ASSET_DIR := "res://assets/title_live2d/"

# Eye rig per eye: [cx, cy, theta, half width, lash top, lower lid, lash thickness, iris x, iris y, iris radius, skew,
#                   lid colour at the crease (r, g, b), lid colour above the lash band (r, g, b)]
const HEROES := {
	"CHR001": {
		"hero": "chr001_hero.png",
		"mask_a": "chr001_mask_a.png",
		"mask_b": "chr001_mask_b.png",
		"size": Vector2(1086, 1448),
		"pad": Vector4(64, 64, 64, 64),
		# the static title layout this replaces: a box in stage fractions, art fitted and centred inside
		"box": Rect2(0.59, 0.015, 0.40, 1.02),
		"body_geo": Vector4(540, 1425, 700, 0),
		"neck_geo": Vector4(512, 250, 238, 300),
		"breath_geo": Vector4(260, 560, 4.0, 0),
		"exp_geo": Vector4(250, 330, 520, 700),
		"face_geo": Vector4(512, 192, 58, 64),
		"flutter_geo": Vector4(60, 360, 0, 0),
		"eyes": [
			[485.2, 189.6, 0.35, 14.5, -5.5, 7.2, 3.5, 6.0, 1.5, 6.5, 0.0, 0.86, 0.60, 0.46, 0.66, 0.40, 0.30],
			[536.0, 180.8, -0.08, 16.0, -7.0, 7.4, 4.0, 2.0, 1.5, 7.5, 0.2, 0.90, 0.69, 0.55, 0.74, 0.47, 0.35],
		],
		# mass-spring chains, one per hair mask channel. radii: distance from the root where node i takes over
		"chains": {
			"a": {"root": Vector2(585, 58), "radii": [36, 110, 190, 270, 360, 470],
				"freq": [2.4, 1.9, 1.5, 1.2, 0.95], "zeta": [0.55, 0.5, 0.45, 0.42, 0.4],
				"wind": [0.3, 0.7, 1.1, 1.5, 1.9], "inertia": [0.5, 0.9, 1.2, 1.5, 1.8], "k0": 0.35, "phase": 1.7, "gain": 0.9},
			"b": {"root": Vector2(445, 100), "radii": [40, 110, 180, 260, 340, 440],
				"freq": [2.2, 1.7, 1.35, 1.05, 0.8], "zeta": [0.55, 0.5, 0.45, 0.42, 0.4],
				"wind": [0.2, 0.5, 0.9, 1.3, 1.7], "inertia": [0.4, 0.8, 1.1, 1.4, 1.7], "k0": 0.35, "phase": 0.3, "gain": 1.0},
			"c": {"root": Vector2(520, 92), "radii": [30, 80, 160, 260, 360, 450],
				"freq": [2.8, 2.3, 1.9, 1.5], "zeta": [0.6, 0.55, 0.5, 0.45],
				"wind": [0.5, 1.2, 2.2, 3.0], "inertia": [0.6, 1.1, 1.7, 2.3], "k0": 0.4, "phase": 2.9, "gain": 0.6},
		},
		# hanging weapon: chain and lantern are their own layer (tools/art/build_title_live2d.py cuts it out of the hero
		# image), rotated rigidly about the grip. rect = x, y, w, h of the layer in hero pixels, seam = the rows where
		# the hero image and the layer overlap and cross-fade. limit soft-caps the swing angle (rad).
		"lantern": {"file": "chr001_lantern.png", "rect": Vector4(129, 710, 178, 604), "seam": Vector2(722, 740)},
		"pendulum": {"pivot": Vector2(240, 725), "length": 430.0, "freq": 0.95, "zeta": 0.16, "drive": 0.020, "kick": 0.20, "impulse": 0.10, "bias": 0.012, "limit": 0.07},
		"cloth": {"amp": 7.0, "wave": 3.2, "freq": 0.012},
		"grade": Vector4(1.22, 0.82, 1.12, 0.0),
		"rim_color": Color(0.72, 1.0, 0.95),
		"emis_color": Color(0.30, 1.0, 0.92),
		"edge_color": Color(0.55, 1.0, 0.95),
		"glint_color": Color(1.0, 0.90, 0.62),
		"rim_dir": Vector2(0.86, -0.5),
		"reveal_delay": 0.8,
		"follow": 1.0,
	},
	"CHR002": {
		"hero": "chr002_hero.png",
		"mask_a": "chr002_mask_a.png",
		"mask_b": "chr002_mask_b.png",
		"size": Vector2(1048, 1536),
		"pad": Vector4(96, 64, 64, 64),
		"box": Rect2(0.49, 0.16, 0.32, 0.80),
		"body_geo": Vector4(520, 1450, 640, 0),
		"neck_geo": Vector4(540, 352, 336, 396),
		"breath_geo": Vector4(330, 520, 4.0, 0),
		"exp_geo": Vector4(360, 430, 560, 700),
		"face_geo": Vector4(528, 292, 62, 60),
		"flutter_geo": Vector4(100, 480, 0, 0),
		"eyes": [
			[502.0, 274.0, 0.42, 24.0, -6.2, 16.0, 5.2, 5.4, 8.2, 8.0, 0.17, 0.80, 0.66, 0.60, 0.66, 0.48, 0.42],
			[553.7, 294.3, -0.62, 15.0, -7.5, 5.0, 3.5, -5.0, -1.0, 5.5, -0.25, 0.66, 0.46, 0.40, 0.46, 0.28, 0.24],
		],
		"chains": {
			"a": {"root": Vector2(425, 170), "radii": [40, 130, 250, 380, 500, 640],
				"freq": [2.3, 1.9, 1.55, 1.25, 1.0], "zeta": [0.55, 0.5, 0.45, 0.42, 0.4],
				"wind": [0.6, 1.2, 2.0, 2.8, 3.6], "inertia": [0.6, 1.0, 1.5, 2.0, 2.6], "k0": 0.35, "phase": 0.9, "gain": 1.0},
			"b": {"root": Vector2(425, 170), "radii": [40, 130, 250, 380, 500, 640],
				"freq": [2.0], "zeta": [0.5], "wind": [0.0], "inertia": [0.0], "k0": 0.4, "phase": 0.0, "gain": 0.0},
			"c": {"root": Vector2(530, 95), "radii": [30, 70, 120, 180, 240, 300],
				"freq": [3.0, 2.5, 2.0], "zeta": [0.6, 0.55, 0.5],
				"wind": [0.5, 1.2, 2.2], "inertia": [0.6, 1.2, 1.9], "k0": 0.4, "phase": 2.2, "gain": 0.6},
		},
		"lantern": {},
		"pendulum": {},
		"cloth": {"amp": 0.0, "wave": 0.0, "freq": 0.012},
		"grade": Vector4(1.22, 0.82, 1.12, 0.0),
		"rim_color": Color(1.0, 0.74, 0.60),
		"emis_color": Color(1.0, 0.30, 0.20),
		"edge_color": Color(1.0, 0.78, 0.55),
		"glint_color": Color(1.0, 0.95, 0.88),
		"rim_dir": Vector2(0.86, -0.5),
		"reveal_delay": 0.45,
		"follow": 0.8,
	},
}

# back to front
const ORDER := ["CHR002", "CHR001"]
