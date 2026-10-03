from __future__ import annotations

import traceback
from pathlib import Path
from typing import Optional, Sequence

import output_layer
from feedback_engine import apply_feedback
from input_management import BuildingTopology
from seismic_simulation import run_nltha

MAX_FEEDBACK_ITERATIONS = 10


def run_pipeline(
    topology: BuildingTopology,
    model_state: Optional[dict],
    motion_x: Sequence[float],
    motion_y: Sequence[float],
    dt: float,
    run_dir: Path,
    inputs: dict,
    run_metadata: Optional[dict] = None,
) -> dict:
    run_dir.mkdir(parents=True, exist_ok=True)
    summary = {
        "status": "running",
        **(run_metadata or {}),
        "inputs": inputs,
        "max_feedback_iterations": MAX_FEEDBACK_ITERATIONS,
        "iterations_completed": 0,
        "iterations": [],
        "stop_reason": None,
        "final_status": None,
    }
    output_layer.write_json_atomic(summary, run_dir / "run_summary.json")

    def report(iteration: int, phase: str, step: int = 0, total: int = 0, frame=None, ruptures=None) -> None:
        payload = {"iteration": iteration, "phase": phase, "step": step, "total_steps": total}
        if frame:
            payload["time_s"] = round(step * dt, 3)
            payload["frame"] = frame
            payload["ruptures"] = ruptures or []
        try:
            output_layer.write_json_atomic(payload, run_dir / "progress.json")
        except OSError:
            pass

    def announce(iteration: int, node_keys) -> None:
        live = {
            "iteration": iteration,
            "model_state": state or {},
            "highlighted": [] if applied is None else [a["target"] for a in applied["actions"]],
            "node_keys": node_keys,
        }
        try:
            output_layer.write_json_atomic(live, run_dir / "live_state.json")
        except OSError:
            pass

    def live_progress(iteration: int, step: int, total: int, frame, node_keys, ruptures) -> None:
        if node_keys is not None:
            announce(iteration, node_keys)
        report(iteration, "simulating", step, total, frame, ruptures)

    state = model_state
    applied = None
    try:
        for iteration in range(MAX_FEEDBACK_ITERATIONS + 1):
            report(iteration, "simulating")
            record = run_nltha(
                topology, motion_x, motion_y, dt, model_state=state,
                progress=lambda step, total, frame, keys, ruptures, n=iteration: live_progress(n, step, total, frame, keys, ruptures),
            )
            history = record.pop("history")
            frames = record.pop("frames", None)
            record["iteration"] = iteration
            record["applied_feedback"] = applied
            record.update(inputs)
            output_layer.write_iteration(run_dir, iteration, record, history, frames)

            summary["iterations_completed"] = iteration + 1
            summary["iterations"].append({
                "iteration": iteration,
                "overall_status": record["overall_status"],
                "collapse_phase": record["collapse_phase"],
                "triggered_rules": [entry["rule"] for entry in (record["evaluation"] or {}).get("triggered_rules", [])],
                "actions_applied": 0 if applied is None else len(applied["actions"]),
            })
            summary["final_status"] = record["overall_status"]
            output_layer.write_json_atomic(summary, run_dir / "run_summary.json")

            if record["structure_survives"]:
                summary["stop_reason"] = "all evaluation checks pass"
                break
            if iteration == MAX_FEEDBACK_ITERATIONS:
                summary["stop_reason"] = f"feedback iteration limit reached ({MAX_FEEDBACK_ITERATIONS})"
                break
            if not record["evaluation"]:
                summary["stop_reason"] = "no evaluation available to drive feedback"
                break

            report(iteration, "feedback")
            seismic_collapse = record["collapse_phase"] == "seismic"
            feedback = apply_feedback(topology, state, record["evaluation"], seismic_collapse)
            if not feedback["changed"]:
                summary["stop_reason"] = "no further improvement possible"
                break
            applied = {
                "from_iteration": iteration,
                "actions": feedback["actions"],
                "changed_members": feedback["changed_members"],
                "section_limit_reached": feedback["section_limit_reached"],
                "sizing_mode": feedback["sizing_mode"],
            }
            state = feedback["model_state"]
        summary["status"] = "completed"
    except Exception as error:
        summary["status"] = "error"
        summary["error"] = f"{type(error).__name__}: {error}"
        summary["traceback"] = traceback.format_exc()
    report(summary["iterations_completed"] - 1, "done")
    output_layer.write_json_atomic(summary, run_dir / "run_summary.json")
    return summary
