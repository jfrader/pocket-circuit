# Vehicle physics

`VehicleStats.physics_model_version` selects the handling implementation: `0`
keeps the shipped legacy controller and is the default, while `1` is reserved
for the upcoming bicycle/tire model. Canonical per-car values live in
`data/vehicles/*.tres`; the championship catalog references those resources and
keeps presentation ratings separate from simulation units.

| Parameter table | `VehicleStats` category |
|---|---|
| 4.1 Chassis/powertrain | Chassis and powertrain |
| 4.2 Tires/steering | Tires and steering |
| 4.3 Brake/drift | Brakes and drift |
| 4.4 Boost/durability | Boost and durability |
Note: v1 is not the default.
