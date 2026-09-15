"""
inspect_model.py
================
Shows the actual OpenSeesPy model that gets built -- real node
coordinates, real element connectivity, the real material/loads
that were assigned, and a real analysis result. This is what
`build_model()` produces; validate_model() just checks it, it doesn't
build anything on its own.
"""

import openseespy.opensees as ops

from schema import BuildingTopology
from model_builder import build_model
from validation import validate_model

topology = BuildingTopology(
    building_id=1,
    floor_count=4,
    story_height=16,      # ft
    bay_count_x=3,
    bay_width_x=30,       # ft
    bay_count_y=2,
    bay_width_y=25,       # ft
    floor_load_kpa=6.0,
    roof_load_kpa=3.0,
)

print("=" * 70)
print("BUILDING THE MODEL")
print("=" * 70)
built = build_model(topology)

print(f"\nTopology: {topology.floor_count} floors, "
      f"{topology.bay_count_x}x{topology.bay_count_y} bays, "
      f"story height {topology.story_height} ft, "
      f"bays {topology.bay_width_x} ft x {topology.bay_width_y} ft\n")

# -- 1. Real nodes, with real coordinates --------------------------------
print(f"NODES: {len(built.node_coords)} created")
print("First 5 node coordinates (tag: x, y, z in meters):")
for i, (tag, (x, y, z)) in enumerate(built.node_coords.items()):
    if i >= 5:
        break
    print(f"  node {tag}: ({x:.2f}, {y:.2f}, {z:.2f})")

# -- 2. Real base fixity ---------------------------------------------------
print(f"\nBASE FIXITY: {len(built.base_node_tags)} nodes fixed at the ground level")
print(f"Example: ops.getFixedDOFs({built.base_node_tags[0]}) = "
      f"{ops.getFixedDOFs(built.base_node_tags[0])}")

# -- 3. Real elements, with real connectivity ------------------------------
print(f"\nCOLUMN ELEMENTS: {len(built.column_elements)} created")
ele_tag, i_tag, j_tag = built.column_elements[0]
print(f"Example: column element {ele_tag} connects node {i_tag} -> node {j_tag}")
print(f"  node {i_tag} is at {built.node_coords[i_tag]}")
print(f"  node {j_tag} is at {built.node_coords[j_tag]}")

print(f"\nBEAM ELEMENTS: {len(built.beam_elements)} created")
ele_tag, i_tag, j_tag = built.beam_elements[0]
print(f"Example: beam element {ele_tag} connects node {i_tag} -> node {j_tag}")
print(f"  node {i_tag} is at {built.node_coords[i_tag]}")
print(f"  node {j_tag} is at {built.node_coords[j_tag]}")

# -- 4. Real material properties assigned ----------------------------------
print(f"\nMATERIAL (AK Steel Grade 25):")
print(f"  E  = {built.material.E_gpa} GPa  ({built.material.E_kpa:.0f} kPa)")
print(f"  Fy = {built.material.fy_mpa} MPa  ({built.material.fy_kpa:.0f} kPa)")
print(f"  G  = {built.material.G_kpa:.0f} kPa (derived)")

# -- 5. Real loads applied ---------------------------------------------------
loaded_count = sum(len(tags) for tags in built.loaded_beam_tags.values())
print(f"\nLOADS: {loaded_count} beam elements have panel loads applied")
print(f"  floor panel load: {topology.floor_load_kpa} kN/m^2")
print(f"  roof panel load:  {topology.roof_load_kpa} kN/m^2")

# -- 6. Validation ------------------------------------------------------------
print("\n" + "=" * 70)
print("VALIDATION")
print("=" * 70)
result = validate_model(built)
print(result.report())

# -- 7. Real analysis, real numbers ------------------------------------------
print("\n" + "=" * 70)
print("RUNNING A REAL GRAVITY ANALYSIS")
print("=" * 70)
ops.system("BandSPD")
ops.numberer("RCM")
ops.constraints("Plain")
ops.integrator("LoadControl", 1.0)
ops.algorithm("Linear")
ops.analysis("Static")
ok = ops.analyze(1)
print(f"ops.analyze(1) returned: {ok}  (0 = converged)\n")

roof_level = topology.floor_count
print(f"Vertical (Z) displacement at every roof node:")
for (level, row, col), tag in sorted(built.node_tags.items()):
    if level == roof_level:
        uz = ops.nodeDisp(tag, 3)
        print(f"  node {tag} (row {row}, col {col}): Uz = {uz * 1000:.4f} mm")
