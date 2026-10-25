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
function Write-Recommendation($msg) { Write-Host "[Recommendation] $msg" -ForegroundColor Magenta }

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

# Make sure that the mount point is not in use, for example by an earlier run that could not unload the hive
if (Test-Path $mountKeyPS) {
    Write-ErrorMsg "$mountKey is already loaded. Unload it first with: reg.exe unload $mountKey"
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

    # Resolve the path on the offline drive: \??\ and \SystemRoot\ prefixes are removed, absolute paths (C:\...)
    # keep their folder on $Drive, and relative paths (System32\drivers\...) are appended to $Drive\Windows
    $cleanPath = $imagePath -replace '"', '' -replace '^\\\?\?\\', '' -replace '^\\SystemRoot\\', ''

    if ($cleanPath -match '^[a-zA-Z]:\\') {
        $resolvedPath = Join-Path -Path $Drive -ChildPath $cleanPath.Substring(3)
    } else {
        $resolvedPath = Join-Path -Path "$Drive\Windows" -ChildPath $cleanPath.TrimStart('\')
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

# Step 5a: Check DeleteFlag on all boot-start (Start=0) services, and confirm that the critical boot drivers exist with Start=0
# A boot-start service with DeleteFlag is not loaded at boot. The new checks open the registry keys with .NET and close
# each one, so that no handle keeps the hive loaded
Write-Info "Checking DeleteFlag on boot-start services and critical boot drivers..."
$offlineRoot = $mountKey -replace '^HKLM\\', ''
$criticalDrivers = @("ACPI", "DISK", "VOLMGR", "PARTMGR", "VOLSNAP", "VOLUME")
$issues = @()
$bootServices = @($criticalDrivers) + @($services | ForEach-Object { $_.ServiceName } | Where-Object { $criticalDrivers -notcontains $_ })

$deleteFlagResults = foreach ($bootService in $bootServices) {
    $isCritical = $criticalDrivers -contains $bootService
    $serviceKeyPath = "$mountKey\$controlSetKey\Services\$bootService"
    $serviceKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$offlineRoot\$controlSetKey\Services\$bootService")
    if (-Not $serviceKey) {
        if ($isCritical) {
            $issues += [PSCustomObject]@{ Check = "MissingService"; Name = $bootService; Key = $serviceKeyPath; Value = $null }
            [PSCustomObject]@{ ServiceName = $bootService; StartType = $null; DeleteFlag = $null; Status = "Service key not found" }
        }
        continue
    }

    $startType = $serviceKey.GetValue("Start")
    $deleteFlag = $serviceKey.GetValue("DeleteFlag")
    $serviceKey.Close()
    $status = @()

    if ($null -ne $deleteFlag) {
        $issues += [PSCustomObject]@{ Check = "DeleteFlag"; Name = $bootService; Key = $serviceKeyPath; Value = $deleteFlag }
        $status += "DeleteFlag is set"
    }

    if ($isCritical -and $startType -ne 0) {
        $issues += [PSCustomObject]@{ Check = "StartType"; Name = $bootService; Key = $serviceKeyPath; Value = $startType }
        $status += "Start is not 0"
    }

    # The critical boot drivers are always listed, the other boot-start services only when an issue is found
    if ($isCritical -or $status.Count -gt 0) {
        [PSCustomObject]@{
            ServiceName = $bootService
            StartType   = $startType
            DeleteFlag  = if ($null -eq $deleteFlag) { "Not present" } else { $deleteFlag }
            Status      = if ($status.Count -eq 0) { "OK" } else { $status -join ", " }
        }
    }
}

$deleteFlagResults | Format-Table ServiceName, StartType, DeleteFlag, Status -AutoSize

if (@($deleteFlagResults | Where-Object { $_.Status -ne "OK" }).Count -eq 0) {
    Write-Success "No DeleteFlag on the $($bootServices.Count) boot-start services checked, and the critical boot drivers are present with Start=0"
} else {
    Write-ErrorMsg "Boot-start services with issues found (see the table above)"
}

# Step 5b: Check ConfigFlags on storage devices (0 = enabled, 1 = disabled)
Write-Info "Checking ConfigFlags on storage devices under Enum\SCSI and Enum\STORAGE..."
$configFlagResults = foreach ($enumRoot in @("SCSI", "STORAGE")) {
    $enumKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$offlineRoot\$controlSetKey\Enum\$enumRoot")
    if (-Not $enumKey) {
        Write-WarningMsg "Enum\$enumRoot not found under $controlSetKey"
        continue
    }

    foreach ($deviceId in $enumKey.GetSubKeyNames()) {
        $deviceKey = $enumKey.OpenSubKey($deviceId)
        if (-Not $deviceKey) { continue }

        foreach ($instanceId in $deviceKey.GetSubKeyNames()) {
            $instanceKey = $deviceKey.OpenSubKey($instanceId)
            if (-Not $instanceKey) { continue }
            $configFlags = $instanceKey.GetValue("ConfigFlags")
            $deviceName = $instanceKey.GetValue("FriendlyName")
            if (-Not $deviceName) { $deviceName = $instanceKey.GetValue("DeviceDesc") }
            $instanceKey.Close()

            $deviceName = ([string]$deviceName -split ';')[-1]
            $relativeKey = "$enumRoot\$deviceId\$instanceId"

            if ($null -eq $configFlags) {
                $status = "Not present"
            } elseif (($configFlags -band 1) -eq 1) {
                $status = "Disabled"
                $issues += [PSCustomObject]@{ Check = "ConfigFlags"; Name = $deviceName; Key = "$mountKey\$controlSetKey\Enum\$relativeKey"; Value = $configFlags }
            } else {
                $status = "Enabled"
            }

            [PSCustomObject]@{
                Device      = $deviceName
                ConfigFlags = $configFlags
                Status      = $status
                Key         = $relativeKey
            }
        }
        $deviceKey.Close()
    }
    $enumKey.Close()
}

$configFlagResults | Format-Table Device, ConfigFlags, Status, Key -AutoSize

if (@($configFlagResults | Where-Object { $_.Status -eq "Disabled" }).Count -eq 0) {
    Write-Success "No disabled storage devices found"
} else {
    Write-ErrorMsg "Disabled storage devices found (see the table above)"
}

# Step 5c: Keep the boot-start driver files that were not found, for the recommendations
$missingDrivers = @($results | Where-Object { $_.Exists -eq "No" } | ForEach-Object {
    [PSCustomObject]@{ ServiceName = $_.ServiceName; ImagePath = $_.ImagePath; ExpectedPath = $_.ResolvedPath }
})

if ($missingDrivers.Count -eq 0) {
    Write-Success "No boot-start driver files are missing"
} else {
    Write-ErrorMsg "$($missingDrivers.Count) boot-start driver file(s) not found on $Drive"
}

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

# Step 7: Check the disk signature against the boot configuration (BCD) of the volume
# When a root volume is attached to a helper instance launched from the same AMI, both disks have the same signature.
# Windows keeps the attached disk offline, and assigns it a new signature when you bring it online. The BCD on the
# volume still points to the original signature, so the original instance cannot boot from the volume until it is restored.
Write-Info "Checking the disk signature against the boot configuration (BCD)..."
$signatureMismatch = $false
$expectedSignature = $null
$expectedHex = $null
$offlineDisk = $null
$volumeId = "<volume-id>"

try {
    $offlinePartition = Get-Partition -DriveLetter $Drive.TrimEnd(':') -ErrorAction Stop
    $offlineDisk = Get-Disk -Number $offlinePartition.DiskNumber -ErrorAction Stop
    # EBS volumes on Nitro instances report the volume ID as the disk serial number
    if ($offlineDisk.SerialNumber -match 'vol([0-9a-fA-F]+)') { $volumeId = "vol-$($Matches[1])" }
} catch {
    Write-WarningMsg "Could not identify the disk of $Drive : $_"
}

if ($offlineDisk -and $offlineDisk.PartitionStyle -ne "MBR") {
    Write-WarningMsg "Disk $($offlineDisk.Number) uses $($offlineDisk.PartitionStyle) partitioning. The disk signature check supports MBR disks only."
} elseif ($offlineDisk) {
    # Find the BCD store on the partitions of the same disk
    $bcdPath = $null
    foreach ($accessPath in @(Get-Partition -DiskNumber $offlineDisk.Number | ForEach-Object { $_.AccessPaths })) {
        if ($accessPath -and [System.IO.File]::Exists("$($accessPath)Boot\BCD")) {
            $bcdPath = "$($accessPath)Boot\BCD"
            break
        }
    }

    if (-Not $bcdPath) {
        Write-WarningMsg "BCD store not found on disk $($offlineDisk.Number), the disk signature was not checked"
    } else {
        $bcdRoot = "OfflineBCD"
        $bcdMountKey = "HKLM\$bcdRoot"
        reg.exe load $bcdMountKey $bcdPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-WarningMsg "Could not load the BCD store from $bcdPath, the disk signature was not checked"
        } else {
            # {bootmgr} device (element 11000001) and the osdevice (element 21000001) of the default boot entry (element 23000003)
            $bootmgrId = "{9dea862c-5cdd-4e70-acc1-f32b344d4795}"
            $bcdElements = @()
            $defaultId = $null
            $elementKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$bcdRoot\Objects\$bootmgrId\Elements\11000001")
            if ($elementKey) { $bcdElements += , $elementKey.GetValue("Element"); $elementKey.Close() }
            $elementKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$bcdRoot\Objects\$bootmgrId\Elements\23000003")
            if ($elementKey) { $defaultId = $elementKey.GetValue("Element"); $elementKey.Close() }
            if ($defaultId) {
                $elementKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$bcdRoot\Objects\$defaultId\Elements\21000001")
                if ($elementKey) { $bcdElements += , $elementKey.GetValue("Element"); $elementKey.Close() }
            }
            $elementKey = $null
            reg.exe unload $bcdMountKey | Out-Null

            $bcdSignatures = @()
            foreach ($element in $bcdElements) {
                # Partition device on an MBR disk: device type 6 at 0x10, partition style 1 at 0x34, disk signature at 0x38
                if ($element -and $element.Length -ge 0x3C -and [BitConverter]::ToUInt32($element, 0x10) -eq 6 -and [BitConverter]::ToUInt32($element, 0x34) -eq 1) {
                    $bcdSignatures += [BitConverter]::ToUInt32($element, 0x38)
                }
            }

            $bcdSignatures = @($bcdSignatures | Select-Object -Unique)
            $currentHex = '{0:X8}' -f $offlineDisk.Signature
            if ($bcdSignatures.Count -eq 0) {
                Write-WarningMsg "No MBR disk signature found in the BCD store at $bcdPath"
            } else {
                $expectedSignature = $bcdSignatures[0]
                $expectedHex = '{0:X8}' -f $expectedSignature
                if ($bcdSignatures.Count -gt 1) {
                    Write-WarningMsg "The BCD entries point to different disk signatures: $(($bcdSignatures | ForEach-Object { '{0:X8}' -f $_ }) -join ', ')"
                }

                if ($offlineDisk.Signature -eq $expectedSignature) {
                    Write-Success "Disk signature $currentHex of disk $($offlineDisk.Number) matches its BCD"
                } else {
                    $signatureMismatch = $true
                    Write-ErrorMsg "Disk signature mismatch: disk $($offlineDisk.Number) has signature $currentHex, but its BCD expects $expectedHex. The original instance cannot boot from this volume until the signature is restored."
                }

                $sameSignature = @(Get-Disk | Where-Object { $_.Number -ne $offlineDisk.Number -and $_.Signature -eq $expectedSignature })
                if ($sameSignature.Count -gt 0) {
                    Write-WarningMsg "Disk $($sameSignature[0].Number) of this instance also uses signature $expectedHex (disk signature collision). Once the signature is restored, the attached disk must stay offline until you detach it."
                }
            }
        }
    }
}

# Step 8: Restore the disk signature expected by the BCD, and take the disk offline
$signatureRestored = $false
$diskTakenOffline = $false
if ($signatureMismatch) {
    # The disk can only be changed when no registry hive from it is still loaded
    $loadedHives = @($offlineRoot, $bcdRoot | Where-Object {
        $hiveKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($_)
        if ($hiveKey) { $hiveKey.Close(); $true } else { $false }
    })
    foreach ($hive in $loadedHives) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        reg.exe unload "HKLM\$hive" 2>&1 | Out-Null
    }
    $loadedHives = @($offlineRoot, $bcdRoot | Where-Object {
        $hiveKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($_)
        if ($hiveKey) { $hiveKey.Close(); $true } else { $false }
    })

    if ($loadedHives.Count -gt 0) {
        Write-ErrorMsg "HKLM\$($loadedHives[0]) is still loaded, so the disk signature was not restored. Close all PowerShell and Registry Editor windows, run: reg.exe unload HKLM\$($loadedHives[0]), and run this script again."
    } else {
        Write-Info "Restoring disk signature $expectedHex on disk $($offlineDisk.Number), so that the original instance can boot from this volume..."
        try {
            Set-Disk -Number $offlineDisk.Number -Signature $expectedSignature -ErrorAction Stop
            Update-HostStorageCache
            Start-Sleep -Seconds 3
            $finalDisk = Get-Disk -Number $offlineDisk.Number

            if ($finalDisk.Signature -eq $expectedSignature) {
                $signatureRestored = $true
                Write-Success "Disk signature of disk $($finalDisk.Number) restored to $expectedHex"
            } else {
                Write-ErrorMsg "Disk $($finalDisk.Number) has signature $('{0:X8}' -f $finalDisk.Signature) after the change, expected $expectedHex"
            }

            # With a signature collision, Windows takes the disk offline by itself
            if (-Not $finalDisk.IsOffline) {
                Set-Disk -Number $finalDisk.Number -IsOffline $true -ErrorAction Stop
                $finalDisk = Get-Disk -Number $finalDisk.Number
            }

            if ($finalDisk.IsOffline) {
                $diskTakenOffline = $true
                Write-Success "Disk $($finalDisk.Number) is offline"
            } else {
                Write-ErrorMsg "Disk $($finalDisk.Number) is still online. Take it offline in Disk Management before you detach the volume."
            }

            if (@(Get-Disk | Where-Object { $_.Number -ne $finalDisk.Number -and $_.Signature -eq $finalDisk.Signature }).Count -gt 0) {
                Write-WarningMsg "Disk $($finalDisk.Number) has the same signature as a disk of this instance. Detach the volume before you restart this instance, so that it does not boot from the wrong volume."
            }
        } catch {
            Write-ErrorMsg "Failed to restore the disk signature: $_"
        }
    }
}

# Step 9: Recommendations
$openIssues = $issues.Count + $missingDrivers.Count + [int]($signatureMismatch -and -Not $signatureRestored)
if ($openIssues -eq 0) {
    if ($signatureRestored) {
        Write-Success "No other issues found. Detach the volume, attach it back to the original instance as the root volume (for example, /dev/sda1), and start the instance."
    } else {
        Write-Success "No issues found"
    }
} else {
    Write-WarningMsg "$openIssues issue(s) found. Recommended actions:"
    $step = 1

    # Region of this instance for the snapshot command (read-only metadata lookup; left out if it fails)
    $region = $null
    try {
        $imdsToken = Invoke-RestMethod -Method Put -Uri "http://169.254.169.254/latest/api/token" -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "60" } -TimeoutSec 3
        $region = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/placement/region" -Headers @{ "X-aws-ec2-metadata-token" = $imdsToken } -TimeoutSec 3
    } catch {
        $region = $null
    }

    Write-Recommendation "$step. Before you make any of the changes below, create a snapshot of the affected root volume ($volumeId), so that you can roll back if needed. In the EC2 console, choose Volumes, select the volume, and choose Actions, Create snapshot. Or run this command from a computer or role with the ec2:CreateSnapshot permission:"
    Write-Host "    aws ec2 create-snapshot$(if ($region) { " --region $region" }) --volume-id $volumeId --description `"Before INACCESSIBLE_BOOT_DEVICE fix`""
    $step++

    if ($diskTakenOffline -and ($issues.Count + $missingDrivers.Count -gt 0)) {
        Write-Recommendation "$step. The disk was taken offline after its signature was restored. To apply the fixes below, bring it online again and use its drive letter in the commands (it can change). Windows can assign a new signature again, so run this script again when you finish:"
        Write-Host "    Set-Disk -Number $($offlineDisk.Number) -IsOffline `$false"
        $step++
    }

    if ($issues.Count -gt 0) {
        Write-Recommendation "$step. Load the SYSTEM hive again and back up each registry key before you change it:"
        Write-Host "    reg.exe load $mountKey $systemHivePath"
        Write-Host "    New-Item -ItemType Directory -Path C:\RegBackup -Force | Out-Null"
        $backupNumber = 1
        foreach ($key in @($issues | Where-Object { $_.Check -ne "MissingService" } | Select-Object -ExpandProperty Key -Unique)) {
            Write-Host "    reg.exe export `"$key`" `"C:\RegBackup\$backupNumber-$(Split-Path $key -Leaf).reg`" /y"
            $backupNumber++
        }
        $step++

        Write-Recommendation "$step. Fix the registry issues, then unload the hive:"
        foreach ($issue in $issues) {
            switch ($issue.Check) {
                "DeleteFlag" {
                    Write-Host "    # $($issue.Name): remove DeleteFlag (current value $($issue.Value)), so that Windows loads the driver at boot"
                    Write-Host "    reg.exe delete `"$($issue.Key)`" /v DeleteFlag /f"
                }
                "StartType" {
                    Write-Host "    # $($issue.Name): set Start to 0 (current value $($issue.Value)), so that the driver loads at boot"
                    Write-Host "    reg.exe add `"$($issue.Key)`" /v Start /t REG_DWORD /d 0 /f"
                }
                "ConfigFlags" {
                    Write-Host "    # $($issue.Name): enable the device (ConfigFlags $($issue.Value) -> $($issue.Value -band (-bnot 1)))"
                    Write-Host "    reg.exe add `"$($issue.Key)`" /v ConfigFlags /t REG_DWORD /d $($issue.Value -band (-bnot 1)) /f"
                }
                "MissingService" {
                    Write-Host "    # $($issue.Name): the service key is missing. Export HKLM\SYSTEM\CurrentControlSet\Services\$($issue.Name) from a working instance"
                    Write-Host "    # with the same Windows Server version, replace HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet with HKEY_LOCAL_MACHINE\Offline\$controlSetKey"
                    Write-Host "    # in the .reg file, and import it with reg.exe import"
                }
            }
        }
        Write-Host "    reg.exe unload $mountKey"
        Write-Host "    # To roll back a change, load the hive again as $mountKey and run: reg.exe import C:\RegBackup\<file>.reg"
        $step++

        if (@($issues | Where-Object { $_.Check -eq "ConfigFlags" }).Count -gt 0) {
            Write-Recommendation "$step. If a security or DLP agent disabled the storage devices, review its device control policy, so that it does not disable the EBS volumes again."
            $step++
        }
    }

    if ($missingDrivers.Count -gt 0) {
        Write-Recommendation "$step. Restore the missing driver files from a working instance with the same Windows Server and driver versions, or from an earlier snapshot of this volume. If a file belongs to third-party software, such as a security agent, work with its vendor. Do not disable a driver that is still listed in an UpperFilters or LowerFilters value, because that also causes INACCESSIBLE_BOOT_DEVICE:"
        foreach ($missingDriver in $missingDrivers) {
            Write-Host "    $($missingDriver.ServiceName): $($missingDriver.ExpectedPath)"
        }
        $step++
    }

    if ($signatureMismatch -and -Not $signatureRestored) {
        Write-Recommendation "$step. Restore the disk signature expected by the BCD ($expectedHex) manually with diskpart, then take the disk offline:"
        Write-Host "    diskpart"
        Write-Host "    select disk $($offlineDisk.Number)"
        Write-Host "    uniqueid disk id=$expectedHex"
        Write-Host "    offline disk"
        $step++
    }

    if ($issues.Count + $missingDrivers.Count -gt 0) {
        Write-Recommendation "$step. Run this script again to confirm the fixes. It also restores the disk signature if Windows changed it again."
        $step++
    }

    Write-Recommendation "$step. Take the disk offline, detach the volume, attach it back to the original instance as the root volume (for example, /dev/sda1), and start the instance."
}
