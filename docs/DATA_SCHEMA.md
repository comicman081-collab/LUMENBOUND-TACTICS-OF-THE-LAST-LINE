# Data Schema

정본은 `data_source/*.csv|json`, 런타임은 `godot/data/compiled/game_data.json`이다. `tools/generate_data.py`가 round-half-up 규칙으로 결정론적으로 생성한다. 빌드된 게임은 Python을 필요로 하지 않는다.

모든 레코드는 영구 ID, localization key, 간접 asset ID를 사용한다. 저장에는 표시 이름이 아닌 ID만 기록한다. 중복 ID, 끊긴 참조, 배열 길이, 수량 부호, 챕터 구조는 정적 및 Godot 헤드리스 러너가 검사한다.

Resource 계약은 `godot/data/definitions/`의 CharacterDef, CharacterArchetypeDef, SkillDef, WeaponDef, EnemyDef, StageDef, ChapterDef, RewardTableDef, ItemDef, ScenarioDef, StatusEffectDef, AffinityMatrixDef에 선언되어 있다. 현재 런타임은 빠른 오프라인 로드를 위해 검증된 JSON을 사용한다.

