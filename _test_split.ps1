$exe = 'D:\Soft\claude-multi-account\ClaudeAccounts.exe'
Get-Process ClaudeAccounts -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2

function Show($label) {
    $ps = @(Get-Process ClaudeAccounts -ErrorAction SilentlyContinue)
    foreach ($p in $ps) {
        $wpf = @($p.Modules | Where-Object { $_.ModuleName -like 'PresentationFramework*' }).Count
        "{0}: pid={1} title='{2}' ws={3:N1}MB priv={4:N1}MB wpf_modules={5}" -f $label,$p.Id,$p.MainWindowTitle,($p.WorkingSet64/1MB),($p.PrivateMemorySize64/1MB),$wpf
    }
}

Start-Process $exe 'usage'
Start-Sleep 5
Show 'usage-open'
$u = Get-Process ClaudeAccounts | Where-Object MainWindowTitle
$u.CloseMainWindow() | Out-Null
Start-Sleep 4
"usage after close: {0}" -f [bool](Get-Process ClaudeAccounts -ErrorAction SilentlyContinue)

Start-Process $exe 'tray'
Start-Sleep 4
Show 'tray-only'

Start-Process $exe 'usage'
Start-Sleep 5
Show 'tray+usage'
try { $e = [System.Threading.EventWaitHandle]::OpenExisting('ClaudeAccounts.UsageQuit'); $e.Set(); $e.Dispose() } catch { "event error: $_" }
Start-Sleep 4
Show 'after quit event'
