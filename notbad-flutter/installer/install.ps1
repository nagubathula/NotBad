# NotBad installer (per-user, no admin required).
#
# - Copies the release build to %LOCALAPPDATA%\NotBad
# - Adds "Open with NotBad" to the right-click menu of .md/.markdown/.txt/.text
# - Registers NotBad in the standard "Open with" list for those types
# - Creates a Start Menu shortcut
#
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File install.ps1
# Undo everything:    powershell -ExecutionPolicy Bypass -File uninstall.ps1

$ErrorActionPreference = 'Stop'

$sourceDir = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release'
$sourceExe = Join-Path $sourceDir 'notbad_flutter.exe'
if (-not (Test-Path $sourceExe)) {
    Write-Error "Release build not found at $sourceExe. Run 'flutter build windows' first."
}

$destDir = Join-Path $env:LOCALAPPDATA 'NotBad'
$destExe = Join-Path $destDir 'notbad_flutter.exe'

# --- Copy the app ---------------------------------------------------------
Write-Host "Installing to $destDir ..."
$running = Get-Process notbad_flutter -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $destExe }
foreach ($proc in $running) {
    if ($proc.MainWindowTitle -like '*Edited*') {
        Write-Error ('NotBad is running with unsaved changes ' +
            "(`"$($proc.MainWindowTitle)`"). Save and close it, then re-run.")
    }
    Write-Host 'Closing the running NotBad (no unsaved changes) ...'
    Stop-Process -Id $proc.Id -Force -Confirm:$false
}
if ($running) { Start-Sleep -Milliseconds 800 }
New-Item -ItemType Directory -Force $destDir | Out-Null
Copy-Item -Path (Join-Path $sourceDir '*') -Destination $destDir -Recurse -Force
# Keep the uninstaller next to the app so "Installed apps" can call it.
Copy-Item -Path (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination $destDir -Force

# --- Registry (per-user: HKCU\Software\Classes) ---------------------------
$classes = 'HKCU:\Software\Classes'
$command = "`"$destExe`" `"%1`""
$extensions = @('.md', '.markdown', '.txt', '.text')

# ProgID so NotBad shows up in the "Open with" chooser.
$progId = "$classes\NotBad.Document"
New-Item -Path "$progId\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $progId -Name '(Default)' -Value 'NotBad Document'
New-Item -Path "$progId\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$progId\DefaultIcon" -Name '(Default)' -Value "$destExe,0"
Set-ItemProperty -Path "$progId\shell\open\command" -Name '(Default)' -Value $command

foreach ($ext in $extensions) {
    # "Open with NotBad" directly in the right-click context menu.
    $verb = "$classes\SystemFileAssociations\$ext\shell\NotBad"
    New-Item -Path "$verb\command" -Force | Out-Null
    Set-ItemProperty -Path $verb -Name '(Default)' -Value 'Open with NotBad'
    Set-ItemProperty -Path $verb -Name 'Icon' -Value "$destExe,0"
    Set-ItemProperty -Path "$verb\command" -Name '(Default)' -Value $command

    # Entry in the standard "Open with" submenu.
    $openWith = "$classes\$ext\OpenWithProgids"
    New-Item -Path $openWith -Force | Out-Null
    New-ItemProperty -Path $openWith -Name 'NotBad.Document' `
        -PropertyType String -Value '' -Force | Out-Null
}

# --- "Installed apps" registration (Add/Remove Programs) ------------------
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NotBad'
New-Item -Path $uninstallKey -Force | Out-Null
$sizeKB = [int]((Get-ChildItem $destDir -Recurse | Measure-Object Length -Sum).Sum / 1KB)
Set-ItemProperty -Path $uninstallKey -Name 'DisplayName' -Value 'NotBad'
Set-ItemProperty -Path $uninstallKey -Name 'DisplayVersion' -Value '1.0.0'
Set-ItemProperty -Path $uninstallKey -Name 'Publisher' -Value 'Nagubathula Satya Sai'
Set-ItemProperty -Path $uninstallKey -Name 'DisplayIcon' -Value "$destExe,0"
Set-ItemProperty -Path $uninstallKey -Name 'InstallLocation' -Value $destDir
Set-ItemProperty -Path $uninstallKey -Name 'UninstallString' `
    -Value "powershell.exe -ExecutionPolicy Bypass -File `"$destDir\uninstall.ps1`""
Set-ItemProperty -Path $uninstallKey -Name 'NoModify' -Value 1 -Type DWord
Set-ItemProperty -Path $uninstallKey -Name 'NoRepair' -Value 1 -Type DWord
Set-ItemProperty -Path $uninstallKey -Name 'EstimatedSize' -Value $sizeKB -Type DWord

# --- Start Menu shortcut --------------------------------------------------
$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\NotBad.lnk'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($shortcut)
$link.TargetPath = $destExe
$link.WorkingDirectory = $destDir
$link.IconLocation = "$destExe,0"
$link.Description = 'NotBad — a quiet place to write'
$link.Save()

# Tell Explorer associations changed (menus refresh without a restart).
Add-Type -Namespace Win32 -Name Shell -MemberDefinition @'
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
'@
[Win32.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Host ''
Write-Host 'Done. NotBad is installed:'
Write-Host "  App:        $destExe"
Write-Host '  Start Menu: NotBad'
Write-Host '  Right-click any .md/.markdown/.txt file -> "Open with NotBad"'
