from __future__ import annotations

import csv
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
import openseespy.opensees as ops

from input_management import BuildingTopology, MaterialProps, WSection, w_section_lookup
from procedural_content_generation import TopologyGrid, generate_topology_grid, member_id
from performance_evaluation import evaluate_gravity_fallback, evaluate_performance, drift_limit_for_period
from data_management import build_run_record
from validation import validate_model

GRAVITY = 9.80665
GRAVITY_PATTERN_TAG = 1
GRAVITY_TS_TAG = 1
SEISMIC_PATTERN_TAG_X = 2
SEISMIC_TS_TAG_X = 2
SEISMIC_PATTERN_TAG_Y = 3
SEISMIC_TS_TAG_Y = 3

COL_TRANSF_TAG = 1
BEAM_TRANSF_TAG = 2
STEEL_TAG = 101
STEEL_RUPTURE_TAG = 102
ELASTIC_TRUSS_TAG = 103
INTEGRATION_POINTS = 3
FLANGE_FIBERS_ACROSS_WIDTH = 8
WEB_FIBERS_ALONG_DEPTH = 8
FRAME_EVERY_STEPS = 10

MAGNITUDE_MIN, MAGNITUDE_MAX = 1.0, 10.0
_EV_B1, _EV_B2, _EV_B3, _EV_B4 = 5600.0, 0.8, 2.0, 40.0
NOMINAL_EPICENTRAL_DISTANCE_KM = 40.0
_CM_S2_PER_G = 981.0

RDK_FILTER_FREQ_MID_HZ = 5.87
RDK_FILTER_FREQ_RATE_HZ_PER_S = -0.089
RDK_FILTER_DAMPING = 0.213
RDK_MEAN_D595_S = 17.25
RDK_MEAN_TMID_S = 12.38
HIGH_PASS_CORNER_HZ = 0.2
RECORD_END_CUMULATIVE_INTENSITY = 0.99
MOTION_SEED_X = 1
MOTION_SEED_Y = 2


def magnitude_to_amplitude_g(magnitude: float) -> float:
    clamped = min(max(magnitude, MAGNITUDE_MIN), MAGNITUDE_MAX)
    pga_cm_s2 = _EV_B1 * math.exp(_EV_B2 * clamped) / (
        (NOMINAL_EPICENTRAL_DISTANCE_KM + _EV_B4) ** _EV_B3
    )
    return pga_cm_s2 / _CM_S2_PER_G


def _gamma_quantiles(shape: float, probabilities: Sequence[float]) -> np.ndarray:
    t = np.linspace(1e-9, shape + 12.0 * math.sqrt(shape) + 20.0, 40000)
    log_density = (shape - 1.0) * np.log(t) - t
    density = np.exp(log_density - log_density.max())
    cdf = np.cumsum(density)
    cdf /= cdf[-1]
    return np.interp(probabilities, cdf, t)


def _envelope_shape_for_ratio(target_ratio: float) -> float:
    def ratio(shape: float) -> float:
        q05, q45, q95 = _gamma_quantiles(shape, [0.05, 0.45, 0.95])
        return (q95 - q05) / q45

    lo, hi = 1.01, 400.0
    for _ in range(80):
        mid = 0.5 * (lo + hi)
        if ratio(mid) > target_ratio:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def _high_pass(signal: np.ndarray, dt: float, corner_hz: float) -> np.ndarray:
    omega_c = 2.0 * math.pi * corner_hz
    c, k = 2.0 * omega_c, omega_c ** 2
    gamma, beta = 0.5, 0.25
    k_eff = k + gamma / (beta * dt) * c + 1.0 / (beta * dt * dt)
    u = v = 0.0
    a = signal[0]
    out = np.empty_like(signal)
    out[0] = a
    for i in range(1, len(signal)):
        p_eff = (
            signal[i]
            + (u / (beta * dt * dt) + v / (beta * dt) + (0.5 / beta - 1.0) * a)
            + c * (gamma * u / (beta * dt) + (gamma / beta - 1.0) * v + dt * (0.5 * gamma / beta - 1.0) * a)
        )
        u_new = p_eff / k_eff
        a_new = (u_new - u) / (beta * dt * dt) - v / (beta * dt) - (0.5 / beta - 1.0) * a
        v = v + dt * ((1.0 - gamma) * a + gamma * a_new)
        u, a = u_new, a_new
        out[i] = a
    return out


def stochastic_motion(dt: float, duration: float, magnitude: float, seed: int) -> List[float]:
    shape = _envelope_shape_for_ratio(RDK_MEAN_D595_S / RDK_MEAN_TMID_S)
    q05, q45, q95, q_end = _gamma_quantiles(shape, [0.05, 0.45, 0.95, RECORD_END_CUMULATIVE_INTENSITY])
    scale = duration / (q95 - q05)
    t_mid = scale * q45
    t_end = scale * q_end
    n = int(round(t_end / dt)) + 1
    t = np.arange(n) * dt
    envelope = np.zeros(n)
    positive = t > 0.0
    log_env = 0.5 * ((shape - 1.0) * np.log(t[positive] / scale) - t[positive] / scale)
    envelope[positive] = np.exp(log_env - log_env.max())

    filter_freq = 2.0 * math.pi * (RDK_FILTER_FREQ_MID_HZ + RDK_FILTER_FREQ_RATE_HZ_PER_S * (t - t_mid))
    if filter_freq.min() <= 0.0:
        raise ValueError("duration too long for the filter-frequency model: frequency becomes non-positive")
    zeta = RDK_FILTER_DAMPING
    root = math.sqrt(1.0 - zeta * zeta)
    noise = np.random.default_rng(seed).standard_normal(n)

    process = np.zeros(n)
    for j in range(1, n):
        lag = t[j] - t[: j + 1]
        w = filter_freq[: j + 1]
        h = (w / root) * np.exp(-zeta * w * lag) * np.sin(w * root * lag)
        norm = math.sqrt(float(h @ h))
        if norm > 0.0:
            process[j] = envelope[j] * float(h @ noise[: j + 1]) / norm

    filtered = _high_pass(process, dt, HIGH_PASS_CORNER_HZ)
    peak = float(np.abs(filtered).max())
    amplitude_g = magnitude_to_amplitude_g(magnitude)
    return list(filtered / peak * amplitude_g) if peak > 0.0 else list(filtered)


def read_motion_csv(path: Path) -> Tuple[float, List[float]]:
    rows = []
    with path.open(newline="") as stream:
        for row in csv.reader(stream):
            if not row or row[0].strip().lower() in {"time", "t"}:
                continue
            try:
                rows.append([float(value) for value in row[:2]])
            except ValueError:
                continue
    if not rows:
        raise ValueError(f"No numeric ground-motion rows found in {path}")
    if len(rows[0]) == 1:
        return 0.01, [row[0] for row in rows]
    dt = rows[1][0] - rows[0][0] if len(rows) > 1 else 0.01
    if dt <= 0:
        raise ValueError("Ground-motion time values must increase")
    return dt, [row[1] for row in rows]


@dataclass
class ElementInfo:
    tag: int
    kind: str
    member: str
    i_tag: int
    j_tag: int
    section: WSection
    length_m: float
    story: int = 0


@dataclass
class BuiltModel:
    topology: BuildingTopology
    grid: TopologyGrid
    node_tags: Dict[tuple, int]
    node_coords: Dict[int, Tuple[float, float, float]]
    column_elements: List[Tuple[int, int, int]]
    beam_elements: List[Tuple[int, int, int]]
    brace_elements: List[Tuple[int, int, int]]
    strut_elements: List[Tuple[int, int, int]]
    base_node_tags: List[int]
    floor_beam_tags: Dict[int, List[int]]
    material: MaterialProps
    elements: Dict[int, ElementInfo] = field(default_factory=dict)
    nonlinear: bool = False
    loaded_beam_tags: Dict[int, List[int]] = field(default_factory=dict)


def node_tag(topology: BuildingTopology, level: int, row: int, col: int) -> int:
    nx, ny = topology.n_nodes_x, topology.n_nodes_y
    return level * (nx * ny) + row * nx + col + 1


def _tributary_width_y(topology: BuildingTopology, row: int) -> float:
    by = topology.bay_width_y_m
    if row == 0 or row == topology.bay_count_y:
        return by / 2.0
    return by


def _tributary_width_x(topology: BuildingTopology, col: int) -> float:
    bx = topology.bay_width_x_m
    if col == 0 or col == topology.bay_count_x:
        return bx / 2.0
    return bx


def _define_w_section(section_tag: int, section: WSection, material: MaterialProps) -> None:
    d, bf, tf, tw = section.d_m, section.bf_m, section.tf_m, section.tw_m
    ops.section("Fiber", section_tag, "-GJ", material.G_kpa * section.J_m4)
    ops.patch("rect", STEEL_RUPTURE_TAG, FLANGE_FIBERS_ACROSS_WIDTH, 1, -bf / 2.0, d / 2.0 - tf, bf / 2.0, d / 2.0)
    ops.patch("rect", STEEL_RUPTURE_TAG, FLANGE_FIBERS_ACROSS_WIDTH, 1, -bf / 2.0, -d / 2.0, bf / 2.0, -d / 2.0 + tf)
    ops.patch("rect", STEEL_RUPTURE_TAG, 1, WEB_FIBERS_ALONG_DEPTH, -tw / 2.0, -d / 2.0 + tf, tw / 2.0, d / 2.0 - tf)


def apply_gravity_loads(built: BuiltModel) -> None:
    topology = built.topology
    ops.timeSeries("Linear", GRAVITY_TS_TAG)
    ops.pattern("Plain", GRAVITY_PATTERN_TAG, GRAVITY_TS_TAG)

    inv_node_tags = {tag: key for key, tag in built.node_tags.items()}
    x_beam_lookup: Dict[int, list] = {lvl: [] for lvl in range(1, topology.n_levels)}
    for ele_tag, i_tag, j_tag in built.beam_elements:
        (li, ri, ci) = inv_node_tags[i_tag]
        (lj, rj, cj) = inv_node_tags[j_tag]
        if not ((li == lj) and (ri == rj) and (abs(ci - cj) == 1)):
            continue
        level, row = li, ri
        is_roof = level == topology.floor_count
        panel_load_kpa = topology.roof_load_kpa if is_roof else topology.floor_load_kpa
        w = panel_load_kpa * _tributary_width_y(topology, row)
        ops.eleLoad("-ele", ele_tag, "-type", "-beamUniform", 0.0, -w)
        x_beam_lookup[level].append(ele_tag)
    built.loaded_beam_tags = x_beam_lookup

    self_weight: Dict[int, float] = {}
    for info in built.elements.values():
        weight_kn = built.material.density_kg_m3 * info.section.A_m2 * info.length_m * GRAVITY / 1000.0
        for tag in (info.i_tag, info.j_tag):
            self_weight[tag] = self_weight.get(tag, 0.0) + weight_kn / 2.0
    for tag, weight_kn in self_weight.items():
        if tag not in built.base_node_tags:
            ops.load(tag, 0.0, 0.0, -weight_kn, 0.0, 0.0, 0.0)


def build_model(
    topology: BuildingTopology,
    material: MaterialProps = None,
    model_state: Optional[dict] = None,
    apply_loads: bool = True,
    nonlinear: bool = False,
) -> BuiltModel:
    material = material or MaterialProps()
    grid: TopologyGrid = generate_topology_grid(topology, model_state)
    sections = w_section_lookup()

    ops.wipe()
    ops.model("basic", "-ndm", 3, "-ndf", 6)

    node_tags: Dict[tuple, int] = {}
    node_coords: Dict[int, Tuple[float, float, float]] = {}
    base_node_tags: List[int] = []
    for key, (x, y, z) in grid.node_coords_m.items():
        tag = node_tag(topology, *key)
        ops.node(tag, x, y, z)
        node_tags[key] = tag
        node_coords[tag] = (x, y, z)
    next_tag = topology.n_levels * topology.n_nodes_x * topology.n_nodes_y + 1
    for key, (x, y, z) in grid.mid_node_coords_m.items():
        ops.node(next_tag, x, y, z)
        node_tags[key] = next_tag
        node_coords[next_tag] = (x, y, z)
        next_tag += 1
    for key in grid.base_keys:
        tag = node_tags[key]
        ops.fix(tag, 1, 1, 1, 1, 1, 1)
        base_node_tags.append(tag)

    ops.geomTransf("PDelta", COL_TRANSF_TAG, 1.0, 0.0, 0.0)
    ops.geomTransf("Linear", BEAM_TRANSF_TAG, 0.0, 0.0, 1.0)

    used_sections = sorted(
        set(grid.member_sections.values())
        | {b.section for b in grid.braces}
        | {s.section for s in grid.struts},
        key=lambda name: [s.name for s in sections.values()].index(name),
    )
    integration_tag: Dict[str, int] = {}
    if nonlinear:
        ops.uniaxialMaterial("Steel01", STEEL_TAG, material.fy_kpa, material.E_kpa, material.hardening_ratio)
        ops.uniaxialMaterial(
            "MinMax", STEEL_RUPTURE_TAG, STEEL_TAG,
            "-min", -material.rupture_strain, "-max", material.rupture_strain,
        )
        for index, name in enumerate(used_sections):
            section_tag = 201 + index
            _define_w_section(section_tag, sections[name], material)
            integration_tag[name] = 301 + index
            ops.beamIntegration("Lobatto", integration_tag[name], section_tag, INTEGRATION_POINTS)
    else:
        ops.uniaxialMaterial("Elastic", ELASTIC_TRUSS_TAG, material.E_kpa)

    elements: Dict[int, ElementInfo] = {}
    column_elements: List[Tuple[int, int, int]] = []
    beam_elements: List[Tuple[int, int, int]] = []
    brace_elements: List[Tuple[int, int, int]] = []
    strut_elements: List[Tuple[int, int, int]] = []
    floor_beam_tags: Dict[int, List[int]] = {lvl: [] for lvl in range(1, topology.n_levels)}
    counter = [1]

    def length(i_tag: int, j_tag: int) -> float:
        (xi, yi, zi), (xj, yj, zj) = node_coords[i_tag], node_coords[j_tag]
        return ((xj - xi) ** 2 + (yj - yi) ** 2 + (zj - zi) ** 2) ** 0.5

    def frame_element(kind: str, member: str, i_tag: int, j_tag: int, section: WSection,
                      transf: int, story: int) -> int:
        tag = counter[0]
        counter[0] += 1
        if nonlinear:
            ops.element("forceBeamColumn", tag, i_tag, j_tag, transf, integration_tag[section.name],
                        "-iter", 20, 1.0e-8)
        else:
            ops.element("elasticBeamColumn", tag, i_tag, j_tag, section.A_m2, material.E_kpa,
                        material.G_kpa, section.J_m4, section.Ix_m4, section.Iy_m4, transf)
        elements[tag] = ElementInfo(tag, kind, member, i_tag, j_tag, section, length(i_tag, j_tag), story)
        return tag

    strut_mid_by_column: Dict[Tuple[int, int, int], tuple] = {}
    for key in grid.mid_node_coords_m:
        _, story, row, col = key
        strut_mid_by_column[(story, row, col)] = key

    for i_key, j_key in grid.column_pairs:
        mid = member_id(i_key, j_key)
        section = sections[grid.member_sections[mid]]
        story, row, col = j_key
        mid_key = strut_mid_by_column.get((story, row, col))
        if mid_key is None:
            segments = [(node_tags[i_key], node_tags[j_key])]
        else:
            segments = [(node_tags[i_key], node_tags[mid_key]), (node_tags[mid_key], node_tags[j_key])]
        for i_tag, j_tag in segments:
            tag = frame_element("column", mid, i_tag, j_tag, section, COL_TRANSF_TAG, story)
            column_elements.append((tag, i_tag, j_tag))

    for i_key, j_key in grid.beam_pairs:
        mid = member_id(i_key, j_key)
        section = sections[grid.member_sections[mid]]
        i_tag, j_tag = node_tags[i_key], node_tags[j_key]
        tag = frame_element("beam", mid, i_tag, j_tag, section, BEAM_TRANSF_TAG, i_key[0])
        beam_elements.append((tag, i_tag, j_tag))
        floor_beam_tags[i_key[0]].append(tag)

    for brace in grid.braces:
        section = sections[brace.section]
        label = f"brace:{brace.story}:{brace.axis}:{brace.line}:{brace.bay}"
        for a_key, b_key in brace.diagonals():
            i_tag, j_tag = node_tags[a_key], node_tags[b_key]
            tag = counter[0]
            counter[0] += 1
            mat = STEEL_RUPTURE_TAG if nonlinear else ELASTIC_TRUSS_TAG
            ops.element("Truss", tag, i_tag, j_tag, section.A_m2, mat)
            elements[tag] = ElementInfo(tag, "brace", label, i_tag, j_tag, section, length(i_tag, j_tag), brace.story)
            brace_elements.append((tag, i_tag, j_tag))

    for strut in grid.struts:
        section = sections[strut.section]
        a_key, b_key = strut.mid_node_keys()
        i_tag, j_tag = node_tags[a_key], node_tags[b_key]
        label = f"strut:{strut.story}:{strut.axis}:{strut.line}:{strut.bay}"
        tag = frame_element("strut", label, i_tag, j_tag, section, BEAM_TRANSF_TAG, strut.story)
        strut_elements.append((tag, i_tag, j_tag))

    built = BuiltModel(
        topology=topology,
        grid=grid,
        node_tags=node_tags,
        node_coords=node_coords,
        column_elements=column_elements,
        beam_elements=beam_elements,
        brace_elements=brace_elements,
        strut_elements=strut_elements,
        base_node_tags=base_node_tags,
        floor_beam_tags=floor_beam_tags,
        material=material,
        elements=elements,
        nonlinear=nonlinear,
    )
    if apply_loads:
        apply_gravity_loads(built)
    return built


def _node_masses(built: BuiltModel) -> Dict[int, float]:
    topology = built.topology
    node_mass: Dict[int, float] = {}
    for level in range(1, topology.n_levels):
        load_kpa = topology.roof_load_kpa if level == topology.floor_count else topology.floor_load_kpa
        for row in range(topology.n_nodes_y):
            for col in range(topology.n_nodes_x):
                area = _tributary_width_x(topology, col) * _tributary_width_y(topology, row)
                tag = built.node_tags[(level, row, col)]
                node_mass[tag] = node_mass.get(tag, 0.0) + load_kpa * area / GRAVITY
    for info in built.elements.values():
        member_mass = built.material.density_kg_m3 * info.section.A_m2 * info.length_m / 1000.0
        for tag in (info.i_tag, info.j_tag):
            node_mass[tag] = node_mass.get(tag, 0.0) + member_mass / 2.0
    return {tag: mass for tag, mass in node_mass.items() if tag not in built.base_node_tags and mass > 0.0}


def _assign_masses(node_mass: Dict[int, float]) -> None:
    for tag, mass in node_mass.items():
        ops.mass(tag, mass, mass, mass, 0.0, 0.0, 0.0)


def _apply_gravity_and_masses(built: BuiltModel) -> None:
    ops.system("UmfPack")
    ops.numberer("RCM")
    ops.constraints("Plain")
    ops.integrator("LoadControl", 0.1)
    ops.algorithm("Newton")
    ops.analysis("Static")
    if ops.analyze(10) != 0:
        raise RuntimeError("Gravity analysis failed before seismic loading")
    ops.loadConst("-time", 0.0)
    _assign_masses(_node_masses(built))


def nscp_lateral_forces(level_weights_kn: Dict[int, float], story_height_m: float,
                        period_s: float, base_shear_kn: float) -> Dict[int, float]:
    top = max(level_weights_kn)
    top_force = 0.0 if period_s <= 0.7 else min(0.07 * period_s * base_shear_kn, 0.25 * base_shear_kn)
    weighted = {level: w * level * story_height_m for level, w in level_weights_kn.items()}
    total = sum(weighted.values())
    forces = {level: (base_shear_kn - top_force) * value / total for level, value in weighted.items()}
    forces[top] += top_force
    return forces


def elastic_story_stiffness(topology: BuildingTopology, model_state: Optional[dict] = None) -> dict:
    stiffness = {}
    period_s = None
    for axis, dof in (("x", 1), ("y", 2)):
        built = build_model(topology, model_state=model_state, apply_loads=False, nonlinear=False)
        node_mass = _node_masses(built)
        _assign_masses(node_mass)
        if period_s is None:
            period_s = 2.0 * math.pi / _fundamental_omega()
        level_tags = {
            level: [built.node_tags[(level, row, col)]
                    for row in range(topology.n_nodes_y) for col in range(topology.n_nodes_x)]
            for level in range(1, topology.n_levels)
        }
        level_mass = {level: sum(node_mass.get(tag, 0.0) for tag in tags) for level, tags in level_tags.items()}
        forces = nscp_lateral_forces({level: m * GRAVITY for level, m in level_mass.items()},
                                     topology.story_height_m, period_s, 1000.0)
        ops.timeSeries("Linear", 20)
        ops.pattern("Plain", 20, 20)
        for level, tags in level_tags.items():
            for tag in tags:
                share = forces[level] * node_mass.get(tag, 0.0) / level_mass[level]
                load = [0.0] * 6
                load[dof - 1] = share
                ops.load(tag, *load)
        ops.system("UmfPack")
        ops.numberer("RCM")
        ops.constraints("Plain")
        ops.integrator("LoadControl", 1.0)
        ops.algorithm("Linear")
        ops.analysis("Static")
        if ops.analyze(1) != 0:
            raise RuntimeError("Elastic lateral analysis for story stiffness failed")
        average = {0: 0.0}
        for level, tags in level_tags.items():
            average[level] = sum(node_mass.get(tag, 0.0) * ops.nodeDisp(tag, dof) for tag in tags) / level_mass[level]
        stiffness[axis] = {}
        for story in range(1, topology.n_levels):
            shear = sum(forces[level] for level in range(story, topology.n_levels))
            drift = abs(average[story] - average[story - 1])
            stiffness[axis][story] = shear / drift if drift > 0.0 else 0.0
    return {"x": stiffness["x"], "y": stiffness["y"], "period_s": period_s}


def _fundamental_omega() -> float:
    attempts = []
    for args in ((2,), ("-fullGenLapack", 2)):
        try:
            eigenvalues = [float(value) for value in ops.eigen(*args)]
        except Exception as error:
            attempts.append(f"{args}: {error}")
            continue
        valid = [value for value in eigenvalues if math.isfinite(value) and value > 1.0e-6]
        if valid:
            return min(valid) ** 0.5
        attempts.append(f"{args}: {eigenvalues}")
    raise RuntimeError(f"eigenvalue solver returned no valid natural frequency: {attempts}")


class ResponseTracker:
    def __init__(self, built: BuiltModel):
        self.built = built
        topology = built.topology
        self.nx, self.ny = topology.n_nodes_x, topology.n_nodes_y
        self.floors = topology.floor_count
        self.story_height = topology.story_height_m
        self.free_tags = [tag for tag in built.node_coords if tag not in set(built.base_node_tags)]
        self.level_tags = {
            level: [[built.node_tags[(level, row, col)] for col in range(self.nx)] for row in range(self.ny)]
            for level in range(topology.n_levels)
        }
        self.peak_stress: Dict[int, float] = {}
        self.peak_compression: Dict[int, float] = {}
        self.peak_strain: Dict[int, float] = {}
        self.peak_deformation: Dict[int, float] = {}
        self.peak_drift = {axis: {s: 0.0 for s in range(1, self.floors + 1)} for axis in "xy"}
        self.end_drift_peaks = {axis: {s: [0.0, 0.0] for s in range(1, self.floors + 1)} for axis in "xy"}
        self.peak_roof = {"x": 0.0, "y": 0.0}
        inv_node_tags = {tag: key for key, tag in built.node_tags.items()}
        self.frame_node_keys = [list(inv_node_tags[tag]) for tag in self.free_tags]
        self.frames: List[List[float]] = []
        self.latest_frame: List[float] = []
        self.steps_done = 0
        self.node_keys_by_tag = inv_node_tags
        self.ruptures: List[dict] = []

    def update(self) -> dict:
        disp = {}
        for tag in self.free_tags:
            disp[tag] = (ops.nodeDisp(tag, 1), ops.nodeDisp(tag, 2))
        for tag in self.built.base_node_tags:
            disp[tag] = (0.0, 0.0)
        self.steps_done += 1
        if self.steps_done % FRAME_EVERY_STEPS == 0:
            self.latest_frame = [round(value, 5) for tag in self.free_tags for value in disp[tag]]
            self.frames.append(self.latest_frame)

        step_max_drift = 0.0
        step_max_idr = 0.0
        roof_x = roof_y = 0.0
        h = self.story_height
        for story in range(1, self.floors + 1):
            upper = self.level_tags[story]
            lower = self.level_tags[story - 1]
            drift_x = [[disp[upper[r][c]][0] - disp[lower[r][c]][0] for c in range(self.nx)] for r in range(self.ny)]
            drift_y = [[disp[upper[r][c]][1] - disp[lower[r][c]][1] for c in range(self.nx)] for r in range(self.ny)]
            max_x = max(abs(v) for row in drift_x for v in row)
            max_y = max(abs(v) for row in drift_y for v in row)
            step_max_drift = max(step_max_drift, max_x, max_y)
            step_max_idr = max(step_max_idr, max_x / h, max_y / h)
            self.peak_drift["x"][story] = max(self.peak_drift["x"][story], max_x)
            self.peak_drift["y"][story] = max(self.peak_drift["y"][story], max_y)
            ends_x = (abs(sum(drift_x[0]) / self.nx), abs(sum(drift_x[self.ny - 1]) / self.nx))
            ends_y = (abs(sum(drift_y[r][0] for r in range(self.ny)) / self.ny),
                      abs(sum(drift_y[r][self.nx - 1] for r in range(self.ny)) / self.ny))
            for axis, ends in (("x", ends_x), ("y", ends_y)):
                peaks = self.end_drift_peaks[axis][story]
                peaks[0] = max(peaks[0], ends[0])
                peaks[1] = max(peaks[1], ends[1])
            if story == self.floors:
                roof_x = max(abs(disp[t][0]) for row in upper for t in row)
                roof_y = max(abs(disp[t][1]) for row in upper for t in row)
        self.peak_roof["x"] = max(self.peak_roof["x"], roof_x)
        self.peak_roof["y"] = max(self.peak_roof["y"], roof_y)

        step_stress = 0.0
        step_deformation = 0.0
        for tag, info in self.built.elements.items():
            section = info.section
            if info.kind == "brace":
                axial = (ops.basicForce(tag) or [0.0])[0]
                elongation = (ops.basicDeformation(tag) or [0.0])[0]
                stress = abs(axial) / section.A_m2 / 1000.0
                compression = max(0.0, -axial) / section.A_m2 / 1000.0
                strain = abs(elongation) / info.length_m
            else:
                force = ops.eleResponse(tag, "localForce") or []
                if len(force) < 12:
                    continue
                axial = max(abs(force[0]), abs(force[6]))
                moment_strong = max(abs(force[4]), abs(force[10]))
                moment_weak = max(abs(force[5]), abs(force[11]))
                stress = (axial / section.A_m2 + moment_strong / section.Sx_m3 + moment_weak / section.Sy_m3) / 1000.0
                compression = max(0.0, force[0]) / section.A_m2 / 1000.0
                strain = 0.0
                if self.built.nonlinear:
                    for point in (1, INTEGRATION_POINTS):
                        deformation = ops.eleResponse(tag, "section", point, "deformation") or []
                        if len(deformation) >= 3:
                            strain = max(strain, abs(deformation[0])
                                         + abs(deformation[2]) * section.d_m / 2.0
                                         + abs(deformation[1]) * section.bf_m / 2.0)
            di, dj = disp[info.i_tag], disp[info.j_tag]
            relative = ((dj[0] - di[0]) ** 2 + (dj[1] - di[1]) ** 2) ** 0.5
            if stress > self.peak_stress.get(tag, 0.0):
                self.peak_stress[tag] = stress
            if compression > self.peak_compression.get(tag, 0.0):
                self.peak_compression[tag] = compression
            if strain > self.built.material.rupture_strain >= self.peak_strain.get(tag, 0.0):
                self.ruptures.append({
                    "time_s": round(ops.getTime(), 3),
                    "nodes": [list(self.node_keys_by_tag[info.i_tag]), list(self.node_keys_by_tag[info.j_tag])],
                })
            if strain > self.peak_strain.get(tag, 0.0):
                self.peak_strain[tag] = strain
            if relative > self.peak_deformation.get(tag, 0.0):
                self.peak_deformation[tag] = relative
            step_stress = max(step_stress, stress)
            step_deformation = max(step_deformation, relative)

        return {
            "stress_mpa": step_stress,
            "displacement_m": roof_x,
            "displacement_y_m": roof_y,
            "deformation_m": step_deformation,
            "idr": step_max_idr,
            "drift_m": step_max_drift,
        }


def _elastic_member_stress(built: BuiltModel) -> Dict[int, float]:
    stresses: Dict[int, float] = {}
    for tag, info in built.elements.items():
        section = info.section
        if info.kind == "brace":
            axial = (ops.basicForce(tag) or [0.0])[0]
            stresses[tag] = abs(axial) / section.A_m2 / 1000.0
            continue
        force = ops.eleResponse(tag, "localForce") or []
        if len(force) < 12:
            continue
        axial = max(abs(force[0]), abs(force[6]))
        moment_strong = max(abs(force[4]), abs(force[10]))
        moment_weak = max(abs(force[5]), abs(force[11]))
        stresses[tag] = (axial / section.A_m2 + moment_strong / section.Sx_m3 + moment_weak / section.Sy_m3) / 1000.0
    return stresses


def elastic_gravity_evaluation(topology: BuildingTopology, model_state: Optional[dict] = None) -> dict:
    built = build_model(topology, model_state=model_state, nonlinear=False)
    ops.system("UmfPack")
    ops.numberer("RCM")
    ops.constraints("Plain")
    ops.integrator("LoadControl", 1.0)
    ops.algorithm("Linear")
    ops.analysis("Static")
    if ops.analyze(1) != 0:
        raise RuntimeError("Linear-elastic gravity analysis failed")
    return evaluate_gravity_fallback(built, _elastic_member_stress(built))


def run_nltha(
    topology: BuildingTopology,
    acceleration_x_g: Sequence[float],
    acceleration_y_g: Sequence[float],
    dt: float,
    model_state: Optional[dict] = None,
    damping_ratio: float = 0.05,
    progress=None,
) -> dict:
    if not acceleration_x_g or not acceleration_y_g or dt <= 0:
        raise ValueError("Non-empty X and Y motions and a positive time step are required")
    if len(acceleration_x_g) != len(acceleration_y_g):
        raise ValueError("X and Y ground motions must have the same number of steps")

    story_stiffness = elastic_story_stiffness(topology, model_state)
    built = build_model(topology, model_state=model_state, nonlinear=True)
    validation = validate_model(built)
    if not validation.ok:
        raise RuntimeError(validation.report())

    def failed_record(phase: str, period: Optional[float], evaluation: Optional[dict]) -> dict:
        record = build_run_record(
            building_id=topology.building_id, time_step_s=dt, steps=0,
            peak_stress_mpa=None, peak_displacement_m=None, peak_displacement_y_m=None,
            peak_deformation_m=None, maximum_idr=None, maximum_story_drift_m=None,
            fundamental_period_s=period,
            drift_limit=None if period is None else drift_limit_for_period(period),
            topology_valid=validation.ok, converged=False,
            collapse_phase=phase, collapse_time_s=0.0, evaluation=evaluation,
            structure_survives=False, model_state=_model_state_summary(built),
        )
        record["history"] = []
        return record

    try:
        _apply_gravity_and_masses(built)
    except RuntimeError:
        return failed_record("gravity", None, elastic_gravity_evaluation(topology, model_state))

    omega = _fundamental_omega()
    period = 2.0 * math.pi / omega

    ops.timeSeries("Path", SEISMIC_TS_TAG_X, "-dt", dt,
                   "-values", *[float(value) * GRAVITY for value in acceleration_x_g])
    ops.pattern("UniformExcitation", SEISMIC_PATTERN_TAG_X, 1, "-accel", SEISMIC_TS_TAG_X)
    ops.timeSeries("Path", SEISMIC_TS_TAG_Y, "-dt", dt,
                   "-values", *[float(value) * GRAVITY for value in acceleration_y_g])
    ops.pattern("UniformExcitation", SEISMIC_PATTERN_TAG_Y, 2, "-accel", SEISMIC_TS_TAG_Y)
    ops.rayleigh(2.0 * damping_ratio * omega, 0.0, 0.0, 0.0)
    ops.wipeAnalysis()
    ops.constraints("Transformation")
    ops.numberer("RCM")
    ops.system("UmfPack")
    ops.test("NormDispIncr", 1.0e-7, 20, 0)
    ops.algorithm("Newton")
    ops.integrator("Newmark", 0.5, 0.25)
    ops.analysis("Transient")

    tracker = ResponseTracker(built)
    history = []
    peak_drift = peak_idr = peak_stress = peak_deformation = 0.0
    converged = True
    collapse_time_s = None
    total_steps = len(acceleration_x_g)
    if progress is not None:
        progress(0, total_steps, None, tracker.frame_node_keys, [])
    for index in range(total_steps):
        if ops.analyze(1, dt) != 0:
            converged = False
            collapse_time_s = ops.getTime()
            break
        step = tracker.update()
        if progress is not None and tracker.steps_done % FRAME_EVERY_STEPS == 0:
            progress(tracker.steps_done, total_steps, tracker.latest_frame, None, tracker.ruptures)
        peak_drift = max(peak_drift, step.pop("drift_m"))
        peak_idr = max(peak_idr, step["idr"])
        peak_stress = max(peak_stress, step["stress_mpa"])
        peak_deformation = max(peak_deformation, step["deformation_m"])
        history.append({"time_s": ops.getTime(), **step})

    evaluation = None
    structure_survives = False
    if history:
        evaluation = evaluate_performance(built, tracker, period, story_stiffness)
        structure_survives = converged and evaluation["pass"]

    record = build_run_record(
        building_id=topology.building_id, time_step_s=dt, steps=len(history),
        peak_stress_mpa=peak_stress, peak_displacement_m=tracker.peak_roof["x"],
        peak_displacement_y_m=tracker.peak_roof["y"], peak_deformation_m=peak_deformation,
        maximum_idr=peak_idr, maximum_story_drift_m=peak_drift,
        fundamental_period_s=period, drift_limit=drift_limit_for_period(period),
        topology_valid=validation.ok, converged=converged,
        collapse_phase=None if converged else "seismic", collapse_time_s=collapse_time_s,
        evaluation=evaluation, structure_survives=structure_survives,
        model_state=_model_state_summary(built),
    )
    record["history"] = history
    record["frames"] = {
        "dt_s": dt * FRAME_EVERY_STEPS,
        "node_keys": tracker.frame_node_keys,
        "frames": tracker.frames,
        "ruptures": tracker.ruptures,
        "collapse_time_s": None if collapse_time_s is None else round(collapse_time_s, 3),
    }
    return record


def _model_state_summary(built: BuiltModel) -> dict:
    grid = built.grid
    return {
        "member_sections": dict(grid.member_sections),
        "braces": [vars(b) for b in grid.braces],
        "struts": [vars(s) for s in grid.struts],
    }
