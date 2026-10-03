# Topology Schema

The JSON contract between Godot (or any caller) and `simulation.py`,
implemented by `input_management.BuildingTopology` and
`procedural_content_generation.generate_topology_grid`.

## Building fields

| Field | Type | Units | Range | Notes |
|---|---|---|---|---|
| `building_id` | int | - | - | identifier |
| `units` | str | - | `"ft"` or `"m"` | length units of the fields below; Godot sends `"m"`; default `"ft"` |
| `floor_count` | int | stories | 1 - 10 | |
| `story_height` | float | `units` | 3 - 5 m (Godot) | uniform |
| `bay_count_x` | int | bays | 1 - 10 | |
| `bay_width_x` | float | `units` | 3 - 9 m (Godot) | uniform |
| `bay_count_y` | int | bays | 1 - 10 | |
| `bay_width_y` | float | `units` | 3 - 9 m (Godot) | uniform |
| `floor_load_kpa` | float | kN/m² | 2 - 10 | Godot fixes 6.0 |
| `roof_load_kpa` | float | kN/m² | 1 - 5 | Godot fixes 3.0 |

Internally lengths are stored in feet and converted to meters
(`FEET_TO_M`); the OpenSees model uses kN, m, s. Godot also writes
`magnitude` and `duration` into `input.json` for the record; `simulation.py`
reads those from its command-line flags.

## Model state (optional fields)

| Field | Type | Default | Meaning |
|---|---|---|---|
| `member_sections` | object | every member `"W12X26"` | member id -> W-section name from `w_sections.json` |
| `braces` | array | `[]` | X-braces: `{"story", "axis", "line", "bay", "section"}` |
| `struts` | array | `[]` | mid-height struts: `{"story", "axis", "line", "bay", "section"}` |

- **Member id:** `"l,r,c|l,r,c"` of its two grid nodes, e.g. column
  `"0,1,1|1,1,1"`, X-beam `"1,0,0|1,0,1"`, Y-beam `"1,0,0|1,1,0"`.
- **axis** `"x"`: a frame along X on grid row `line`, between columns `bay`
  and `bay + 1`. **axis** `"y"`: a frame along Y on grid column `line`, between
  rows `bay` and `bay + 1`. `story` is 1 - `floor_count`.
- `section` defaults to the starting section. Invalid stories, lines, bays,
  axes or section names are rejected.

## Derived geometry

- `n_nodes_x = bay_count_x + 1`, `n_nodes_y = bay_count_y + 1`, `n_levels = floor_count + 1`
- Grid node tag: `level * (n_nodes_x * n_nodes_y) + row * n_nodes_x + col + 1`
- Strut mid-height nodes get tags after the grid nodes and split both columns
  into two elements.

## Connectivity

- **Columns:** `(level, row, col) -> (level + 1, row, col)`, P-Delta transformation.
- **Beams:** full grid at levels 1 - `floor_count`, X- and Y-direction.
- **Braces:** two diagonals per braced bay, `Truss` elements.
- **Base:** every level-0 node fully fixed.

## Material and sections

See `README.md` (Model) and `w_sections.json`. Section axes: flange width
along the element's local y, depth along local z; columns use
vecxz = (1, 0, 0) (web parallel to global X), beams and struts use
vecxz = (0, 0, 1).
