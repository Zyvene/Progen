import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Dict, List

FEET_TO_M = 0.3048

W_SECTIONS_PATH = Path(__file__).parent / "w_sections.json"
STARTING_SECTION = "W12X26"


@dataclass
class BuildingTopology:
    building_id: int
    floor_count: int
    story_height: float
    bay_count_x: int
    bay_width_x: float
    bay_count_y: int
    bay_width_y: float

    floor_load_kpa: float = 6.0
    roof_load_kpa: float = 3.0

    def __post_init__(self):
        errors = []
        if self.floor_count < 1:
            errors.append(f"floor_count must be >= 1, got {self.floor_count}")
        if self.bay_count_x < 1:
            errors.append(f"bay_count_x must be >= 1, got {self.bay_count_x}")
        if self.bay_count_y < 1:
            errors.append(f"bay_count_y must be >= 1, got {self.bay_count_y}")
        if self.story_height <= 0:
            errors.append(f"story_height must be > 0, got {self.story_height}")
        if self.bay_width_x <= 0:
            errors.append(f"bay_width_x must be > 0, got {self.bay_width_x}")
        if self.bay_width_y <= 0:
            errors.append(f"bay_width_y must be > 0, got {self.bay_width_y}")
        if not (2.0 <= self.floor_load_kpa <= 10.0):
            errors.append(
                f"floor_load_kpa {self.floor_load_kpa} outside spec range 2-10 kN/m^2"
            )
        if not (1.0 <= self.roof_load_kpa <= 5.0):
            errors.append(
                f"roof_load_kpa {self.roof_load_kpa} outside spec range 1-5 kN/m^2"
            )
        if errors:
            raise ValueError(
                f"BuildingTopology {self.building_id} failed validation: "
                + "; ".join(errors)
            )

    @property
    def story_height_m(self) -> float:
        return self.story_height * FEET_TO_M

    @property
    def bay_width_x_m(self) -> float:
        return self.bay_width_x * FEET_TO_M

    @property
    def bay_width_y_m(self) -> float:
        return self.bay_width_y * FEET_TO_M

    @property
    def n_nodes_x(self) -> int:
        return self.bay_count_x + 1

    @property
    def n_nodes_y(self) -> int:
        return self.bay_count_y + 1

    @property
    def n_levels(self) -> int:
        return self.floor_count + 1

    @property
    def footprint_area_m2(self) -> float:
        return (self.bay_count_x * self.bay_width_x_m) * (
            self.bay_count_y * self.bay_width_y_m
        )

    def as_dict(self) -> dict:
        return {
            "building_id": self.building_id,
            "floor_count": self.floor_count,
            "story_height": self.story_height,
            "bay_count_x": self.bay_count_x,
            "bay_width_x": self.bay_width_x,
            "bay_count_y": self.bay_count_y,
            "bay_width_y": self.bay_width_y,
            "floor_load_kpa": self.floor_load_kpa,
            "roof_load_kpa": self.roof_load_kpa,
        }

    @classmethod
    def from_dict(cls, values: dict) -> "BuildingTopology":
        units = values.get("units", "ft").lower()
        length_factor = 1.0 / FEET_TO_M if units == "m" else 1.0
        if units not in {"ft", "m"}:
            raise ValueError(f"Unsupported topology length units: {units}")
        return cls(
            building_id=int(values["building_id"]),
            floor_count=int(values["floor_count"]),
            story_height=float(values["story_height"]) * length_factor,
            bay_count_x=int(values["bay_count_x"]),
            bay_width_x=float(values["bay_width_x"]) * length_factor,
            bay_count_y=int(values["bay_count_y"]),
            bay_width_y=float(values["bay_width_y"]) * length_factor,
            floor_load_kpa=float(values.get("floor_load_kpa", 6.0)),
            roof_load_kpa=float(values.get("roof_load_kpa", 3.0)),
        )


@dataclass
class MaterialProps:
    name: str = "AK_Steel_Grade_25"
    E_gpa: float = 200.0
    fy_mpa: float = 170.0
    tensile_ultimate_mpa: float = 290.0
    elongation_at_break_pct: float = 26.0
    density_gcc: float = 7.87
    poisson: float = 0.30

    @property
    def E_kpa(self) -> float:
        return self.E_gpa * 1e6

    @property
    def fy_kpa(self) -> float:
        return self.fy_mpa * 1e3

    @property
    def G_kpa(self) -> float:
        return self.E_kpa / (2 * (1 + self.poisson))

    @property
    def rupture_strain(self) -> float:
        return self.elongation_at_break_pct / 100.0

    @property
    def yield_strain(self) -> float:
        return self.fy_mpa / (self.E_gpa * 1e3)

    @property
    def hardening_ratio(self) -> float:
        hardening_modulus_mpa = (self.tensile_ultimate_mpa - self.fy_mpa) / (
            self.rupture_strain - self.yield_strain
        )
        return hardening_modulus_mpa / (self.E_gpa * 1e3)

    @property
    def density_kg_m3(self) -> float:
        return self.density_gcc * 1000.0


@dataclass(frozen=True)
class WSection:
    name: str
    metric_name: str
    d_m: float
    bf_m: float
    tf_m: float
    tw_m: float
    A_m2: float
    Ix_m4: float
    Iy_m4: float
    Sx_m3: float
    Sy_m3: float
    rx_m: float
    ry_m: float
    J_m4: float
    mass_kg_per_m: float


@lru_cache(maxsize=1)
def load_w_sections() -> List[WSection]:
    data = json.loads(W_SECTIONS_PATH.read_text(encoding="utf-8"))
    return [WSection(**entry) for entry in data["sections"]]


def w_section_lookup() -> Dict[str, WSection]:
    return {section.name: section for section in load_w_sections()}
