.\parallel_engine.ps1
$Credential = Get-Credential
Connect-AzAccount
$newVmList = Import-Csv ".\deployment.csv"
#foreach ($_ in $newVmList){
$newVmList | Invoke-Parallel -ImportVariables -NoCloseOnTimeout -ScriptBlock{
$locName = $_.Location
$pip = $_.Pip
$SubscriptionID = $_.SubscriptionID
$DefaultNetRG = $_.RGNetCore
$NetworkName = $_.NetworkName
$subnetName = $_.Subnet
$RGname = $_.VMResourceGroup
$vmName = $_.VMName    
$vmsize = $_.VMSize
$ImageID = $_.ImageID
#$osdisksku = $_.osdisksku
#$osdisksize = $_.osdisksize
$RGDiagnosticStorage = $_.RGDiagnosticStorage
$StDiagName = $_.StDiagName
Select-AzSubscription -SubscriptionId $SubscriptionID
$ipName = $vmName+"IP"
$nicName = $vmName+"nic1"
$diskName = $vmName+"osdisk"
$hasDataDisk = $_.hasDataDisk
$datadisksku = $_.datadiskSKU
$disksize0 = $_.diskSize0
$disksize1 = $_.diskSize1
$disksize2 = $_.diskSize2
$disksize3 = $_.diskSize3
$disksize4 = $_.diskSize4
$RGStatus = Get-AzResourceGroup -Name $RGname -ErrorAction Ignore
if ($null -eq $RGStatus)
{    
"Resource group $RGname does not exist and will be created"
New-AzResourceGroup -Name $RGname -Location $locName 
$RGStatus = Get-AzResourceGroup -Name $RGname  
}
else
{
"Resource group $RGname already exists.  $vmName will be deployed to $RGname."
}
#$stDiagName = "storshduathexdiag"
#$RGDiagnosticStorage = "RG-SHD-UAT02-STORAGE"
$DiagStatus = Get-AzStorageAccount -Name $stDiagName -ResourceGroupName $RGDiagnosticStorage
if ($null -eq $DiagStatus)  
{    
"Boot Diagnostic Storage account $stDiagName does not exist and will be created"
New-AzStorageAccount -Location $locName -Name $stDiagName -ResourceGroupName $RGDiagnosticStorage -SkuName "Standard_LRS" -Kind "Storage"     
$DiagStatus = Get-AzStorageAccount -Name $stDiagName -ResourceGroupName $RGDiagnosticStorage   
}
else
{
"Boot Diagnostics Storage account $stDiagName already exists.  $vmName Boot Diag logs will be kept at $stDiagName."
}
$vm = New-AzVMConfig -VMName $vmName -VMSize $vmsize
$nicvar = "/subscriptions/$subscriptionID/resourceGroups/$RGname/providers/Microsoft.Network/networkInterfaces/$nicName"
$subnetIdvar = "/subscriptions/$subscriptionID/resourceGroups/$DefaultNetRG/providers/Microsoft.Network/virtualNetworks/$Networkname/subnets/$subnetName"
$IpConfigName1 = "IPConfig1"
$IpConfig1     = New-AzNetworkInterfaceIpConfig -Name $IpConfigName1 -SubnetId $subnetIdvar -PrivateIpAddress $pip -Primary
$nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $RGname -Location $locName -IpConfiguration $IpConfig1
# Assign Static IP on the vmNIC
#$NetworkInterface = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $RGname
#$NetworkInterface.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
#$NetworkInterface | Set-AzNetworkInterface -AsJob
$vm = Add-AzVMNetworkInterface -VM $vm -Id $nicvar
#$vm = Set-AzVMBootDiagnostic -VM $vm -Enable -ResourceGroupName $RGDiagnosticStorage -StorageAccountName $stDiagName
#Update-AzVM -VM $vm -ResourceGroupName $RGname -location $locName
#Update-AzVM -VM $vm -ResourceGroupName $RGname -location $locName
write-host "`nSet the vm, $vmName, with BootDiagnostic 'Enabled'`n" -f y
"----------------------------------------------------------------------------"
"The VM will be deployed with the following specs"
"VMname                      $vmName"
"VMsize                      $vmsize"
"VMImageID                   $ImageID"
"Location Name               $locName"
"Resource Group              $RGname"
"Subnet Name                 $subnetName"
"Subscription                $subscriptionID"
"----------------------------------------------------------------------------"
$StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch; $stopwatch.start()
write-host "`nDeploying the vm, $vmName, to $locName...`n" -f y
$vmConfig = New-AzVMConfig `
-VMName $vmName `
-VMSize $vmsize `
-LicenseType "Windows_Server" | `
Set-AzVMSourceImage -Id $ImageID | `
Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $Credential | `
Set-AzVMOSDisk -Name $diskName -CreateOption "FromImage" | `
Add-AzVMNetworkInterface -Id $nic.Id
New-AzVM `
-ResourceGroupName $RGname `
-Location $locName `
-VM $vmConfig
if(($_.hasDataDisk).Trim() -eq "TRUE") {
$diskcount = 0
$driveletter = ('1','2','3','4','5')
if(($_.diskSize0).Trim() -ne "") {$diskcount += 1}
if(($_.diskSize1).Trim() -ne "") {$diskcount += 1}
if(($_.diskSize2).Trim() -ne "") {$diskcount += 1}
if(($_.diskSize3).Trim() -ne "") {$diskcount += 1}
if(($_.diskSize4).Trim() -ne "") {$diskcount += 1}
$j=2
for($i=0; $i -lt $diskcount;$i++ ) {
$diskSizename="diskSize$i"
$diskSize=$_.$diskSizename
$diskName=$null
$diskName= $vmName + "_datadisk_"+ $driveletter[$i]
if($null -ne $diskName) {
$diskConfig = New-AzDiskConfig -Location $locName -CreateOption Empty -DiskSizeGB $diskSize -SkuName $datadisksku
$dataDisk = New-AzDisk -ResourceGroupName $RGname -DiskName $diskName -Disk $diskConfig
$vm = Get-AzVM -Name $vmName -ResourceGroupName $RGname
$vm = Add-AzVMDataDisk -VM $vm -Name $dataDisk.Name -CreateOption Attach -ManagedDiskId $dataDisk.Id -Lun $j
$j++
Update-AzVM -VM $vm -ResourceGroupName $RGname              
$diskinfo = $vm.StorageProfile.DataDisks
if($null -ne $diskinfo) {
try {
Write-Verbose -Verbose "disk $dataDisk.Name attached"
}
catch
{
Write-Verbose -Verbose "disk $diskName could not be attached. Possibly VM type is unsupported"
}
}
else {
Write-Verbose -Verbose "disk $diskName attach failed"
}
}
}
}
else {
Write-Verbose -Verbose "No disk to attach"
[string](Get-Date) + ": No disk to attach" + $_.Exception.Message | Out-File -FilePath $ErrorLogFile -Append
}
$vm = Get-AzVM -ResourceGroupName $RGName -Name $vmName
Set-AzVMBootDiagnostic -VM $vm -Enable -ResourceGroupName $RGDiagnosticStorage -StorageAccountName $stDiagName | `
Update-AzVM
write-host '[Deployment Elapsed Time]' -f y
$stopwatch.stop(); $stopwatch.elapsed
}