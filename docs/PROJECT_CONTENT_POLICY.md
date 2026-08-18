# 프로젝트 전역 콘텐츠 정책

상태: `IMMUTABLE_PROJECT_CONSTRAINT`, 버전 1.

이 프로젝트의 인간 및 인간형 캐릭터는 전부 명확한 성인 여성으로 제작한다. 플레이어 캐릭터, 스토리 등장인물, NPC, 정적 일러스트, SD 모델, 초상화, 아이콘, 생성형 콘셉트와 Blender 모델링 가이드에 남성 캐릭터를 만들거나 추가하지 않는다. 비인간 적은 성별 없는 기계·잔향체·이상체로만 제작한다.

모든 일러스트·SD·인게임 의상은 `MAXIMUM_NON_EXPLICIT` 노출도를 공통 목표로 한다. 성인 여성 판독성을 유지하는 고노출 판타지 전투복을 사용하되, 성기·유두 등 친밀 신체 부위는 가리고 노골적 성행위 표현은 사용하지 않는다. 치비 비율에서도 아동·청소년·교복·유아 체형으로 읽히는 디자인은 금지한다.

이 규칙은 다음 단계에서 동시에 강제한다.

- `CharacterDef.gender`는 항상 `FEMALE`이다.
- `CharacterDef.age_category`는 항상 `ADULT`이고 `attire_policy`는 항상 `MAXIMUM_NON_EXPLICIT`이다.
- 비인간 적의 `gender`는 `GENDERLESS_NONHUMAN`이다.
- 캐릭터 생성용 positive prompt에는 `adult woman`을 명시한다.
- 캐릭터 생성용 positive prompt에서 남성 지시어를 차단한다.
- 프롬프트만으로 판정을 보증하지 않는다. `FEMALE_CONFIRMED`, `ADULT_CONFIRMED`, `ATTIRE_POLICY_CONFIRMED` 시각 QA가 모두 없는 결과는 활성 자산이나 Blender·Godot에 연결하지 않는다.
- 콘셉트 manifest와 Blender reference collection에 `FEMALE_ONLY` 정책을 기록하고 검증한다.
- 정적 검증 실패 시 빌드·자산 생성 승인을 중단한다.

정본 기계 판독 정책은 `tools/policy/project_content_policy.json`이다. 제작 편의를 위한 예외는 허용하지 않는다.
