# Presets the map editor for this package (run by open-map-editor.bat; README.txt "Map editor"). The editor keeps its
# settings in the registry, HKCU\<mapeditor\settings-key.txt> (written by the package build from the program itself).
# It sets, and keeps every other setting:
#   - the folder of the 10.98 client profile: mapeditor\client (Tibia.dat, Tibia.spr, Tibia.otfi, items.otb)
#   - the selected client profile: 10.98
#   - with -Map: that map first in "Recent maps", opened with the 10.98 profile
#   - the script of Tools > Lua Scripts: mapeditor\cinders\generate_area.lua, while none or a missing one is set
# Without settings-key.txt it changes nothing (the clicks are in README.txt).
param([string]$Package, [string]$Map = '')
$ErrorActionPreference = 'Stop'
$Package = (Resolve-Path -LiteralPath $Package).Path
$ed = Join-Path $Package 'mapeditor'
$keyFile = Join-Path $ed 'settings-key.txt'
if (-not (Test-Path -LiteralPath $keyFile)) {
    Write-Host 'No mapeditor\settings-key.txt: choose the client folder once in the editor (README.txt).'
    exit 0
}
$sub = (Get-Content -LiteralPath $keyFile -TotalCount 1).Trim()
if ($sub -notmatch '^Software\\[A-Za-z0-9_.-]+\\[A-Za-z0-9_.-]+$') {
    Write-Host "mapeditor\settings-key.txt holds no settings key: nothing preset."
    exit 0
}
$key = 'HKCU:\' + $sub
if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }

function Fwd([string]$p) { return ($p -replace '\\', '/') }
function Read-Json([string]$name) {
    $item = Get-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    try { return ($item.$name | ConvertFrom-Json) } catch { return $null }
}
function Write-Value([string]$name, [string]$value) {
    Set-ItemProperty -LiteralPath $key -Name $name -Value $value -Type String
}

# the 10.98 profile's client folder
$client = Fwd (Join-Path $ed 'client')
$paths = Read-Json 'clientPathsJson'
if ($null -eq $paths -or $paths -is [array]) { $paths = New-Object PSObject }
$paths | Add-Member -NotePropertyName '1098' -NotePropertyValue $client -Force
Write-Value 'clientPathsJson' ($paths | ConvertTo-Json -Compress)
Write-Value 'selectedClientKey' '1098'

if ($Map -ne '') {
    $m = Fwd ((Resolve-Path -LiteralPath $Map).Path)
    $recent = @(Read-Json 'recentMapsJson') | Where-Object { $_ -is [string] -and $_ -ne '' -and $_ -ne $m }
    $list = @(@($m) + @($recent) | Select-Object -First 12)
    Write-Value 'recentMapsJson' (ConvertTo-Json -InputObject $list -Compress)
    $profiles = Read-Json 'mapProfilesJson'
    if ($null -eq $profiles -or $profiles -is [array]) { $profiles = New-Object PSObject }
    $profiles | Add-Member -NotePropertyName $m -NotePropertyValue '1098' -Force
    Write-Value 'mapProfilesJson' ($profiles | ConvertTo-Json -Compress)
}

# Tools > Lua Scripts: our generator, unless another existing script is chosen
$lua = Join-Path $key 'luaGenerator'
if (-not (Test-Path -LiteralPath $lua)) { New-Item -Path $lua -Force | Out-Null }
$cur = (Get-ItemProperty -LiteralPath $lua -Name 'scriptPath' -ErrorAction SilentlyContinue).scriptPath
if (-not $cur -or -not (Test-Path -LiteralPath $cur)) {
    Set-ItemProperty -LiteralPath $lua -Name 'scriptPath' -Value (Fwd (Join-Path $ed 'cinders\generate_area.lua')) -Type String
}
Write-Host "Map editor settings: client 10.98 = $client"
