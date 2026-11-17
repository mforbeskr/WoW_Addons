# Generates the BambooBags textures (uncompressed 32-bit TGA, which the 3.3.5 client loads directly).
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File make_textures.ps1
# Changed textures need a full client restart, not just /reload.
# Note: PowerShell variable names ignore case ($S and $s are the same variable), so keep names distinct.

$out = Join-Path $PSScriptRoot "..\textures"
New-Item -ItemType Directory -Force $out | Out-Null

function New-Image($w, $h) { @{ W = $w; H = $h; Data = New-Object byte[] ($w * $h * 4) } }

function Set-Px($img, $x, $y, $r, $g, $b, $a) {
  # TGA rows are stored bottom-up
  $i = ((($img.H - 1 - $y) * $img.W) + $x) * 4
  $img.Data[$i]     = [byte][Math]::Max(0, [Math]::Min(255, $b))
  $img.Data[$i + 1] = [byte][Math]::Max(0, [Math]::Min(255, $g))
  $img.Data[$i + 2] = [byte][Math]::Max(0, [Math]::Min(255, $r))
  $img.Data[$i + 3] = [byte][Math]::Max(0, [Math]::Min(255, $a))
}

function Save-Tga($img, $name) {
  $header = New-Object byte[] 18
  $header[2] = 2                                  # uncompressed true-color
  $header[12] = $img.W -band 0xFF; $header[13] = $img.W -shr 8
  $header[14] = $img.H -band 0xFF; $header[15] = $img.H -shr 8
  $header[16] = 32                                # bits per pixel
  $header[17] = 8                                 # 8 alpha bits, bottom-left origin
  $fs = [IO.File]::Create((Join-Path $out "$name.tga"))
  $fs.Write($header, 0, 18)
  $fs.Write($img.Data, 0, $img.Data.Length)
  $fs.Close()
}

function Gauss($v, $center, $width) { [Math]::Exp(-[Math]::Pow(($v - $center) / $width, 2)) }

$rand = New-Object Random 7

# ---------- linen.tga: evening hemp linen, tileable 128x128 ----------
$linen = New-Image 128 128
$base = @(74, 64, 51)
$rowSlub = 0..127 | ForEach-Object { $rand.Next(-9, 10) }
$colSlub = 0..127 | ForEach-Object { $rand.Next(-9, 10) }
for ($y = 0; $y -lt 128; $y++) {
  for ($x = 0; $x -lt 128; $x++) {
    $over = ([Math]::Floor($x / 2) + [Math]::Floor($y / 2)) % 2
    if ($over -eq 0) { $v = $colSlub[$x] + $(if ($x % 2 -eq 0) { 6 } else { -3 }) }
    else             { $v = $rowSlub[$y] + $(if ($y % 2 -eq 0) { 4 } else { -5 }) }
    $v += $rand.Next(-4, 5)
    Set-Px $linen $x $y ($base[0] + $v) ($base[1] + $v) ($base[2] + $v * 0.8) 255
  }
}
Save-Tga $linen "linen"

# ---------- bamboo.tga: backdrop edge file, 8 squares of 32px ----------
# Drawn at 32px (the border shows it at ~10px), dark and low-contrast so it frames without shouting.
# Order: left, right, top, bottom, topleft, topright, bottomleft, bottomright.
# Top/bottom are drawn vertical; the client rotates them.
$SEG = 32
$STALK_LEFT = 5
$STALK_WIDTH = 22
$wetGreen = @(52, 76, 34)
$rope = @(104, 86, 60)
$mottle = 0..($SEG - 1) | ForEach-Object { $rand.Next(-7, 8) }
$fiber = 0..($SEG - 1) | ForEach-Object { $rand.Next(-6, 7) }
# Water droplets on the stalk: x, y, radius
$drops = @(@(10, 11, 1.6), @(19, 22, 1.2))

# Color across a wet stalk; t goes 0..1 from one side to the other
function Get-StalkColor($t, $var) {
  $t = [Math]::Min([Math]::Max($t, 0), 1)
  $shade = 0.32 + 0.68 * [Math]::Pow([Math]::Sin([Math]::PI * $t), 0.8)
  $spec = (Gauss $t 0.27 0.05) * 0.45      # wet highlight
  $sheen = (Gauss $t 0.36 0.12) * 0.1      # soft sheen around it
  $neon = (Gauss $t 0.8 0.07) * 0.3        # purple neon reflected on the shadow side
  @(
    ($wetGreen[0] * $shade + 255 * $spec + 200 * $sheen + 190 * $neon + $var),
    ($wetGreen[1] * $shade + 255 * $spec + 225 * $sheen + 70 * $neon + $var),
    ($wetGreen[2] * $shade + 255 * $spec + 150 * $sheen + 255 * $neon + $var * 0.6)
  )
}

function Draw-Stalk($img, $ox) {
  for ($y = 0; $y -lt $SEG; $y++) {
    $isNode = $y -eq 1
    $lo = $(if ($isNode) { $STALK_LEFT - 1 } else { $STALK_LEFT })
    $hi = $STALK_LEFT + $STALK_WIDTH + $(if ($isNode) { 1 } else { 0 })
    for ($x = 0; $x -lt $SEG; $x++) {
      $cover = [Math]::Min([Math]::Min($x - $lo + 1, $hi - $x), 1)
      if ($cover -le 0) { Set-Px $img ($ox + $x) $y 0 0 0 0; continue }
      $col = Get-StalkColor (($x - $STALK_LEFT) / $STALK_WIDTH) ($mottle[$y] + $fiber[$x])

      # Node: a soft groove with a faint ridge. The border repeats this tile every few pixels,
      # so a strong node would make the stalk look like a segmented pipe
      $k = 1.0
      if ($y -eq 1) { $k = 0.8 } elseif ($y -eq 2) { $k = 1.06 }

      $highlight = $false
      foreach ($drop in $drops) {
        $ddx = $x - $drop[0]; $ddy = $y - $drop[1]; $rad = $drop[2]
        $dd = [Math]::Sqrt($ddx * $ddx + $ddy * $ddy)
        if ($dd -lt $rad) {
          $k *= 0.8
          $hx = $ddx + 0.4 * $rad; $hy = $ddy + 0.4 * $rad
          if ([Math]::Sqrt($hx * $hx + $hy * $hy) -lt 0.45 * $rad) { $highlight = $true }
          elseif ($ddy -gt 0.4 * $rad) { $k *= 0.7 }
        } elseif ($dd -lt $rad + 1.2 -and $ddy -gt 0) {
          $k *= 0.8
        }
      }
      if ($highlight) { Set-Px $img ($ox + $x) $y 150 160 175 (255 * $cover); continue }
      Set-Px $img ($ox + $x) $y ($col[0] * $k) ($col[1] * $k) ($col[2] * $k) (255 * $cover)
    }
  }
}

# Corner: two stalks crossing, X-lashed with wet hemp rope and a knot on top
function Draw-Lashing($img, $ox) {
  $c = 15.5; $hw = $STALK_WIDTH / 2
  for ($y = 0; $y -lt $SEG; $y++) {
    for ($x = 0; $x -lt $SEG; $x++) {
      $dx = $x - $c; $dy = $y - $c
      $col = $null; $alpha = 0

      $coverV = [Math]::Min($hw - [Math]::Abs($dx) + 0.5, 1)
      $coverH = [Math]::Min($hw - [Math]::Abs($dy) + 0.5, 1)
      if ($coverV -gt 0) {
        $col = Get-StalkColor (($x - $STALK_LEFT) / $STALK_WIDTH) ($mottle[$y] + $fiber[$x]); $alpha = $coverV
      } elseif ($coverH -gt 0) {
        $col = Get-StalkColor (($y - $STALK_LEFT) / $STALK_WIDTH) ($mottle[$x] + $fiber[$y]); $alpha = $coverH
      }

      # Rope wraps along both diagonals over the crossing
      if ([Math]::Abs($dx) -lt $hw + 2 -and [Math]::Abs($dy) -lt $hw + 2) {
        foreach ($dir in 1, -1) {
          $p = ($dx - $dir * $dy) / 1.414
          $along = ($dx + $dir * $dy) / 1.414
          if ([Math]::Abs($p) -lt 5.5 -and [Math]::Abs($along) -lt $hw * 1.35) {
            $v = (($p + 5.5) % 3.67) / 3.67
            if ($v -lt 0.85) {
              $vv = $v / 0.85
              $shade = 0.45 + 0.55 * [Math]::Sin([Math]::PI * $vv)
              $twist = 0.82 + 0.18 * [Math]::Sin($along * 2.8 + $vv * 4)
              $spec = (Gauss $vv 0.3 0.12) * 35
              $col = @(($rope[0] * $shade * $twist + $spec), ($rope[1] * $shade * $twist + $spec), ($rope[2] * $shade * $twist + $spec * 0.9))
              $alpha = 1
            }
          }
        }
      }

      # Knot
      $kd = [Math]::Sqrt($dx * $dx + $dy * $dy)
      if ($kd -lt 3.25) {
        $shade = 0.55 + 0.45 * (1 - $kd / 3.25)
        $spec = (Gauss ($dx + $dy) -2 1.25) * 40
        $col = @(($rope[0] * $shade + $spec), ($rope[1] * $shade + $spec), ($rope[2] * $shade + $spec))
        $alpha = [Math]::Min(3.25 - $kd + 0.5, 1)
      }

      if ($col) { Set-Px $img ($ox + $x) $y $col[0] $col[1] $col[2] (255 * $alpha) }
      else { Set-Px $img ($ox + $x) $y 0 0 0 0 }
    }
  }
}

$edge = New-Image ($SEG * 8) $SEG
for ($i = 0; $i -lt 4; $i++) { Draw-Stalk $edge ($i * $SEG) }
for ($i = 4; $i -lt 8; $i++) { Draw-Lashing $edge ($i * $SEG) }
Save-Tga $edge "bamboo"

# ---------- glow.tga: soft white radial glow, tinted purple in game ----------
$glow = New-Image 64 64
for ($y = 0; $y -lt 64; $y++) {
  for ($x = 0; $x -lt 64; $x++) {
    $d = [Math]::Sqrt([Math]::Pow($x - 31.5, 2) + [Math]::Pow($y - 31.5, 2)) / 32
    $a = [Math]::Pow([Math]::Max(0, 1 - $d), 2)
    Set-Px $glow $x $y 255 255 255 (255 * $a)
  }
}
Save-Tga $glow "glow"

"Textures written to $out"
