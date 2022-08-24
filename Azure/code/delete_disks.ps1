.\parallel_engine.ps1
connect-azaccount
$vmSubscriptionID = ""
Select-AzSubscription -Subscription $vmSubscriptionID
$disklistFile = ".\disks.txt"
###########CODE##########################################
#CODE####################################################
##########CODE###########################################
($rmdisks=Get-AzDisk) > 0
$diskrunninglist = @()
$disklist = Get-Content $disklistFile
ForEach($disk in $disklist)   
{
foreach($diskobj in $rmdisks)
{
if($diskobj.name -eq $disk)
{
$diskrunninglist = $diskrunninglist + $diskobj
}
}
}
$diskrunninglist | Invoke-Parallel -ImportVariables -NoCloseOnTimeout -ScriptBlock{
$disk = Get-AzDisk -ResourceGroupName $_.ResourceGroupName -DiskName $_.Name
Remove-AzDisk -ResourceGroupName $disk.ResourceGroupName -DiskName $disk.Name -Force
}
Write-Host "Script done at $(Get-Date)"