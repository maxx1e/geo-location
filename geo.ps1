<#
SYNOPSIS
  Menu to manage Windows 11 geolocation surfaces: services, Wi-Fi adapters, registry, hardware checks, and a quick IP/geo check.
NOTES
  Run elevated (Administrator). ASCII only. Tested on Windows PowerShell 5.1 and PowerShell 7+.
  Bluetooth is intentionally not modified because it may be required for peripherals.
#>

# ---- Admin check ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Run this script as Administrator."
    exit 1
}

# ---- TLS preference (for older stacks) ----
try {
    $tls = [Net.SecurityProtocolType]::Tls12
    if ([Enum]::GetNames([Net.SecurityProtocolType]) -contains 'Tls13') {
        $tls = $tls -bor [Net.SecurityProtocolType]::Tls13
    }
    [Net.ServicePointManager]::SecurityProtocol = $tls
} catch { }

function Pause { Read-Host -Prompt "Press Enter to continue" }

# ---- Config ----
$services = @(
    "lfsvc",             # Geolocation Service
    "SensorService",     # Sensor Service
    "SensrSvc",          # Sensor Monitoring Service
    "SensorDataService", # Sensor Data Service
    "MapsBroker",        # Downloaded Maps Manager
    "DiagTrack",         # Connected User Experiences and Telemetry
    "WlanSvc"            # WLAN AutoConfig
)

$wifiAdapterPattern = 'Wireless|Wi-?Fi|WLAN|802\.11'
$wwanAdapterPattern = 'WWAN|Cellular|Mobile Broadband|LTE|5G|4G|eSIM|Quectel|Fibocom|Sierra|Telit'
$gnssDevicePattern = 'GPS|GNSS|Location|Geolocation|Sensor|Accelerometer|Compass|Gyroscope'

$policyRegistrySettings = @(
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"; Name = "DisableLocation";                Value = 1 },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"; Name = "DisableWindowsLocationProvider"; Value = 1 },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"; Name = "DisableSensors";                 Value = 1 },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"; Name = "DisableLocationScripting";       Value = 1 },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy";         Name = "LetAppsAccessLocation";          Value = 2 },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";             Name = "EnableActivityFeed";             Value = 0 },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";             Name = "PublishUserActivities";         Value = 0 },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";             Name = "UploadUserActivities";          Value = 0 },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection";     Name = "AllowTelemetry";                Value = 0 }
)

$privacyRegistrySettings = @(
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location";                 Name = "Value"; Value = "Deny" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location";                 Name = "Deny";  Value = 1 },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged";    Name = "Value"; Value = "Deny" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location";                 Name = "Value"; Value = "Deny" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location";                 Name = "Deny";  Value = 1 },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged";    Name = "Value"; Value = "Deny" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}"; Name = "SensorPermissionState"; Value = 0 },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}";   Name = "Value"; Value = "Deny" }
)

$registrySettings = $policyRegistrySettings + $privacyRegistrySettings

# Startup defaults used by "revert"
$serviceDefaultStartup = @{
    "lfsvc"             = "Manual"
    "SensorService"     = "Manual"
    "SensrSvc"          = "Manual"
    "SensorDataService" = "Manual"
    "MapsBroker"        = "Manual"
    "DiagTrack"         = "Automatic"
    "WlanSvc"           = "Automatic"
}

# ---- Functions ----
function Disable-ServiceAndCheck {
    param([string]$Name)
    Write-Host "Disabling service: $Name"

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host ("  {0}: Not found" -f $Name)
        return
    }

    if ($svc.Status -ne 'Stopped') {
        try {
            Stop-Service -Name $Name -Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not stop '$Name': $_"
        }
    }

    try {
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
    } catch {
        Write-Warning "Could not disable '$Name': $_"
    }

    $svcObj = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($svcObj) {
        Write-Host ("  {0}: StartupType={1}, Status={2}" -f $Name, $svcObj.StartMode, $svcObj.State)
    }
}

function Check-ServiceStatus {
    param([string]$Name)
    $svc = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($svc) {
        $modeText = switch ($svc.StartMode) {
            "Auto"     { "Automatic" }
            "Manual"   { "Manual" }
            "Disabled" { "Disabled" }
            default    { $svc.StartMode }
        }
        Write-Host ("  {0}: StartupType={1}, Status={2}" -f $Name, $modeText, $svc.State)
    } else {
        Write-Host ("  {0}: Not Installed" -f $Name)
    }
}

function Disable-WiFiAdaptersAndCheck {
    Write-Host "Disabling Wi-Fi adapters"
    $wifiAdapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match $wifiAdapterPattern }
    if ($wifiAdapters) {
        foreach ($adapter in $wifiAdapters) {
            try {
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            } catch {
                Write-Warning "Could not disable adapter '$($adapter.Name)': $_"
            }
            $status = (Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue).Status
            Write-Host ("  {0}: {1}" -f $adapter.Name, $status)
        }
    } else {
        Write-Host "  No Wi-Fi adapters found."
    }
}

function Check-NetworkAdaptersStatus {
    Write-Host "Network adapters:"
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue

    $pnpDevices = $null
    try {
        if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
            $pnpDevices = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue
        }
    } catch { }

    $col1 = "Name".PadRight(28)
    $col2 = "Description".PadRight(58)
    $col3 = "Status".PadRight(12)
    $col4 = "PnP".PadRight(12)
    Write-Host ($col1 + $col2 + $col3 + $col4)
    Write-Host ("-" * 110)

    foreach ($adapter in $adapters) {
        $pText = "N/A"
        if ($pnpDevices) {
            $pnp = $pnpDevices | Where-Object { $_.FriendlyName -eq $adapter.InterfaceDescription }
            $pText = if ($pnp) { $pnp.Status } else { "NotFound" }
        }
        $f1 = $adapter.Name.PadRight(28)
        $f2 = $adapter.InterfaceDescription.PadRight(58)
        $f3 = ($adapter.Status).PadRight(12)
        $f4 = $pText.PadRight(12)
        Write-Host ($f1 + $f2 + $f3 + $f4)
    }
}

function Check-LocationRelevantHardware {
    Write-Host "Location-relevant hardware inventory:"

    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue

    Write-Host "  Ethernet:"
    $ethernetAdapters = $adapters | Where-Object {
        $_.InterfaceDescription -notmatch $wifiAdapterPattern -and
        $_.InterfaceDescription -notmatch $wwanAdapterPattern -and
        $_.InterfaceDescription -notmatch 'Bluetooth'
    }
    if ($ethernetAdapters) {
        foreach ($adapter in $ethernetAdapters) {
            Write-Host ("    {0}: {1} - {2}" -f $adapter.Name, $adapter.Status, $adapter.InterfaceDescription)
        }
    } else {
        Write-Host "    Not detected"
    }

    Write-Host "  Wi-Fi:"
    $wifiAdapters = $adapters | Where-Object { $_.InterfaceDescription -match $wifiAdapterPattern }
    if ($wifiAdapters) {
        foreach ($adapter in $wifiAdapters) {
            Write-Host ("    {0}: {1} - {2}" -f $adapter.Name, $adapter.Status, $adapter.InterfaceDescription)
        }
    } else {
        Write-Host "    Not detected"
    }

    Write-Host "  WWAN/LTE/eSIM:"
    $wwanAdapters = $adapters | Where-Object { $_.InterfaceDescription -match $wwanAdapterPattern }
    if ($wwanAdapters) {
        foreach ($adapter in $wwanAdapters) {
            Write-Warning ("    PRESENT: {0}: {1} - {2}" -f $adapter.Name, $adapter.Status, $adapter.InterfaceDescription)
        }
    } else {
        Write-Host "    Not detected"
    }

    Write-Host "  GPS/GNSS/Sensors:"
    $sensorDevices = $null
    try {
        if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
            $sensorDevices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
                $_.FriendlyName -match $gnssDevicePattern
            }
        }
    } catch { }

    if ($sensorDevices) {
        foreach ($device in $sensorDevices) {
            Write-Warning ("    PRESENT: {0}: {1} - {2}" -f $device.Class, $device.Status, $device.FriendlyName)
        }
    } else {
        Write-Host "    Not detected"
    }

    Write-Host "  Bluetooth:"
    Write-Host "    Not modified by this script by design."
}

function Ensure-RegistryPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Host "Creating registry key: $Path"
        New-Item -Path $Path -Force | Out-Null
    }
}

function Set-RegistryValueAndCheck {
    param([string]$Path, [string]$Name, [object]$Value)
    Ensure-RegistryPath -Path $Path
    try {
        $propertyType = if ($Value -is [int] -or $Value -is [long]) { 'DWORD' } else { 'String' }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $propertyType -Force | Out-Null
        $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        Write-Host ("  [{0}] {1} = {2}" -f $Path, $Name, $prop.$Name)
    } catch {
        Write-Warning "Failed setting '$Name' at '$Path': $_"
    }
}

function Check-RegistryStatus {
    param([string]$Path, [string]$Name)
    try {
        $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        Write-Host ("  [{0}] {1} = {2}" -f $Path, $Name, $prop.$Name)
    } catch {
        Write-Host ("  [{0}] {1} = Not Configured" -f $Path, $Name)
    }
}

function Check-PublicIPAndGeo {
    Write-Host "Public IP and geolocation:"
    $publicIP = $null
    try {
        $publicIP = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -ErrorAction Stop).ip
        Write-Host ("  Public IP: {0}" -f $publicIP)
    } catch {
        Write-Warning "Failed to retrieve public IP: $_"
    }

    if ($publicIP) {
        try {
            $geo = Invoke-RestMethod -Uri ("http://ip-api.com/json/{0}?fields=status,country,regionName,city,lat,lon,isp,org,as,query" -f $publicIP) -ErrorAction Stop
            Write-Host ("  Country: {0}" -f $geo.country)
            Write-Host ("  Region:  {0}" -f $geo.regionName)
            Write-Host ("  City:    {0}" -f $geo.city)
            Write-Host ("  Coords:  {0}, {1}" -f $geo.lat, $geo.lon)
            Write-Host ("  ISP:     {0}" -f $geo.isp)
            Write-Host ("  Org:     {0}" -f $geo.org)
            Write-Host ("  ASN:     {0}" -f $geo.as)

            if ($geo.country -ne "United Arab Emirates" -or $geo.city -notmatch "Dubai") {
                Write-Warning "Public IP does not geolocate to Dubai/UAE. Check router VPN routing."
            }
        } catch {
            Write-Warning "Failed to retrieve geolocation: $_"
        }
    }
}

function Show-Documentation {
    Write-Host "References (short):"
    Write-Host "  Policies key: HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
    Write-Host "  App location policy: HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy\LetAppsAccessLocation = 2"
    Write-Host "  Timeline/activity feed policies: HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    Write-Host "  Telemetry policy: HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    Write-Host "  App location consent: HKLM/HKCU ...\ConsentStore\location"
    Write-Host "  Sensor overrides: HKLM/HKCU ...\Sensor and ...\DeviceAccess\Global"
    Write-Host "  Services: lfsvc, SensorService, SensrSvc, SensorDataService, MapsBroker, DiagTrack, WlanSvc"
    Write-Host "  Hardware check: Ethernet, Wi-Fi, WWAN/LTE/eSIM, GPS/GNSS/sensors. Bluetooth is not modified."
    Write-Host "  Public IP: https://api.ipify.org"
    Write-Host "  IP Geo:    https://ip-api.com"
}

function Revert-DefaultSettings {
    Write-Host "Reverting services to defaults and re-enabling Wi-Fi"
    foreach ($svc in $services) {
        $target = $serviceDefaultStartup[$svc]; if (-not $target) { $target = 'Manual' }
        try {
            Set-Service -Name $svc -StartupType $target -ErrorAction Stop
            if ($target -in @('Automatic','Auto')) {
                try { Start-Service -Name $svc -ErrorAction Stop } catch { }
            }
            Write-Host ("  {0}: StartupType={1}" -f $svc, $target)
        } catch {
            Write-Warning "Could not adjust '$svc': $_"
        }
    }

    $wifiAdapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match $wifiAdapterPattern }
    if ($wifiAdapters) {
        foreach ($adapter in $wifiAdapters) {
            try {
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            } catch {
                Write-Warning "Could not enable adapter '$($adapter.Name)': $_"
            }
            $status = (Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue).Status
            Write-Host ("  {0}: {1}" -f $adapter.Name, $status)
        }
    }

    foreach ($entry in $registrySettings) {
        if (Test-Path $entry.Path) {
            try {
                Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction Stop
                Write-Host ("  Removed setting: [{0}] {1}" -f $entry.Path, $entry.Name)
            } catch {
                Write-Warning ("Could not remove setting [{0}] {1}: {2}" -f $entry.Path, $entry.Name, $_)
            }
        }
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "Windows 11 Geolocation Control"
    Write-Host "=============================="
    Write-Host "1) Check status (services, adapters, registry, hardware)"
    Write-Host "2) Disable services and Wi-Fi adapters only"
    Write-Host "3) Apply registry lockdown only"
    Write-Host "4) Full lockdown (services + Wi-Fi + registry + hardware check)"
    Write-Host "5) Check location-relevant hardware"
    Write-Host "6) Check public IP and geolocation"
    Write-Host "7) Documentation"
    Write-Host "8) Revert to default settings"
    Write-Host "Q) Exit"
}

# ---- Main loop ----
do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice.ToUpper()) {
        '1' {
            Write-Host "[Status] Services:"
            foreach ($svc in $services) { Check-ServiceStatus -Name $svc }
            Write-Host "[Status] Adapters:"
            Check-NetworkAdaptersStatus
            Write-Host "[Status] Hardware:"
            Check-LocationRelevantHardware
            Write-Host "[Status] Registry:"
            foreach ($entry in $registrySettings) { Check-RegistryStatus -Path $entry.Path -Name $entry.Name }
            Pause
        }
        '2' {
            Write-Host "[Action] Disabling services and Wi-Fi adapters"
            foreach ($svc in $services) { Disable-ServiceAndCheck -Name $svc }
            Disable-WiFiAdaptersAndCheck
            Pause
        }
        '3' {
            Write-Host "[Action] Applying registry lockdown"
            foreach ($entry in $registrySettings) {
                Set-RegistryValueAndCheck -Path $entry.Path -Name $entry.Name -Value $entry.Value
            }
            Pause
        }
        '4' {
            Write-Host "[Action] Full lockdown"
            foreach ($svc in $services) { Disable-ServiceAndCheck -Name $svc }
            Disable-WiFiAdaptersAndCheck
            foreach ($entry in $registrySettings) {
                Set-RegistryValueAndCheck -Path $entry.Path -Name $entry.Name -Value $entry.Value
            }
            Check-LocationRelevantHardware
            Pause
        }
        '5' {
            Check-LocationRelevantHardware
            Pause
        }
        '6' {
            Check-PublicIPAndGeo
            Pause
        }
        '7' {
            Show-Documentation
            Pause
        }
        '8' {
            Revert-DefaultSettings
            Pause
        }
        'Q' { break }
        default {
            Write-Host "Invalid selection. Choose 1-8 or Q."
            Pause
        }
    }
} while ($true)
