extends SceneTree

const OUTPUT_DIR := "res://assets/textures/imagine"
const OUTLINE := "#2b2620"


func _initialize() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("PROP_ASSET_GENERATOR FAIL: could not create %s: %s" % [OUTPUT_DIR, error_string(directory_error)])
		quit(1)
		return

	var assets: Array[Dictionary] = [
		{"name": "barrel_wood", "body": _barrel_wood()},
		{"name": "flower_pot", "body": _flower_pot()},
		{"name": "basketball", "body": _basketball()},
		{"name": "soccer_ball", "body": _soccer_ball()},
		{"name": "football", "body": _football()},
		{"name": "watermelon", "body": _watermelon()},
		{"name": "frying_pan", "body": _frying_pan()},
		{"name": "remote_control", "body": _remote_control()},
		{"name": "wrench", "body": _wrench()},
		{"name": "hammer", "body": _hammer()},
		{"name": "strawberry", "body": _strawberry()},
		{"name": "bolt", "body": _bolt()},
		{"name": "screw", "body": _screw()},
		{"name": "coin", "body": _coin()},
		{"name": "plant_small", "body": _plant_small()},
		{"name": "lamp_desk", "body": _lamp_desk()},
		{"name": "track_strip_workshop", "body": _track_strip_workshop()},
		{"name": "track_strip_office", "body": _track_strip_office()},
	]

	for asset: Dictionary in assets:
		var name := String(asset["name"])
		var svg := _svg(String(asset["body"]), name)
		var image := Image.new()
		var load_error := image.load_svg_from_buffer(svg.to_utf8_buffer(), 4.0)
		if load_error != OK:
			push_error("PROP_ASSET_GENERATOR FAIL: %s SVG: %s" % [name, error_string(load_error)])
			quit(1)
			return
		if image.get_width() != 256 or image.get_height() != 256:
			push_error("PROP_ASSET_GENERATOR FAIL: %s rendered at %dx%d" % [name, image.get_width(), image.get_height()])
			quit(1)
			return
		var output_path := "%s/%s.png" % [OUTPUT_DIR, name]
		var save_error := image.save_png(output_path)
		if save_error != OK:
			push_error("PROP_ASSET_GENERATOR FAIL: %s: %s" % [output_path, error_string(save_error)])
			quit(1)
			return
		print("SAVE %s OK" % output_path)
	quit(0)


func _svg(body: String, title: String) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 256 256">
<title>%s</title>
<g stroke="%s" stroke-width="8" stroke-linejoin="round" stroke-linecap="round">%s</g>
</svg>""" % [title, OUTLINE, body]


func _barrel_wood() -> String:
	return """
<path fill="#a96632" d="M67 49 Q128 24 189 49 L197 80 Q207 128 197 176 L189 207 Q128 232 67 207 L59 176 Q49 128 59 80 Z"/>
<path fill="#c98545" d="M91 43 Q80 128 91 213 M128 36 L128 220 M165 43 Q176 128 165 213"/>
<path fill="#657078" d="M58 77 Q128 95 198 77 L202 103 Q128 119 54 103 Z"/>
<path fill="#657078" d="M54 153 Q128 137 202 153 L198 179 Q128 161 58 179 Z"/>
<path fill="none" d="M67 49 Q128 67 189 49 M67 207 Q128 189 189 207"/>
"""


func _flower_pot() -> String:
	return """
<path fill="#3f9b54" d="M127 109 C95 84 78 59 89 39 C112 44 126 64 128 88 C133 58 151 39 177 37 C187 62 166 89 132 110 Z"/>
<path fill="#58b864" d="M126 109 C101 91 101 62 116 45 C132 57 136 83 128 104 C143 78 166 69 185 77 C179 101 156 113 129 116 Z"/>
<path fill="none" d="M128 109 L111 58 M129 108 L171 82 M128 106 L171 48"/>
<path fill="#d8683f" d="M79 118 L177 118 L165 211 Q128 227 91 211 Z"/>
<path fill="#ee8250" d="M70 108 Q128 96 186 108 L180 139 Q128 151 76 139 Z"/>
<path fill="none" d="M101 146 L108 207 M155 146 L148 207"/>
"""


func _basketball() -> String:
	return """
<circle fill="#ee8128" cx="128" cy="128" r="94"/>
<path fill="none" d="M34 128 H222 M128 34 V222 M62 62 C114 79 177 91 214 75 M42 181 C87 165 151 174 194 204"/>
"""


func _soccer_ball() -> String:
	return """
<circle fill="#f5f1df" cx="128" cy="128" r="94"/>
<g fill="#2b2620" stroke-width="6">
<path d="M128 82 L158 103 L147 138 L109 138 L98 103 Z"/>
<path d="M64 62 L90 48 L106 73 L88 98 L57 88 Z"/>
<path d="M166 48 L193 65 L198 94 L167 99 L149 73 Z"/>
<path d="M45 148 L71 131 L94 151 L84 182 L52 181 Z"/>
<path d="M172 149 L198 132 L218 153 L205 183 L176 181 Z"/>
<path d="M105 188 L137 177 L158 201 L142 220 L108 218 Z"/>
</g>
<g fill="none" stroke-width="6">
<path d="M106 73 L113 88 M149 73 L143 88 M88 98 L98 106 M167 99 L158 106 M94 151 L109 137 M172 149 L147 137 M84 182 L106 190 M176 181 L157 199"/>
</g>
"""


func _football() -> String:
	return """
<path fill="#9c552e" d="M33 128 C56 66 104 39 163 51 C194 58 219 88 223 128 C219 168 194 198 163 205 C104 217 56 190 33 128 Z"/>
<path fill="none" stroke="#f6eee0" stroke-width="9" d="M101 93 C127 102 147 102 171 92 M101 163 C126 153 148 153 171 164"/>
<path fill="none" stroke="#f6eee0" stroke-width="8" d="M132 99 L128 157 M113 111 L148 111 M111 128 L146 128 M110 145 L145 145"/>
"""


func _watermelon() -> String:
	return """
<path fill="#2f9b4c" d="M34 171 Q128 236 222 171 L208 141 Q128 193 48 141 Z"/>
<path fill="#8acb54" d="M48 141 Q128 193 208 141 L199 124 Q128 168 57 124 Z"/>
<path fill="#ef4f55" d="M57 124 Q128 36 199 124 Q128 168 57 124 Z"/>
<g fill="#2b2620" stroke="none">
<path d="M94 118 q8 -16 16 0 q-8 11 -16 0"/>
<path d="M124 94 q8 -16 16 0 q-8 11 -16 0"/>
<path d="M150 121 q8 -16 16 0 q-8 11 -16 0"/>
</g>
<path fill="none" stroke="#176f3d" d="M62 155 Q128 201 194 155 M88 176 L77 190 M128 190 V208 M168 176 L179 190"/>
"""


func _frying_pan() -> String:
	return """
<path fill="#43484b" d="M174 81 L211 45 Q222 35 231 45 L235 49 Q244 59 233 69 L191 104 Z"/>
<circle fill="#303437" cx="113" cy="137" r="78"/>
<circle fill="#555b5e" cx="113" cy="137" r="55"/>
<path fill="none" stroke="#6f7679" d="M84 111 Q113 91 142 111"/>
"""


func _remote_control() -> String:
	return """
<path fill="#3d444b" d="M87 31 Q128 20 169 31 L180 218 Q128 232 76 218 Z"/>
<rect fill="#20262b" x="98" y="47" width="60" height="31" rx="7"/>
<circle fill="#e45b4f" cx="105" cy="98" r="10"/>
<circle fill="#4fa46c" cx="151" cy="98" r="10"/>
<circle fill="#e2b83e" cx="128" cy="126" r="12"/>
<path fill="#778087" d="M106 151 H150 V190 H106 Z"/>
<path fill="none" d="M128 153 V188 M108 170 H148"/>
<circle fill="#58a7cf" cx="104" cy="207" r="7" stroke-width="5"/>
<circle fill="#d96aaf" cx="128" cy="210" r="7" stroke-width="5"/>
<circle fill="#68b95f" cx="152" cy="207" r="7" stroke-width="5"/>
"""


func _wrench() -> String:
	return """
<g transform="rotate(-35 128 128)">
<path fill="#aeb9c0" fill-rule="evenodd" d="M101 218 C82 202 80 175 96 157 L110 142 L110 99 C86 90 72 67 78 42 L105 68 L128 47 L105 21 C135 15 163 32 172 59 C180 84 166 108 143 116 L143 143 L158 158 C175 176 171 205 151 219 C136 230 116 229 101 218 Z M115 190 A14 14 0 1 0 143 190 A14 14 0 1 0 115 190 Z"/>
<path fill="none" stroke="#dce3e6" stroke-width="6" d="M126 113 V158"/>
</g>
"""


func _hammer() -> String:
	return """
<g transform="rotate(-35 128 128)">
<path fill="#9b5a31" d="M113 91 H143 L148 221 Q128 232 108 221 Z"/>
<path fill="#c17a3e" stroke-width="5" d="M118 105 L124 210 M139 104 L134 211"/>
<path fill="#aab4bb" d="M61 39 H169 Q183 39 190 53 L201 79 H149 V98 H91 V79 H56 Q45 79 45 68 V55 Q45 39 61 39 Z"/>
<path fill="#d6dde0" stroke-width="5" d="M61 52 H164"/>
</g>
"""


func _strawberry() -> String:
	return """
<path fill="#e7473f" d="M57 91 Q70 56 128 62 Q186 56 199 91 Q203 145 128 220 Q53 145 57 91 Z"/>
<path fill="#4eaa55" d="M128 72 C109 47 88 40 70 51 L85 77 C63 68 47 77 43 96 L87 101 C105 91 151 91 169 101 L213 96 C209 77 193 68 171 77 L186 51 C168 40 147 47 128 72 Z"/>
<g fill="#f5d46a" stroke="none">
<ellipse cx="92" cy="116" rx="5" ry="9"/><ellipse cx="128" cy="112" rx="5" ry="9"/><ellipse cx="164" cy="116" rx="5" ry="9"/>
<ellipse cx="109" cy="148" rx="5" ry="9"/><ellipse cx="147" cy="148" rx="5" ry="9"/><ellipse cx="128" cy="181" rx="5" ry="9"/>
</g>
"""


func _bolt() -> String:
	return """
<g transform="rotate(24 128 128)">
<path fill="#9da9b1" d="M77 37 L128 20 L179 37 L179 91 L128 108 L77 91 Z"/>
<path fill="#c5ced3" d="M102 101 H154 V211 Q128 228 102 211 Z"/>
<path fill="none" stroke="#727e86" stroke-width="7" d="M105 127 L152 115 M105 151 L152 139 M105 175 L152 163 M105 199 L152 187"/>
<path fill="none" stroke="#e0e5e7" stroke-width="6" d="M99 58 H157"/>
</g>
"""


func _screw() -> String:
	return """
<g transform="rotate(20 128 128)">
<circle fill="#aab5bc" cx="128" cy="60" r="43"/>
<path fill="none" d="M101 60 H155 M128 34 V86"/>
<path fill="#c5ced3" d="M113 101 H143 V203 L128 228 L113 203 Z"/>
<path fill="none" stroke="#707b83" stroke-width="7" d="M112 119 L144 108 M112 140 L144 129 M112 161 L144 150 M112 182 L144 171 M112 203 L143 192"/>
</g>
"""


func _coin() -> String:
	return """
<circle fill="#e7aa27" cx="128" cy="128" r="91"/>
<circle fill="#f5c94c" cx="128" cy="128" r="68"/>
<path fill="#d9961e" d="M128 72 L144 108 L184 112 L154 139 L163 179 L128 158 L93 179 L102 139 L72 112 L112 108 Z"/>
<path fill="none" stroke="#ffe27a" stroke-width="6" d="M73 84 A70 70 0 0 1 165 66"/>
"""


func _plant_small() -> String:
	return """
<path fill="#287e49" d="M127 130 C92 113 69 82 77 55 C105 55 128 82 128 114 C130 73 153 42 185 43 C194 79 166 113 130 131 Z"/>
<path fill="#58b95e" d="M128 133 C103 107 102 73 120 54 C140 73 141 106 130 128 C149 98 177 88 198 101 C188 129 159 143 129 140 Z"/>
<path fill="none" d="M128 132 L91 70 M130 130 L176 59 M130 135 L185 108 M129 127 L123 70"/>
<path fill="#4d86a6" d="M77 145 H179 L166 215 Q128 230 90 215 Z"/>
<path fill="#70a9c5" d="M70 135 Q128 122 186 135 L180 157 Q128 170 76 157 Z"/>
"""


func _lamp_desk() -> String:
	return """
<circle fill="#ffd95c" fill-opacity="0.16" stroke="none" cx="190" cy="66" r="57"/>
<circle fill="#ffe98a" fill-opacity="0.25" stroke="none" cx="190" cy="66" r="39"/>
<circle fill="#b98735" cx="65" cy="184" r="46"/>
<circle fill="#d8a94b" cx="65" cy="184" r="30" stroke-width="6"/>
<path fill="none" stroke="#b98735" stroke-width="22" d="M78 157 L117 119 L162 91"/>
<path fill="none" stroke="#f1c662" stroke-width="8" d="M81 154 L118 120 L158 94"/>
<circle fill="#d8a94b" cx="117" cy="119" r="16"/>
<circle fill="#f1c662" cx="117" cy="119" r="6" stroke-width="4"/>
<path fill="#c8963d" d="M158 43 Q190 26 222 43 L229 82 Q190 105 151 82 Z"/>
<path fill="#edbd50" d="M169 47 Q190 38 211 47 L216 69 Q190 82 164 69 Z" stroke-width="5"/>
<path fill="#ffd95c" d="M165 84 Q190 96 215 84 Q208 113 190 125 Q172 113 165 84 Z" stroke-width="6"/>
"""


func _track_strip_workshop() -> String:
	return """
<rect fill="#3a3633" stroke="none" x="0" y="0" width="256" height="256"/>
<g fill="none" stroke-linecap="round">
<path stroke="#4a4440" stroke-width="5" opacity="0.48" d="M-12 37 C38 30 77 45 132 37 S221 24 268 34"/>
<path stroke="#2d2a28" stroke-width="4" opacity="0.52" d="M-18 104 C37 113 80 95 137 103 S215 119 270 108"/>
<path stroke="#504944" stroke-width="3" opacity="0.42" d="M-14 179 C42 164 91 181 147 174 S217 161 268 170"/>
<path stroke="#302c2a" stroke-width="6" opacity="0.38" d="M-20 228 C37 236 75 218 129 226 S217 241 273 226"/>
</g>
<g stroke="none">
<circle fill="#5a514b" cx="22" cy="70" r="2"/><circle fill="#292624" cx="48" cy="18" r="2"/>
<circle fill="#514a45" cx="73" cy="139" r="3"/><circle fill="#2c2927" cx="101" cy="61" r="2"/>
<circle fill="#625850" cx="126" cy="199" r="2"/><circle fill="#292624" cx="154" cy="24" r="3"/>
<circle fill="#554c46" cx="181" cy="146" r="2"/><circle fill="#272422" cx="210" cy="75" r="2"/>
<circle fill="#60564e" cx="236" cy="213" r="3"/><circle fill="#2b2826" cx="31" cy="217" r="2"/>
<circle fill="#4f4843" cx="94" cy="235" r="2"/><circle fill="#282523" cx="225" cy="129" r="3"/>
</g>
"""


func _track_strip_office() -> String:
	return """
<rect fill="#39424d" stroke="none" x="0" y="0" width="256" height="256"/>
<g fill="none" stroke-linecap="round">
<path stroke="#46515e" stroke-width="4" opacity="0.34" d="M-12 55 C42 48 80 61 135 54 S220 43 268 52"/>
<path stroke="#2d3540" stroke-width="4" opacity="0.38" d="M-18 151 C35 160 86 143 141 151 S218 166 270 155"/>
<path stroke="#4b5663" stroke-width="3" opacity="0.28" d="M-14 224 C42 213 88 229 145 221 S218 210 270 220"/>
</g>
<g fill="#637080" stroke="none" opacity="0.38">
<circle cx="16" cy="16" r="2"/><circle cx="48" cy="16" r="2"/><circle cx="80" cy="16" r="2"/><circle cx="112" cy="16" r="2"/><circle cx="144" cy="16" r="2"/><circle cx="176" cy="16" r="2"/><circle cx="208" cy="16" r="2"/><circle cx="240" cy="16" r="2"/>
<circle cx="16" cy="48" r="2"/><circle cx="48" cy="48" r="2"/><circle cx="80" cy="48" r="2"/><circle cx="112" cy="48" r="2"/><circle cx="144" cy="48" r="2"/><circle cx="176" cy="48" r="2"/><circle cx="208" cy="48" r="2"/><circle cx="240" cy="48" r="2"/>
<circle cx="16" cy="80" r="2"/><circle cx="48" cy="80" r="2"/><circle cx="80" cy="80" r="2"/><circle cx="112" cy="80" r="2"/><circle cx="144" cy="80" r="2"/><circle cx="176" cy="80" r="2"/><circle cx="208" cy="80" r="2"/><circle cx="240" cy="80" r="2"/>
<circle cx="16" cy="112" r="2"/><circle cx="48" cy="112" r="2"/><circle cx="80" cy="112" r="2"/><circle cx="112" cy="112" r="2"/><circle cx="144" cy="112" r="2"/><circle cx="176" cy="112" r="2"/><circle cx="208" cy="112" r="2"/><circle cx="240" cy="112" r="2"/>
<circle cx="16" cy="144" r="2"/><circle cx="48" cy="144" r="2"/><circle cx="80" cy="144" r="2"/><circle cx="112" cy="144" r="2"/><circle cx="144" cy="144" r="2"/><circle cx="176" cy="144" r="2"/><circle cx="208" cy="144" r="2"/><circle cx="240" cy="144" r="2"/>
<circle cx="16" cy="176" r="2"/><circle cx="48" cy="176" r="2"/><circle cx="80" cy="176" r="2"/><circle cx="112" cy="176" r="2"/><circle cx="144" cy="176" r="2"/><circle cx="176" cy="176" r="2"/><circle cx="208" cy="176" r="2"/><circle cx="240" cy="176" r="2"/>
<circle cx="16" cy="208" r="2"/><circle cx="48" cy="208" r="2"/><circle cx="80" cy="208" r="2"/><circle cx="112" cy="208" r="2"/><circle cx="144" cy="208" r="2"/><circle cx="176" cy="208" r="2"/><circle cx="208" cy="208" r="2"/><circle cx="240" cy="208" r="2"/>
<circle cx="16" cy="240" r="2"/><circle cx="48" cy="240" r="2"/><circle cx="80" cy="240" r="2"/><circle cx="112" cy="240" r="2"/><circle cx="144" cy="240" r="2"/><circle cx="176" cy="240" r="2"/><circle cx="208" cy="240" r="2"/><circle cx="240" cy="240" r="2"/>
</g>
"""
