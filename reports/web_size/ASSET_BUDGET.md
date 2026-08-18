# Web Art Pilot Asset Budget

## 판정

- 기준 ZIP: 219,207,871 bytes
- R2 파일럿 ZIP: 343,286,085 bytes
- 증가량: 124,078,214 bytes (56.60%)
- 권장 상한: 300,000,000 bytes
- 결과: **FAIL / OVER_BUDGET**

R2는 테스트, 제작 스크립트, 미사용 전신·반신·프로필 카드와 QA 산출물을 Web export에서 제외해 R1보다 9,361,729 bytes 줄였다. 그러나 `index.pck`가 334,091,952 bytes로 여전히 대부분을 차지한다.

## 다음 최적화 우선순위

1. PCK 내부 PNG의 중복 콘텐츠 해시 감사
2. 사용하지 않는 legacy fallback과 import 변형 제외
3. SD 프레임의 무손실 atlas 재패킹
4. 초기 로드와 후속 챕터 리소스 분리
5. 품질 손실 없는 PNG 최적화

얼굴 디테일, 알파 가장자리, SD 프레임 수 또는 VFX 형태를 훼손하는 손실 압축은 적용하지 않았다.
