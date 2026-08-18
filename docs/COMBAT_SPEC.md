# Combat Specification

- 고정 시뮬레이션: 30 Hz. 화면 표현과 분리.
- 표현 목표: 60 FPS. 1×/2×/3×는 한 화면 프레임에 소비하는 고정 tick 수만 바꾼다.
- 기본 공격/이동/대상/NORMAL/PASSIVE 자동. ULTIMATE는 수동 또는 AUTO.
- 공용 전술 게이지 0~10, 자연 회복 0.40/s. 5개 ULTIMATE 버튼을 항상 표시.
- 기본 90초/3웨이브이며 StageDef가 덮어쓴다.

`BattleSimulation`만 상태·AI·판정·RNG·웨이브·승패를 소유한다. `BattleView`는 `BattleEvent`를 읽어 코드 기반 DEV SD, 투사체, 숫자, HUD를 표현한다. 같은 데이터/seed/명령이면 `JSON.stringify(event_log).sha256_text()`가 동일해야 한다.

피해/회복식은 마스터 프롬프트의 명중, 방어, 레벨, 치명타, 0.97~1.03 편차를 그대로 구현한다. 상성은 `game_data.json/affinity_matrix`에서 읽는다. 보호막은 source별 HP를 갖고 실제 HP보다 먼저 소모된다.

상태이상은 STUN, SILENCE, SLOW, HASTE, TAUNT, DEF_DOWN, ATK_DOWN, DOT, HOT, SHIELD, INVULNERABLE, CLEANSE, DISPEL을 데이터로 정의한다. 보스 저항 필드와 해제 가능 여부를 포함한다.

리플레이 계약: data_version, seed, party snapshot, stage ID, tick timestamp가 있는 command log. 버티컬 슬라이스는 메모리 내 이벤트 해시와 결과에 이를 포함하며 영구 리플레이 UI는 향후 범위다.

