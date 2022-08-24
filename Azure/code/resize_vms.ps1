.\parallel_engine.ps1"
connect-azaccount
$vmSubscriptionID = ""
Select-AzSubscription -Subscription $vmSubscriptionID
$vmlistFile = ".\vmlist.txt"
($rmvms=Get-AzVM) > 0
$vmrunninglist = @()
$vmlist = Get-Content $vmlistFile
ForEach($VM in $vmlist)   
{
foreach($vmobj in $rmvms)
{
if($vmobj.name -eq $VM)
{
$vmrunninglist = $vmrunninglist + $vmobj
}
}
}
$vmrunninglist | Invoke-Parallel -ImportVariables -NoCloseOnTimeout -ScriptBlock{
$vm = Get-AzVM -ResourceGroupName $_.ResourceGroupName -VMName $_.Name
$vm.HardwareProfile.VmSize = "Standard_E4s_v3"
Update-AzVM -VM $vm -ResourceGroupName $_.ResourceGroupName
Write-Host $vm.name
}
Write-Host "Script done at $(Get-Date)"