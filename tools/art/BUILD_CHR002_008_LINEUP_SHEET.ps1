param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$outputDir = Join-Path $ProjectRoot 'reports\r15\art_b\contact_sheets'
$outputPath = Join-Path $outputDir 'CHR002_008_STATIC_LINEUP_R1.png'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$members = @(
    @{ Id = 'CHR002'; Name = '로안'; Role = 'VANGUARD'; Path = 'godot\assets\art\characters\CHR002\CHR002_PORTRAIT_R1.png' },
    @{ Id = 'CHR003'; Name = '나린'; Role = 'ASSAULT'; Path = 'godot\assets\art\characters\CHR003\CHR003_PORTRAIT_R1.png' },
    @{ Id = 'CHR004'; Name = '에다'; Role = 'ASSAULT'; Path = 'godot\assets\art\characters\CHR004\CHR004_PORTRAIT_R1.png' },
    @{ Id = 'CHR005'; Name = '소렌'; Role = 'ARTILLERY'; Path = 'godot\assets\art\characters\CHR005\CHR005_PORTRAIT_R1.png' },
    @{ Id = 'CHR006'; Name = '베라'; Role = 'SPECIALIST'; Path = 'godot\assets\art\characters\CHR006\CHR006_PORTRAIT_R1.png' },
    @{ Id = 'CHR007'; Name = '토아'; Role = 'SPECIALIST'; Path = 'godot\assets\art\characters\CHR007\CHR007_PORTRAIT_R1.png' },
    @{ Id = 'CHR008'; Name = '이리'; Role = 'MEDIC'; Path = 'godot\assets\art\characters\CHR008\CHR008_PORTRAIT_R1.png' }
)

$canvas = [System.Drawing.Bitmap]::new(2240, 1100, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
$graphics.Clear([System.Drawing.Color]::FromArgb(10, 17, 31))
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$titleFont = [System.Drawing.Font]::new('Segoe UI', 30, [System.Drawing.FontStyle]::Bold)
$labelFont = [System.Drawing.Font]::new('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
$subFont = [System.Drawing.Font]::new('Segoe UI', 14)
$graphics.DrawString('CHR002–CHR008 STATIC ART — R1 LINEUP PARITY', $titleFont, [System.Drawing.Brushes]::PaleTurquoise, 36, 24)

for ($index = 0; $index -lt $members.Count; $index++) {
    $entry = $members[$index]
    $panelX = 24 + $index * 314
    $panelY = 88
    $panel = [System.Drawing.Rectangle]::new($panelX, $panelY, 292, 970)
    $graphics.FillRectangle([System.Drawing.Brushes]::Black, $panel)
    $graphics.DrawRectangle([System.Drawing.Pens]::DarkSlateGray, $panel)
    $graphics.DrawString("$($entry.Id)  $($entry.Name)", $labelFont, [System.Drawing.Brushes]::PaleTurquoise, $panelX + 14, $panelY + 14)
    $graphics.DrawString($entry.Role, $subFont, [System.Drawing.Brushes]::LightSteelBlue, $panelX + 14, $panelY + 44)
    $assetPath = Join-Path $ProjectRoot $entry.Path
    if (-not (Test-Path -LiteralPath $assetPath)) { throw "Missing lineup asset: $assetPath" }
    $image = [System.Drawing.Image]::FromFile($assetPath)
    $usable = [System.Drawing.Rectangle]::new($panelX + 12, $panelY + 76, 268, 862)
    $scale = [Math]::Min($usable.Width / $image.Width, $usable.Height / $image.Height)
    $drawWidth = [int]($image.Width * $scale)
    $drawHeight = [int]($image.Height * $scale)
    $drawX = $usable.X + [int](($usable.Width - $drawWidth) / 2)
    $drawY = $usable.Y + [int](($usable.Height - $drawHeight) / 2)
    $graphics.DrawImage($image, [System.Drawing.Rectangle]::new($drawX, $drawY, $drawWidth, $drawHeight))
    $image.Dispose()
}

$graphics.DrawString('Review intent: head-authority, silhouette separation, palette consistency, and transparent-card integration. Production approval remains user-gated.', $subFont, [System.Drawing.Brushes]::LightSlateGray, 36, 1068)
$canvas.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$subFont.Dispose()
$labelFont.Dispose()
$titleFont.Dispose()
$graphics.Dispose()
$canvas.Dispose()
Write-Output "CHR002_008_LINEUP_SHEET=$outputPath"
