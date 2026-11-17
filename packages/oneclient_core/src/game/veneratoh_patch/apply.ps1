# Veneratoh Client: puts the custom branding back into the PolyPlus mod.
# Runs right before launch, on the copies inside the game folders only.
param([string]$Clusters = "", [string]$Shared = "")
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$marker = "veneratoh.patched"
$version = "3"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = @(Get-ChildItem -LiteralPath $here -File | Where-Object { $_.Extension -in ".svg", ".png", ".json", ".class" })

$jars = @()
foreach ($d in @($Clusters, $Shared)) {
  if ($d -and (Test-Path -LiteralPath $d)) {
    $jars += @(Get-ChildItem -LiteralPath $d -Recurse -Depth 3 -Filter "polyplus-*.jar" -File -ErrorAction SilentlyContinue)
  }
}

function Test-Patched($path) {
  $z = [IO.Compression.ZipFile]::OpenRead($path)
  try {
    $e = $z.GetEntry($marker)
    if ($null -eq $e) { return $false }
    $r = New-Object IO.StreamReader($e.Open())
    $v = $r.ReadToEnd()
    $r.Dispose()
    return ($v.Trim() -eq $version)
  } finally {
    $z.Dispose()
  }
}

foreach ($j in $jars) {
  try {
    $path = $j.FullName
    $item = Get-Item -LiteralPath $path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      # a link into the download cache: never touch the cache copy, patch a private copy
      $target = $item.Target
      if ($target -is [array]) { $target = $target[0] }
      if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path -Parent $path) $target }
      $tmp = "$path.vtmp"
      Copy-Item -LiteralPath $target -Destination $tmp -Force
      Remove-Item -LiteralPath $path -Force
      Move-Item -LiteralPath $tmp -Destination $path -Force
    }
    if (Test-Patched $path) { continue }

    $z = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Update)
    try {
      foreach ($f in $files) {
        $name = ($f.Name -replace '__', '/') -replace '--S--', '$'
        $old = $z.GetEntry($name)
        if ($old) { $old.Delete() }
        $e = $z.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
        $s = $e.Open()
        $b = [IO.File]::ReadAllBytes($f.FullName)
        $s.Write($b, 0, $b.Length)
        $s.Dispose()
      }
      $old = $z.GetEntry($marker)
      if ($old) { $old.Delete() }
      $m = $z.CreateEntry($marker)
      $w = New-Object IO.StreamWriter($m.Open())
      $w.Write($version)
      $w.Dispose()
    } finally {
      $z.Dispose()
    }
    Write-Output "patched $path"
  } catch {
    [Console]::Error.WriteLine("failed $($j.FullName): $($_.Exception.Message)")
  }
}

# ---- Free community cosmetics for every Veneratoh Client player: MinecraftCapes ----
# Open source (LGPL-2.1). Everybody who runs it sees everybody else's capes.
function Get-CapesJar {
  $cache = Join-Path $here "mods"
  New-Item -ItemType Directory -Force -Path $cache | Out-Null
  $have = Get-ChildItem -LiteralPath $cache -Filter "*.jar" -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($have) { return $have.FullName }

  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $api = 'https://api.modrinth.com/v2/project/minecraftcapes/version?game_versions=%5B%221.8.9%22%5D&loaders=%5B%22ornithe%22%5D'
  $versions = @(Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'VeneratohClient/1.0 (launcher)' } -TimeoutSec 25)
  if ($versions.Count -eq 0) { throw "MinecraftCapes: nessuna versione per 1.8.9 / Ornithe" }
  $file = @($versions[0].files | Where-Object { $_.primary })[0]
  if (-not $file) { $file = @($versions[0].files)[0] }
  $dest = Join-Path $cache $file.filename
  Invoke-WebRequest -Uri $file.url -OutFile $dest -UseBasicParsing -TimeoutSec 90
  $sha = (Get-FileHash -LiteralPath $dest -Algorithm SHA1).Hash.ToLower()
  if ($file.hashes.sha1 -and $sha -ne $file.hashes.sha1.ToLower()) {
    Remove-Item -LiteralPath $dest -Force
    throw "MinecraftCapes: hash non valido, scaricamento scartato"
  }
  return $dest
}

try {
  $dirs = @($jars | ForEach-Object { $_.DirectoryName } | Select-Object -Unique)
  if ($dirs.Count -gt 0) {
    $capes = $null
    foreach ($dir in $dirs) {
      $present = Get-ChildItem -LiteralPath $dir -Filter "*minecraftcapes*.jar" -File -ErrorAction SilentlyContinue
      if ($present) { continue }
      if (-not $capes) { $capes = Get-CapesJar }
      Copy-Item -LiteralPath $capes -Destination (Join-Path $dir (Split-Path -Leaf $capes)) -Force
      Write-Output "capes installate in $dir"
    }
  }
} catch {
  [Console]::Error.WriteLine("capes: $($_.Exception.Message)")
}

exit 0
