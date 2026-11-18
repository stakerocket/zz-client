Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\Aceton\.cursor\projects\d-OSPanel-home-zonezero\assets\stalker_atlas.jpg"
$outDir = "d:\OSPanel\home\zonezero\client\assets\units"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$src = [System.Drawing.Bitmap]::FromFile($srcPath)
$w = $src.Width
$h = $src.Height
$frames = 8
$cellW = [int]($w / $frames)
$cellH = $h

function Is-Green([System.Drawing.Color]$c) {
	# neon green chromakey + slight spill
	if ($c.G -lt 140) { return $false }
	if ($c.G -le $c.R + 40) { return $false }
	if ($c.G -le $c.B + 40) { return $false }
	return $true
}

function Despill([System.Drawing.Color]$c) {
	if ($c.G -gt $c.R + 15 -and $c.G -gt $c.B + 15) {
		$ng = [Math]::Min($c.G, [int](($c.R + $c.B) / 2 + 20))
		return [System.Drawing.Color]::FromArgb($c.A, $c.R, $ng, $c.B)
	}
	return $c
}

# Full RGBA canvas
$keyed = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $h; $y++) {
	for ($x = 0; $x -lt $w; $x++) {
		$c = $src.GetPixel($x, $y)
		if (Is-Green $c) {
			$keyed.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
		} else {
			$keyed.SetPixel($x, $y, (Despill $c))
		}
	}
}

$names = @("idle_0", "idle_1", "walk_0", "walk_1", "walk_2", "sit", "cover", "death")
$frameBitmaps = @()
$maxFw = 0
$maxFh = 0

for ($i = 0; $i -lt $frames; $i++) {
	$x0 = $i * $cellW
	$minx = $cellW; $miny = $cellH; $maxx = -1; $maxy = -1
	for ($y = 0; $y -lt $cellH; $y++) {
		for ($x = 0; $x -lt $cellW; $x++) {
			$c = $keyed.GetPixel($x0 + $x, $y)
			if ($c.A -gt 20) {
				if ($x -lt $minx) { $minx = $x }
				if ($y -lt $miny) { $miny = $y }
				if ($x -gt $maxx) { $maxx = $x }
				if ($y -gt $maxy) { $maxy = $y }
			}
		}
	}
	if ($maxx -lt $minx) {
		Write-Host "empty frame $i"
		continue
	}
	$fw = $maxx - $minx + 1
	$fh = $maxy - $miny + 1
	$fb = New-Object System.Drawing.Bitmap $fw, $fh, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$g = [System.Drawing.Graphics]::FromImage($fb)
	$g.Clear([System.Drawing.Color]::Transparent)
	$g.DrawImage($keyed, (New-Object System.Drawing.Rectangle 0,0,$fw,$fh), (New-Object System.Drawing.Rectangle ($x0+$minx),$miny,$fw,$fh), [System.Drawing.GraphicsUnit]::Pixel)
	$g.Dispose()
	$path = Join-Path $outDir ("stalker_" + $names[$i] + ".png")
	$fb.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
	Write-Host "frame $($names[$i]) ${fw}x${fh} -> $path"
	$frameBitmaps += ,@{Bmp=$fb; Name=$names[$i]; W=$fw; H=$fh}
	if ($fw -gt $maxFw) { $maxFw = $fw }
	if ($fh -gt $maxFh) { $maxFh = $fh }
}

# Pack uniform atlas: 8 cells of maxFw x maxFh, feet-aligned bottom-center
$pad = 2
$aw = ($maxFw + $pad * 2) * $frames
$ah = $maxFh + $pad * 2
$atlas = New-Object System.Drawing.Bitmap $aw, $ah, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$ag = [System.Drawing.Graphics]::FromImage($atlas)
$ag.Clear([System.Drawing.Color]::Transparent)
$cellUW = $maxFw + $pad * 2
for ($i = 0; $i -lt $frameBitmaps.Count; $i++) {
	$info = $frameBitmaps[$i]
	$dx = $i * $cellUW + $pad + [int](($maxFw - $info.W) / 2)
	$dy = $pad + ($maxFh - $info.H) # feet align bottom
	$ag.DrawImage($info.Bmp, $dx, $dy, $info.W, $info.H)
}
$ag.Dispose()
$atlasPath = Join-Path $outDir "stalker_atlas.png"
$atlas.Save($atlasPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "atlas $aw x $ah cell=$cellUW x $($maxFh+$pad*2) -> $atlasPath"

# meta for Godot
$meta = @"
{
  "frames": 8,
  "names": ["idle_0","idle_1","walk_0","walk_1","walk_2","sit","cover","death"],
  "cell_w": $cellUW,
  "cell_h": $($maxFh + $pad * 2),
  "pad": $pad,
  "content_w": $maxFw,
  "content_h": $maxFh
}
"@
Set-Content -Path (Join-Path $outDir "stalker_atlas.json") -Value $meta -Encoding UTF8

foreach ($info in $frameBitmaps) { $info.Bmp.Dispose() }
$atlas.Dispose()
$keyed.Dispose()
$src.Dispose()
