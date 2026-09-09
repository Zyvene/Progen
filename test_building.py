from schema import BuildingTopology
from model_builder import build_model
from validation import validate_model

topology = BuildingTopology(
    building_id=2,
    floor_count=10,
    story_height=16,
    bay_count_x=5,
    bay_width_x=28,
    bay_count_y=5,
    bay_width_y=32,
)

built = build_model(topology)
result = validate_model(built)
print(result.report())