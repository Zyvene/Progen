from pathlib import Path
from typing import List

import pandas as pd

from input_management import BuildingTopology

DEFAULT_XLSX_PATH = Path(__file__).parent / "regular_buildings.xlsx"


def sample_topology() -> BuildingTopology:
    return BuildingTopology(
        building_id=9001,
        floor_count=2,
        story_height=12.0,
        bay_count_x=1,
        bay_width_x=20.0,
        bay_count_y=1,
        bay_width_y=20.0,
    )


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
