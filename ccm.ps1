# ccm - keep several Claude accounts open side by side in the desktop app.
#
# Each account gets its own data folder under ~\.claude-accounts\<name> and a Start
# menu shortcut that opens the normal Claude desktop app on that folder. Every window
# still uses the same ~\.claude, so Code sessions from all accounts land in one
# history and the usage stats count all of them.
#
# This script manages the accounts (add, rename, remove, shortcuts, icons).
# ClaudeAccounts.exe, built from ClaudeAccounts.cs, opens the windows, gives each its
# own taskbar button and shows the usage window. Neither reads or copies a login;
# signing in happens inside each Claude window.

$ErrorActionPreference = 'Stop'

$Root = if ($env:CCM_HOME) { $env:CCM_HOME } else { Join-Path $HOME '.claude-accounts' }
$Shortcuts = Join-Path ([Environment]::GetFolderPath('Programs')) 'Claude accounts'
$App = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\claude-desktop.exe'
$MainData = Join-Path $env:APPDATA 'Claude'
$Exe = Join-Path $PSScriptRoot 'ClaudeAccounts.exe'
$Reserved = 'add', 'list', 'ls', 'remove', 'rm', 'rename', 'shortcuts', 'usage', 'build', 'install', 'doctor', 'isolate', 'claude', 'telemetry', 'help'
$Colors = '#2563EB', '#16A34A', '#7C3AED', '#DB2777', '#0D9488', '#475569', '#B45309', '#DC2626'

function Show-Help {
    @'
ccm - keep several Claude accounts open side by side in the desktop app

  ccm add <name>     create an account window and its Start menu shortcut
  ccm <name>         open that account's window (same as clicking "Claude <name>")
  ccm claude <name>  run Claude Code in this terminal with that account's own config
  ccm doctor         check that no two windows share an identity file
  ccm isolate <name> give an account its own Claude Code config, temp dir and device name
  ccm telemetry <name> off|on
                     block the app's essential telemetry (Sentry, Datadog RUM) for one window
  ccm usage          open the usage window (also lives in the tray)
  ccm list           the same numbers as text
  ccm rename <a> <b> give an account a different name (its window must be closed)
  ccm remove <name>  delete an account window and its saved sign-in (history is kept)
  ccm shortcuts      recreate the Start menu shortcuts and their icons
  ccm build          rebuild ClaudeAccounts.exe from ClaudeAccounts.cs
  ccm install        build, and make the ccm command available in every terminal
'@
}

function Get-AccountDir($name) {
    if (-not $name) { throw 'Missing account name. See: ccm help' }
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $Reserved -contains $name) {
        throw "'$name' is not a usable account name (letters, digits, . _ - only)."
    }
    return Join-Path $Root $name
}

function Get-ExistingAccountDir($name) {
    $data = Get-AccountDir $name
    if (-not (Test-Path -LiteralPath $data)) { throw "No account '$name'. Create it with: ccm add $name" }
    return $data
}

# The app keeps `lockfile` open for as long as a window on that folder is running.
function Test-Open($data) {
    $file = Join-Path $data 'lockfile'
    if (-not (Test-Path -LiteralPath $file)) { return $false }
    try { [IO.File]::Open($file, 'Open', 'ReadWrite', 'None').Dispose(); return $false }
    catch { return $true }
}

function Get-AppExe {
    if (-not $script:AppExe) {
        $script:AppExe = Join-Path (Get-AppxPackage -Name Claude -WarningAction SilentlyContinue).InstallLocation 'app\Claude.exe'
    }
    return $script:AppExe
}

# team1 -> T1, max20a -> M20a: short enough to read on a taskbar icon.
function Get-Label($name) {
    if ($name -match '^([A-Za-z])[A-Za-z]*(\d.*)$') { return $Matches[1].ToUpper() + $Matches[2] }
    return $name.Substring(0, [Math]::Min(3, $name.Length))
}

# Draw the Claude icon with a coloured tag and save it as an .ico. The icon is copied
# out of the installed app, so the file keeps working after app updates.
function New-TaggedIcon($label, $color, $path) {
    try {
        Add-Type -AssemblyName System.Drawing
        $bitmap = [Drawing.Icon]::ExtractIcon((Get-AppExe), 0, 256).ToBitmap()
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $graphics.SmoothingMode = 'AntiAlias'
        $graphics.TextRenderingHint = 'AntiAlias'

        $tag = [Drawing.Rectangle]::new(8, 118, 240, 130)
        $corner = 88
        $shape = [Drawing.Drawing2D.GraphicsPath]::new()
        $shape.AddArc($tag.X, $tag.Y, $corner, $corner, 180, 90)
        $shape.AddArc($tag.Right - $corner, $tag.Y, $corner, $corner, 270, 90)
        $shape.AddArc($tag.Right - $corner, $tag.Bottom - $corner, $corner, $corner, 0, 90)
        $shape.AddArc($tag.X, $tag.Bottom - $corner, $corner, $corner, 90, 90)
        $shape.CloseFigure()
        $graphics.FillPath([Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($color)), $shape)

        $size = 104
        do {
            $size -= 4
            $font = [Drawing.Font]::new('Segoe UI', $size, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
        } while ($graphics.MeasureString($label, $font).Width -gt $tag.Width -and $size -gt 24)
        $format = [Drawing.StringFormat]::new()
        $format.Alignment = 'Center'
        $format.LineAlignment = 'Center'
        $graphics.DrawString($label, $font, [Drawing.Brushes]::White, [Drawing.RectangleF]$tag, $format)
        $graphics.Dispose()

        # A .ico file holding one 256px PNG: 6-byte header, 16-byte entry, then the image.
        $png = [IO.MemoryStream]::new()
        $bitmap.Save($png, [Drawing.Imaging.ImageFormat]::Png)
        $header = [byte[]](0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 32, 0) +
            [BitConverter]::GetBytes([int]$png.Length) + [BitConverter]::GetBytes(22)
        [IO.File]::WriteAllBytes($path, $header + $png.ToArray())
        return $path
    }
    catch { return $null }
}

function New-AccountIcon($name, $data) {
    $order = @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object CreationTime, Name | ForEach-Object FullName)
    $color = $Colors[[Array]::IndexOf($order, $data) % $Colors.Count]
    New-TaggedIcon (Get-Label $name) $color (Join-Path $data 'ccm-icon.ico')
}

# Compile ClaudeAccounts.exe with the C# compiler that ships with Windows.
function Build-App {
    $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
    if (-not (Test-Path (Join-Path $framework 'csc.exe'))) { $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319' }
    $compiler = Join-Path $framework 'csc.exe'
    if (-not (Test-Path $compiler)) { throw 'The .NET Framework C# compiler (csc.exe) was not found.' }

    # A running copy of this program keeps the file locked.
    Get-Process ClaudeAccounts -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Exe } | Stop-Process -Force
    New-Item -ItemType Directory -Force $Root | Out-Null
    $arguments = @('/nologo', '/target:winexe', '/optimize+', "/out:$Exe")
    $arguments += 'WPF\PresentationFramework.dll', 'WPF\PresentationCore.dll', 'WPF\WindowsBase.dll', 'System.Xaml.dll' |
        ForEach-Object { "/reference:$(Join-Path $framework $_)" }
    $icon = New-TaggedIcon '%' '#334155' (Join-Path $Root 'usage.ico')
    if ($icon) { $arguments += "/win32icon:$icon" }
    $output = & $compiler @arguments (Join-Path $PSScriptRoot 'ClaudeAccounts.cs')
    if ($LASTEXITCODE -ne 0) { throw "Build failed:`n$($output -join "`n")" }
    "Built $Exe"
}

# Build on first use, and again whenever the source is newer than the program.
function Get-Exe {
    $source = Get-Item -LiteralPath (Join-Path $PSScriptRoot 'ClaudeAccounts.cs')
    $built = Get-Item -LiteralPath $Exe -ErrorAction SilentlyContinue
    if (-not $built -or $built.LastWriteTime -lt $source.LastWriteTime) { Build-App | Out-Null }
    return $Exe
}

# Lets a pinned shortcut and the running window share one taskbar button.
function Set-ShortcutAppId($path, $appId) {
    if (-not ('CcmShell' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CcmShell
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PropertyKey { public Guid FormatId; public uint PropertyId; }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    struct PropVariant { [FieldOffset(0)] public ushort Type; [FieldOffset(8)] public IntPtr Pointer; }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr bindContext, int flags, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

    // System.AppUserModel.ID, written as a string, on a store opened for writing.
    public static void SetAppId(string path, string appId)
    {
        var iid = typeof(IPropertyStore).GUID;
        IPropertyStore store;
        Marshal.ThrowExceptionForHR(SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 2, ref iid, out store));
        var key = new PropertyKey { FormatId = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), PropertyId = 5 };
        var value = new PropVariant { Type = 31, Pointer = Marshal.StringToCoTaskMemUni(appId) };
        try { Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref value)); }
        finally { Marshal.FreeCoTaskMem(value.Pointer); }
        Marshal.ThrowExceptionForHR(store.Commit());
        Marshal.ReleaseComObject(store);
    }
}
'@
    }
    try { [CcmShell]::SetAppId($path, $appId) } catch { }
}

function Set-Shortcut($path, $arguments, $description, $icon, $appId) {
    New-Item -ItemType Directory -Force $Shortcuts | Out-Null
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
    $link.TargetPath = Get-Exe
    $link.Arguments = $arguments
    $link.Description = $description
    if ($icon) { $link.IconLocation = "$icon,0" }
    $link.Save()
    Set-ShortcutAppId $path $appId
}

function Set-AccountShortcut($name, $data) {
    Set-Shortcut (Join-Path $Shortcuts "Claude $name.lnk") "open $name" "Claude desktop app, account '$name'" `
        (New-AccountIcon $name $data) "ClaudeAccounts.$name"
}

function Set-UsageShortcut {
    Remove-Item -LiteralPath (Join-Path $Shortcuts 'Claude accounts usage.lnk') -Force -ErrorAction SilentlyContinue
    Set-Shortcut (Join-Path $Shortcuts 'Claude accounts.lnk') '' 'Every Claude account and its last saved plan usage' `
        $null 'ClaudeAccounts.Usage'
}

function Update-Shortcuts {
    Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Set-AccountShortcut $_.Name $_.FullName }
    Set-UsageShortcut
    # Pinned taskbar icons are copies of the shortcuts; keep them on the current launcher too.
    $pinned = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    Get-ChildItem -LiteralPath $pinned -Filter 'Claude *.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.BaseName.Substring('Claude '.Length)
        $data = Join-Path $Root $name
        if ($name -notin $Reserved -and (Test-Path -LiteralPath $data)) {
            Set-Shortcut $_.FullName "open $name" "Claude desktop app, account '$name'" (Join-Path $data 'ccm-icon.ico') "ClaudeAccounts.$name"
        }
    }
    "Shortcuts are in the Start menu under 'Claude accounts'."
}

# State that used to be shared through %USERPROFILE% and %TEMP%: a Claude Code config
# directory (machine id, credentials, telemetry spool) and a temp directory. The
# launcher points CLAUDE_CONFIG_DIR/TEMP/TMP there, so nothing carries over between
# accounts. The device name the app shows for remote tools stops being the hostname.
function Initialize-Isolation($name, $data) {
    New-Item -ItemType Directory -Force (Join-Path $data 'claude-config'), (Join-Path $data 'temp') | Out-Null
    $file = Join-Path $data 'claude_desktop_config.json'
    $config = if (Test-Path -LiteralPath $file) {
        try { Get-Content -LiteralPath $file -Raw | ConvertFrom-Json } catch { [pscustomobject]@{} }
    } else { [pscustomobject]@{} }
    if (-not $config.PSObject.Properties['preferences']) {
        $config | Add-Member -NotePropertyName preferences -NotePropertyValue ([pscustomobject]@{})
    }
    if (-not $config.preferences.remoteToolsDeviceName -or $config.preferences.remoteToolsDeviceName -eq [Environment]::MachineName) {
        $config.preferences | Add-Member -NotePropertyName remoteToolsDeviceName `
            -NotePropertyValue ('device-' + [guid]::NewGuid().ToString('N').Substring(0, 10)) -Force
    }
    [IO.File]::WriteAllText($file, ($config | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
}

function New-Account($name) {
    $data = Get-AccountDir $name
    if (Test-Path -LiteralPath $data) { throw "Account '$name' already exists." }
    if (-not (Test-Path -LiteralPath $App)) { throw 'The Claude desktop app is not installed (claude-desktop.exe not found).' }
    New-Item -ItemType Directory -Force $data | Out-Null
    Initialize-Isolation $name $data
    Set-AccountShortcut $name $data
    Set-UsageShortcut
    "Created '$name'. Open it from the Start menu (`"Claude $name`") or with: ccm $name"
}

function Open-Account($name) {
    Get-ExistingAccountDir $name | Out-Null
    Start-Process (Get-Exe) -ArgumentList 'open', $name
    "Opening Claude for '$name'."
}

# Run the Claude Code CLI against this account's own config directory, so a terminal
# session cannot reuse another account's machine id or saved credentials.
# The app reads --desktop-managed-config from its own command line; the launcher turns
# that into this marker so blocking telemetry is one file per account.
function Set-Telemetry($name, $state) {
    $data = Get-ExistingAccountDir $name
    $marker = Join-Path $data 'no-telemetry'
    if ($state -eq 'off') {
        New-Item -ItemType File -Force $marker | Out-Null
        "Essential telemetry is blocked for '$name'. Restart its window to apply."
    } elseif ($state -eq 'on') {
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        "Essential telemetry is allowed again for '$name'. Restart its window to apply."
    } else {
        throw 'Use: ccm telemetry <name> off|on'
    }
}

function Open-Code($name, $cliArgs) {
    $data = Get-ExistingAccountDir $name
    $config = Join-Path $data 'claude-config'
    New-Item -ItemType Directory -Force $config | Out-Null
    $cli = $null
    foreach ($base in @($data, $MainData)) {
        $found = Get-ChildItem -LiteralPath (Join-Path $base 'claude-code') -Filter 'claude.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) { $cli = $found.FullName; break }
    }
    if (-not $cli) {
        $command = Get-Command claude.exe -ErrorAction SilentlyContinue
        if ($command) { $cli = $command.Source }
    }
    if (-not $cli) { throw 'Claude Code CLI not found. Open the Code tab in a Claude window once, then retry.' }
    $env:CLAUDE_CONFIG_DIR = $config
    & $cli @cliArgs
}

# Base64 UUID the app writes into each data folder; base64 of a UUID string.
function Get-DeviceId($data) {
    $file = Join-Path $data 'ant-did'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Get-Content -LiteralPath $file -Raw).Trim())) }
    catch { return 'unreadable' }
}

function Get-MachineIdFile($file) {
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { return (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json).machineID } catch { return 'unreadable' }
}

# Shows the identifiers each window keeps, so a shared install id, a missing per-account
# config dir or a hostname device name is visible before it can link two accounts.
function Show-Doctor {
    $targets = @([pscustomobject]@{ Name = '(normal app)'; Data = $MainData })
    Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $targets += [pscustomobject]@{ Name = $_.Name; Data = $_.FullName }
    }
    $rows = foreach ($target in $targets) {
        $configDir = Join-Path $target.Data 'claude-config'
        $machineFile = if ($target.Name -eq '(normal app)') { Join-Path $HOME '.claude.json' } else { Join-Path $configDir '.claude.json' }
        $deviceName = $null
        $configFile = Join-Path $target.Data 'claude_desktop_config.json'
        if (Test-Path -LiteralPath $configFile) {
            try { $deviceName = (Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json).preferences.remoteToolsDeviceName } catch { }
        }
        [pscustomobject]@{
            Account     = $target.Name
            'install id' = Get-DeviceId $target.Data
            'machine id' = Get-MachineIdFile $machineFile
            'device name' = $deviceName
            'code config' = Test-Path -LiteralPath $configDir
            temp        = Test-Path -LiteralPath (Join-Path $target.Data 'temp')
        }
    }
    $rows | Format-List

    foreach ($column in @('install id', 'machine id', 'device name')) {
        $values = @($rows | ForEach-Object { $_[$column] } | Where-Object { $_ })
        $shared = @($values | Group-Object | Where-Object { $_.Count -gt 1 })
        if ($shared.Count -gt 0) {
            Write-Host ("PROBLEM: shared {0}: {1}" -f $column, (($shared | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ')) -ForegroundColor Red
        }
    }
    $hostName = [Environment]::MachineName
    if (@($rows | Where-Object { $_.Account -ne '(normal app)' -and $_.'device name' -eq $hostName }).Count -gt 0) {
        Write-Host "Note: an account still advertises the hostname as its device name." -ForegroundColor Yellow
    }
    "Checked $($rows.Count) window(s). Every column above should differ per account."
}

# The desktop app records its own plan usage samples per window; show the latest one.
function Get-Row($label, $data) {
    $row = [ordered]@{
        Account  = $label
        Status   = if (Test-Open $data) { 'open' } else { 'closed' }
        '5h %'   = $null
        'Week %' = $null
        Saved    = 'never signed in'
    }
    try {
        $samples = (Get-Content -LiteralPath (Join-Path $data 'plan-usage-history.json') -Raw | ConvertFrom-Json).samples
        $last = $samples | Sort-Object t | Select-Object -Last 1
        $row['5h %'] = $last.u.fh
        $row['Week %'] = $last.u.sd
        $row.Saved = [DateTimeOffset]::FromUnixTimeMilliseconds($last.t).LocalDateTime.ToString('g')
    }
    catch { }
    [pscustomobject]$row
}

function Show-Accounts {
    $rows = @(Get-Row '(normal app)' $MainData)
    Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $rows += Get-Row $_.Name $_.FullName }
    $rows | Format-Table -AutoSize
}

# Claude Code keeps its OAuth token in Windows Credential Manager under a name derived
# from the config directory. That entry lives outside the profile, so remove it too.
function Remove-CodeCredentials($data) {
    $config = Join-Path $data 'claude-config'
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($config.Normalize([Text.NormalizationForm]::FormC))
        $hash = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    } finally { $sha.Dispose() }
    $target = 'Claude Code-credentials-' + $hash.Substring(0, 8)
    & cmd.exe /c ('cmdkey /delete:"' + $target + '"') 2>$null | Out-Null
}

function Remove-Account($name, $skipPrompt) {
    $data = Get-ExistingAccountDir $name
    if (Test-Open $data) { throw "The Claude window for '$name' is still running. Quit it first (tray icon > Quit)." }
    if (-not $skipPrompt) {
        $answer = Read-Host "Delete the '$name' window, its saved sign-in and local app data? Code history is kept. Type the name to confirm"
        if ($answer -ne $name) { return 'Cancelled.' }
    }
    Remove-Item -LiteralPath (Join-Path $Shortcuts "Claude $name.lnk") -Force -ErrorAction SilentlyContinue
    $pinned = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    Remove-Item -LiteralPath (Join-Path $pinned "Claude $name.lnk") -Force -ErrorAction SilentlyContinue
    Remove-CodeCredentials $data
    Remove-Item -LiteralPath $data -Recurse -Force
    "Removed '$name'."
}

# The sign-in lives inside the folder, so it moves with it.
function Rename-Account($old, $new) {
    $from = Get-ExistingAccountDir $old
    $to = Get-AccountDir $new
    if (Test-Path -LiteralPath $to) { throw "Account '$new' already exists." }
    if (Test-Open $from) { throw "The Claude window for '$old' is still running. Quit it first (tray icon > Quit)." }
    Remove-Item -LiteralPath (Join-Path $Shortcuts "Claude $old.lnk") -Force -ErrorAction SilentlyContinue
    Rename-Item -LiteralPath $from -NewName $new
    Set-AccountShortcut $new $to
    "Renamed '$old' to '$new'."
}

# Drop small launchers next to claude-desktop.exe, a folder Windows already has on PATH.
function Install-Ccm {
    Build-App
    Update-Shortcuts
    $bin = Split-Path $App
    $script = Join-Path $PSScriptRoot 'ccm.ps1'
    Set-Content -LiteralPath (Join-Path $bin 'ccm.ps1') -Value "& '$script' @args`r`nexit `$LASTEXITCODE"
    Set-Content -LiteralPath (Join-Path $bin 'ccm.cmd') -Value "@`"$(Join-Path $PSScriptRoot 'ccm.cmd')`" %*"
    "Installed. 'ccm' now works in any terminal (launchers are in $bin)."
}

$command = if ($args.Count) { [string]$args[0] } else { 'help' }
$rest = @($args | Select-Object -Skip 1)

try {
    switch ($command) {
        { $_ -in 'help', '-h', '--help' } { Show-Help }
        'add' { New-Account $rest[0] }
        { $_ -in 'list', 'ls' } { Show-Accounts }
        'doctor' { Show-Doctor }
        'isolate' { Initialize-Isolation $rest[0] (Get-ExistingAccountDir $rest[0]); "Isolation files are in place for '$($rest[0])'." }
        'telemetry' { Set-Telemetry $rest[0] $rest[1] }
        'claude' { Open-Code $rest[0] @($rest | Select-Object -Skip 1) }
        'usage' { Start-Process (Get-Exe) }
        { $_ -in 'remove', 'rm' } { Remove-Account $rest[0] ($rest -contains '--yes') }
        'rename' { Rename-Account $rest[0] $rest[1] }
        'shortcuts' { Update-Shortcuts }
        'build' { Build-App }
        'install' { Install-Ccm }
        default { Open-Account $command }
    }
    exit 0
}
catch {
    Write-Host "ccm: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
