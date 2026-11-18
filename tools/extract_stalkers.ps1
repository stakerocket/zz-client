Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\Aceton\.cursor\projects\d-OSPanel-home-zonezero\assets\image-f6da2497-b57d-49e9-ad9c-ca596ed64f2d.jpg"
$outDir = "d:\OSPanel\home\zonezero\client\assets\units"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$src = [System.Drawing.Bitmap]::FromFile($srcPath)

function Test-Bg([System.Drawing.Color]$c) {
	$r = [int]$c.R; $g = [int]$c.G; $b = [int]$c.B
	$lum = ($r + $g + $b) / 3.0
	# cyan / blue UI glow
	if ($b -gt 130 -and $b -gt $r + 25 -and $g -gt 90) { return $true }
	# red selection glow
	if ($r -gt 140 -and $r -gt $g + 35 -and $r -gt $b + 35 -and $g -lt 120) { return $true }
	# desaturated ground
	$maxc = [Math]::Max($r, [Math]::Max($g, $b))
	$minc = [Math]::Min($r, [Math]::Min($g, $b))
	$sat = $maxc - $minc
	if ($lum -gt 50 -and $lum -lt 185 -and $sat -lt 42) { return $true }
	# pale UI
	if ($lum -gt 205) { return $true }
	# blue panel
	if ($b -gt 80 -and $b -gt $r + 40 -and $r -lt 80 -and $g -lt 100) { return $true }
	return $false
}

function Extract-Sprite {
	param(
		[System.Drawing.Bitmap]$Source,
		[int]$X, [int]$Y, [int]$W, [int]$H,
		[string]$OutPath
	)
	$rect = New-Object System.Drawing.Rectangle $X, $Y, $W, $H
	$crop = $Source.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$visited = New-Object "bool[,]" $W, $H
	$qx = New-Object System.Collections.Generic.Queue[int]
	$qy = New-Object System.Collections.Generic.Queue[int]
	for ($i = 0; $i -lt $W; $i++) {
		$qx.Enqueue($i); $qy.Enqueue(0)
		$qx.Enqueue($i); $qy.Enqueue($H - 1)
	}
	for ($j = 0; $j -lt $H; $j++) {
		$qx.Enqueue(0); $qy.Enqueue($j)
		$qx.Enqueue($W - 1); $qy.Enqueue($j)
	}
	while ($qx.Count -gt 0) {
		$px = $qx.Dequeue()
		$py = $qy.Dequeue()
		if ($px -lt 0 -or $py -lt 0 -or $px -ge $W -or $py -ge $H) { continue }
		if ($visited[$px, $py]) { continue }
		$visited[$px, $py] = $true
		$col = $crop.GetPixel($px, $py)
		$isDark = ($col.R -lt 40 -and $col.G -lt 40 -and $col.B -lt 40)
		if ($isDark) { continue }
		if (-not (Test-Bg $col)) { continue }
		$crop.SetPixel($px, $py, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
		$qx.Enqueue($px + 1); $qy.Enqueue($py)
		$qx.Enqueue($px - 1); $qy.Enqueue($py)
		$qx.Enqueue($px); $qy.Enqueue($py + 1)
		$qx.Enqueue($px); $qy.Enqueue($py - 1)
	}
	# also punch remaining bg islands by direct pass (non-flood)
	for ($py = 0; $py -lt $H; $py++) {
		for ($px = 0; $px -lt $W; $px++) {
			$col = $crop.GetPixel($px, $py)
			if ($col.A -eq 0) { continue }
			if (Test-Bg $col) {
				# only clear if neighbor already transparent or edge-ish to avoid eating camo
				$edge = $false
				foreach ($d in @(@(1,0),@(-1,0),@(0,1),@(0,-1))) {
					$nx = $px + $d[0]; $ny = $py + $d[1]
					if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $W -or $ny -ge $H) { $edge = $true; break }
					if ($crop.GetPixel($nx, $ny).A -lt 10) { $edge = $true; break }
				}
				if ($edge) {
					$crop.SetPixel($px, $py, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
				}
			}
		}
	}
	$minx = $W; $miny = $H; $maxx = -1; $maxy = -1
	for ($py = 0; $py -lt $H; $py++) {
		for ($px = 0; $px -lt $W; $px++) {
			if ($crop.GetPixel($px, $py).A -gt 20) {
				if ($px -lt $minx) { $minx = $px }
				if ($py -lt $miny) { $miny = $py }
				if ($px -gt $maxx) { $maxx = $px }
				if ($py -gt $maxy) { $maxy = $py }
			}
		}
	}
	if ($maxx -lt $minx) {
		Write-Host "empty $OutPath"
		$crop.Dispose()
		return
	}
	$tw = $maxx - $minx + 1
	$th = $maxy - $miny + 1
	$trimRect = New-Object System.Drawing.Rectangle $minx, $miny, $tw, $th
	$trim = $crop.Clone($trimRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$trim.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
	Write-Host "saved $OutPath ${tw}x${th}"
	$crop.Dispose()
	$trim.Dispose()
}

# Blue stalker (facing right) — body under blue dossier tip
Extract-Sprite -Source $src -X 218 -Y 222 -W 72 -H 92 -OutPath (Join-Path $outDir "stalker_blue.png")
# Red stalker (facing left)
Extract-Sprite -Source $src -X 730 -Y 215 -W 78 -H 100 -OutPath (Join-Path $outDir "stalker_red.png")

$src.Dispose()
