# NotBad uninstaller — removes everything install.ps1 created.
# Run:  powershell -ExecutionPolicy Bypass -File uninstall.ps1
# (Also invoked by Windows Settings > Installed apps > NotBad > Uninstall.)

$ErrorActionPreference = 'SilentlyContinue'

$destDir = Join-Path $env:LOCALAPPDATA 'NotBad'
$classes = 'HKCU:\Software\Classes'
$extensions = @('.md', '.markdown', '.txt', '.text')

# Leave the install folder before deleting it (it may be our working dir).
Set-Location $env:TEMP

Get-Process notbad_flutter | Where-Object {
    $_.Path -like "$destDir*"
} | Stop-Process -Confirm:$false

foreach ($ext in $extensions) {
    Remove-Item -Path "$classes\SystemFileAssociations\$ext\shell\NotBad" -Recurse -Force
    Remove-ItemProperty -Path "$classes\$ext\OpenWithProgids" -Name 'NotBad.Document' -Force
}
Remove-Item -Path "$classes\NotBad.Document" -Recurse -Force
Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NotBad' -Recurse -Force
Remove-Item -Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\NotBad.lnk') -Force

# Transient locks (antivirus scans, Explorer) can hold files briefly — retry.
foreach ($attempt in 1..5) {
    Remove-Item -Path $destDir -Recurse -Force
    if (-not (Test-Path $destDir)) { break }
    Start-Sleep -Milliseconds 600
}

Add-Type -Namespace Win32 -Name Shell -MemberDefinition @'
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
'@
[Win32.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Host 'NotBad has been uninstalled.'
