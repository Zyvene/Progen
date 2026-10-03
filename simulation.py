from __future__ import annotations

import argparse
import json
from pathlib import Path

from input_management import BuildingTopology
from seismic_simulation import (
    MOTION_SEED_X, MOTION_SEED_Y, magnitude_to_amplitude_g, read_motion_csv, run_nltha,
    stochastic_motion,
)
import output_layer
from data_management import resolve_previous_runs, run_key, tool_fingerprint
from pipeline import run_pipeline

MODEL_STATE_KEYS = ("member_sections", "braces", "struts")


def _load_topology_json(path: Path):
    values = json.loads(path.read_text())
    model_state = {key: values[key] for key in MODEL_STATE_KEYS if key in values}
    return BuildingTopology.from_dict(values), model_state


def main() -> None:
    parser = argparse.ArgumentParser(description="Run OpenSeesPy NLTHA on one building")
    parser.add_argument("--topology", type=Path, help="JSON file following SCHEMA.md")
    parser.add_argument("--motion", type=Path, help="CSV with time,acceleration_g (applied to both X and Y)")
    parser.add_argument("--dt", type=float, default=0.01)
    parser.add_argument("--duration", type=float, default=15.0,
                        help="Strong-shaking duration D5-95 in seconds; ignored when --motion is given")
    parser.add_argument("--magnitude", type=float, default=5.0,
                         help="Seismic magnitude, 1-10; ignored when --motion is given")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--history", type=Path, help="CSV file for every NLTHA time step")
    parser.add_argument("--run-dir", type=Path,
                        help="Run the closed-loop pipeline and save each iteration in this folder")
    args = parser.parse_args()
    if args.run_dir and not args.topology and (args.run_dir / "input.json").exists():
        args.topology = args.run_dir / "input.json"
    if args.topology:
        topology, model_state = _load_topology_json(args.topology)
    else:
        topology, model_state = BuildingTopology(
            building_id=9001, floor_count=2, story_height=12, bay_count_x=1,
            bay_width_x=20, bay_count_y=1, bay_width_y=20,
        ), {}

    run_metadata = {}
    if args.run_dir and not args.motion:
        values = json.loads(args.topology.read_text()) if args.topology else topology.as_dict()
        key = run_key(values, args.magnitude, args.duration)
        fingerprint = tool_fingerprint()
        previous = resolve_previous_runs(args.run_dir.parent, args.run_dir, key, fingerprint)
        if previous["reuse"] is not None:
            args.run_dir.mkdir(parents=True, exist_ok=True)
            output_layer.write_json_atomic(
                {"reuse_run": str(previous["reuse"]), "run_key": key, "tool_fingerprint": fingerprint,
                 "replaced_runs": previous["replaced"]},
                args.run_dir / "reuse.json",
            )
            print(f"reusing {previous['reuse']}")
            return
        run_metadata = {"run_key": key, "tool_fingerprint": fingerprint, "replaced_runs": previous["replaced"]}

    if args.motion:
        dt, motion_x = read_motion_csv(args.motion)
        motion_y = motion_x
    else:
        dt = args.dt
        motion_x = stochastic_motion(dt, args.duration, args.magnitude, MOTION_SEED_X)
        motion_y = stochastic_motion(dt, args.duration, args.magnitude, MOTION_SEED_Y)

    if args.run_dir:
        inputs = {"source_motion": str(args.motion) if args.motion else "stochastic"}
        if not args.motion:
            inputs.update({
                "input_magnitude": args.magnitude,
                "input_duration_s": args.duration,
                "input_pga_g": round(magnitude_to_amplitude_g(args.magnitude), 5),
                "record_length_s": round((len(motion_x) - 1) * dt, 3),
            })
        summary = run_pipeline(topology, model_state, motion_x, motion_y, dt, args.run_dir, inputs, run_metadata)
        print(output_layer.serialize_result({k: v for k, v in summary.items() if k != "traceback"}))
        return

    result = run_nltha(topology, motion_x, motion_y, dt, model_state=model_state)
    history = result.pop("history")
    result.pop("frames", None)
    if not args.motion:
        result["input_magnitude"] = args.magnitude
        result["input_duration_s"] = args.duration
        result["input_pga_g"] = round(magnitude_to_amplitude_g(args.magnitude), 5)
        result["record_length_s"] = round((len(motion_x) - 1) * dt, 3)

    serialized = output_layer.serialize_result(result)
    print(serialized)
    if args.output:
        output_layer.write_result_json(result, args.output)
    if args.history:
        output_layer.write_history_csv(history, args.history)


if __name__ == "__main__":
    main()
