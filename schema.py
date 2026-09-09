"""
schema.py
=========
Formal definition of the topology schema this module consumes.

This is the contract between the (not-yet-built) Procedural Content
Generator (PCG) and the OpenSeesPy model builder. Until PCG exists, the
schema is populated from `regular_buildings.xlsx`, which already matches
these fields 1:1 (see `sample_data.py`).

Parametric scope (per Chapter 3 / the task brief):
    floor_count   : 1  .. 10    stories
    bay_count_x   : 1  .. 10    bays in the X direction
    bay_count_y   : 1  .. 10    bays in the Y direction
    bay_width_x   : building-specific, feet
    bay_width_y   : building-specific, feet
    story_height  : building-specific, feet

NOTE on units: the sample dataset stores story height and bay widths as
plain numbers (e.g. 16, 28-40) with no unit column. This matches the
convention used elsewhere in this project (see structure_data.gd in the
LSDSE-Godot-Prototype repo, which hardcodes "All coordinates are in
feet"), so geometry is assumed to be in **feet** and converted to
**meters** internally so the whole model (geometry + kN/m^2 loads +
GPa material) lives in one consistent SI unit system (kN, m).
If the true unit convention turns out to be different, only
`schema.FEET_TO_M` needs to change.
"""

from dataclasses import dataclass, field
from typing import Optional

FEET_TO_M = 0.3048


@dataclass
class BuildingTopology:
    """
    One row of the topology schema. Field names intentionally mirror the
    columns of regular_buildings.xlsx so a row can be unpacked directly.

    Geometry fields are stored in the SOURCE units (feet) and exposed via
    the *_m properties in meters, so callers never have to remember to
    convert.
    """

    building_id: int
    floor_count: int          # number of stories above the base, >= 1
    story_height: float       # ft, uniform story height (all stories equal)
    bay_count_x: int          # number of bays in X, >= 1
    bay_width_x: float        # ft, uniform bay width in X
    bay_count_y: int          # number of bays in Y, >= 1
    bay_width_y: float        # ft, uniform bay width in Y

    # Panel loads (kN/m^2). Not present in the sample dataset (PCG will
    # eventually generate these); default to the midpoint of each
    # spec'd range and can be overridden per-building.
    floor_load_kpa: float = 6.0   # kN/m^2, spec range 2-10
    roof_load_kpa: float = 3.0    # kN/m^2, spec range 1-5

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

    # ---- derived geometry, in meters -----------------------------------
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
        """Number of node levels including the base (level 0)."""
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


@dataclass
class MaterialProps:
    """AK Steel Grade 25, per Table 2."""

    name: str = "AK_Steel_Grade_25"
    E_gpa: float = 200.0        # modulus of elasticity, GPa
    fy_mpa: float = 170.0       # yield strength (minimum), MPa
    poisson: float = 0.30       # not given by Table 2; standard value for structural steel

    @property
    def E_kpa(self) -> float:
        """Modulus in kPa, for a (kN, m) unit system."""
        return self.E_gpa * 1e6

    @property
    def fy_kpa(self) -> float:
        return self.fy_mpa * 1e3

    @property
    def G_kpa(self) -> float:
        """Shear modulus, derived from E and Poisson's ratio (isotropic)."""
        return self.E_kpa / (2 * (1 + self.poisson))


@dataclass
class SectionProps:
    """
    Placeholder beam/column cross-section properties.

    PCG (the sizing/section-assignment module referenced in the task
    brief) is not built yet, so there is no catalog to pick real W- or
    HSS-sections from. These are nominal, documented placeholder values
    only, sized to be plausible for the story heights / bay widths in
    the sample dataset -- NOT the result of any design check. Swap
    `model_builder.build_model(..., section=...)` for real values (or a
    per-element lookup) once PCG exists.
    """

    label: str = "PLACEHOLDER_SECTION"
    A_m2: float = 0.010      # cross-sectional area, m^2  (~100 cm^2)
    Iz_m4: float = 8.33e-5   # strong-axis moment of inertia, m^4
    Iy_m4: float = 8.33e-5   # weak-axis moment of inertia, m^4
    J_m4: float = 1.67e-4    # torsional constant, m^4
