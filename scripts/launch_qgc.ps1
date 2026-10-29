# QGroundControl launcher helper for Drone-SLAM
$ErrorActionPreference = 'Stop'

function Get-QgcProcess {
    $found = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '(?i)qgroundcontrol|qgc'
    })
    if ($found.Count -gt 0) { return $found[0] }

    $cim = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '(?i)qgroundcontrol|qgc'
    })
    if ($cim.Count -gt 0) { return $cim[0] }
    return $null
}

function Wait-QgcProcess([int]$Seconds = 25) {
    for ($i = 0; $i -lt $Seconds; $i++) {
        $p = Get-QgcProcess
        if ($null -ne $p) { return $p }
        Start-Sleep -Seconds 1
    }
    return $null
}

Write-Host "Checking whether QGroundControl is already running..."
$running = Get-QgcProcess
if ($null -ne $running) {
    Write-Host "[OK] QGroundControl process found: $($running.ProcessName)"
    exit 0
}

# Search shortcut names broadly across common Start Menu and Desktop locations.
$shortcutRoots = @(
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    ([Environment]::GetFolderPath('Desktop')),
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:USERPROFILE 'OneDrive\Desktop'),
    (Join-Path $env:OneDrive 'Desktop')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$shortcuts = @()
foreach ($root in $shortcutRoots) {
    try {
        $shortcuts += Get-ChildItem -Path $root -Filter '*QGroundControl*.lnk' -File -Recurse -ErrorAction SilentlyContinue
        $shortcuts += Get-ChildItem -Path $root -Filter '*QGC*.lnk' -File -Recurse -ErrorAction SilentlyContinue
    } catch {}
}
foreach ($shortcut in ($shortcuts | Select-Object -Unique)) {
    Write-Host "Trying shortcut: $($shortcut.FullName)"
    try { Start-Process -FilePath $shortcut.FullName -ErrorAction Stop } catch { continue }
    $running = Wait-QgcProcess 20
    if ($null -ne $running) {
        Write-Host "[OK] QGroundControl launched from shortcut."
        exit 0
    }
}

# Try Start Menu's registered application entries.
try {
    $app = Get-StartApps | Where-Object { $_.Name -match '(?i)QGroundControl|QGC' } | Select-Object -First 1
    if ($null -ne $app) {
        Write-Host "Trying Start Menu app entry: $($app.Name)"
        Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$($app.AppID)"
        $running = Wait-QgcProcess 20
        if ($null -ne $running) {
            Write-Host "[OK] QGroundControl launched from the Start Menu app entry."
            exit 0
        }
    }
} catch {}

# Common install paths.
$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$candidates = @(
    (Join-Path $env:ProgramFiles 'QGroundControl\QGroundControl.exe'),
    (Join-Path $env:ProgramFiles 'QGroundControl.exe'),
    (Join-Path $pf86 'QGroundControl\QGroundControl.exe'),
    (Join-Path $pf86 'QGroundControl.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\QGroundControl\QGroundControl.exe'),
    (Join-Path $env:LOCALAPPDATA 'QGroundControl\QGroundControl.exe'),
    (Join-Path $env:USERPROFILE 'QGroundControl\QGroundControl.exe'),
    'C:\QGroundControl\QGroundControl.exe'
)
$candidates = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

# Use uninstall registry entries to discover custom install locations.
$uninstallRoots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($regRoot in $uninstallRoots) {
    try {
        $entries = Get-ItemProperty $regRoot -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '(?i)QGroundControl|QGC' }
        foreach ($entry in $entries) {
            if ($entry.InstallLocation) {
                $candidate = Join-Path $entry.InstallLocation 'QGroundControl.exe'
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidates += $candidate }
            }
            if ($entry.DisplayIcon) {
                $iconPath = ($entry.DisplayIcon -replace '^"([^"]+)".*$', '$1' -replace ',\d+$', '')
                if (Test-Path -LiteralPath $iconPath -PathType Leaf) { $candidates += $iconPath }
            }
        }
    } catch {}
}

# Search the most likely custom/portable install folders, not the whole C: drive.
$searchRoots = @(
    (Join-Path $env:ProgramFiles 'QGroundControl'),
    (Join-Path $pf86 'QGroundControl'),
    (Join-Path $env:LOCALAPPDATA 'Programs'),
    (Join-Path $env:USERPROFILE 'Downloads'),
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:USERPROFILE 'OneDrive\Desktop')
) | Where-Object { $_ -and (Test-Path $_ -PathType Container) } | Select-Object -Unique
foreach ($root in $searchRoots) {
    if ($candidates.Count -gt 0) { break }
    try {
        $found = Get-ChildItem -Path $root -Filter 'QGroundControl.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $found) { $candidates += $found.FullName; break }
    } catch {}
}

$exe = $candidates | Select-Object -First 1
if ($exe) {
    Write-Host "Launching executable: $exe"
    try { Start-Process -FilePath $exe -ErrorAction Stop } catch {
        Write-Error "Could not launch QGroundControl at '$exe': $_"
        exit 1
    }
} else {
    Write-Host "QGroundControl wasn't found automatically. Select QGroundControl.exe in the file picker."
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Locate QGroundControl.exe'
        $dialog.Filter = 'QGroundControl executable (QGroundControl.exe)|QGroundControl.exe|Executable files (*.exe)|*.exe'
        $dialog.CheckFileExists = $true
        $dialog.Multiselect = $false
        $dialog.InitialDirectory = [Environment]::GetFolderPath('UserProfile')
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Error 'QGroundControl was not selected. Cancelled before starting PX4.'
            exit 1
        }
        if ([IO.Path]::GetFileName($dialog.FileName) -notmatch '(?i)qgroundcontrol|qgc') {
            Write-Error 'The selected file name does not look like QGroundControl.exe. Cancelled before starting PX4.'
            exit 1
        }
        Start-Process -FilePath $dialog.FileName -ErrorAction Stop
    } catch {
        Write-Error "Could not launch QGroundControl: $_"
        exit 1
    }
}

$running = Wait-QgcProcess 25
if ($null -eq $running) {
    Write-Error 'QGroundControl was launched (or selected) but its process was not detected within 25 seconds. Do not continue; open it manually and rerun the launcher.'
    exit 1
}
Write-Host "[OK] QGroundControl process detected: $($running.ProcessName)"
exit 0
