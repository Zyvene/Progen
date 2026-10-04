from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from PIL import Image, ImageDraw

import output_layer
from input_management import BuildingTopology, w_section_lookup
from procedural_content_generation import generate_topology_grid, member_id

GIF_NAME = "simulation.gif"
GIF_VERSION = b"progen-gif 2"
GIF_WIDTH = 520
GIF_HEIGHT = 280
SUPERSAMPLE = 2
FRAME_STRIDE = 3
FRAME_DURATION_MS = 100
FINAL_HOLD_MS = 1500
END_HOLD_MS = 500
PALETTE_COLORS = 96

SHAKE_DISPLAY_FRACTION = 0.04
SHAKE_MIN_PEAK_M = 0.001
SHAKE_MAX_MAGNIFICATION = 200.0
GRAVITY_M_S2 = 9.81
TOPPLE_MIN_S = 0.6

CAMERA_FOV_DEG = 75.0
CAMERA_DIRECTION = (1.0, 0.7, 1.0)
CAMERA_DISTANCE_FACTOR = 1.2
CAMERA_MIN_DISTANCE = 6.0

BACKGROUND = (224, 242, 254)
COLUMN_COLOR = (48, 82, 140)
BEAM_COLOR = (153, 166, 184)
BRACE_COLOR = (242, 140, 26)
STRUT_COLOR = (140, 64, 191)
UPSIZED_COLOR = (219, 51, 51)

Vec = Tuple[float, float, float]


def _sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _scale(a: Vec, s: float) -> Vec:
    return (a[0] * s, a[1] * s, a[2] * s)


def _dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _length(a: Vec) -> float:
    return math.sqrt(_dot(a, a))


def _normalized(a: Vec) -> Vec:
    n = _length(a)
    return (a[0] / n, a[1] / n, a[2] / n) if n > 0.0 else a


def _slerp(a: Vec, b: Vec, t: float) -> Vec:
    cos_angle = max(-1.0, min(1.0, _dot(a, b)))
    angle = math.acos(cos_angle)
    if angle < 1e-6:
        return a
    s = math.sin(angle)
    return _normalized(_add(_scale(a, math.sin((1.0 - t) * angle) / s), _scale(b, math.sin(t * angle) / s)))


def node_id(key) -> str:
    if len(key) == 4:
        return "mid:%d,%d,%d" % (int(key[1]), int(key[2]), int(key[3]))
    return "%d,%d,%d" % (int(key[0]), int(key[1]), int(key[2]))


class Member:
    def __init__(self, kind: str, na: str, nb: str, a: Vec, b: Vec, depth_m: float, color):
        self.kind = kind
        self.na = na
        self.nb = nb
        self.a = a
        self.b = b
        self.depth_m = depth_m
        self.color = color
        self.length = _length(_sub(b, a))
        self.fall_start_time: Optional[float] = None
        self.fall_origin: Vec = (0.0, 0.0, 0.0)
        self.fall_axis_start: Vec = (0.0, 0.0, 1.0)
        self.fall_axis_end: Vec = (1.0, 0.0, 0.0)
        self.current: Tuple[Vec, Vec] = (a, b)


class Scene:
    def __init__(self, topology: BuildingTopology, model_state: dict, highlighted: List[str]):
        grid = generate_topology_grid(topology, model_state)
        sections = w_section_lookup()
        to_godot = lambda p: (p[0], p[2], p[1])
        nodes = {key: to_godot(xyz) for key, xyz in grid.node_coords_m.items()}
        highlighted_set = set(highlighted)
        self.members: List[Member] = []
        self.rest: Dict[str, Vec] = {}
        self.support: Dict[str, Tuple[str, float]] = {}

        strut_mids = set()
        for strut in grid.struts:
            for key in strut.mid_node_keys():
                strut_mids.add(node_id(key))

        for a_key, b_key in grid.column_pairs:
            mid = member_id(a_key, b_key)
            depth = sections[grid.member_sections[mid]].d_m
            color = UPSIZED_COLOR if mid in highlighted_set else COLUMN_COLOR
            split = "mid:%d,%d,%d" % b_key
            pa, pb = nodes[a_key], nodes[b_key]
            if split in strut_mids:
                middle = _scale(_add(pa, pb), 0.5)
                self._add("column", node_id(a_key), split, pa, middle, depth, color)
                self._add("column", split, node_id(b_key), middle, pb, depth, color)
            else:
                self._add("column", node_id(a_key), node_id(b_key), pa, pb, depth, color)
        for a_key, b_key in grid.beam_pairs:
            mid = member_id(a_key, b_key)
            depth = sections[grid.member_sections[mid]].d_m
            color = UPSIZED_COLOR if mid in highlighted_set else BEAM_COLOR
            self._add("beam", node_id(a_key), node_id(b_key), nodes[a_key], nodes[b_key], depth, color)
        for brace in grid.braces:
            label = "brace:%d:%s:%d:%d" % (brace.story, brace.axis, brace.line, brace.bay)
            color = UPSIZED_COLOR if label in highlighted_set else BRACE_COLOR
            depth = sections[brace.section].d_m
            for a_key, b_key in brace.diagonals():
                self._add("brace", node_id(a_key), node_id(b_key), nodes[a_key], nodes[b_key], depth, color)
        for strut in grid.struts:
            label = "strut:%d:%s:%d:%d" % (strut.story, strut.axis, strut.line, strut.bay)
            color = UPSIZED_COLOR if label in highlighted_set else STRUT_COLOR
            depth = sections[strut.section].d_m
            a_key, b_key = strut.mid_node_keys()
            (ra, ca), (rb, cb) = strut.column_grid_keys()
            pa = _scale(_add(nodes[(strut.story - 1, ra, ca)], nodes[(strut.story, ra, ca)]), 0.5)
            pb = _scale(_add(nodes[(strut.story - 1, rb, cb)], nodes[(strut.story, rb, cb)]), 0.5)
            self._add("strut", node_id(a_key), node_id(b_key), pa, pb, depth, color)
        self.order = sorted(self.rest, key=lambda nid: self.rest[nid][1])

    def _add(self, kind, na, nb, pa, pb, depth, color):
        self.members.append(Member(kind, na, nb, pa, pb, depth, color))
        self.rest[na] = pa
        self.rest[nb] = pb
        if kind == "column":
            self.support[nb] = (na, _length(_sub(pb, pa)))

    def apply_frame(self, offsets: Dict[str, Vec]) -> None:
        positions: Dict[str, Vec] = {}
        for nid in self.order:
            offset = offsets.get(nid, (0.0, 0.0, 0.0))
            moved = _add(self.rest[nid], offset)
            if nid in self.support and self.support[nid][0] in positions:
                below_id, length = self.support[nid]
                drift = _sub(offset, offsets.get(below_id, (0.0, 0.0, 0.0)))
                if _length(drift) > length:
                    drift = _scale(_normalized(drift), length)
                rise = math.sqrt(max(length * length - _dot(drift, drift), 0.0))
                moved = _add(_add(positions[below_id], drift), (0.0, rise, 0.0))
            positions[nid] = moved
        for member in self.members:
            if member.fall_start_time is None:
                member.current = (positions.get(member.na, member.a), positions.get(member.nb, member.b))

    def drop(self, node_keys, time_s: float) -> None:
        if len(node_keys) != 2:
            return
        ids = {node_id(node_keys[0]), node_id(node_keys[1])}
        for member in self.members:
            if member.fall_start_time is not None or {member.na, member.nb} != ids:
                continue
            a, b = member.current
            axis = _normalized(_sub(b, a))
            flat = (axis[0], 0.0, axis[2])
            if _length(flat) < 0.2:
                center = _scale(_add(a, b), 0.5)
                rest_center = _scale(_add(member.a, member.b), 0.5)
                lean = _sub(center, rest_center)
                flat = (lean[0], 0.0, lean[2])
                if _length(flat) < 0.001:
                    flat = (1.0, 0.0, 0.0)
            member.fall_start_time = time_s
            member.fall_origin = _scale(_add(a, b), 0.5)
            member.fall_axis_start = axis
            member.fall_axis_end = _normalized(flat)

    def update_falls(self, time_s: float) -> None:
        for member in self.members:
            if member.fall_start_time is None:
                continue
            t = max(time_s - member.fall_start_time, 0.0)
            origin = member.fall_origin
            rest = member.depth_m * 0.5
            land_s = max(math.sqrt(2.0 * max(origin[1] - rest, 0.0) / GRAVITY_M_S2), TOPPLE_MIN_S)
            axis = _slerp(member.fall_axis_start, member.fall_axis_end, min(t / land_s, 1.0))
            half_height = member.length * 0.5 * abs(axis[1])
            y = max(origin[1] - 0.5 * GRAVITY_M_S2 * t * t, rest + half_height)
            center = (origin[0], y, origin[2])
            half = _scale(axis, member.length * 0.5)
            member.current = (_sub(center, half), _add(center, half))

    def settle_time(self) -> float:
        latest = 0.0
        for member in self.members:
            if member.fall_start_time is None:
                continue
            rest = member.depth_m * 0.5
            land_s = max(math.sqrt(2.0 * max(member.fall_origin[1] - rest, 0.0) / GRAVITY_M_S2), TOPPLE_MIN_S)
            latest = max(latest, member.fall_start_time + land_s)
        return latest


class Camera:
    def __init__(self, topology: BuildingTopology, width: int, height: int):
        extents = (
            topology.bay_count_x * topology.bay_width_x_m,
            topology.floor_count * topology.story_height_m,
            topology.bay_count_y * topology.bay_width_y_m,
        )
        center = _scale(extents, 0.5)
        half_fov = math.radians(CAMERA_FOV_DEG) / 2.0
        distance = max(_length(extents) / 2.0 / math.sin(half_fov) * CAMERA_DISTANCE_FACTOR, CAMERA_MIN_DISTANCE)
        self.position = _add(center, _scale(_normalized(CAMERA_DIRECTION), distance))
        self.forward = _normalized(_sub(center, self.position))
        self.right = _normalized(_cross(self.forward, (0.0, 1.0, 0.0)))
        self.up = _cross(self.right, self.forward)
        self.focal = (height / 2.0) / math.tan(half_fov)
        self.width = width
        self.height = height

    def project(self, point: Vec) -> Tuple[float, float, float]:
        v = _sub(point, self.position)
        depth = max(_dot(v, self.forward), 1e-6)
        x = self.width / 2.0 + _dot(v, self.right) / depth * self.focal
        y = self.height / 2.0 - _dot(v, self.up) / depth * self.focal
        return x, y, depth


def _render(scene: Scene, camera: Camera, size: Tuple[int, int] = (GIF_WIDTH, GIF_HEIGHT),
            background=BACKGROUND) -> Image.Image:
    image = Image.new("RGB", (camera.width, camera.height), background)
    draw = ImageDraw.Draw(image)
    items = []
    for member in scene.members:
        a, b = member.current
        xa, ya, da = camera.project(a)
        xb, yb, db = camera.project(b)
        depth = (da + db) / 2.0
        width = max(1, int(round(member.depth_m * camera.focal / depth)))
        items.append((depth, (xa, ya, xb, yb), width, member.color))
    for _, coords, width, color in sorted(items, key=lambda item: -item[0]):
        draw.line(coords, fill=color, width=width)
    return image.resize(size, Image.LANCZOS)


def render_still(topology: BuildingTopology, model_state: dict, width: int, height: int,
                 background=(255, 255, 255)) -> Image.Image:
    scene = Scene(topology, model_state or {}, [])
    camera = Camera(topology, width * SUPERSAMPLE, height * SUPERSAMPLE)
    return _render(scene, camera, (width, height), background)


def _magnification(topology: BuildingTopology, frames: List[List[float]]) -> float:
    peak = 0.0
    for values in frames:
        for i in range(len(values) // 2):
            peak = max(peak, math.hypot(values[2 * i], values[2 * i + 1]))
    height = topology.floor_count * topology.story_height_m
    return min(max(SHAKE_DISPLAY_FRACTION * height / max(peak, SHAKE_MIN_PEAK_M), 1.0), SHAKE_MAX_MAGNIFICATION)


def _offsets(node_ids: List[str], values: List[float], magnification: float) -> Dict[str, Vec]:
    count = min(len(node_ids), len(values) // 2)
    return {node_ids[i]: (values[2 * i] * magnification, 0.0, values[2 * i + 1] * magnification) for i in range(count)}


def _highlighted(record: dict) -> List[str]:
    applied = record.get("applied_feedback")
    if not isinstance(applied, dict):
        return []
    return [str(action.get("target", "")) for action in applied.get("actions", [])]


def build_frames(topology: BuildingTopology, record: dict, frames_data: Optional[dict]) -> Tuple[List[Image.Image], List[int]]:
    scene = Scene(topology, record.get("model_state") or {}, _highlighted(record))
    camera = Camera(topology, GIF_WIDTH * SUPERSAMPLE, GIF_HEIGHT * SUPERSAMPLE)
    frames = (frames_data or {}).get("frames") or []
    if not frames:
        return [_render(scene, camera)], [FINAL_HOLD_MS]

    dt = max(float(frames_data.get("dt_s", 0.1)), 0.001)
    node_ids = [node_id(key) for key in frames_data.get("node_keys", [])]
    ruptures = sorted(frames_data.get("ruptures", []) or [], key=lambda r: float(r.get("time_s", 0.0)))
    collapsed = frames_data.get("collapse_time_s") is not None
    magnification = _magnification(topology, frames)

    picks = list(range(0, len(frames), FRAME_STRIDE))
    if picks[-1] != len(frames) - 1:
        picks.append(len(frames) - 1)
    images: List[Image.Image] = []
    durations: List[int] = []
    next_rupture = 0
    time_s = 0.0
    for index in picks:
        time_s = index * dt
        while next_rupture < len(ruptures) and float(ruptures[next_rupture].get("time_s", 0.0)) <= time_s:
            scene.drop(ruptures[next_rupture].get("nodes", []), float(ruptures[next_rupture].get("time_s", 0.0)))
            next_rupture += 1
        scene.apply_frame(_offsets(node_ids, frames[index], magnification))
        scene.update_falls(time_s)
        images.append(_render(scene, camera))
        durations.append(FRAME_DURATION_MS)

    while next_rupture < len(ruptures):
        scene.drop(ruptures[next_rupture].get("nodes", []), time_s)
        next_rupture += 1
    settle = scene.settle_time()
    step = dt * FRAME_STRIDE
    while time_s < settle:
        time_s = min(time_s + step, settle)
        scene.update_falls(time_s)
        images.append(_render(scene, camera))
        durations.append(FRAME_DURATION_MS)
    durations[-1] = FINAL_HOLD_MS if collapsed else END_HOLD_MS
    return images, durations


def _palette_swatches() -> Image.Image:
    colors = (COLUMN_COLOR, BEAM_COLOR, BRACE_COLOR, STRUT_COLOR, UPSIZED_COLOR)
    steps = 8
    swatch = Image.new("RGB", (GIF_WIDTH, GIF_HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(swatch)
    cell_w = GIF_WIDTH // steps
    cell_h = GIF_HEIGHT // len(colors)
    for row, color in enumerate(colors):
        for step in range(steps):
            t = (step + 1) / steps
            mixed = tuple(int(round(BACKGROUND[c] + (color[c] - BACKGROUND[c]) * t)) for c in range(3))
            draw.rectangle((step * cell_w, row * cell_h, (step + 1) * cell_w - 1, (row + 1) * cell_h - 1), fill=mixed)
    return swatch


def write_gif(images: List[Image.Image], durations: List[int], path: Path) -> None:
    sample = Image.new("RGB", (GIF_WIDTH, GIF_HEIGHT * 4))
    sample.paste(_palette_swatches(), (0, 0))
    for slot, index in enumerate((0, len(images) // 2, len(images) - 1)):
        sample.paste(images[index], (0, GIF_HEIGHT * (slot + 1)))
    palette = sample.quantize(colors=PALETTE_COLORS, method=Image.Quantize.MEDIANCUT)
    frames = [image.quantize(palette=palette, dither=Image.Dither.NONE) for image in images]
    temp = path.with_name(path.name + ".tmp")
    frames[0].save(
        temp, format="GIF", save_all=True, append_images=frames[1:], duration=durations,
        loop=0, optimize=False, disposal=1, comment=GIF_VERSION,
    )
    output_layer._replace_with_retry(temp, path)


def is_current(path: Path) -> bool:
    if not path.exists():
        return False
    try:
        with Image.open(path) as image:
            return image.info.get("comment") == GIF_VERSION
    except OSError:
        return False


def _read_json(path: Path) -> Optional[dict]:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def export_run(run_dir: Path, only: Optional[int] = None) -> int:
    values = _read_json(run_dir / "input.json")
    if values is None:
        print(f"no input.json in {run_dir}")
        return 1
    topology = BuildingTopology.from_dict(values)
    failures = 0
    folders = []
    for folder in run_dir.iterdir():
        match = re.fullmatch(r"iteration_(\d+)", folder.name)
        if match and folder.is_dir() and (only is None or int(match.group(1)) == only):
            folders.append((int(match.group(1)), folder))
    for number, folder in sorted(folders):
        target = folder / GIF_NAME
        if is_current(target):
            continue
        record = _read_json(folder / "record.json")
        if record is None:
            continue
        try:
            images, durations = build_frames(topology, record, _read_json(folder / "frames.json"))
            write_gif(images, durations, target)
            print(f"iteration_{number}: {len(images)} frames, {target.stat().st_size // 1024} KB")
        except Exception as error:
            failures += 1
            print(f"iteration_{number}: GIF failed: {type(error).__name__}: {error}")
    return 1 if failures else 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Export the Simulation GIF of each saved iteration in a run folder")
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--iteration", type=int)
    args = parser.parse_args()
    raise SystemExit(export_run(args.run_dir, args.iteration))


if __name__ == "__main__":
    main()
