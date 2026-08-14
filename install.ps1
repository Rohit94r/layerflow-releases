# LayerFlow CLI installer for Windows (PowerShell 5.1+ / PowerShell 7).
#
# One line (run in Windows PowerShell or Windows Terminal):
#   powershell -ExecutionPolicy Bypass -c "irm https://layerflow.dev/install.ps1 | iex"
# or simply:
#   irm https://layerflow.dev/install.ps1 | iex
#
# Downloads the prebuilt lf.exe for your CPU from the public
# Rohit94r/layerflow-releases repo, verifies its SHA-256 checksum, installs
# it to $HOME\.local\bin, and adds that folder to your user PATH.
# Also creates a `layerflow.exe` copy so both `lf` and `layerflow` work.
#
# NOTE: this script runs in YOUR PowerShell session (via iex). We never call
# `exit`, because that would close your terminal. Errors use `throw`.
#
# Options:
#   $env:VERSION   install a specific version, e.g. 0.2.3 (default: latest)
#   $env:INSTALL_DIR   override the install folder (default: $HOME\.local\bin)
#
# Examples:
#   $env:VERSION = "0.2.3"; irm https://layerflow.dev/install.ps1 | iex
#   $env:INSTALL_DIR = "C:\tools\bin"; irm https://layerflow.dev/install.ps1 | iex

$ErrorActionPreference = "Stop"

$Repo      = "Rohit94r/layerflow-releases"
$App       = "lf"
$Alias     = "layerflow"
$Dest      = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $HOME ".local\bin" }
$Version   = if ($env:VERSION) { $env:VERSION } else { "latest" }

Write-Host ""
Write-Host "  LayerFlow CLI installer" -ForegroundColor Cyan

# ── Resolve the latest release tag ─────────────────────────────────────────
if ($Version -eq "latest") {
    Write-Host "  Resolving latest release..." -ForegroundColor DarkGray
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    $Version = $release.tag_name
}
$Version = $Version.TrimStart("v")
$Base = "https://github.com/$Repo/releases/download/v$Version"

# ── Detect CPU architecture ────────────────────────────────────────────────
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -eq "AMD64") {
    $osarch = "amd64"
} elseif ($arch -eq "ARM64") {
    $osarch = "arm64"
} elseif ($arch -eq "x86") {
    # 32-bit PowerShell on a 64-bit OS -> install the 64-bit build.
    if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") { $osarch = "amd64" }
    else { throw "Unsupported architecture: $arch" }
} else {
    throw "Unsupported architecture: $arch (supported: amd64, arm64)"
}

$Archive = "lf_${Version}_windows_${osarch}.zip"
$ArchiveUrl = "$Base/$Archive"

# ── Download ───────────────────────────────────────────────────────────────
Write-Host "  Downloading $App $Version (windows/$osarch)..." -ForegroundColor DarkGray
$zip = Join-Path $env:TEMP $Archive
try {
    Invoke-WebRequest -Uri $ArchiveUrl -OutFile $zip
} catch {
    # Not every release ships a windows_arm64 build yet. Windows on ARM runs
    # x64 apps via emulation, so fall back to the amd64 build in that case.
    if ($osarch -eq "arm64") {
        Write-Host "  No windows/arm64 build for $Version — using windows/amd64 (runs via Windows on ARM emulation)." -ForegroundColor Yellow
        $osarch = "amd64"
        $Archive = "lf_${Version}_windows_${osarch}.zip"
        $ArchiveUrl = "$Base/$Archive"
        $zip = Join-Path $env:TEMP $Archive
        Invoke-WebRequest -Uri $ArchiveUrl -OutFile $zip
    } else {
        throw "Download failed: $ArchiveUrl ($_)"
    }
}
if (-not (Test-Path $zip)) {
    throw "Download failed: $ArchiveUrl"
}

# ── Verify SHA-256 against the release checksums.txt ───────────────────────
try {
    # GoReleaser serves checksums.txt as application/octet-stream, so PS7
    # returns .Content as Byte[]. Decode it to text before splitting.
    $resp = Invoke-WebRequest -Uri "$Base/checksums.txt" -UseBasicParsing
    if ($resp.Content -is [byte[]]) {
        $checksums = [Text.Encoding]::UTF8.GetString($resp.Content) -split "`r?`n"
    } else {
        $checksums = ([string]$resp.Content) -split "`r?`n"
    }
} catch {
    Write-Host "  Warning: could not fetch checksums.txt ($_) — skipping verification." -ForegroundColor Yellow
    $checksums = @()
}
$want = ($checksums | Where-Object { $_ -match "\s+$([regex]::Escape($Archive))\s*$" }) -split "\s+" | Select-Object -First 1
if ($want) {
    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $want.ToLowerInvariant()) {
        throw "Checksum verification FAILED for $Archive. Expected $want, got $actual. Aborting to keep your system safe."
    }
    Write-Host "  Checksum verified." -ForegroundColor Green
} elseif ($checksums) {
    Write-Host "  Warning: $Archive not found in checksums.txt — skipping verification." -ForegroundColor Yellow
}

# ── Install ────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$tmp = Join-Path $env:TEMP "layerflow-install"
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Expand-Archive -Path $zip -DestinationPath $tmp -Force

Copy-Item -Path (Join-Path $tmp "lf.exe") -Destination (Join-Path $Dest "lf.exe") -Force
Copy-Item -Path (Join-Path $tmp "lf.exe") -Destination (Join-Path $Dest "$Alias.exe") -Force
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

Write-Host ("  OK  Installed lf {0} to {1}" -f $Version, $Dest) -ForegroundColor Green

# ── Add to user PATH (persists; applies to NEW terminals) ──────────────────
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ([string]::IsNullOrEmpty($userPath)) { $userPath = "" }
$inPath = @($userPath -split ";") | Where-Object { $_ -and ($_.TrimEnd("\") -eq $Dest) }
if (-not $inPath) {
    $sep = if ($userPath.EndsWith(";")) { "" } else { ";" }
    [Environment]::SetEnvironmentVariable("Path", "$userPath$sep$Dest", "User")
    Write-Host "  OK  Added $Dest to your user PATH (new terminals only)." -ForegroundColor Green
} else {
    Write-Host "  OK  $Dest is already on your PATH." -ForegroundColor Green
}

# ── Try to refresh the current session's PATH too ──────────────────────────
$env:Path = "$Dest;$env:Path"

Write-Host ""
Write-Host "  $App installed. To use it:" -ForegroundColor Cyan
Write-Host "    1. Close this terminal and open a new one (so PATH reloads)." -ForegroundColor DarkGray
Write-Host "    2. Run:  lf" -ForegroundColor White
Write-Host "       (or 'layerflow' - both work)" -ForegroundColor DarkGray
Write-Host "    3. Run 'lf login' to connect your account." -ForegroundColor DarkGray
Write-Host "    4. Run 'lf' inside any project folder to start chatting." -ForegroundColor DarkGray
Write-Host ""
