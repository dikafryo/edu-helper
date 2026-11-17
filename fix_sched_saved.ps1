$ErrorActionPreference='Continue'
$path = Join-Path $env:LOCALAPPDATA 'PenHelper\schedules.json'
$mapPath = Join-Path $env:LOCALAPPDATA 'PenHelper\gcal_saved.json'
$raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
$arr = $raw | ConvertFrom-Json
$map = @{}
if (Test-Path $mapPath) {
  $mj = [IO.File]::ReadAllText($mapPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  foreach ($p in $mj.PSObject.Properties) { $map[$p.Name] = $true }
}
$out = @()
foreach ($s in @($arr)) {
  $gs = [bool]$s.GoogleSaved
  if (-not $gs -and $map.ContainsKey([string]$s.Id)) { $gs = $true }
  $out += [pscustomobject]@{
    Id=$s.Id; Title=$s.Title; Body=$s.Body; Date=$s.Date
    Source=$s.Source; Created=$s.Created; GoogleSaved=$gs
  }
  Write-Host ("{0} saved={1}" -f $s.Id, $gs)
}
$json = $out | ConvertTo-Json -Depth 6
$utf8 = New-Object Text.UTF8Encoding $true
[IO.File]::WriteAllText($path, $json, $utf8)
Write-Host 'updated'
