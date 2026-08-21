class_name VehicleStats
extends Resource

@export_category("Motion")
@export var mass: float = 1.0
@export var engine_power: float = 650.0
@export var max_speed: float = 650.0
@export var acceleration: float = 1.0
@export var reverse_speed: float = 250.0
@export var steering_rate: float = 3.5
@export var steering_response: float = 9.0

@export_category("Handling")
@export var grip: float = 0.9
@export var lateral_grip: float = 11.0
@export_range(0.05, 1.0) var drift_factor: float = 0.3
@export var brake_force: float = 1000.0
@export var handbrake_force: float = 260.0

@export_category("Boost and durability")
@export var boost_power: float = 500.0
@export var boost_capacity: float = 100.0
@export var boost_recharge: float = 9.0
@export var durability: float = 55.0
