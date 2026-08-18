# Asset Contract

SD 최종 계약은 512×512 RGBA PNG, foot anchor (0.50, 0.88), 기본 12 FPS, sheet 최대 2048×2048이다. idle 8, move 12, basic 8, normal 12, ultimate 18, hit 4, down 8, victory 10프레임 이상이 필요하다. MIRROR_SAFE만 flip_h를 허용한다.

전투 방향 계약은 정면 캐릭터 일러스트와 분리한다. 아군은 화면 왼쪽에 배치하고 `THREE_QUARTER_RIGHT_DOWN_30` 시점으로 오른쪽 아래를 바라본다. 적은 화면 오른쪽에 배치하고 `THREE_QUARTER_LEFT_DOWN_30` 시점으로 왼쪽 아래를 바라본다. 머리, 시선, 흉곽, 골반, 발끝, 장비의 진행축이 모두 같은 방향이어야 한다. 단순히 눈동자만 옆으로 움직인 정면 이미지는 전투 방향 자산으로 인정하지 않는다.

비대칭 장비·문양·문자·한쪽 장식이 있는 캐릭터는 `SEPARATE_LEFT_RIGHT`이며 `flip_h`가 금지된다. 대칭인 비인간 적만 명시적인 `MIRROR_SAFE` 검증 후 반전할 수 있다. 아군 전투 정본과 적 전투 정본은 각각 별도 경로에 저장한다.

애니메이션 중에도 512×512 공통 캔버스와 발 기준점을 유지한다. 이동/공격의 전진감은 캔버스 크롭 변경이 아니라 포즈와 루트 변위 메타데이터로 표현한다. 피해 판정 프레임은 시각 이벤트일 뿐이며 실제 피해는 계속 30 Hz 전투 시뮬레이션 이벤트가 결정한다.

현재 `BattleView`의 코드 도형과 동기화한 Three.js PNG/sheet는 전부 `DEV_PLACEHOLDER`다. 기존 walk sheet가 최종 8개 애니메이션 계약을 충족한다고 보고하지 않는다. 피해 시점은 animation frame이 아닌 시뮬레이션 event다.

`DEV_ANIMATION_DERIVATION`은 방향 후보에서 결정론적으로 만든 런타임 검증용 모션이다. 8종 프레임 수, 12 FPS, 발 고정, 이벤트 연결을 검증할 수 있지만 손으로 그린 관절/머리카락/의상 2차 동작을 대체하는 최종 제작 애니메이션으로 보고하지 않는다.

스토리는 1920×1080 정적 배경/CG, 1024×1536 투명 portrait, 512 icon, 256 UI/skill/material icon 계약이다. Live2D, 반복 호흡, 자동 패닝/확대, 런타임 TTS를 사용하지 않는다.
