#Requires -Version 5.1
<#
.SYNOPSIS
    Input Leap - Windows setup and build script
.DESCRIPTION
    Installs prerequisites (winget), sets up Qt, downloads Bonjour SDK, and builds Input Leap.
    Run from the repo root in a PowerShell terminal (Administrator recommended).
.NOTES
    Requirements:
      - Windows 10/11 (64-bit)
      - Visual Studio 2019 or 2022 with "Desktop development with C++" workload
      - winget (comes with Windows 10 1709+ / Windows 11)
    Optional env vars:
      $env:B_QT_MAJOR_VERSION  - Qt major version to use (default: 6)
      $env:B_QT_ROOT           - Path to Qt install root (default: auto-detect C:\Qt\...)
      $env:B_BUILD_TYPE        - Build type: Release or Debug (default: Release)
#>

$ErrorActionPreference = "Stop"

# ── Check for Administrator (needed for winget/vcpkg installs) ────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "NOTE: Not running as Administrator. Dependency installs (OpenSSL, Qt) may fail." -ForegroundColor Yellow
    Write-Host "      Re-run from an elevated PowerShell if any install step fails." -ForegroundColor Yellow
}
$qt_major_version = if ($env:B_QT_MAJOR_VERSION) { $env:B_QT_MAJOR_VERSION } else { "6" }
$build_type       = if ($env:B_BUILD_TYPE)        { $env:B_BUILD_TYPE }        else { "Release" }

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Err($msg)  { Write-Host "    ERROR: $msg" -ForegroundColor Red; exit 1 }

# ── 1. Check winget ──────────────────────────────────────────────────────────
Step "Checking winget"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Err "winget not found. Install it from https://aka.ms/getwinget or the Microsoft Store."
}
Ok "winget found"

# ── 2. Install CMake ─────────────────────────────────────────────────────────
Step "Installing CMake"
$cmakeInstalled = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmakeInstalled) {
    Ok "CMake already installed: $(cmake --version | Select-Object -First 1)"
} else {
    winget install --id Kitware.CMake --silent --accept-package-agreements --accept-source-agreements
    $env:PATH += ";C:\Program Files\CMake\bin"
    Ok "CMake installed"
}

# ── 3. Install OpenSSL ───────────────────────────────────────────────────────
Step "Installing OpenSSL"
$ssl_candidates = @(
    "C:\vcpkg\installed\x64-windows",
    "C:\Program Files\OpenSSL-Win64",
    "C:\Program Files\OpenSSL",
    "C:\OpenSSL-Win64",
    "C:\OpenSSL"
)
# Require the dev headers, not just the runtime DLLs
$openssl_root = $ssl_candidates | Where-Object { Test-Path "$_\include\openssl\ssl.h" } | Select-Object -First 1

if ($openssl_root) {
    Ok "OpenSSL dev already installed at $openssl_root"
} else {
    Write-Host "    Full OpenSSL dev headers not found. Installing via vcpkg..." -ForegroundColor Yellow

    $vcpkg_root = "C:\vcpkg"
    if (-not (Test-Path "$vcpkg_root\vcpkg.exe")) {
        Write-Host "    Cloning vcpkg..." -ForegroundColor Yellow
        git clone https://github.com/microsoft/vcpkg.git $vcpkg_root
        & "$vcpkg_root\bootstrap-vcpkg.bat" -disableMetrics
    }

    Write-Host "    Installing openssl:x64-windows via vcpkg (this takes a few minutes)..." -ForegroundColor Yellow
    & "$vcpkg_root\vcpkg.exe" install "openssl:x64-windows" --triplet x64-windows
    & "$vcpkg_root\vcpkg.exe" integrate install

    $openssl_root = "$vcpkg_root\installed\x64-windows"
    if (-not (Test-Path "$openssl_root\include\openssl\ssl.h")) {
        Err "vcpkg OpenSSL install failed. Check output above."
    }
    Ok "OpenSSL installed at $openssl_root"
}

# ── 4. Install Git (needed for submodules) ───────────────────────────────────
Step "Checking Git"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements
    $env:PATH += ";C:\Program Files\Git\bin"
    Ok "Git installed"
} else {
    Ok "Git already installed"
}

# ── 5. Install Qt via aqt if not present ─────────────────────────────────────
Step "Checking Qt $qt_major_version"
$qt_root = if ($env:B_QT_ROOT) {
    $env:B_QT_ROOT
} else {
    (Resolve-Path "C:\Qt\$qt_major_version*\*" -ErrorAction SilentlyContinue | Select-Object -First 1).Path
}

if (-not $qt_root) {
    Write-Host "    Qt not found. Installing via aqt..." -ForegroundColor Yellow

    # Install Python and aqt
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        winget install --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements
        $env:PATH += ";$env:LOCALAPPDATA\Programs\Python\Python311;$env:LOCALAPPDATA\Programs\Python\Python311\Scripts"
    }
    pip install aqtinstall --quiet

    if ($qt_major_version -eq "6") {
        aqt install-qt windows desktop 6.6.0 win64_msvc2019_64 -O C:\Qt
    } else {
        aqt install-qt windows desktop 5.15.2 win64_msvc2019_64 -O C:\Qt
    }

    $qt_root = (Resolve-Path "C:\Qt\$qt_major_version*\*" 2>$null | Select-Object -First 1).Path
    if (-not $qt_root) { Err "Qt installation failed. Set `$env:B_QT_ROOT manually." }
    Ok "Qt installed at $qt_root"
} else {
    Ok "Qt found at $qt_root"
}

# ── 6. Download Bonjour SDK ──────────────────────────────────────────────────
Step "Downloading Bonjour SDK"
$bonjour_path = Join-Path (Get-Location) "deps\BonjourSDKLike"
New-Item -Force -ItemType Directory -Path ".\deps" | Out-Null

if (-not (Test-Path "$bonjour_path\Lib\x64\dnssd.lib")) {
    Invoke-WebRequest `
        'https://github.com/nelsonjchen/mDNSResponder/releases/download/v2019.05.08.1/x64_RelWithDebInfo.zip' `
        -OutFile 'deps\BonjourSDKLike.zip'
    if (Test-Path $bonjour_path) { Remove-Item $bonjour_path -Recurse }
    Expand-Archive .\deps\BonjourSDKLike.zip -DestinationPath $bonjour_path
    Remove-Item deps\BonjourSDKLike.zip
    Ok "Bonjour SDK downloaded"
} else {
    Ok "Bonjour SDK already present"
}

# ── 7. Init submodules ───────────────────────────────────────────────────────
Step "Initializing git submodules"
git submodule update --init --recursive
Ok "Submodules ready"

# ── 8. Find Visual Studio ────────────────────────────────────────────────────
Step "Detecting Visual Studio"
$vs_locations = @(
    @{ version = "Visual Studio 17 2022"; path = "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat" },
    @{ version = "Visual Studio 17 2022"; path = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" },
    @{ version = "Visual Studio 16 2019"; path = "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\Common7\Tools\VsDevCmd.bat" },
    @{ version = "Visual Studio 16 2019"; path = "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7\Tools\VsDevCmd.bat" }
)

$vs_version = ""
foreach ($loc in $vs_locations) {
    if (Test-Path $loc.path) { $vs_version = $loc.version; break }
}
if ($vs_version -eq "") { Err "Visual Studio 2019 or 2022 not found. Install it with the 'Desktop development with C++' workload." }
Ok "Using $vs_version"

# ── 9. CMake configure & build ───────────────────────────────────────────────
Step "Configuring CMake ($build_type)"
if (Test-Path build) { Remove-Item build -Recurse }
New-Item -Force -ItemType Directory -Path .\build | Out-Null
Push-Location build

try {
    $env:BONJOUR_SDK_HOME = $bonjour_path
    cmake .. -G $vs_version -A x64 `
        "-DCMAKE_BUILD_TYPE=$build_type" `
        "-DCMAKE_PREFIX_PATH=$qt_root" `
        "-DQT_DEFAULT_MAJOR_VERSION=$qt_major_version" `
        "-DDNSSD_LIB=$bonjour_path\Lib\x64\dnssd.lib" `
        "-DOPENSSL_ROOT_DIR=$openssl_root" `
        -DCMAKE_INSTALL_PREFIX=input-leap-install

    if ($LASTEXITCODE -ne 0) { Err "CMake configure failed (exit $LASTEXITCODE)." }

    Step "Building Input Leap"
    cmake --build . --parallel --config $build_type --target install
    if ($LASTEXITCODE -ne 0) { Err "Build failed (exit $LASTEXITCODE)." }

    # Copy OpenSSL runtime DLLs if they came from vcpkg (not bundled by CMake install)
    $vcpkg_bin = "C:\vcpkg\installed\x64-windows\bin"
    if (Test-Path $vcpkg_bin) {
        foreach ($dll in @("libcrypto-3-x64.dll", "libssl-3-x64.dll")) {
            $src = "$vcpkg_bin\$dll"
            if ((Test-Path $src) -and -not (Test-Path "input-leap-install\$dll")) {
                Copy-Item $src "input-leap-install\$dll"
                Ok "Copied $dll"
            }
        }
    }

    Ok "Build complete -> build\input-leap-install\"
} finally {
    Pop-Location
}

Write-Host "`n[DONE] Run build\input-leap-install\input-leap.exe to start the GUI." -ForegroundColor Green
