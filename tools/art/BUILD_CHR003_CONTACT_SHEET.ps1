param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$renderRoot = 'D:\AI 종합 폴더\Games\asset_share\blender_sources\characters\CHR003\renders'
$outputDir = Join-Path $ProjectRoot 'reports\r15\art_b\contact_sheets'
$outputPath = Join-Path $outputDir 'CHR003_STATIC_ART_R1_CONTACT_SHEET.png'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

function Draw-ArtPanel {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Path,
        [string]$Label,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )
    $panel = [System.Drawing.Rectangle]::new($X, $Y, $Width, $Height)
    $Graphics.FillRectangle([System.Drawing.Brushes]::Black, $panel)
    $Graphics.DrawRectangle([System.Drawing.Pens]::DarkSlateGray, $panel)
    $font = [System.Drawing.Font]::new('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
    $Graphics.DrawString($Label, $font, [System.Drawing.Brushes]::PaleTurquoise, $X + 18, $Y + 14)
    $font.Dispose()
    $image = [System.Drawing.Image]::FromFile($Path)
    $usable = [System.Drawing.Rectangle]::new($X + 20, $Y + 58, $Width - 40, $Height - 78)
    $scale = [Math]::Min($usable.Width / $image.Width, $usable.Height / $image.Height)
    $drawWidth = [int]($image.Width * $scale)
    $drawHeight = [int]($image.Height * $scale)
    $drawX = $usable.X + [int](($usable.Width - $drawWidth) / 2)
    $drawY = $usable.Y + [int](($usable.Height - $drawHeight) / 2)
    $Graphics.DrawImage($image, [System.Drawing.Rectangle]::new($drawX, $drawY, $drawWidth, $drawHeight))
    $image.Dispose()
}

$canvas = [System.Drawing.Bitmap]::new(2048, 1536, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
$graphics.Clear([System.Drawing.Color]::FromArgb(10, 17, 31))
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

Draw-ArtPanel $graphics (Join-Path $renderRoot 'CHR003_ILLUSTRATION_MASTER_R1.png') 'MASTER RGBA' 32 32 980 720
Draw-ArtPanel $graphics (Join-Path $renderRoot 'CHR003_PORTRAIT_R1.png') 'WEB PORTRAIT RGBA' 1036 32 980 720
Draw-ArtPanel $graphics (Join-Path $renderRoot 'CHR003_ICON_R1.png') 'ICON RGBA' 32 784 980 720
Draw-ArtPanel $graphics (Join-Path $renderRoot 'CHR003_RUNTIME_ICON_R1.png') 'AUTHORING DERIVATIVE (NOT MAPPED)' 1036 784 980 720

$canvas.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$canvas.Dispose()
Write-Output "CHR003_CONTACT_SHEET=$outputPath"
