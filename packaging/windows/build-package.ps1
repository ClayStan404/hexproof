# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$CMakeSource = Get-Content (Join-Path $RepoRoot "apps/client-qt/CMakeLists.txt")
$SourceVersionLine = $CMakeSource |
    Select-String -Pattern '^\s*set\(HEXPROOF_VERSION\s+"([0-9]+\.[0-9]+\.[0-9]+)"\s*\)\s*$'
if (-not $SourceVersionLine) {
    throw "Could not read the default version from apps/client-qt/CMakeLists.txt"
}
$SourceVersion = $SourceVersionLine.Matches[0].Groups[1].Value
$Version = if ($env:HEXPROOF_VERSION) { $env:HEXPROOF_VERSION } else { $SourceVersion }
$Arch = if ($env:HEXPROOF_ARCH) {
    $env:HEXPROOF_ARCH
} elseif ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    "arm64"
} else {
    "x64"
}
$BuildDir = Join-Path $RepoRoot "build/package-windows"
$OutputDir = if ($env:HEXPROOF_OUTPUT_DIR) {
    $env:HEXPROOF_OUTPUT_DIR
} else {
    Join-Path $RepoRoot "build/packages"
}
$StageDir = Join-Path $BuildDir ("stage-" + [Guid]::NewGuid().ToString("N"))
$PackageRoot = Join-Path $StageDir "Hexproof-$Version-windows-$Arch"
$Archive = Join-Path $OutputDir "Hexproof-$Version-windows-$Arch.zip"

try {
    $ConfigureArgs = @(
        "-S", (Join-Path $RepoRoot "apps/client-qt"),
        "-B", $BuildDir,
        "-DCMAKE_BUILD_TYPE=Release",
        "-DHEXPROOF_VERSION_OVERRIDE=$Version"
    )
    if ($env:HEXPROOF_CMAKE_GENERATOR) {
        $ConfigureArgs += @("-G", $env:HEXPROOF_CMAKE_GENERATOR)
    }
    if ($env:HEXPROOF_CMAKE_GENERATOR_PLATFORM) {
        $ConfigureArgs += @("-A", $env:HEXPROOF_CMAKE_GENERATOR_PLATFORM)
    }
    if ($env:HEXPROOF_CMAKE_TOOLCHAIN_FILE) {
        $ConfigureArgs += "-DCMAKE_TOOLCHAIN_FILE=$env:HEXPROOF_CMAKE_TOOLCHAIN_FILE"
    }
    if ($env:HEXPROOF_VCPKG_TARGET_TRIPLET) {
        $ConfigureArgs += "-DVCPKG_TARGET_TRIPLET=$env:HEXPROOF_VCPKG_TARGET_TRIPLET"
    }
    if ($env:HEXPROOF_SERVER_DIRECTORY_FILE) {
        $ConfigureArgs += "-DHEXPROOF_SERVER_DIRECTORY_FILE=$env:HEXPROOF_SERVER_DIRECTORY_FILE"
    }
    cmake @ConfigureArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configure failed with exit code $LASTEXITCODE."
    }
    cmake --build $BuildDir --config Release --target hexproof
    if ($LASTEXITCODE -ne 0) {
        throw "Client build failed with exit code $LASTEXITCODE."
    }
    New-Item -ItemType Directory -Force -Path $PackageRoot, $OutputDir | Out-Null
    cmake --install $BuildDir --config Release --prefix $PackageRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Client install failed with exit code $LASTEXITCODE."
    }
    cmake "-DHEXPROOF_PACKAGE_ROOT=$PackageRoot" `
        -P (Join-Path $RepoRoot "packaging/prune-client-runtime.cmake")
    if ($LASTEXITCODE -ne 0) {
        throw "Runtime pruning failed with exit code $LASTEXITCODE."
    }
    if (Test-Path $Archive) {
        Remove-Item -Force $Archive
    }
    Compress-Archive -Path $PackageRoot -DestinationPath $Archive
    Write-Output $Archive
} finally {
    if (Test-Path $StageDir) {
        Remove-Item -Recurse -Force $StageDir
    }
}
