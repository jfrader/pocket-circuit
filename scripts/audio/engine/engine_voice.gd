class_name EngineVoice
extends RefCounted

## Immutable generated voice: the table bank plus the metadata the synth needs.
## Built once by EngineVoiceGenerator at a load boundary, then only read.

var signature: String = ""
var recipe: EngineRecipe
var rpm_bands: PackedFloat32Array = PackedFloat32Array()
var load_bands: PackedFloat32Array = PackedFloat32Array()
## [rpm_index][load_index] -> PackedFloat32Array of `sample_count` values.
var tables: Array = []
var mechanical: PackedFloat32Array = PackedFloat32Array()
var sample_count: int = 0


func _init(voice_signature: String = "", source: EngineRecipe = null) -> void:
	signature = voice_signature
	recipe = source


func rpm_band_count() -> int:
	return rpm_bands.size()


func load_band_count() -> int:
	return load_bands.size()


## Rough size of the bank in bytes, for budget assertions in tests.
func table_bytes() -> int:
	return tables.size() * load_band_count() * sample_count * 4 + mechanical.size() * 4
