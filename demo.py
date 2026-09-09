"""
demo.py
=======
End-to-end run: pull a small spread of sample structures out of
regular_buildings.xlsx, build an OpenSeesPy model for each, validate it,
and (as a cheap proof the model is actually analysis-ready) run a linear
static gravity analysis and report the max vertical roof deflection.
"""

import openseespy.opensees as ops

from sample_data import pick_edge_case_spread
from model_builder import build_model
from validation import validate_model


def run_gravity_check(built) -> float:
    """Run a linear static analysis under the applied panel loads and
    return the max abs. vertical (Z) displacement at the roof level, as
    a smoke test that the model actually solves."""
    ops.system("BandSPD")
    ops.numberer("RCM")
    ops.constraints("Plain")
    ops.integrator("LoadControl", 1.0)
    ops.algorithm("Linear")
    ops.analysis("Static")
    ok = ops.analyze(1)

    topology = built.topology
    roof_level = topology.floor_count
    max_uz = 0.0
    for (level, row, col), tag in built.node_tags.items():
        if level == roof_level:
            uz = ops.nodeDisp(tag, 3)
            max_uz = max(max_uz, abs(uz))
    return ok, max_uz


def main():
    topologies = pick_edge_case_spread()
    print(f"Loaded {len(topologies)} sample structures from regular_buildings.xlsx\n")

    all_ok = True
    for topology in topologies:
        print("=" * 70)
        print(
            f"Building {topology.building_id}: "
            f"{topology.floor_count} floors, "
            f"{topology.bay_count_x}x{topology.bay_count_y} bays, "
            f"story height {topology.story_height} ft, "
            f"bays {topology.bay_width_x}x{topology.bay_width_y} ft"
        )
        built = build_model(topology)

        result = validate_model(built)
        print(result.report())
        all_ok = all_ok and result.ok

        if result.ok:
            analyze_ok, max_uz = run_gravity_check(built)
            status = "converged" if analyze_ok == 0 else "FAILED TO CONVERGE"
            print(
                f"  Gravity analysis: {status}, "
                f"max roof |Uz| = {max_uz * 1000:.3f} mm"
            )
        print()

    print("=" * 70)
    print("ALL BUILDINGS VALID" if all_ok else "AT LEAST ONE BUILDING FAILED VALIDATION")


if __name__ == "__main__":
    main()
