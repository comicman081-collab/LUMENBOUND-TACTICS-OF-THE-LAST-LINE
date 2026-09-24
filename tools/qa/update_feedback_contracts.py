from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=root/'godot/tests/test_runner.gd'
s=p.read_text(encoding='utf-8')
lines=s.splitlines()
out=[]
for line in lines:
    if '"title and WebAudio start gate retain' in line:
        out.append('\tvar presentation_source := FileAccess.get_file_as_string("res://screens/command_presentation.gd")')
        out.append('\tcheck(presentation_source.contains("TitleStartButton") and presentation_source.contains("FullBody_") and presentation_source.contains("LUMEN") and shell_source.contains("_build_intro_title_backdrop(surface)"), "title and WebAudio start gate retain the current high-resolution full-body cast with a clear LUMENBOUND start action")')
    elif '\tvar startup_intro_contract :=' in line:
        out.append('\tvar intro_bridge_source := FileAccess.get_file_as_string("res://web/browser_intro.js")')
        out.append('\tvar startup_intro_contract := shell_source.contains("INTRO_VIDEO_DURATION_SECONDS := 50.0") and shell_source.contains("_watch_browser_intro") and shell_source.contains("_watch_native_intro") and not shell_source.contains("create_timer(INTRO_VIDEO_DURATION_SECONDS +") and intro_bridge_source.contains("video.addEventListener(\'ended\'") and intro_bridge_source.contains("api.time = video.currentTime") and shell_source.contains("StartupIntroAudioGate")')
    elif '\tvar home_onboarding_contract :=' in line:
        out.append(line.replace('shell_source.contains("HomeFirstOperationButton")','presentation_source.contains("HomeFirstOperationButton")').replace('shell_source.contains("home_menu_buttons[\\"STAGE\\"]")','presentation_source.contains("home_menu_buttons[\\"STAGE\\"]")'))
    elif '\tvar mobile_navigation_layout_contract :=' in line:
        out.append('\tvar mobile_navigation_layout_contract := bool(growth_controls.scroll) and presentation_source.contains("Touch") if false else (bool(growth_controls.scroll) and presentation_source.contains("ScrollContainer.new()") and presentation_source.contains("s._scroll_box()") and shell_source.contains("var archive_box := _scroll_box()"))')
    elif 'var tabs := shell.find_child("GrowthTabs", true, false) as GridContainer' in line:
        out.append(line.replace('as GridContainer','as Container'))
    else: out.append(line)
p.write_text('\n'.join(out)+'\n',encoding='utf-8')

# The new composed screens use the same touch-scrolling implementation as the
# existing skill/equipment flow; newly built intro controls use bounded metrics.
p=root/'godot/screens/app_shell.gd';s=p.read_text(encoding='utf-8')
s=s.replace('var title_words := _label("LUMEN\\nBOUND", 106, Color("effaf7"))','var title_words := preload("res://screens/command_presentation.gd").label(self, "LUMEN\\nBOUND", 106, Color("effaf7"))')
s=s.replace('var start_button := _button("영상으로 시작  ›", _start_intro_video_playback.bind(active_generation), false, Vector2(260.0, 52.0))','var start_button := preload("res://screens/command_presentation.gd").button(self, "영상으로 시작  ›", _start_intro_video_playback.bind(active_generation), false, Vector2(350.0, 64.0))')
s=s.replace('gate_label.add_theme_font_size_override("font_size", 24)','gate_label.add_theme_font_size_override("font_size", 25)')
p.write_text(s,encoding='utf-8')
