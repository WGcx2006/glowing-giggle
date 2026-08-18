extends RefCounted

const CLASS_DATA: Array[Dictionary] = [
	{
		"id": "assault",
		"name": "突击兵",
		"description": "均衡的突击步枪手，擅长中近距离推进。",
		"primary_indices": [0],
		"secondary_indices": [1, 4],
		"speed_multiplier": 1.0,
	},
	{
		"id": "recon",
		"name": "侦察兵",
		"description": "使用精确射手步枪，机动性强，负责侦察与远程压制。",
		"primary_indices": [2],
		"secondary_indices": [1],
		"speed_multiplier": 1.12,
	},
	{
		"id": "support",
		"name": "支援兵",
		"description": "使用冲锋枪并携带破片手雷，为队伍提供近距离火力。",
		"primary_indices": [1],
		"secondary_indices": [4],
		"speed_multiplier": 0.94,
	},
	{
		"id": "engineer",
		"name": "工程兵",
		"description": "携带火箭筒与突击步枪，擅长对抗载具和工事。",
		"primary_indices": [3],
		"secondary_indices": [0],
		"speed_multiplier": 0.98,
	},
]


static func get_classes() -> Array[Dictionary]:
	return CLASS_DATA


static func get_class_data(class_id: String) -> Dictionary:
	for class_data in CLASS_DATA:
		if str(class_data["id"]) == class_id:
			return class_data
	return {}


static func get_default_loadout() -> Dictionary:
	return {
		"class_id": "assault",
		"primary_index": 0,
		"secondary_index": 1,
	}


static func get_available_indices(loadout: Dictionary) -> Array[int]:
	var indices: Array[int] = []
	var primary_index: int = int(loadout.get("primary_index", 0))
	var secondary_index: int = int(loadout.get("secondary_index", 1))
	for index in [primary_index, secondary_index]:
		if not indices.has(index):
			indices.append(index)
	return indices
