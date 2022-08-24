$pw = "" | ConvertTo-SecureString -asPlainText –Force
$usr = ""
$creds = New-Object System.Management.Automation.PSCredential($usr,$pw)
Add-Computer -DomainName "" -OUPath "OU=,OU=,DC=,DC=" -Credential $creds -Restart