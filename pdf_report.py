from __future__ import annotations

import argparse
import datetime
import io
import json
import os
import re
from collections import Counter
from pathlib import Path
from typing import List, Optional, Tuple

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import Image as PdfImage
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from PIL import Image, ImageChops

import gif_exporter
from input_management import BuildingTopology, MaterialProps, load_w_sections

PICTURE_SIZE = (1600, 1000)
PICTURE_MARGIN_PX = 24
PICTURE_MAX_HEIGHT = 95 * mm
PAGE_MARGIN = 18 * mm
FRAME_PADDING = 6
CONTENT_WIDTH = A4[0] - 2 * PAGE_MARGIN - 2 * FRAME_PADDING
LABEL_WIDTH = 62 * mm
BLUE = colors.HexColor("#155dfc")
TEXT = colors.HexColor("#111827")
MUTED = colors.HexColor("#4b5563")
RULE_LINE = colors.HexColor("#e5e7eb")

RULE_UNITS = {
    1: "member(s)", 2: "column(s)", 3: "member(s)", 4: "floor(s)", 5: "floor and direction case(s)",
    6: "floor(s)", 7: "floor(s)", 8: None, 9: "floor and direction case(s)", 10: None,
}

BODY = ParagraphStyle("body", fontName="Helvetica", fontSize=10, leading=14.5, textColor=TEXT, spaceAfter=7)
NOTE = ParagraphStyle("note", fontName="Helvetica-Oblique", fontSize=8.5, leading=11.5, textColor=MUTED)
TITLE = ParagraphStyle("title", fontName="Helvetica-Bold", fontSize=18, leading=22, textColor=TEXT)
SUBTITLE = ParagraphStyle("subtitle", fontName="Helvetica", fontSize=10, leading=14, textColor=MUTED)
HEADING = ParagraphStyle("heading", fontName="Helvetica-Bold", fontSize=11, leading=14, textColor=BLUE,
                         spaceBefore=10, spaceAfter=4, keepWithNext=1)
CELL = ParagraphStyle("cell", fontName="Helvetica", fontSize=9.5, leading=12, textColor=TEXT)
LABEL = ParagraphStyle("label", parent=CELL, textColor=MUTED)


def _read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def _mm(value_m) -> str:
    return "not available" if value_m is None else f"{value_m * 1000.0:.2f} mm"


def _pct(ratio, digits: int = 3) -> str:
    return "not available" if ratio is None else f"{ratio * 100.0:.{digits}f}%"


def _status(passed: bool) -> str:
    color = "#15803d" if passed else "#b91c1c"
    return f'<font color="{color}"><b>{"PASS" if passed else "FAIL"}</b></font>'


def _floors(values: List[int]) -> str:
    if not values:
        return "none"
    names = [str(int(v)) for v in values]
    if len(names) == 1:
        return "floor " + names[0]
    return "floors " + ", ".join(names[:-1]) + " and " + names[-1]


def _run_label(run_dir: Path) -> str:
    match = re.fullmatch(r"run_(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})(_\d+)?", run_dir.name)
    if match:
        return f"{match.group(1)} {match.group(2)}:{match.group(3)}:{match.group(4)}"
    return run_dir.name


def _iteration_name(index: int) -> str:
    return "Initial Iteration" if index == 0 else f"Iteration {index}"


def _table(rows: List[Tuple[str, str]]) -> Table:
    data = [[Paragraph(label, LABEL), Paragraph(value, CELL)] for label, value in rows]
    table = Table(data, colWidths=[LABEL_WIDTH, CONTENT_WIDTH - LABEL_WIDTH])
    table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, RULE_LINE),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
    ]))
    return table


def _section(title: str, rows: List[Tuple[str, str]]):
    return [Paragraph(title, HEADING), _table(rows)]


def _member_kind(target: str) -> str:
    if target.startswith("brace:"):
        return "braced bay"
    if target.startswith("strut:"):
        return "strut"
    ends = target.split("|")
    if len(ends) == 2 and ends[0].split(",")[0] != ends[1].split(",")[0]:
        return "column"
    return "beam"


def _plural(word: str, count: int) -> str:
    return word if count == 1 else word + "s"


def _feedback_rows(record: dict, iteration: int) -> List[Tuple[str, str]]:
    applied = record.get("applied_feedback")
    if not isinstance(applied, dict):
        return [("Feedback applied", "None. The Initial Iteration is the generated structure before any feedback (the open-loop result)."
                 if iteration == 0 else "None")]
    sizing = applied.get("sizing_mode") or "demand ratio"
    rows = [("Source", f"Evaluation of {_iteration_name(int(applied.get('from_iteration', iteration - 1)))}"),
            ("Sizing", "one step per member (the previous iteration collapsed during the earthquake)"
             if sizing.startswith("one step") else "smallest section meeting the demand ratio")]
    groups = Counter()
    for action in applied.get("actions", []):
        rules = ", ".join(str(int(r)) for r in action.get("rules", []))
        groups[(action.get("action", ""), _member_kind(str(action.get("target", ""))),
                action.get("from"), action.get("to"), rules)] += 1
    lines = []
    for (kind, member, before, after, rules), count in sorted(groups.items(), key=lambda item: -item[1]):
        rule_text = f"Rule {rules}" if "," not in rules else f"Rules {rules}"
        if kind == "add_brace":
            lines.append(f"{count} X-braced {_plural('bay', count)} added ({after}) ({rule_text})")
        elif kind == "add_strut":
            lines.append(f"{count} mid-height {_plural('strut', count)} added ({after}) ({rule_text})")
        else:
            lines.append(f"{count} {_plural(member, count)} upsized {before} to {after} ({rule_text})")
    rows.append(("Changes", "<br/>".join(lines) if lines else "none"))
    limited = applied.get("section_limit_reached") or []
    if limited:
        rows.append(("Section limit reached", f"{len(limited)} member(s) already at W36X529"))
    return rows


def _evaluation_rows(record: dict) -> Tuple[List[Tuple[str, str]], Optional[List[Tuple[str, str]]]]:
    evaluation = record.get("evaluation")
    if not isinstance(evaluation, dict):
        return [("Evaluation", "not available (the analysis produced no results to evaluate)")], None
    element = evaluation.get("element_level") or {}
    floor = evaluation.get("floor_level")
    structure = evaluation.get("structure_level") or {}
    fallback = bool(evaluation.get("gravity_fallback"))
    total = int(element.get("total_elements", 0))
    rows = [("Element level", "%s (%d overstressed, %d buckled, %d ruptured, of %d members)%s" % (
        _status(bool(element.get("pass"))), len(element.get("overstressed_elements", [])),
        len(element.get("buckled_elements", [])), len(element.get("ruptured_elements", [])), total,
        "; from a linear-elastic gravity check" if fallback else ""))]
    if isinstance(floor, dict):
        rows.append(("Floor level", "%s (floors over the drift limit: %s; soft story: %s; mid-story concentration: %s; X/Y imbalance: %s)" % (
            _status(bool(floor.get("pass"))), _floors(floor.get("exceeding_floors", [])),
            _floors(floor.get("soft_story_floors", [])), _floors(floor.get("mid_story_concentration_floors", [])),
            _floors(floor.get("directional_instability_floors", [])))))
    else:
        rows.append(("Floor level", "not evaluated (no seismic analysis)"))
    if fallback:
        rows.append(("Structure level", "%s (mean stress %.2f MPa of %.1f MPa allowed)" % (
            _status(bool(structure.get("pass"))), structure.get("mean_stress_mpa", 0.0),
            structure.get("mean_stress_threshold_mpa", 0.0))))
    else:
        roof = max(structure.get("roof_displacement_x_m", 0.0), structure.get("roof_displacement_y_m", 0.0))
        rows.append(("Structure level", "%s (roof displacement %s of %s allowed; torsion ratio %.2f of %.2f allowed; mean stress %.2f MPa of %.1f MPa allowed)" % (
            _status(bool(structure.get("pass"))), _mm(roof), _mm(structure.get("roof_displacement_limit_m")),
            structure.get("max_torsional_irregularity_ratio", 1.0), structure.get("torsional_irregularity_ratio_limit", 1.2),
            structure.get("mean_stress_mpa", 0.0), structure.get("mean_stress_threshold_mpa", 0.0))))
    triggered = evaluation.get("triggered_rules", [])
    if triggered:
        lines = []
        for entry in triggered:
            number = int(entry.get("rule", 0))
            unit = RULE_UNITS.get(number)
            count = int(entry.get("count", 0))
            lines.append(f"Rule {number}, {entry.get('name', '')}: " + (f"{count} {unit}" if unit else "triggered"))
        rows.append(("Triggered rules", "<br/>".join(lines)))
    else:
        rows.append(("Triggered rules", "none"))
    drift_rows = None
    if isinstance(floor, dict) and floor.get("peak_idr_x_by_floor"):
        idr_x = floor.get("peak_idr_x_by_floor", {})
        idr_y = floor.get("peak_idr_y_by_floor", {})
        drift_rows = [(f"Floor {int(k)}", f"{_pct(idr_x[k])} / {_pct(idr_y.get(k))}")
                      for k in sorted(idr_x, key=lambda key: int(key))]
    return rows, drift_rows


def _join(items: List[str]) -> str:
    if len(items) <= 1:
        return "".join(items)
    return ", ".join(items[:-1]) + " and " + items[-1]


def _deficiencies(evaluation: dict, fy_mpa: float) -> List[str]:
    element = evaluation.get("element_level") or {}
    floor = evaluation.get("floor_level") or {}
    structure = evaluation.get("structure_level") or {}
    reasons = []
    for entry in evaluation.get("triggered_rules", []):
        number = int(entry.get("rule", 0))
        count = int(entry.get("count", 0))
        if number == 1:
            reasons.append(f"{count} {_plural('member', count)} exceeded the material's {fy_mpa:g} MPa yield strength.")
        elif number == 2:
            reasons.append(f"{count} {_plural('column', count)} exceeded {'its' if count == 1 else 'their'} buckling stress.")
        elif number == 3:
            reasons.append(f"{count} {_plural('member', count)} exceeded the material's "
                           f"{_pct(element.get('rupture_strain', 0.26), 0)} elongation at break.")
        elif number == 4:
            reasons.append(f"{_floors(floor.get('exceeding_floors', [])).capitalize()} swayed beyond the drift limit.")
        elif number == 5:
            soft = floor.get("soft_story_floors", [])
            reasons.append(f"{_floors(soft).capitalize()} {'is a soft story' if len(soft) == 1 else 'are soft stories'}.")
        elif number == 6:
            reasons.append(f"Sway concentrated in the mid-height {_floors(floor.get('mid_story_concentration_floors', []))}.")
        elif number == 7:
            reasons.append(f"{_floors(floor.get('directional_instability_floors', [])).capitalize()} swayed beyond the limit in only one direction.")
        elif number == 8:
            reasons.append(f"The roof moved more than the allowed {_mm(structure.get('roof_displacement_limit_m'))}.")
        elif number == 9:
            reasons.append("The floors twisted beyond the torsion limit (ratio %.2f against %.2f)." % (
                structure.get("max_torsional_irregularity_ratio", 0.0), structure.get("torsional_irregularity_ratio_limit", 1.2)))
        elif number == 10:
            reasons.append(f"The average member stress reached {structure.get('mean_stress_mpa', 0.0) / fy_mpa * 100.0:.1f}% of the yield strength.")
    return reasons


def _in_short(record: dict, evaluation: dict) -> str:
    phase = record.get("collapse_phase")
    if phase == "gravity":
        return "In short, the structure cannot stand under its own loads."
    if phase == "seismic":
        return "In short, the structure did not survive this earthquake."
    element_ok = bool((evaluation.get("element_level") or {}).get("pass"))
    floor_ok = bool((evaluation.get("floor_level") or {}).get("pass"))
    structure_ok = bool((evaluation.get("structure_level") or {}).get("pass"))
    if element_ok and floor_ok and structure_ok:
        return "In short, the frame is strong and stiff enough for this earthquake."
    if not element_ok and floor_ok and structure_ok:
        return "In short, the frame is stiff enough, but some members are not strong enough."
    if element_ok and not floor_ok and structure_ok:
        return "In short, the members are strong enough, but the frame sways too much."
    if element_ok and floor_ok:
        return "In short, the members and floors pass, but the building as a whole does not."
    return "In short, the frame fails more than one group of checks."


def _change_text(before: float, after: float, unit: str, digits: int) -> str:
    if abs(after - before) < 10 ** (-digits):
        return f"stayed at {after:.{digits}f}{unit}"
    verb = "fell" if after < before else "rose"
    return f"{verb} from {before:.{digits}f} to {after:.{digits}f}{unit}"


def _comparison(record: dict, previous: dict, previous_index: int) -> Optional[str]:
    if record.get("peak_stress_mpa") is None or previous.get("peak_stress_mpa") is None:
        return None
    text = f"Compared with {_iteration_name(previous_index)}, peak stress {_change_text(previous['peak_stress_mpa'], record['peak_stress_mpa'], ' MPa', 2)}"
    count_before = len(((previous.get("evaluation") or {}).get("element_level") or {}).get("overstressed_elements", []))
    count_after = len(((record.get("evaluation") or {}).get("element_level") or {}).get("overstressed_elements", []))
    if count_before != count_after:
        text += f", and members above yield {_change_text(count_before, count_after, '', 0)}"
    return text + "."


def _actions_text(applied: dict) -> str:
    upsized = Counter()
    added = Counter()
    for action in applied.get("actions", []):
        kind = action.get("action", "")
        member = _member_kind(str(action.get("target", "")))
        if kind == "add_brace":
            added["X-braced bay"] += 1
        elif kind == "add_strut":
            added["mid-height strut"] += 1
        else:
            upsized[member] += 1
    parts = []
    if upsized:
        parts.append("upsized " + _join([f"{count} {_plural(name, count)}" for name, count in upsized.most_common()]))
    if added:
        parts.append("added " + _join([f"{count} {_plural(name, count)}" for name, count in added.most_common()]))
    return _join(parts)


STOP_REASONS = {
    "all evaluation checks pass": "all evaluation checks passed",
    "no further improvement possible": "no rule could change the structure any further",
    "no evaluation available to drive feedback": "the analysis produced no results for feedback",
}


def _stop_reason_text(reason: str) -> str:
    match = re.fullmatch(r"feedback iteration limit reached \((\d+)\)", reason or "")
    if match:
        return f"the limit of {match.group(1)} feedback iterations was reached"
    return STOP_REASONS.get(reason, reason or "of an unknown reason")


def _interpretation(record: dict, summary: dict, iteration: int, final: bool, fy_mpa: float,
                    previous: Optional[dict] = None, following: Optional[dict] = None) -> List[str]:
    evaluation = record.get("evaluation") if isinstance(record.get("evaluation"), dict) else {}
    phase = record.get("collapse_phase")
    passed = record.get("overall_status") == "PASS"
    if record.get("input_magnitude") is not None:
        quake = f"the simulated magnitude {float(record['input_magnitude']):.1f} earthquake"
        if record.get("input_pga_g"):
            quake += f" (peak ground acceleration {float(record['input_pga_g']):.4f} g)"
    else:
        quake = "the applied ground motion"

    verdict = "<b>PASSES</b>" if passed else "<b>DOES NOT PASS</b>"
    reasons: List[str] = []
    if phase == "gravity":
        reasons.append("It could not carry its own gravity load, so the earthquake was never applied.")
        over = len((evaluation.get("element_level") or {}).get("overstressed_elements", []))
        reasons.append(f"A linear-elastic gravity check found {over} {_plural('member', over)} above the material's {fy_mpa:g} MPa yield strength.")
    elif not passed:
        if phase == "seismic":
            reasons.append(f"The analysis stopped at t = {float(record.get('collapse_time_s') or 0.0):.2f} s, which indicates a collapse.")
        reasons += _deficiencies(evaluation, fy_mpa)
    first = [f"Based on the metrics, this structure {verdict} ProGen's evaluation under {quake}."
             + ("".join(f"<br/>&bull; {reason}" for reason in reasons))]

    second: List[str] = []
    stress = record.get("peak_stress_mpa")
    if stress is not None:
        second.append(f"Peak stress reached {stress:.2f} MPa, {stress / fy_mpa * 100.0:.1f}% of the yield strength.")
    floor = evaluation.get("floor_level") or {}
    idr_x = floor.get("peak_idr_x_by_floor") or {}
    idr_y = floor.get("peak_idr_y_by_floor") or {}
    limit = record.get("drift_limit")
    if (idr_x or idr_y) and limit:
        candidates = [(v, int(k), "X") for k, v in idr_x.items()] + [(v, int(k), "Y") for k, v in idr_y.items()]
        value, level, axis = max(candidates)
        if value <= limit:
            share = f"{value / limit * 100.0:.1f}% of the {_pct(limit, 1)} NSCP limit"
        else:
            share = f"{value / limit:.1f} times the {_pct(limit, 1)} NSCP limit"
        second.append(f"The largest drift ratio is {_pct(value)} on floor {level} ({axis} direction), {share}.")
    structure = evaluation.get("structure_level") or {}
    roof_limit = structure.get("roof_displacement_limit_m")
    if roof_limit and phase is None:
        roof = max(structure.get("roof_displacement_x_m", 0.0), structure.get("roof_displacement_y_m", 0.0))
        second.append(f"The roof moved at most {_mm(roof)} of the {_mm(roof_limit)} allowed.")
    second.append(_in_short(record, evaluation))

    third: List[str] = []
    if iteration == 0:
        third.append("This is the Initial Iteration, the generated structure before any feedback (the open-loop result).")
    elif previous is not None:
        change = _comparison(record, previous, iteration - 1)
        if change:
            third.append(change)
    if final:
        third.append(f"This is the final iteration; the run ended because {_stop_reason_text(summary.get('stop_reason', ''))}.")
    elif following is not None and isinstance(following.get("applied_feedback"), dict):
        actions = _actions_text(following["applied_feedback"])
        if actions:
            third.append(f"Next, ProGen {actions} to produce Iteration {iteration + 1}.")
    elif not passed:
        third.append(f"ProGen's feedback rules act on these results to produce Iteration {iteration + 1}.")

    note = ("These conclusions follow ProGen's simulation and evaluation criteria (the NSCP 2015 drift limit and the "
            "AK Steel Grade 25 properties) and are not a structural design certification.")
    return [" ".join(part) for part in (first, second, third) if part] + [note]


def build_story(run_dir: Path, iteration: int) -> list:
    folder = run_dir / f"iteration_{iteration}"
    record = _read_json(folder / "record.json")
    values = _read_json(run_dir / "input.json")
    if record is None or values is None:
        raise FileNotFoundError(f"iteration_{iteration} or input.json is missing in {run_dir}")
    summary = _read_json(run_dir / "run_summary.json") or {}
    topology = BuildingTopology.from_dict(values)
    material = MaterialProps()
    model_state = record.get("model_state") or {}

    completed = int(summary.get("iterations_completed", 0))
    final = summary.get("status") == "completed" and iteration == completed - 1
    status = record.get("overall_status", "?")
    status_color = "#15803d" if status == "PASS" else "#b91c1c"
    story = [
        Paragraph("ProGen Iteration Report", TITLE),
        Paragraph(f'Run {_run_label(run_dir)} &nbsp;|&nbsp; {_iteration_name(iteration)}{" (final)" if final else ""}'
                  f' &nbsp;|&nbsp; Result: <font color="{status_color}"><b>{status}</b></font>', SUBTITLE),
    ]
    if final and summary.get("stop_reason"):
        story.append(Paragraph(f"Run stopped because: {summary['stop_reason']}", SUBTITLE))
    story.append(Spacer(1, 6))

    picture = gif_exporter.render_still(topology, model_state, *PICTURE_SIZE)
    box = ImageChops.difference(picture, Image.new("RGB", picture.size, (255, 255, 255))).getbbox()
    if box:
        picture = picture.crop((max(box[0] - PICTURE_MARGIN_PX, 0), max(box[1] - PICTURE_MARGIN_PX, 0),
                                min(box[2] + PICTURE_MARGIN_PX, picture.width), min(box[3] + PICTURE_MARGIN_PX, picture.height)))
    buffer = io.BytesIO()
    picture.save(buffer, format="PNG")
    buffer.seek(0)
    scale = min(CONTENT_WIDTH / picture.width, PICTURE_MAX_HEIGHT / picture.height)
    story.append(PdfImage(buffer, width=picture.width * scale, height=picture.height * scale))

    order = [section.name for section in load_w_sections()]
    counts = Counter((model_state.get("member_sections") or {}).values())
    section_lines = [f"{name}: {counts[name]} {_plural('member', counts[name])}" for name in order if counts.get(name)]
    braces = model_state.get("braces") or []
    struts = model_state.get("struts") or []
    story += _section("GENERATION", [
        ("Floors", str(topology.floor_count)),
        ("Bays (X x Y)", f"{topology.bay_count_x} x {topology.bay_count_y}"),
        ("Bay width (X x Y)", f"{topology.bay_width_x_m:.2f} m x {topology.bay_width_y_m:.2f} m"),
        ("Story height", f"{topology.story_height_m:.2f} m"),
        ("Floor load / roof load", f"{topology.floor_load_kpa:g} kN/m² / {topology.roof_load_kpa:g} kN/m²"),
        ("Material", f"AK Steel Grade 25 (yield strength {material.fy_mpa:g} MPa)"),
        ("Member sections", "<br/>".join(section_lines) if section_lines else "not available"),
        ("X-braced bays", str(len(braces))),
        ("Mid-height struts", str(len(struts))),
    ])

    dt = float(record.get("time_step_s") or 0.01)
    record_length = record.get("record_length_s")
    sim_rows = []
    if record.get("source_motion", "stochastic") == "stochastic" and record.get("input_magnitude") is not None:
        sim_rows += [
            ("Magnitude", f"{float(record['input_magnitude']):.1f}"),
            ("Strong-shaking duration", f"{float(record.get('input_duration_s', 0.0)):.1f} s"),
            ("Peak ground acceleration", f"{float(record.get('input_pga_g', 0.0)):.4f} g"),
        ]
    else:
        sim_rows.append(("Ground motion", f"from file {record.get('source_motion', '')}"))
    if record_length is not None:
        total_steps = int(round(float(record_length) / dt)) + 1
        sim_rows.append(("Record length", f"{float(record_length):.2f} s ({total_steps:,} steps of {dt:g} s)"))
        sim_rows.append(("Analysis steps completed", f"{int(record.get('steps', 0)):,} of {total_steps:,}"))
    period = record.get("fundamental_period_s")
    sim_rows.append(("Fundamental period", "not available" if period is None else f"{period:.3f} s"))
    phase = record.get("collapse_phase")
    if phase == "gravity":
        analysis = "collapsed under gravity before the earthquake"
    elif phase == "seismic":
        analysis = f"collapsed during the earthquake at t = {float(record.get('collapse_time_s') or 0.0):.2f} s"
    else:
        analysis = "completed, no collapse"
    sim_rows.append(("Analysis", analysis))
    story += _section("SIMULATION", sim_rows)

    limit = record.get("drift_limit")
    stress = record.get("peak_stress_mpa")
    metric_rows = [
        ("Peak stress", "not available" if stress is None else f"{stress:.2f} MPa (yield {material.fy_mpa:g} MPa)"),
        ("Peak displacement X", _mm(record.get("peak_displacement_m"))),
        ("Peak displacement Y", _mm(record.get("peak_displacement_y_m"))),
        ("Peak deformation", _mm(record.get("peak_deformation_m"))),
        ("Maximum story drift", _mm(record.get("maximum_story_drift_m"))),
        ("Maximum interstory drift ratio", _pct(record.get("maximum_idr")) + ("" if limit is None or record.get("maximum_idr") is None else f" (limit {_pct(limit, 1)})")),
    ]
    if phase == "seismic":
        metric_rows.append(("Note", "values include the response leading up to the collapse"))
    elif phase == "gravity":
        metric_rows.append(("Note", "no seismic metrics: the structure collapsed under gravity"))
    story += _section("PERFORMANCE METRICS", metric_rows)

    evaluation_rows, drift_rows = _evaluation_rows(record)
    story += _section("EVALUATION", evaluation_rows)
    if drift_rows:
        story += _section("EVALUATION: DRIFT BY FLOOR (X / Y)", drift_rows)
    story += _section("FEEDBACK", _feedback_rows(record, iteration))
    previous = _read_json(run_dir / f"iteration_{iteration - 1}" / "record.json") if iteration > 0 else None
    following = _read_json(run_dir / f"iteration_{iteration + 1}" / "record.json")
    story.append(Paragraph("INTERPRETATION", HEADING))
    paragraphs = _interpretation(record, summary, iteration, final, material.fy_mpa, previous, following)
    for text in paragraphs[:-1]:
        story.append(Paragraph(text, BODY))
    story.append(Paragraph(paragraphs[-1], NOTE))
    return story


def export_pdf(run_dir: Path, iteration: int, output: Path) -> None:
    story = build_story(run_dir, iteration)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    footer = f"ProGen  |  {run_dir.name}  |  {_iteration_name(iteration)}  |  created {stamp}"

    def draw_footer(canvas, document):
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        canvas.setFillColor(MUTED)
        canvas.drawString(PAGE_MARGIN, 10 * mm, footer)
        canvas.drawRightString(A4[0] - PAGE_MARGIN, 10 * mm, f"Page {document.page}")
        canvas.restoreState()

    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_name(output.name + ".tmp")
    document = SimpleDocTemplate(str(temp), pagesize=A4, leftMargin=PAGE_MARGIN, rightMargin=PAGE_MARGIN,
                                 topMargin=PAGE_MARGIN, bottomMargin=PAGE_MARGIN + 4 * mm,
                                 title=f"ProGen {_iteration_name(iteration)} Report", author="ProGen")
    document.build(story, onFirstPage=draw_footer, onLaterPages=draw_footer)
    os.replace(temp, output)


def main() -> None:
    parser = argparse.ArgumentParser(description="Save one iteration of a ProGen run as a PDF report")
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--iteration", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        export_pdf(args.run_dir, args.iteration, args.output)
    except Exception as error:
        print(f"PDF failed: {type(error).__name__}: {error}")
        raise SystemExit(1)
    print(f"saved {args.output}")


if __name__ == "__main__":
    main()
