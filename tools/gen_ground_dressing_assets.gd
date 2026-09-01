extends SceneTree

const OUTPUT_DIR := "res://assets/textures/ground_dressing"


func _initialize() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("GROUND_DRESSING_ASSET_GENERATOR FAIL: could not create %s: %s" % [OUTPUT_DIR, error_string(directory_error)])
		quit(1)
		return

	var assets: Array[Dictionary] = [
		{"name": "kitchen_tablecloth_patch", "body": _kitchen_tablecloth_patch()},
		{"name": "kitchen_dish_towel_blue", "body": _kitchen_dish_towel_blue()},
		{"name": "kitchen_cleaning_rag_yellow", "body": _kitchen_cleaning_rag_yellow()},
		{"name": "kitchen_oven_mitt_red", "body": _kitchen_oven_mitt_red()},
		{"name": "workshop_dropcloth_patch", "body": _workshop_dropcloth_patch()},
		{"name": "workshop_shop_rag_red", "body": _workshop_shop_rag_red()},
		{"name": "workshop_cardboard_scrap", "body": _workshop_cardboard_scrap()},
		{"name": "workshop_sandpaper_sheet", "body": _workshop_sandpaper_sheet()},
		{"name": "office_desk_pad_patch", "body": _office_desk_pad_patch()},
		{"name": "office_envelope_stack", "body": _office_envelope_stack()},
		{"name": "office_sticky_notes", "body": _office_sticky_notes()},
		{"name": "office_notepad_page", "body": _office_notepad_page()},
	]

	for asset: Dictionary in assets:
		var asset_name := String(asset["name"])
		var image := Image.new()
		var load_error := image.load_svg_from_buffer(_svg(String(asset["body"]), asset_name).to_utf8_buffer(), 4.0)
		if load_error != OK:
			push_error("GROUND_DRESSING_ASSET_GENERATOR FAIL: %s SVG: %s" % [asset_name, error_string(load_error)])
			quit(1)
			return
		if image.get_width() != 1024 or image.get_height() != 1024:
			push_error("GROUND_DRESSING_ASSET_GENERATOR FAIL: %s rendered at %dx%d" % [asset_name, image.get_width(), image.get_height()])
			quit(1)
			return
		var output_path := "%s/%s.png" % [OUTPUT_DIR, asset_name]
		var save_error := image.save_png(output_path)
		if save_error != OK:
			push_error("GROUND_DRESSING_ASSET_GENERATOR FAIL: %s: %s" % [output_path, error_string(save_error)])
			quit(1)
			return
		print("SAVE %s OK" % output_path)
	quit(0)


func _svg(body: String, title: String) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<title>%s</title>
<defs>
<linearGradient id="creamCloth" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff2cf"/><stop offset="0.55" stop-color="#ead6aa"/><stop offset="1" stop-color="#c3a777"/></linearGradient>
<linearGradient id="blueCloth" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9dd4e5"/><stop offset="0.52" stop-color="#5d9fbd"/><stop offset="1" stop-color="#376d89"/></linearGradient>
<linearGradient id="yellowCloth" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffe58b"/><stop offset="0.55" stop-color="#efbd43"/><stop offset="1" stop-color="#b87a25"/></linearGradient>
<linearGradient id="redCloth" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e77761"/><stop offset="0.55" stop-color="#b8483f"/><stop offset="1" stop-color="#742f31"/></linearGradient>
<linearGradient id="canvas" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#dbc08c"/><stop offset="0.58" stop-color="#b48d59"/><stop offset="1" stop-color="#765638"/></linearGradient>
<linearGradient id="paper" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fffef7"/><stop offset="0.7" stop-color="#ece9de"/><stop offset="1" stop-color="#c9c3b5"/></linearGradient>
<linearGradient id="pad" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#547989"/><stop offset="0.58" stop-color="#344f5e"/><stop offset="1" stop-color="#253640"/></linearGradient>
<pattern id="blueCheck" width="24" height="24" patternUnits="userSpaceOnUse"><rect width="24" height="24" fill="#f5e5c5"/><rect width="12" height="12" fill="#6aa4bd" fill-opacity="0.72"/><rect x="12" y="12" width="12" height="12" fill="#6aa4bd" fill-opacity="0.72"/><path d="M0 12H24M12 0V24" stroke="#3e7997" stroke-width="2" stroke-opacity="0.55"/></pattern>
<pattern id="blueStripe" width="22" height="22" patternUnits="userSpaceOnUse"><rect width="22" height="22" fill="#f2e2bd"/><rect width="7" height="22" fill="#5595b3"/><rect x="10" width="3" height="22" fill="#8bbdd0"/></pattern>
<pattern id="padGrid" width="24" height="24" patternUnits="userSpaceOnUse"><rect width="24" height="24" fill="#3d5b69"/><path d="M0 0H24V24" fill="none" stroke="#7591a0" stroke-width="1" stroke-opacity="0.3"/></pattern>
</defs>
%s
</svg>""" % [title, body]


func _kitchen_tablecloth_patch() -> String:
	return """
<path fill="#372c29" fill-opacity="0.2" d="M26 60 Q42 49 62 55 Q86 43 108 54 Q132 44 155 54 Q182 43 205 57 Q228 55 236 72 L230 188 Q216 204 196 196 Q176 210 154 197 Q128 209 105 198 Q78 210 58 196 Q35 204 22 187 Z"/>
<path fill="url(#blueCheck)" stroke="#44677a" stroke-width="5" stroke-linejoin="round" d="M20 53 Q39 44 59 49 Q84 38 107 49 Q132 39 156 50 Q183 39 207 52 Q229 49 234 66 L228 182 Q214 198 195 190 Q174 204 153 191 Q127 203 104 192 Q77 204 57 190 Q33 198 18 181 Z"/>
<path fill="none" stroke="#fff3d3" stroke-width="4" stroke-dasharray="8 8" stroke-opacity="0.72" d="M31 65 Q68 55 105 62 T178 62 Q207 58 221 70 L217 173 Q198 182 180 176 T142 179 T101 177 T62 178 Q41 183 29 171 Z"/>
<path fill="none" stroke="#315c74" stroke-width="4" stroke-opacity="0.42" d="M67 50 Q73 112 61 190 M126 48 Q119 119 130 196 M188 52 Q178 119 191 190"/>
"""


func _kitchen_dish_towel_blue() -> String:
	return """
<g transform="rotate(-12 128 128)">
<path fill="#322a27" fill-opacity="0.22" d="M58 38 L198 52 L191 217 Q169 228 150 215 Q128 229 108 215 Q84 226 61 211 Z"/>
<path fill="url(#blueStripe)" stroke="#385c70" stroke-width="5" stroke-linejoin="round" d="M51 31 L191 45 L184 209 Q164 218 145 207 Q124 221 104 207 Q80 218 55 203 Z"/>
<path fill="none" stroke="#f8e8c6" stroke-width="5" stroke-opacity="0.78" d="M69 47 L67 193 M174 56 L167 197"/>
<path fill="none" stroke="#2f6f8e" stroke-width="4" stroke-opacity="0.55" d="M102 39 Q95 117 104 211 M143 43 Q133 126 145 208"/>
<g stroke="#385c70" stroke-width="3" stroke-linecap="round"><path d="M62 205L57 225M76 207L73 227M91 209L90 229M108 210L108 231M126 210L128 231M145 208L149 229M163 207L169 226M179 204L186 222"/></g>
</g>
"""


func _kitchen_cleaning_rag_yellow() -> String:
	return """
<path fill="#3d3028" fill-opacity="0.2" d="M38 93 Q52 54 90 61 Q116 35 145 59 Q184 48 204 82 Q232 109 209 143 Q222 178 188 195 Q158 224 126 199 Q91 219 69 189 Q31 178 45 143 Q22 119 38 93 Z"/>
<path fill="url(#yellowCloth)" stroke="#865b2c" stroke-width="5" stroke-linejoin="round" d="M32 84 Q47 48 86 56 Q112 29 142 53 Q182 41 202 76 Q229 102 205 136 Q218 171 184 188 Q155 218 123 192 Q88 212 65 183 Q28 171 41 136 Q17 111 32 84 Z"/>
<path fill="none" stroke="#fff0a3" stroke-width="6" stroke-opacity="0.58" d="M53 94 Q86 73 111 91 T169 83 Q189 102 179 127 T192 166"/>
<path fill="none" stroke="#9f6727" stroke-width="5" stroke-opacity="0.48" d="M71 177 Q90 139 123 151 Q150 164 176 135 M93 57 Q114 94 144 101 Q173 107 201 84"/>
<path fill="none" stroke="#704725" stroke-width="3" stroke-dasharray="5 7" stroke-opacity="0.65" d="M43 92 Q59 62 88 66 Q118 46 146 65 Q179 55 194 82"/>
"""


func _kitchen_oven_mitt_red() -> String:
	return """
<g transform="rotate(19 128 128)">
<path fill="#342826" fill-opacity="0.22" d="M76 35 Q105 24 127 44 L142 73 Q153 47 174 55 Q197 63 193 88 Q191 111 170 128 L184 199 Q157 222 111 211 Q78 203 68 173 L52 87 Q46 52 76 35 Z"/>
<path fill="url(#redCloth)" stroke="#632e31" stroke-width="6" stroke-linejoin="round" d="M69 28 Q98 17 120 37 L136 66 Q147 40 168 48 Q191 56 187 81 Q185 104 164 121 L178 192 Q151 215 105 204 Q72 196 62 166 L46 80 Q40 45 69 28 Z"/>
<path fill="none" stroke="#f39a7f" stroke-width="4" stroke-opacity="0.55" d="M60 67 L157 183 M51 101 L137 204 M84 28 L177 135 M112 25 L184 104"/>
<path fill="none" stroke="#fff0cf" stroke-width="5" stroke-dasharray="6 7" stroke-opacity="0.72" d="M67 38 Q95 29 111 45 L139 94 Q151 62 169 63"/>
<ellipse fill="none" stroke="#6b3434" stroke-width="6" cx="126" cy="174" rx="35" ry="18"/>
</g>
"""


func _workshop_dropcloth_patch() -> String:
	return """
<path fill="#312b27" fill-opacity="0.22" d="M27 62 L74 42 L111 53 L152 38 L190 53 L231 48 L226 118 L236 181 L198 211 L157 199 L119 216 L82 199 L35 207 L41 151 L21 113 Z"/>
<path fill="url(#canvas)" stroke="#63482f" stroke-width="6" stroke-linejoin="round" d="M20 54 L70 35 L109 47 L150 31 L188 46 L232 40 L226 111 L237 174 L195 204 L155 192 L116 210 L79 192 L28 201 L35 145 L14 105 Z"/>
<path fill="none" stroke="#ead09a" stroke-width="5" stroke-opacity="0.5" d="M39 77 Q83 58 112 77 Q153 57 204 66 M31 139 Q77 121 113 142 Q154 121 222 136"/>
<g fill="#516a70" fill-opacity="0.52"><circle cx="70" cy="102" r="9"/><circle cx="88" cy="111" r="5"/><circle cx="178" cy="86" r="12"/><circle cx="191" cy="101" r="5"/></g>
<g fill="#8b4034" fill-opacity="0.55"><circle cx="143" cy="161" r="10"/><circle cx="157" cy="169" r="5"/><circle cx="56" cy="166" r="7"/></g>
<path fill="none" stroke="#6c4d31" stroke-width="3" stroke-dasharray="7 8" d="M34 66 L68 49 L108 61 L151 45 L190 60 L216 56"/>
"""


func _workshop_shop_rag_red() -> String:
	return """
<path fill="#302725" fill-opacity="0.22" d="M31 101 Q39 60 77 63 Q99 39 129 59 Q158 37 184 63 Q221 70 218 108 Q239 137 211 162 Q202 202 162 199 Q132 222 105 200 Q68 215 50 183 Q15 160 37 130 Q18 116 31 101 Z"/>
<path fill="url(#redCloth)" stroke="#5d3030" stroke-width="5" stroke-linejoin="round" d="M25 93 Q33 52 72 57 Q94 32 125 52 Q155 30 181 56 Q217 63 213 101 Q235 130 207 155 Q198 195 158 192 Q128 215 101 193 Q64 208 45 176 Q10 153 32 123 Q12 108 25 93 Z"/>
<path fill="none" stroke="#ef8e78" stroke-width="6" stroke-opacity="0.45" d="M45 92 Q82 75 107 95 T167 80 Q194 94 196 121 M57 171 Q94 144 126 158 Q155 172 190 150"/>
<path fill="#272728" fill-opacity="0.46" d="M82 91 Q103 69 124 88 Q138 102 126 120 Q102 133 82 114 Z M148 139 Q165 126 181 142 Q184 162 164 169 Q145 162 148 139 Z"/>
"""


func _workshop_cardboard_scrap() -> String:
	return """
<g transform="rotate(-8 128 128)">
<path fill="#332923" fill-opacity="0.22" d="M34 57 L218 46 L226 201 L184 214 L151 203 L111 218 L77 205 L31 214 Z"/>
<path fill="#b98750" stroke="#68462e" stroke-width="6" stroke-linejoin="round" d="M27 49 L212 38 L220 193 L180 207 L148 196 L108 211 L74 198 L24 207 Z"/>
<path fill="none" stroke="#d8ad72" stroke-width="4" stroke-opacity="0.7" d="M46 65 L196 56 M43 93 L199 84 M40 122 L202 113 M37 152 L205 143 M34 181 L208 172"/>
<path fill="#d8c09c" fill-opacity="0.82" stroke="#77624b" stroke-width="3" d="M103 42 L142 40 L150 203 L111 207 Z"/>
<path fill="none" stroke="#6f4b30" stroke-width="5" stroke-dasharray="12 8" d="M31 127 L215 116"/>
<path fill="none" stroke="#4d382a" stroke-width="4" d="M68 80 Q83 68 97 80 M166 156 Q182 140 198 155"/>
</g>
"""


func _workshop_sandpaper_sheet() -> String:
	return """
<g transform="rotate(11 128 128)">
<rect fill="#332b27" fill-opacity="0.2" x="42" y="34" width="178" height="194" rx="12"/>
<path fill="#9a7049" stroke="#5f4634" stroke-width="6" d="M34 27 H204 Q215 27 215 38 V207 Q215 218 204 218 H45 Q34 218 34 207 Z"/>
<path fill="#c49a63" d="M35 28 H204 Q215 28 215 39 V68 H35 Z" stroke="none"/>
<path fill="#e5d4b5" stroke="#6e5841" stroke-width="4" d="M174 28 H204 Q215 28 215 39 V70 Z"/>
<g fill="#4f4238" fill-opacity="0.65"><circle cx="60" cy="91" r="2"/><circle cx="83" cy="81" r="2"/><circle cx="107" cy="99" r="2"/><circle cx="130" cy="84" r="2"/><circle cx="157" cy="103" r="2"/><circle cx="187" cy="87" r="2"/><circle cx="67" cy="131" r="2"/><circle cx="95" cy="146" r="2"/><circle cx="122" cy="126" r="2"/><circle cx="150" cy="151" r="2"/><circle cx="183" cy="132" r="2"/><circle cx="62" cy="182" r="2"/><circle cx="89" cy="194" r="2"/><circle cx="127" cy="177" r="2"/><circle cx="164" cy="194" r="2"/><circle cx="192" cy="174" r="2"/></g>
<text x="55" y="62" font-family="sans-serif" font-size="20" font-weight="700" fill="#684a31">P120</text>
</g>
"""


func _office_desk_pad_patch() -> String:
	return """
<rect fill="#22292d" fill-opacity="0.24" x="20" y="48" width="224" height="166" rx="27"/>
<rect fill="url(#padGrid)" stroke="#263b47" stroke-width="7" x="13" y="41" width="224" height="166" rx="27"/>
<rect fill="none" stroke="#91acb7" stroke-width="3" stroke-dasharray="7 7" stroke-opacity="0.72" x="27" y="55" width="196" height="138" rx="18"/>
<path fill="none" stroke="#a9c0ca" stroke-width="5" stroke-opacity="0.34" d="M47 80 H198 M47 105 H198 M47 130 H198 M47 155 H198"/>
<path fill="none" stroke="#1d2c34" stroke-width="8" stroke-opacity="0.45" d="M184 50 Q210 77 225 104"/>
"""


func _office_envelope_stack() -> String:
	return """
<g transform="rotate(-9 128 128)">
<rect fill="#313238" fill-opacity="0.22" x="37" y="60" width="190" height="137" rx="11"/>
<g transform="translate(12 14) rotate(8 128 128)"><rect fill="#d5ceb9" stroke="#777266" stroke-width="4" x="42" y="54" width="176" height="125" rx="9"/><path fill="#c1b9a5" d="M43 57 L130 126 L217 57" stroke="#777266" stroke-width="4" stroke-linejoin="round"/></g>
<rect fill="url(#paper)" stroke="#696a68" stroke-width="5" x="31" y="45" width="181" height="128" rx="10"/>
<path fill="#e4dfd2" stroke="#85847e" stroke-width="4" stroke-linejoin="round" d="M32 49 L121 122 L211 49"/>
<path fill="none" stroke="#b9b4a8" stroke-width="4" d="M32 169 L101 101 M211 169 L143 101"/>
<rect fill="#e9b65e" stroke="#8d6631" stroke-width="3" x="166" y="60" width="28" height="24" rx="3"/>
<path fill="none" stroke="#6d7880" stroke-width="4" d="M49 145 H98 M49 155 H83"/>
</g>
"""


func _office_sticky_notes() -> String:
	return """
<g transform="rotate(-5 128 128)">
<rect fill="#2b2d31" fill-opacity="0.18" x="44" y="47" width="100" height="100" rx="6"/>
<rect fill="#f6d85e" stroke="#9d7c2b" stroke-width="4" x="36" y="39" width="100" height="100" rx="6"/>
<path fill="#d1ad34" fill-opacity="0.45" d="M36 118 L57 139 H36 Z"/>
<path fill="none" stroke="#8e7535" stroke-width="4" stroke-linecap="round" d="M56 72 H113 M56 89 H105 M56 106 H91"/>
</g>
<g transform="rotate(11 164 153)">
<rect fill="#2b2d31" fill-opacity="0.16" x="111" y="101" width="105" height="105" rx="6"/>
<rect fill="#82c7c1" stroke="#477d79" stroke-width="4" x="103" y="93" width="105" height="105" rx="6"/>
<path fill="#4f9d96" fill-opacity="0.42" d="M103 176 L125 198 H103 Z"/>
<path fill="none" stroke="#386f6b" stroke-width="4" stroke-linecap="round" d="M125 126 H185 M125 143 H177 M125 160 H188"/>
</g>
<g transform="rotate(-17 88 181)"><rect fill="#ef9a86" stroke="#9b5549" stroke-width="4" x="45" y="143" width="78" height="72" rx="5"/><path fill="none" stroke="#984b43" stroke-width="4" d="M61 169 H105 M61 184 H96"/></g>
"""


func _office_notepad_page() -> String:
	return """
<g transform="rotate(7 128 128)">
<rect fill="#303137" fill-opacity="0.2" x="51" y="25" width="164" height="213" rx="12"/>
<path fill="url(#paper)" stroke="#686b70" stroke-width="5" d="M43 17 H196 Q207 17 207 28 V219 Q207 230 196 230 H54 Q43 230 43 219 Z"/>
<rect fill="#5a6974" x="43" y="17" width="164" height="34" rx="10"/>
<g fill="#ced5d8" stroke="#5e666c" stroke-width="3"><circle cx="67" cy="34" r="8"/><circle cx="95" cy="34" r="8"/><circle cx="123" cy="34" r="8"/><circle cx="151" cy="34" r="8"/><circle cx="179" cy="34" r="8"/></g>
<path fill="none" stroke="#91b8cd" stroke-width="3" stroke-opacity="0.7" d="M61 78 H188 M61 103 H188 M61 128 H188 M61 153 H188 M61 178 H188 M61 203 H163"/>
<path fill="none" stroke="#db786e" stroke-width="3" stroke-opacity="0.7" d="M77 58 V216"/>
<path fill="#ded9cb" stroke="#868277" stroke-width="3" d="M171 230 H196 Q207 230 207 219 V190 Z"/>
</g>
"""
