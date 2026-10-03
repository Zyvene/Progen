# ProGen Defense Guide: The Tool From Start to Finish

**What this is:** a walkthrough of one complete closed-loop run of the **default building**, in the order the tool executes it. Every step names the file, the line range, the concept, the numbers the default building actually produces, and the source that justifies it.

**Default inputs (UI defaults):** Bay X = 3, Bay Y = 3, Bay Width X = 6 m, Bay Width Y = 6 m, Floor Count = 4, Story Height = 3.5 m, Magnitude = 5, Duration = 15 s.

**Line numbers** refer to the project as of 30 Sep 2026, including the visual shake and collapse view. No code files contain comments; all explanation lives in this guide, `README.md`, `SCHEMA.md` and `guide.txt`.

---

## 0. The whole process on one page

```
UI (Godot)  --inputs-->  GENERATE STRUCTURE (preview grid, W12X26 I-profiles)
            --RUN------> runs/run_<date-time>/input.json  --> simulation.py --run-dir
                                                                  |
  reuse check (same inputs + same tool fingerprint?) --yes--> load the existing run, stop
                                                                  | no
  ground motion (Esteva & Villaverde PGA + Rezaeian & Der Kiureghian shape), X and Y
                                                                  |
  +------------------------ ITERATION n  (n = 0 .. 10) -----------------------------+
  | PCG: grid + section per member + braces + struts                                 |
  | elastic static analysis -> story stiffness (NSCP Eqs. 208-15 to 208-17)          |
  | nonlinear model (W-shape fibers, P-Delta, self-weight, tributary mass)           |
  | gravity -> eigenvalue period T -> NLTHA (Newmark, 5% damping, X+Y shaking)       |
  |   (every 0.1 s: node displacements + ruptures -> progress.json -> live shake)    |
  | evaluation: 10 rules (NSCP drift limit from T)  -> save iteration_n folder       |
  | all pass? stop.  n = 10? stop.  otherwise feedback -> new model state -> n+1     |
  +----------------------------------------------------------------------------------+
Godot polls progress.json + iteration folders -> Iteration Records panel, red = changed members
Click the Simulation Preview -> replay iteration_n/frames.json in the preview and the main view
```

Iteration 0 is the generated structure before any feedback, so **Iteration 0 is the open-loop result**. Iterations 1 to 10 are the closed-loop refinements.

---

## 1. Fixed values and their sources

| Item | Value | Where in code | Source |
|---|---|---|---|
| Material | AK Steel Grade 25: Fy 170 MPa, Fu 290 MPa, E 200 GPa, elongation 26 %, density 7.87 g/cc | `input_management.py` 117-124 | Manuscript Table 2 (Look Polymers datasheet) |
| Poisson's ratio | 0.30 → G = E / 2(1+ν) = 76,923 MPa | `input_management.py` 124, 134-136 | **Assumption** (not on the datasheet) |
| Post-yield hardening ratio b | (290 − 170) / (0.26 − 0.00085) / 200,000 = **0.002315** | `input_management.py` 146-151 | Derived from Table 2 |
| Sections | 17 AISC W-shapes, W10X15 … W36X529 | `w_sections.json` | AISC Shapes Database v16.0 (Aug 2023), consistent with the AISC Steel Construction Manual, 16th ed. |
| Starting section | **W12X26** for every member | `input_management.py` 10 | Engineer consultation (named W10×15 and W12×26; W12×26 chosen because it survives gravity for the default building) |
| Loads | floor 6 kPa, roof 3 kPa | `main.gd` 1194-1217 (export), `input_management.py` 23-24 | Design assumption within the LSDSE-derived ranges |
| Drift limit | 0.025 h if T < 0.7 s, else 0.020 h | `performance_evaluation.py` 5-7, 19-22 | NSCP 2015 §208.6.5.1 |
| NLTHA drift used directly | not reduced | `performance_evaluation.py` 124-125 | NSCP Eq. 208-21 Exception; §208.5.3.6.3.1 |
| P-Delta | on every column | `seismic_simulation.py` 282 | NSCP §208.6.4.2 ("shall consider PΔ effects") |
| Damping | 5 % | `seismic_simulation.py` 702 | NSCP §208.5.3.2 Item 2 |
| Seismic mass | tributary area × panel load ÷ g + self-weight | `seismic_simulation.py` 397-411 | NSCP §208.6.2 (spatial distribution of mass) |
| Magnitude → PGA | A = 5.7·e^(0.8M)·(Δ+40)^−2 g, Δ = 40 km | `seismic_simulation.py` 35-38, 52-57 | Esteva & Villaverde (1973), via JCSS PMC §2.17 Table 1; Δ = 40 km is an **assumption** |
| Motion shape | 5.87 Hz, −0.089 Hz/s, ζf 0.213, 0.2 Hz high-pass | `seismic_simulation.py` 40-46 | Rezaeian & Der Kiureghian (2010), PEER 2010/02 Table 4.3 means, §2.5 |
| Soft story | < 70 % of story above or < 80 % of avg of 3 above | `performance_evaluation.py` 11-12, 134-149 | NSCP Table 208-9 |
| Torsion | > 1.2 × average of the two ends | `performance_evaluation.py` 9, 175-187 | NSCP Table 208-10 |
| Rule 10 threshold | mean stress ≥ 0.90 Fy | `performance_evaluation.py` 16 | **Heuristic** |
| Iteration cap | 10 feedback iterations | `pipeline.py` 12 | Manuscript (preliminary design assumption) |
| Numerical settings | dt 0.01 s, 3 Lobatto points, 8+8 fibers, Newmark γ = ½, β = ¼ | `seismic_simulation.py` 31-33, 709; `simulation.py` 29 | Numerical choices (stated, not data) |
| Shake frames | every 10 steps (0.1 s) | `seismic_simulation.py` 34 | Display choice (not a result) |

---

## 2. Stage by stage

### 2.1 The user interface: inputs, validation, preview (Godot)

**`godot_ui/scripts/main.gd`**
- **136-163 `_ready` / `_load_w_sections`:** builds the UI, then reads `w_sections.json` from the project root. The main view and the Simulation Preview both get every W-shape's real dimensions.
- **990-1034 `_validate_inputs`:** Input Management on the UI side. It enforces the manuscript ranges: bays 1-10, bay widths 3-9 m, floors 1-10, story height 3-5 m, magnitude 1-10, duration 10-30 s. Invalid inputs are blocked before anything is generated.
- **1082-1120 `_on_generate_pressed`:** calls the generator and validator, then draws the structure.

**`godot_ui/scripts/structure_generator.gd` 4-62:** the procedural grid on the Godot side. Nodes at every (level, row, col); a column from each node to the one above; beams along X and Y on every floor.
- Default building: **80 nodes, 64 columns, 96 beams = 160 members**.

**`godot_ui/scripts/structure_validator.gd` 4-75:** topology checks. Node, column and beam counts; orphaned nodes; every node reachable from the base (breadth-first search over the member graph).

**`godot_ui/scripts/member_visual.gd`**
- **11-32:** draws each member as an **I-profile**: two flange boxes plus a web box at the true AISC dimensions. For W12X26 that's d = 310 mm, bf = 165 mm, tf = 9.65 mm, tw = 5.84 mm.
  - Meshes are cached per (section, length), so large buildings stay light.
  - Columns have their web parallel to X; beams have their web vertical.
- **46-68 `setup` / `place`:** `place` re-positions a member between two moved end points without rebuilding the mesh (used by the shake).

**`godot_ui/scripts/static_structure_view.gd`**
- **149-194 `build_state`:** draws any saved model state (sections, braces, struts). Members changed by feedback are highlighted in red. Columns with a strut are drawn in two segments meeting at the strut's mid-height node.
- **196-236 `preview_rule`:** visual mock-ups of the ten Table 1 actions (no analysis).

### 2.2 Starting a run, and run reuse (Godot → Python)

**`main.gd`**
- **1140-1177 `_on_simulate_pressed`:** blocks a second RUN while one is running, creates the run folder, writes `input.json`.
- **1182-1192 `_create_run_dir`:** `runs/run_<date-time>/`.
- **1194-1217 `_export_topology_for_python`:** writes the building, loads (6 / 3 kPa), magnitude and duration in metres.
- **1219-1247 `_start_python_nltha`:** launches `.venv-1/Scripts/python.exe simulation.py --topology input.json --duration 15 --magnitude 5 --run-dir <folder>` as a background process.

**`simulation.py`**
- **25-47:** reads arguments and loads the topology (`input_management.BuildingTopology.from_dict`, `input_management.py` 97-114, which converts metres to the internal feet storage).
- **49-64: run reuse / overwrite.**
  - `run_key` (`data_management.py` 47-59) normalizes the 8 inputs plus loads to 6 decimals.
  - `tool_fingerprint` (`data_management.py` 26-32) is a SHA-256 of `w_sections.json` and every result-affecting `.py` file.
  - `resolve_previous_runs` (`data_management.py` 69-92) scans `runs/run_*`:
    - same key + same fingerprint + completed → writes `reuse.json`, and Godot loads the old run (no simulation);
    - same key but an older fingerprint, or an incomplete run → that folder is deleted and the run is simulated fresh.
- **66-72:** generates the X and Y ground motions (§2.3).
- **74-85:** hands everything to the closed loop, `pipeline.run_pipeline`.

### 2.3 The earthquake (ground motion) — `seismic_simulation.py`

**52-57 `magnitude_to_amplitude_g`: Esteva & Villaverde (1973) attenuation law**
- A = b1·e^(b2·M)·(Δ + k)^−b3 with b1 = 5600 cm/s² (= 5.7 g), b2 = 0.8, b3 = 2, k = 40 km (JCSS PMC §2.17, Table 1).
- The distance Δ is fixed at 40 km because the thesis has no distance input (a stated limitation).
- **Default (M5): PGA = 5600·e^4 / 80² = 47.8 cm/s² = 0.0487 g.**

**60-81 `_gamma_quantiles`, `_envelope_shape_for_ratio`: the time-modulating function**
- Rezaeian & Der Kiureghian model the intensity build-up and decay with a **gamma-shaped envelope**. Its cumulative energy (Arias intensity) follows a gamma distribution.
- The code solves for the gamma shape k such that the ratio D5-95 / t_mid equals the ratio of their Table 4.3 sample means (17.25 s / 12.38 s).
- Result: **k = 6.592**.

**107-139 `stochastic_motion`: the modulated, filtered white-noise process**
- **108-114:** the user's duration is the **strong-shaking duration D5-95** (5 % → 95 % of the energy).
  - For 15 s: scale = 1.808 s, t05 = 5.44 s, t_mid = 10.77 s, t95 = 20.44 s.
  - The record ends at 99 % of the energy: **25.28 s = 2,529 steps at dt = 0.01 s**. That's why the record is about 1.7× the duration.
- **120:** the filter frequency varies linearly in time, ω(t) = 2π[5.87 − 0.089(t − t_mid)] (Table 4.3 means; the minus sign is confirmed on the printed table). For the default it runs from **6.83 Hz at the start to 4.58 Hz at the end**.
- **125:** white noise from a **fixed seed** (X = 1, Y = 2). The motion is reproducible, which the comparative design needs.
- **127-134:** each sample is the envelope times the normalized sum of past noise pulses filtered by a damped oscillator's impulse response: h(τ) = (ω/√(1−ζ²))·e^(−ζωτ)·sin(ω√(1−ζ²)τ), with ζ = 0.213.
- **84-104 `_high_pass`:** a critically damped 0.2 Hz high-pass filter (report §2.5 post-processing), solved with Newmark average acceleration. It removes residual velocity and displacement drift.
- **136-139:** scaled so the peak equals the PGA (0.0487 g). Checked: the dominant frequency is about 5 Hz, and D5-95 comes out within about 7 % of the target for these seeds.

### 2.4 Procedural generation of the model state — `procedural_content_generation.py`

- **77-112:** the deterministic grid. Nodes at (col·bx, row·by, level·h); column pairs; X and Y beam pairs. The same rules as the Godot generator.
- **12-13 `member_id`:** each member's identity is "level,row,col|level,row,col" of its two nodes. The feedback layer uses this to change one member's section.
- **114-125:** assigns a W-section per member. The default is **W12X26** unless the model state asks for another listed section.
- **16-28 `Brace`:** an X-brace is two diagonals across one bay of one story.
- **31-46 `Strut`:** a horizontal member at mid-height between two columns; it creates mid-height nodes (134-139).
- **62-74 `_check_frame_member`:** rejects impossible braces or struts (story, line, bay or section out of range).

### 2.5 The finite-element model — `seismic_simulation.py` 249-394 (`build_model`)

- **261:** a 3-D model, 6 degrees of freedom per node, units kN-m-s.
- **263-280:** nodes; every base node fully fixed (fixed-base idealization).
- **282-283: geometric transformations.**
  - Columns use **P-Delta** (NSCP §208.6.4.2), with local z = global X, so the web is parallel to X: the strong axis resists X sway and the weak axis resists Y.
  - Beams use Linear, with local z vertical (gravity bends the strong axis).
- **292-297: material.** `Steel01` (bilinear: Fy 170 MPa, E 200 GPa, b = 0.002315) wrapped in `MinMax` at ±0.26 strain. A fiber whose strain passes the elongation at break carries no more stress (rupture).
- **211-216 `_define_w_section`: fiber section** = top flange + bottom flange (8 fibers across the width each) + web (8 fibers along the depth). Torsion is added elastically as G·J.
- **298-302:** `Lobatto` integration with **3 points** per member.
- **318-329 `frame_element`:** columns, beams and struts are `forceBeamColumn` elements, a force-based formulation that stays exact for nonlinear material along the member.
- **336-347:** columns (split in two where a strut attaches).
- **349-355:** beams.
- **357-367:** braces are `Truss` elements (axial only).
- **369-375:** struts.
- Default building: **160 elements**.

**Loads — 219-246 `apply_gravity_loads`**
- **226-237: panel loads, one-way load path.** Each X-direction beam carries panel load × tributary width (half a bay on the edge rows). The default floor interior X-beam carries **6 kPa × 6 m = 36 kN/m**; the roof carries 3 kPa.
- **239-246: self-weight.** ρ·A·L·g for every element, half to each end node. W12X26 is 38.7 kg/m.

**Mass — 397-416 `_node_masses` / `_assign_masses`: tributary-area mass** (NSCP §208.6.2)
- An interior node carries 6 × 6 = 36 m², an edge node 18 m², a corner node 9 m².
- Default floor interior node: 6 kPa × 36 m² ÷ 9.807 = **22.0 t**, plus half of each attached member's self-mass.

### 2.6 Elastic story stiffness for the soft-story check — `seismic_simulation.py` 432-484

- **432-440 `nscp_lateral_forces`: NSCP §208.5.2.3.**
  - Eq. 208-16: top force Ft = 0.07TV, capped at ≤ 0.25V, and zero when T ≤ 0.7 s.
  - Eq. 208-17: Fx = (V − Ft)·wx·hx / Σwi·hi.
  - Eq. 208-15: V = Ft + ΣFi.
- **443-484 `elastic_story_stiffness`:**
  1. Builds a **linear-elastic** copy of the same structure.
  2. Gets its period.
  3. Applies the NSCP force pattern (V = 1000 kN, spread over each floor's nodes by mass, as the code requires).
  4. Solves one static step.
  5. Computes K(story) = story shear ÷ mass-weighted average story drift.
- Default: elastic T = 3.187 s. The forces are 97, 194, 291 and 417 kN (the roof includes Ft = 223 kN).
  - K_x = 36,312 / 23,039 / 21,831 / 20,964 kN/m
  - K_y = 5,650 / 5,117 / 5,099 / 5,105 kN/m
  - Y is weaker because the columns bend about their weak axis in Y.

### 2.7 Gravity, period, and the nonlinear time-history analysis — `seismic_simulation.py` 654-757 (`run_nltha`)

- **668:** the elastic story stiffness (§2.6).
- **669-672:** builds the nonlinear model and validates it (`validation.py` 23-115: counts including braces and struts, orphans, connectivity to the base).
- **688-691 + 419-429: gravity.** 10 load steps with Newton-Raphson, then `loadConst` locks the gravity state and the masses are assigned. If gravity fails to converge, the building "collapsed under gravity", and a linear-elastic gravity analysis (641-651) supplies stresses for Rules 1 and 10.
  - Default: **gravity converges, but 18 interior floor beams already reach 181.4 MPa > 170 MPa.**
  - Hand check: wL²/12 = 36·6²/12 = 108 kN·m; 108 / Sx (547 × 10³ mm³) ≈ 199 MPa at a perfectly fixed end.
- **693-694 + 487-499: eigenvalue analysis → fundamental period T.**
  - ω² is the smallest eigenvalue of K·φ = ω²·M·φ, and T = 2π/ω.
  - Two modes are requested (requesting one is unreliable in ARPACK), with a full-LAPACK fallback. Verified against full LAPACK on four structures.
  - **Default Iteration 0: T = 3.954 s.** It's longer than the elastic 3.187 s because the gravity state is already partly yielded and P-Delta reduces stiffness.
  - T ≥ 0.7 s → **drift limit 0.020**.
- **696-701: ground motion input.** Two `UniformExcitation` patterns apply the X and Y records to the base at the same time (acceleration in g × 9.807).
- **702: Rayleigh damping** a0 = 2ζω with ζ = 0.05 (mass-proportional) (NSCP §208.5.3.2).
- **703-710: transient analysis.** Newmark average acceleration (γ = ½, β = ¼, unconditionally stable), Newton-Raphson, `NormDispIncr` 1e-7 convergence test, BandGeneral solver.
- **720-734: the time loop.** 2,529 steps of 0.01 s. If a step fails to converge, the building has **collapsed during the earthquake** (`collapse_phase = "seismic"`, with the collapse time recorded).
  - Every 10 steps the loop sends the latest frame and the rupture list to `pipeline.py` (for the live shake, §2.12).
- **502-621 `ResponseTracker`: what is measured at every step (`update`, 529).**
  - **Story drift:** floor displacement minus the floor below, per node, in X and Y. IDR = drift / story height.
  - **End drifts** (555-561): the average drift of each end line of the floor (rows 0 and last for X, columns 0 and last for Y). The **peak over the whole record** is kept for each end, for the torsion check.
  - **Roof displacement** (562-564).
  - **Member stress** (575, 585): σ = |N|/A + |M_strong|/Sx + |M_weak|/Sy. This is the combined axial + bending demand stress (the same idea as STAAD's combined stress). Braces use |N|/A.
  - **Compression** (586): column axial force ÷ A.
  - **Strain** (587-595): section deformation at the two end integration points; ε = |ε0| + |κy|·d/2 + |κz|·bf/2 (flange tip).
  - **Deformation** (596): relative horizontal displacement between a member's ends.
  - **First rupture time** (601-605): the step when a member's strain first passes 0.26 (the Rule 3 criterion), with its two end nodes.
  - **Frames** (534-538): every 10 steps, the X and Y displacement of every free node.
- **740-756:** packs the record (`data_management.build_run_record` 95-141) plus the frames, ruptures and collapse time.

### 2.8 Performance evaluation: the ten rules — `performance_evaluation.py`

- **19-22:** drift limit from T (NSCP §208.6.5.1).
- **Element level (98-120):**
  - **Rule 1 Yield Stress (100-102):** peak stress > 170 MPa; ratio = σ / Fy.
  - **Rule 2 Buckling (103-115):** Euler σcr = π²E / (KL/r)², K = 1, using the governing of weak-axis L/ry (halved if a Y-strut is present) and strong-axis L/rx (halved if an X-strut is present). W12X26 at 3.5 m: **237.6 MPa** weak axis.
  - **Rule 3 Rupture Strain (116-119):** peak strain > 0.26.
- **Floor level (122-164):**
  - IDR per floor and axis = peak drift / h.
  - **Rule 4 (130-132):** IDR > limit.
  - **Rule 5 Soft story (134-149):** NSCP Table 208-9 with the elastic stiffnesses from §2.6.
  - **Rule 6 (151-153):** mid floors exceed while ground and roof don't (3+ floors).
  - **Rule 7 (155-162):** exactly one direction exceeds.
- **Structure level (166-189):**
  - **Rule 8 (166-169):** roof displacement > limit × total height (0.020 × 14 m = 0.28 m for the default).
  - **Rule 10 (171-173):** mean member stress ≥ 0.90 × 170 = 153 MPa.
  - **Rule 9 Torsion (175-187):** max(end peak) / average(end peaks) > 1.2 (NSCP Table 208-10). NSCP applies this where diaphragms are not flexible; ProGen floors are not modelled as rigid diaphragms (a stated limitation).
- **191-210:** a triggered-rules summary with each rule's count and maximum demand ratio.
- **The iteration passes only if all three levels pass and the analysis converged.**
- **25-69 `evaluate_gravity_fallback`:** Rules 1 and 10 only, from the linear-elastic gravity stresses, used when gravity collapses.

### 2.9 Feedback engine: Table 1 actions — `feedback_engine.py`

- **11-12:** the 17 sections in upsizing order (smallest → largest).
- **26-36 `select_section`:** skip-forward sizing. The smallest listed section that meets the requirement, **at least one step** up. If `one_step` is set, exactly one step (used after a seismic collapse). Returns None at W36X529 ("section limit reached").
- **39-41 `_strength_requirements`:** A ≥ A_current × ratio and Sx ≥ Sx_current × ratio (first-order: stress ∝ 1/A and 1/S).
- **44-89 `_Requests`:** collects every request. **If two rules ask for the same member, the larger section wins** (55-65). Braces are added or upsized; struts added.
- **148-279 `apply_feedback`: the rule-to-action map (all rules apply together).**

| Rule | Lines | Action |
|---|---|---|
| 1 Yield | 167-168 | upsize that member (A, Sx ≥ × ratio) |
| 2 Buckling | 170-177 | add a Y mid-height strut (preferring a Y-braced bay); if already strutted, upsize for ry ≥ × √ratio |
| 3 Rupture | 179-180 | upsize that member |
| 4 Floor IDR | 182-185 | X-brace every bay of that floor, both directions (existing braces: upsize) |
| 5 Soft story | 187-191 | upsize that story's columns for Ix (X) or Iy (Y) ≥ × ratio |
| 6 Mid-story | 197-201 | X-brace perimeter bays of those floors |
| 7 Directional | 203-205 | X-brace the weak direction's bays |
| 8 Roof | 207-218 | upsize the columns of the story with the greatest drift (Ix or Iy) |
| 9 Torsion | 220-225 | X-brace all perimeter bays, all floors |
| 10 Mean stress | 227-234 | upsize every member, brace, strut |

- **236-279:** applies the requests to a copy of the state and logs every action (target, from, to, rules). **Sections only ever increase; bracing is only ever added.**

### 2.10 The closed loop — `pipeline.py`

- **12:** `MAX_FEEDBACK_ITERATIONS = 10`.
- **26-36:** writes `run_summary.json` (status running, run key, fingerprint).
- **38-47 `report`:** writes `progress.json` (iteration, phase, step, and while simulating the time, latest frame and ruptures). It can never crash a run.
- **49-59 `announce`:** writes `live_state.json` at the start of each iteration's analysis (the model state being analyzed, the members changed by feedback, the node list).
- **69-116: the loop, for iteration n.**
  1. `run_nltha` (§2.3-2.8), with `live_progress` (61-64) as the progress callback.
  2. Saves `iteration_n/record.json`, `history.csv` and `frames.json` immediately (80 → `output_layer.write_iteration` 46-60: written as a temporary folder, then renamed).
  3. Updates the summary.
  4. Checks the stop conditions (93-101):
     - all pass → "all evaluation checks pass";
     - n = 10 → "feedback iteration limit reached (10)";
     - no evaluation → stop.
  5. Feedback, with **one-step sizing if this iteration collapsed during the earthquake** (104). No possible change → "no further improvement possible".
  6. The new model state goes to the next iteration (116).
- **117-123:** marks the run completed (or error with the message) and writes the final `progress.json` ("done").

**`output_layer.py` 29-43:** atomic JSON writes with a retry, so Godot reading a file at the same moment can't crash Python on Windows (stress-tested with 5,794 concurrent reads).

### 2.11 Showing the results (Godot)

**`main.gd`**
- **115-134 `_process`:** every screen frame, advances the live shake and the preview replay. While Python runs, polls the run every 0.1 s.
- **1259-1290 `_poll_run`:** each new `iteration_n` folder becomes an Iteration Records entry and is drawn and printed immediately. It then reads `progress.json` for the line "Iteration n: simulating step s/2529" and the live shake frame.
- **1356-1386 `_finish_run`:** handles `reuse.json` (loads the existing run), reports replaced older runs, an unexpected stop or an error, and prints the stop reason.
- **1388-1429 `_add_iteration_entry` / `_on_iteration_pressed` / `_show_iteration`:** a clickable record per iteration. It redraws that iteration's model state in the main view and the Simulation Preview, with members changed by feedback in red.
- **1543-1650 `_log_record`:** the terminal report:
  - input (PGA, duration, record length);
  - T and the NSCP limit;
  - element, floor and structure results;
  - triggered rules with demand ratios;
  - peak metrics (the manuscript's four dependent variables: peak stress, peak displacement, peak deformation, MaxIDR);
  - the feedback that produced the iteration and its sizing mode.
- **1690-1722 Clean Previous Runs:** a confirmation dialog, then permanent deletion of `runs/run_*`.

### 2.12 The visual shake and collapse view (display only)

**What it is:** the node displacements OpenSeesPy computed, drawn on the 3D model. It does not feed back into the analysis or the evaluation.

**Python side**
- `seismic_simulation.py` 34 (`FRAME_EVERY_STEPS = 10`), 534-538 (frames), 601-605 (first rupture times), 752-756 (`frames`, `ruptures`, `collapse_time_s` in the record).
- `pipeline.py` 38-64: the live frame goes to `progress.json` every 0.1 s; `live_state.json` says which structure is being analyzed. `iteration_n/frames.json` keeps the whole record for replay.

**Live shake while simulating (`main.gd`)**
- **1302-1315 `_begin_live_shake`:** reads `live_state.json` and redraws the structure being analyzed.
- **1317-1334 `_set_live_target`:** takes the newest frame, updates the magnification, drops newly ruptured members.
- **1336-1345 `_update_live_shake`:** eases the drawn shape toward the newest frame every screen frame.
- **1347-1354 `_stop_live_shake`:** the shake stops when that iteration's folder is saved; the saved view replaces it.

**Replay after the run (`main.gd`)**
- **1467-1495 `_on_preview_input`:** clicking the Simulation Preview loads `frames.json`.
- **1497-1541 `_update_preview_playback`:** plays it in real time (0.1 s frames, linearly blended) in **both** the preview and the main view. At the end it holds the last frame; a collapsed iteration shows "collapse at t = X s".

**How a frame moves the model (`static_structure_view.gd`)**
- **69-92 `apply_frame`:**
  - Python's X displacement → Godot x, Y → Godot z, times the magnification.
  - **Column lengths are kept:** each column node is placed from the node below using the computed story drift (capped at the column length), and drops so the column keeps its length. A story swayed as far as its column length lies flat. At ordinary drifts the drop is invisible.
  - Every member is drawn straight between its two end nodes, so nothing floats; base nodes stay fixed.
- **100-129 `drop_member`, 131-147 `update_falls`:** at a member's first rupture time it detaches and falls (9.81 m/s², turning flat, at its true length) and comes to rest on the ground. The analysis keeps the member in the model; the fall is a display of the rupture event.
- **Magnification** (`main.gd` 1292-1294): the record's peak node displacement is shown as 4 % of the building height, between ×1 and ×200. The factor is always on screen.

---

## 3. The default building, iteration by iteration

Actual run: `simulation.py --run-dir` with the UI defaults (M5, 15 s). **Result: PASS at Iteration 4** (5 iterations saved; stop reason "all evaluation checks pass"). The same result is obtained through the Godot UI.

**Before Iteration 0 (same for every iteration):**
- Ground motion: PGA 0.0487 g, D5-95 = 15 s, record 25.28 s (2,529 steps), X seed 1, Y seed 2.
- 80 nodes, 160 members, all W12X26; tributary masses; panel loads 6 / 3 kPa.

| Iteration | Result | T (s) → limit | Peak stress (MPa) | Max IDR | Roof X / Y (mm) | Triggered |
|---|---|---|---|---|---|---|
| 0 (open-loop) | FAIL | 3.954 → 2.0 % | 211.1 | 0.432 % | 11.2 / 20.5 | Rule 1 × 38 (max ratio 1.242) |
| 1 | FAIL | 3.479 → 2.0 % | 212.0 | 0.247 % | 16.6 / 21.8 | Rule 1 × 33 (1.247) |
| 2 | FAIL | 3.157 → 2.0 % | 198.7 | 0.320 % | 14.2 / 25.6 | Rule 1 × 19 (1.169) |
| 3 | FAIL | 2.874 → 2.0 % | 180.5 | 0.322 % | 14.4 / 23.4 | Rule 1 × 2 (1.062) |
| **4** | **PASS** | 2.859 → 2.0 % | **169.6** (< 170) | 0.304 % | 14.2 / 23.6 | none |

Drift stays far below the NSCP 2.0 % limit throughout (roof limit 0.020 × 14 m = 0.28 m). The deficiency is **strength**: the low AK Steel yield of 170 MPa against gravity plus earthquake bending. That is why only Rule 1 fires. Soft story, torsion (ratios 1.03-1.16 < 1.2) and the other rules stay clear. **This is also why the default building never gets X-bracing:** the bracing rules (4, 6, 7, 9) only trigger on drift or torsion failures.

**Iteration 0 → 1: feedback on 38 overstressed members (demand-ratio sizing)**
- **What failed:**
  - the 18 interior X-direction floor beams on levels 1-3 (the lines carrying the full 6 m tributary width: 36 kN/m);
  - 12 story-1 columns (8 edge, 4 interior);
  - 8 story-2 columns (4 edge, 4 interior).
- **Action (`feedback_engine.py` 167-168 → `select_section` 26-36):** each member moves to the smallest section with A and Sx ≥ current × its own ratio.
  - Ratios up to about 1.16 → **W14X30** (Sx 688 vs 547 × 10³ mm³, +26 %).
  - Higher ratios need more area than W14X30's +16 %, so they skip to **W16X36**.
  - Result: 14 beams + 7 columns → W14X30; 4 beams + 13 columns → W16X36.

**Iteration 1 → 2: 33 still overstressed** (stiffer members attract more force, moment redistribution)
- 14 interior beams W14X30 → W16X36.
- 8 columns W16X36 → W18X50.
- 7 columns W14X30 → W16X36.
- 4 story-3 edge columns W12X26 → W14X30.

**Iteration 2 → 3: 19 overstressed, all columns** (the beams are now adequate)
- 19 column upsizes, including 4 interior columns W18X50 → **W21X62**.

**Iteration 3 → 4: 2 overstressed** (story-3 interior columns, ratio 1.062)
- 2 columns W14X30 → W16X36.

**Iteration 4:** peak stress 169.6 MPa ≤ 170, every rule clear → **PASS**. The loop stops (`pipeline.py` 93-95).

**Final design (Iteration 4):**

| Section | Count | Where |
|---|---|---|
| W12X26 | 113 | everything not overstressed (all Y-beams, edge-row X-beams, roof beams, upper columns) |
| W16X36 | 31 | 18 interior floor X-beams; 10 edge + 3 interior columns |
| W18X50 | 10 | 6 edge + 4 interior columns |
| W21X62 | 4 | **interior columns** (the heaviest members) |
| W14X30 | 2 | 1 edge + 1 interior column |

- **Interior columns end up the heaviest**, the pattern the engineer described (interior members carry more floor load). It came out of the analysis, not a hard-coded rule.
- **No bracing was needed**, and 113 of 160 members kept the starting section: an adequate design rather than the strongest one.
- No member was ever downsized. Every change is logged in `iteration_n/record.json` → `applied_feedback.actions` with its target, from, to and rule.

**Manuscript dependent variables (open-loop vs closed-loop for this building):**

| Metric | Iteration 0 (open-loop) | Iteration 4 (closed-loop) |
|---|---|---|
| Peak stress | 211.1 MPa | 169.6 MPa |
| Peak displacement (roof, X / Y) | 11.2 / 20.5 mm | 14.2 / 23.6 mm |
| Peak deformation | 15.6 mm | 10.9 mm |
| MaxIDR | 0.432 % | 0.304 % |

The roof displacement rises slightly while stress and IDR fall. The upsized frame is stiffer (T 3.954 → 2.859 s), so it responds to a different part of the ground motion's frequency content. Roof displacement only becomes a Table 1 target (Rule 8) when it exceeds the NSCP-derived limit, 0.28 m here, far above 23.6 mm. The rules correct code-check failures; they don't optimize every metric at once. Be ready to explain this if asked.

**Same building at Magnitude 7 (shows the bracing rules working):**

| Iteration | Result | What happened |
|---|---|---|
| 0 | FAIL | collapsed during the earthquake at 11.09 s; Rules 1, 3, 4, 7, 10 |
| 1 | FAIL | feedback added **96 X-braced bays** (Rules 4 and 7) and one-step upsized all 160 members (after a collapse); IDR 0.124 %; Rule 1 only |
| 2-4 | FAIL | Rule 1 upsizes (33, 8, 2 members) |
| 5 | PASS | all checks pass |

---

## 4. Questions a panel may ask (short answers)

- **Why NLTHA and not the NSCP formula ΔM = 0.7RΔS?** NSCP Eq. 208-21's Exception allows ΔM to be computed by nonlinear time-history analysis (§208.5.3.6.3), and the drift must then not be reduced. ProGen compares NLTHA drift directly to §208.6.5.1.
- **Why is the drift limit 2.0 %, not 1.5 %?** NSCP §208.6.5.1: 0.020 h for T ≥ 0.7 s. Chang & Cheng's 1.5 % was one of two dataset scenarios (they also used 2.5 %), not a code limit.
- **Why W-shapes, and why W12×26?** The licensed structural engineer's consultation: improve members by increasing web and flange depth and thickness (a W-shape catalogue) instead of adding members. W12×26 is the engineer's second example, and the smallest that survives gravity for the default building.
- **Why does the stress fail under gravity alone?** AK Steel's yield (170 MPa) is low. A 6 m interior beam carrying 36 kN/m has an end moment of ~108 kN·m, and 108 / 547 × 10³ mm³ ≈ 199 MPa (the model gives 181 MPa because joints aren't perfectly fixed). That's the open-loop deficiency the closed loop corrects.
- **Why no X-bracing on the default building?** Its drift (0.43 %) is far under the 2 % limit, so no drift or torsion rule fires; only Rule 1 (stress), whose action is upsizing. At M7 the same building collapses, Rules 4 and 7 fire, and 96 bays are X-braced.
- **Why did stiffer members sometimes still fail in the next iteration?** Stiffer members attract more force (moment redistribution). The loop re-simulates and corrects, which is why it iterates.
- **Why one step after a collapse?** Responses leading into a dynamic instability (e.g. strains hundreds of times the rupture limit) describe the collapse, not a demand you can size for. Bounding the correction is a ProGen design choice (collapse-assessment practice treats that point as a limit state).
- **Is the shake the real simulation?** The lateral node displacements are exactly what OpenSeesPy computed, every 0.1 s. Three things are display choices: the magnification (shown on screen), keeping column lengths (vertical drop), and members falling at their first rupture time (the analysis keeps them). Member bending between nodes is not drawn.
- **Isn't STAAD already doing this?** STAAD analyses a model a human defines. ProGen is a computer science contribution: procedural generation whose rules are driven by simulation feedback, with every change traceable to the rule that caused it. STAAD's reporting conventions (displacement, drift, combined stress) guided which metrics ProGen reports.
- **Is the result reproducible?** Yes. Fixed seeds, deterministic rules, and the rerun tests match (sections identical; numbers to ~14 digits, the last digits differing only from ARPACK's random start vector).
- **Why is the record longer than the duration input?** The input is the strong-shaking duration D5-95 (Rezaeian & Der Kiureghian). The build-up and decay add time; the record ends at 99 % of the energy.

---

## 5. Stated assumptions and limitations (have these ready)

1. Poisson's ratio 0.30; epicentral distance 40 km; Rule 10's 90 %; a mid-height strut halves the buckling length; loads fixed at 6 / 3 kPa.
2. W-shape geometry with idealized AK Steel properties; one section list for beams, columns and braces.
3. No rigid floor diaphragm: a single column line can sway independently.
4. Braces have no compression buckling cap; X-diagonals are not connected at the crossing.
5. Floor load carried by X-direction beams only (one-way load path) and treated wholly as seismic weight.
6. One synthetic ground-motion pair (NSCP §208.5.3.6.1 asks for ≥ 3 recorded pairs for design); the attenuation law is from California and Central America data.
7. No 5 % accidental torsion (§208.5.1.3); no panel-zone deformation (§208.6.2 Item 2).
8. Large buildings take a long time (minutes per iteration); the open/closed-loop UI is future work.
9. The visual shake is a display of the computed node displacements. It is magnified; member bending, ground translation and vertical displacements are not drawn. Falling members and the column-length rule are display choices, not computed collapse mechanics; the analysis does not remove ruptured members or model contact.

---

## 6. References used by the tool

- Association of Structural Engineers of the Philippines. (2015). *National Structural Code of the Philippines 2015, Vol. 1* (7th ed.). §208.5.2.3, §208.5.3.2, §208.5.3.6.1, §208.5.3.6.3, §208.6.2, §208.6.3, §208.6.4.2 (Eq. 208-21), §208.6.5.1, Tables 208-9 and 208-10.
- American Institute of Steel Construction. (2023). *Steel Construction Manual* (16th ed.) / *AISC Shapes Database v16.0*.
- Esteva, L., & Villaverde, R. (1973). Seismic risk, design spectra and structural reliability. *Proc. 5th WCEE*, 2586-2597 (coefficients via JCSS Probabilistic Model Code §2.17, Table 1).
- Rezaeian, S., & Der Kiureghian, A. (2010). *Stochastic modeling and simulation of ground motions for performance-based earthquake engineering* (PEER Report 2010/02), Table 4.3 and §2.5; and the 2010 *EESD* article.
- Chang, K.-H., & Cheng, C.-Y. (2020). Learning to simulate and design for structural engineering. *PMLR* 119, 1426-1436 (LSDSE parameter ranges; section-sizing framing).
- McKenna, F., Scott, M. H., & Zhu, M. (2018). OpenSeesPy. *SoftwareX*, 7, 6-11 (the analysis engine: forceBeamColumn, Steel01, fiber sections, Newmark).
- AK Steel Grade 25 datasheet (Look Polymers) — Table 2.
