Add-Type -AssemblyName System.Drawing

$outputPath = Join-Path $PSScriptRoot '..\assets\ui\xbox_controls.png'
$bitmap = [System.Drawing.Bitmap]::new(1100, 84)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

function New-Brush([string]$hex) { [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($hex)) }
function Draw-RoundedRect($g, [float]$x, [float]$y, [float]$width, [float]$height, [float]$radius, $brush) {
	$path = [System.Drawing.Drawing2D.GraphicsPath]::new()
	$diameter = $radius * 2
	$path.AddArc($x, $y, $diameter, $diameter, 180, 90)
	$path.AddArc($x + $width - $diameter, $y, $diameter, $diameter, 270, 90)
	$path.AddArc($x + $width - $diameter, $y + $height - $diameter, $diameter, $diameter, 0, 90)
	$path.AddArc($x, $y + $height - $diameter, $diameter, $diameter, 90, 90)
	$path.CloseFigure()
	$g.FillPath($brush, $path)
	$path.Dispose()
}
function Draw-CenteredText($g, [string]$text, [float]$centerX, [float]$y, $font, $brush) {
	$size = $g.MeasureString($text, $font)
	$g.DrawString($text, $font, $brush, $centerX - $size.Width / 2, $y)
}

$panel = New-Brush '#101827'
$captionBrush = New-Brush '#AFC4DE'
$white = New-Brush '#FFFFFF'
$outline = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#9CB1C9'), 2)
$stickBrush = New-Brush '#27364A'
$dpadBrush = New-Brush '#27364A'
$aBrush = New-Brush '#43B868'
$xBrush = New-Brush '#3D8EEA'
$yBrush = New-Brush '#D9AE35'
$bumperBrush = New-Brush '#66758A'
$labelFont = [System.Drawing.Font]::new('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$buttonFont = [System.Drawing.Font]::new('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
$smallButtonFont = [System.Drawing.Font]::new('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$captionFont = [System.Drawing.Font]::new('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

Draw-RoundedRect $graphics 0 0 1100 84 12 $panel

# Move icon: stick plus D-pad.
$graphics.FillEllipse($stickBrush, 119, 18, 36, 36)
$graphics.DrawEllipse($outline, 119, 18, 36, 36)
$graphics.FillEllipse($outline.Brush, 133, 32, 8, 8)
Draw-RoundedRect $graphics 167 18 12 36 3 $dpadBrush
Draw-RoundedRect $graphics 155 30 36 12 3 $dpadBrush
Draw-CenteredText $graphics 'MOVE  LS / D-PAD' 155 60 $captionFont $captionBrush

# Every button, letter, and caption is rendered into this same bitmap.
$buttons = @(
	@{ x = 285; color = $aBrush; letter = 'A'; caption = 'JUMP / CLIMB'; kind = 'round' },
	@{ x = 415; color = $xBrush; letter = 'X'; caption = 'ATTACK'; kind = 'round' },
	@{ x = 525; color = $yBrush; letter = 'Y'; caption = 'HOOK'; kind = 'round' },
	@{ x = 635; color = $bumperBrush; letter = 'LB'; caption = 'HOLD HOOK'; kind = 'wide' },
	@{ x = 745; color = $bumperBrush; letter = 'RB'; caption = 'DASH'; kind = 'wide' },
	@{ x = 850; color = $xBrush; letter = 'X'; caption = 'STICK / D-PAD DOWN + X'; kind = 'round' },
	@{ x = 1010; color = $bumperBrush; letter = 'MENU'; caption = 'RESET'; kind = 'wide' }
)
foreach ($button in $buttons) {
	if ($button.kind -eq 'round') {
		$graphics.FillEllipse($button.color, $button.x - 17, 19, 34, 34)
		Draw-CenteredText $graphics $button.letter $button.x 24 $buttonFont $white
	} else {
		Draw-RoundedRect $graphics ($button.x - 23) 20 46 32 9 $button.color
		Draw-CenteredText $graphics $button.letter $button.x 27 $smallButtonFont $white
	}
	Draw-CenteredText $graphics $button.caption $button.x 61 $captionFont $captionBrush
}

$bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$captionFont.Dispose(); $smallButtonFont.Dispose(); $buttonFont.Dispose(); $labelFont.Dispose()
$outline.Dispose(); $panel.Dispose(); $captionBrush.Dispose(); $white.Dispose(); $stickBrush.Dispose(); $dpadBrush.Dispose(); $aBrush.Dispose(); $xBrush.Dispose(); $yBrush.Dispose(); $bumperBrush.Dispose()
$graphics.Dispose(); $bitmap.Dispose()
