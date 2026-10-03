from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from input_management import STARTING_SECTION, BuildingTopology, w_section_lookup

NodeKey = Tuple[int, int, int]
MidNodeKey = Tuple[str, int, int, int]

AXES = ("x", "y")


def member_id(i_key: NodeKey, j_key: NodeKey) -> str:
    return "%d,%d,%d|%d,%d,%d" % (*i_key, *j_key)


@dataclass(frozen=True)
class Brace:
    story: int
    axis: str
    line: int
    bay: int
    section: str = STARTING_SECTION

    def diagonals(self) -> List[Tuple[NodeKey, NodeKey]]:
        s, line, bay = self.story, self.line, self.bay
        if self.axis == "x":
            return [((s - 1, line, bay), (s, line, bay + 1)), ((s - 1, line, bay + 1), (s, line, bay))]
        return [((s - 1, bay, line), (s, bay + 1, line)), ((s - 1, bay + 1, line), (s, bay, line))]


@dataclass(frozen=True)
class Strut:
    story: int
    axis: str
    line: int
    bay: int
    section: str = STARTING_SECTION

    def column_grid_keys(self) -> Tuple[Tuple[int, int], Tuple[int, int]]:
        if self.axis == "x":
            return (self.line, self.bay), (self.line, self.bay + 1)
        return (self.bay, self.line), (self.bay + 1, self.line)

    def mid_node_keys(self) -> Tuple[MidNodeKey, MidNodeKey]:
        (ra, ca), (rb, cb) = self.column_grid_keys()
        return ("mid", self.story, ra, ca), ("mid", self.story, rb, cb)


@dataclass
class TopologyGrid:
    topology: BuildingTopology
    node_coords_m: Dict[NodeKey, Tuple[float, float, float]]
    column_pairs: List[Tuple[NodeKey, NodeKey]]
    beam_pairs: List[Tuple[NodeKey, NodeKey]]
    base_keys: List[NodeKey]
    member_sections: Dict[str, str] = field(default_factory=dict)
    braces: List[Brace] = field(default_factory=list)
    struts: List[Strut] = field(default_factory=list)
    mid_node_coords_m: Dict[MidNodeKey, Tuple[float, float, float]] = field(default_factory=dict)


def _check_frame_member(topology: BuildingTopology, item, kind: str) -> None:
    if item.axis not in AXES:
        raise ValueError(f"{kind} axis must be 'x' or 'y', got {item.axis!r}")
    if not 1 <= item.story <= topology.floor_count:
        raise ValueError(f"{kind} story {item.story} outside 1-{topology.floor_count}")
    lines = topology.n_nodes_y if item.axis == "x" else topology.n_nodes_x
    bays = topology.bay_count_x if item.axis == "x" else topology.bay_count_y
    if not 0 <= item.line < lines:
        raise ValueError(f"{kind} line {item.line} outside 0-{lines - 1}")
    if not 0 <= item.bay < bays:
        raise ValueError(f"{kind} bay {item.bay} outside 0-{bays - 1}")
    if item.section not in w_section_lookup():
        raise ValueError(f"{kind} section {item.section!r} is not in w_sections.json")


def generate_topology_grid(
    topology: BuildingTopology, model_state: Optional[dict] = None
) -> TopologyGrid:
    model_state = model_state or {}
    nx, ny = topology.n_nodes_x, topology.n_nodes_y
    sh = topology.story_height_m
    bx = topology.bay_width_x_m
    by = topology.bay_width_y_m

    node_coords_m: Dict[NodeKey, Tuple[float, float, float]] = {}
    base_keys: List[NodeKey] = []
    for level in range(topology.n_levels):
        z = level * sh
        for row in range(ny):
            y = row * by
            for col in range(nx):
                x = col * bx
                key = (level, row, col)
                node_coords_m[key] = (x, y, z)
                if level == 0:
                    base_keys.append(key)

    column_pairs: List[Tuple[NodeKey, NodeKey]] = []
    for level in range(topology.floor_count):
        for row in range(ny):
            for col in range(nx):
                column_pairs.append(((level, row, col), (level + 1, row, col)))

    beam_pairs: List[Tuple[NodeKey, NodeKey]] = []
    for level in range(1, topology.n_levels):
        for row in range(ny):
            for col in range(nx - 1):
                beam_pairs.append(((level, row, col), (level, row, col + 1)))
        for col in range(nx):
            for row in range(ny - 1):
                beam_pairs.append(((level, row, col), (level, row + 1, col)))

    sections = w_section_lookup()
    requested = model_state.get("member_sections", {})
    member_sections: Dict[str, str] = {}
    for i_key, j_key in column_pairs + beam_pairs:
        mid = member_id(i_key, j_key)
        name = requested.get(mid, STARTING_SECTION)
        if name not in sections:
            raise ValueError(f"member {mid} section {name!r} is not in w_sections.json")
        member_sections[mid] = name
    unknown = set(requested) - set(member_sections)
    if unknown:
        raise ValueError(f"member_sections refers to unknown members: {sorted(unknown)[:5]}")

    braces = [Brace(**entry) for entry in model_state.get("braces", [])]
    struts = [Strut(**entry) for entry in model_state.get("struts", [])]
    for brace in braces:
        _check_frame_member(topology, brace, "brace")
    for strut in struts:
        _check_frame_member(topology, strut, "strut")

    mid_node_coords_m: Dict[MidNodeKey, Tuple[float, float, float]] = {}
    for strut in struts:
        for key in strut.mid_node_keys():
            _, story, row, col = key
            x, y, _ = node_coords_m[(0, row, col)]
            mid_node_coords_m[key] = (x, y, (story - 0.5) * sh)

    return TopologyGrid(
        topology=topology,
        node_coords_m=node_coords_m,
        column_pairs=column_pairs,
        beam_pairs=beam_pairs,
        base_keys=base_keys,
        member_sections=member_sections,
        braces=braces,
        struts=struts,
        mid_node_coords_m=mid_node_coords_m,
    )
