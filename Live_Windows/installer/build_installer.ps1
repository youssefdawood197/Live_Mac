<#
.SYNOPSIS
    Publishes Lively Wallpaper for Windows and compiles the Inno Setup installer.

.DESCRIPTION
    Executes 'dotnet publish' targeting win-x64, self-contained with trimmed dependencies,
    and invokes the Inno Setup compiler (ISCC.exe) to produce LivelyWallpaper-Windows-Setup-x64.exe.

.EXAMPLE
    .\build_installer.ps1
#>

[CmdletBinding()]
param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsRoot = Split-Path -Parent $ScriptDir
$ProjectFile = Join-Path $WindowsRoot "src\Live.App\Live.App.csproj"
$InnoScript = Join-Path $ScriptDir "LivelyWallpaper.iss"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Building Lively Wallpaper Windows Installer" -ForegroundColor Cyan
Write-Host " Configuration: $Configuration" -ForegroundColor Cyan
Write-Host " Target Runtime: $Runtime" -ForegroundColor Cyan
Write-Host " Project: $ProjectFile" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Publish Self-Contained WinUI 3 Application
Write-Host "`n==> Publishing Live.App with dotnet publish..." -ForegroundColor Green
dotnet publish $ProjectFile `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=false `
    -p:PublishReadyToRun=true

# 2. Locate Inno Setup Compiler (ISCC.exe)
$IsccPaths = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
)

$IsccExe = $IsccPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $IsccExe) {
    Write-Warning "Inno Setup compiler (ISCC.exe) was not found in standard program paths."
    Write-Warning "The published self-contained app is ready in: src\Live.App\bin\$Configuration\net8.0-windows10.0.19041.0\$Runtime\publish"
    Write-Warning "Install Inno Setup 6 from https://jrsoftware.org/isdl.php to compile the single-file setup installer."
    exit 0
}

# 3. Compile Setup Installer
Write-Host "`n==> Compiling setup executable with ISCC.exe..." -ForegroundColor Green
& $IsccExe $InnoScript

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " Successfully created LivelyWallpaper-Windows-Setup-x64.exe!" -ForegroundColor Green
Write-Host " Location: bin\installer\LivelyWallpaper-Windows-Setup-x64.exe" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
