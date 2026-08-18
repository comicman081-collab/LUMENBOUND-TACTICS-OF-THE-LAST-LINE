# License Policy

Godot Engine의 MIT 라이선스와 게임/제3자 자산 라이선스를 분리해 표시한다. 외부 파일마다 source, author, license, modification, commercial_use, attribution_required, file_sha256를 요구한다.

로컬 `asset_share` 팩토리 코드의 package license는 MIT지만 개별 output manifest에는 자산 권리 필드가 없다. 따라서 동기화 결과는 `MANIFEST_NOT_DECLARED`, `commercial_use=false`, `attribution_required=true`로 보수적으로 기록했다. 권리 확인 전 상업 이용 가능이라고 주장하지 않는다.

로컬 AI 모델은 `tools/local_art_pipeline/model_policy.json`의 허용 목록만 빌드 시점에 사용할 수 있다. `C:\AI_MODELS`와 `C:\AI_ENVS`의 원본 및 연결 자산은 읽기 전용으로 취급하며 게임에 포함하지 않는다. Apache-2.0 또는 Open RAIL 계열이라는 사실은 개별 출력물의 제3자 권리·상표·초상·저작권 안전을 자동 보증하지 않는다. Krea2, 권리 불명 모델, OpenPose 조건 모델, InsightFace 계열 pretrained weights는 금지 목록으로 유지한다.

최종 앱 설정에서 라이선스 화면을 열 수 있다. 네트워크 스트리밍·원격 생성 API·온라인 TTS는 없다.

Web 배포 파일 크기 제한을 위한 WASM gzip fallback에는 로컬에 설치된 pako
`pako_inflate.min.js`(MIT License, nodeca/pako)를 사용한다. 해당 파일은 빌드
시점에만 복사되며, 브라우저에서는 gzip WASM을 메모리에서 해제하는 용도다.
