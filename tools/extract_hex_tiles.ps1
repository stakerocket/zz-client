Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\Aceton\.cursor\projects\d-OSPanel-home-zonezero\assets\image-2db0a1ec-b8c9-4c99-ba7c-32d688224bcc.jpg"
$outDir = "d:\OSPanel\home\zonezero\client\assets\battle\hex"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$src = [System.Drawing.Bitmap]::FromFile($srcPath)
$tw = 56
$th = 38

function Test-InPointyHex([float]$px, [float]$py, [float]$cx, [float]$cy, [float]$rx, [float]$ry) {
	# Same verts as ZZPixelArt._hex_points: -30 + 60*i
	$pts = @()
	for ($i = 0; $i -lt 6; $i++) {
		$a = (-30.0 + 60.0 * $i) * [Math]::PI / 180.0
		$pts += ,([PSCustomObject]@{ X = $cx + [Math]::Cos($a) * $rx; Y = $cy + [Math]::Sin($a) * $ry })
	}
	$inside = $false
	$j = 5
	for ($i = 0; $i -lt 6; $i++) {
		$pi = $pts[$i]; $pj = $pts[$j]
		if ((($pi.Y -gt $py) -ne ($pj.Y -gt $py)) -and ($px -lt (($pj.X - $pi.X) * ($py - $pi.Y) / (($pj.Y - $pi.Y) + 0.0001) + $pi.X))) {
			$inside = -not $inside
		}
		$j = $i
	}
	return $inside
}

function Make-HexTile([System.Drawing.Bitmap]$Source, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$OutPath) {
	$rect = New-Object System.Drawing.Rectangle $X, $Y, $W, $H
	$crop = $Source.Clone($rect, $Source.PixelFormat)
	$scaled = New-Object System.Drawing.Bitmap $tw, $th, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$g = [System.Drawing.Graphics]::FromImage($scaled)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.Clear([System.Drawing.Color]::Transparent)
	$g.DrawImage($crop, 0, 0, $tw, $th)
	$g.Dispose()
	$crop.Dispose()

	$cx = $tw * 0.5
	$cy = $th * 0.5
	$rx = $tw * 0.5
	$ry = $th * 0.5
	$out = New-Object System.Drawing.Bitmap $tw, $th, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	for ($yy = 0; $yy -lt $th; $yy++) {
		for ($xx = 0; $xx -lt $tw; $xx++) {
			$px = $xx + 0.5
			$py = $yy + 0.5
			if (Test-InPointyHex $px $py $cx $cy $rx $ry) {
				$c = $scaled.GetPixel($xx, $yy)
				$out.SetPixel($xx, $yy, [System.Drawing.Color]::FromArgb(255, $c.R, $c.G, $c.B))
			} else {
				$out.SetPixel($xx, $yy, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
			}
		}
	}
	# Thin dark outline on opaque edge
	$edge = [System.Drawing.Color]::FromArgb(255, 18, 16, 14)
	$marks = New-Object System.Collections.Generic.List[object]
	for ($yy = 0; $yy -lt $th; $yy++) {
		for ($xx = 0; $xx -lt $tw; $xx++) {
			if ($out.GetPixel($xx, $yy).A -lt 128) { continue }
			$border = $false
			foreach ($d in @(@(1,0),@(-1,0),@(0,1),@(0,-1))) {
				$nx = $xx + $d[0]; $ny = $yy + $d[1]
				if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $tw -or $ny -ge $th -or $out.GetPixel($nx, $ny).A -lt 128) {
					$border = $true; break
				}
			}
			if ($border) { $marks.Add(@($xx, $yy)) }
		}
	}
	foreach ($m in $marks) {
		$out.SetPixel($m[0], $m[1], $edge)
	}
	$out.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
	$scaled.Dispose()
	$out.Dispose()
	Write-Host "saved $OutPath from crop ${X},${Y} ${W}x${H}"
}

# Crops of relatively empty floor (avoid UI/units/cover labels). Tuned for 1024x558 board.
# dirt / brown
Make-HexTile $src 310 310 70 48 (Join-Path $outDir "hex_dirt_01.png")
Make-HexTile $src 380 340 70 48 (Join-Path $outDir "hex_dirt_02.png")
# cracked / grey concrete
Make-HexTile $src 470 300 70 48 (Join-Path $outDir "hex_cracked_01.png")
Make-HexTile $src 250 280 70 48 (Join-Path $outDir "hex_cracked_02.png")
# dry grass patches
Make-HexTile $src 420 250 70 48 (Join-Path $outDir "hex_grass_01.png")
Make-HexTile $src 340 270 70 48 (Join-Path $outDir "hex_grass_02.png")
# rubble-ish
Make-HexTile $src 520 330 70 48 (Join-Path $outDir "hex_rubble_01.png")
Make-HexTile $src 290 350 70 48 (Join-Path $outDir "hex_scorched_01.png")

# Also save a preview strip of raw crops for QA
$preview = New-Object System.Drawing.Bitmap 560 48, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$pg = [System.Drawing.Graphics]::FromImage($preview)
$pg.Clear([System.Drawing.Color]::Magenta)
$i = 0
foreach ($name in @("hex_dirt_01.png","hex_dirt_02.png","hex_cracked_01.png","hex_cracked_02.png","hex_grass_01.png","hex_grass_02.png","hex_rubble_01.png","hex_scorched_01.png")) {
	$p = Join-Path $outDir $name
	if (Test-Path $p) {
		$t = [System.Drawing.Bitmap]::FromFile($p)
		$pg.DrawImage($t, $i * 70, 5, 56, 38)
		$t.Dispose()
		$i++
	}
}
$pg.Dispose()
$preview.Save((Join-Path $outDir "_preview_strip.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$preview.Dispose()
$src.Dispose()
Write-Host "done"
