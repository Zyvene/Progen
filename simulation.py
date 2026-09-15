"""Nonlinear time-history analysis and response metrics.

Units are kN, m, seconds.  Ground acceleration input is in g unless a
caller passes acceleration in m/s^2 directly to ``run_nltha``.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

import openseespy.opensees as ops

from model_builder import build_model
from schema import BuildingTopology
from validation import validate_model

GRAVITY = 9.80665
SEISMIC_PATTERN_TAG = 2
SEISMIC_TS_TAG = 2


def synthetic_motion(dt: float, duration: float, amplitude_g: float = 0.15) -> List[float]:
    """Return a tapered, deterministic motion for a solver smoke test."""
    import math

    values = []
    for index in range(round(duration / dt) + 1):
        time = index * dt
        envelope = min(1.0, time / 1.0) * min(1.0, (duration - time) / 1.0)
        envelope = max(0.0, envelope)
        values.append(
            amplitude_g * envelope * (
                math.sin(2.0 * math.pi * 1.0 * time)
                + 0.35 * math.sin(2.0 * math.pi * 2.7 * time)
            )
        )
    return values


def read_motion_csv(path: Path) -> Tuple[float, List[float]]:
    """Read ``time,acceleration_g`` or a one-column acceleration CSV."""
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


def _apply_gravity_and_masses(built) -> None:
    topology = built.topology
    floor_area = topology.footprint_area_m2
    ops.system("UmfPack")
    ops.numberer("RCM")
    ops.constraints("Plain")
    ops.integrator("LoadControl", 0.1)
    ops.algorithm("Newton")
    ops.analysis("Static")
    if ops.analyze(10) != 0:
        raise RuntimeError("Gravity analysis failed before seismic loading")
    ops.loadConst("-time", 0.0)

    # Lump each floor's gravity load equally into its dynamic nodes.
    for level in range(1, topology.n_levels):
        load_kN = (topology.roof_load_kpa if level == topology.floor_count
                   else topology.floor_load_kpa) * floor_area
        mass = load_kN / GRAVITY / (topology.n_nodes_x * topology.n_nodes_y)
        for row in range(topology.n_nodes_y):
            for col in range(topology.n_nodes_x):
                ops.mass(built.node_tags[(level, row, col)], mass, mass, mass, 0, 0, 0)


def _story_and_roof_response(built) -> Tuple[float, float, float]:
    topology = built.topology
    max_roof = 0.0
    max_drift = 0.0
    max_idr = 0.0
    for row in range(topology.n_nodes_y):
        for col in range(topology.n_nodes_x):
            roof_tag = built.node_tags[(topology.floor_count, row, col)]
            max_roof = max(max_roof, abs(ops.nodeDisp(roof_tag, 1)))
            for level in range(1, topology.floor_count + 1):
                current = built.node_tags[(level, row, col)]
                below = built.node_tags[(level - 1, row, col)]
                drift = abs(ops.nodeDisp(current, 1) - ops.nodeDisp(below, 1))
                max_drift = max(max_drift, drift)
                max_idr = max(max_idr, drift / topology.story_height_m)
    return max_roof, max_drift, max_idr


def _peak_member_stress_and_deformation(built) -> Tuple[float, float]:
    peak_stress_mpa = 0.0
    peak_deformation_m = 0.0
    section = built.section
    extreme_fiber = (section.Iz_m4 * 12.0) ** 0.25 / 2.0
    for element_tag, i_tag, j_tag in built.column_elements + built.beam_elements:
        force = ops.eleResponse(element_tag, "localForce") or []
        if len(force) >= 6:
            axial = max(abs(force[0]), abs(force[6]) if len(force) > 6 else 0.0)
            moment_y = max(abs(force[4]), abs(force[10]) if len(force) > 10 else 0.0)
            moment_z = max(abs(force[5]), abs(force[11]) if len(force) > 11 else 0.0)
            stress_kpa = axial / section.A_m2
            stress_kpa += moment_y * extreme_fiber / section.Iy_m4
            stress_kpa += moment_z * extreme_fiber / section.Iz_m4
            peak_stress_mpa = max(peak_stress_mpa, stress_kpa / 1000.0)
        # Report chord deformation in the excitation direction. Including
        # unconstrained transverse translations in this scalar would mix
        # different response components and can exaggerate the result.
        relative_x = abs(ops.nodeDisp(j_tag, 1) - ops.nodeDisp(i_tag, 1))
        peak_deformation_m = max(peak_deformation_m, relative_x)
    return peak_stress_mpa, peak_deformation_m


def run_nltha(
    topology: BuildingTopology,
    acceleration_g: Sequence[float],
    dt: float,
    damping_ratio: float = 0.05,
) -> dict:
    """Build, gravity-load, shake, and extract the requested metrics."""
    if not acceleration_g or dt <= 0:
        raise ValueError("A non-empty motion and positive time step are required")

    built = build_model(topology, nonlinear=True)
    validation = validate_model(built)
    if not validation.ok:
        raise RuntimeError(validation.report())
    _apply_gravity_and_masses(built)

    ops.timeSeries("Path", SEISMIC_TS_TAG, "-dt", dt,
                   "-values", *[float(value) * GRAVITY for value in acceleration_g])
    ops.pattern("UniformExcitation", SEISMIC_PATTERN_TAG, 1, "-accel", SEISMIC_TS_TAG)
    try:
        eigenvalue = ops.eigen(1)
        eigenvalue = eigenvalue[0] if isinstance(eigenvalue, list) else eigenvalue
        alpha_m = 2.0 * damping_ratio * float(eigenvalue) ** 0.5
    except Exception:
        alpha_m = 0.0
    ops.rayleigh(alpha_m, 0.0, 0.0, 0.0)
    ops.wipeAnalysis()
    ops.constraints("Transformation")
    ops.numberer("RCM")
    ops.system("UmfPack")
    ops.test("NormDispIncr", 1.0e-7, 20, 0)
    ops.algorithm("Newton")
    ops.integrator("Newmark", 0.5, 0.25)
    ops.analysis("Transient")

    peak_roof = 0.0
    peak_drift = 0.0
    peak_idr = 0.0
    peak_stress = 0.0
    peak_deformation = 0.0
    history = []
    for _ in acceleration_g:
        if ops.analyze(1, dt) != 0:
            raise RuntimeError(f"Transient analysis failed at t={ops.getTime():.4f} s")
        roof, drift, idr = _story_and_roof_response(built)
        stress, deformation = _peak_member_stress_and_deformation(built)
        peak_roof = max(peak_roof, roof)
        peak_drift = max(peak_drift, drift)
        peak_idr = max(peak_idr, idr)
        peak_stress = max(peak_stress, stress)
        peak_deformation = max(peak_deformation, deformation)
        history.append({
            "time_s": ops.getTime(),
            "stress_mpa": stress,
            "displacement_m": roof,
            "deformation_m": deformation,
            "idr": idr,
        })

    return {
        "building_id": topology.building_id,
        "analysis": "NLTHA",
        "time_step_s": dt,
        "steps": len(acceleration_g),
        "peak_stress_mpa": peak_stress,
        "peak_displacement_m": peak_roof,
        "peak_deformation_m": peak_deformation,
        "maximum_idr": peak_idr,
        "maximum_story_drift_m": peak_drift,
        "validation": validation.ok,
        "history": history,
    }


def _topology_from_json(path: Path) -> BuildingTopology:
    return BuildingTopology.from_dict(json.loads(path.read_text()))


def main() -> None:
    parser = argparse.ArgumentParser(description="Run OpenSeesPy NLTHA on one building")
    parser.add_argument("--topology", type=Path, help="JSON file following SCHEMA.md")
    parser.add_argument("--motion", type=Path, help="CSV with time,acceleration_g")
    parser.add_argument("--dt", type=float, default=0.01)
    parser.add_argument("--duration", type=float, default=8.0)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--history", type=Path, help="CSV file for every NLTHA time step")
    args = parser.parse_args()
    topology = _topology_from_json(args.topology) if args.topology else BuildingTopology(
        building_id=9001, floor_count=2, story_height=12, bay_count_x=1,
        bay_width_x=20, bay_count_y=1, bay_width_y=20,
    )
    if args.motion:
        dt, motion = read_motion_csv(args.motion)
    else:
        dt, motion = args.dt, synthetic_motion(args.dt, args.duration)
    result = run_nltha(topology, motion, dt)
    history = result.pop("history")
    serialized = json.dumps(result, indent=2)
    print(serialized)
    if args.output:
        args.output.write_text(serialized + "\n")
    if args.history:
        with args.history.open("w", newline="") as stream:
            writer = csv.DictWriter(
                stream,
                fieldnames=["time_s", "stress_mpa", "displacement_m", "deformation_m", "idr"],
            )
            writer.writeheader()
            writer.writerows(history)


if __name__ == "__main__":
    main()