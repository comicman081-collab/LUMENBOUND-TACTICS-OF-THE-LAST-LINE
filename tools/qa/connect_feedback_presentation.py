from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=root/'godot/screens/app_shell.gd'
s=p.read_text(encoding='utf-8')
for function, new in [('_show_home','home(self)'),('_show_title','title(self)'),('_show_roster','roster(self)'),('_show_growth','growth(self)'),('_build_growth_level','level(self, parent, cid)')]:
    start=s.index('func '+function+'(')
    header_end=s.index('\n',start)
    end=s.index('\nfunc ',header_end)
    s=s[:header_end]+'\n\tpreload("res://screens/command_presentation.gd").'+new+'\n'+s[end:]
start=s.index('func _build_intro_title_backdrop(')
header_end=s.index('\n',start)
end=s.index('\nfunc ',header_end)
s=s[:header_end]+'''
\tintro_still_backdrop = Control.new()
\tintro_still_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
\tintro_still_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
\tsurface.add_child(intro_still_backdrop)
\tpreload("res://screens/command_presentation.gd").title_backdrop(self, intro_still_backdrop)
'''+s[end:]
s=s.replace('title_center.anchor_left = 0.0','title_center.anchor_left = 0.055',1).replace('title_center.anchor_right = 1.0','title_center.anchor_right = 0.49',1).replace('title_center.anchor_top = 0.10','title_center.anchor_top = 0.22',1).replace('title_center.anchor_bottom = 0.56','title_center.anchor_bottom = 0.62',1)
start=s.index('\tvar title_logo := TextureRect.new()')
end=s.index('\tvar skip :=',start)
s=s[:start]+'''\ttitle_lockup.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
\tvar title_words := _label("LUMEN\\nBOUND", 106, Color("effaf7"))
\ttitle_lockup.add_child(title_words)
'''+s[end:]
s=s.replace('Vector2(720.0, 200.0)','Vector2(640.0, 340.0)',1)
s=s.replace('intro_start_gate.anchor_left = 0.5','intro_start_gate.anchor_left = 0.25',1).replace('intro_start_gate.anchor_right = 0.5','intro_start_gate.anchor_right = 0.25',1)
s=s.replace('gate_label.text = "인트로 시작"','gate_label.text = "꺼진 노선 위에서, 다시 빛을 잇다."',1).replace('gate_hint.text = "소리를 켜고 첫 장면부터 재생합니다"','gate_hint.text = "50초의 프롤로그"',1).replace('_button("소리 켜고 시작"','_button("영상으로 시작  ›"',1)
s=s.replace('intro_title_tween.tween_interval(5.0)','intro_title_tween.tween_interval(0.0)',1)
p.write_text(s,encoding='utf-8')
