# 🔎 Offline Windows SYSTEM Hive Inspector

This PowerShell script inspects **boot-critical services and drivers** from an **offline Windows installation** by loading the SYSTEM registry hive. It helps troubleshoot issues such as **INACCESSIBLE_BOOT_DEVICE (0x7B) BSODs** by identifying boot-start services, verifying that their driver files exist on disk, and checking the registry flags that commonly prevent Windows from booting (**DeleteFlag** and **ConfigFlags**). It also detects and fixes a **disk signature collision** caused by attaching the root volume to a helper instance, and prints **recommendations with the exact fix commands** for every issue found.

## ⚙️ Features
- Loads the offline **SYSTEM hive** from a specified drive, and stops if `HKLM\Offline` is still loaded from an earlier run  
- Detects the **current ControlSet** used by Windows  
- Enumerates all **boot-start (Start=0) services**  
- Resolves each service’s **ImagePath** on the offline drive (relative, `\SystemRoot\`, `\??\C:\` and `C:\` paths) and verifies whether the driver file is present  
- Checks every boot-start service for **DeleteFlag**, and confirms that the critical boot drivers (`ACPI`, `DISK`, `VOLMGR`, `PARTMGR`, `VOLSNAP`, `VOLUME`) exist with `Start=0`  
- Checks **ConfigFlags** on the storage devices under `Enum\SCSI` and `Enum\STORAGE` (`0` = enabled, `1` = disabled)  
- Outputs results in a clean, tabular format  
- Automatically **unloads the hive** after inspection to avoid registry locks  
- Compares the **disk signature** with the boot configuration (**BCD**) of the volume, and when they don't match (disk signature collision), restores the original signature and takes the disk offline  
- Prints **recommendations** for each issue found: snapshot of the volume, registry backup (`reg.exe export`), the exact fix commands, rollback, and the next steps  

## 📌 Usage
```powershell
# Run PowerShell as Administrator
.\Check-BootCriticalDrivers.ps1 -Drive D:
```
Where ```D:``` is the drive letter of the offline Windows system.

## 🧭 Typical Workflow
1. Stop the affected instance and attach its root volume to a helper instance as a secondary volume.
2. Bring the disk online on the helper instance (Disk Management), and note its drive letter.
3. Run the script, and review the results and the recommendations.
4. If issues were found, create a snapshot of the volume first, then bring the disk online again and apply the recommended fixes.
5. Run the script again to confirm the fixes. It also restores the disk signature if Windows changed it again.
6. Detach the volume, attach it back to the original instance as the root volume (for example, `/dev/sda1`), and start the instance.

## ✅ Example Output

From a test volume with simulated issues (a missing boot-start driver, `DeleteFlag` on two drivers, a critical driver with `Start=4`, disabled storage devices, and a disk signature collision):

```powershell
[Info] Loading SYSTEM hive from F:\Windows\System32\Config\SYSTEM as HKLM\Offline...
[Success] Successfully loaded SYSTEM hive
[Info] Retrieving current control set...
[Success] Current control set is ControlSet001
[Info] Listing boot-start (Start=0) services under ControlSet001...
[Success] Found 109 boot-start services
[Info] Resolving image paths and checking for driver file existence...

ServiceName           StartType Type ImagePath                                                                  ResolvedPath                                                                          Exists
-----------           --------- ---- ---------                                                                  ------------                                                                          ------
3ware                         0    1 System32\drivers\3ware.sys                                                 F:\Windows\System32\drivers\3ware.sys                                                 Yes
ACPI                          0    1 System32\drivers\ACPI.sys                                                  F:\Windows\System32\drivers\ACPI.sys                                                  Yes
acpiex                        0    1 System32\Drivers\acpiex.sys                                                F:\Windows\System32\Drivers\acpiex.sys                                                Yes
ADP80XX                       0    1 System32\drivers\ADP80XX.SYS                                               F:\Windows\System32\drivers\ADP80XX.SYS                                               Yes
amdsata                       0    1 System32\drivers\amdsata.sys                                               F:\Windows\System32\drivers\amdsata.sys                                               Yes
...
AWSNVMe                       0    1 System32\drivers\AWSNVMe.sys                                               F:\Windows\System32\drivers\AWSNVMe.sys                                               Yes
...
CNG                           0    1 System32\Drivers\cng.sys                                                   F:\Windows\System32\Drivers\cng.sys                                                   Yes
disk                          0    1 System32\drivers\disk.sys                                                  F:\Windows\System32\drivers\disk.sys                                                  Yes
...
ExampleBootDriver             0    1 System32\drivers\ExampleBootDriver.sys                                     F:\Windows\System32\drivers\ExampleBootDriver.sys                                     No
...

[Info] Checking DeleteFlag on boot-start services and critical boot drivers...

ServiceName StartType DeleteFlag  Status
----------- --------- ----------  ------
ACPI                0 Not present OK
DISK                0 Not present OK
VOLMGR              0 Not present OK
PARTMGR             0 1           DeleteFlag is set
VOLSNAP             4 Not present Start is not 0
VOLUME              0 Not present OK
bttflt              0 1           DeleteFlag is set

[Error] Boot-start services with issues found (see the table above)
[Info] Checking ConfigFlags on storage devices under Enum\SCSI and Enum\STORAGE...

Device                                 ConfigFlags Status   Key
------                                 ----------- ------   ---
Microsoft Virtual DVD-ROM                        0 Enabled  SCSI\CdRom&Ven_Msft&Prod_Virtual_DVD-ROM\2&1f4adffe&0&000001
AWS PVDISK SCSI Disk Device                      0 Enabled  SCSI\Disk&Ven_AWS&Prod_PVDISK\5&445a993&0&000000
AWS PVDISK SCSI Disk Device                      0 Enabled  SCSI\Disk&Ven_AWS&Prod_PVDISK\5&445a993&0&004e00
AWS PVDISK SCSI Disk Device                      0 Enabled  SCSI\Disk&Ven_AWS&Prod_PVDISK\5&445a993&0&004f00
NVMe Amazon Elastic B SCSI Disk Device           0 Enabled  SCSI\Disk&Ven_NVMe&Prod_Amazon_Elastic_B\4&16825f14&0&000000
NVMe Amazon Elastic B SCSI Disk Device           1 Disabled SCSI\Disk&Ven_NVMe&Prod_Amazon_Elastic_B\4&3744fc08&0&000000
NVMe Amazon Elastic B SCSI Disk Device           0 Enabled  SCSI\Disk&Ven_NVMe&Prod_Amazon_Elastic_B\4&8159206&0&000000
Volume                                           1 Disabled STORAGE\Volume\{5c822eb3-c52e-11ee-ba66-806e6f6e6963}#0000000000100000
Volume                                           0 Enabled  STORAGE\Volume\{5c822eb3-c52e-11ee-ba66-806e6f6e6963}#00000018C7A00000

[Error] Disabled storage devices found (see the table above)
[Error] 1 boot-start driver file(s) not found on F:
[Info] Unloading SYSTEM hive...
[Success] Successfully unloaded SYSTEM hive
[Info] Checking the disk signature against the boot configuration (BCD)...
[Error] Disk signature mismatch: disk 3 has signature 0B1CF833, but its BCD expects 4C6DA7A9. The original instance cannot boot from this volume until the signature is restored.
[Warning] Disk 0 of this instance also uses signature 4C6DA7A9 (disk signature collision). Once the signature is restored, the attached disk must stay offline until you detach it.
[Info] Restoring disk signature 4C6DA7A9 on disk 3, so that the original instance can boot from this volume...
[Success] Disk signature of disk 3 restored to 4C6DA7A9
[Success] Disk 3 is offline
[Warning] Disk 3 has the same signature as a disk of this instance. Detach the volume before you restart this instance, so that it does not boot from the wrong volume.
[Warning] 6 issue(s) found. Recommended actions:
[Recommendation] 1. Before you make any of the changes below, create a snapshot of the affected root volume (vol-0123456789abcdef0), so that you can roll back if needed. In the EC2 console, choose Volumes, select the volume, and choose Actions, Create snapshot. Or run this command from a computer
or role with the ec2:CreateSnapshot permission:
    aws ec2 create-snapshot --region eu-west-1 --volume-id vol-0123456789abcdef0 --description "Before INACCESSIBLE_BOOT_DEVICE fix"
[Recommendation] 2. The disk was taken offline after its signature was restored. To apply the fixes below, bring it online again and use its drive letter in the commands (it can change). Windows can assign a new signature again, so run this script again when you finish:
    Set-Disk -Number 3 -IsOffline $false
[Recommendation] 3. Load the SYSTEM hive again and back up each registry key before you change it:
    reg.exe load HKLM\Offline F:\Windows\System32\Config\SYSTEM
    New-Item -ItemType Directory -Path C:\RegBackup -Force | Out-Null
    reg.exe export "HKLM\Offline\ControlSet001\Services\PARTMGR" "C:\RegBackup\1-PARTMGR.reg" /y
    reg.exe export "HKLM\Offline\ControlSet001\Services\VOLSNAP" "C:\RegBackup\2-VOLSNAP.reg" /y
    reg.exe export "HKLM\Offline\ControlSet001\Services\bttflt" "C:\RegBackup\3-bttflt.reg" /y
    reg.exe export "HKLM\Offline\ControlSet001\Enum\SCSI\Disk&Ven_NVMe&Prod_Amazon_Elastic_B\4&3744fc08&0&000000" "C:\RegBackup\4-4&3744fc08&0&000000.reg" /y
    reg.exe export "HKLM\Offline\ControlSet001\Enum\STORAGE\Volume\{5c822eb3-c52e-11ee-ba66-806e6f6e6963}#0000000000100000" "C:\RegBackup\5-{5c822eb3-c52e-11ee-ba66-806e6f6e6963}#0000000000100000.reg" /y
[Recommendation] 4. Fix the registry issues, then unload the hive:
    # PARTMGR: remove DeleteFlag (current value 1), so that Windows loads the driver at boot
    reg.exe delete "HKLM\Offline\ControlSet001\Services\PARTMGR" /v DeleteFlag /f
    # VOLSNAP: set Start to 0 (current value 4), so that the driver loads at boot
    reg.exe add "HKLM\Offline\ControlSet001\Services\VOLSNAP" /v Start /t REG_DWORD /d 0 /f
    # bttflt: remove DeleteFlag (current value 1), so that Windows loads the driver at boot
    reg.exe delete "HKLM\Offline\ControlSet001\Services\bttflt" /v DeleteFlag /f
    # NVMe Amazon Elastic B SCSI Disk Device: enable the device (ConfigFlags 1 -> 0)
    reg.exe add "HKLM\Offline\ControlSet001\Enum\SCSI\Disk&Ven_NVMe&Prod_Amazon_Elastic_B\4&3744fc08&0&000000" /v ConfigFlags /t REG_DWORD /d 0 /f
    # Volume: enable the device (ConfigFlags 1 -> 0)
    reg.exe add "HKLM\Offline\ControlSet001\Enum\STORAGE\Volume\{5c822eb3-c52e-11ee-ba66-806e6f6e6963}#0000000000100000" /v ConfigFlags /t REG_DWORD /d 0 /f
    reg.exe unload HKLM\Offline
    # To roll back a change, load the hive again as HKLM\Offline and run: reg.exe import C:\RegBackup\<file>.reg
[Recommendation] 5. If a security or DLP agent disabled the storage devices, review its device control policy, so that it does not disable the EBS volumes again.
[Recommendation] 6. Restore the missing driver files from a working instance with the same Windows Server and driver versions, or from an earlier snapshot of this volume. If a file belongs to third-party software, such as a security agent, work with its vendor. Do not disable a driver that is still
listed in an UpperFilters or LowerFilters value, because that also causes INACCESSIBLE_BOOT_DEVICE:
    ExampleBootDriver: F:\Windows\System32\drivers\ExampleBootDriver.sys
[Recommendation] 7. Run this script again to confirm the fixes. It also restores the disk signature if Windows changed it again.
[Recommendation] 8. Take the disk offline, detach the volume, attach it back to the original instance as the root volume (for example, /dev/sda1), and start the instance.
```

## ⚠️ Notes
- The script doesn't change anything on the volume, with one exception: when the disk signature doesn't match the BCD, it restores the original signature and takes the disk offline, so that the original instance can boot from it.
- After the signature is restored, **detach the volume before you restart the helper instance**, because both disks can share the same signature and the helper could boot from the wrong volume.
- The script **never creates AWS resources**. It recommends creating a snapshot, with the EC2 console steps and the AWS CLI command, and leaves that decision to the owner of the instance.
- The disk signature check supports **MBR** disks, which most EC2 Windows AMIs use. On GPT disks it shows a warning and skips the check.

## 🔐 Requirements

- PowerShell 5.1+
- Administrator privileges
- Access to the offline Windows drive
- The Storage module (`Get-Disk`, `Set-Disk`), included in Windows Server 2012 R2 and later
- No AWS credentials are needed. Access to the instance metadata is optional, and only adds the Region to the snapshot command that the script recommends.
