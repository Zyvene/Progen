"""
model_builder.py
=================
Turns a BuildingTopology into a valid, analysis-ready OpenSeesPy model:
nodes, base fixity, beam-column elements, material, and floor/roof loads.

Model conventions
------------------
- ndm=3, ndf=6 (full 3D frame, 6 DOF/node)
- Units: kN, m  (consistent with the loads spec and the converted geometry)
- Axes: X, Y = plan directions (matches bay_count_x / bay_count_y),
        Z = vertical (story direction)
- Node tag scheme: unique per (level, row, col):
      tag = level * (n_nodes_x * n_nodes_y) + row * n_nodes_x + col + 1
  level 0 = base/ground, level floor_count = roof.
- Base nodes (level 0) are fully fixed (fix 1 1 1 1 1 1) -- a simple
  fixed-base idealization; swap for a spring/foundation model later if
  the project needs one.
- Columns connect (level, row, col) -> (level+1, row, col) for every
  grid point, at every story.
- Beams connect adjacent grid points *within* a level, for every level
  from 1 (first floor) through floor_count (roof) -- levels run both
  X-direction and Y-direction beams, forming a complete floor grid.
  Level 0 (the base) has no beams, only columns rising from it.
"""

from dataclasses import dataclass
from typing import Dict, List, Tuple

import openseespy.opensees as ops

from schema import BuildingTopology, MaterialProps, SectionProps

NodeKey = Tuple[int, int, int]  # (level, row, col)


@dataclass
class BuiltModel:
    """Everything downstream consumers (validation, analysis, viz) need."""

    topology: BuildingTopology
    node_tags: Dict[NodeKey, int]
    node_coords: Dict[int, Tuple[float, float, float]]
    column_elements: List[Tuple[int, int, int]]  # (ele_tag, i_tag, j_tag)
    beam_elements: List[Tuple[int, int, int]]     # (ele_tag, i_tag, j_tag)
    base_node_tags: List[int]
    floor_beam_tags: Dict[int, List[int]]  # level -> beam element tags at that level
    material: MaterialProps
    section: SectionProps


def node_tag(topology: BuildingTopology, level: int, row: int, col: int) -> int:
    nx, ny = topology.n_nodes_x, topology.n_nodes_y
    return level * (nx * ny) + row * nx + col + 1


def build_model(
    topology: BuildingTopology,
    material: MaterialProps = None,
    section: SectionProps = None,
    apply_loads: bool = True,
) -> BuiltModel:
    """
    Build a fresh OpenSeesPy model in memory for `topology` and return a
    BuiltModel describing what was created. Calling this again for a
    different topology starts a brand-new model (wipe()).
    """
    material = material or MaterialProps()
    section = section or SectionProps()

    ops.wipe()
    ops.model("basic", "-ndm", 3, "-ndf", 6)

    nx, ny = topology.n_nodes_x, topology.n_nodes_y
    sh = topology.story_height_m
    bx = topology.bay_width_x_m
    by = topology.bay_width_y_m

    node_tags: Dict[NodeKey, int] = {}
    node_coords: Dict[int, Tuple[float, float, float]] = {}
    base_node_tags: List[int] = []

    # -- Nodes ------------------------------------------------------------
    for level in range(topology.n_levels):
        z = level * sh
        for row in range(ny):
            y = row * by
            for col in range(nx):
                x = col * bx
                tag = node_tag(topology, level, row, col)
                ops.node(tag, x, y, z)
                node_tags[(level, row, col)] = tag
                node_coords[tag] = (x, y, z)
                if level == 0:
                    ops.fix(tag, 1, 1, 1, 1, 1, 1)
                    base_node_tags.append(tag)

    # -- Material / transform ----------------------------------------------
    # Geometric transformation for 3D elasticBeamColumn: columns are
    # vertical (local axis along global Z) so a global-X vector reference
    # works for them; beams run horizontal so a global-Z vector reference
    # works. Two transforms keep both element groups well-conditioned.
    COL_TRANSF_TAG = 1
    BEAM_TRANSF_TAG = 2
    ops.geomTransf("Linear", COL_TRANSF_TAG, 1.0, 0.0, 0.0)
    ops.geomTransf("Linear", BEAM_TRANSF_TAG, 0.0, 0.0, 1.0)

    ele_tag_counter = 1
    column_elements: List[Tuple[int, int, int]] = []
    beam_elements: List[Tuple[int, int, int]] = []
    floor_beam_tags: Dict[int, List[int]] = {lvl: [] for lvl in range(1, topology.n_levels)}

    # -- Columns: every grid point, every story ----------------------------
    for level in range(topology.floor_count):
        for row in range(ny):
            for col in range(nx):
                i_tag = node_tags[(level, row, col)]
                j_tag = node_tags[(level + 1, row, col)]
                ele_tag = ele_tag_counter
                ele_tag_counter += 1
                ops.element(
                    "elasticBeamColumn", ele_tag, i_tag, j_tag,
                    section.A_m2, material.E_kpa, material.G_kpa,
                    section.J_m4, section.Iy_m4, section.Iz_m4,
                    COL_TRANSF_TAG,
                )
                column_elements.append((ele_tag, i_tag, j_tag))

    # -- Beams: every level 1..floor_count, full grid in X and Y -----------
    for level in range(1, topology.n_levels):
        # X-direction beams: connect (col, col+1) at each row
        for row in range(ny):
            for col in range(nx - 1):
                i_tag = node_tags[(level, row, col)]
                j_tag = node_tags[(level, row, col + 1)]
                ele_tag = ele_tag_counter
                ele_tag_counter += 1
                ops.element(
                    "elasticBeamColumn", ele_tag, i_tag, j_tag,
                    section.A_m2, material.E_kpa, material.G_kpa,
                    section.J_m4, section.Iy_m4, section.Iz_m4,
                    BEAM_TRANSF_TAG,
                )
                beam_elements.append((ele_tag, i_tag, j_tag))
                floor_beam_tags[level].append(ele_tag)
        # Y-direction beams: connect (row, row+1) at each col
        for col in range(nx):
            for row in range(ny - 1):
                i_tag = node_tags[(level, row, col)]
                j_tag = node_tags[(level, row + 1, col)]
                ele_tag = ele_tag_counter
                ele_tag_counter += 1
                ops.element(
                    "elasticBeamColumn", ele_tag, i_tag, j_tag,
                    section.A_m2, material.E_kpa, material.G_kpa,
                    section.J_m4, section.Iy_m4, section.Iz_m4,
                    BEAM_TRANSF_TAG,
                )
                beam_elements.append((ele_tag, i_tag, j_tag))
                floor_beam_tags[level].append(ele_tag)

    built = BuiltModel(
        topology=topology,
        node_tags=node_tags,
        node_coords=node_coords,
        column_elements=column_elements,
        beam_elements=beam_elements,
        base_node_tags=base_node_tags,
        floor_beam_tags=floor_beam_tags,
        material=material,
        section=section,
    )

    if apply_loads:
        from loads import apply_panel_loads
        apply_panel_loads(built)

    return built
