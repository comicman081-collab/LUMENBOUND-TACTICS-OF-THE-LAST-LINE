#!/usr/bin/env python3
"""Evaluate the completed R15 BattleSimulation matrix against stated goals.

This is deliberately a report reader.  It has no access to source balance data,
so a failed target cannot be hidden by the evaluator itself.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "reports" / "r15"
DEFAULT_MATRIX = REPORTS / "R15_CH01_BALANCE_MATRIX_HEALTH_GATED_AOE2_CADENCE30.json"
DEFAULT_OUT = REPORTS / "R15_BALANCE_TARGET_AUDIT_HEALTH_GATED_AOE2_CADENCE30.json"

TARGETS = {
    ("CH01-N01", "AUTO"): {"win": (0.95, 1.00), "time": (15.0, 30.0)},
    ("CH01-N03", "AUTO"): {"win": (0.90, 0.98)},
    ("CH01-N05", "AUTO"): {"win": (0.85, 0.95), "time": (25.0, 50.0)},
    ("CH01-N07", "AUTO"): {"win": (0.78, 0.92)},
    ("CH01-N09", "AUTO"): {"win": (0.72, 0.88)},
    ("CH01-N10", "AUTO"): {"win": (0.70, 0.88), "time": (45.0, 75.0)},
    ("CH01-N10", "SCRIPTED_MANUAL_ULTIMATE"): {"win": (0.85, 0.97)},
    ("CH01-H01", "AUTO"): {"win": (0.60, 0.80)},
    ("CH01-H02", "AUTO"): {"win": (0.55, 0.75)},
    ("CH01-H03", "AUTO"): {"win": (0.45, 0.70)},
    ("CH01-H04", "AUTO"): {"win": (0.35, 0.60)},
    ("CH01-H05", "AUTO"): {"win": (0.25, 0.55), "time": (60.0, 88.0)},
    ("CH01-H05", "SCRIPTED_MANUAL_ULTIMATE"): {"win": (0.45, 0.75), "time": (60.0, 88.0)},
}


def within(value: float, bounds: tuple[float, float]) -> bool:
    return bounds[0] <= value <= bounds[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    matrix = args.matrix if args.matrix.is_absolute() else ROOT / args.matrix
    out = args.output if args.output.is_absolute() else ROOT / args.output
    if not matrix.exists():
        raise SystemExit(f"R15 balance matrix missing: {matrix}")
    data = json.loads(matrix.read_text(encoding="utf-8"))
    cells = {(str(c["stage_id"]), str(c["control"])): c for c in data.get("cells", []) if str(c.get("profile")) == "RECOMMENDED"}
    rows = []
    for key, targets in TARGETS.items():
        cell = cells.get(key)
        reasons = []
        if cell is None:
            reasons.append("missing recommended matrix cell")
            rows.append({"stage_id": key[0], "control": key[1], "verdict": "UNVERIFIED", "reasons": reasons})
            continue
        if "win" in targets and not within(float(cell["win_rate"]), targets["win"]):
            reasons.append(f"win {float(cell['win_rate']):.3f} outside {targets['win'][0]:.3f}-{targets['win'][1]:.3f}")
        if "time" in targets and not within(float(cell["mean_time"]), targets["time"]):
            reasons.append(f"mean_time {float(cell['mean_time']):.3f} outside {targets['time'][0]:.1f}-{targets['time'][1]:.1f}")
        rows.append({
            "stage_id": key[0], "control": key[1], "runs": cell["runs"], "win_rate": cell["win_rate"], "mean_time": cell["mean_time"],
            "targets": targets, "verdict": "PASS" if not reasons else "FAIL", "reasons": reasons,
        })
    result = {
        "matrix_path": str(matrix.relative_to(ROOT)),
        "matrix_runs_per_cell": data.get("runs_per_cell"),
        "matrix_total_runs": data.get("total_runs"),
        "manual_policy": data.get("manual_policy", {}),
        "rows": rows,
        "pass": sum(r["verdict"] == "PASS" for r in rows),
        "fail": sum(r["verdict"] == "FAIL" for r in rows),
        "unverified": sum(r["verdict"] == "UNVERIFIED" for r in rows),
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("pass", "fail", "unverified")}, ensure_ascii=False))
    return 0 if result["fail"] == 0 and result["unverified"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
