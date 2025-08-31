param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[a-zA-Z]:$')]
    [string]$Drive
)

# Example usage: .\Check-BootCriticalDrivers.ps1 -Drive D:


# Run as Administrator

function Write-Info($msg) { Write-Host "[Info] $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[Success] $msg" -ForegroundColor Green }
function Write-WarningMsg($msg) { Write-Host "[Warning] $msg" -ForegroundColor Yellow }
function Write-ErrorMsg($msg) { Write-Host "[Error] $msg" -ForegroundColor Red }

# Step 1: Prompt for drive letter
# Write-Info "Prompting for offline system drive letter..."
# $Drive = Read-Host "Enter the drive letter of the offline system (e.g. D:)"

# Step 2: Load SYSTEM hive
$systemHivePath = "$Drive\Windows\System32\Config\SYSTEM"
$mountKey = "HKLM\Offline"
$mountKeyPS = "Registry::$mountKey"

Write-Info "Loading SYSTEM hive from $systemHivePath as $mountKey..."
if (-Not (Test-Path $systemHivePath)) {
    Write-ErrorMsg "SYSTEM hive not found at $systemHivePath"
    exit 1
}

try {
    reg.exe load $mountKey $systemHivePath | Out-Null
    Write-Success "Successfully loaded SYSTEM hive"
} catch {
    Write-ErrorMsg "Failed to load SYSTEM hive: $_"
    exit 1
}

# Step 3: Determine current ControlSet
Write-Info "Retrieving current control set..."
try {
    $current = Get-ItemProperty -Path "$mountKeyPS\Select" -Name "Current" | Select-Object -ExpandProperty Current
    $controlSetKey = "ControlSet{0:D3}" -f $current
    Write-Success "Current control set is $controlSetKey"
} catch {
    Write-ErrorMsg "Failed to retrieve current control set: $_"
    reg.exe unload $mountKey | Out-Null
    exit 1
}

# Step 4: Find services with Start=0
Write-Info "Listing boot-start (Start=0) services under $controlSetKey..."
$servicesPath = "$mountKeyPS\$controlSetKey\Services"
$services = @()

try {
    $services = Get-ChildItem -Path $servicesPath | ForEach-Object {
        $serviceName = $_.PSChildName
        $props = Get-ItemProperty -Path $_.PSPath
        if ($props.Start -eq 0) {
            [PSCustomObject]@{
                ServiceName = $serviceName
                StartType   = $props.Start
                Type        = $props.Type
                ImagePath   = $props.ImagePath
            }
        }
    } | Where-Object { $_ -ne $null }

    if ($services.Count -eq 0) {
        Write-WarningMsg "No services found with Start = 0"
    } else {
        Write-Success "Found $($services.Count) boot-start services"
    }
} catch {
    Write-ErrorMsg "Failed to enumerate services: $_"
}

# Step 5: Resolve ImagePaths and check file existence
Write-Info "Resolving image paths and checking for driver file existence..."
$results = foreach ($service in $services) {
    if ([string]::IsNullOrEmpty($service.ImagePath)) {
        continue  # Skip this service, no ImagePath
    }

    $imagePath = $service.ImagePath

    $cleanPath = $imagePath -replace '"', '' -replace '\\SystemRoot', '\Windows'

    if ($cleanPath -notmatch '^[a-zA-Z]:\\') {
        $resolvedPath = Join-Path -Path "$Drive\Windows" -ChildPath $cleanPath.TrimStart('\')
    } else {
        $resolvedPath = $cleanPath
    }

    $exists = if (Test-Path $resolvedPath) { "Yes" } else { "No" }

    [PSCustomObject]@{
        ServiceName  = $service.ServiceName
        StartType    = $service.StartType
        Type         = $service.Type
        ImagePath    = $service.ImagePath
        ResolvedPath = $resolvedPath
        Exists       = $exists
    }
}

# Output results
# $results | Out-GridView -Title "Boot-start Services and Driver File Check"
$results | Format-Table ServiceName, StartType, Type, ImagePath, ResolvedPath, Exists -AutoSize

# Step 6: Clean up and unload hive
Write-Info "Unloading SYSTEM hive..."

# Release variables holding registry references
$services = $null
$results = $null
$props = $null

# Run garbage collection to ensure no lingering handlesn
[GC]::Collect()
[GC]::WaitForPendingFinalizers()

Start-Sleep -Milliseconds 5000  # Give time for cleanup

try {
    reg.exe unload $mountKey | Out-Null
    Write-Success "Successfully unloaded SYSTEM hive"
} catch {
    Write-WarningMsg "Failed to unload hive: $_ make sure PowerShell isn't locking the handle, close all PowerShell windows and try to unload the hive manually using regedit."
}
