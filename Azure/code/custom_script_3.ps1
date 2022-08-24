##<<< THIS SCRIPT IS OPTIONAL - ONLY TO BE USED IN CASE THERE IS AN ISSUE WITH 
##AZURE DOMAIN JOIN EXTENSION USED IN custom_script_1.ps1 ####
#. ".\parallel_engine.ps1"
$vmSubscriptionID = "98152792-9287-4fb2-a062-2bad4ee71a0a"
Select-AzSubscription -Subscription $vmSubscriptionID

##//**CODE BLOCK
##//**CODE BLOCK
##//**CODE BLOCK
$vmlistFile = "D:\Shaonz_Latest_Technical-Stuff\Scripts\Powershell\Azure\Hexagon\code\vmlist.txt"
#$ScriptPathaddlocaladmin = "D:\Shaonz_Latest_Technical-Stuff\Scripts\Powershell\Azure\Hexagon\jobs\post_deployment.ps1"
$ScriptPathaddlocaladmin = "D:\Shaonz_Latest_Technical-Stuff\Scripts\Powershell\Azure\Hexagon\jobs\extend_volume.ps1"
#$ScriptPathaddlocaladmin = "E:\Scripts\Hexagon\jobs\check_domain.ps1"
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
Invoke-AzVMRunCommand -ResourceGroupName $_.ResourceGroupName `
-VMName $_.Name `
-CommandId 'RunPowerShellScript' `
-ScriptPath $ScriptPathaddlocaladmin
Write-Host "Script done at $(Get-Date)"
}