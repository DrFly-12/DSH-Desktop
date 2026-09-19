Add-Type -AssemblyName System.Drawing

$dir = 'c:\Users\gavan\.dsh\scripts\installer'

# ---------- Large wizard banner: 164 x 314 ----------
$bmp = New-Object System.Drawing.Bitmap 164, 314
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

$rect = New-Object System.Drawing.Rectangle 0, 0, 164, 314
$grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    [System.Drawing.Color]::FromArgb(13, 27, 51),
    [System.Drawing.Color]::FromArgb(30, 64, 120),
    135.0)
$g.FillRectangle($grad, $rect)

# decorative accent bar
$accent = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(56, 189, 248))
$g.FillRectangle($accent, 0, 246, 164, 3)

# wordmark
$white = [System.Drawing.Brushes]::White
$cyan  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(125, 211, 252))
$gray  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(203, 213, 225))

$fBrand = New-Object System.Drawing.Font('Segoe UI Semibold', 17, ([System.Drawing.FontStyle]::Bold), [System.Drawing.GraphicsUnit]::Pixel)
$fSub   = New-Object System.Drawing.Font('Segoe UI', 12, ([System.Drawing.FontStyle]::Regular), [System.Drawing.GraphicsUnit]::Pixel)
$fVer   = New-Object System.Drawing.Font('Segoe UI', 9, ([System.Drawing.FontStyle]::Regular), [System.Drawing.GraphicsUnit]::Pixel)

$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center

$g.DrawString('DeepSeek', $fBrand, $white, (New-Object System.Drawing.RectangleF 0, 96, 164, 30), $sf)
$g.DrawString('Harness', $fSub, $cyan,  (New-Object System.Drawing.RectangleF 0, 124, 164, 22), $sf)
$g.DrawString('Desktop Launcher', $fVer, $gray, (New-Object System.Drawing.RectangleF 0, 260, 164, 16), $sf)
$g.DrawString('v1.1.0', $fVer, $gray, (New-Object System.Drawing.RectangleF 0, 278, 164, 16), $sf)

$g.Dispose()
$bmp.Save((Join-Path $dir 'wizard-large.bmp'), [System.Drawing.Imaging.ImageFormat]::Bmp)
$bmp.Dispose()

# ---------- Small wizard image: 55 x 58 ----------
$bmp2 = New-Object System.Drawing.Bitmap 55, 58
$g2 = [System.Drawing.Graphics]::FromImage($bmp2)
$g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g2.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

$rect2 = New-Object System.Drawing.Rectangle 0, 0, 55, 58
$grad2 = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect2,
    [System.Drawing.Color]::FromArgb(13, 27, 51),
    [System.Drawing.Color]::FromArgb(30, 64, 120),
    135.0)
$g2.FillRectangle($grad2, $rect2)

$fDsh = New-Object System.Drawing.Font('Segoe UI Semibold', 13, ([System.Drawing.FontStyle]::Bold), [System.Drawing.GraphicsUnit]::Pixel)
$g2.DrawString('DSH', $fDsh, $white, (New-Object System.Drawing.RectangleF 0, 20, 55, 20), $sf)
$g2.FillRectangle($accent, 0, 52, 55, 2)

$g2.Dispose()
$bmp2.Save((Join-Path $dir 'wizard-small.bmp'), [System.Drawing.Imaging.ImageFormat]::Bmp)
$bmp2.Dispose()

Write-Host 'Wizard images generated:'
Get-ChildItem (Join-Path $dir 'wizard-*.bmp') | Select-Object Name, Length
