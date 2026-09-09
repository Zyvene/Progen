"""
loads.py
========
Converts the floor/roof panel loads (kN/m^2) into distributed line loads
on beam elements (kN/m) and applies them via OpenSeesPy's eleLoad.

Load path assumption (documented, not derived from the schema): the
floor/roof deck is assumed to span in the Y direction onto the
X-direction beams (a one-way slab), which is the standard simplifying
assumption used before a real slab/deck model exists. Only X-direction
beams receive tributary panel load; Y-direction beams carry no directly
-applied panel load in this pass. Swap this rule out once PCG defines
real framing/deck direction per building.

Tributary width for an X-beam at grid row `r` (0-indexed, r in
[0, bay_count_y]) is the standard beam tributary rule for uniform bay
spacing `by`:
    edge row   (r == 0 or r == bay_count_y): by / 2
    interior row:                             by

Local-axis note: every beam element in this model uses the same
geomTransf reference vector (0, 0, 1) (see model_builder.BEAM_TRANSF_TAG).
For a horizontal element (axis in the global X-Y plane) with that
reference vector, the resulting local y-axis is always global +Z,
regardless of whether the beam runs along global X or Y. That means a
downward gravity load can always be applied as `Wy = -w` in local
coordinates -- no per-beam trigonometry needed.
"""

from typing import Dict

import openseespy.opensees as ops

from schema import BuildingTopology

GRAVITY_PATTERN_TAG = 1
GRAVITY_TS_TAG = 1


def _tributary_width_y(topology: BuildingTopology, row: int) -> float:
    by = topology.bay_width_y_m
    if row == 0 or row == topology.bay_count_y:
        return by / 2.0
    return by


def apply_panel_loads(built) -> None:
    """
    Apply floor loads (all levels 1..floor_count-1) and roof load (level
    floor_count) as uniform distributed loads on X-direction beams only,
    per the load-path assumption above. Mutates the live OpenSeesPy
    model in place; does not return anything.
    """
    topology: BuildingTopology = built.topology
    nx, ny = topology.n_nodes_x, topology.n_nodes_y

    ops.timeSeries("Linear", GRAVITY_TS_TAG)
    ops.pattern("Plain", GRAVITY_PATTERN_TAG, GRAVITY_TS_TAG)

    # Rebuild a lookup: (level, row, col) beam tags, so we can identify
    # X-direction beams specifically (they were built row-major, col..col+1).
    node_tags = built.node_tags
    x_beam_lookup: Dict[int, list] = {}
    for level in range(1, topology.n_levels):
        x_beam_lookup[level] = []

    # We recover which stored beam elements are X-direction by comparing
    # the row/col of their endpoints (same row, adjacent col => X-beam).
    inv_node_tags = {tag: key for key, tag in node_tags.items()}

    for ele_tag, i_tag, j_tag in built.beam_elements:
        (li, ri, ci) = inv_node_tags[i_tag]
        (lj, rj, cj) = inv_node_tags[j_tag]
        is_x_beam = (li == lj) and (ri == rj) and (abs(ci - cj) == 1)
        if not is_x_beam:
            continue  # Y-direction beam: no panel load in this pass

        level = li
        row = ri
        is_roof = level == topology.floor_count
        panel_load_kpa = topology.roof_load_kpa if is_roof else topology.floor_load_kpa
        trib_width_m = _tributary_width_y(topology, row)
        w = panel_load_kpa * trib_width_m  # kN/m, magnitude

        ops.eleLoad("-ele", ele_tag, "-type", "-beamUniform", -w, 0.0)
        x_beam_lookup[level].append(ele_tag)

    built.loaded_beam_tags = x_beam_lookup
