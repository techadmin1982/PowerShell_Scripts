.\parallel_engine.ps1
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
foreach($_ in $vmrunninglist)
{
$vmrunninglist | Invoke-Parallel -ImportVariables -NoCloseOnTimeout -ScriptBlock{
Start-AzVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName
Write-Host "Script done at $(Get-Date)"
}
}