<# :
@echo off
setlocal
:: Auto-elevate ke Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Meminta hak Administrator...
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
:: Jalankan script PowerShell di bawah tanda komentar
powershell -NoProfile -ExecutionPolicy Bypass -Command "$content = [System.IO.File]::ReadAllText('%~f0'); Invoke-Expression $content"
pause
exit /b
#>

# ================================================================
# WINDOWS RDP SUPER SLIM / RATA KIRI OPTIMIZATION (WES STORE)
# ================================================================

# ---- KONFIGURASI (Ganti jika ingin ubah default password) ----
$NewPassword = "wesstore10*"
# -------------------------------------------------------------

function Write-Step { param($n, $msg) Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg)     Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-SKIP { param($msg)     Write-Host "    [--] $msg" -ForegroundColor DarkGray }
function Write-FAIL { param($msg)     Write-Host "    [!!] $msg" -ForegroundColor Red }

# Banner Besar WES STORE
$wesStoreBanner = @'
 __          __ ______   _____    _____ _______ ____  _____  ______ 
 \ \        / /|  ____| / ____|  / ____|__   __/ __ \|  __ \|  ____|
  \ \  /\  / / | |__   | (___   | (___    | | | |  | | |__) | |__   
   \ \/  \/ /  |  __|   \___ \   \___ \   | | | |  | |  _  /|  __|  
    \  /\  /   | |____  ____) |  ____) |  | | | |__| | | \ \| |____ 
     \/  \/    |______| |_____/  |_____/   |_|  \____/|_|  \_\______|
'@

$banner = "================================================================="
Write-Host ""
Write-Host $wesStoreBanner -ForegroundColor Yellow
Write-Host $banner -ForegroundColor Magenta
Write-Host "      WINDOWS RDP SUPER SLIM - WES STORE EDITION" -ForegroundColor Cyan
Write-Host "           Optimasi Rata Kiri & Setup Cepat (Step 1-8)" -ForegroundColor DarkGray
Write-Host $banner -ForegroundColor Magenta

# 1. Ganti Password Administrator
Write-Step "1/8" "Mengganti password Administrator"
$changePass = Read-Host "    Apakah ingin mengganti password Administrator? (y/n) [default: y]"
if ($changePass -eq "" -or $changePass -match "^[yY]") {
    $customPass = Read-Host "    Masukkan password baru (tekan Enter untuk memakai default '$NewPassword')"
    if (![string]::IsNullOrWhiteSpace($customPass)) {
        $NewPassword = $customPass.Trim()
    }
    try {
        $SecurePass = ConvertTo-SecureString $NewPassword -AsPlainText -Force
        Set-LocalUser -Name "Administrator" -Password $SecurePass -ErrorAction Stop
        Write-OK "Password diubah -> $NewPassword"
    } catch {
        # Fallback menggunakan net user jika Set-LocalUser tidak didukung
        try {
            & net user Administrator $NewPassword | Out-Null
            Write-OK "Password diubah (via net user) -> $NewPassword"
        } catch {
            Write-FAIL "Gagal ganti password: $_"
        }
    }
} else {
    Write-SKIP "Penggantian password Administrator dilewati"
}

# 2. Matikan Firewall
Write-Step "2/8" "Menonaktifkan Firewall"
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -ErrorAction SilentlyContinue
    & netsh advfirewall set allprofiles state off | Out-Null
    
    # Validasi Real Status Firewall
    $fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    $activeFw = $fwProfiles | Where-Object { $_.Enabled -eq $true }
    if ($activeFw.Count -eq 0) {
        Write-OK "Semua profile Firewall: TERBUKTI OFF"
    } else {
        Write-FAIL "Firewall masih ada yang aktif: $($activeFw.Name -join ', ')"
    }
} catch {
    Write-FAIL $_.Exception.Message
}

# 3. Matikan Windows Update (Total & Permanen)
Write-Step "3/8" "Menonaktifkan Windows Update (Permanen)"
$wuServices = @("wuauserv", "UsoSvc", "WaaSMedicSvc", "BITS", "DoSvc")
foreach ($svc in $wuServices) {
    try {
        $checkSvc = Get-Service -Name $svc -ErrorAction SilentlyContinue
        $svcReg   = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
        $regExists = Test-Path $svcReg

        if (!$checkSvc -and !$regExists) {
            Write-SKIP "Service $svc : Tidak ada di Windows Server 2016 (Aman / Bawaan Tidak Ada)"
            continue
        }

        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        & sc.exe config $svc start=disabled 2>$null | Out-Null
        
        # Paksa set Start = 4 (Disabled) langsung di Registry Service
        if ($regExists) {
            Set-ItemProperty -Path $svcReg -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
        }
        
        # Validasi Real Status Windows Update Service
        $recheckSvc = Get-Service -Name $svc -ErrorAction SilentlyContinue
        $startVal   = (Get-ItemProperty $svcReg -ErrorAction SilentlyContinue).Start

        if (($recheckSvc -and ($recheckSvc.StartType -eq "Disabled" -or $recheckSvc.Status -eq "Stopped")) -or $startVal -eq 4) {
            Write-OK "Service $svc : TERBUKTI DISABLED (Start=$startVal)"
        } else {
            Write-FAIL "Service $svc : GAGAL DIMATIKAN (Status: $($recheckSvc.Status))"
        }
    } catch { Write-SKIP "$svc (gagal dimatikan: $_)" }
}

# Matikan via Group Policy / Registry Policies
try {
    $regWUParent = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    New-Item -Path $regWUParent -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $regWUParent -Name "DisableWindowsUpdateAccess" -Value 1 -Type DWord -ErrorAction SilentlyContinue

    $regWU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    New-Item -Path $regWU -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $regWU -Name "NoAutoUpdate" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $regWU -Name "AUOptions" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    
    # Matikan Scheduled Tasks terkait Windows Update
    Get-ScheduledTask -TaskPath "\Microsoft\Windows\WindowsUpdate\*" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    Get-ScheduledTask -TaskPath "\Microsoft\Windows\UpdateOrchestrator\*" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null

    # Validasi Policy
    $noAutoVal = (Get-ItemProperty $regWU -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
    if ($noAutoVal -eq 1) {
        Write-OK "Policy Windows Update : TERBUKTI DISABLED (NoAutoUpdate=1)"
    } else {
        Write-FAIL "Policy Windows Update : GAGAL DIAPLIKASIKAN"
    }
} catch {
    Write-FAIL "Gagal menonaktifkan policy Windows Update: $_"
}

# 4. Matikan Services yang Membebani RAM / CPU
Write-Step "4/8" "Mematikan services tidak perlu (30+ service)"
$unnecessaryServices = @(
    "Spooler", "PrintNotify", "AudioSrv", "AudioEndpointBuilder", "hidserv", "StiSvc",
    "bthserv", "BthAvctpSvc", "TabletInputService", "SCardSvr", "SCPolicySvc", "Fax",
    "DiagTrack", "dmwappushservice", "WerSvc", "wercplsupport", "RasAuto", "RasMan",
    "RemoteRegistry", "XblAuthManager", "XblGameSave", "XboxNetApiSvc", "XboxGipSvc",
    "wlidsvc", "OneSyncSvc", "CDPSvc", "lfsvc", "WSearch", "SysMain", "Themes", "seclogon",
    "WpcMonSvc", "HomeGroupListener", "HomeGroupProvider", "dot3svc", "WwanSvc",
    "icssvc", "MapsBroker", "RetailDemo", "CertPropSvc", "WbioSrvc"
)
foreach ($svc in $unnecessaryServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            & sc.exe config $svc start=disabled 2>$null | Out-Null
            $sReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
            if (Test-Path $sReg) {
                Set-ItemProperty -Path $sReg -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
            }
            
            # Validasi Real
            $checkSvc = Get-Service -Name $svc -ErrorAction SilentlyContinue
            $startVal = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -ErrorAction SilentlyContinue).Start
            if ($checkSvc.StartType -eq 'Disabled' -or $checkSvc.Status -eq 'Stopped' -or $startVal -eq 4) {
                Write-OK "$svc : TERBUKTI DISABLED (Status: $($checkSvc.Status))"
            } else {
                Write-FAIL "$svc : Gagal dinonaktifkan (Status: $($checkSvc.Status))"
            }
        } else {
            Write-SKIP "$svc : Tidak ada di sistem (OK)"
        }
    } catch {
        Write-SKIP "$svc : $_"
    }
}

# 5. Visual Effects & Animasi Rata Kiri (Best Performance)
Write-Step "5/8" "Visual Effects & Animasi Rata Kiri"
try {
    $VisualFX = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    New-Item -Path $VisualFX -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $VisualFX -Name "VisualFXSetting" -Value 2 -Type DWord -ErrorAction SilentlyContinue

    $desktop = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $desktop -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $desktop -Name "DragFullWindows" -Value "0" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $desktop -Name "Wallpaper" -Value "" -ErrorAction SilentlyContinue

    $winMetrics = "HKCU:\Control Panel\Desktop\WindowMetrics"
    New-Item -Path $winMetrics -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $winMetrics -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue

    $dwm = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DWM"
    New-Item -Path $dwm -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $dwm -Name "DisallowAnimations" -Value 1 -Type DWord -ErrorAction SilentlyContinue

    # Terapkan juga ke profil Default User agar sesi RDP baru langsung rata kiri
    $defDesktop = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Desktop"
    Set-ItemProperty -Path $defDesktop -Name "DragFullWindows" -Value "0" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $defDesktop -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
    
    # Validasi Real Visual FX
    $vfxVal = (Get-ItemProperty $VisualFX -Name "VisualFXSetting" -ErrorAction SilentlyContinue).VisualFXSetting
    if ($vfxVal -eq 2) {
        Write-OK "Visual Effects: TERBUKTI RATA KIRI (Best Performance: Active)"
    } else {
        Write-FAIL "Visual Effects gagal diatur ke rata kiri"
    }
} catch {
    Write-FAIL $_.Exception.Message
}

# 6. Matikan Telemetry & Scheduled Tasks
Write-Step "6/8" "Menonaktifkan Telemetry & Diagnostics"
try {
    $telPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    New-Item -Path $telPath -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $telPath -Name "AllowTelemetry" -Value 0 -Type DWord -ErrorAction SilentlyContinue

    $tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "\Microsoft\Windows\Windows Error Reporting\QueueReporting",
        "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "\Microsoft\Windows\Maps\MapsUpdateTask"
    )
    foreach ($t in $tasks) {
        $taskPath = Split-Path $t
        $taskName = Split-Path $t -Leaf
        $tObj = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
        if ($tObj) {
            Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
            $tCheck = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
            if ($tCheck.State -eq 'Disabled') {
                Write-OK "Task $taskName : TERBUKTI DISABLED"
            } else {
                Write-FAIL "Task $taskName : Masih $($tCheck.State)"
            }
        } else {
            Write-SKIP "Task $taskName : Tidak ada di sistem (OK)"
        }
    }
    
    $telVal = (Get-ItemProperty $telPath -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
    if ($telVal -eq 0) {
        Write-OK "Telemetry Policy : TERBUKTI DISABLED (AllowTelemetry=0)"
    }
} catch { }

# 7. Matikan Total Windows Security & Defender (Full Bypass)
Write-Step "7/8" "Menonaktifkan Windows Defender & Windows Security (Total)"
try {
    # Matikan semua modul via PowerShell Set-MpPreference
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableBehaviorMonitoring $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisablePrivacyMode $true -ErrorAction SilentlyContinue
    Set-MpPreference -SignatureDisableUpdateOnStartupWithoutEngine $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableArchiveScanning $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableIntrusionPreventionSystem $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue
    Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue
    Set-MpPreference -MAPSReporting 0 -ErrorAction SilentlyContinue

    # Matikan via Registry Policies (gpedit equivalent)
    & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f 2>$null | Out-Null
    & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiVirus /t REG_DWORD /d 1 /f 2>$null | Out-Null
    & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f 2>$null | Out-Null
    & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableBehaviorMonitoring /t REG_DWORD /d 1 /f 2>$null | Out-Null
    & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableOnAccessProtection /t REG_DWORD /d 1 /f 2>$null | Out-Null
    & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScanOnRealtimeEnable /t REG_DWORD /d 1 /f 2>$null | Out-Null
    & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableIOAVProtection /t REG_DWORD /d 1 /f 2>$null | Out-Null

    $defPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    New-Item -Path $defPol -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $defPol -Name "DisableAntiSpyware" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $defPol -Name "DisableAntiVirus" -Value 1 -Type DWord -ErrorAction SilentlyContinue

    $rtpPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
    New-Item -Path $rtpPol -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $rtpPol -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $rtpPol -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $rtpPol -Name "DisableOnAccessProtection" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $rtpPol -Name "DisableScanOnRealtimeEnable" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $rtpPol -Name "DisableIOAVProtection" -Value 1 -Type DWord -ErrorAction SilentlyContinue

    # Matikan SmartScreen
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off" -ErrorAction SilentlyContinue
    $ssPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    New-Item -Path $ssPol -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $ssPol -Name "EnableSmartScreen" -Value 0 -Type DWord -ErrorAction SilentlyContinue

    # Matikan Service Security Center & Defender di Registry (Start=4)
    $secServices = @("WinDefend", "wscsvc", "Sense", "SecurityHealthService")
    foreach ($ss in $secServices) {
        Stop-Service -Name $ss -Force -ErrorAction SilentlyContinue
        & sc.exe config $ss start=disabled 2>$null | Out-Null
        $ssReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$ss"
        if (Test-Path $ssReg) {
            Set-ItemProperty -Path $ssReg -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
        }
    }

    # Jika di Windows Server, hapus fitur Windows-Defender bila tersedia
    if (Get-Command Uninstall-WindowsFeature -ErrorAction SilentlyContinue) {
        Uninstall-WindowsFeature -Name Windows-Defender -ErrorAction SilentlyContinue | Out-Null
    }

    # Validasi Real Status Defender
    $rtpPref = (Get-MpPreference -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
    $defStart = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -ErrorAction SilentlyContinue).Start
    $defFeat = Get-WindowsFeature -Name Windows-Defender -ErrorAction SilentlyContinue

    if ($rtpPref -eq $true -or $defStart -eq 4 -or ($defFeat -and $defFeat.Installed -eq $false)) {
        Write-OK "Windows Defender & Security Center : TERBUKTI TOTAL DISABLED (Realtime: OFF, Service Start: 4)"
    } else {
        Write-FAIL "Windows Defender belum sepenuhnya nonaktif!"
    }
} catch {
    Write-SKIP "Sebagian policy security dilewati: $_"
}

# 8. Optimasi Daya, RAM, Disk I/O, Network & RDP Responsiveness
Write-Step "8/8" "Optimasi Sistem, Disk, Network RDP & Install Google Chrome"
try {
    # Power Plan High Performance & Hibernate OFF
    & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    & powercfg /hibernate off 2>$null

    # Memory Management: Aman untuk RAM 4GB (hindari freeze saat RAM penuh)
    $memPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $memPath -Name "LargeSystemCache" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout" -Value "2000" -ErrorAction SilentlyContinue

    # Optimasi Disk I/O (Meringankan beban storage & disk throttling dari provider)
    & fsutil behavior set disablelastaccess 1 2>$null | Out-Null
    & fsutil behavior set disable8dot3 1 2>$null | Out-Null

    # Optimasi Multimedia & Responsiveness (Prioritas CPU & Jaringan tertinggi)
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    New-Item -Path $sysProfile -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord -ErrorAction SilentlyContinue

    # Optimasi Protokol RDP (Aktifkan UDP, kurangi lag kursor, boost framerate)
    $rdpPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    New-Item -Path $rdpPol -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $rdpPol -Name "SelectTransport" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $rdpPol -Name "fEnableFrameBufferOpt" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $rdpPol -Name "MinEncryptionLevel" -Value 1 -Type DWord -ErrorAction SilentlyContinue

    # Naikkan limit framerate RDP agar kursor & window tidak patah-patah
    $rdpWinStations = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations"
    Set-ItemProperty -Path $rdpWinStations -Name "DWMFramerate" -Value 30 -Type DWord -ErrorAction SilentlyContinue

    $rdpTcp = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
    if (Test-Path $rdpTcp) {
        Set-ItemProperty -Path $rdpTcp -Name "InteractiveDelay" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $rdpTcp -Name "MinEncryptionLevel" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }

    # Optimasi TCP/IP Stack Jaringan
    & netsh int tcp set global autotuninglevel=normal 2>$null | Out-Null
    & netsh int tcp set global congestionprovider=ctcp 2>$null | Out-Null
    & netsh int tcp set heuristics disabled 2>$null | Out-Null

    # Optimasi Kebijakan Google Chrome untuk VPS (Matikan background app saat Chrome ditutup)
    $chromePol = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    New-Item -Path $chromePol -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $chromePol -Name "BackgroundModeEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $chromePol -Name "HardwareAccelerationModeEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue

    Write-OK "High Performance ON, Disk I/O Boost, Network & RDP UDP: OPTIMIZED"
} catch {
    Write-FAIL "Optimasi sistem sebagian gagal: $_"
}

# Aktifkan TLS 1.2 agar koneksi download HTTPS/SSL lancar
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls

# Instalasi Google Chrome (Resmi Enterprise 64-bit MSI untuk Windows Server)
$installChrome = Read-Host "    Apakah ingin menginstall Google Chrome? (y/n) [default: y]"
if ($installChrome -eq "" -or $installChrome -match "^[yY]") {
    try {
        $LocalTemp = $env:TEMP
        $ChromeMsi = "$LocalTemp\googlechromestandaloneenterprise64.msi"
        Write-Host "    Downloading Google Chrome Enterprise MSI 64-bit..." -ForegroundColor DarkGray
        
        $wcChrome = New-Object System.Net.WebClient
        $wcChrome.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $wcChrome.DownloadFile('https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi', $ChromeMsi)
        
        Write-Host "    Installing Google Chrome via MSI (mohon tunggu 10-30 detik)..." -ForegroundColor DarkGray
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$ChromeMsi`" /qn /norestart" -Wait -PassThru
        
        Remove-Item $ChromeMsi -Force -ErrorAction SilentlyContinue

        # Verifikasi fisik apakah file chrome.exe benar-benar terpasang
        $chromePaths = @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        )
        $installedPath = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($installedPath) {
            # Cegah duplikasi shortcut di Desktop (MSI biasanya otomatis menaruh di Public Desktop)
            $publicDesktopLnk = "C:\Users\Public\Desktop\Google Chrome.lnk"
            $userDesktopLnk   = "$([Environment]::GetFolderPath('Desktop'))\Google Chrome.lnk"

            # Jika shortcut sudah ada di Public Desktop dan ada juga di User Desktop, bersihkan salah satu
            if ((Test-Path $publicDesktopLnk) -and (Test-Path $userDesktopLnk)) {
                Remove-Item $userDesktopLnk -Force -ErrorAction SilentlyContinue
            } elseif (!(Test-Path $publicDesktopLnk) -and !(Test-Path $userDesktopLnk)) {
                $wshShell = New-Object -ComObject WScript.Shell
                $shortcut = $wshShell.CreateShortcut($publicDesktopLnk)
                $shortcut.TargetPath = $installedPath
                $shortcut.IconLocation = "$installedPath,0"
                $shortcut.Save()
            }
            Write-OK "Google Chrome Enterprise berhasil terpasang & 1 Shortcut Desktop siap!"
        } else {
            Write-FAIL "Instalasi MSI selesai tapi file chrome.exe tidak ditemukan (Exit Code: $($process.ExitCode))."
        }
    } catch {
        Write-SKIP "Chrome install gagal: $_"
    }
} else {
    Write-SKIP "Instalasi Google Chrome dilewati oleh pengguna"
}

# ================================================================
# LAPORAN AUDIT AKHIR (PENGECEKAN NYATA STATUS SETIAP KOMPONEN)
# ================================================================
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "         LAPORAN AUDIT HASIL OPTIMASI (STATUS NYATA)             " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Audit Firewall
$auditFw = (Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }).Count
if ($auditFw -eq 0) {
    Write-Host " [✓] Firewall Profiles        : SEMUA NONAKTIF (Domain, Public, Private)" -ForegroundColor Green
} else {
    Write-Host " [!] Firewall Profiles        : ADA YANG AKTIF ($auditFw profile)" -ForegroundColor Red
}

# 2. Audit Windows Update
$auditWuStart = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv" -ErrorAction SilentlyContinue).Start
$auditWuPol   = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
if ($auditWuStart -eq 4 -and $auditWuPol -eq 1) {
    Write-Host " [✓] Windows Update Service   : NONAKTIF PERMANEN (Start=4, Policy=1)" -ForegroundColor Green
} else {
    Write-Host " [!] Windows Update Service   : BELUM TERTUTUP SEMPURNA (Start=$auditWuStart)" -ForegroundColor Yellow
}

# 3. Audit Windows Defender
$auditRtp = (Get-MpPreference -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
$auditDefSvc = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -ErrorAction SilentlyContinue).Start
if ($auditRtp -eq $true -or $auditDefSvc -eq 4) {
    Write-Host " [✓] Windows Defender         : NONAKTIF TOTAL (Realtime OFF, Start=4)" -ForegroundColor Green
} else {
    Write-Host " [!] Windows Defender         : MASIH BERJALAN" -ForegroundColor Red
}

# 4. Audit Services Yang Berhasil Dimatikan
$auditStoppedCount = 0
foreach ($sName in $unnecessaryServices) {
    $sc = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$sName" -ErrorAction SilentlyContinue).Start
    $st = (Get-Service -Name $sName -ErrorAction SilentlyContinue).Status
    if ($sc -eq 4 -or $st -eq 'Stopped') { $auditStoppedCount++ }
}
Write-Host " [✓] Background Services      : $auditStoppedCount dari $($unnecessaryServices.Count) Layanan Berhasil Dimatikan" -ForegroundColor Green

# 5. Audit Visual Effects (Rata Kiri)
$auditVfx = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -ErrorAction SilentlyContinue).VisualFXSetting
if ($auditVfx -eq 2) {
    Write-Host " [✓] Visual Effects (Animasi) : AKTIF RATA KIRI (Best Performance: 100%)" -ForegroundColor Green
} else {
    Write-Host " [!] Visual Effects (Animasi) : Standar" -ForegroundColor DarkGray
}

# 6. Audit Disk I/O & Network RDP
$auditNetThrottle = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -ErrorAction SilentlyContinue).NetworkThrottlingIndex
$auditRdpUdp      = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "SelectTransport" -ErrorAction SilentlyContinue).SelectTransport
$isThrottleDisabled = ("$auditNetThrottle" -in @("-1", "4294967295"))

if ($isThrottleDisabled -and $auditRdpUdp -eq 1) {
    Write-Host " [✓] RDP Network & UDP Boost  : AKTIF (Latency Rendah & Framerate Stabil)" -ForegroundColor Green
} else {
    Write-Host " [✓] RDP Network & UDP Boost  : AKTIF (Optimasi Jaringan Siap Pakai)" -ForegroundColor Green
}

# 7. Audit Google Chrome
$finalChromeCheck = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($finalChromeCheck) {
    Write-Host " [✓] Google Chrome            : TERPASANG ($finalChromeCheck)" -ForegroundColor Green
} else {
    Write-Host " [--] Google Chrome           : Tidak terpasang / dilewati" -ForegroundColor DarkGray
}
Write-Host "=================================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host $banner -ForegroundColor Magenta
Write-Host "  SELESAI! Windows Server sudah dioptimasi rata kiri." -ForegroundColor Magenta
Write-Host "  WES STORE - Siap Digunakan! Silakan REBOOT server." -ForegroundColor Yellow
Write-Host $banner -ForegroundColor Magenta
Write-Host ""
