##<<< THIS SCRIPT IS for DOMAIN JOINING ONLY USING AZURE DOMAIN JOIN EXTENSION -
## IN CASE extsnion FAILS PLEASE USE custom_script_3.ps1 ####
##Update the vmlist.txt file.
##Change the variables before you proceed.
$kvSubscriptionID = ""
$vmSubscriptionID = ""
$kvname = ""
$secretnameDomain = ""
$DomainName = ""
$ServiceAcct = ""
$OU = "OU=,OU=,DC=,DC="

##//**CODE BLOCK [don't MODIFY !!!!]
##//**CODE BLOCK [don't MODIFY !!!!]
##//**CODE BLOCK [don't MODIFY !!!!]
##//**CODE BLOCK [don't MODIFY !!!!]
# Get service account password from key vault
Select-AzSubscription -Subscription $kvSubscriptionID
$keyVaultValue = Get-AzKeyVaultSecret -VaultName $kvname -Name $secretnameDomain
$ServiceAcctPassword = $keyVaultValue.SecretValue | ConvertFrom-SecureString -AsPlainText
$ServiceAcctPasswordSecured = ConvertTo-SecureString $ServiceAcctPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($ServiceAcct,$ServiceAcctPasswordSecured)
Select-AzSubscription -Subscription $vmSubscriptionID
# Adding vmlist to variable
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
# Join VMs to adnoc.ae Domain   
$vm1=$_.Name
Write-Host "Joining $vm1 to domain $DomainName. $(Get-Date)"
$JoinOpt = "0x00000003" # specifies the options to join a domain, 0x00000001 + 0x00000002
Set-AzVMADDomainExtension -DomainName $DomainName `
-VMName $_.Name `
-ResourceGroupName $_.ResourceGroupName `
-Location $_.Location `
-Credential $Credential `
-OUPath $OU `
-JoinOption $JoinOpt `
-Restart `
-Verbose
Write-Host "Script done at $(Get-Date)"
}
##//**CODE BLOCK [don't MODIFY !!!!]