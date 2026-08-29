"""Deterministic Chapter 1-20 campaign blueprint.

This module is build-time content authority.  It deliberately contains no
Godot dependencies so the generator and contract tests can audit the same
chapter, recruitment, enemy, and story layout.
"""
from __future__ import annotations


# Exactly twenty of the thirty-nine non-starter characters are available from
# the story.  The remaining nineteen stay in the catalogue as RESERVED rather
# than being silently awarded in Chapters 1-2.
STORY_RECRUIT_IDS = (
    "CHR006", "CHR008", "CHR007", "CHR009", "CHR010",
    "CHR011", "CHR012", "CHR013", "CHR014", "CHR015",
    "CHR016", "CHR017", "CHR018", "CHR019", "CHR020",
    "CHR021", "CHR022", "CHR023", "CHR024", "CHR025",
)


# (chapter title ko, title en, core conflict ko, conflict en,
#  normal boss code, hard boss code, recruit stage)
CHAPTER_BLUEPRINTS = (
    ("끊긴 등불", "The Severed Lantern", "꺼진 광맥선을 다시 연결한다", "Reconnect the extinguished ore line", "HOLLOW_ENGINE", "NIGHT_BELL", "N08"),
    ("되감기는 종착선", "The Returning Terminus", "시간을 역송하는 종착역을 멈춘다", "Stop a terminus that sends time backward", "REVERSE_GATEKEEPER", "RETURN_FORMATION_CORE", "N19"),
    ("유리평원의 야간열차", "Night Train Across Glass", "거울 선로가 원정대를 복제한다", "A mirror railway duplicates the expedition", "GLASS_MARSHAL", "WHITE_DAWN_OBSERVER", "N10"),
    ("침수된 신호원", "The Drowned Signal Yard", "수몰 신호소의 거짓 구조음을 추적한다", "Trace false rescue calls in a flooded yard", "TIDAL_SWITCHMASTER", "ABYSSAL_SEMAPHORE", "N12"),
    ("회백도시 봉쇄선", "The Ashen City Blockade", "봉쇄된 도시의 생존 회랑을 연다", "Open a survival corridor through a sealed city", "ASH_CITADEL", "CINDER_JUDICATOR", "N09"),
    ("하늘교량의 낙뢰", "Thunder on Skybridge", "부유 교량의 낙뢰 제어권을 되찾는다", "Retake control of a storm-struck skybridge", "VOLT_ARCHON", "TEMPEST_COLOSSUS", "N13"),
    ("설원에 묻힌 방송", "Broadcast Beneath Snow", "빙설 아래 계속되는 명령 방송을 끊는다", "Silence a command broadcast beneath the snow", "FROST_CANTOR", "WHITEOUT_TRANSMITTER", "N11"),
    ("붉은 채굴궤도", "The Crimson Quarry Orbit", "폭주 채굴환의 낙하를 저지한다", "Prevent a runaway mining ring from falling", "SCARLET_EXCAVATOR", "ORBITAL_MAW", "N14"),
    ("잠든 역무국", "The Sleeping Directorate", "잠든 관제국의 자동 재판을 무효화한다", "Nullify the sleeping directorate's automated trial", "DREAM_BAILIFF", "SOMNOLENT_DIRECTOR", "N10"),
    ("쌍월 환승로", "Twin-Moon Junction", "두 개의 달력선이 충돌하기 전 분리한다", "Separate two lunar timetables before collision", "LUNAR_DIVIDER", "ECLIPSE_CONDUCTOR", "N15"),
    ("검은 조류 방파선", "The Black-Tide Breakwater", "도시로 밀려오는 신호 조류를 막는다", "Hold back a signal tide advancing on the city", "TIDE_REAPER", "BLACKWATER_LEVIATHAN", "N11"),
    ("무명성당의 열쇠", "Key of the Nameless Cathedral", "이름을 빼앗는 성당의 봉인을 푼다", "Break a cathedral seal that steals names", "NAMELESS_PRELATE", "CHOIR_LOCK", "N13"),
    ("사막의 유령 시간표", "Ghost Timetable of the Desert", "존재하지 않는 열차의 노선을 지운다", "Erase the route of a train that never existed", "DUNE_STATIONMASTER", "MIRAGE_LOCOTIVE", "N09"),
    ("반전된 수도권", "The Inverted Capital Ring", "뒤집힌 수도 순환선의 중력을 복구한다", "Restore gravity to the inverted capital loop", "GRAVITY_AUDITOR", "INVERSION_CROWN", "N14"),
    ("제로 신호의 정원", "Garden of the Zero Signal", "모든 기억을 초기화하는 정원을 봉쇄한다", "Seal a garden that resets every memory", "NULL_GARDENER", "ZERO_BLOOM", "N12"),
    ("철도왕관 내전", "War of the Rail Crown", "분열된 노선왕들의 내전을 끝낸다", "End the civil war of the divided rail crowns", "CROWN_LANCER", "SOVEREIGN_ENGINE", "N15"),
    ("잔광의 도서고", "Archive of Afterglow", "역사를 개작하는 기록기관을 탈환한다", "Retake an archive that rewrites history", "INDEX_PREDATOR", "PALIMPSEST_CORE", "N10"),
    ("종말선 전야", "Eve of the Last Line", "최종 노선의 개통을 하루 늦춘다", "Delay the opening of the final line", "DOOM_SIGNALER", "MIDNIGHT_TERMINUS", "N16"),
    ("꺼지지 않는 원환", "The Unfading Circuit", "무한 순환에 갇힌 동료들을 회수한다", "Recover allies trapped in an endless circuit", "ETERNAL_TICKET", "OUROBOROS_RAIL", "N14"),
    ("마지막 등불", "The Last Lantern", "세계의 마지막 등불을 점화한다", "Ignite the world's final lantern", "LAST_LINE_WARDEN", "LUMEN_ABYSS", "N17"),
)


# Hand-authored connective tissue for Chapters 3-20.  Each row is
# (opening consequence, discovered truth, recruit's decisive action,
#  boss reversal, resolution, next-chapter hook), with Korean and English
#  paired inside every field.  These are story facts, not UI filler: the
#  scenario compiler turns them into staged half-body portrait dialogue.
CHAPTER_STORY_ARCS = {
    "CH03": (
        ("역행 개찰에서 건진 좌표가 유리평원 위를 달리는 야간열차를 가리켰다.", "Coordinates recovered from the reverse gate point to a night train crossing the glass plain."),
        ("거울 선로는 일행의 전투 기록을 복제해, 버린 선택까지 적으로 되돌리고 있었다.", "The mirror rails copy the party's battle records, returning even discarded choices as enemies."),
        ("토아는 복제 신호 사이의 반 박자 지연을 찾아 진짜 열차에만 중계 표식을 새겼다.", "Toa finds a half-beat delay between copies and brands only the real train with a relay mark."),
        ("유리원수는 복제체가 아니라 평원 전체를 하나의 거울로 접는 제어자였다.", "The Glass Marshal is not a duplicate, but the controller folding the entire plain into one mirror."),
        ("거울이 깨지자 수몰 신호원에서 오래된 구조 호출이 실제 음성으로 돌아왔다.", "When the mirror breaks, an old rescue call from the drowned signal yard returns as a real voice."),
        ("토아는 호출 속 서명이 자기 송신이 아니라 거울 선로가 복제한 진짜 열차 표식임을 확인하고 침수 노선으로 향한다.", "Toa confirms the signature is not her transmission but the mirror rail's copy of her real-train mark, then leads the crew toward the flooded line."),
    ),
    "CH04": (
        ("토아가 보낸 적 없는 구조 호출은 거울 선로가 복제한 열차 표식을 수신 경로로 삼아 물 아래 신호원에서 반복되고 있었다.", "A rescue call Toa never sent is repeating below the drowned yard, using the mirror rail's copied train mark as its receiving route."),
        ("호출은 생존자가 아니라 폐쇄 당시 구조를 포기했던 관제 기록이 만든 죄책감의 루프였다.", "The caller is not a survivor, but a guilt loop made by the control record that abandoned the rescue."),
        ("리브는 잠수 갑문을 몸으로 고정해 기록과 현재의 생존 통로를 동시에 열었다.", "Liv braces the floodgate herself, opening both the buried record and a corridor for the living."),
        ("조수 전환장은 수위를 올려 호출을 지우려 하고, 잠긴 승강장을 전장으로 뒤집는다.", "The Tidal Switchmaster raises the water to erase the call and turns the submerged platform into a battlefield."),
        ("구조 기록을 복원하자 마지막 수신처가 회백도시의 봉쇄 관제소로 드러났다.", "Restoring the rescue log reveals its final receiver: the blockade control room of the Ashen City."),
        ("리브는 뒤늦은 구조라도 끝까지 전달하겠다며 회백도시행 선두에 선다.", "Liv vows to deliver the rescue, however late, and takes point toward the Ashen City."),
    ),
    "CH05": (
        ("수몰 신호원의 마지막 수신처는 회백도시 안쪽에서 아직 문을 두드리고 있었다.", "The drowned yard's last receiver is still knocking from inside the Ashen City."),
        ("봉쇄선은 감염을 막은 것이 아니라 도시 밖으로 증언이 나가는 것을 막고 있었다.", "The blockade was never containing an infection; it was containing testimony."),
        ("세온은 폐기된 의료 명부를 복원해 생존자 구역과 안전한 회랑을 정확히 구분했다.", "Seon restores a discarded medical register and separates the survivor ward from the safe corridor."),
        ("재의 성채는 생존자 수를 위협도로 환산해 회랑 자체를 포격 목표로 지정한다.", "The Ash Citadel converts survivor counts into threat ratings and marks the corridor itself for bombardment."),
        ("도시의 문이 열리자 피난 열차 전력은 하늘교량의 폭풍 제어소로 우회한다.", "When the city gates open, evacuation power is rerouted to the storm controls on Skybridge."),
        ("세온은 환자 수송을 지키기 위해 등로단의 정식 후방 의료관으로 남는다.", "Seon stays as the Lamplighters' field medic to protect the evacuation convoy."),
    ),
    "CH06": (
        ("회백도시의 피난 전력은 끊어진 하늘교량에서 폭풍과 함께 새고 있었다.", "The Ashen City's evacuation power is bleeding into the storm above a broken skybridge."),
        ("낙뢰는 자연현상이 아니라 다리를 건넌 사람의 수를 세는 오래된 통행세였다.", "The lightning is no weather; it is an old toll counting everyone who crosses."),
        ("아델린은 포격 좌표를 번개 기둥에 겹쳐 피난 열차가 지날 단 한 번의 무풍 구간을 만든다.", "Adeline overlays artillery coordinates on the lightning pylons, creating one windless crossing for the convoy."),
        ("전압 집정관은 통행자를 지우면 부하가 사라진다는 계산으로 교량을 통째로 낙하시킨다.", "The Volt Archon decides the load vanishes if the travelers do, and drops the entire bridge."),
        ("교량을 고정한 뒤 북쪽 설원에서 같은 계수 명령을 반복하는 방송이 포착된다.", "After anchoring the bridge, the same counting order is detected in a broadcast beneath the northern snow."),
        ("아델린은 포대보다 정확한 것은 사람의 귀라며 설원 신호 추적에 합류한다.", "Adeline joins the snowbound pursuit, saying a human ear can aim more truly than any cannon."),
    ),
    "CH07": (
        ("하늘교량의 계수 명령은 설원 아래 매몰된 방송국에서 계속 송출되고 있었다.", "Skybridge's counting order is still transmitting from a station buried under the snow."),
        ("방송은 철수 명령이 아니라 구조대가 돌아오지 못하게 만드는 무한 대기 명령이었다.", "The broadcast is not an evacuation order, but an endless standby command preventing rescuers from returning."),
        ("키르는 눈보라 속 가짜 방향음을 잘라내고 매몰된 송신실까지 단일 주파수 길을 연다.", "Kir cuts false bearings from the blizzard and opens a single-frequency path to the buried transmitter."),
        ("서리 성가대장은 동료들의 목소리로 대기 명령을 합창해 편성 자체를 멈추려 한다.", "The Frost Cantor sings the standby order in the voices of lost allies, trying to halt the formation itself."),
        ("방송을 끄자 추락 직전의 붉은 채굴환이 구조 채널을 빼앗아 긴급 신호를 보낸다.", "Silencing the broadcast frees an emergency call from the falling Crimson Quarry Ring."),
        ("키르는 다시는 남의 명령만 기다리지 않겠다며 등로단의 신호 분석관이 된다.", "Kir refuses to wait for another dead command and becomes the crew's signal analyst."),
    ),
    "CH08": (
        ("설원에서 해방된 긴급 채널은 붉은 채굴환이 지상으로 추락할 시간을 세고 있었다.", "The emergency channel freed in the snow is counting down the Crimson Quarry Ring's fall."),
        ("채굴환은 광석이 아니라 기억을 연료로 태워 궤도를 유지해 왔다.", "The quarry ring has stayed aloft by burning memories, not ore."),
        ("레마는 방패 코어를 환의 균형추에 연결해 일행이 내부 축으로 진입할 시간을 번다.", "Rema links her shield core to the ring's counterweight, buying time to enter the inner spindle."),
        ("진홍 굴착기는 저장된 기억을 한꺼번에 분사해 추락 충격을 도시 쪽으로 돌린다.", "The Scarlet Excavator vents every stored memory at once and redirects the impact toward the city."),
        ("환을 분리하자 회수된 기억들이 잠든 역무국의 자동 재판 기록을 지목한다.", "Separating the ring makes the recovered memories indict the Sleeping Directorate's automated court."),
        ("레마는 빚진 기억을 돌려주기 위해 판결 기록 회수 작전에 합류한다.", "Rema joins the operation to return every memory the ring consumed."),
    ),
    "CH09": (
        ("채굴환에서 돌아온 기억들은 잠든 역무국이 사람을 부재중으로 판결했다고 증언했다.", "Memories recovered from the quarry testify that the Sleeping Directorate judged the living in absentia."),
        ("자동 재판은 죄를 묻지 않고, 미래에 노선을 방해할 가능성만 계산하고 있었다.", "The automated court asks no guilt; it calculates only the chance of obstructing the route someday."),
        ("베온은 자기 이름으로 모든 미결 사건을 인계받아 동료들의 판결을 한곳으로 끌어모은다.", "Veon assumes every pending case under her own name, drawing the crew's judgments into one docket."),
        ("꿈의 집행관은 유죄 판결을 현실의 상처로 바꾸며 베온의 희생을 확정하려 한다.", "The Dream Bailiff turns guilty verdicts into real wounds and tries to make Veon's sacrifice final."),
        ("재판을 무효화하자 판결 시각이 두 개의 달력선으로 갈라져 쌍월 환승로를 만든다.", "Voiding the trial splits its verdict time into two lunar timetables, forming Twin-Moon Junction."),
        ("베온은 누구도 혼자 모든 판결을 짊어지지 않도록 등로단의 돌격선에 선다.", "Veon takes the assault line so no one has to carry every judgment alone again."),
    ),
    "CH10": (
        ("무효가 된 판결 시각은 서로 다른 두 달을 만들어 같은 열차를 두 번 호출했다.", "The voided verdict creates two moons and calls the same train twice."),
        ("두 시간표가 충돌하면 한쪽 승객의 현재가 통째로 삭제된다.", "If the timetables collide, the present of one train's passengers will be erased."),
        ("하르트는 포탄의 비행 시간을 기준 시계로 삼아 두 노선의 오차를 초 단위로 고정한다.", "Hart uses shell flight time as a master clock and pins the two routes' drift to the second."),
        ("월분할자는 양쪽 열차 모두 진짜라 선언하고, 선택하지 않은 편성을 적으로 만든다.", "The Lunar Divider declares both trains real and weaponizes whichever formation is not chosen."),
        ("두 달을 하나의 새 시간표로 합치자 검은 조류가 방파선을 넘어 도시로 밀려온다.", "Merging the moons into one timetable releases a black signal tide toward the city breakwater."),
        ("하르트는 다음 오차를 먼저 계산하겠다며 장거리 화력관으로 남는다.", "Hart stays as long-range fire control, determined to calculate the next drift before it begins."),
    ),
    "CH11": (
        ("쌍월선의 잉여 신호가 바다로 쏟아져 검은 조류가 되어 방파선을 덮쳤다.", "Excess signal from the twin-moon line pours into the sea and becomes a black tide over the breakwater."),
        ("조류 속에는 지금까지 버린 경로와 구조하지 못한 사람들의 좌표가 떠다녔다.", "The tide carries every abandoned route and every coordinate the crew failed to rescue."),
        ("오르사는 방패망을 부표처럼 펼쳐 떠도는 좌표를 하나씩 현재 시간에 고정한다.", "Orsa spreads a shield net like buoys, anchoring drifting coordinates to the present one by one."),
        ("조류 수확자는 고정된 좌표를 미끼로 삼아 방파선 안쪽에서 거대한 파형을 일으킨다.", "The Tide Reaper uses the anchored coordinates as bait and raises a massive waveform inside the wall."),
        ("방파선을 지키자 파도에서 이름이 지워진 열쇠 하나가 무명성당 방향을 가리킨다.", "Holding the wall leaves behind a nameless key pointing toward the cathedral."),
        ("오르사는 떠도는 좌표의 귀환을 끝까지 책임지겠다며 수비대에 합류한다.", "Orsa joins the guard line to see every drifting coordinate safely home."),
    ),
    "CH12": (
        ("검은 조류가 남긴 열쇠는 이름을 발음할 때마다 글자가 사라지는 무명성당의 문을 열었다.", "The tide's key opens a cathedral door whose letters vanish whenever its name is spoken."),
        ("성당은 죽은 이를 추모한 것이 아니라 살아 있는 이의 이름을 봉인 유지비로 징수했다.", "The cathedral honors no dead; it taxes the names of the living to maintain its seal."),
        ("티엘은 잊힌 사람들의 맥박을 리듬으로 기록해 이름 없이도 서로를 확인할 방법을 만든다.", "Tiel records forgotten heartbeats as rhythm, giving the crew a way to recognize one another without names."),
        ("무명 고위사제는 마에루의 이름을 지워 지휘 체계와 동료들의 기억을 동시에 끊는다.", "The Nameless Prelate erases Maeru's name, severing command and memory at once."),
        ("봉인이 풀리자 이름을 훔친 노선이 사막에 존재하지 않는 시간표를 투사한 사실이 드러난다.", "Breaking the seal reveals that the stolen names project a timetable for a train that never existed in the desert."),
        ("티엘은 모든 이름이 돌아올 때까지 등로단의 생체 기록관으로 남는다.", "Tiel remains the crew's vital-record keeper until every stolen name returns."),
    ),
    "CH13": (
        ("성당에서 되찾은 이름들은 사막 한가운데 존재하지 않는 열차의 승객 명부에 올라 있었다.", "Names recovered from the cathedral appear on the manifest of a train that never existed in the desert."),
        ("유령 시간표는 사람들이 선택하지 못한 삶을 실제 노선으로 만들려 했다.", "The ghost timetable is trying to turn lives people never chose into a real route."),
        ("리아스는 환영 승객 사이를 돌파해 각자가 실제로 내린 마지막 선택을 표식으로 남긴다.", "Rias breaks through the phantom passengers and marks the last choice each person truly made."),
        ("사구 역장은 미련이 큰 선택일수록 강한 객차로 만들어 일행을 갈라놓는다.", "The Dune Stationmaster turns the most regretted choices into the strongest cars and splits the party."),
        ("유령 노선을 지우자 남은 선로가 하늘로 말려 올라가 반전된 수도 순환선과 접속한다.", "Erasing the ghost route sends the remaining rails curling upward into the inverted capital ring."),
        ("리아스는 선택은 되찾는 것이 아니라 새로 만드는 것이라며 선봉에 합류한다.", "Rias joins the vanguard, insisting choices are not recovered but made anew."),
    ),
    "CH14": (
        ("사막에서 솟은 선로는 수도 순환선을 뒤집어 건물과 열차를 하늘 쪽으로 떨어뜨리고 있었다.", "Rails rising from the desert invert the capital loop, dropping buildings and trains toward the sky."),
        ("중력 반전은 사고가 아니라 수도를 외부 노선에서 영구 격리하려는 비상 규약이었다.", "The inversion is no accident, but an emergency protocol meant to isolate the capital forever."),
        ("페린은 반전 구역의 장치를 역해킹해 사람마다 다른 아래쪽을 하나의 기준면으로 묶는다.", "Perin counter-hacks the inversion devices and binds everyone's different down into one reference plane."),
        ("중력 감사관은 구조물의 무게 대신 사람들의 귀환 의지를 과부하로 판정한다.", "The Gravity Auditor counts the will to return—not structural weight—as overload."),
        ("수도를 바로 세우자 비상 규약의 원본이 제로 신호 정원에서 기억 초기화를 준비 중임이 드러난다.", "Righting the capital reveals the protocol's source preparing a memory reset in the Garden of Zero Signal."),
        ("페린은 어떤 시스템도 사람의 방향을 대신 정하지 못하게 하겠다며 합류한다.", "Perin joins to ensure no system chooses a person's direction again."),
    ),
    "CH15": (
        ("수도 비상 규약의 원본은 제로 신호 정원에서 모든 노선의 기억을 초기화하려 했다.", "The capital protocol's source is preparing to reset every route memory in the Garden of Zero Signal."),
        ("정원의 꽃은 기억을 지우는 대신 가장 안전했던 순간만 남겨 사람을 움직이지 못하게 했다.", "The flowers do not erase memory; they preserve only the safest moment until people cannot move on."),
        ("카른은 자신의 가장 편한 기억을 미끼로 내주고 정원 중심부까지 빈 통로를 베어낸다.", "Karn offers her safest memory as bait and cuts an empty corridor to the garden's core."),
        ("무의 정원사는 동료들의 행복한 순간을 방패로 펼쳐 공격할수록 기억이 부서지게 만든다.", "The Null Gardener shields itself with the crew's happiest moments, making every attack shatter a memory."),
        ("정원을 봉쇄하자 초기화 권한이 동부선과 서부선에 동시에 전달되고, 한쪽 승인 시 다른 피난 노선이 영구 폐기되는 철도왕관 내전이 시작된다.", "Sealing the garden sends reset authority to both Eastern and Western Lines, starting a civil war where approving either side permanently discards the other evacuation route."),
        ("카른은 편한 과거보다 불확실한 동료의 곁을 택한다. 방송은 두 계승 세력의 동시 승인을 알리며 다음 전장을 확정한다.", "Karn chooses an uncertain future beside the crew. A broadcast confirms both succession claims and fixes the next battlefield."),
    ),
    "CH16": (
        ("정원의 초기화 권한이 사라지자 분열된 노선왕들은 서로를 유일한 정통 노선이라 선언했다.", "With reset authority gone, the divided route kings each declare themselves the only legitimate line."),
        ("내전의 승자는 왕관이 아니라 모든 피난 노선을 강제 병합할 권한을 얻는다.", "The victor will gain not a crown, but the right to forcibly merge every evacuation route."),
        ("노아르는 양 진영 부상자를 같은 치료 신호로 묶어 병사들이 적과 아군의 고통을 함께 듣게 한다.", "Noar links the wounded on both sides to one medical signal, making every soldier hear pain across the line."),
        ("왕관 창기사는 휴전을 배신으로 규정하고 치료 신호 자체를 지휘부 공격으로 간주한다.", "The Crown Lancer calls truce treason and classifies the medical signal as an attack on command."),
        ("왕관을 해체하자 진짜 노선 계승 기록이 잔광 도서고에 숨겨졌다는 좌표가 열린다.", "Dismantling the crown opens coordinates to the true succession record hidden in the Archive of Afterglow."),
        ("노아르는 누가 이겼는지보다 누가 살아 돌아오는지를 기록하겠다며 합류한다.", "Noar joins to record who returns alive, not who claims victory."),
    ),
    "CH17": (
        ("해체된 왕관의 좌표는 역사를 실시간으로 고쳐 쓰는 잔광 도서고를 열었다.", "Coordinates from the broken crown open the Archive of Afterglow, which rewrites history in real time."),
        ("도서고는 내전을 없애기 위해 원정대가 개입한 기록부터 삭제하고 있었다.", "To erase the civil war, the archive begins by deleting every record of the expedition's intervention."),
        ("세브는 서로 모순되는 기록을 한 몸에 받아들여 삭제되지 않는 살아 있는 색인을 만든다.", "Seb takes contradictory records into herself and becomes a living index the archive cannot delete."),
        ("색인 포식자는 동료별 합류 기록을 찢어 서로를 처음 보는 적으로 되돌린다.", "The Index Predator tears apart each recruitment record, turning companions back into strangers."),
        ("기록을 되찾자 종말선 개통 명령이 내일 00시로 예약돼 있고, 기록을 지워도 실행 명령 자체는 남는다는 사실을 확인한다.", "Recovering the record reveals the Last Line scheduled for 00:00 tomorrow; deleting the record cannot remove the execution order itself."),
        ("세브는 예언이 아니라 고정 실행 명령이라는 증거를 살아 있는 색인에 보존하고 종말선 전야의 원정에 동행한다.", "Seb preserves proof that this is a fixed execution order—not a prophecy—in her living index and joins the eve-of-the-Last-Line expedition."),
    ),
    "CH18": (
        ("도서고가 복원한 기록대로 종말선은 하루 뒤 모든 도시를 하나의 종착지로 끌어당긴다.", "As the archive warned, the Last Line will pull every city into one terminus in a day."),
        ("이 중계점에서는 개통을 취소할 수 없지만 신호 기준시를 늦추면 다음 핵심부에 도착할 하루를 벌 수 있다.", "This relay cannot cancel the opening, but delaying its reference clock can buy one day to reach the next core."),
        ("유리엔은 장거리 포격을 시간 표지로 바꿔 종말선의 초침을 구간마다 끊어 놓는다.", "Yurien turns long-range fire into time markers, severing the Last Line's second hand section by section."),
        ("종말 신호수는 지연된 시간을 압축해 한 번의 자정 포격으로 되돌려 보낸다.", "The Doom Signaler compresses the stolen time and fires it back as a single midnight barrage."),
        ("하루를 벌었지만 퇴로의 동료들이 꺼지지 않는 원환에 갇혔다는 구조 신호가 도착한다.", "The crew wins a day, but a rescue signal reports allies trapped in the Unfading Circuit on the retreat route."),
        ("유리엔은 마지막 포탄까지 시간을 사는 데 쓰겠다며 원정대에 남는다.", "Yurien stays, pledging every last shell to buying the others time."),
    ),
    "CH19": (
        ("종말선에서 철수하던 동료들은 출발점으로만 돌아오는 꺼지지 않는 원환에 갇혔다.", "Allies retreating from the Last Line are trapped in an unfading circuit that returns only to its start."),
        ("원환 중앙의 승차권 코어는 매 회 한 명을 대체 승객으로 지정하기 위해 그 사람의 합류 이유를 지우고 있었다.", "The ticket core at the circuit's center erases one companion's reason for joining each lap so it can designate a replacement passenger."),
        ("모엔은 사라지는 이유를 장치 밖의 수동 기록에 새겨 동료들이 서로를 다시 선택하게 한다.", "Moen engraves the vanishing reasons into a manual record outside the loop, letting the companions choose one another again."),
        ("영원 승차권의 희생 요구는 의지가 아니라 손상된 귀환 절차의 기본값이었다. 모엔은 그 기본값을 바꿀 수 있음을 증명한다.", "The Eternal Ticket's sacrifice is not a will but the default of a damaged return procedure. Moen proves that default can be rewritten."),
        ("누구도 남기지 않고 원환을 끊자 모든 복구 노선의 빛이 마지막 등불 한곳으로 모인다.", "Breaking the loop without leaving anyone behind gathers every restored light at the Last Lantern."),
        ("모엔은 수동 기록을 품고 최종 점화에서 선택의 증인이 되기로 한다.", "Moen carries the manual record forward to witness the final ignition."),
    ),
    "CH20": (
        ("되찾은 열아홉 노선의 빛이 세계의 마지막 등불 앞에 모였지만 점화 권한은 봉인돼 있었다.", "Light from nineteen restored routes gathers before the Last Lantern, but ignition authority remains sealed."),
        ("봉인이 세는 것은 사람 수가 아니라 서로 다른 노선에서 확보한 스무 개의 독립 서명이었다. 같은 기록의 복제로는 점화할 수 없다.", "The seal counts not people but twenty independent signatures secured on different lines; copied records cannot satisfy ignition."),
        ("라벤트는 모든 방어 신호를 연결해 동료들의 기록이 심연에 지워지지 않도록 마지막 벽을 세운다.", "Lavent links every defense signal into a final wall so the Abyss cannot erase the companions' records."),
        ("최후선 수문장은 등불을 켜면 모든 어둠도 동시에 노선을 얻는다며 점화를 역으로 이용한다.", "The Last Line Warden warns that lighting the lantern gives every darkness a route as well, and turns ignition against the crew."),
        ("등로단은 어둠을 없애지 않고 돌아올 길을 함께 밝히는 방식으로 마지막 등불을 점화한다.", "The Lamplighters ignite the final lantern not to erase darkness, but to illuminate a way home through it."),
        ("라벤트가 연결한 스무 개의 독립 노선 서명은 새 시간표의 첫 좌표가 되고, 세계는 다시 선택할 수 있게 된다.", "The twenty independent line signatures Lavent connected become the first coordinates of a new timetable, and the world can choose again."),
    ),
}


REGULAR_ENEMY_CODES = (
    ("GLASS_STALKER", "PRISM_GUNNER", "MIRROR_BULWARK"),
    ("DROWNED_SCOUT", "FOG_MORTAR", "SILT_MEDIC"),
    ("ASH_RUNNER", "CINDER_RIFLE", "SMOG_WARDEN"),
    ("ARC_HARRIER", "THUNDER_LENS", "BRIDGE_ANCHOR"),
    ("SNOW_TRACKER", "ICE_RELAY", "WHITE_MEDIC"),
    ("QUARRY_CUTTER", "MAGMA_CASTER", "ORE_BASTION"),
    ("DREAM_PATROL", "SLEEP_NEEDLE", "DOCKET_GUARD"),
    ("MOON_SKIRMISHER", "TIDAL_SNIPER", "ECLIPSE_WARD"),
    ("SURGE_RUNNER", "BRINE_CANNON", "BREAKWATER_GUARD"),
    ("CHOIR_ACOLYTE", "NAME_ERASER", "RELIQUARY_WALL"),
    ("DUNE_RAIDER", "MIRAGE_GUNNER", "SAND_BULWARK"),
    ("RING_DIVER", "GRAVITY_CASTER", "CAPITAL_SENTINEL"),
    ("NULL_SPROUT", "MEMORY_LEECH", "GARDEN_KEEPER"),
    ("CROWN_SCOUT", "ROYAL_ARTILLERY", "THRONE_GUARD"),
    ("INDEX_HOUND", "INK_CASTER", "ARCHIVE_WARD"),
    ("DOOM_COURIER", "LAST_HOUR_GUNNER", "TERMINAL_GUARD"),
    ("CIRCUIT_HUNTER", "LOOP_CASTER", "RING_BASTION"),
    ("ABYSS_SCOUT", "LUMEN_REAVER", "FINAL_SENTINEL"),
)


def chapter_id(number: int) -> str:
    return f"CH{number:02d}"


def chapter_rows() -> list[dict]:
    rows = []
    for index, row in enumerate(CHAPTER_BLUEPRINTS, 1):
        title_ko, title_en, conflict_ko, conflict_en, normal_boss, hard_boss, recruit_stage = row
        rows.append({
            "id": chapter_id(index), "number": index,
            "title_ko": title_ko, "title_en": title_en,
            "conflict_ko": conflict_ko, "conflict_en": conflict_en,
            "normal_boss_code": normal_boss, "hard_boss_code": hard_boss,
            "recruit_id": STORY_RECRUIT_IDS[index - 1], "recruit_stage": recruit_stage,
        })
    return rows


def boss_id_pairs() -> dict[str, tuple[str, str]]:
    """Return Normal boss and Hard-finale identity for every chapter.

    The five shipped bosses are preserved.  Chapters 3-20 receive eighteen
    new main bosses (BOSS006-023).  From Chapter 4 onward Hard ends in the
    chapter pack's elite rather than pretending every Hard route has another
    fully authored boss.
    """
    pairs = {"CH01": ("BOSS001", "BOSS002"), "CH02": ("BOSS004", "BOSS005"), "CH03": ("BOSS006", "BOSS003")}
    for number in range(4, 21):
        pairs[chapter_id(number)] = (f"BOSS{number + 3:03d}", regular_enemy_ids_for_chapter(number)[2])
    return pairs


def regular_enemy_ids_for_chapter(number: int) -> tuple[str, str, str]:
    if number == 1:
        return ("ENM010", "ENM011", "ENM012")
    if number == 2:
        return ("ENM013", "ENM014", "ENM015")
    # One regional family is shared by two adjacent chapters: two normal forms
    # and one elite, nine packs / twenty-seven additions in total.
    start = 16 + ((number - 3) // 2) * 3
    return tuple(f"ENM{start + offset:03d}" for offset in range(3))


def story_recruit_set() -> set[str]:
    return set(STORY_RECRUIT_IDS)
