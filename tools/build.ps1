<#
	Builds dist\Amity-<version>.zip for a manual CurseForge upload.
	The zip contains a single "Amity" folder, the same layout the packager makes.

	Usage:  powershell -ExecutionPolicy Bypass -File tools\build.ps1 [-Version 0.1.0-beta]
	Without -Version the newest "## [x.y.z]" entry of CHANGELOG.md is used.
#>
param([string]$Version)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (-not $Version) {
	$m = Select-String -Path (Join-Path $root "CHANGELOG.md") -Pattern '^## \[(\d+\.\d+\.\d+[^\]]*)\]' | Select-Object -First 1
	if (-not $m) { throw "No version given and none found in CHANGELOG.md" }
	$Version = $m.Matches[0].Groups[1].Value
}

# Everything the addon needs at runtime; keep in sync with .pkgmeta's ignore list.
$include = @("Amity.toc", "Core.lua", "Minimap.lua", "Panel.lua", "Modules", "Media", "CHANGELOG.md", "LICENSE")

$dist = Join-Path $root "dist"
$stage = Join-Path $dist "Amity"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null

foreach ($item in $include) {
	Copy-Item -Recurse (Join-Path $root $item) $stage
}

$toc = Join-Path $stage "Amity.toc"
# no BOM in the TOC
$text = [IO.File]::ReadAllText($toc).Replace("@project-version@", $Version)
[IO.File]::WriteAllText($toc, $text, (New-Object Text.UTF8Encoding($false)))

$zip = Join-Path $dist "Amity-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
# Write the entries by hand: Compress-Archive and ZipFile on Windows PowerShell
# store "\" separators, which other unzip tools treat as part of the file name.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
	Get-ChildItem -Recurse -File $stage | ForEach-Object {
		$name = "Amity/" + $_.FullName.Substring($stage.Length + 1).Replace("\", "/")
		[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $name, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
	}
} finally {
	$archive.Dispose()
}
Remove-Item -Recurse -Force $stage
Write-Host "Built $zip"
