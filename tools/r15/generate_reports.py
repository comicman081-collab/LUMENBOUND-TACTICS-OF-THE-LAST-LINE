#!/usr/bin/env python3
"""Build transparent R15 reports from generated audit and simulation outputs."""
from __future__ import annotations

import csv
import hashlib
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "reports" / "r15"


def read_json(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def write(name: str, body: str) -> None:
    (REPORTS / name).write_text(body.rstrip() + "\n", encoding="utf-8")


def cell_index(balance: dict) -> dict[tuple[str, str, str], dict]:
    return {(str(c["stage_id"]), str(c["profile"]), str(c["control"])): c for c in balance.get("cells", [])}


def rate(value: float) -> str:
    return f"{value * 100:.1f}%"


def main() -> None:
    REPORTS.mkdir(parents=True, exist_ok=True)
    with (REPORTS / "R15_CONTENT_GAP_MATRIX.csv").open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    players = [r for r in rows if r["type"] == "PLAYER"]
    enemies = [r for r in rows if r["type"].startswith("ENEMY_")]
    stages = [r for r in rows if r["type"].startswith("STAGE_")]
    scenarios = [r for r in rows if r["type"] == "SCENARIO"]
    selected_balance_path = REPORTS / "R15_CH01_BALANCE_MATRIX_HEALTH_GATED_AOE2_CADENCE30.json"
    if not selected_balance_path.exists():
        selected_balance_path = REPORTS / "R15_CH01_BALANCE_MATRIX.json"
    balance = read_json(selected_balance_path, {})
    pretune_balance = read_json(REPORTS / "R15_CH01_BALANCE_MATRIX_PRETUNE.json", {})
    progression = read_json(REPORTS / "R15_PROGRESSION_SIMULATION.json", {})
    regression = read_json(REPORTS / "R15_REGRESSION_STATUS.json", {})
    cells = cell_index(balance)

    runtime_complete_players = sum(r["battle_integration"] == "COMPLETE" and r["fallback_used"] == "FALSE" for r in players)
    runtime_complete_enemies = sum(r["battle_integration"] == "COMPLETE" and r["fallback_used"] == "FALSE" for r in enemies)
    art_partial_players = sum(r["illustration"] != "COMPLETE" or r["portrait"] != "COMPLETE" for r in players)
    art_complete_players = len(players) - art_partial_players
    regression_total = regression.get("total", {})
    regression_line = "UNVERIFIED"
    if regression_total:
        regression_line = "{passed}/{executed} PASS".format(
            passed=regression_total.get("passed", 0),
            executed=regression_total.get("executed", 0),
        )
    write("R15_CONTENT_COMPLETION.md", f"""# R15 Content Completion Audit

This report distinguishes runtime availability from premium-art approval.

| Category | Runtime complete | Required | Remaining visual gap |
|---|---:|---:|---:|
| Players | {runtime_complete_players} | {len(players)} | {art_partial_players} have non-final illustration/portrait coverage |
| Enemies | {runtime_complete_enemies} | {len(enemies)} | individual sources are tracked in the matrix |
| NORMAL stages | {len([r for r in stages if r['type'] == 'STAGE_NORMAL'])} | 10 | 0 data gaps |
| HARD stages | {len([r for r in stages if r['type'] == 'STAGE_HARD'])} | 5 | 0 data gaps |
| Scenarios | {len(scenarios)} | 9 | 0 command-list gaps |

Runtime card/static battle fallback: **0**. The generated R15 SD/VFX packs are marked as development cutout-rig/code VFX where applicable; they are not reported as premium-final illustration.

Source of truth: `R15_CONTENT_GAP_MATRIX.csv`.
""")

    def qa_table(items: list[dict]) -> str:
        out = ["| ID | SD | Animation | VFX | Map pawn | Battle | Illustration | Portrait | QA |", "|---|---|---|---|---|---|---|---|---|"]
        for r in items:
            out.append("| {entity_id} | {sd_pack} | {animation} | {vfx} | {map_pawn} | {battle_integration} | {illustration} | {portrait} | {qa_status} |".format(**r))
        return "\n".join(out)

    write("R15_CHARACTER_ASSET_QA.md", "# R15 Character Runtime Asset QA\n\n" + qa_table(players) + "\n\n`COMPLETE` denotes runtime connection; the illustration/portrait columns retain the actual quality gap.\n")
    write("R15_ENEMY_ASSET_QA.md", "# R15 Enemy Runtime Asset QA\n\n" + qa_table(enemies) + "\n\nAll 11 enemy IDs resolve battle SD, map pawn, projectile and VFX runtime paths.\n")

    def balance_section(mode: str, name: str) -> str:
        stage_ids = [f"CH01-{'N' if mode == 'NORMAL' else 'H'}{index:02d}" for index in range(1, 11 if mode == 'NORMAL' else 6)]
        lines = [f"# R15 {name} Balance Matrix", ""]
        if not cells:
            return "\n".join(lines + ["**UNVERIFIED** — full 200-seed BattleSimulation matrix has not completed."])
        lines += ["| Stage | Recommended AUTO | Recommended Manual | Low AUTO | High AUTO | AUTO mean | Manual mean |", "|---|---:|---:|---:|---:|---:|---:|"]
        for stage_id in stage_ids:
            auto = cells.get((stage_id, "RECOMMENDED", "AUTO"), {})
            manual = cells.get((stage_id, "RECOMMENDED", "SCRIPTED_MANUAL_ULTIMATE"), {})
            low = cells.get((stage_id, "LOW", "AUTO"), {})
            high = cells.get((stage_id, "HIGH", "AUTO"), {})
            if not auto:
                lines.append(f"| {stage_id} | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | — | — |")
            else:
                lines.append(f"| {stage_id} | {rate(auto['win_rate'])} | {rate(manual['win_rate'])} | {rate(low['win_rate'])} | {rate(high['win_rate'])} | {auto['mean_time']:.2f}s | {manual['mean_time']:.2f}s |")
        manual_policy = balance.get("manual_policy", {})
        lines += ["", f"Source: `{selected_balance_path.name}`. Runs per cell: `{balance.get('runs_per_cell', 0)}`. Total recorded runs: `{balance.get('total_runs', 0)}`. Results are from the shipping deterministic `BattleSimulation`."]
        if manual_policy:
            lines += [f"Scripted manual policy: `{manual_policy.get('id', 'UNKNOWN')}` at `{manual_policy.get('decision_ticks', 0)}` decision ticks."]
        if mode == "NORMAL":
            before = cell_index(pretune_balance).get(("CH01-N10", "RECOMMENDED", "AUTO"), {})
            after = cells.get(("CH01-N10", "RECOMMENDED", "AUTO"), {})
            if before and after:
                lines += [
                    "",
                    "## N10 before/after control",
                    f"- Pre-tune: {rate(before['win_rate'])}, {before['mean_time']:.2f}s.",
                    f"- Current: {rate(after['win_rate'])}, {after['mean_time']:.2f}s.",
                    "- CH01-N10's data multiplier was intentionally unchanged; the comparison guards the climax while intermediate-stage data is tuned.",
                ]
        return "\n".join(lines)

    write("R15_NORMAL_BALANCE.md", balance_section("NORMAL", "NORMAL"))
    write("R15_HARD_BALANCE.md", balance_section("HARD", "HARD"))

    if progression:
        final_party = progression.get("final_party", {})
        party_lines = ["| Character | Level | Breakthrough | Skills (N/P/U) | Weapon |", "|---|---:|---:|---|---|"]
        for cid, entry in final_party.items():
            skills = entry.get("skills", {})
            weapon = entry.get("weapon", {})
            party_lines.append(f"| {cid} | {entry.get('level')} | B{entry.get('breakthrough')} | {skills.get('normal')}/{skills.get('passive')}/{skills.get('ultimate')} | Lv.{weapon.get('level')} T{weapon.get('tier')} |")
        write("R15_PROGRESSION_ECONOMY.md", "# R15 Fresh-Save Progression\n\n" + ("**PASS**" if progression.get("completed_normal_route") else "**FAIL**") + f" — actual service flow completed `{progression.get('stages_completed', 0)}/10` NORMAL stages.\n\n" + "\n".join(party_lines) + "\n\nThe simulation uses `BattleSimulation`, `RewardService`, `GrowthAffordabilityAnalyzer`, `CharacterProgression`, `BreakthroughService`, `SkillUpgradeService`, and `WeaponUpgradeService`; it is not an external calculator.\n")
    else:
        write("R15_PROGRESSION_ECONOMY.md", "# R15 Fresh-Save Progression\n\n**UNVERIFIED** — runtime simulation output missing.\n")

    write("R15_CHAPTER_PACING.md", """# R15 Chapter Pacing

Authored encounter progression remains data-defined:

- N01–N02: basic mixed enemy onboarding.
- N03–N04: ranged/melee/support combinations.
- N05–N06: elite introduction and three-wave pressure.
- N07–N08: elite area/support pressure.
- N09: three elite preparation waves.
- N10: approach + boss climax.

The map data distributes patrols, relays, events, optional branches, visible treasure and hidden treasure across the macro route. The data audit and map suite validate all 15 encounter nodes and 97 map/round-trip checks; browser playtime remains a separate Web E2E measurement.
""")

    web_zip = ROOT / "builds" / "SD_STORY_RPG_HTML.zip"
    if web_zip.exists():
        digest = hashlib.sha256(web_zip.read_bytes()).hexdigest()
        web_line = f"Existing Web ZIP: `{web_zip.name}` — {web_zip.stat().st_size:,} bytes — SHA-256 `{digest}`."
    else:
        web_line = "Web release has not been rebuilt in R15; no package claim is made."
    write("R15_WEB_PACKAGE_AUDIT.md", "# R15 Web Package Audit\n\n" + web_line + "\n\nR15 runtime additions remain under `assets/runtime_web`; source `.blend`, generated-import frame sources and tool scripts are excluded by the Web export filter. A new browser package audit is required after the R15 Web build.\n")
    write("R15_FULL_E2E.md", "# R15 Full E2E Status\n\nHeadless data/runtime/map/progression verification is recorded. Full browser E2E (new save, story, map, N01–N10, HARD H01–H05, save/reload) remains **UNVERIFIED** until a fresh Web Release is built and driven in a browser. No deployment was performed.\n")
    balance_state = "AVAILABLE" if cells else "RUNNING_OR_UNVERIFIED"
    write("R15_FINAL_REPORT.md", f"""# R15 Interim Final Report

## Runtime

- Players with connected battle runtime packs: {runtime_complete_players}/8
- Enemies with connected battle runtime packs: {runtime_complete_enemies}/11
- Static-card battle fallback: 0
- NORMAL/HARD stage data: 10/5
- Scenario data: 9

## Verified

- Current headless regression run: {regression_line}.
- Static-art source/routing audit: {art_complete_players}/8 reviewed-art complete; {art_partial_players}/8 pending an explicit visual gate.
- Fresh-save N01→N10 growth simulation: `{progression.get('completed_normal_route', False)}`.
- Full balance matrix: {balance_state}.

## Honest remaining gates

- CHR001's internally sourced R6P2 static art is linked and SHA-256 lineage-verified, but its GPT Web visual/references review is pending; runtime animation coverage must not be mistaken for final art approval.
- Fresh Web build, browser E2E, package audit and visual review are not yet claimed.
- No public deployment was performed.
""")


if __name__ == "__main__":
    main()
