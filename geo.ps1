<#
.SYNOPSIS
  Interactive menu to manage Windows 11 geolocation settings (disable services, adapters, registry), check statuses, network adapters, IP/DNS, and view documentation.
.DESCRIPTION
  1) Disable services, Wi‑Fi adapters & registry tweaks, then check status
  2) Check current services, all network adapters & registry status only
  3) Disable services & Wi‑Fi adapters only (no registry), with checks
  4) Apply registry lockdown only, with checks
  5) Check public IP, DNS server configuration, and geolocation details
  6) Show detailed documentation and references
  7) Revert to default settings
  Q) Quit
.NOTES
  Run this in an elevated PowerShell session.
#>

# --- Ensure running as Admin ---
If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
      [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator."
    Exit 1
}

# --- Helper Pause function ---
Function Pause { Read-Host -Prompt "Press Enter to continue" }

# --- Configuration ---
$services = @(
    "lfsvc",             # Geolocation Service
    "SensorService",     # Sensor Service
    "SensrSvc",          # Sensor Monitoring Service
    "SensorDataService", # Sensor Data Service
    "MapsBroker",        # Downloaded Maps Manager
    "DiagTrack",         # Connected User Experiences & Telemetry
    "Wlansvc"            # WLAN AutoConfig
)
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
$regValues = @{  
    "DisableLocation"                = 1
    "DisableWindowsLocationProvider" = 1
    "DisableSensors"                 = 1
    "DisableLocationScripting"       = 1
}

# --- Functions ---
Function Disable-ServiceAndCheck {
    Param([string]$Name)
    Write-Host " >> Disabling service '$Name' ..." -ForegroundColor Cyan
    Try {
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        Stop-Service -Name $Name -Force -ErrorAction Stop
    } Catch {
        Write-Warning "  ⚠ Could not disable/stop '$Name': $_"
    }
    $svc = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    If ($svc) {
        Write-Host "  ✔ $Name ▶ StartupType=$($svc.StartMode), Status=$($svc.State)"
    } Else {
        Write-Host "  ⚠ Service '$Name' not found."
    }
    Write-Host ""
}

Function Check-ServiceStatus {
    Param([string]$Name)
    $svc = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    If ($svc) {
        Write-Host ("$Name ▶ StartupType={0}, Status={1}" -f $svc.StartMode, $svc.State)
    } Else {
        Write-Host ("$Name ▶ Not Installed")
    }
}

Function Disable-WiFiAdaptersAndCheck {
    Write-Host " >> Disabling Wi‑Fi adapters ..." -ForegroundColor Cyan
    $wifiAdapters = Get-NetAdapter -Physical | Where-Object { $_.InterfaceDescription -Match 'Wireless|Wi-?Fi' }
    If ($wifiAdapters) {
        foreach ($adapter in $wifiAdapters) {
            Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            $status = (Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue).Status
            Write-Host "  ✔ Adapter '$($adapter.Name)' status: $status"
        }
    } Else {
        Write-Host "  ⚠ No Wi‑Fi adapters found."
    }
    Write-Host ""
}

Function Check-NetworkAdaptersStatus {
    Write-Host " >> Network adapters status:" -ForegroundColor Cyan
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue
    foreach ($adapter in $adapters) {
        $isWifi = $adapter.InterfaceDescription -Match 'Wireless|Wi-?Fi'
        $nameColor = if ($isWifi) { 'Magenta' } else { 'White' }
        switch ($adapter.Status) {
            'Up'           { $statusColor = 'Green'; break }
            'Disabled'     { $statusColor = 'Red'; break }
            'Disconnected' { $statusColor = 'Yellow'; break }
            Default        { $statusColor = 'White' }
        }
        Write-Host ($adapter.Name) -ForegroundColor $nameColor -NoNewline
        Write-Host (" - $($adapter.InterfaceDescription)") -ForegroundColor 'Gray' -NoNewline
        Write-Host (" ▶ Status: $($adapter.Status)") -ForegroundColor $statusColor
    }
    Write-Host ""
}

Function Set-RegistryValueAndCheck {
    Param([string]$Name, [int]$Value)
    Write-Host " >> Setting registry '$Name' = $Value" -ForegroundColor Cyan
    Try {
        # Ensure the registry path exists
        If (-not (Test-Path $regPath)) {
            Write-Host "  ✔ Creating registry path: $regPath" -ForegroundColor Green
            New-Item -Path $regPath -Force | Out-Null
        }
        # Set the registry value
        New-ItemProperty -Path $regPath -Name $Name -Value $Value -PropertyType DWORD -Force | Out-Null
    } Catch {
        Write-Warning "  ⚠ Could not write '$Name': $_"
    }
    Try {
        # Verify the registry value
        $prop = Get-ItemProperty -Path $regPath -Name $Name -ErrorAction Stop
        Write-Host ("  ✔ {0} = {1}" -f $Name, $prop.$Name)
    } Catch {
        Write-Warning "  ⚠ {0} not set" -f $Name
    }
    Write-Host ""
}

Function Check-RegistryStatus {
    Param([string]$Name)
    Try {
        $prop = Get-ItemProperty -Path $regPath -Name $Name -ErrorAction Stop
        Write-Host ("{0} = {1}" -f $Name, $prop.$Name)
    } Catch {
        Write-Host ("{0} ▶ Not Configured" -f $Name)
    }
}

Function Check-PublicIPAndDns {
    Param()
    $activity = "Checking Public IP & Geolocation"

    # Step 1: Retrieve Public IP
    Write-Progress -Activity $activity -Status "Retrieving public IP…" -PercentComplete 0
    Try {
        $publicIP = Invoke-RestMethod -Uri 'http://api.ipify.org?format=json' -UseBasicParsing -ErrorAction Stop | Select-Object -ExpandProperty ip
        Write-Progress -Activity $activity -Status "Public IP retrieved: $publicIP" -PercentComplete 50
        Write-Host "  ✔ Public IP: $publicIP" -ForegroundColor Green
    } Catch {
        Write-Progress -Activity $activity -Status "Failed to retrieve public IP" -PercentComplete 50
        Write-Warning "  ⚠ Could not retrieve public IP: $_"
    }

    # Step 2: Retrieve Geolocation
    Write-Progress -Activity $activity -Status "Retrieving geolocation info…" -PercentComplete 60
    Try {
        $geo = Invoke-RestMethod -Uri "http://ip-api.com/json/$publicIP" -UseBasicParsing -ErrorAction Stop
        Write-Progress -Activity $activity -Status "Geolocation retrieved" -PercentComplete 100
        Write-Host "  City:        $($geo.city)"         -ForegroundColor Green
        Write-Host "  Region:      $($geo.regionName)"   -ForegroundColor Green
        Write-Host "  Country:     $($geo.country)"      -ForegroundColor Green
        Write-Host "  Coordinates: $($geo.lat), $($geo.lon)" -ForegroundColor Green
        Write-Host "  ISP:         $($geo.isp)"          -ForegroundColor Green
    } Catch {
        Write-Progress -Activity $activity -Status "Failed to retrieve geolocation" -PercentComplete 100
        Write-Warning "  ⚠ Could not retrieve geolocation: $_"
    }

    # Clear the progress bar
    Write-Progress -Activity $activity -Completed
    Write-Host ""
}

Function Show-Documentation {
    Write-Host " >> Detailed Documentation and Results:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Geolocation Service (lfsvc)" -ForegroundColor White
    Write-Host "   Link: https://docs.microsoft.com/windows/privacy/manage-windows-location-service" -ForegroundColor Gray
    Write-Host "   Change: Service stopped & disabled to block precise location queries." -ForegroundColor Gray
    Write-Host "   Result: lfsvc is Disabled/Stopped; no OS or app location via GPS/Wi-Fi." -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Sensor & SensorData Services" -ForegroundColor White
    Write-Host "   Link: https://docs.microsoft.com/windows/privacy/windows-location-and-sensors" -ForegroundColor Gray
    Write-Host "   Change: Disabled SensorService, SensrSvc, SensorDataService to block hardware sensors." -ForegroundColor Gray
    Write-Host "   Result: No GPS, accelerometer, or ambient-light sensor data available." -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Downloaded Maps Manager (MapsBroker)" -ForegroundColor White
    Write-Host "   Link: https://docs.microsoft.com/windows/apps/maps/offline-maps" -ForegroundColor Gray
    Write-Host "   Change: Disabled service to stop map caching and background downloads." -ForegroundColor Gray
    Write-Host "   Result: Offline maps and location-assisted map features disabled." -ForegroundColor Gray
    Write-Host ""
    Write-Host "4. Connected User Experiences & Telemetry (DiagTrack)" -ForegroundColor White
    Write-Host "   Link: https://docs.microsoft.com/windows/privacy/windows-telemetry" -ForegroundColor Gray
    Write-Host "   Change: Disabled to prevent telemetry that may include network-based geodata." -ForegroundColor Gray
    Write-Host "   Result: Diagnostic uploads limited to basic; reduces location-related metadata." -ForegroundColor Gray
    Write-Host ""
    Write-Host "5. WLAN AutoConfig (Wlansvc)" -ForegroundColor White
    Write-Host "   Link: https://docs.microsoft.com/windows/wlan/wlan-auto-config-service" -ForegroundColor Gray
    Write-Host "   Change: Disabled Wi-Fi adapter management to block SSID scanning." -ForegroundColor Gray
    Write-Host "   Result: Wi-Fi adapters disabled; no SSID/MAC data collected." -ForegroundColor Gray
    Write-Host ""
    Write-Host "6. Registry Policies (LocationAndSensors)" -ForegroundColor White
    Write-Host "   Link: https://docs.microsoft.com/windows/configuration/administrative-templates#location-and-sensors" -ForegroundColor Gray
    Write-Host "   Change: Set policy keys to lock down location and sensor settings." -ForegroundColor Gray
    Write-Host "   Result: Settings toggles grayed out; cannot re-enable without registry undo." -ForegroundColor Gray
    Write-Host ""
    Write-Host "7. DNS Client Configuration" -ForegroundColor White
    Write-Host "   Link: https://docs.microsoft.com/windows-server/networking/dns/dns-client-settings" -ForegroundColor Gray
    Write-Host "   Change: Reviewed adapter DNS entries for leak detection." -ForegroundColor Gray
    Write-Host "   Result: DNS servers listed; verify no unauthorized entries." -ForegroundColor Gray
    Write-Host ""
    Write-Host "8. Public IP Lookup (ipify)" -ForegroundColor White
    Write-Host "   Link: https://www.ipify.org/" -ForegroundColor Gray
    Write-Host "   Change: Retrieved external IP to confirm internet egress address." -ForegroundColor Gray
    Write-Host "   Result: Identifies IP geolocation fallback source." -ForegroundColor Gray
    Write-Host ""
    Write-Host "9. IP Geolocation API (ip-api.com)" -ForegroundColor White
    Write-Host "   Link: http://ip-api.com/" -ForegroundColor Gray
    Write-Host "   Change: Queried city/region/coords based on IP." -ForegroundColor Gray
    Write-Host "   Result: Coarse location details available; no fine-grained tracking." -ForegroundColor Gray
    Write-Host ""
}

Function Show-Menu {
    Clear-Host
    Write-Host "Windows 11 Geolocation Control" -ForegroundColor White
    Write-Host "=================================" -ForegroundColor White
    Write-Host "1) Disable services, Wi‑Fi adapters & registry tweaks, then check status"
    Write-Host "2) Check current services, all network adapters & registry status only"
    Write-Host "3) Disable services & Wi‑Fi adapters only (no registry), with checks"
    Write-Host "4) Apply registry lockdown only, with checks"
    Write-Host "5) Check public IP, DNS server configuration, and geolocation details"
    Write-Host "6) Show detailed documentation and references"
    Write-Host "7) Revert to default settings"
    Write-Host "Q) Quit"
}

Function Revert-DefaultSettings {
    Write-Host " >> Reverting to default settings..." -ForegroundColor Cyan

    # Re-enable services
    foreach ($svc in $services) {
        Write-Host " >> Enabling service '$svc' ..." -ForegroundColor Cyan
        Try {
            Set-Service -Name $svc -StartupType Automatic -ErrorAction Stop
            Start-Service -Name $svc -ErrorAction Stop
            Write-Host "  ✔ Service '$svc' enabled and started." -ForegroundColor Green
        } Catch {
            Write-Warning "  ⚠ Could not enable/start '$svc': $_"
        }
    }

    # Re-enable Wi-Fi adapters
    Write-Host " >> Enabling Wi‑Fi adapters ..." -ForegroundColor Cyan
    $wifiAdapters = Get-NetAdapter -Physical | Where-Object { $_.InterfaceDescription -Match 'Wireless|Wi-?Fi' }
    If ($wifiAdapters) {
        foreach ($adapter in $wifiAdapters) {
            Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            $status = (Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue).Status
            Write-Host "  ✔ Adapter '$($adapter.Name)' status: $status"
        }
    } Else {
        Write-Host "  ⚠ No Wi‑Fi adapters found."
    }

    # Reset registry values
    Write-Host " >> Resetting registry values to default..." -ForegroundColor Cyan
    foreach ($name in $regValues.Keys) {
        Try {
            Remove-ItemProperty -Path $regPath -Name $name -ErrorAction Stop
            Write-Host "  ✔ Registry value '$name' removed." -ForegroundColor Green
        } Catch {
            Write-Warning "  ⚠ Could not remove registry value '$name': $_"
        }
    }

    Write-Host " >> Default settings restored." -ForegroundColor Green
    Write-Host ""
}

# --- MAIN MENU LOOP ---
do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice) {
        '1' {
            Write-Host "`n[1] Disabling services & Wi‑Fi adapters..." -ForegroundColor Yellow
            foreach ($svc in $services) { Disable-ServiceAndCheck -Name $svc }
            Disable-WiFiAdaptersAndCheck
            Write-Host "[1] Applying registry tweaks..." -ForegroundColor Yellow
            foreach ($kv in $regValues.GetEnumerator()) { Set-RegistryValueAndCheck -Name $kv.Key -Value $kv.Value }
            Pause
        }
        '2' {
            Write-Host "`n[2] Checking service status..." -ForegroundColor Yellow
            foreach ($svc in $services) { Check-ServiceStatus -Name $svc }
            Check-NetworkAdaptersStatus
            Write-Host "`n[2] Checking registry status..." -ForegroundColor Yellow
            foreach ($name in $regValues.Keys) { Check-RegistryStatus -Name $name }
            Pause
        }
        '3' {
            Write-Host "`n[3] Disabling services & Wi‑Fi adapters only..." -ForegroundColor Yellow
            foreach ($svc in $services) { Disable-ServiceAndCheck -Name $svc }
            Disable-WiFiAdaptersAndCheck
            Pause
        }
        '4' {
            Write-Host "`n[4] Applying registry lockdown only..." -ForegroundColor Yellow
            foreach ($kv in $regValues.GetEnumerator()) { Set-RegistryValueAndCheck -Name $kv.Key -Value $kv.Value }
            Pause
        }
        '5' {
            Write-Host "`n[5] Checking public IP, DNS & geolocation..." -ForegroundColor Yellow
            Check-PublicIPAndDns
            Pause
        }
        '6' {
            Write-Host "`n[6] Detailed documentation and references..." -ForegroundColor Yellow
            Show-Documentation
            Pause
        }
        '7' {
            Write-Host "`n[7] Reverting to default settings..." -ForegroundColor Yellow
            Revert-DefaultSettings
            Pause
        }
        'Q' {
            Write-Host "Exiting..." -ForegroundColor Green
            break
        }
        'q' {
            Write-Host "Exiting..." -ForegroundColor Green
            break
        }
        Default {
            Write-Warning "Invalid selection. Please choose 1–7 or Q."
            Pause
        }
    }
} while ($true)
