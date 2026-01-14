param(
    [switch]$ForceServerUpdate
)

Write-Host "[0/3] Checking for script updates..." -ForegroundColor Cyan

if ((Get-Command "git" -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $PSScriptRoot ".git"))) {
    try {
        $null = git fetch
        $LocalHash  = (git rev-parse HEAD).Trim()
        $RemoteHash = (git rev-parse "@{u}").Trim()

        if ($LocalHash -ne $RemoteHash) {
            Write-Host "      Update found! Pulling changes..." -ForegroundColor Yellow
            $PullResult = git pull
            Write-Host "      Restarting script with new version..." -ForegroundColor Magenta
            
            $MyArgs = @()
            if ($ForceServerUpdate) { $MyArgs += "-ForceServerUpdate" }
            
            $PwshExe = (Get-Process -Id $PID).Path
            
            Start-Process -FilePath $PwshExe -ArgumentList (("-File", "`"$PSCommandPath`"") + $MyArgs) -NoNewWindow -Wait
            exit
        } else {
            Write-Host "      Scripts are up to date." -ForegroundColor Gray
        }
    } catch {
        Write-Warning "      Git update check failed. Continuing..."
    }
} else {
    Write-Host "      Git not found or not a repo. Skipping." -ForegroundColor DarkGray
}

$DownloaderUrl = "https://downloader.hytale.com/hytale-downloader.zip"
$CurrentDir    = $PSScriptRoot
$ToolDir       = Join-Path $CurrentDir "hytale_tool"
$ServerDir     = Join-Path $CurrentDir "hytale_server"
$MetaFile      = Join-Path $ToolDir "version.meta"

$IsWindows = $true
if ($PSVersionTable.PSEdition -eq "Core" -and $PSVersionTable.Platform -eq "Unix") {
    $IsWindows = $false
}

Write-Host "[1/3] Checking Downloader Tool..." -ForegroundColor Cyan

if (-not (Test-Path $ToolDir)) { New-Item -Path $ToolDir -ItemType Directory | Out-Null }

$ToolWasUpdated = $false

try {
    $HeadRequest = Invoke-WebRequest -Uri $DownloaderUrl -Method Head -UseBasicParsing -ErrorAction Stop
    $RemoteLastModified = $HeadRequest.Headers["Last-Modified"]
    
    $LocalLastModified = ""
    if (Test-Path $MetaFile) { $LocalLastModified = Get-Content $MetaFile }

    if ($RemoteLastModified -ne $LocalLastModified) {
        Write-Host "      New tool version found. Downloading..." -ForegroundColor Yellow
        $ZipPath = Join-Path $ToolDir "downloader.zip"
        Invoke-WebRequest -Uri $DownloaderUrl -OutFile $ZipPath -UseBasicParsing
        Expand-Archive -Path $ZipPath -DestinationPath $ToolDir -Force
        Set-Content -Path $MetaFile -Value $RemoteLastModified
        Remove-Item $ZipPath -Force
        $ToolWasUpdated = $true
        Write-Host "      Tool updated." -ForegroundColor Green
    } else {
        Write-Host "      Tool is up to date." -ForegroundColor Gray
    }
} catch {
    Write-Host "      Error checking tool: $_" -ForegroundColor Red
}

Write-Host "[2/3] Checking Game Server files..." -ForegroundColor Cyan

$JarCheckPath = Join-Path (Join-Path $ServerDir "Server") "HytaleServer.jar"
$ServerExists = Test-Path $JarCheckPath

$ShouldUpdate = $ForceServerUpdate -or $ToolWasUpdated -or (-not $ServerExists)

if ($ShouldUpdate) {
    if ($ForceServerUpdate) { Write-Host "      Forced update requested." -ForegroundColor Yellow }
    elseif ($ToolWasUpdated) { Write-Host "      Tool updated, syncing server..." -ForegroundColor Yellow }
    else { Write-Host "      First run/Missing files detected." -ForegroundColor Yellow }

    if ($IsWindows) {
        $ToolExe = Get-ChildItem -Path $ToolDir -Filter "*.exe" -Recurse | Select-Object -First 1
    } else {
        $ToolExe = Get-ChildItem -Path $ToolDir -File | Where-Object { $_.Extension -eq "" } | Select-Object -First 1
        if ($ToolExe) { Start-Process "chmod" -ArgumentList "+x", $ToolExe.FullName -NoNewWindow -Wait }
    }

    if ($ToolExe) {
        Write-Host "      Downloading server files..." -ForegroundColor Gray
        & $ToolExe.FullName -download-path $ServerDir

        $ZipExternal = "$ServerDir.zip"              
        $ZipInternal = Join-Path $ServerDir "*.zip"  
        
        $ZipToExtract = $null
        
        if (Test-Path $ZipExternal) {
            $ZipToExtract = $ZipExternal
        } else {
            $ZipToExtract = Get-ChildItem -Path $ServerDir -Filter "*.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
        }

        if ($ZipToExtract) {
            Write-Host "      Unpacking content ($ZipToExtract)..." -ForegroundColor Yellow
            
            if (-not (Test-Path $ServerDir)) { New-Item -Path $ServerDir -ItemType Directory | Out-Null }
            
            Expand-Archive -Path $ZipToExtract -DestinationPath $ServerDir -Force
        } else {
            Write-Warning "      No zip file found after download."
        }
    } else {
        Write-Error "      Could not find downloader executable."
    }
} else {
    Write-Host "      Skipping update (Run update.bat to force)." -ForegroundColor Green
}

Write-Host "[3/3] Launching Hytale Server..." -ForegroundColor Cyan

if (Test-Path $ServerDir) {
    $JarPath = Join-Path (Join-Path $ServerDir "Server") "HytaleServer.jar"
    
    if (Test-Path $JarPath) {
        Push-Location $ServerDir
        $JavaArgs = "-jar", ".\Server\HytaleServer.jar", "--assets", "Assets.zip"
        Write-Host "      Exec: java $JavaArgs" -ForegroundColor Gray
        & java $JavaArgs
        Pop-Location
    } else {
        Write-Error "HytaleServer.jar not found at $JarPath.`n      Try running update.bat"
    }
} else {
    Write-Error "Server directory missing. Try running update.bat"
}