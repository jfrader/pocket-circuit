extends SceneTree

const OUTPUT_DIR := "res://assets/textures/imagine"
const OUTLINE := "#2b2620"


func _initialize() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("PROP_ASSET_GENERATOR_2 FAIL: could not create %s: %s" % [OUTPUT_DIR, error_string(directory_error)])
		quit(1)
		return

	var assets: Array[Dictionary] = [
		{"name": "mug_top", "svg": _prop_svg(_mug_top(), "mug_top")},
		{"name": "bottle_top", "svg": _prop_svg(_bottle_top(), "bottle_top")},
		{"name": "plate_stack", "svg": _prop_svg(_plate_stack(), "plate_stack")},
		{"name": "vase_top", "svg": _prop_svg(_vase_top(), "vase_top")},
		{"name": "teapot_top", "svg": _prop_svg(_teapot_top(), "teapot_top")},
		{"name": "screwdriver", "svg": _prop_svg(_screwdriver(), "screwdriver")},
		{"name": "tape_roll", "svg": _prop_svg(_tape_roll(), "tape_roll")},
		{"name": "stapler_top", "svg": _prop_svg(_stapler_top(), "stapler_top")},
		{"name": "pencil", "svg": _prop_svg(_pencil(), "pencil")},
		{"name": "crayons", "svg": _prop_svg(_crayons(), "crayons")},
		{"name": "scissors_top", "svg": _prop_svg(_scissors_top(), "scissors_top")},
		{"name": "salt_shaker", "svg": _prop_svg(_salt_shaker(), "salt_shaker")},
		{"name": "keys_ring", "svg": _prop_svg(_keys_ring(), "keys_ring")},
		{"name": "matchbox", "svg": _prop_svg(_matchbox(), "matchbox")},
		{"name": "teacup_saucer", "svg": _prop_svg(_teacup_saucer(), "teacup_saucer")},
		{"name": "crumb_cluster", "svg": _decal_svg(_crumb_cluster(), "crumb_cluster")},
		{"name": "stain_ring", "svg": _decal_svg(_stain_ring(), "stain_ring")},
		{"name": "paper_sheet", "svg": _decal_svg(_paper_sheet(), "paper_sheet")},
		{"name": "sawdust_patch", "svg": _decal_svg(_sawdust_patch(), "sawdust_patch")},
		{"name": "oil_stain", "svg": _decal_svg(_oil_stain(), "oil_stain")},
	]

	for asset: Dictionary in assets:
		var name := String(asset["name"])
		var svg := String(asset["svg"])
		var image := Image.new()
		var load_error := image.load_svg_from_buffer(svg.to_utf8_buffer(), 4.0)
		if load_error != OK:
			push_error("PROP_ASSET_GENERATOR_2 FAIL: %s SVG: %s" % [name, error_string(load_error)])
			quit(1)
			return
		if image.get_width() != 1024 or image.get_height() != 1024:
			push_error("PROP_ASSET_GENERATOR_2 FAIL: %s rendered at %dx%d" % [name, image.get_width(), image.get_height()])
			quit(1)
			return
		var output_path := "%s/%s.png" % [OUTPUT_DIR, name]
		var save_error := image.save_png(output_path)
		if save_error != OK:
			push_error("PROP_ASSET_GENERATOR_2 FAIL: %s: %s" % [output_path, error_string(save_error)])
			quit(1)
			return
		print("SAVE %s OK" % output_path)
	quit(0)


func _prop_svg(body: String, title: String) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<title>%s</title>
<defs>
<radialGradient id="ceramic" cx="0.28" cy="0.22" r="0.92"><stop offset="0" stop-color="#fffdf5"/><stop offset="0.58" stop-color="#f1ead9"/><stop offset="1" stop-color="#c8bca8"/></radialGradient>
<radialGradient id="cream" cx="0.28" cy="0.22" r="0.92"><stop offset="0" stop-color="#fff2c7"/><stop offset="0.62" stop-color="#e8cf91"/><stop offset="1" stop-color="#b8995e"/></radialGradient>
<radialGradient id="glass" cx="0.27" cy="0.2" r="0.94"><stop offset="0" stop-color="#e8fbf2" stop-opacity="0.95"/><stop offset="0.55" stop-color="#8ec7b8" stop-opacity="0.84"/><stop offset="1" stop-color="#397568" stop-opacity="0.95"/></radialGradient>
<radialGradient id="metal" cx="0.25" cy="0.2" r="0.96"><stop offset="0" stop-color="#f2f7f7"/><stop offset="0.5" stop-color="#b8c3c7"/><stop offset="1" stop-color="#667278"/></radialGradient>
<radialGradient id="orange" cx="0.25" cy="0.2" r="0.96"><stop offset="0" stop-color="#ffb23d"/><stop offset="0.55" stop-color="#ee7625"/><stop offset="1" stop-color="#a83d1d"/></radialGradient>
<radialGradient id="yellow" cx="0.25" cy="0.2" r="0.96"><stop offset="0" stop-color="#ffe982"/><stop offset="0.58" stop-color="#f3bd31"/><stop offset="1" stop-color="#bc771d"/></radialGradient>
<radialGradient id="red" cx="0.25" cy="0.2" r="0.96"><stop offset="0" stop-color="#ff8371"/><stop offset="0.58" stop-color="#df493b"/><stop offset="1" stop-color="#8f2928"/></radialGradient>
<radialGradient id="blue" cx="0.25" cy="0.2" r="0.96"><stop offset="0" stop-color="#82d2ee"/><stop offset="0.58" stop-color="#3b91bf"/><stop offset="1" stop-color="#245574"/></radialGradient>
<radialGradient id="green" cx="0.25" cy="0.2" r="0.96"><stop offset="0" stop-color="#91da78"/><stop offset="0.58" stop-color="#4ca64f"/><stop offset="1" stop-color="#286338"/></radialGradient>
<radialGradient id="dark" cx="0.25" cy="0.2" r="0.96"><stop offset="0" stop-color="#737980"/><stop offset="0.58" stop-color="#40464d"/><stop offset="1" stop-color="#20252a"/></radialGradient>
<radialGradient id="wood" cx="0.25" cy="0.2" r="0.96"><stop offset="0" stop-color="#db9b5e"/><stop offset="0.58" stop-color="#aa6236"/><stop offset="1" stop-color="#6e3b29"/></radialGradient>
</defs>
<g stroke="%s" stroke-width="10" stroke-linejoin="round" stroke-linecap="round">%s</g>
</svg>""" % [title, OUTLINE, body]


func _decal_svg(body: String, title: String) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<title>%s</title>
%s
</svg>""" % [title, body]


func _mug_top() -> String:
	return """
<path fill="url(#ceramic)" d="M174 80 C218 70 232 96 222 126 C216 145 199 154 177 149 L174 126 C194 132 202 119 201 108 C200 96 190 93 174 99 Z"/>
<circle fill="url(#ceramic)" cx="112" cy="126" r="76"/>
<circle fill="#6f3f24" cx="112" cy="126" r="55" stroke-width="8"/>
<circle fill="#3b2119" cx="112" cy="126" r="43" stroke="none"/>
<path fill="none" stroke="#f9f0dc" stroke-width="9" opacity="0.85" d="M69 91 A61 61 0 0 1 118 67"/>
<path fill="none" stroke="#8f806e" stroke-width="8" opacity="0.7" d="M149 171 A69 69 0 0 0 177 128"/>
<ellipse fill="#d8a268" stroke="none" opacity="0.55" cx="91" cy="106" rx="18" ry="9"/>
"""


func _bottle_top() -> String:
	return """
<circle fill="url(#glass)" cx="128" cy="128" r="84"/>
<circle fill="#6fa896" cx="128" cy="128" r="57" stroke-width="8"/>
<circle fill="url(#metal)" cx="128" cy="128" r="34" stroke-width="8"/>
<circle fill="#4b8a74" cx="128" cy="128" r="19" stroke-width="6"/>
<path fill="none" stroke="#effff8" stroke-width="9" opacity="0.75" d="M72 108 A62 62 0 0 1 111 72"/>
<path fill="none" stroke="#285c51" stroke-width="10" opacity="0.6" d="M166 178 A73 73 0 0 0 197 137"/>
<path fill="none" stroke="#e7ece9" stroke-width="4" d="M109 111 L147 111 M106 123 L150 123 M106 135 L150 135 M109 147 L147 147"/>
"""


func _plate_stack() -> String:
	return """
<circle fill="#b6aa97" cx="136" cy="139" r="86"/>
<circle fill="url(#ceramic)" cx="130" cy="132" r="86"/>
<circle fill="url(#cream)" cx="124" cy="125" r="70" stroke-width="8"/>
<circle fill="url(#ceramic)" cx="118" cy="118" r="54" stroke-width="8"/>
<circle fill="#f9f4e8" cx="118" cy="118" r="35" stroke-width="6"/>
<path fill="none" stroke="#ffffff" stroke-width="8" opacity="0.78" d="M76 87 A50 50 0 0 1 111 69"/>
<path fill="none" stroke="#a89880" stroke-width="9" opacity="0.62" d="M151 175 A66 66 0 0 0 180 140"/>
"""


func _vase_top() -> String:
	return """
<circle fill="url(#blue)" cx="128" cy="132" r="76"/>
<circle fill="#2d637f" cx="128" cy="132" r="39" stroke-width="8"/>
<circle fill="#173c52" cx="128" cy="132" r="24" stroke-width="6"/>
<path fill="none" stroke="#b7ecf8" stroke-width="9" opacity="0.75" d="M78 103 A58 58 0 0 1 116 77"/>
<path fill="none" stroke="#173d57" stroke-width="10" opacity="0.65" d="M161 184 A68 68 0 0 0 194 146"/>
<g stroke-width="5">
<circle fill="#f26c62" cx="74" cy="75" r="13"/><circle fill="#f2c74d" cx="105" cy="58" r="12"/>
<circle fill="#df72b2" cx="147" cy="59" r="13"/><circle fill="#ef8c45" cx="181" cy="80" r="12"/>
<circle fill="#7acb65" cx="190" cy="117" r="10"/><circle fill="#68aee1" cx="62" cy="116" r="10"/>
</g>
<g fill="#f7d76b" stroke="none"><circle cx="74" cy="75" r="4"/><circle cx="105" cy="58" r="4"/><circle cx="147" cy="59" r="4"/><circle cx="181" cy="80" r="4"/></g>
"""


func _teapot_top() -> String:
	return """
<path fill="url(#ceramic)" d="M70 102 C45 91 27 101 20 119 C35 117 50 122 66 137 Z"/>
<path fill="url(#ceramic)" fill-rule="evenodd" d="M181 87 C229 75 243 111 230 143 C220 169 199 178 177 168 L183 144 C201 153 210 139 210 125 C209 107 198 101 181 109 Z"/>
<circle fill="url(#cream)" cx="121" cy="130" r="76"/>
<circle fill="#d4b270" cx="121" cy="130" r="54" stroke-width="7"/>
<circle fill="url(#ceramic)" cx="121" cy="130" r="43" stroke-width="7"/>
<circle fill="url(#yellow)" cx="121" cy="130" r="17" stroke-width="7"/>
<path fill="none" stroke="#fff5d6" stroke-width="9" opacity="0.75" d="M72 103 A59 59 0 0 1 109 76"/>
<path fill="none" stroke="#9c7444" stroke-width="10" opacity="0.65" d="M151 184 A67 67 0 0 0 184 146"/>
"""


func _screwdriver() -> String:
	return """
<g transform="rotate(-35 128 128)">
<rect fill="url(#orange)" x="93" y="31" width="70" height="104" rx="28"/>
<path fill="none" stroke="#ffbd51" stroke-width="8" opacity="0.7" d="M108 48 V108"/>
<path fill="none" stroke="#a13b1f" stroke-width="9" opacity="0.75" d="M145 55 V112"/>
<path fill="url(#metal)" d="M115 133 H141 V215 L134 230 H122 L115 215 Z"/>
<path fill="#58656b" d="M111 211 H145 L138 232 H118 Z" stroke-width="7"/>
<path fill="none" stroke="#f0f6f6" stroke-width="6" opacity="0.7" d="M123 145 V204"/>
</g>
"""


func _tape_roll() -> String:
	return """
<path fill="url(#cream)" d="M158 160 C188 169 214 184 229 205 L209 226 C188 207 167 196 142 191 Z"/>
<circle fill="url(#yellow)" cx="112" cy="119" r="82"/>
<circle fill="#b77b24" cx="112" cy="119" r="45" stroke-width="8"/>
<circle fill="#ffffff" fill-opacity="0.2" cx="112" cy="119" r="30" stroke-width="7"/>
<path fill="none" stroke="#fff0a2" stroke-width="9" opacity="0.8" d="M57 89 A65 65 0 0 1 101 54"/>
<path fill="none" stroke="#9c5d1d" stroke-width="10" opacity="0.65" d="M145 178 A73 73 0 0 0 183 136"/>
<path fill="none" stroke="#f9d768" stroke-width="5" opacity="0.7" d="M172 181 L211 211"/>
"""


func _stapler_top() -> String:
	return """
<g transform="rotate(-12 128 128)">
<rect fill="#252a30" x="58" y="31" width="140" height="194" rx="34"/>
<rect fill="url(#dark)" x="70" y="42" width="116" height="170" rx="27" stroke-width="8"/>
<path fill="url(#metal)" d="M91 57 H165 Q177 57 177 72 V166 Q177 180 164 180 H92 Q79 180 79 166 V72 Q79 57 91 57 Z" stroke-width="8"/>
<path fill="#5c666c" d="M91 162 H165 V185 Q128 197 91 185 Z" stroke-width="6"/>
<path fill="none" stroke="#f8ffff" stroke-width="7" opacity="0.68" d="M96 71 H150"/>
<path fill="none" stroke="#171a1e" stroke-width="7" d="M77 193 H179"/>
<circle fill="#aeb9bd" cx="128" cy="190" r="7" stroke-width="5"/>
</g>
"""


func _pencil() -> String:
	return """
<g transform="rotate(-42 128 128)">
<path fill="url(#yellow)" d="M99 41 L128 25 L157 41 V186 L99 186 Z"/>
<path fill="#e7a92a" d="M128 25 L145 43 V186 H128 Z" stroke="none" opacity="0.68"/>
<rect fill="#d6a2a2" x="99" y="41" width="58" height="38" rx="8"/>
<path fill="#ef91a0" d="M107 47 H130 V73 H107 Z" stroke="none"/>
<rect fill="url(#metal)" x="99" y="76" width="58" height="22" stroke-width="7"/>
<path fill="url(#wood)" d="M99 186 H157 L128 232 Z"/>
<path fill="#343238" d="M116 214 L128 232 L140 214 Z" stroke-width="5"/>
<path fill="none" stroke="#fff19a" stroke-width="7" opacity="0.72" d="M110 108 V176"/>
</g>
"""


func _crayons() -> String:
	return """
<g transform="rotate(-8 128 128)">
<g><path fill="url(#red)" d="M47 75 H99 V194 L73 224 L47 194 Z"/><path fill="#f5b08d" d="M47 104 H99 V128 H47 Z" stroke-width="6"/><path fill="none" stroke="#ff9b8d" stroke-width="6" d="M60 84 V185"/></g>
<g transform="translate(55 -18)"><path fill="url(#blue)" d="M47 75 H99 V194 L73 224 L47 194 Z"/><path fill="#a6d8e8" d="M47 104 H99 V128 H47 Z" stroke-width="6"/><path fill="none" stroke="#a8e7fa" stroke-width="6" d="M60 84 V185"/></g>
<g transform="translate(110 5)"><path fill="url(#green)" d="M47 75 H99 V194 L73 224 L47 194 Z"/><path fill="#b8df9f" d="M47 104 H99 V128 H47 Z" stroke-width="6"/><path fill="none" stroke="#b9ec9f" stroke-width="6" d="M60 84 V185"/></g>
</g>
"""


func _scissors_top() -> String:
	return """
<g transform="rotate(12 128 128)">
<path fill="url(#metal)" d="M111 127 L39 32 Q31 22 43 20 Q54 19 61 30 L129 112 Z"/>
<path fill="url(#metal)" d="M130 126 L205 31 Q213 21 224 27 Q234 33 226 43 L147 142 Z"/>
<circle fill="#7a858a" cx="129" cy="129" r="14" stroke-width="7"/>
<path fill="url(#orange)" fill-rule="evenodd" d="M112 139 C86 145 55 157 43 184 C30 215 65 236 91 218 C107 207 117 183 126 158 Z M62 190 A18 18 0 1 0 96 178 A18 18 0 1 0 62 190 Z"/>
<path fill="url(#orange)" fill-rule="evenodd" d="M143 139 C168 147 198 161 210 187 C223 216 190 236 164 218 C148 207 139 183 132 158 Z M166 181 A18 18 0 1 0 198 194 A18 18 0 1 0 166 181 Z"/>
<path fill="none" stroke="#ffffff" stroke-width="6" opacity="0.7" d="M52 39 L112 116 M205 45 L146 119"/>
</g>
"""


func _salt_shaker() -> String:
	return """
<circle fill="url(#ceramic)" cx="128" cy="128" r="82"/>
<circle fill="url(#metal)" cx="128" cy="128" r="59" stroke-width="8"/>
<path fill="none" stroke="#ffffff" stroke-width="9" opacity="0.72" d="M76 99 A62 62 0 0 1 116 72"/>
<path fill="none" stroke="#7c8588" stroke-width="10" opacity="0.65" d="M159 184 A70 70 0 0 0 194 144"/>
<g fill="#3a4145" stroke="none">
<circle cx="103" cy="99" r="6"/><circle cx="128" cy="92" r="6"/><circle cx="153" cy="99" r="6"/>
<circle cx="92" cy="123" r="6"/><circle cx="116" cy="119" r="6"/><circle cx="140" cy="119" r="6"/><circle cx="164" cy="123" r="6"/>
<circle cx="103" cy="146" r="6"/><circle cx="128" cy="151" r="6"/><circle cx="153" cy="146" r="6"/>
</g>
"""


func _keys_ring() -> String:
	return """
<circle fill="none" stroke="url(#metal)" stroke-width="16" cx="105" cy="82" r="46"/>
<g transform="rotate(-24 112 134)">
<path fill="url(#metal)" d="M84 103 A30 30 0 1 0 124 103 L133 195 H154 V218 H129 V205 H111 V192 H96 Z"/>
<circle fill="#59666b" cx="104" cy="84" r="13" stroke-width="6"/>
<path fill="none" stroke="#f7ffff" stroke-width="6" opacity="0.72" d="M111 112 L123 183"/>
</g>
<g transform="rotate(30 139 139)">
<path fill="url(#cream)" d="M125 100 A27 27 0 1 0 159 100 L166 185 H186 V207 H163 V196 H145 V182 H132 Z"/>
<circle fill="#9b7b44" cx="142" cy="84" r="11" stroke-width="6"/>
<path fill="none" stroke="#fff2b2" stroke-width="6" opacity="0.7" d="M148 110 L157 174"/>
</g>
"""


func _matchbox() -> String:
	return """
<g transform="rotate(-13 128 128)">
<rect fill="url(#wood)" x="43" y="62" width="170" height="132" rx="16"/>
<rect fill="url(#red)" x="55" y="50" width="146" height="132" rx="14" stroke-width="8"/>
<rect fill="#f2d8a0" x="75" y="75" width="106" height="82" rx="10" stroke-width="7"/>
<path fill="#e45b43" d="M100 128 C114 92 151 92 164 128 C147 115 118 115 100 128 Z" stroke-width="6"/>
<rect fill="#75402f" x="56" y="164" width="144" height="30" rx="7" stroke-width="7"/>
<g fill="#c98a64" stroke="none"><circle cx="75" cy="179" r="3"/><circle cx="91" cy="173" r="3"/><circle cx="108" cy="184" r="3"/><circle cx="127" cy="175" r="3"/><circle cx="145" cy="184" r="3"/><circle cx="164" cy="174" r="3"/><circle cx="183" cy="182" r="3"/></g>
<path fill="none" stroke="#fff3cc" stroke-width="7" opacity="0.7" d="M72 65 H164"/>
</g>
"""


func _teacup_saucer() -> String:
	return """
<circle fill="url(#cream)" cx="118" cy="128" r="91"/>
<circle fill="url(#ceramic)" cx="118" cy="128" r="73" stroke-width="8"/>
<path fill="url(#ceramic)" d="M169 91 C211 81 228 107 220 134 C214 156 194 166 171 158 L170 136 C190 142 198 131 198 118 C197 106 188 102 169 109 Z"/>
<circle fill="url(#blue)" cx="112" cy="124" r="55"/>
<circle fill="#704226" cx="112" cy="124" r="37" stroke-width="7"/>
<ellipse fill="#d9a36c" stroke="none" opacity="0.58" cx="98" cy="111" rx="15" ry="8"/>
<path fill="none" stroke="#fffdf0" stroke-width="8" opacity="0.72" d="M72 94 A49 49 0 0 1 104 77"/>
<path fill="none" stroke="#9e8461" stroke-width="9" opacity="0.6" d="M151 183 A76 76 0 0 0 184 150"/>
"""


func _crumb_cluster() -> String:
	return """
<g fill="#9a6237" opacity="0.88">
<circle cx="74" cy="99" r="7"/><circle cx="96" cy="76" r="5"/><circle cx="116" cy="112" r="8"/>
<circle cx="143" cy="87" r="6"/><circle cx="167" cy="109" r="9"/><circle cx="86" cy="140" r="6"/>
<circle cx="112" cy="161" r="5"/><circle cx="143" cy="145" r="7"/><circle cx="174" cy="157" r="5"/>
<circle cx="132" cy="127" r="4"/><circle cx="62" cy="126" r="4"/>
</g>
<g fill="#d09a5f" opacity="0.65"><circle cx="72" cy="96" r="2"/><circle cx="113" cy="108" r="3"/><circle cx="164" cy="105" r="3"/><circle cx="140" cy="142" r="2"/></g>
"""


func _stain_ring() -> String:
	return """
<circle fill="none" stroke="#82502f" stroke-width="13" stroke-linecap="round" stroke-dasharray="440 35 22 28" opacity="0.3" cx="128" cy="128" r="76"/>
<circle fill="none" stroke="#b1784d" stroke-width="5" opacity="0.22" cx="128" cy="128" r="68"/>
<path fill="none" stroke="#704329" stroke-width="7" stroke-linecap="round" opacity="0.22" d="M175 184 C191 192 196 203 193 216"/>
"""


func _paper_sheet() -> String:
	return """
<g transform="rotate(-6 128 128)">
<rect fill="#7a6e62" fill-opacity="0.18" x="55" y="47" width="168" height="190" rx="10"/>
<rect fill="#fffdf7" x="48" y="39" width="168" height="190" rx="10"/>
<path fill="#ece8df" d="M181 39 H206 Q216 39 216 49 V74 Z"/>
<rect fill="#8e969a" opacity="0.7" x="75" y="91" width="109" height="8" rx="4"/>
<rect fill="#aab0b2" opacity="0.62" x="75" y="119" width="88" height="8" rx="4"/>
<rect fill="#8e969a" opacity="0.55" x="75" y="147" width="118" height="8" rx="4"/>
<path fill="none" stroke="#ffffff" stroke-width="5" opacity="0.8" d="M60 55 H169"/>
</g>
"""


func _sawdust_patch() -> String:
	return """
<g fill="#c79758" opacity="0.55">
<circle cx="54" cy="119" r="4"/><circle cx="66" cy="92" r="3"/><circle cx="75" cy="147" r="5"/><circle cx="83" cy="113" r="3"/>
<circle cx="91" cy="76" r="4"/><circle cx="96" cy="168" r="3"/><circle cx="104" cy="132" r="5"/><circle cx="111" cy="96" r="3"/>
<circle cx="120" cy="61" r="3"/><circle cx="124" cy="157" r="4"/><circle cx="132" cy="118" r="3"/><circle cx="139" cy="182" r="4"/>
<circle cx="147" cy="83" r="5"/><circle cx="151" cy="144" r="3"/><circle cx="161" cy="108" r="4"/><circle cx="168" cy="167" r="3"/>
<circle cx="177" cy="130" r="5"/><circle cx="187" cy="93" r="3"/><circle cx="198" cy="145" r="4"/><circle cx="205" cy="118" r="3"/>
<circle cx="71" cy="178" r="3"/><circle cx="184" cy="186" r="4"/><circle cx="114" cy="201" r="3"/><circle cx="151" cy="205" r="3"/>
</g>
<g fill="#e1bb7d" opacity="0.48"><circle cx="80" cy="128" r="2"/><circle cx="99" cy="108" r="2"/><circle cx="118" cy="144" r="2"/><circle cx="142" cy="101" r="2"/><circle cx="164" cy="153" r="2"/><circle cx="186" cy="120" r="2"/></g>
"""


func _oil_stain() -> String:
	return """
<path fill="#89684e" fill-opacity="0.3" d="M42 137 C39 111 63 91 89 88 C104 64 137 55 158 72 C190 66 215 88 209 115 C229 137 211 166 187 174 C174 202 139 207 116 192 C87 204 54 188 57 162 C44 156 39 147 42 137 Z"/>
<path fill="#302c2a" fill-opacity="0.72" d="M51 136 C49 116 70 100 94 99 C108 76 136 68 156 83 C182 77 204 96 197 119 C215 138 197 158 178 163 C166 187 139 190 118 178 C94 190 68 175 70 155 C58 152 50 145 51 136 Z"/>
<path fill="#5a4b40" fill-opacity="0.48" d="M76 127 C84 101 112 91 132 99 C151 91 179 109 176 132 C181 152 155 166 136 157 C114 172 83 156 76 127 Z"/>
<ellipse fill="#9b8571" fill-opacity="0.2" cx="111" cy="113" rx="24" ry="12"/>
"""
