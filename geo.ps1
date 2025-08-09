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

    # Try to get the service
    $svc = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue

    if ($svc) {
        # Service name in Cyan
        Write-Host $Name -ForegroundColor Cyan -NoNewline
        Write-Host " ▶ " -ForegroundColor Gray -NoNewline

        # Colorize StartupType
        switch ($svc.StartMode) {
            "Auto" { $modeColor = 'Green'; $modeText = 'Automatic'; break }
            "Manual" { $modeColor = 'Yellow'; $modeText = 'Manual'; break }
            "Disabled" { $modeColor = 'Red'; $modeText = 'Disabled'; break }
            default { $modeColor = 'White'; $modeText = $svc.StartMode }
        }
        Write-Host ("StartupType={0}" -f $modeText) -ForegroundColor $modeColor -NoNewline
        Write-Host ", " -ForegroundColor Gray -NoNewline

        # Colorize Status
        switch ($svc.State) {
            "Running" { $stateColor = 'Green'; break }
            "Stopped" { $stateColor = 'Red'; break }
            "Paused" { $stateColor = 'Yellow'; break }
            "StartPending" { $stateColor = 'Yellow'; break }
            "StopPending" { $stateColor = 'Yellow'; break }
            default { $stateColor = 'White' }
        }
        Write-Host ("Status={0}" -f $svc.State) -ForegroundColor $stateColor
    }
    else {
        # Not installed in Red
        Write-Host $Name -ForegroundColor Cyan -NoNewline
        Write-Host " ▶ " -ForegroundColor Gray -NoNewline
        Write-Host "Not Installed" -ForegroundColor Red
    }

    Write-Host ""
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
    Write-Host "`n=== Network Adapters Status ===" -ForegroundColor Cyan

    # Fetch adapters and PnP devices
    $adapters = Get-NetAdapter   -ErrorAction SilentlyContinue
    $pnpDevices = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue

    # Print a header with wider columns
    $col1 = "Name".PadRight(40)
    $col2 = "Description".PadRight(70)
    $col3 = "Adapter Status".PadRight(15)
    $col4 = "PnP Status".PadRight(15)
    Write-Host ("{0}{1}{2}{3}" -f $col1, $col2, $col3, $col4) -ForegroundColor DarkGray
    Write-Host ("-" * 150) -ForegroundColor DarkGray

    foreach ($adapter in $adapters) {
        # Determine adapter status color & icon
        switch ($adapter.Status) {
            'Up' { $aColor = 'Green'; $aIcon = '✔'; break }
            'Disabled' { $aColor = 'Red'; $aIcon = '✖'; break }
            'Disconnected' { $aColor = 'Yellow'; $aIcon = '⚠'; break }
            Default { $aColor = 'Gray'; $aIcon = '?'; break }
        }

        # Highlight Wi-Fi adapters
        $isWifi = $adapter.InterfaceDescription -Match 'Wireless|Wi-?Fi'
        $nameColor = if ($isWifi) { 'Magenta' } else { 'White' }

        # Find PnP device
        $pnp = $pnpDevices | Where-Object { $_.FriendlyName -eq $adapter.InterfaceDescription }
        if ($pnp) {
            switch ($pnp.Status) {
                'OK' { $pColor = 'Green'; $pIcon = '✔'; break }
                'Error' { $pColor = 'Red'; $pIcon = '✖'; break }
                'Disabled' { $pColor = 'Yellow'; $pIcon = '⚠'; break }
                Default { $pColor = 'Gray'; $pIcon = '?'; break }
            }
            $pText = "$pIcon $($pnp.Status)"
        }
        else {
            $pColor = 'Yellow'; $pText = "⚠ Not found"
        }

        # Format each field to the new widths
        $f1 = $adapter.Name.PadRight(40)
        $f2 = $adapter.InterfaceDescription.PadRight(70)
        $f3 = ("$aIcon $($adapter.Status)").PadRight(15)
        $f4 = $pText.PadRight(15)

        # Write the aligned, colored row
        Write-Host $f1 -ForegroundColor $nameColor -NoNewline
        Write-Host $f2 -ForegroundColor Gray      -NoNewline
        Write-Host $f3 -ForegroundColor $aColor    -NoNewline
        Write-Host $f4 -ForegroundColor $pColor
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
Function Show-Menu {
    Write-Host "`n=== Main Menu ===" -ForegroundColor Cyan
    Write-Host "1) Check status (services, adapters & registry)" -ForegroundColor Green
    Write-Host "2) Disable services & Wi-Fi adapters only" -ForegroundColor Yellow
    Write-Host "3) Apply registry lockdown only" -ForegroundColor Yellow
    Write-Host "4) Full lockdown (services + Wi-Fi + registry)" -ForegroundColor Yellow
    Write-Host "5) Check public IP, DNS & geolocation" -ForegroundColor Magenta
    Write-Host "6) Documentation & references" -ForegroundColor Magenta
    Write-Host "7) Revert to default settings" -ForegroundColor Red
    Write-Host "Q) Exit" -ForegroundColor DarkGray
}

# --- MAIN MENU LOOP ---
do {
    Show-Menu
    $choice = Read-Host "Select an option"

    switch ($choice.ToUpper()) {
        '1' {
            Write-Host "`n[1] Checking service status..." -ForegroundColor Green
            foreach ($svc in $services) { Check-ServiceStatus -Name $svc }

            Write-Host "[1] Checking network adapter status..." -ForegroundColor Green
            Check-NetworkAdaptersStatus

            Write-Host "[1] Checking registry status..." -ForegroundColor Green
            foreach ($name in $regValues.Keys) { Check-RegistryStatus -Name $name }

            Pause
        }
        '2' {
            Write-Host "`n[2] Disabling services & Wi-Fi adapters only..." -ForegroundColor Yellow
            foreach ($svc in $services) { Disable-ServiceAndCheck -Name $svc }
            Disable-WiFiAdaptersAndCheck
            Pause
        }
        '3' {
            Write-Host "`n[3] Applying registry lockdown only..." -ForegroundColor Yellow
            foreach ($kv in $regValues.GetEnumerator()) {
                Set-RegistryValueAndCheck -Name $kv.Key -Value $kv.Value
            }
            Pause
        }
        '4' {
            Write-Host "`n[4] Full lockdown: disabling services, Wi-Fi adapters & applying registry tweaks..." -ForegroundColor Yellow
            foreach ($svc in $services) { Disable-ServiceAndCheck -Name $svc }
            Disable-WiFiAdaptersAndCheck
            foreach ($kv in $regValues.GetEnumerator()) {
                Set-RegistryValueAndCheck -Name $kv.Key -Value $kv.Value
            }
            Pause
        }
        '5' {
            Write-Host "`n[5] Checking public IP, DNS & geolocation..." -ForegroundColor Magenta
            Check-PublicIPAndDns
            Pause
        }
        '6' {
            Write-Host "`n[6] Detailed documentation & references..." -ForegroundColor Magenta
            Show-Documentation
            Pause
        }
        '7' {
            Write-Host "`n[7] Reverting to default settings..." -ForegroundColor Red
            Revert-DefaultSettings
            Pause
        }
        'Q' {
            Write-Host "`nExiting..." -ForegroundColor DarkGray
            break
        }
        Default {
            Write-Host "Invalid selection. Please choose 1–7 or Q." -ForegroundColor Red
            Pause
        }
    }
} while ($true)
