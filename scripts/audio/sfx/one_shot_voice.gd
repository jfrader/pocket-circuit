class_name OneShotVoice
extends RefCounted

## A generated one-shot effect: strength tiers of raw samples plus the mix rate
## they were rendered at. Tiers exist so a light hit differs in timbre from a
## heavy one, not just in volume.

var signature: String = ""
var mix_rate: int = 22050
var tiers: Array[PackedFloat32Array] = []
## Ascending strength at which each tier becomes the chosen one.
var tier_thresholds: PackedFloat32Array = PackedFloat32Array()


func _init(voice_signature: String = "", rate: int = 22050) -> void:
	signature = voice_signature
	mix_rate = rate


## Index of the tier whose character fits this strength.
func tier_for(strength: float) -> int:
	var bounded := clampf(strength, 0.0, 1.0)
	for index in tier_thresholds.size():
		if bounded <= tier_thresholds[index]:
			return index
	return maxi(0, tier_thresholds.size() - 1)


func sample_count() -> int:
	return tiers[0].size() if not tiers.is_empty() else 0
