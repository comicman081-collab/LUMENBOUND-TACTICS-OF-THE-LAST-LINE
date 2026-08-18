. "$PSScriptRoot\COMMON.ps1"
$project = Get-ProjectRoot
$factory = 'D:\AI 종합 폴더\Games\asset_share'
$revision = if ($args.Count -gt 0) { $args[0] } else { 'R5' }
$source = Join-Path $factory "exports\premium\pilot\$revision"
$validationPath = Join-Path $source 'validation_report.json'
if (-not (Test-Path -LiteralPath $validationPath -PathType Leaf)) { throw "Validation report missing: $validationPath" }
$validation = Get-Content -Raw -LiteralPath $validationPath | ConvertFrom-Json
if (-not $validation.technical_pass) { throw "Revision $revision is not TECHNICAL_PASS" }
$artRoot = Join-Path $project 'godot\assets\art'

function Copy-FileIncremental([string]$From, [string]$To) {
    $parent = Split-Path -Parent $To
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    if (Test-Path -LiteralPath $To -PathType Leaf) {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $From).Hash
        $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $To).Hash
        if ($sourceHash -eq $targetHash) { Write-Host "UNCHANGED $To"; return }
        Write-Host "REPLACE_CHANGED $To"
    } else { Write-Host "COPY_NEW $To" }
    Copy-Item -LiteralPath $From -Destination $To -Force
}

function Copy-TreeIncremental([string]$From, [string]$To) {
    Get-ChildItem -LiteralPath $From -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($From.Length).TrimStart('\')
        Copy-FileIncremental $_.FullName (Join-Path $To $relative)
    }
}

$packMap = @{
    'CHR001' = @{ Destination = (Join-Path $artRoot 'sd\CHR001'); View = 'THREE_QUARTER_RIGHT_DOWN_30'; Facing = 'SEPARATE_LEFT_RIGHT' }
    'CHR008' = @{ Destination = (Join-Path $artRoot 'sd\CHR008'); View = 'THREE_QUARTER_RIGHT_DOWN_30'; Facing = 'SEPARATE_LEFT_RIGHT' }
    'ENM001' = @{ Destination = (Join-Path $artRoot 'enemies\ENM001'); View = 'THREE_QUARTER_LEFT_DOWN_30'; Facing = 'MIRROR_SAFE' }
    'ENM007' = @{ Destination = (Join-Path $artRoot 'enemies\ENM007'); View = 'THREE_QUARTER_LEFT_DOWN_30'; Facing = 'MIRROR_SAFE' }
    'BOSS001' = @{ Destination = (Join-Path $artRoot 'bosses\BOSS001'); View = 'THREE_QUARTER_LEFT_DOWN_30'; Facing = 'MIRROR_SAFE' }
}
foreach ($entity in $packMap.Keys) {
    $from = Join-Path $source "sd\$entity"
    $config = $packMap[$entity]
    Copy-TreeIncremental $from $config.Destination
    $factoryManifest = Get-Content -Raw -LiteralPath (Join-Path $from 'animation_manifest.json') | ConvertFrom-Json
    $animations = [ordered]@{}
    foreach ($state in @('idle','move','basic_attack','normal_skill','ultimate','hit','down','victory')) {
        $definition = $factoryManifest.animations.$state
        $paths = @(Get-ChildItem -LiteralPath (Join-Path $from $state) -File -Filter '*.png' | Sort-Object Name | ForEach-Object { "$state/$($_.Name)" })
        $animations[$state] = [ordered]@{ fps = [int]$definition.fps; loop = [bool]$definition.loop; frame_paths = $paths }
    }
    $animations['stun'] = [ordered]@{ fps = 12; loop = $true; frame_paths = @($animations.hit.frame_paths) }
    $runtimeManifest = [ordered]@{
        character_id = $entity; asset_id = $factoryManifest.asset_id; revision = $revision
        view = $config.View; facing_policy = $config.Facing; foot_anchor = @(0.5, 0.88); head_anchor = @(0.5, 0.12)
        animations = $animations; events = $factoryManifest.events; source_blend = $factoryManifest.source_blend
        ownership_status = 'ORIGINAL_INTERNAL'; status = 'ART_QA_CANDIDATE'
    }
    $runtimeManifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $config.Destination 'animation_manifest.json') -Encoding UTF8
}

Copy-TreeIncremental (Join-Path $source 'characters') (Join-Path $artRoot 'characters')
Copy-TreeIncremental (Join-Path $source 'backgrounds') (Join-Path $artRoot 'backgrounds')
Copy-TreeIncremental (Join-Path $source 'cg') (Join-Path $artRoot 'cg')
Copy-TreeIncremental (Join-Path $source 'icons') (Join-Path $artRoot 'icons')
if (Test-Path -LiteralPath (Join-Path $source 'vfx')) { Copy-TreeIncremental (Join-Path $source 'vfx') (Join-Path $artRoot 'vfx') }
Write-Host "ART_SYNC_COMPLETE revision=$revision"
