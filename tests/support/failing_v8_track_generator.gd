extends RefCounted


static func generate(request: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"kind": "v8_not_implemented",
		"error": "Track generator schema 2 version 8 is intentionally unavailable until the real v8 generator exists.",
		"request": request.duplicate(true),
	}
