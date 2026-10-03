import hashlib
import json
import shutil
from pathlib import Path
from typing import Optional

FINGERPRINT_FILES = (
    "w_sections.json",
    "input_management.py",
    "procedural_content_generation.py",
    "seismic_simulation.py",
    "performance_evaluation.py",
    "feedback_engine.py",
    "pipeline.py",
    "data_management.py",
    "output_layer.py",
    "validation.py",
    "simulation.py",
)
RUN_KEY_FIELDS = (
    "floor_count", "story_height", "bay_count_x", "bay_width_x", "bay_count_y", "bay_width_y",
    "floor_load_kpa", "roof_load_kpa",
)


def tool_fingerprint() -> str:
    digest = hashlib.sha256()
    root = Path(__file__).parent
    for name in FINGERPRINT_FILES:
        digest.update(name.encode())
        digest.update((root / name).read_bytes())
    return digest.hexdigest()


def _normalize(value):
    if isinstance(value, bool) or value is None:
        return value
    if isinstance(value, (int, float)):
        return round(float(value), 6)
    if isinstance(value, dict):
        return {key: _normalize(item) for key, item in sorted(value.items())}
    if isinstance(value, list):
        return [_normalize(item) for item in value]
    return value


def run_key(input_values: dict, magnitude: float, duration: float) -> str:
    units = str(input_values.get("units", "ft")).lower()
    scale = 0.3048 if units == "ft" else 1.0
    key = {}
    for field in RUN_KEY_FIELDS:
        value = input_values.get(field)
        if field in ("story_height", "bay_width_x", "bay_width_y") and value is not None:
            value = float(value) * scale
        key[field] = value
    key["magnitude"] = magnitude
    key["duration"] = duration
    key["model_state"] = {k: input_values[k] for k in ("member_sections", "braces", "struts") if k in input_values}
    return json.dumps(_normalize(key), sort_keys=True)


def _read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def resolve_previous_runs(runs_root: Path, current_run: Path, key: str, fingerprint: str) -> dict:
    reusable = None
    replaced = []
    if not runs_root.is_dir():
        return {"reuse": None, "replaced": replaced}
    for run_dir in sorted(runs_root.iterdir()):
        if not run_dir.is_dir() or not run_dir.name.startswith("run_") or run_dir.resolve() == current_run.resolve():
            continue
        summary = _read_json(run_dir / "run_summary.json") or {}
        if summary.get("run_key") is not None:
            same_inputs = summary["run_key"] == key
        else:
            values = _read_json(run_dir / "input.json")
            same_inputs = bool(values) and "magnitude" in values and "duration" in values and run_key(
                values, float(values["magnitude"]), float(values["duration"])) == key
        if not same_inputs:
            continue
        if (reusable is None and summary.get("status") == "completed"
                and summary.get("tool_fingerprint") == fingerprint):
            reusable = run_dir
            continue
        shutil.rmtree(run_dir, ignore_errors=True)
        replaced.append(run_dir.name)
    return {"reuse": reusable, "replaced": replaced}


def build_run_record(
    *,
    building_id: int,
    time_step_s: float,
    steps: int,
    peak_stress_mpa: Optional[float],
    peak_displacement_m: Optional[float],
    peak_displacement_y_m: Optional[float],
    peak_deformation_m: Optional[float],
    maximum_idr: Optional[float],
    maximum_story_drift_m: Optional[float],
    fundamental_period_s: Optional[float],
    drift_limit: Optional[float],
    topology_valid: bool,
    converged: bool,
    collapse_phase: Optional[str],
    collapse_time_s: Optional[float],
    evaluation: Optional[dict],
    structure_survives: bool,
    model_state: Optional[dict] = None,
) -> dict:
    idr_exceeds_limit = (
        None if maximum_idr is None or drift_limit is None else maximum_idr > drift_limit
    )
    return {
        "building_id": building_id,
        "analysis": "NLTHA",
        "time_step_s": time_step_s,
        "steps": steps,
        "fundamental_period_s": fundamental_period_s,
        "drift_limit": drift_limit,
        "peak_stress_mpa": peak_stress_mpa,
        "peak_displacement_m": peak_displacement_m,
        "peak_displacement_y_m": peak_displacement_y_m,
        "peak_deformation_m": peak_deformation_m,
        "maximum_idr": maximum_idr,
        "maximum_story_drift_m": maximum_story_drift_m,
        "idr_exceeds_limit": idr_exceeds_limit,
        "topology_valid": topology_valid,
        "converged": converged,
        "collapse_phase": collapse_phase,
        "collapse_time_s": collapse_time_s,
        "evaluation": evaluation,
        "structure_survives": structure_survives,
        "overall_status": "PASS" if structure_survives else "FAIL",
        "model_state": model_state,
    }
