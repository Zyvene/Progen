"""
sample_data.py
===============
Converts rows of regular_buildings.xlsx into BuildingTopology objects,
to use as realistic placeholder input while PCG doesn't exist yet.

The dataset columns already match the schema field names 1:1:
    Building_ID, Floor_Count, Story_Height,
    Bay_Count_X, Bay_Width_X, Bay_Count_Y, Bay_Width_Y

The dataset's actual parametric coverage (423 rows) is narrower than the
full spec'd range:
    floor_count   observed 1-10   (spec: 1-10)   -> full coverage
    bay_count_x   observed 1-5    (spec: 1-10)   -> partial coverage
    bay_count_y   observed 1-4    (spec: 1-10)   -> partial coverage
So "near 10x10 bays" isn't available in this sample; the largest
available footprint (5x4 bays) is used instead as the upper-end pick,
and this gap is called out explicitly rather than silently upscaled.
"""

from pathlib import Path
from typing import List

import pandas as pd

from schema import BuildingTopology

DEFAULT_XLSX_PATH = Path(__file__).parent / "regular_buildings.xlsx"


def load_all(xlsx_path: Path = DEFAULT_XLSX_PATH) -> pd.DataFrame:
    df = pd.read_excel(xlsx_path, sheet_name="Sheet1")
    expected_cols = {
        "Building_ID", "Floor_Count", "Story_Height",
        "Bay_Count_X", "Bay_Width_X", "Bay_Count_Y", "Bay_Width_Y",
    }
    missing = expected_cols - set(df.columns)
    if missing:
        raise ValueError(f"regular_buildings.xlsx is missing columns: {missing}")
    return df


def row_to_topology(row: pd.Series, floor_load_kpa: float = 6.0,
                     roof_load_kpa: float = 3.0) -> BuildingTopology:
    return BuildingTopology(
        building_id=int(row["Building_ID"]),
        floor_count=int(row["Floor_Count"]),
        story_height=float(row["Story_Height"]),
        bay_count_x=int(row["Bay_Count_X"]),
        bay_width_x=float(row["Bay_Width_X"]),
        bay_count_y=int(row["Bay_Count_Y"]),
        bay_width_y=float(row["Bay_Width_Y"]),
        floor_load_kpa=floor_load_kpa,
        roof_load_kpa=roof_load_kpa,
    )


def pick_edge_case_spread(xlsx_path: Path = DEFAULT_XLSX_PATH) -> List[BuildingTopology]:
    """
    Pick a small spread of buildings across the parametric range, to use
    as smoke-test / edge-case input:
        - smallest:  1 floor,  smallest available bay counts (1x1)
        - largest:   10 floors, largest available bay counts (5x4)
        - one mid-range building for good measure
    """
    df = load_all(xlsx_path)

    footprint = df["Bay_Count_X"] * df["Bay_Count_Y"]

    smallest_row = df.loc[
        (df["Floor_Count"] == df["Floor_Count"].min())
        & (footprint == footprint.min())
    ].iloc[0]

    largest_row = df.loc[
        (df["Floor_Count"] == df["Floor_Count"].max())
        & (footprint == footprint.max())
    ]
    if largest_row.empty:
        # fall back: max floors, then max footprint among those
        candidates = df.loc[df["Floor_Count"] == df["Floor_Count"].max()]
        largest_row = candidates.loc[[footprint.loc[candidates.index].idxmax()]]
    largest_row = largest_row.iloc[0]

    mid_target_floor = int(round(df["Floor_Count"].median()))
    mid_candidates = df.loc[df["Floor_Count"] == mid_target_floor]
    mid_row = mid_candidates.iloc[len(mid_candidates) // 2]

    return [
        row_to_topology(smallest_row, floor_load_kpa=2.0, roof_load_kpa=1.0),
        row_to_topology(mid_row, floor_load_kpa=6.0, roof_load_kpa=3.0),
        row_to_topology(largest_row, floor_load_kpa=10.0, roof_load_kpa=5.0),
    ]


if __name__ == "__main__":
    for t in pick_edge_case_spread():
        print(t.as_dict(), "-> footprint_area_m2 =", round(t.footprint_area_m2, 1))
