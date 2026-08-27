param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sourceRoot = Join-Path $ProjectRoot 'godot\assets\art\characters\CHR001'
$outputDir = Join-Path $ProjectRoot 'reports\r15\art_b\contact_sheets'
$outputPath = Join-Path $outputDir 'CHR001_STATIC_ART_R6P2_CONTACT_SHEET.png'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

function Draw-ArtPanel {
    param([System.Drawing.Graphics]$Graphics,[string]$Path,[string]$Label,[int]$X,[int]$Y,[int]$Width,[int]$Height)
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
Draw-ArtPanel $graphics (Join-Path $sourceRoot 'fullbody_2048x3072.png') 'MASTER RGBA (R6P2)' 32 32 980 720
Draw-ArtPanel $graphics (Join-Path $sourceRoot 'portrait_1024x1536.png') 'WEB PORTRAIT RGBA' 1036 32 980 720
Draw-ArtPanel $graphics (Join-Path $sourceRoot 'icon_512x512.png') 'ICON RGBA' 32 784 980 720
Draw-ArtPanel $graphics (Join-Path $sourceRoot 'halfbody_1024x1536.png') 'PRESERVED HALF BODY (SOURCE)' 1036 784 980 720
$canvas.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$canvas.Dispose()
Write-Output "CHR001_CONTACT_SHEET=$outputPath"
