. "$PSScriptRoot\COMMON.ps1"
$root = Get-ProjectRoot
$godot = Find-Godot471
Set-ProjectGodotUserPaths $root
Copy-GodotWebTemplatesToProjectProfile $root

$tag = if ($args.Count -gt 0) { [string]$args[0] } else { 'r6p2' }
$artRevision = if ($args.Count -gt 1) { [string]$args[1] } else { 'R6P2' }
if ($tag -notmatch '^[a-z0-9_]+$') { throw "Invalid Web build tag: $tag" }
$development = Join-Path $root "builds\web_${tag}_development"
$release = Join-Path $root "builds\web_${tag}_release"
foreach ($directory in @($development, $release)) {
    if (Test-Path -LiteralPath $directory -PathType Container) {
        $existing = @(Get-ChildItem -LiteralPath $directory -Force)
        if ($existing.Count -gt 0) { throw "Refusing to overwrite non-empty Web build directory: $directory" }
    }
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--export-debug', 'Web Development', (Join-Path $development 'index.html'))
Invoke-Checked $godot @('--headless', '--path', (Join-Path $root 'godot'), '--export-release', 'Web HTML Release', (Join-Path $release 'index.html'))

function Add-OrientationGate([string]$IndexPath) {
    $fragment = @'
<style id="lanternline-orientation-style">
#lanternline-orientation-gate{position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;background:#05070b;color:#f4f7fb;font-family:system-ui,sans-serif;text-align:center;padding:24px;box-sizing:border-box}
#lanternline-orientation-gate[hidden]{display:none}
#lanternline-orientation-gate .card{width:min(420px,88vw);padding:28px 24px;border:1px solid #ffffff30;border-radius:16px;background:#101827e8;box-shadow:0 18px 48px #00000066}
#lanternline-orientation-gate strong{display:block;color:#78e6d0;font-size:24px;letter-spacing:.08em;margin-bottom:12px}
#lanternline-orientation-gate span{display:block;color:#cdd5e3;font-size:16px;line-height:1.55}
</style>
<div id="lanternline-orientation-gate" hidden role="dialog" aria-live="polite"><div class="card"><strong>LANTERNLINE</strong><span>가로 화면으로 돌려 주세요.<br>최소 지원 크기 844 × 390</span></div></div>
<script id="lanternline-orientation-script">(()=>{const g=document.getElementById('lanternline-orientation-gate');const u=()=>{g.hidden=!(innerHeight>innerWidth||innerWidth<844||innerHeight<390)};addEventListener('resize',u,{passive:true});addEventListener('orientationchange',u,{passive:true});u()})();</script>
'@
    $html = Get-Content -Raw -LiteralPath $IndexPath
    if ($html -notmatch '</body>') { throw "Web index has no body close tag: $IndexPath" }
    $html.Replace('</body>', "$fragment`r`n</body>") | Set-Content -LiteralPath $IndexPath -Encoding UTF8
}
Add-OrientationGate (Join-Path $development 'index.html')
Add-OrientationGate (Join-Path $release 'index.html')

@'
# LANTERNLINE R6P2 Web Pilot

Serve through a local HTTP server. This is a Godot 4.7.1 Compatibility Web export. Production approval remains pending user review.
'@ | Set-Content -LiteralPath (Join-Path $release 'README_HTML.md') -Encoding UTF8

[ordered]@{
    build_id = "LANTERNLINE_$($tag.ToUpperInvariant())_WEB_PILOT"
    engine = 'Godot 4.7.1-stable'
    renderer = 'Compatibility'
    target = 'Web HTML Release'
    art_revision = $artRevision
    production_approved = $false
    created_utc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $release 'VERSION.json') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $root 'docs\LICENSE_POLICY.md') -Destination (Join-Path $release 'LICENSES.md')

$required = @('index.html','index.js','index.wasm','index.pck','index.png','index.manifest.json','index.service.worker.js','index.offline.html','README_HTML.md','VERSION.json','LICENSES.md')
foreach ($name in $required) {
    $path = Join-Path $release $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required R6 Web file missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -le 0) { throw "Required R6 Web file empty: $path" }
}
Write-Host "WEB_R6_DEVELOPMENT=$development"
Write-Host "WEB_R6_RELEASE=$release"
