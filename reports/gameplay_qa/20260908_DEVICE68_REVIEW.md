# 모바일 전용 회전 수정

원인: 창 높이>너비만 검사해서 PC의 좁은 미리보기 창도 회전했다.
수정: Android/iPhone/iPad 식별을 추가하고 PC는 항상 정방향으로 유지한다. Windows 터치스크린을 모바일로 간주하지 않는다. PC의 좁은 창에서는 가로 게임을 창 너비 안에 맞춰 전체 표시한다. 모바일의 기존90도 회전/입력/상태 유지는 보존한다.

소스 godot/web/landscape.html와 현재 실행 중인 Release67 HTML을 함께 수정했다. 이전 HTML은 quarantine/ui_desktop_rotation67에 해시와 함께 보존했다.
실제 Chrome 기기 프로필 검사 20/20: Windows 일반/터치 좁은 창, Mac 좁은 창, Android 회전 전환, iPhone, iPad 데스크톱 UA, PC 실행 중 창 크기 변경. 실제 OS 기기 테스트는 아니다.
기존 landscape_only_audit.mjs도 이제 창 크기만 바꾸는 대신 명시적 모바일 UA로 검증한다.
