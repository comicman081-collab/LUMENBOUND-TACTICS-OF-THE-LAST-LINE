. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
$project = Join-Path $root 'godot'
# Compatibility can emit a non-fatal RID leak warning while the offscreen
# window tears down.  Keep exit-code and fatal-script checks authoritative;
# do not let PowerShell promote that warning to a terminating exception before
# `Invoke-Checked` can inspect Godot's actual result.
$captureErrorPreference = $ErrorActionPreference
try {
    # `Invoke-Checked` below still fails non-zero exits and fatal Godot script
    # diagnostics itself.  This only prevents a non-fatal native stderr warning
    # from short-circuiting that authoritative check.
    $ErrorActionPreference = 'Continue'
    Invoke-Checked $godot @(
        '--path', $project,
        '--position', '10000,10000',
        '--resolution', '1920x1080',
        '--disable-vsync',
        'res://tools/capture_visual_qa.tscn'
    )
} finally {
    $ErrorActionPreference = $captureErrorPreference
}
