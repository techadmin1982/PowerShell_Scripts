$vmSubscriptionID = ""
Select-AzSubscription -Subscription $vmSubscriptionID
##//**CODE BLOCK
##//**CODE BLOCK
##//**CODE BLOCK
$Script= "..\jobs\post_deployment.ps1"
$vmlistFile = ".\vmlist.txt"
# Code Block to iterate VMlist in an empty array
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
$vmrunninglist
Write-Host "Running Post Deployment Tasks on VM: $_.name . $(Get-Date)"
Invoke-AzVMRunCommand -ResourceGroupName $_.ResourceGroupName `
-VMName $_.Name `
-CommandId 'RunPowerShellScript' `
-ScriptPath $Script
Write-Host "Script done at $(Get-Date)"
}