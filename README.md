# ProGen: topology -> OpenSeesPy NLTHA -> Performance Evaluation

Generates a regular steel beam-column frame, runs a bidirectional nonlinear
time-history analysis (NLTHA) with OpenSeesPy, and evaluates the result
against the ten trigger conditions of the thesis's Table 1. The Feedback
Engine applies the Table 1 actions automatically. It is currently capped at
**one feedback iteration** (`pipeline.MAX_FEEDBACK_ITERATIONS = 1`) for
experimentation: Iteration 0 (the generated structure, i.e. the open-loop
result) -> feedback -> Iteration 1.

## Files

One module per System Architecture layer (thesis Figure 5):

| File | Layer | Purpose |
|---|---|---|
| `input_management.py` | Input Management | `BuildingTopology`, `MaterialProps` (AK Steel Grade 25, Table 2), `WSection` records loaded from `w_sections.json`, starting section |
| `w_sections.json` | Input Management (data) | 17 AISC W-shapes, W10X15 to W36X529, generated from the AISC Shapes Database v16.0 (metric columns), in SI units, ordered as the upsizing sequence |
| `procedural_content_generation.py` | Procedural Content Generation | Node/column/beam grid plus the model state: W-section per member, X-braces, mid-height struts |
| `seismic_simulation.py` | Seismic Simulation | Ground motion, OpenSeesPy model, gravity + masses, elastic story stiffness, NLTHA, response tracking |
| `performance_evaluation.py` | Performance Evaluation | Element / floor / structure scope checks for all ten Table 1 triggers, with demand ratios |
| `feedback_engine.py` | Feedback Engine | `apply_feedback(...)`: turns an evaluation into the next model state using the Table 1 actions; logs every action |
| `data_management.py` | Data Management | `build_run_record(...)`, the result record of one simulation; run key, tool fingerprint and previous-run reuse/overwrite |
| `output_layer.py` | Output Layer | JSON / time-history CSV writers, atomic per-iteration folders |
| `pipeline.py` | (closed loop) | simulate -> evaluate -> save iteration -> feedback -> repeat, up to `MAX_FEEDBACK_ITERATIONS` |
| `simulation.py` | (orchestrator) | CLI entry point; `--run-dir` runs the closed loop (used by Godot), `--output` runs a single simulation |
| `validation.py` | (PCG/Input bridge) | Node/element counts (including braces and struts), orphaned nodes, base-to-roof connectivity |
| `demo.py`, `test_building.py`, `inspect_model.py` | (dev utilities) | Smoke tests using the elastic model |
| `sample_data.py` | (dev utility) | Loads `regular_buildings.xlsx` (not in this folder; `demo.py` falls back to a built-in sample) |

## Quick start

```
py -3.12 -m venv .venv-1
.\.venv-1\Scripts\python.exe -m pip install -r requirements.txt
.\.venv-1\Scripts\python.exe demo.py
.\.venv-1\Scripts\python.exe simulation.py --duration 10 --magnitude 5 --output results.json --history nltha_history.csv
```

Without `--topology`, `simulation.py` uses a built-in 2-storey, 1 x 1-bay
sample. `--topology file.json` takes any JSON following `SCHEMA.md`.

```
```

Open `godot_ui/` in Godot 4.4.1 and run the main scene. `GENERATE STRUCTURE`
draws the frame; `RUN SIMULATION` runs the closed loop in the background
(no further clicks) and saves everything for that run in `runs/run_<date-time>/`:

- `input.json`: the building, loads, magnitude and duration sent to Python
- `iteration_<n>/record.json`: peak metrics, fundamental period, drift limit,
  evaluation, model state, and the feedback actions that produced it
- `iteration_<n>/history.csv`: one row per converged time step
- `run_summary.json`: status, iterations completed, stop reason, final result
- `progress.json`: current iteration, phase and step, plus the latest
  displacement frame while simulating (read by Godot)
- `live_state.json`: the model state and node list of the iteration being
  simulated (read by Godot for the live shake)
- `iteration_<n>/frames.json`: lateral X and Y displacements (m) of every
  free node (grid nodes and strut mid-height nodes) every 10 analysis steps
  (0.1 s), the time each member first exceeded the rupture strain (the
  Rule 3 criterion) with its two end nodes, and the collapse time if the
  analysis stopped converging; absent when the structure collapsed under
  gravity

Each iteration folder is written under a temporary name and renamed when
complete; Godot lists it in the Iteration Records panel as soon as it
appears (click to view that iteration's structure and results; members
changed by feedback are drawn in red). The run stops when all checks pass,
when the iteration cap is reached, or when no rule can change anything.

**Visual shake.** While an iteration is being simulated, the main viewport
moves the structure with the node displacements OpenSeesPy is computing at
that moment (Python writes one frame every 10 steps; Godot eases toward the
newest one). The shake stops when the iteration folder is saved. After the
run, the Simulation Preview (top right) shows the structure of the selected
iteration; click it to replay that iteration's `frames.json` in real time in both the preview and the main viewport
(0.1 s frames, linearly interpolated). Both views draw each member straight
between its two analysis nodes, so members stay connected (columns with a
strut are drawn in two segments meeting at the strut's mid-height node) and
base nodes stay fixed. Displacements are relative to the ground and are
magnified for visibility; the factor is shown on screen (the preview scales
the record's peak node displacement to 4 % of the building height, capped
at x200; the live view uses the peak seen so far in the run, so its factor
only decreases). Member bending between nodes, ground translation, and
vertical displacements are not drawn.

**Collapse view.** A member falls to the ground at the record time its
peak strain first exceeds the rupture strain (the same criterion as Rule
3); the analysis itself keeps the member in the model, so the fall is a
display of that event, not a computed motion (free fall at 9.81 m/s² while
turning flat, at the member's true length). Column lengths are kept: each
column node is placed from the node below it using the computed story
drift (lateral positions from OpenSeesPy, capped at the column length) and
drops so the column keeps its length, so a story swayed as far as its
column length lies flat. At ordinary drifts this drop is negligible; during
a collapse run-away (displacements growing without bound before the
analysis stops) it makes the building sway and sink instead of stretching.
When the analysis stopped converging, playback holds the last computed
frame with fallen members on the ground and shows the collapse time.

## Feedback actions (Table 1)

| Rule | Action |
|---|---|
| 1, 3 | Upsize the member to the smallest listed section with A and Sx ≥ current x demand ratio (at least one step) |
| 2 | Add a Y-direction mid-height strut at the column (preferring a Y-braced bay); if already strutted, upsize to ry ≥ current x √ratio |
| 4 | X-brace every bay of the floor, both directions (existing braces: upsize with A ≥ current x ratio) |
| 5 | Upsize the soft story's columns: Ix (X) or Iy (Y) ≥ current x required stiffness ratio |
| 6 | X-brace the perimeter bays of the mid-story floors |
| 7 | X-brace the weak direction's bays on the floor |
| 8 | Upsize the columns of the story with the greatest drift: Ix or Iy ≥ current x IDR / limit |
| 9 | X-brace all perimeter bays on all floors (ratio / 1.2 for existing braces) |
| 10 | Upsize every member, brace and strut (A and Sx ≥ current x mean stress / Fy) |

When several rules target the same member, the largest requested section
wins; a member already at W36X529 is reported as "section limit reached".
If the iteration being corrected collapsed during the earthquake (the NLTHA
stopped converging), every upsize is limited to **one step** for that
feedback pass: responses leading into a dynamic instability (e.g. strains
hundreds of times the rupture limit) describe the collapse rather than a
sizable demand. Bracing actions are unaffected. This one-step bound is a
ProGen design choice; each record logs its `sizing_mode`.
If gravity collapses, a linear-elastic gravity analysis supplies member
stresses for Rules 1 and 10.

`Clean Previous Runs` (bottom of the Iteration Records panel) permanently
deletes every `runs/run_*` folder after a confirmation dialog.

**Run reuse / overwrite.** Before simulating, `simulation.py --run-dir`
compares the new run's inputs (building fields, loads, magnitude, duration,
normalized to 6 decimals) and the tool fingerprint (SHA-256 of
`w_sections.json` and every source file that affects results) with each
`runs/run_*` folder:

- same inputs, same fingerprint, completed: nothing is simulated; Python
  writes `reuse.json` in the new folder and Godot loads the existing run
  instead (the new, empty folder is deleted)
- same inputs but a different or missing fingerprint (older tool version),
  or an interrupted/errored run: that folder is deleted and the run is
  simulated fresh (listed as `replaced_runs` in `run_summary.json`)

So each set of inputs has at most one run folder, always from the current
tool version. Runs with a custom `--motion` file are never reused.

## Model

- **Material:** AK Steel Grade 25 (Table 2): Fy 170 MPa, Fu 290 MPa, E 200 GPa,
  elongation 26 %, density 7.87 g/cc. Poisson's ratio 0.30 is an assumption
  (not on the datasheet). `Steel01` post-yield hardening ratio
  (290 - 170) / (0.26 - Fy/E) / E ≈ 0.0023 is derived from Table 2, wrapped in
  `MinMax` at the 26 % rupture strain.
- **Sections:** every member starts as **W12X26**. Fiber section = two flange
  plates (8 fibers across the width) and a web (8 fibers along the depth);
  `forceBeamColumn` with 3 Lobatto integration points. Column webs are
  parallel to global X (strong axis resists X sway; weak axis in Y).
- **Braces / struts** (supported in the model state; nothing creates them
  until the Feedback Engine exists): X-braces are two `Truss` diagonals per
  bay (not connected where they cross, no compression buckling cap); struts
  are beam-columns at story mid-height, splitting both columns.
- **Geometry:** P-Delta transformation on columns; fixed base; floors are
  **not** rigid diaphragms.
- **Loads:** fixed floor 6 kPa and roof 3 kPa (design assumption within the
  LSDSE-derived ranges) on X-direction beams by tributary width (one-way
  load path), plus member self-weight (density x area x length).
- **Mass:** floor load lumped at each node by its tributary floor area
  (NSCP 2015 §208.6.2) plus member self-weight.
- **Damping:** 5 % mass-proportional Rayleigh (NSCP §208.5.3.2).
- **Analysis:** 10-step gravity (Newton), eigenvalue for T, Newmark average
  acceleration at dt = 0.01 s, BandGeneral solver, X and Y excitation together.

## Ground motion (Option A)

- **PGA** from magnitude: Esteva & Villaverde (1973),
  A = 5.7 e^(0.8M) (Δ + 40)^-2 g, at a fixed distance Δ = 40 km
  (coefficients per JCSS Probabilistic Model Code §2.17, Table 1).
- **Shape:** modulated, filtered white noise (simplified Rezaeian & Der
  Kiureghian, 2010, PEER Report 2010/02). Filter frequency 5.87 Hz at mid
  shaking, changing -0.089 Hz/s; filter damping 0.213 (Table 4.3 sample
  means); 0.2 Hz high-pass. Gamma modulating function whose 5-95 % duration
  equals the user's duration and whose t_mid/D5-95 ratio follows the Table 4.3
  means; the record ends at 99 % cumulative intensity (≈ 1.7 x the duration).
  Fixed seeds (X = 1, Y = 2), scaled so the peak equals the PGA.
- `--motion file.csv` applies a custom record to both X and Y instead.

## Performance Evaluation

Drift limit (NSCP 2015 §208.6.5.1): 0.025 x story height if T < 0.7 s,
0.020 if T ≥ 0.7 s, applied directly to NLTHA drift (Eq. 208-21 Exception).

| Rule | Scope | Trigger |
|---|---|---|
| 1 | Element | Peak combined stress P/A + M/Sx + M/Sy > Fy |
| 2 | Element | Column compressive stress > Euler stress, K = 1, governing of weak axis (ry, halved length if a Y-strut is present) and strong axis (rx, halved length if an X-strut is present) |
| 3 | Element | Peak fiber strain > 26 % elongation at break |
| 4 | Floor | Floor IDR > NSCP limit |
| 5 | Floor | Soft story (NSCP Table 208-9): stiffness < 70 % of the story above or < 80 % of the average of the three above; stiffness from a linear-elastic static analysis with the NSCP §208.5.2.3 force distribution (Eqs. 208-15 to 208-17), mass-weighted average drift |
| 6 | Floor | Mid-story floors exceed the limit while ground and roof floors do not |
| 7 | Floor | One direction exceeds the limit, the other does not |
| 8 | Structure | Roof displacement > limit x total height |
| 9 | Structure | Torsional irregularity (NSCP Table 208-10): peak drift at one end > 1.2 x average of the two ends' peak drifts, per floor and direction over the whole record (no accidental torsion; NSCP applies this check when diaphragms are not flexible, while ProGen's floors are not modelled as rigid diaphragms) |
| 10 | Structure | Mean member peak stress ≥ 90 % of Fy (heuristic) |

Every trigger reports a demand ratio. If gravity fails to converge the run
is recorded as `collapse_phase: "gravity"`; if the NLTHA stops converging it is
recorded as `collapse_phase: "seismic"` and the peaks include the response up
to that point.

## Known limitations

1. No rigid floor diaphragm: a single column line can sway independently.
2. One section list for beams, columns and braces; per-member sections, no grouping.
3. Braces have no compression buckling cap; X-brace diagonals are not connected at the crossing.
4. Panel loads are carried by X-direction beams only and treated wholly as seismic weight.
5. One synthetic ground-motion pair (NSCP §208.5.3.6.1 asks for ≥ 3 recorded pairs for design).
6. No accidental torsion (§208.5.1.3) and no panel-zone deformation (§208.6.2 Item 2).
7. With Fy = 170 MPa, W12X26 floor beams on 6 m bays already exceed yield under gravity alone; larger or taller buildings may collapse under gravity at the starting section.
8. Large configurations take a long time (a 6-storey 5 x 5-bay frame with a 17 s record takes about 3 minutes).
