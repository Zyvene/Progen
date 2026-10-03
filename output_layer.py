import csv
import json
import os
import shutil
import time
from pathlib import Path
from typing import List, Optional

HISTORY_CSV_FIELDNAMES = [
    "time_s", "stress_mpa", "displacement_m", "displacement_y_m", "deformation_m", "idr",
]


def serialize_result(result: dict) -> str:
    return json.dumps(result, indent=2)


def write_result_json(result: dict, path: Path) -> None:
    path.write_text(serialize_result(result) + "\n")


def write_history_csv(history: List[dict], path: Path) -> None:
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=HISTORY_CSV_FIELDNAMES)
        writer.writeheader()
        writer.writerows(history)


def _replace_with_retry(source: Path, target: Path, attempts: int = 40, delay_s: float = 0.05) -> None:
    for attempt in range(attempts):
        try:
            os.replace(source, target)
            return
        except PermissionError:
            if attempt == attempts - 1:
                raise
            time.sleep(delay_s)


def write_json_atomic(data: dict, path: Path) -> None:
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(data, indent=2) + "\n")
    _replace_with_retry(temp, path)


def write_iteration(run_dir: Path, iteration: int, record: dict, history: List[dict],
                    frames: Optional[dict] = None) -> Path:
    final_dir = run_dir / f"iteration_{iteration}"
    temp_dir = run_dir / f".iteration_{iteration}.tmp"
    if temp_dir.exists():
        shutil.rmtree(temp_dir)
    temp_dir.mkdir(parents=True)
    write_result_json(record, temp_dir / "record.json")
    write_history_csv(history, temp_dir / "history.csv")
    if frames is not None:
        (temp_dir / "frames.json").write_text(json.dumps(frames, separators=(",", ":")))
    if final_dir.exists():
        shutil.rmtree(final_dir)
    _replace_with_retry(temp_dir, final_dir)
    return final_dir
