$rgName = ''
$vmName = ''
$diskName = ''
$newsize = 1024
$vmSubscriptionID = ""
###########CODE##########################################
#CODE####################################################
##########CODE###########################################
Connect-AzAccount
Select-AzSubscription -Subscription $vmSubscriptionID
$vm = Get-AzVM -ResourceGroupName $rgName -Name $vmName
Stop-AzVM -ResourceGroupName $rgName -Name $vmName -force
$disk= Get-AzDisk -ResourceGroupName $rgName -DiskName $diskName
$disk.DiskSizeGB = $newsize
Update-AzDisk -ResourceGroupName $rgName -Disk $disk -DiskName $disk.Name
Start-AzVM -ResourceGroupName $rgName -Name $vmName