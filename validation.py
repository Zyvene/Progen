"""
validation.py
==============
Basic sanity checks on a BuiltModel before it gets handed downstream:
    1. No orphaned nodes (every node touches at least one element, or is
       a fixed base node).
    2. Connectivity is complete:
         - every non-base node is reachable from a base node by walking
           the element graph (the frame is one connected structure, not
           several disjoint pieces).
         - every grid point at every level has a column below/above (as
           appropriate) and a full beam grid at every floor level, i.e.
           node count and element count match what the topology implies.
    3. Every base node is actually fixed (no floating "ground" nodes).

This is deliberately basic (per the task brief) -- it is not a full
mesh-quality or engineering-adequacy check.
"""

from dataclasses import dataclass, field
from typing import List

from schema import BuildingTopology


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
    errors: List[str] = []
    warnings: List[str] = []

    all_node_tags = set(built.node_tags.values())
    n_nodes_expected = topology.n_levels * topology.n_nodes_x * topology.n_nodes_y
    if len(all_node_tags) != n_nodes_expected:
        errors.append(
            f"expected {n_nodes_expected} nodes, found {len(all_node_tags)}"
        )

    # -- element counts vs. what the grid implies --------------------------
    n_cols_expected = topology.floor_count * topology.n_nodes_x * topology.n_nodes_y
    if len(built.column_elements) != n_cols_expected:
        errors.append(
            f"expected {n_cols_expected} column elements, "
            f"found {len(built.column_elements)}"
        )

    n_beams_per_level = (
        topology.n_nodes_y * (topology.n_nodes_x - 1)  # X-direction
        + topology.n_nodes_x * (topology.n_nodes_y - 1)  # Y-direction
    )
    n_beams_expected = n_beams_per_level * topology.floor_count
    if len(built.beam_elements) != n_beams_expected:
        errors.append(
            f"expected {n_beams_expected} beam elements, "
            f"found {len(built.beam_elements)}"
        )

    # -- base fixity ---------------------------------------------------------
    expected_base_nodes = topology.n_nodes_x * topology.n_nodes_y
    if len(built.base_node_tags) != expected_base_nodes:
        errors.append(
            f"expected {expected_base_nodes} fixed base nodes, "
            f"found {len(built.base_node_tags)}"
        )

    # -- orphaned nodes + connectivity (graph walk) ---------------------------
    adjacency = {tag: set() for tag in all_node_tags}
    for _ele_tag, i_tag, j_tag in built.column_elements + built.beam_elements:
        adjacency.setdefault(i_tag, set()).add(j_tag)
        adjacency.setdefault(j_tag, set()).add(i_tag)

    orphaned = [
        tag for tag in all_node_tags
        if not adjacency.get(tag) and tag not in built.base_node_tags
    ]
    if orphaned:
        errors.append(f"{len(orphaned)} orphaned node(s) with no elements: {orphaned}")

    # BFS from base nodes to confirm the whole frame is one connected piece
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

    # -- loads sanity check (warning only) ------------------------------------
    if getattr(built, "loaded_beam_tags", None) is not None:
        for level, tags in built.loaded_beam_tags.items():
            if not tags:
                warnings.append(f"level {level}: no beams received panel load")

    return ValidationResult(
        building_id=topology.building_id,
        ok=(len(errors) == 0),
        errors=errors,
        warnings=warnings,
    )
