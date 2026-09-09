# Topology Schema

This is the contract between PCG (topology generation, not built yet)
and this module (topology &rarr; OpenSeesPy model). It is implemented as
`schema.BuildingTopology`.

## Input fields

| Field | Type | Units | Spec range | Notes |
|---|---|---|---|---|
| `building_id` | int | - | - | unique ID |
| `floor_count` | int | stories | 1 - 10 | number of stories above grade |
| `story_height` | float | ft | building-specific | uniform across all stories |
| `bay_count_x` | int | bays | 1 - 10 | bays in the X (plan) direction |
| `bay_width_x` | float | ft | building-specific | uniform across all X bays |
| `bay_count_y` | int | bays | 1 - 10 | bays in the Y (plan) direction |
| `bay_width_y` | float | ft | building-specific | uniform across all Y bays |
| `floor_load_kpa` | float | kN/m^2 | 2 - 10 | typical floor panel load; not in the sample dataset, defaults to 6.0 |
| `roof_load_kpa` | float | kN/m^2 | 1 - 5 | roof panel load; not in the sample dataset, defaults to 3.0 |

`regular_buildings.xlsx` already matches the first 7 columns 1:1
(`Building_ID`, `Floor_Count`, `Story_Height`, `Bay_Count_X`,
`Bay_Width_X`, `Bay_Count_Y`, `Bay_Width_Y`) — see `sample_data.py`.

**Units assumption:** geometry fields are stored in feet, per the
convention already established in `structure_data.gd` in the
LSDSE-Godot-Prototype repo ("All coordinates are in feet"). This module
converts to meters internally (`schema.FEET_TO_M`) so the full model
(geometry + kN/m^2 loads + GPa material) lives in one consistent SI
system: **kN, m**. If the true source units differ, only that one
constant needs to change.

**Regularity assumption:** this schema describes *regular* buildings
only — a single uniform story height and uniform, constant bay widths
in each direction, matching both the task brief ("regular buildings")
and the dataset's structure. Irregular story heights or bay widths
per-story would need a schema extension (e.g. lists instead of scalars).

## Derived geometry

- `n_nodes_x = bay_count_x + 1`, `n_nodes_y = bay_count_y + 1`
- `n_levels = floor_count + 1` (includes the base, level 0)
- Node grid: `n_levels * n_nodes_x * n_nodes_y` nodes total
- Node tag: `level * (n_nodes_x * n_nodes_y) + row * n_nodes_x + col + 1`

## Material (Table 2 — AK Steel Grade 25)

| Property | Value |
|---|---|
| E (modulus) | 200 GPa |
| Fy (min. yield) | 170 MPa |
| Poisson's ratio | 0.30 (assumed; not given by Table 2) |

## Section properties

**Not yet available.** PCG (the sizing module) hasn't shipped a section
catalog, so `schema.SectionProps` is a single nominal placeholder
(`A`, `Iz`, `Iy`, `J`) applied to every beam and column in every
building. This is explicitly flagged as a placeholder in the code —
swap it for real per-element section assignment once PCG exists.

## Connectivity rules

- **Columns:** one per grid point per story, connecting
  `(level, row, col) -> (level+1, row, col)`.
- **Beams:** a complete grid at every level from 1 (first floor) through
  `floor_count` (roof) — X-direction beams connecting `(col, col+1)` at
  each row, and Y-direction beams connecting `(row, row+1)` at each col.
  Level 0 (the base) has no beams.
- **Base fixity:** every level-0 node is fully fixed
  (`fix tag 1 1 1 1 1 1`) — a simple fixed-base idealization.

## Loads

Floor/roof panel loads (kN/m^2) are converted to distributed beam loads
(kN/m) via tributary width and applied with `eleLoad -type -beamUniform`.
See `loads.py` docstring for the exact tributary-width and load-path
assumptions (one-way load path onto X-direction beams only — documented
there since it's a modeling choice, not part of the schema itself).
