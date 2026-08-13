<#
.SYNOPSIS
  Snaps the Factorio window and this terminal window side-by-side, so it's obvious
  by position alone which window currently has keyboard focus.

.PARAMETER Swap
  Put the terminal on the left and Factorio on the right (default: Factorio left, terminal right).

.PARAMETER GameWidthPercent
  Percent of the monitor's width given to the Factorio window (default 50).

.EXAMPLE
  .\split-screen.ps1
.EXAMPLE
  .\split-screen.ps1 -Swap -GameWidthPercent 65
#>
param(
    [switch]$Swap,
    [ValidateRange(10, 90)]
    [int]$GameWidthPercent = 50
)

Add-Type -AssemblyName System.Windows.Forms

Add-Type -Namespace SplitScreen -Name Win32 -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool MoveWindow(System.IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
'@

$SW_RESTORE = 9

$factorio = Get-Process factorio -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $factorio) {
    Write-Error "No running Factorio process with a visible window was found."
    exit 1
}
$factorioHwnd = $factorio.MainWindowHandle

# GetConsoleWindow() returns the classic conhost window. Windows Terminal hosts the
# real console via a hidden ConPTY conhost, so on Windows Terminal we instead grab
# the WindowsTerminal.exe window itself (only correct when a single WT window is open).
$wt = Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($wt) {
    $termHwnd = $wt.MainWindowHandle
} else {
    $termHwnd = [SplitScreen.Win32]::GetConsoleWindow()
}
if ($termHwnd -eq 0) {
    Write-Error "Could not find this terminal's window handle."
    exit 1
}

$screen = [System.Windows.Forms.Screen]::FromHandle($termHwnd)
$wa = $screen.WorkingArea
$gameWidth = [int]($wa.Width * ($GameWidthPercent / 100.0))
$termWidth = $wa.Width - $gameWidth

if ($Swap) {
    $termRect = @{ X = $wa.X;             Width = $termWidth }
    $gameRect = @{ X = $wa.X + $termWidth; Width = $gameWidth }
} else {
    $gameRect = @{ X = $wa.X;             Width = $gameWidth }
    $termRect = @{ X = $wa.X + $gameWidth; Width = $termWidth }
}

[SplitScreen.Win32]::ShowWindow($factorioHwnd, $SW_RESTORE) | Out-Null
[SplitScreen.Win32]::MoveWindow($factorioHwnd, $gameRect.X, $wa.Y, $gameRect.Width, $wa.Height, $true) | Out-Null

[SplitScreen.Win32]::ShowWindow($termHwnd, $SW_RESTORE) | Out-Null
[SplitScreen.Win32]::MoveWindow($termHwnd, $termRect.X, $wa.Y, $termRect.Width, $wa.Height, $true) | Out-Null

[SplitScreen.Win32]::SetForegroundWindow($termHwnd) | Out-Null

Write-Host "Factorio and terminal snapped side-by-side ($GameWidthPercent% / $(100 - $GameWidthPercent)%)."
