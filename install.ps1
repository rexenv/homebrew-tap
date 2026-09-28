# rexenv installer for Windows.
#
#   irm https://rexenv.rex.bd/install.ps1 | iex
#
# Installs the latest published rexenv release from this repository's GitHub Releases: the
# per-user installer (rexenv_<version>_x64-setup.exe), run silently. It needs no
# administrator rights and raises no UAC prompt, because rexenv installs into your own
# profile. The download is checked against the release's own .sha256 before it runs. That
# proves the file arrived intact; that it is rexenv's rests on HTTPS to github.com, as it
# does for a browser download of the same file.
#
# A rexenv that is already installed is never touched. rexenv updates itself (Settings ->
# About -> Check now), so the script says where the installed copy is and stops.
#
# Why no SmartScreen dialog: SmartScreen checks a file carrying the Mark of the Web, and a
# BROWSER writes that mark on a download. Invoke-WebRequest writes none (measured on
# Windows 10 22H2, PowerShell 5.1). rexenv is not code-signed: running this script is your
# decision to trust this source. Where Smart App Control is on, it still blocks unsigned
# apps; nothing here changes that, and nothing here touches Microsoft Defender.
#
#   $env:REXENV_NO_LAUNCH = '1'   install, but do not start rexenv
#
# Everything runs inside one script block and nothing calls `exit`: `iex` runs in YOUR
# PowerShell session, where `exit` would close the window and a changed preference variable
# would outlive the script. The block is invoked on the LAST line, so a download cut short
# runs nothing. ASCII only: Windows PowerShell 5.1 decodes a response without a charset as
# Latin-1.
#
# These promises are row #738 of docs/CLAIM-LEDGER.md in the app repo; the design and its
# measurements are docs/archive/PLAN-install-scripts.md there.

& {
    $ErrorActionPreference = 'Stop'
    # Windows PowerShell 5.1 redraws its progress bar per chunk, which slows a download
    # several times over.
    $ProgressPreference = 'SilentlyContinue'

    $Releases = 'https://github.com/rexenv/homebrew-tap/releases'
    $UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\rexenv'
    $UserAgent = 'rexenv-install'

    function Say([string]$Message) { Write-Host "rexenv: $Message" }

    function Get-InstalledRexenv {
        foreach ($hive in 'HKCU:', 'HKLM:') {
            $entry = Get-ItemProperty -Path "$hive\$UninstallKey" -ErrorAction SilentlyContinue
            if ($entry) { return $entry }
        }
        return $null
    }

    # The OS's own architecture, for the Windows-on-Arm note only. PROCESSOR_ARCHITEW6432 is set
    # only inside a 32-bit process on 64-bit Windows and names the OS's architecture; otherwise
    # PROCESSOR_ARCHITECTURE does.
    #
    # NOT [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture. In an INTERACTIVE
    # Windows PowerShell 5.1 that type name resolves to PSReadLine 2.0.0's own internal class,
    # which has no such property, so it reads as $null - and the first release of this script
    # refused every Windows desktop with "this machine is ." (measured 29 Sep 2026; CI and SSH
    # runs are non-interactive, load no PSReadLine, and passed). The lint job greps for the name.
    function Get-OsArchitecture {
        if ($env:PROCESSOR_ARCHITEW6432) { return [string]$env:PROCESSOR_ARCHITEW6432 }
        return [string]$env:PROCESSOR_ARCHITECTURE
    }

    # releases/latest answers 302 to .../releases/tag/v<X.Y.Z>. Reading that Location costs
    # one request and no API call (so no rate limit), and "latest" never names a draft or a
    # prerelease: the same release the website's /download resolves.
    function Get-LatestVersion {
        $request = [System.Net.HttpWebRequest]::Create("$Releases/latest")
        $request.AllowAutoRedirect = $false
        $request.Method = 'HEAD'
        $request.UserAgent = $UserAgent
        $response = $request.GetResponse()
        try { $location = [string]$response.Headers['Location'] } finally { $response.Close() }
        if ($location -notmatch '/releases/tag/v(\d+\.\d+\.\d+)$') {
            throw "could not read the latest release from '$location'."
        }
        return $Matches[1]
    }

    function Save-File([string]$Url, [string]$Path) {
        Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -UserAgent $UserAgent
    }

    function Install-Rexenv {
        if ([Environment]::OSVersion.Version.Major -lt 10) {
            throw 'rexenv needs Windows 10 or 11.'
        }
        # The one refusal is a 32-bit Windows. Anything 64-bit gets the x64 build: native on x64,
        # emulated on Arm. An architecture the environment does not name is not a reason to stop.
        if (-not [Environment]::Is64BitOperatingSystem) {
            throw 'rexenv is built for 64-bit Windows (x64); this Windows is 32-bit.'
        }
        if ((Get-OsArchitecture) -match '^ARM64$') {
            Say 'note: Windows on Arm is not supported. The x64 build runs under emulation, but the PHP and PostgreSQL builds rexenv downloads are x64 only.'
        }

        $existing = Get-InstalledRexenv
        if ($existing) {
            Say "rexenv $($existing.DisplayVersion) is already installed: $(([string]$existing.InstallLocation).Trim('"'))"
            Say 'it updates itself: Settings -> About -> Check now. Nothing was changed.'
            return
        }

        # Windows PowerShell 5.1 on an older .NET may not offer TLS 1.2 by default, and
        # github.com accepts nothing older.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $version = Get-LatestVersion
        Say "latest release: $version"
        $asset = "rexenv_${version}_x64-setup.exe"
        $url = "$Releases/download/v$version/$asset"
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('rexenv-install-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            $installer = Join-Path $tmp $asset
            Say "downloading $asset"
            Save-File $url $installer
            Save-File "$url.sha256" "$installer.sha256"
            $want = ((Get-Content -LiteralPath "$installer.sha256" -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
            if ($want -notmatch '^[0-9a-f]{64}$') {
                throw "$asset.sha256 does not hold a SHA-256. Nothing was installed."
            }
            $got = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($want -ne $got) {
                throw "checksum mismatch for $asset (release says $want, the download is $got). Nothing was installed."
            }
            Say 'checksum ok'

            Say "installing rexenv $version for this user (no administrator prompt)"
            $process = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                throw "the installer stopped with exit code $($process.ExitCode)."
            }
        } finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }

        $installed = Get-InstalledRexenv
        if (-not $installed) {
            throw 'the installer finished, but Windows lists no rexenv under Installed apps.'
        }
        $dir = ([string]$installed.InstallLocation).Trim('"')
        Say "installed rexenv $version`: $dir"

        if ($env:REXENV_NO_LAUNCH -eq '1') {
            Say 'not starting it (REXENV_NO_LAUNCH=1). Start rexenv from the Start menu.'
            return
        }
        Start-Process -FilePath (Join-Path $dir 'rexenv.exe')
        Say 'started. rexenv lives in the taskbar tray: left-click its icon to open the window.'
    }

    try {
        Install-Rexenv
    } catch {
        Write-Host "rexenv: $($_.Exception.Message)" -ForegroundColor Red
    }
}
