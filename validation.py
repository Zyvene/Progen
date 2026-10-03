from dataclasses import dataclass, field
from typing import List

from input_management import BuildingTopology


@dataclass
class ValidationResult:
    building_id: int
    ok: bool
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)

    def report(self) -> str:
        lines = [f"Building {self.building_id}: {'PASS' if self.ok else 'FAIL'}"]
        for e in self.errors:
            lines.append(f"  ERROR:   {e}")
        for w in self.warnings:
            lines.append(f"  WARNING: {w}")
        return "\n".join(lines)


def validate_model(built) -> ValidationResult:
    topology: BuildingTopology = built.topology
    grid = built.grid
    errors: List[str] = []
    warnings: List[str] = []

    all_node_tags = set(built.node_tags.values())
    n_mid_nodes = len(grid.mid_node_coords_m)
    n_nodes_expected = topology.n_levels * topology.n_nodes_x * topology.n_nodes_y + n_mid_nodes
    if len(all_node_tags) != n_nodes_expected:
        errors.append(
            f"expected {n_nodes_expected} nodes, found {len(all_node_tags)}"
        )

    n_cols_expected = topology.floor_count * topology.n_nodes_x * topology.n_nodes_y + n_mid_nodes
    if len(built.column_elements) != n_cols_expected:
        errors.append(
            f"expected {n_cols_expected} column elements, "
            f"found {len(built.column_elements)}"
        )

    n_beams_per_level = (
        topology.n_nodes_y * (topology.n_nodes_x - 1)
        + topology.n_nodes_x * (topology.n_nodes_y - 1)
    )
    n_beams_expected = n_beams_per_level * topology.floor_count
    if len(built.beam_elements) != n_beams_expected:
        errors.append(
            f"expected {n_beams_expected} beam elements, "
            f"found {len(built.beam_elements)}"
        )

    if len(built.brace_elements) != 2 * len(grid.braces):
        errors.append(
            f"expected {2 * len(grid.braces)} brace elements, found {len(built.brace_elements)}"
        )
    if len(built.strut_elements) != len(grid.struts):
        errors.append(
            f"expected {len(grid.struts)} strut elements, found {len(built.strut_elements)}"
        )

    expected_base_nodes = topology.n_nodes_x * topology.n_nodes_y
    if len(built.base_node_tags) != expected_base_nodes:
        errors.append(
            f"expected {expected_base_nodes} fixed base nodes, "
            f"found {len(built.base_node_tags)}"
        )

    all_elements = (
        built.column_elements + built.beam_elements + built.brace_elements + built.strut_elements
    )
    adjacency = {tag: set() for tag in all_node_tags}
    for _ele_tag, i_tag, j_tag in all_elements:
        adjacency.setdefault(i_tag, set()).add(j_tag)
        adjacency.setdefault(j_tag, set()).add(i_tag)

    orphaned = [
        tag for tag in all_node_tags
        if not adjacency.get(tag) and tag not in built.base_node_tags
    ]
    if orphaned:
        errors.append(f"{len(orphaned)} orphaned node(s) with no elements: {orphaned}")

    visited = set()
    frontier = list(built.base_node_tags)
    visited.update(frontier)
    while frontier:
        nxt = []
        for tag in frontier:
            for neighbor in adjacency.get(tag, ()):
                if neighbor not in visited:
                    visited.add(neighbor)
                    nxt.append(neighbor)
        frontier = nxt

    unreachable = all_node_tags - visited
    if unreachable:
        errors.append(
            f"{len(unreachable)} node(s) not connected to the base "
            f"through the element graph: {sorted(unreachable)}"
        )

    if getattr(built, "loaded_beam_tags", None):
        for level, tags in built.loaded_beam_tags.items():
            if not tags:
                warnings.append(f"level {level}: no beams received panel load")

    return ValidationResult(
        building_id=topology.building_id,
        ok=(len(errors) == 0),
        errors=errors,
        warnings=warnings,
    )
