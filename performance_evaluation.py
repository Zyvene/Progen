from __future__ import annotations

import math

SHORT_PERIOD_DRIFT_LIMIT = 0.025
LONG_PERIOD_DRIFT_LIMIT = 0.020
DRIFT_LIMIT_PERIOD_THRESHOLD_S = 0.7

TORSIONAL_IRREGULARITY_RATIO_LIMIT = 1.2

SOFT_STORY_RATIO_TO_STOREY_ABOVE = 0.70
SOFT_STORY_RATIO_TO_THREE_ABOVE = 0.80

COLUMN_K_FACTOR = 1.0

MEAN_STRESS_APPROACH_FRACTION = 0.90


def drift_limit_for_period(period_s: float) -> float:
    if period_s < DRIFT_LIMIT_PERIOD_THRESHOLD_S:
        return SHORT_PERIOD_DRIFT_LIMIT
    return LONG_PERIOD_DRIFT_LIMIT


def evaluate_gravity_fallback(built, stress_by_element: dict) -> dict:
    fy_mpa = built.material.fy_mpa
    inv_node_tags = {tag: list(key) for key, tag in built.node_tags.items()}
    overstressed = []
    for tag, info in built.elements.items():
        stress = stress_by_element.get(tag, 0.0)
        if stress > fy_mpa:
            overstressed.append({
                "element_tag": info.tag, "kind": info.kind, "member": info.member,
                "section": info.section.name,
                "i_node": inv_node_tags[info.i_tag], "j_node": inv_node_tags[info.j_tag],
                "peak_stress_mpa": stress, "ratio": stress / fy_mpa,
            })
    stresses = [stress_by_element.get(tag, 0.0) for tag in built.elements]
    mean_stress_mpa = sum(stresses) / len(stresses) if stresses else 0.0
    mean_stress_exceeds = mean_stress_mpa >= MEAN_STRESS_APPROACH_FRACTION * fy_mpa
    triggered = []
    if overstressed:
        triggered.append({"rule": 1, "name": "Yield Stress", "count": len(overstressed),
                          "max_ratio": max(item["ratio"] for item in overstressed)})
    if mean_stress_exceeds:
        triggered.append({"rule": 10, "name": "Mean Stress", "count": 1, "max_ratio": mean_stress_mpa / fy_mpa})
    return {
        "gravity_fallback": True,
        "fundamental_period_s": None,
        "drift_limit": None,
        "triggered_rules": triggered,
        "element_level": {
            "pass": not overstressed,
            "total_elements": len(built.elements),
            "overstressed_elements": overstressed,
            "buckled_elements": [],
            "ruptured_elements": [],
            "yield_stress_mpa": fy_mpa,
        },
        "floor_level": None,
        "structure_level": {
            "pass": not mean_stress_exceeds,
            "mean_stress_mpa": mean_stress_mpa,
            "mean_stress_exceeds_yield": mean_stress_exceeds,
            "mean_stress_threshold_mpa": MEAN_STRESS_APPROACH_FRACTION * fy_mpa,
        },
        "pass": False,
    }


def evaluate_performance(built, tracker, period_s: float, story_stiffness: dict) -> dict:
    topology = built.topology
    material = built.material
    fy_mpa = material.fy_mpa
    e_mpa = material.E_gpa * 1e3
    rupture_strain = material.rupture_strain
    drift_limit = drift_limit_for_period(period_s)
    inv_node_tags = {tag: list(key) for key, tag in built.node_tags.items()}

    def describe(info) -> dict:
        return {
            "element_tag": info.tag, "kind": info.kind, "member": info.member,
            "section": info.section.name,
            "i_node": inv_node_tags[info.i_tag], "j_node": inv_node_tags[info.j_tag],
        }

    strut_axes = {}
    for strut in built.grid.struts:
        for key in strut.mid_node_keys():
            _, story, row, col = key
            strut_axes.setdefault((story, row, col), set()).add(strut.axis)

    def column_location(info):
        key = inv_node_tags[info.j_tag]
        return (info.story, key[-2], key[-1])

    story_height = topology.story_height_m
    overstressed, buckled, ruptured = [], [], []
    for tag, info in built.elements.items():
        stress = tracker.peak_stress.get(tag, 0.0)
        if stress > fy_mpa:
            overstressed.append({**describe(info), "peak_stress_mpa": stress, "ratio": stress / fy_mpa})
        if info.kind == "column":
            axes = strut_axes.get(column_location(info), set())
            weak_length = story_height / 2.0 if "y" in axes else story_height
            strong_length = story_height / 2.0 if "x" in axes else story_height
            slenderness = COLUMN_K_FACTOR * max(weak_length / info.section.ry_m,
                                                strong_length / info.section.rx_m)
            euler_mpa = (math.pi ** 2) * e_mpa / slenderness ** 2
            compression = tracker.peak_compression.get(tag, 0.0)
            if compression > euler_mpa:
                buckled.append({
                    **describe(info), "peak_compressive_stress_mpa": compression,
                    "euler_critical_stress_mpa": euler_mpa, "ratio": compression / euler_mpa,
                })
        strain = tracker.peak_strain.get(tag, 0.0)
        if strain > rupture_strain:
            ruptured.append({**describe(info), "peak_strain": strain, "rupture_strain": rupture_strain,
                             "ratio": strain / rupture_strain})
    element_level_pass = not overstressed and not buckled and not ruptured

    floors = topology.floor_count
    h = topology.story_height_m
    idr_x = {s: tracker.peak_drift["x"][s] / h for s in range(1, floors + 1)}
    idr_y = {s: tracker.peak_drift["y"][s] / h for s in range(1, floors + 1)}

    def floor_idr(level):
        return max(idr_x[level], idr_y[level])

    exceeding_floors = [s for s in range(1, floors + 1) if floor_idr(s) > drift_limit]
    exceeding_detail = [{"floor": s, "idr": floor_idr(s), "ratio": floor_idr(s) / drift_limit}
                        for s in exceeding_floors]

    soft_story_detail = []
    for axis in ("x", "y"):
        stiffness = story_stiffness[axis]
        for level in range(1, floors):
            k_here, k_above = stiffness[level], stiffness[level + 1]
            if k_here <= 0.0 or k_above <= 0.0:
                continue
            required = SOFT_STORY_RATIO_TO_STOREY_ABOVE * k_above
            if level + 3 <= floors:
                three_above = [stiffness[level + i] for i in (1, 2, 3)]
                if all(k > 0.0 for k in three_above):
                    required = max(required, SOFT_STORY_RATIO_TO_THREE_ABOVE * sum(three_above) / 3.0)
            if k_here < required:
                soft_story_detail.append({"floor": level, "axis": axis, "stiffness_kn_per_m": k_here,
                                          "required_kn_per_m": required, "ratio": required / k_here})
    soft_story_floors = sorted({entry["floor"] for entry in soft_story_detail})

    mid_story_floors = []
    if floors >= 3 and floor_idr(1) <= drift_limit and floor_idr(floors) <= drift_limit:
        mid_story_floors = [s for s in range(2, floors) if floor_idr(s) > drift_limit]

    directional_detail = []
    for level in range(1, floors + 1):
        x_over, y_over = idr_x[level] > drift_limit, idr_y[level] > drift_limit
        if x_over != y_over:
            weak = "x" if x_over else "y"
            directional_detail.append({"floor": level, "weak_axis": weak,
                                       "ratio": max(idr_x[level], idr_y[level]) / drift_limit})
    directional_floors = [entry["floor"] for entry in directional_detail]

    floor_level_pass = not (exceeding_floors or soft_story_floors or mid_story_floors or directional_floors)

    total_height_m = floors * h
    roof_limit_m = drift_limit * total_height_m
    peak_roof_m = max(tracker.peak_roof["x"], tracker.peak_roof["y"])
    roof_exceeds = peak_roof_m > roof_limit_m

    stresses = [tracker.peak_stress.get(tag, 0.0) for tag in built.elements]
    mean_stress_mpa = sum(stresses) / len(stresses) if stresses else 0.0
    mean_stress_exceeds = mean_stress_mpa >= MEAN_STRESS_APPROACH_FRACTION * fy_mpa

    torsion_detail = []
    max_torsion_ratio = 1.0
    for axis in ("x", "y"):
        for level in range(1, floors + 1):
            end_a, end_b = tracker.end_drift_peaks[axis][level]
            average = (end_a + end_b) / 2.0
            if average <= 0.0:
                continue
            ratio = max(end_a, end_b) / average
            max_torsion_ratio = max(max_torsion_ratio, ratio)
            if ratio > TORSIONAL_IRREGULARITY_RATIO_LIMIT:
                torsion_detail.append({"floor": level, "axis": axis, "ratio": ratio})
    torsional_irregularity = bool(torsion_detail)

    structure_level_pass = not (roof_exceeds or torsional_irregularity or mean_stress_exceeds)

    def rule_entry(number, name, items, ratio_key="ratio"):
        if not items:
            return None
        return {"rule": number, "name": name, "count": len(items),
                "max_ratio": max(item[ratio_key] for item in items)}

    triggered = [entry for entry in (
        rule_entry(1, "Yield Stress", overstressed),
        rule_entry(2, "Buckling", buckled),
        rule_entry(3, "Rupture Strain", ruptured),
        rule_entry(4, "Floor IDR", exceeding_detail),
        rule_entry(5, "Soft-Story", soft_story_detail),
        rule_entry(6, "Mid-Story IDR Concentration",
                   [{"ratio": floor_idr(s) / drift_limit} for s in mid_story_floors]),
        rule_entry(7, "Directional Instability", directional_detail),
        rule_entry(8, "Roof Displacement", [{"ratio": peak_roof_m / roof_limit_m}] if roof_exceeds else []),
        rule_entry(9, "Torsional Irregularity", torsion_detail),
        rule_entry(10, "Mean Stress",
                   [{"ratio": mean_stress_mpa / fy_mpa}] if mean_stress_exceeds else []),
    ) if entry]

    return {
        "fundamental_period_s": period_s,
        "drift_limit": drift_limit,
        "triggered_rules": triggered,
        "element_level": {
            "pass": element_level_pass,
            "total_elements": len(built.elements),
            "overstressed_elements": overstressed,
            "buckled_elements": buckled,
            "ruptured_elements": ruptured,
            "yield_stress_mpa": fy_mpa,
            "rupture_strain": rupture_strain,
        },
        "floor_level": {
            "pass": floor_level_pass,
            "total_floors": floors,
            "idr_limit": drift_limit,
            "exceeding_floors": exceeding_floors,
            "exceeding_detail": exceeding_detail,
            "soft_story_floors": soft_story_floors,
            "soft_story_detail": soft_story_detail,
            "mid_story_concentration_floors": mid_story_floors,
            "directional_instability_floors": directional_floors,
            "directional_detail": directional_detail,
            "peak_idr_x_by_floor": {str(k): v for k, v in idr_x.items()},
            "peak_idr_y_by_floor": {str(k): v for k, v in idr_y.items()},
            "story_stiffness_x_kn_per_m": {str(k): v for k, v in story_stiffness["x"].items()},
            "story_stiffness_y_kn_per_m": {str(k): v for k, v in story_stiffness["y"].items()},
            "story_stiffness_method": "elastic static analysis, NSCP Eqs. 208-15 to 208-17 lateral force distribution",
        },
        "structure_level": {
            "pass": structure_level_pass,
            "roof_displacement_x_m": tracker.peak_roof["x"],
            "roof_displacement_y_m": tracker.peak_roof["y"],
            "roof_displacement_limit_m": roof_limit_m,
            "roof_displacement_exceeds_limit": roof_exceeds,
            "mean_stress_mpa": mean_stress_mpa,
            "mean_stress_exceeds_yield": mean_stress_exceeds,
            "mean_stress_threshold_mpa": MEAN_STRESS_APPROACH_FRACTION * fy_mpa,
            "max_torsional_irregularity_ratio": max_torsion_ratio,
            "torsional_irregularity_ratio_limit": TORSIONAL_IRREGULARITY_RATIO_LIMIT,
            "torsional_irregularity": torsional_irregularity,
            "torsion_detail": torsion_detail,
        },
        "pass": element_level_pass and floor_level_pass and structure_level_pass,
    }
