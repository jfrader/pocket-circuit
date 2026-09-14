
extends SceneTree

const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const PREVIEW := preload("res://scripts/race/circuit_route_preview.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const FIXTURE_SEED := 246810


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var identity := IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2)
	if not _expect(not identity.is_empty() and identity == IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2), "identity generation should be deterministic"):
		return
	if not _expect((identity["sub_seeds"] as Dictionary).keys() == IDENTITIES.DOMAINS, "every generator domain should have an explicit sub-seed"):
		return
	if not _expect((identity["fingerprints"] as Dictionary).keys().size() == IDENTITIES.DOMAINS.size() + 1, "every domain and the complete circuit should have fingerprints"):
		return
	if not _expect(identity["sub_seeds"] == {"route": 246810, "room_composition": 1821677131, "material": 1916693968, "dressing": 493555838, "obstacle": 328509393, "hazard": 1746009985} and String(identity["fingerprint"]) == "98fd871294e832f1" and String(identity["display_name"]) == "Clockwork Clamp Circuit" and String(identity["material_id"]) == "workshop_oiled" and String(identity["palette_id"]) == "oiled_espresso", "the v6 fixture identity, fingerprint, and every domain sub-seed should stay regression-pinned"):
		return
	for domain: String in IDENTITIES.DOMAINS:
		if not _expect(String(identity["fingerprints"][domain]).length() == 16, "%s should have a stable inspectable fingerprint" % domain):
			return
	if not _expect(String(identity["display_name"]).contains("Circuit") and String(identity["summary"]).contains("Seed 246810") and String(identity["summary"]).contains("Workshop") and String(identity["summary"]).contains("Wide room") and String(identity["summary"]).contains("Material workshop_oiled / palette oiled_espresso") and String(identity["summary"]).contains("Forward"), "generated identity should expose a readable name and complete compact summary"):
		return

	var code_result := IDENTITIES.encode_share_code(identity)
	if not _expect(bool(code_result.get("ok", false)) and String(code_result["code"]).begins_with("PC1-") and String(code_result["code"]).length() < 80, "a compatible identity should produce a compact versioned human-enterable code"):
		return
	var decoded := IDENTITIES.decode_share_code(String(code_result["code"]))
	if not _expect(bool(decoded.get("ok", false)) and decoded["identity"] == identity, "share codes should round-trip the complete canonical identity exactly"):
		return
	var typed_lowercase := String(code_result["code"]).to_lower().replace("-", " ")
	if not _expect(IDENTITIES.decode_share_code(typed_lowercase).get("identity", {}) == identity, "typing should tolerate case, spaces, and omitted grouping punctuation"):
		return

	var compact := String(code_result["code"]).replace("-", "")
	var tamper_index := compact.length() - 5
	var replacement := "0" if compact[tamper_index] != "0" else "1"
	var tampered := compact.substr(0, tamper_index) + replacement + compact.substr(tamper_index + 1)
	var tampered_result := IDENTITIES.decode_share_code(tampered)
	if not _expect(not bool(tampered_result.get("ok", false)) and String(tampered_result.get("error", "")).length() > 10, "a one-character corruption should fail with an actionable integrity error"):
		return
	var schema_result := IDENTITIES.decode_share_code(String(code_result["code"]).replace("PC1", "PC9"))
	if not _expect(not bool(schema_result.get("ok", false)) and schema_result.get("kind") == "unsupported_schema" and String(schema_result["error"]).contains("PC9"), "unknown schema versions should be rejected explicitly"):
		return
	var multi_schema_result := IDENTITIES.decode_share_code(String(code_result["code"]).replace("PC1-", "PC10-"))
	if not _expect(multi_schema_result.get("kind") == "unsupported_schema" and String(multi_schema_result.get("error", "")).contains("PC10"), "multi-digit future schema versions should not be mistaken for payload data"):
		return
	var padded_schema_result := IDENTITIES.decode_share_code(String(code_result["code"]).replace("PC1-", "PC01-"))
	if not _expect(padded_schema_result.get("kind") == "format" and String(padded_schema_result.get("error", "")).contains("canonical"), "non-canonical padded schema spellings should be rejected"):
		return
	if not _expect(not bool(IDENTITIES.decode_share_code("PC1-NOT*A-CODE").get("ok", false)), "invalid alphabet input should never partially decode"):
		return

	var payload_result := IDENTITIES._base32_decode(compact.substr(3))
	var payload: PackedByteArray = payload_result["bytes"]
	var body := payload.slice(0, payload.size() - 4)
	body[0] = 9
	var unsupported_payload := body.duplicate()
	unsupported_payload.append_array(IDENTITIES._checksum(body))
	var generator_code := "PC1" + IDENTITIES._base32_encode(unsupported_payload)
	var generator_result := IDENTITIES.decode_share_code(generator_code)
	if not _expect(not bool(generator_result.get("ok", false)) and generator_result.get("kind") == "unsupported_generator", "unknown generator versions should be rejected after checksum validation"):
		return

	var v5_body := payload.slice(0, payload.size() - 4)
	v5_body[0] = 5
	var v5_payload := v5_body.duplicate()
	v5_payload.append_array(IDENTITIES._checksum(v5_body))
	var v5_code := "PC1" + IDENTITIES._base32_encode(v5_payload)
	var v5_result := IDENTITIES.decode_share_code(v5_code)
	if not _expect(not bool(v5_result.get("ok", false)) and v5_result.get("kind") == "unsupported_generator", "the previous generator version should be rejected honestly as unsupported"):
		return

	var bad_tier_body := payload.slice(0, payload.size() - 4)
	bad_tier_body[5] = 9
	var bad_tier_payload := bad_tier_body.duplicate()
	bad_tier_payload.append_array(IDENTITIES._checksum(bad_tier_body))
	var bad_tier_code := "PC1" + IDENTITIES._base32_encode(bad_tier_payload)
	var bad_tier_result := IDENTITIES.decode_share_code(bad_tier_code)
	if not _expect(not bool(bad_tier_result.get("ok", false)) and bad_tier_result.get("kind") == "invalid_fields", "an out-of-range length profile index should be rejected after checksum validation"):
		return

	var explicit := IDENTITIES.create(&"office", &"wide", 42, true, 3, "cork_v2", "night_blue")
	var explicit_decoded := IDENTITIES.decode_share_code(String(IDENTITIES.encode_share_code(explicit)["code"]))
	if not _expect(explicit_decoded.get("identity", {}) == explicit and String(explicit["summary"]).contains("Material cork_v2 / palette night_blue") and not String(explicit["summary"]).contains("Material fallback"), "explicit material and palette IDs should survive codes and display as the actual identity"):
		return
	var reverse := IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, true, 2)
	if not _expect(reverse["sub_seeds"] == identity["sub_seeds"] and reverse["fingerprints"]["circuit"] == identity["fingerprints"]["circuit"] and reverse["fingerprint"] != identity["fingerprint"], "reverse direction should retain circuit composition while changing complete race identity"):
		return

	var preview := PREVIEW.prepare(identity)
	var prepared := TRACK_BUILDER.prepare_layout(&"workshop", &"wide", FIXTURE_SEED, IDENTITIES.generation_options(identity))
	if not _expect(not preview.is_empty() and String(preview["loaded_fingerprint"]) == PREVIEW.fingerprint_for_prepared(identity, prepared), "preview and loaded preparation should resolve to the same fingerprint"):
		return
	if not _expect(String(prepared["spec"]["story_id"]) == String(identity["story_id"]) and int(prepared["spec"]["material_seed"]) == int(identity["sub_seeds"]["material"]) and int(prepared["spec"]["dressing_seed"]) == int(identity["sub_seeds"]["dressing"]) and int(prepared["spec"]["obstacle_seed"]) == int(identity["sub_seeds"]["obstacle"]) and int(prepared["spec"]["hazard_seed"]) == int(identity["sub_seeds"]["hazard"]), "route preparation should consume every composition seed in its matching domain"):
		return
	if not _expect(bool(preview["hazard_present"]) == bool(identity["danger_profile"]["hazard_present"]) and int(preview["obstacle_count"]) <= int(identity["danger_profile"]["obstacle_count"]), "the summary danger profile should bound the deterministic prepared obstacle plan and match its hazard exactly"):
		return
	var inconsistent_room_seed := int(identity["sub_seeds"]["room_composition"]) + 1
	if not _expect(IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2, "", "", {"room_composition": inconsistent_room_seed}).is_empty(), "room-composition overrides must be rejected when their selected room disagrees with the encoded room"):
		return
	var inconsistent_normalized := identity.duplicate(true)
	inconsistent_normalized["room"] = "classic"
	inconsistent_normalized.erase("fingerprint")
	if not _expect(IDENTITIES.normalize(inconsistent_normalized).is_empty(), "normalization must reject a room that was not selected by its composition seed even without trusting a supplied fingerprint"):
		return
	var override_room := IDENTITIES.room_for_composition_seed(inconsistent_room_seed)
	var overridden := IDENTITIES.create(&"workshop", override_room, FIXTURE_SEED, false, 2, "", "", {"room_composition": inconsistent_room_seed})
	if not _expect(not overridden.is_empty() and int(overridden["sub_seeds"]["room_composition"]) == inconsistent_room_seed and String(overridden["room"]) == String(override_room), "a consistent room-composition override should become a real identity domain"):
		return
	if not _expect(IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2, "", "", {"route": FIXTURE_SEED + 1}).is_empty(), "the route argument must not be replaced by hidden override entropy"):
		return
	for route_seed in range(24):
		var selected_room := IDENTITIES.room_for_route_seed(route_seed)
		var generic := IDENTITIES.create(&"kitchen", selected_room, route_seed)
		if not _expect(not generic.is_empty() and String(generic["room"]) == String(IDENTITIES.room_for_composition_seed(int(generic["sub_seeds"]["room_composition"]))), "generic room composition should select its encoded room for route seed %d" % route_seed):
			return
	for room: String in IDENTITIES.ROOMS:
		var explicit_room := IDENTITIES.create(&"office", StringName(room), 0, false, 3)
		if not _expect(not explicit_room.is_empty() and String(IDENTITIES.room_for_composition_seed(int(explicit_room["sub_seeds"]["room_composition"]))) == room, "an explicit generated-circuit room should receive consistent composition entropy for %s" % room):
			return

	var profile_fingerprints := {}
	for tier: String in IDENTITIES.GENERATED_RULES.LENGTH_TIERS:
		var profiled := IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2, "", "", {}, tier)
		if not _expect(not profiled.is_empty() and String(profiled["length_tier"]) == tier and String(profiled["room"]) == String(identity["room"]) and profiled["sub_seeds"] == identity["sub_seeds"], "length profile %s should reuse the same sub-seeds, room, and master seed" % tier):
			return
		profile_fingerprints[String(profiled["fingerprint"])] = true
		var profile_code := IDENTITIES.encode_share_code(profiled)
		if not _expect(bool(profile_code.get("ok", false)) and String(profile_code["code"]).length() < 80 and IDENTITIES.decode_share_code(String(profile_code["code"])).get("identity", {}) == profiled, "length profile %s should round-trip its compact share code exactly" % tier):
			return
	if not _expect(profile_fingerprints.size() == IDENTITIES.GENERATED_RULES.LENGTH_TIERS.size(), "identical seeds and rooms across length profiles should yield distinct fingerprints"):
		return
	if not _expect(IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2, "", "", {}, "bogus").is_empty(), "an unknown length profile should be rejected by create"):
		return
	var unknown_tier := identity.duplicate(true)
	unknown_tier["length_tier"] = "bogus"
	unknown_tier.erase("fingerprint")
	if not _expect(IDENTITIES.normalize(unknown_tier).is_empty(), "normalization must reject an unknown length profile"):
		return
	var long_identity := IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2, "", "", {}, "long")
	if not _expect(String(IDENTITIES.normalize(long_identity)["length_tier"]) == "long", "canonicalization must not silently drop a supplied length profile"):
		return
	var missing_tier := identity.duplicate(true)
	missing_tier.erase("length_tier")
	missing_tier.erase("fingerprint")
	if not _expect(String(IDENTITIES.normalize(missing_tier)["length_tier"]) == "standard", "a current-version identity missing a length profile should default to standard"):
		return

	print("GENERATED_CIRCUIT_IDENTITY_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_CIRCUIT_IDENTITY_TEST FAIL: " + message)
	quit(1)
	return false
