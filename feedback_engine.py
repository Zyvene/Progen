from __future__ import annotations

import copy
import math
from typing import Dict, List, Optional, Tuple

from input_management import STARTING_SECTION, BuildingTopology, load_w_sections
from procedural_content_generation import generate_topology_grid, member_id
from performance_evaluation import TORSIONAL_IRREGULARITY_RATIO_LIMIT

SECTION_ORDER = [section.name for section in load_w_sections()]
SECTIONS = {section.name: section for section in load_w_sections()}

FrameKey = Tuple[int, str, int, int]


def _frame_key(entry: dict) -> FrameKey:
    return (int(entry["story"]), entry["axis"], int(entry["line"]), int(entry["bay"]))


def _parse_frame_label(label: str) -> FrameKey:
    _, story, axis, line, bay = label.split(":")
    return (int(story), axis, int(line), int(bay))


def select_section(current: str, requirements: Dict[str, float], one_step: bool = False) -> Optional[str]:
    index = SECTION_ORDER.index(current)
    if index + 1 >= len(SECTION_ORDER):
        return None
    if one_step:
        return SECTION_ORDER[index + 1]
    for name in SECTION_ORDER[index + 1:]:
        section = SECTIONS[name]
        if all(getattr(section, prop) >= value for prop, value in requirements.items()):
            return name
    return SECTION_ORDER[-1]


def _strength_requirements(current: str, ratio: float) -> Dict[str, float]:
    section = SECTIONS[current]
    return {"A_m2": section.A_m2 * ratio, "Sx_m3": section.Sx_m3 * ratio, "Sy_m3": section.Sy_m3 * ratio}


class _Requests:
    def __init__(self, state: dict, one_step: bool = False):
        self.state = state
        self.one_step = one_step
        self.members: Dict[str, Tuple[str, List[int]]] = {}
        self.brace_upsizes: Dict[FrameKey, Tuple[str, List[int]]] = {}
        self.strut_upsizes: Dict[FrameKey, Tuple[str, List[int]]] = {}
        self.new_braces: Dict[FrameKey, List[int]] = {}
        self.new_struts: Dict[FrameKey, List[int]] = {}
        self.limit_reached: List[dict] = []

    def _merge(self, table: dict, key, current: str, wanted: Optional[str], rule: int, ratio: float, label: str):
        if wanted is None:
            self.limit_reached.append({"rule": rule, "target": label, "section": current, "ratio": ratio})
            return
        if key in table:
            name, rules = table[key]
            if SECTION_ORDER.index(wanted) > SECTION_ORDER.index(name):
                name = wanted
            table[key] = (name, rules + [rule])
        else:
            table[key] = (wanted, [rule])

    def upsize_member(self, member: str, requirements: Dict[str, float], rule: int, ratio: float) -> None:
        current = self.state["member_sections"][member]
        wanted = select_section(current, requirements, self.one_step)
        self._merge(self.members, member, current, wanted, rule, ratio, member)

    def upsize_brace(self, key: FrameKey, ratio: float, rule: int) -> None:
        current = self.state["braces"][key]["section"]
        wanted = select_section(current, {"A_m2": SECTIONS[current].A_m2 * ratio}, self.one_step)
        self._merge(self.brace_upsizes, key, current, wanted, rule, ratio, "brace:%d:%s:%d:%d" % key)

    def upsize_strut(self, key: FrameKey, ratio: float, rule: int) -> None:
        current = self.state["struts"][key]["section"]
        wanted = select_section(current, _strength_requirements(current, ratio), self.one_step)
        self._merge(self.strut_upsizes, key, current, wanted, rule, ratio, "strut:%d:%s:%d:%d" % key)

    def brace_bay(self, key: FrameKey, ratio: float, rule: int) -> None:
        if key in self.state["braces"]:
            self.upsize_brace(key, ratio, rule)
        else:
            self.new_braces.setdefault(key, []).append(rule)

    def add_strut(self, key: FrameKey, rule: int) -> None:
        self.new_struts.setdefault(key, []).append(rule)


def _frame_bays(topology: BuildingTopology, story: int, axis: str, perimeter_only: bool) -> List[FrameKey]:
    lines = topology.n_nodes_y if axis == "x" else topology.n_nodes_x
    bays = topology.bay_count_x if axis == "x" else topology.bay_count_y
    keys = []
    for line in range(lines):
        if perimeter_only and line not in (0, lines - 1):
            continue
        for bay in range(bays):
            keys.append((story, axis, line, bay))
    return keys


def _story_columns(topology: BuildingTopology, story: int) -> List[str]:
    grid = generate_topology_grid(topology)
    return [member_id(i, j) for i, j in grid.column_pairs if j[0] == story]


def _column_group(topology: BuildingTopology, member: str) -> Optional[Tuple[int, str]]:
    lower, upper = member.split("|")
    i_key = [int(value) for value in lower.split(",")]
    j_key = [int(value) for value in upper.split(",")]
    if i_key[1:] != j_key[1:] or j_key[0] != i_key[0] + 1:
        return None
    story, row, col = j_key
    on_row_edge = row in (0, topology.bay_count_y)
    on_col_edge = col in (0, topology.bay_count_x)
    if on_row_edge and on_col_edge:
        return (story, "corner")
    if on_row_edge:
        return (story, "row_edge")
    if on_col_edge:
        return (story, "col_edge")
    return (story, "interior")


def _group_column_upsizes(topology: BuildingTopology, state: dict, req: "_Requests") -> None:
    targets: Dict[Tuple[int, str], str] = {}
    for member, (name, rules) in req.members.items():
        group = _column_group(topology, member)
        if group is None or 1 not in rules:
            continue
        if group not in targets or SECTION_ORDER.index(name) > SECTION_ORDER.index(targets[group]):
            targets[group] = name
    for member, current in state["member_sections"].items():
        group = _column_group(topology, member)
        if group in targets and SECTION_ORDER.index(targets[group]) > SECTION_ORDER.index(current):
            req._merge(req.members, member, current, targets[group], 1, 0.0, member)


def _column_grid_location(entry: dict) -> Tuple[int, int, int]:
    j_node = entry["j_node"]
    if j_node[0] == "mid":
        return (int(j_node[1]), int(j_node[2]), int(j_node[3]))
    return (int(j_node[0]), int(j_node[1]), int(j_node[2]))


def _weak_axis_strut_key(topology: BuildingTopology, state: dict, story: int, row: int, col: int) -> FrameKey:
    candidates = [bay for bay in (row - 1, row) if 0 <= bay < topology.bay_count_y]
    for bay in candidates:
        if (story, "y", col, bay) in state["braces"]:
            return (story, "y", col, bay)
    return (story, "y", col, candidates[-1])


def _column_has_y_strut(topology: BuildingTopology, state: dict, story: int, row: int, col: int) -> bool:
    for bay in (row - 1, row):
        if (story, "y", col, bay) in state["struts"]:
            return True
    return False


def _normalized_state(model_state: Optional[dict], topology: BuildingTopology) -> dict:
    grid = generate_topology_grid(topology, model_state)
    return {
        "member_sections": dict(grid.member_sections),
        "braces": {_frame_key(vars(b)): dict(vars(b)) for b in grid.braces},
        "struts": {_frame_key(vars(s)): dict(vars(s)) for s in grid.struts},
    }


def _export_state(state: dict) -> dict:
    return {
        "member_sections": dict(state["member_sections"]),
        "braces": [dict(entry) for _, entry in sorted(state["braces"].items())],
        "struts": [dict(entry) for _, entry in sorted(state["struts"].items())],
    }


def apply_feedback(topology: BuildingTopology, model_state: Optional[dict], evaluation: dict,
                   seismic_collapse: bool = False) -> dict:
    state = _normalized_state(model_state, topology)
    req = _Requests(state, one_step=seismic_collapse)
    element = evaluation.get("element_level") or {}
    floor = evaluation.get("floor_level") or {}
    structure = evaluation.get("structure_level") or {}
    triggered = {entry["rule"] for entry in evaluation.get("triggered_rules", [])}

    def upsize_element(entry: dict, ratio: float, rule: int) -> None:
        kind = entry["kind"]
        if kind in ("column", "beam"):
            member = entry["member"]
            req.upsize_member(member, _strength_requirements(state["member_sections"][member], ratio), rule, ratio)
        elif kind == "brace":
            req.upsize_brace(_parse_frame_label(entry["member"]), ratio, rule)
        elif kind == "strut":
            req.upsize_strut(_parse_frame_label(entry["member"]), ratio, rule)

    for entry in element.get("overstressed_elements", []):
        upsize_element(entry, entry["ratio"], 1)

    for entry in element.get("buckled_elements", []):
        story, row, col = _column_grid_location(entry)
        if _column_has_y_strut(topology, state, story, row, col):
            current = state["member_sections"][entry["member"]]
            requirement = {"ry_m": SECTIONS[current].ry_m * math.sqrt(entry["ratio"])}
            req.upsize_member(entry["member"], requirement, 2, entry["ratio"])
        else:
            req.add_strut(_weak_axis_strut_key(topology, state, story, row, col), 2)

    for entry in element.get("ruptured_elements", []):
        upsize_element(entry, entry["ratio"], 3)

    for entry in floor.get("exceeding_detail", []):
        for axis in ("x", "y"):
            for key in _frame_bays(topology, entry["floor"], axis, False):
                req.brace_bay(key, entry["ratio"], 4)

    for entry in floor.get("soft_story_detail", []):
        prop = "Ix_m4" if entry["axis"] == "x" else "Iy_m4"
        for member in _story_columns(topology, entry["floor"]):
            current = state["member_sections"][member]
            req.upsize_member(member, {prop: getattr(SECTIONS[current], prop) * entry["ratio"]}, 5, entry["ratio"])
        for key in _frame_bays(topology, entry["floor"], entry["axis"], False):
            req.brace_bay(key, entry["ratio"], 5)

    drift_limit = evaluation.get("drift_limit") or floor.get("idr_limit")
    idr_x = {int(k): v for k, v in (floor.get("peak_idr_x_by_floor") or {}).items()}
    idr_y = {int(k): v for k, v in (floor.get("peak_idr_y_by_floor") or {}).items()}

    for story in floor.get("mid_story_concentration_floors", []):
        ratio = max(idr_x.get(story, 0.0), idr_y.get(story, 0.0)) / drift_limit
        for axis in ("x", "y"):
            for key in _frame_bays(topology, story, axis, True):
                req.brace_bay(key, ratio, 6)

    for entry in floor.get("directional_detail", []):
        for key in _frame_bays(topology, entry["floor"], entry["weak_axis"], False):
            req.brace_bay(key, entry["ratio"], 7)

    if structure.get("roof_displacement_exceeds_limit") and idr_x:
        story_x = max(idr_x, key=idr_x.get)
        story_y = max(idr_y, key=idr_y.get)
        if idr_x[story_x] >= idr_y[story_y]:
            story, axis, idr = story_x, "x", idr_x[story_x]
        else:
            story, axis, idr = story_y, "y", idr_y[story_y]
        ratio = idr / drift_limit
        prop = "Ix_m4" if axis == "x" else "Iy_m4"
        for member in _story_columns(topology, story):
            current = state["member_sections"][member]
            req.upsize_member(member, {prop: getattr(SECTIONS[current], prop) * ratio}, 8, ratio)

    if structure.get("torsional_irregularity"):
        ratio = structure["max_torsional_irregularity_ratio"] / TORSIONAL_IRREGULARITY_RATIO_LIMIT
        for story in range(1, topology.floor_count + 1):
            for axis in ("x", "y"):
                for key in _frame_bays(topology, story, axis, True):
                    req.brace_bay(key, ratio, 9)

    if structure.get("mean_stress_exceeds_yield") and 10 in triggered:
        ratio = structure["mean_stress_mpa"] / element.get("yield_stress_mpa", 170.0)
        for member, current in state["member_sections"].items():
            req.upsize_member(member, _strength_requirements(current, ratio), 10, ratio)
        for key in list(state["braces"]):
            req.upsize_brace(key, ratio, 10)
        for key in list(state["struts"]):
            req.upsize_strut(key, ratio, 10)

    _group_column_upsizes(topology, state, req)

    new_state = copy.deepcopy(state)
    actions: List[dict] = []
    for member, (name, rules) in sorted(req.members.items()):
        before = new_state["member_sections"][member]
        if name != before:
            new_state["member_sections"][member] = name
            actions.append({"action": "upsize", "target": member, "from": before, "to": name,
                            "rules": sorted(set(rules))})
    for key, (name, rules) in sorted(req.brace_upsizes.items()):
        before = new_state["braces"][key]["section"]
        if name != before:
            new_state["braces"][key]["section"] = name
            actions.append({"action": "upsize_brace", "target": "brace:%d:%s:%d:%d" % key, "from": before,
                            "to": name, "rules": sorted(set(rules))})
    for key, (name, rules) in sorted(req.strut_upsizes.items()):
        before = new_state["struts"][key]["section"]
        if name != before:
            new_state["struts"][key]["section"] = name
            actions.append({"action": "upsize_strut", "target": "strut:%d:%s:%d:%d" % key, "from": before,
                            "to": name, "rules": sorted(set(rules))})
    for key, rules in sorted(req.new_braces.items()):
        story, axis, line, bay = key
        new_state["braces"][key] = {"story": story, "axis": axis, "line": line, "bay": bay,
                                    "section": STARTING_SECTION}
        actions.append({"action": "add_brace", "target": "brace:%d:%s:%d:%d" % key, "to": STARTING_SECTION,
                        "rules": sorted(set(rules))})
    for key, rules in sorted(req.new_struts.items()):
        if key in new_state["struts"]:
            continue
        story, axis, line, bay = key
        new_state["struts"][key] = {"story": story, "axis": axis, "line": line, "bay": bay,
                                    "section": STARTING_SECTION}
        actions.append({"action": "add_strut", "target": "strut:%d:%s:%d:%d" % key, "to": STARTING_SECTION,
                        "rules": sorted(set(rules))})

    changed_members = sorted({a["target"] for a in actions if a["action"] == "upsize"})
    return {
        "model_state": _export_state(new_state),
        "actions": actions,
        "changed_members": changed_members,
        "section_limit_reached": req.limit_reached,
        "sizing_mode": "one step (seismic collapse)" if seismic_collapse else "demand ratio",
        "changed": bool(actions),
    }
