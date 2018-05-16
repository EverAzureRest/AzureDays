##############################################
###Azure Days Powershell deployment scripts###
##############################################

#login to Azure
login-azureRmAccount
set-azureRmContext -Subscription 'az-training-01'

#setup OMS variables
####################
$artifactsLocation = "https://raw.githubusercontent.com/mmcsa/AzureDays/master"
$location = "West Europe"
$OpsResourceGroup = "azd-ops-rg-01"
$vnetresourceGroup = "azd-vnet-rg-01"


#######################################################
###deploy OMS and Automation accounts from templates###
#######################################################
New-AzureRmResourceGroup -Name $opsResourceGroup -Location $location
$omsTemplatePath = "$artifactsLocation/OMS/omsMaster-deploy.json"
$omsParameterPath = "C:\Users\mamorga\Source\Repos\AzureDays\OMS\omsMaster.parameters.json"
New-AzureRmResourceGroupDeployment `
    -Name azdOmsDeploy `
    -ResourceGroupName $opsResourceGroup `
    -TemplateFile $omsTemplatePath `
    -TemplateParameterFile $omsParameterPath `
    -Mode Incremental `
    -Verbose

#####################################
###Deploy KeyVault and add secrets###
#####################################
$keyvaultName = "azd-kv-01"
$vault = New-AzureRmKeyVault `
    -VaultName $keyvaultName `
    -ResourceGroupName $OpsResourceGroup `
    -Location $location `
    -EnabledForTemplateDeployment
#Copy resource ID of KeyVault for VM template parameters
#get OMS workspace name & keys, store key in vault. 
$omsWorkspace = Get-AzureRmOperationalInsightsWorkspace -ResourceGroupName $OpsResourceGroup
$omsKeys = Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $OpsResourceGroup -Name $omsWorkspace.Name
$omsPrimaryKey = $omsKeys.PrimarySharedKey
$omsSecret = ConvertTo-SecureString $omsPrimaryKey -AsPlainText -force
$omsVault = Set-AzureKeyVaultSecret -VaultName $keyvaultName -Name 'omsKey' -SecretValue $omsSecret

########################################################################################
###Get admin credential from Automation account, prompt for password as secure string. #
########################################################################################
$Account = Get-AzureRmAutomationAccount -ResourceGroupName $OpsResourceGroup
$autoAccountName = $account.AutomationAccountName
$adminCredential = Get-AzureRmAutomationCredential -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Name AzureCredentials
$adminUsername = $adminCredential.UserName
$adminCredential = Get-Credential -UserName $adminUsername -Message "Please enter the password for the Azure Admin user for the VM"
$adminPassword = $adminCredential.Password
#store Admin credentials in Keyvault
$secret = Set-AzureKeyVaultSecret -VaultName $keyvaultName -Name 'vmAdminPassword' -SecretValue $adminPassword

###########################################################################    
#get Automation registration info for DSC, set variables for VM deployment#
#we will be placing deployment variables in Automation account            #
###########################################################################
$RegistrationInfo = $Account | Get-AzureRmAutomationRegistrationInfo
$registrationUrl = $RegistrationInfo.Endpoint
$registrationKey = $RegistrationInfo.PrimaryKey
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $opsResourceGroup 
$storageAccountKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $OpsResourceGroup -Name $storageAccount.StorageAccountName
$storagePrimaryKey = $storageAccountKeys[0].value
$opsRgVar = New-AzureRmAutomationVariable -Encrypted $false -Name "OpsResourceGroup" -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Value $OpsresourceGroup
$vnetRgVar = New-AzureRmAutomationVariable -Encrypted $false -Name "VnetResourceGroup" -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Value $vnetresourceGroup
$artifactsVar = New-AzureRmAutomationVariable -Encrypted $false -Name "artifactsLocation" -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Value $artifactsLocation
$storageAccountNameVar = New-AzureRmAutomationVariable -Encrypted $false -Name "saname" -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Value $storageAccount.StorageAccountName
$storageAccountKeyVar = New-AzureRmAutomationVariable -Encrypted $true -Name "sakey" -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Value $storagePrimaryKey


##########################################
#copy website content from GIT to storage#
##########################################
$Context = New-AzureStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storagePrimaryKey
$container = New-AzureStorageContainer -Name "website-bits" -Context $Context
Start-AzureStorageBlobCopy -AbsoluteUri "$artifactsLocation/website.zip" -DestContainer $container.Name -DestBlob "azdays-website.zip" -DestContext $Context


#####################
###VNet deployment###
#####################

#create VNet Resource Group
New-AzureRmResourceGroup -Name $vnetResourceGroup -Location $location

#Deploy VNET from template
$vnetTemplatePath = "$artifactsLocation/simplevnet.json"
$vnetparameterPath = "C:\Users\mamorga\Source\Repos\AzureDaysDraft\AzureDays\simplevnet.parameters.json"
New-AzureRmResourceGroupDeployment `
    -Name azdVnetDeploy `
    -ResourceGroupName $vnetresourceGroup `
    -TemplateFile $vnetTemplatePath `
    -TemplateParameterFile $vnetparameterPath `
    -Mode Incremental `
    -Verbose


##############################
###Load Balancer Deployment###
##############################

#create Public IP for LB
$publicIP = New-AzureRmPublicIpAddress `
  -ResourceGroupName $VNetresourceGroup `
  -Location $location `
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
  -Name HttpProbe `
  -LoadBalancer $lb `
  -Protocol tcp `
  -Port 80 `
  -IntervalInSeconds 15 `
  -ProbeCount 2
Set-AzureRmLoadBalancer -LoadBalancer $lb
$probe = Get-AzureRmLoadBalancerProbeConfig -LoadBalancer $lb -Name HttpProbe

#add LB rule for port 80
Add-AzureRmLoadBalancerRuleConfig `
  -Name HttpRule `
  -LoadBalancer $lb `
  -FrontendIpConfiguration $lb.FrontendIpConfigurations[0] `
  -BackendAddressPool $lb.BackendAddressPools[0] `
  -Protocol Tcp `
  -FrontendPort 80 `
  -BackendPort 80 `
  -Probe $probe

Set-AzureRmLoadBalancer -LoadBalancer $lb

#configure RDP NAT Rules
$lb | Add-AzureRmLoadBalancerInboundNatRuleConfig `
    -Name RDP1 `
    -FrontendIpConfiguration $lb.FrontendIpConfigurations[0] `
    -Protocol TCP `
    -FrontendPort 3441 `
    -BackendPort 3389

$lb | Add-AzureRmLoadBalancerInboundNatRuleConfig `
-Name RDP2 `
-FrontendIpConfiguration $lb.FrontendIpConfigurations[0] `
-Protocol TCP `
-FrontendPort 3442 `
-BackendPort 3389

Set-AzureRmLoadBalancer -LoadBalancer $lb 

##########################
#create VMs              #
##########################
$vmResourceGroup = "azd-vm-rg-01"
#run azdays-VmDeploy.ps1

#############################################################
#create Azure Container Registry while VMs build            #
#we will be pushing a docker image from VMs after deployment#
#############################################################
$registry = New-AzureRmContainerRegistry -Name "azdayscontreg" -ResourceGroupName $OpsResourceGroup -Sku Basic -EnableAdminUser
$dockerCredential = Get-AzureRmContainerRegistryCredential -ResourceGroupName $OpsResourceGroup -Name $registry.Name 
$dockerCredential

$dockerSecurePass = ($dockerCredential.Password | ConvertTo-SecureString -AsPlainText -Force)
$dockerCredential = New-Object System.Management.Automation.PSCredential ($dockerCredential.Username, $dockerSecurePass)

#copy LoginServer for use in docker image tag.
#copy username & password for docker login

#check DSC Compliance
Get-AzureRmAutomationDscNode -AutomationAccountName $autoAccountName -ResourceGroupName $OpsResourceGroup

#########################################################################
#add VMs to Load Balancer with RDP NAT rules mapped across multiple VMs.# 
#########################################################################
$vms = Get-AzureRmVM -ResourceGroupName $vmResourceGroup
$lb = Get-AzureRmLoadBalancer -Name azd-lb-01 -ResourceGroupName $vnetresourceGroup
$vmCount = 0
foreach ($vm in $vms)
    {     
        $nicId = $vm.NetworkProfile.NetworkInterfaces.id
        $nicName = $nicId.split('/')[8]
        $nic = get-azureRMNetworkInterface -Name $nicName -ResourceGroupName $vmResourceGroup
        $nic.IpConfigurations[0].LoadBalancerBackendAddressPools=$lb.BackendAddressPools[$vmCount]
        $nic.IpConfigurations[0].LoadBalancerInboundNatRules=$lb.InboundNatRules[$vmCount]
        Set-AzureRmNetworkInterface -NetworkInterface $nic
        $vmCount++
    }

#####################################
#deploy docker image to ACI instance#
####################################

$aci = New-AzureRmContainerGroup `
    -ResourceGroupName $vmResourceGroup `
    -Name azd-site `
    -Image azdayscontreg.azurecr.io/iis-site:v1 `
    -OsType Windows `
    -IpAddressType Public `
    -Port 8000 `
    -RegistryCredential $dockerCredential

