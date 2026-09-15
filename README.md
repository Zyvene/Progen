# topology -> OpenSeesPy

Takes a structural topology and turns it into a valid, analysis-ready
OpenSeesPy model. Built as a placeholder-input pipeline while PCG
(topology generation) is still in progress — see `SCHEMA.md` for the
schema both teams need to agree on.

## Files

| File | Purpose |
|---|---|
| `schema.py` | `BuildingTopology`, `MaterialProps`, `SectionProps` — the data contract, with input validation |
| `sample_data.py` | Loads `regular_buildings.xlsx` rows into `BuildingTopology` objects; picks a small/mid/large spread across the parametric range |
| `model_builder.py` | `build_model(topology)` — builds nodes, base fixity, and beam-column elements in OpenSeesPy |
| `loads.py` | Converts floor/roof panel loads (kN/m^2) into distributed beam loads and applies them |
| `validation.py` | `validate_model(built)` — checks node/element counts, orphaned nodes, and base-to-roof connectivity |
| `demo.py` | End-to-end run: sample structures &rarr; build &rarr; validate &rarr; gravity analysis smoke test |
| `regular_buildings.xlsx` | Sample dataset (423 buildings) used as placeholder topology input |
| `SCHEMA.md` | Formal schema documentation |

## Quick start

The project uses a virtual environment: `.venv-1` with Python 3.12.

```
   py -3.12 -m venv .venv-1
   .venv-1\Scripts\Activate.ps1
   pip install -r requirements.txt
   python demo.py
   python simulation.py --topology sample_topology.json --output results.json --history nltha_history.csv
```

```powershell
.\.venv-1\Scripts\python.exe -m pip install -r requirements.txt
.\.venv-1\Scripts\python.exe demo.py
.\.venv-1\Scripts\python.exe simulation.py --topology sample_topology.json --output results.json
```

- Run `Godot: open project` from **Terminal -> Run Task** to open the project
   in Godot.
- The `RUN SIMULATION` button in Godot launches the OpenSeesPy's
   NLTHA automatically after the visual shake begins.

Other Notes:
Pressing `GENERATE STRUCTURE` in Godot also writes the displayed geometry to
the root `sample_topology.json`. 

When the analysis finishes, two files are written in the project root:
- `results.json` contains the extracted peak stress, peak displacement, peak
   deformation, maximum story drift, and maximum IDR.
- `nltha_history.csv` contains one row for every converged time step with
   `time_s`, `stress_mpa`, `displacement_m`, `deformation_m`, and `idr`. 

## NLTHA and metrics

`simulation.py` builds the sample as a nonlinear fiber-section frame, applies load gravity, runs a base-excitation Newmark transient analysis, and writes
- `peak_stress_mpa`: maximum combined axial-plus-bending fiber stress;
- `peak_displacement_m`: maximum displacement in the excitation direction;
- `peak_deformation_m`: maximum relative member deformation in the
   excitation direction;
- `maximum_idr`: maximum inter-story drift ratio.

The Godot terminal reports the summary when the analysis finishes. The complete time history is contained in `nltha_history.csv` for reference.

The section is still a documented placeholder until PCG supplies real member
sections. Replace the placeholder dimensions/material assignment in
`model_builder.py` when that data becomes available. A CSV motion may be
passed as `--motion motion.csv`; it can contain `time,acceleration_g` or one
acceleration-g value per row.

## Analysis sequence

1. `build_model(..., nonlinear=True)` creates the nodes, fixed bases, fiber
   sections, and force-based beam-column members.
2. `apply_panel_loads` converts floor and roof area loads to line loads on
   X-direction beams using tributary widths.
3. Gravity is solved in ten incremental static steps, then committed with
   `loadConst`.
4. Floor masses are assigned from the gravity load divided by `g`, and a
   `UniformExcitation` pattern applies the ground acceleration in global X.
5. Newmark integration advances the NLTHA one record sample at a time.
6. Stress, displacement, deformation, and IDR are scanned after every converged step and their maxima are written to the respective JSON file.

This builds and validates 3 buildings pulled from the sample dataset
(smallest, mid-range, and the largest available), runs a linear static
gravity analysis on each as a smoke test, and prints a pass/fail report.

## Using it on your own topology

```python
from schema import BuildingTopology
from model_builder import build_model
from validation import validate_model

topology = BuildingTopology(
    building_id=1,
    floor_count=4,
    story_height=16,      # ft
    bay_count_x=3,
    bay_width_x=30,       # ft
    bay_count_y=2,
    bay_width_y=25,       # ft
    floor_load_kpa=6.0,
    roof_load_kpa=3.0,
)

built = build_model(topology)
result = validate_model(built)
print(result.report())
```

`built` carries everything downstream code needs: `node_tags`,
`node_coords`, `column_elements`, `beam_elements`, `base_node_tags`,
plus the live OpenSeesPy model (there's exactly one model in memory at a
time — `build_model` calls `ops.wipe()` each time it's invoked).

## Known gaps / where this stops short of "done"

These are called out explicitly rather than silently papered over,
since the brief says PCG isn't done yet and this schema is what both
teams need to agree on:

1. **Sample dataset doesn't cover the full parametric range.** Spec says
   up to 10x10 bays; the dataset tops out at 5x4. `sample_data.py` picks
   the largest *available* footprint and says so in its docstring rather
   than pretending it hit 10x10.
2. **No section catalog yet.** Every beam/column gets the same nominal
   placeholder cross-section (`schema.SectionProps`) — not a designed
   size. Real member sizing is presumably PCG/NeuralSizer's job (see the
   sibling `LSDSE-Godot-Prototype` repo's `neural_sizer.gd` for how a
   later stage might assign sections).
3. **Panel load magnitudes aren't in the schema.** The dataset has no
   load columns, so `floor_load_kpa` / `roof_load_kpa` default to the
   midpoint of the spec'd ranges and are only actually varied in
   `sample_data.pick_edge_case_spread` to exercise the low/mid/high
   ends.
4. **One-way load path assumption.** Panel loads are applied to
   X-direction beams only (documented in `loads.py`) — a simplification
   until PCG defines real deck/framing direction.
5. **Fixed-base idealization**, no foundation/spring model.
