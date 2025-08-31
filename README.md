# 🔎 Offline Windows SYSTEM Hive Inspector

This PowerShell script inspects **boot-critical services and drivers** from an **offline Windows installation** by loading the SYSTEM registry hive. It helps troubleshoot issues such as **INACCESSIBLE_BOOT_DEVICE (0x7B) BSODs** by identifying boot-start services and verifying that their driver files exist on disk.  

## ⚙️ Features
- Loads the offline **SYSTEM hive** from a specified drive  
- Detects the **current ControlSet** used by Windows  
- Enumerates all **boot-start (Start=0) services**  
- Resolves each service’s **ImagePath** and verifies whether the driver file is present  
- Outputs results in a clean, tabular format  
- Automatically **unloads the hive** after inspection to avoid registry locks  

## 📌 Usage
```powershell
# Run PowerShell as Administrator
.\Check-BootCriticalDrivers.ps1 -Drive D:
```
Where ```D:``` is the drive letter of the offline Windows system.

## ✅ Example Output

```powershell
[Info] Loading SYSTEM hive from E:\Windows\System32\Config\SYSTEM as HKLM\Offline...
[Success] Successfully loaded SYSTEM hive
[Info] Retrieving current control set...
[Success] Current control set is ControlSet001
[Info] Listing boot-start (Start=0) services under ControlSet001...
[Success] Found 103 boot-start services
[Info] Resolving image paths and checking for driver file existence...

ServiceName           StartType Type ImagePath                                  ResolvedPath                                          Exists
-----------           --------- ---- ---------                                  ------------                                          ------
3ware                         0    1 System32\drivers\3ware.sys                 E:\Windows\System32\drivers\3ware.sys                 Yes
ACPI                          0    1 System32\drivers\ACPI.sys                  E:\Windows\System32\drivers\ACPI.sys                  Yes
acpiex                        0    1 System32\Drivers\acpiex.sys                E:\Windows\System32\Drivers\acpiex.sys                Yes
ADP80XX                       0    1 System32\drivers\ADP80XX.SYS               E:\Windows\System32\drivers\ADP80XX.SYS               Yes
amdsata                       0    1 System32\drivers\amdsata.sys               E:\Windows\System32\drivers\amdsata.sys               Yes
amdsbs                        0    1 System32\drivers\amdsbs.sys                E:\Windows\System32\drivers\amdsbs.sys                Yes
amdxata                       0    1 System32\drivers\amdxata.sys               E:\Windows\System32\drivers\amdxata.sys               Yes
arcsas                        0    1 System32\drivers\arcsas.sys                E:\Windows\System32\drivers\arcsas.sys                Yes
atapi                         0    1 System32\drivers\atapi.sys                 E:\Windows\System32\drivers\atapi.sys                 Yes
AWSNVMe                       0    1 System32\drivers\AWSNVMe.sys               E:\Windows\System32\drivers\AWSNVMe.sys               Yes
b06bdrv                       0    1 System32\drivers\bxvbda.sys                E:\Windows\System32\drivers\bxvbda.sys                Yes
bfadfcoei                     0    1 System32\drivers\bfadfcoei.sys             E:\Windows\System32\drivers\bfadfcoei.sys             Yes
bfadi                         0    1 System32\drivers\bfadi.sys                 E:\Windows\System32\drivers\bfadi.sys                 Yes
bttflt                        0    1 System32\drivers\bttflt.sys                E:\Windows\System32\drivers\bttflt.sys                Yes
bxfcoe                        0    1 System32\drivers\bxfcoe.sys                E:\Windows\System32\drivers\bxfcoe.sys                Yes
bxois                         0    1 System32\drivers\bxois.sys                 E:\Windows\System32\drivers\bxois.sys                 Yes
cht4iscsi                     0    1 System32\drivers\cht4sx64.sys              E:\Windows\System32\drivers\cht4sx64.sys              Yes
CLFS                          0    1 System32\drivers\CLFS.sys                  E:\Windows\System32\drivers\CLFS.sys                  Yes
CNG                           0    1 System32\Drivers\cng.sys                   E:\Windows\System32\Drivers\cng.sys                   Yes
...
[Info] Unloading SYSTEM hive...
[Success] Successfully unloaded SYSTEM hive
```

## 🔐 Requirements

- PowerShell 5.1+
- Administrator privileges
- Access to the offline Windows drive
