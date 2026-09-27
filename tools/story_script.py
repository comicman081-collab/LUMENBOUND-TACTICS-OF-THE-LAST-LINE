"""Compile the authored story scripts (``data_source/story_script/*.json``).

One script is one chapter (see ``docs/STORY_SCRIPT_FORMAT.md``).  This module
turns it into the runtime contracts that already exist:

* scenarios (``ScenarioRunner`` commands) with automatic portrait staging;
* chapter story triggers (``AppState.queue_story_event``);
* map pre-battle dialogue pages (companion / wanderer / anomaly / boss);
* map incidents (random events while moving on the chapter map);
* localization rows (Korean on screen, English fallback).

It is pure build-time Python with no Godot dependency so the generator and the
contract tests audit the same text.
"""
from __future__ import annotations

import json
from pathlib import Path

BACKGROUNDS = {
    "tunnel": "bg_lantern_tunnel_dev",
    "rail": "bg_ch01_glass_rail_story",
    "cathedral": "bg_ch01_signal_cathedral_story",
}
SCENE_IDS = ("PROLOGUE", "INTRO", "MID_A", "MID_B", "CAMP", "PREBOSS", "OUTRO", "HARD_INTRO", "HARD_OUTRO")
# Starters keep the speaker keys the voice cast already uses.
PARTY_SPEAKER_KEYS = {
    "CHR001": "SPEAKER_MAERU", "CHR002": "SPEAKER_ROAN", "CHR003": "SPEAKER_NARIN",
    "CHR004": "SPEAKER_EDA", "CHR005": "SPEAKER_SOREN", "CHR008": "SPEAKER_IRI",
}
VOICE_SPEAKER_KEYS = {
    "N": "SPEAKER_ROUTEKEEPER", "CONTROL": "SPEAKER_CONTROL", "SIO": "SPEAKER_SIO",
    "SURVIVOR": "SPEAKER_SURVIVOR", "ECHO": "SPEAKER_ECHO",
    "EAST_KING": "SPEAKER_EAST_KING", "WEST_KING": "SPEAKER_WEST_KING",
}
SPEAKER_NAMES = {
    "SPEAKER_EDA": ("에다", "Eda"),
    "SPEAKER_CONTROL": ("종착 관제", "Terminus Control"),
    "SPEAKER_SIO": ("시오", "Sio"),
    "SPEAKER_SURVIVOR": ("생존자", "Survivor"),
    "SPEAKER_ECHO": ("잔향체", "Echoform"),
    "SPEAKER_EAST_KING": ("동부선 노선왕", "Sovereign of the Eastern Line"),
    "SPEAKER_WEST_KING": ("서부선 노선왕", "Sovereign of the Western Line"),
}
POPUP_KEYS = ("RECRUIT", "WANDERER", "BOSS", "HARD_BOSS", "ANOMALY_1", "ANOMALY_2", "ANOMALY_3")
INCIDENT_OUTCOMES = {
    "AMBUSH": ("FIGHT", "EVADE"),
    "DISTRESS": ("RESCUE", "RECORD"),
    "STORM": ("SHELTER", "PUSH"),
    "CACHE": ("TAKE",),
    "BANTER": ("CONTINUE",),
    "ECHO": ("LISTEN", "IGNORE"),
}
SLOT_PREFERENCE = ("RIGHT", "LEFT", "CENTER")
# Expression states carried on portrait slots (scenario metadata; a line may name one with "e").
EXPRESSIONS = ("NEUTRAL", "SMILE", "SAD", "ALERT", "SERIOUS", "RESOLVED", "CONCERNED", "BATTLE_FOCUS", "RELIEVED")


def _tone(ko: str, scene_id: str) -> str:
    """Expression implied by a line's wording, or "" to keep the current one."""
    text = ko.strip()
    if any(word in text for word in ("미안", "잃", "눈물", "울고", "울지")):
        return "SAD"
    if text.startswith("……"):
        return "SERIOUS"
    if any(word in text for word in ("다행", "고마", "하하", "후후", "웃")):
        return "SMILE"
    if text.endswith("!"):
        return "BATTLE_FOCUS" if scene_id in ("PREBOSS", "HARD_INTRO") else "ALERT"
    if text.endswith("?"):
        return "CONCERNED"
    return ""


def load_scripts(source_root: Path) -> dict[str, dict]:
    scripts: dict[str, dict] = {}
    folder = source_root / "story_script"
    if not folder.exists():
        return scripts
    for path in sorted(folder.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        scripts[str(data["chapter_id"])] = data
    return scripts


class StoryContext:
    """Chapter facts the compiler needs from the campaign blueprint."""

    def __init__(self, character_codes: dict[str, str], boss_pairs: dict[str, tuple[str, str]],
                 boss_name_keys: dict[str, tuple[str, str]], required_normal: dict[str, list[int]],
                 enemy_name_keys: dict[str, str]):
        self.character_codes = character_codes
        self.boss_pairs = boss_pairs
        self.boss_name_keys = boss_name_keys
        self.required_normal = required_normal
        self.enemy_name_keys = enemy_name_keys

    def speaker_key(self, chapter_id: str, code: str) -> str:
        if code in PARTY_SPEAKER_KEYS:
            return PARTY_SPEAKER_KEYS[code]
        if code.startswith("CHR"):
            return f"CHAR_{self.character_codes[code]}_NAME"
        if code in ("BOSS", "HBOSS"):
            return self.boss_name_keys[chapter_id][0 if code == "BOSS" else 1]
        if code in VOICE_SPEAKER_KEYS:
            return VOICE_SPEAKER_KEYS[code]
        raise ValueError(f"{chapter_id}: unknown speaker code {code!r}")

    def portrait(self, chapter_id: str, code: str) -> str:
        if code.startswith("CHR"):
            return f"portrait_{code.lower()}_dev"
        if code in ("BOSS", "HBOSS"):
            enemy_id = self.boss_pairs[chapter_id][0 if code == "BOSS" else 1]
            return f"enemy_{enemy_id.lower()}_dev"
        return ""


def _set_loc(loc: dict, key: str, line: dict) -> None:
    ko = str(line["ko"]).strip()
    en = str(line.get("en", "")).strip() or ko
    loc[key] = (ko, en)


class _SceneCompiler:
    def __init__(self, ctx: StoryContext, chapter_id: str, scene: dict, loc: dict):
        self.ctx = ctx
        self.chapter_id = chapter_id
        self.scene = scene
        self.loc = loc
        self.commands: list[dict] = []
        self.slots: dict[str, str] = {}
        self.expressions: dict[str, str] = {}
        self.expression_changes = 0
        self.last_speaker_slot = ""
        self.exits: set[int] = set()
        self.last_spoke: dict[str, int] = {}
        self.clock = 0
        self.line_number = 0
        self.choice_number = 0
        self.pending_label = ""
        prologue = chapter_id == "PROLOGUE"
        self.key_prefix = "STORY_PROLOGUE" if prologue else f"STORY_{chapter_id}_{scene['id']}"

    def emit(self, command: dict) -> None:
        if self.pending_label:
            command = {"id": self.pending_label, **command}
            self.pending_label = ""
        self.commands.append(command)

    def _asset_for_cast(self, code: str | None) -> str:
        if not code:
            return ""
        return self.ctx.portrait(self.chapter_id, code)

    def show(self, slot: str, asset_id: str) -> None:
        self.emit({"command": "show_portrait", "slot": slot, "asset_id": asset_id, "expression": "NEUTRAL"})
        self.slots[slot] = asset_id
        self.expressions[slot] = "NEUTRAL"
        self.last_spoke[slot] = self.clock

    def hide(self, slot: str) -> None:
        self.emit({"command": "hide_portrait", "slot": slot})
        self.slots.pop(slot, None)

    def apply_cast(self, cast: dict) -> None:
        for slot, code in cast.items():
            asset_id = self._asset_for_cast(code)
            if asset_id:
                if self.slots.get(slot) != asset_id:
                    self.show(slot, asset_id)
            elif slot in self.slots:
                self.hide(slot)

    def stage(self, asset_id: str) -> None:
        for slot, staged in self.slots.items():
            if staged == asset_id:
                self.last_spoke[slot] = self.clock
                return
        empty = [slot for slot in SLOT_PREFERENCE if slot not in self.slots]
        slot = empty[0] if empty else min(SLOT_PREFERENCE, key=lambda s: self.last_spoke.get(s, -1))
        self.show(slot, asset_id)

    def express(self, asset_id: str, expression: str) -> None:
        slot = next((slot for slot, staged in self.slots.items() if staged == asset_id), "")
        if not slot:
            return
        self.last_speaker_slot = slot
        if expression and expression != self.expressions.get(slot):
            self.emit({"command": "set_expression", "slot": slot, "expression": expression})
            self.expressions[slot] = expression
            self.expression_changes += 1

    def line(self, line: dict) -> None:
        code = str(line["s"])
        self.clock += 1
        self.line_number += 1
        text_key = f"{self.key_prefix}_{self.line_number:02d}"
        _set_loc(self.loc, text_key, line)
        portrait = self.ctx.portrait(self.chapter_id, code)
        if portrait:
            self.stage(portrait)
            self.express(portrait, str(line.get("e") or _tone(str(line["ko"]), str(self.scene["id"]))))
        command = {
            "command": "narration" if code == "N" else "dialogue",
            "speaker_key": self.ctx.speaker_key(self.chapter_id, code),
            "text_key": text_key,
        }
        if portrait:
            command["portrait_asset_id"] = portrait
        self.emit(command)
        if portrait and id(line) in self.exits:
            slot = next((slot for slot, staged in self.slots.items() if staged == portrait), "")
            if slot:
                self.hide(slot)

    def choice(self, options: list[dict]) -> None:
        self.choice_number += 1
        number = self.choice_number
        labels = [f"c{number}_{chr(97 + index)}" for index in range(len(options))]
        end_label = f"c{number}_end"
        choices = []
        for index, option in enumerate(options):
            text_key = str(option.get("key") or f"{self.key_prefix}_CHOICE{number}_{chr(65 + index)}")
            self.loc[text_key] = (str(option["ko"]).strip(), str(option.get("en", "")).strip() or str(option["ko"]))
            entry = {"text_key": text_key, "target": labels[index]}
            if option.get("flag"):
                entry["set_flag"] = str(option["flag"])
            choices.append(entry)
        self.emit({"command": "choice", "choices": choices})
        saved = dict(self.slots)
        saved_expressions = dict(self.expressions)
        touched: set[str] = set()
        for index, option in enumerate(options):
            self.slots = dict(saved)
            self.expressions = dict(saved_expressions)
            self.pending_label = labels[index]
            for reply in option.get("reply", []):
                self.item(reply)
            self.emit({"command": "jump", "target": end_label})
            touched.update(slot for slot in set(self.slots) | set(saved) if self.slots.get(slot) != saved.get(slot))
        # Every branch merges into the same staging it started from.
        self.slots = {}
        self.expressions = dict(saved_expressions)
        self.pending_label = end_label
        for slot in SLOT_PREFERENCE:
            if slot not in touched:
                if slot in saved:
                    self.slots[slot] = saved[slot]
                continue
            if slot in saved:
                self.show(slot, saved[slot])
            else:
                self.emit({"command": "hide_portrait", "slot": slot})

    def item(self, item: dict) -> None:
        if "choice" in item:
            self.choice(item["choice"])
        elif "cast" in item and "s" not in item:
            self.apply_cast(item["cast"])
        else:
            self.line(item)

    def _opening_cast(self) -> dict:
        if self.scene.get("cast"):
            return dict(self.scene["cast"])
        # Stage the first speakers so the scene opens as an ensemble instead of
        # portraits popping in one by one.  Later arrivals still enter on cue.
        cast: dict = {}
        for item in self.scene["lines"][:4]:
            if "s" not in item:
                break
            portrait = self.ctx.portrait(self.chapter_id, str(item["s"]))
            if portrait and str(item["s"]) not in cast.values() and len(cast) < 3:
                cast[SLOT_PREFERENCE[len(cast)]] = str(item["s"])
        return cast

    def compile(self) -> list[dict]:
        background = BACKGROUNDS[str(self.scene.get("background", "tunnel"))]
        self.emit({"id": "start", "command": "set_background", "asset_id": background})
        if self.scene.get("cg"):
            self.emit({"command": "set_cg", "asset_id": str(self.scene["cg"])})
        self.apply_cast(self._opening_cast())
        self.emit({"command": "fade_in", "duration": .35})
        if str(self.scene["id"]) in ("OUTRO", "HARD_OUTRO"):
            # A defeated boss leaves the stage after its last words.
            boss_lines = [item for item in self.scene["lines"] if "s" in item and str(item["s"]) in ("BOSS", "HBOSS")]
            if boss_lines and boss_lines[-1] is not self.scene["lines"][-1]:
                self.exits.add(id(boss_lines[-1]))
        for item in self.scene["lines"]:
            self.item(item)
        if not self.expression_changes and self.last_speaker_slot in self.slots:
            # Every scene closes on a settled face even when no line set one.
            self.emit({"command": "set_expression", "slot": self.last_speaker_slot, "expression": "RESOLVED"})
        if self.chapter_id == "PROLOGUE":
            self.emit({"command": "set_flag", "flag": "PROLOGUE_READ", "value": True})
        self.emit({"command": "grant_reward", "item_id": "LANTERN_SHARD", "quantity": 5})
        self.emit({"command": "end_scenario"})
        return self.commands


def scenario_id(chapter_id: str, scene_id: str) -> str:
    return "SCN_PROLOGUE" if chapter_id == "PROLOGUE" else f"SCN_{chapter_id}_{scene_id}"


def compile_scenarios(scripts: dict[str, dict], ctx: StoryContext, loc: dict) -> list[dict]:
    result = []
    for chapter_id in sorted(scripts, key=lambda cid: (cid != "PROLOGUE", cid)):
        for scene in scripts[chapter_id].get("scenes", []):
            sid = scenario_id(chapter_id, str(scene["id"]))
            title_key = "SCENARIO_PROLOGUE_TITLE" if chapter_id == "PROLOGUE" else f"SCENARIO_{chapter_id}_{scene['id']}_TITLE"
            loc[title_key] = (str(scene["title_ko"]), str(scene.get("title_en", scene["title_ko"])))
            commands = _SceneCompiler(ctx, chapter_id, scene, loc).compile()
            result.append({
                "id": sid, "title_key": title_key, "chapter_id": chapter_id,
                "presentation": "CINEMATIC", "commands": commands,
            })
    return result


def _stage_rank(trigger: str) -> int:
    if trigger == "MAP_ENTER":
        return 0
    return int(trigger[1:]) + (0 if trigger.startswith("N") else 20)


def compile_triggers(scripts: dict[str, dict], ctx: StoryContext) -> list[dict]:
    triggers = []
    for chapter_id in sorted(cid for cid in scripts if cid != "PROLOGUE"):
        number = int(chapter_id[2:])
        scenes = list(enumerate(scripts[chapter_id].get("scenes", [])))
        scenes.sort(key=lambda pair: (_stage_rank(str(pair[1]["trigger"])), pair[0]))
        for order, (_index, scene) in enumerate(scenes):
            code = str(scene["trigger"])
            if code != "MAP_ENTER" and code.startswith("N") and int(code[1:]) not in ctx.required_normal[chapter_id]:
                raise ValueError(f"{chapter_id} {scene['id']}: trigger {code} is an optional branch")
            trigger_id = f"TRIG_{chapter_id}_{scene['id']}"
            triggers.append({
                "id": trigger_id, "event": "MAP_ENTER" if code == "MAP_ENTER" else "STAGE_CLEAR",
                "stage_id": "" if code == "MAP_ENTER" else f"{chapter_id}-{code}",
                "scenario_id": scenario_id(chapter_id, str(scene["id"])),
                "completion_flag": f"story.trigger.{trigger_id}",
                "priority": number * 1000 + (order + 1) * 10,
            })
    return triggers


def compile_pages(ctx: StoryContext, chapter_id: str, key_prefix: str, lines: list[dict], loc: dict,
                  enemy_id: str = "") -> list[dict]:
    """Map dialogue pages.  Each page is one voiced line with its own speaker art."""
    pages = []
    for number, line in enumerate(lines, 1):
        code = str(line["s"])
        text_key = f"{key_prefix}_DIALOGUE_{number:02d}"
        _set_loc(loc, text_key, line)
        if code.startswith("CHR"):
            page = {"speaker_kind": "COMPANION", "speaker_id": code}
        elif code in ("BOSS", "HBOSS"):
            page = {"speaker_kind": "ENEMY", "speaker_id": ctx.boss_pairs[chapter_id][0 if code == "BOSS" else 1]}
        elif code == "ENEMY":
            page = {"speaker_kind": "ENEMY", "speaker_id": enemy_id}
        elif code == "N":
            page = {"speaker_kind": "NARRATION", "speaker_id": ""}
        else:
            page = {"speaker_kind": "VOICE", "speaker_id": ""}
        page["text_key"] = text_key
        if code == "ENEMY":
            page["speaker_key"] = ctx.enemy_name_keys[enemy_id]
            page["portrait_asset_id"] = f"enemy_{enemy_id.lower()}_dev"
        else:
            page["speaker_key"] = ctx.speaker_key(chapter_id, code)
            page["portrait_asset_id"] = ctx.portrait(chapter_id, code)
        pages.append(page)
    return pages


def compile_incidents(ctx: StoryContext, chapter_id: str, incidents: list[dict], loc: dict) -> list[dict]:
    result = []
    for incident in incidents:
        kind = str(incident["kind"])
        prefix = f"MAP_INCIDENT_{chapter_id}_{kind}"
        loc[f"{prefix}_TITLE"] = (str(incident["title_ko"]), str(incident.get("title_en", incident["title_ko"])))
        choices = []
        authored = {str(choice["outcome"]): choice for choice in incident.get("choices", [])}
        for outcome in INCIDENT_OUTCOMES[kind]:
            choice = authored.get(outcome)
            if choice is None:
                raise ValueError(f"{chapter_id} incident {kind} is missing outcome {outcome}")
            label_key = f"{prefix}_CHOICE_{outcome}"
            loc[label_key] = (str(choice["ko"]), str(choice.get("en", choice["ko"])))
            choices.append({"outcome": outcome, "label_key": label_key})
        result.append({
            "incident_id": f"INC_{chapter_id}_{kind}", "kind": kind,
            "title_key": f"{prefix}_TITLE",
            "lines": compile_pages(ctx, chapter_id, prefix, incident["lines"], loc),
            "choices": choices,
        })
    return result


def speaker_localization() -> dict[str, tuple[str, str]]:
    return dict(SPEAKER_NAMES)


def validate_script(script: dict, allowed_characters: set[str]) -> list[str]:
    """Structural checks shared by the generator and the contract tests."""
    errors: list[str] = []
    chapter_id = str(script.get("chapter_id", "?"))
    allowed = set(VOICE_SPEAKER_KEYS) | {"BOSS", "HBOSS", "ENEMY"} | allowed_characters

    def check_line(line: dict, where: str) -> None:
        if "choice" in line:
            for option in line["choice"]:
                if not option.get("ko"):
                    errors.append(f"{chapter_id} {where}: choice without text")
                for reply in option.get("reply", []):
                    check_line(reply, where)
            return
        if "cast" in line and "s" not in line:
            return
        if str(line.get("s", "")) not in allowed:
            errors.append(f"{chapter_id} {where}: speaker {line.get('s')!r}")
        if not str(line.get("ko", "")).strip() or not str(line.get("en", "")).strip():
            errors.append(f"{chapter_id} {where}: missing ko/en")
        if line.get("e") and str(line["e"]) not in EXPRESSIONS:
            errors.append(f"{chapter_id} {where}: expression {line['e']!r}")

    for scene in script.get("scenes", []):
        if str(scene.get("id")) not in SCENE_IDS:
            errors.append(f"{chapter_id}: unknown scene id {scene.get('id')}")
        if str(scene.get("background", "tunnel")) not in BACKGROUNDS:
            errors.append(f"{chapter_id} {scene.get('id')}: background {scene.get('background')}")
        for line in scene.get("lines", []):
            check_line(line, str(scene.get("id")))
    for key, lines in script.get("popups", {}).items():
        if key not in POPUP_KEYS:
            errors.append(f"{chapter_id}: unknown popup {key}")
        for line in lines:
            check_line(line, key)
    for incident in script.get("incidents", []):
        if str(incident.get("kind")) not in INCIDENT_OUTCOMES:
            errors.append(f"{chapter_id}: unknown incident {incident.get('kind')}")
        for line in incident.get("lines", []):
            check_line(line, str(incident.get("kind")))
    return errors
