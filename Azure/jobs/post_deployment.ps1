$ErrorActionPreference = "SilentlyContinue"
Write-Information "Formatting any RAW data disks"
##[JOB1 - FORMAT DISKS]##
$disks = Get-Disk | where PartitionStyle -EQ "RAW" | sort number
$letters = 70..89 | ForEach-Object { [char]$_ }
$count = 0
$labels = "data1","data2","data3","data4","data5" 
foreach ($disk in $disks) {
$driveLetter = $letters[$count].ToString()
$disk | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -UseMaximumSize -DriveLetter $driveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel $labels[$count] -Confirm:$false -Force -Verbose
$count++
}
##[JOB2 - CHANGE TIMEZONE FROM UTC TO ARABIA TIME]##
Write-Information "Setting Time to Gulf Standard"
set-Itemproperty -path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\VMICTimeProvider' -Name 'Enabled' -value '0'
Stop-Service w32time
Start-Service W32Time
tzutil /s "Arabian Standard Time"
Set-TimeZone -Name "Arabian Standard Time" -Verbose
##[JOB2 - ADD ADMINS FOR REMOTE LOGIN]##
Write-Information "Adding Admins for remote access"
net localgroup Administrators /add "domain\uid", "domain\uid"