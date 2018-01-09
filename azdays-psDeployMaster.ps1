###Azure Days Powershell deployment scripts
$artifactsLocation = "https://raw.githubusercontent.com/mmcsa/AzureDays/master"
#$subscriptionId = "<subscriptionID>"
$location = "East US"
$vnetresourceGroup = "azd-vnet-rg-01"
$vmResourceGroup = "azd-vm-rg-01"
$OpsResourceGroup = "azd-ops-rg-01"

###Deploy KeyVault and add secrets###
$keyvaultName = "azd-kv-01"
$vault = New-AzureRmKeyVault -VaultName $keyvaultName -ResourceGroupName $OpsResourceGroup -Location $location -EnabledForTemplateDeployment
###Copy resource ID of KeyVault for VM template parameters
#Get admin credential from Automation account, prompt for password as secure string. 
$adminCredential = Get-AzureRmAutomationCredential -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Name AzureCredentials
$adminUsername = $adminCredential.UserName
$adminCredential = Get-Credential -UserName $adminUsername -Message "Please enter the password for the Azure Admin user for the VM"
$adminPassword = $adminCredential.Password
#store Admin credentials in Keyvault
$secret = Set-AzureKeyVaultSecret -VaultName $keyvaultName -Name 'vmAdminPassword' -SecretValue $adminPassword

###deploy OMS and Automation accounts from templates###
$omsTemplatePath = "$artifactsLocation/omsMaster-deploy.json"
$omsParameterPath = "C:\Users\mamorga\Source\Repos\AzureDays\OMS\omsMaster.parameters.json"
New-AzureRmResourceGroupDeployment -Name azdOmsDeploy -ResourceGroupName $vnetresourceGroup -TemplateFile $vnetTemplatePath -TemplateParameterFile $vnetparameterPath -Mode Incremental -Verbose
#get OMS workspace name & keys, store key in vault. 
$omsWorkspace = Get-AzureRmOperationalInsightsWorkspace -ResourceGroupName $OpsResourceGroup
$omsKeys = Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $OpsResourceGroup -Name $omsWorkspace.Name
$omsPrimaryKey = $omsKeys.PrimarySharedKey
$omsSecret = ConvertTo-SecureString $omsPrimaryKey -AsPlainText -force
$omsVault = Set-AzureKeyVaultSecret -VaultName $keyvaultName -Name 'omsKey' -SecretValue $omsSecret
    
#get Automation info for DSC
$Account = Get-AzureRmAutomationAccount -ResourceGroupName $OpsResourceGroup
$autoAccountName = $account.AutomationAccountName
$RegistrationInfo = $Account | Get-AzureRmAutomationRegistrationInfo
$registrationUrl = $RegistrationInfo.Endpoint
$registrationKey = $RegistrationInfo.PrimaryKey

###VNet deployment##
#create VNet Resource Group
New-AzureRmResourceGroup -Name $vnetResourceGroup -Location $location

#Deploy VNET from template
$vnetTemplatePath = "$artifactsLocation/simplevnet.json"
$vnetparameterPath = "C:\Users\mamorga\Source\Repos\AzureDaysDraft\AzureDays\simplevnet.parameters.json"
New-AzureRmResourceGroupDeployment -Name azdVnetDeploy -ResourceGroupName $vnetresourceGroup -TemplateFile $vnetTemplatePath -TemplateParameterFile $vnetparameterPath -Mode Incremental -Verbose

###Load Balancer Deployment###

New-AzureRmResourceGroup `
  -ResourceGroupName $VNetresourceGroup `
  -Location $location

#create Public IP for LB
$publicIP = New-AzureRmPublicIpAddress `
  -ResourceGroupName $VNetresourceGroup `
  -Location $location`
  -AllocationMethod Static `
  -Name myPublicIP

#front-end IP for LB
$frontendIP = New-AzureRmLoadBalancerFrontendIpConfig `
  -Name myFrontEndPool `
  -PublicIpAddress $publicIP

#backend pool
$backendPool = New-AzureRmLoadBalancerBackendAddressPoolConfig -Name myBackEndPool

#create Load Balancer
$lb = New-AzureRmLoadBalancer `
  -ResourceGroupName $VNetresourceGroup `
  -Name azd-lb-01 `
  -Location $location `
  -FrontendIpConfiguration $frontendIP `
  -BackendAddressPool $backendPool

#create port 80 probe
Add-AzureRmLoadBalancerProbeConfig `
  -Name myHealthProbe `
  -LoadBalancer $lb `
  -Protocol tcp `
  -Port 80 `
  -IntervalInSeconds 15 `
  -ProbeCount 2
Set-AzureRmLoadBalancer -LoadBalancer $lb
$probe = Get-AzureRmLoadBalancerProbeConfig -LoadBalancer $lb -Name myHealthProbe

#add LB rule for port 80
Add-AzureRmLoadBalancerRuleConfig `
  -Name myLoadBalancerRuleHttp `
  -LoadBalancer $lb `
  -FrontendIpConfiguration $lb.FrontendIpConfigurations[0] `
  -BackendAddressPool $lb.BackendAddressPools[0] `
  -Protocol Tcp `
  -FrontendPort 80 `
  -BackendPort 80 `
  -Probe $probe
Set-AzureRmLoadBalancer -LoadBalancer $lb

#create VMs




#add VMs to Load Balancer






