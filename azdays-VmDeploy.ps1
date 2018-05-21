#create multiple VMs from ARM Template with provided parameters. 
#DSC and OMS extensions configured with DSC node config as selected. 
Param
(
    # name of VM resource group
    [Parameter(Mandatory=$true, HelpMessage="Name of Resource Group for VMs")]
    [string]$vmResourceGroup,

    # name of Resource Group with Automation account deployed
    [Parameter(Mandatory=$true, HelpMessage="Name of Resource Group for automation acccount")]
    [string]$opsResourceGroup,
    
    # prefix for VM names
    [Parameter(Mandatory=$true, HelpMessage="prefix for VM names")]
    [string]$vmNamePrefix,

    # availability set name
    [Parameter(Mandatory=$true, HelpMessage="name for Availability set for VMs")]
    [string]$availabilitySetName,

    # VM Size
    [Parameter(Mandatory=$True, HelpMessage="Enter the Vm Size.")]
    [ValidateSet("Standard_D2_v3")]
    [String]$VmSize,

    # number of VMs to deploy
    [Parameter(Mandatory=$true, HelpMessage="number of identical VMs to deploy")]
    [int]$numberOfInstances,
    
    # DSC Node config to use
    [Parameter(Mandatory=$true, HelpMessage="DSC configuration to apply")]
    [ValidateSet("Web")]
    [string]$nodeConfigurationName
)
# Function to log output with timestamp.
function Log-Output($msg) {
    Write-Output "[$(get-date -Format HH:mm:ss)] $msg"
}

#initial steps --if you have access to multiple subscriptions uncomment below & add correct sub name
#login-azureRmAccount
$armContext = Set-AzureRmContext -Subscription 'az-training-01'
$location = "West Europe"
$keyvault = Get-AzureRmKeyVault -ResourceGroupName $OpsResourceGroup

Log-Output ("connected to subscription " + $armContext.Subscription +" as " + $armContext.Account.Id)
Log-Output "secrets being retrieved from keyvault = " + $keyvault.VaultName

#get Automation info for DSC & retrieve variables and keys
$adminSecret = Get-AzureKeyVaultSecret -VaultName $keyvault.VaultName -Name 'vmAdminPassword'
$adminPassword = ($adminSecret.SecretValueText | ConvertTo-SecureString -AsPlainText -Force)
$Account = Get-AzureRmAutomationAccount -ResourceGroupName $OpsResourceGroup
$autoAccountName = $account.AutomationAccountName
$adminCredential = Get-AzureRmAutomationCredential -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Name AzureCredentials
$adminUser = $adminCredential.UserName.Split('@', 2)
$adminUsername = $adminUser[0]
$vnetResourceVar = (Get-AzureRmAutomationVariable -ResourceGroupName $opsResourceGroup -AutomationAccountName $autoAccountName -Name "VnetResourceGroup").Value
$vnetResourceGroup = "$vnetResourceVar" ##for whatever reason some retreived vars can't be directly passed unless redeclared as strings 
$artifactsLocation = (Get-AzureRmAutomationVariable -ResourceGroupName $opsResourceGroup -AutomationAccountName $autoAccountName -Name "ArtifactsLocation").Value

#get VNET info and set subnet based on config selected
$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $vnetresourceGroup
$vnetName = $vnet.Name
$subnets = $vnet.Subnets
$vmSubnetName = $subnets[1].Name

$nodeConfiguration = "WebConfig.$nodeConfigurationName"

Log-Output ("VMs will be placed in VNET = " + $vnetName + ", subnet = " + $vmSubnetName)

#get OMS workspace info
$omsWorkspace = Get-AzureRmOperationalInsightsWorkspace -ResourceGroupName $OpsResourceGroup
$workspaceId = $omsWorkspace.CustomerId.Guid
$workspaceSecret = Get-AzureKeyVaultSecret -VaultName $keyvault.VaultName -Name 'omsKey'
$workspaceKey = ($workspaceSecret.SecretValueText | ConvertTo-SecureString -AsPlainText -Force)

Log-Output ("automation account $autoAccountName found")
Log-Output ("DSC registration URL $registrationUrl will be used")
Log-Output ("OMS workspace " + $omsWorkspace.Name + " will be used for Log Analytics")

New-AzureRmResourceGroup -Name $vmResourceGroup -Location $location

$vmTemplateUri = "$artifactsLocation/Windows-2016-VM-Template.json"

Log-Output "Setting template parameters."
$params =[ordered]@{
    adminUsername               = $adminUsername;
    availabilitySetName         = $availabilitySetName;
    vmNamePrefix                = $vmNamePrefix;
    vmSize                      = $VmSize;
    numberOfInstances           = $numberOfInstances;
    virtualNetworkName          = $vnetName;
    virtualNetworkResourceGroup = $vnetResourceGroup;
    subnetName                  = $vmSubnetName;
    nodeConfigurationName       = $nodeConfiguration

}

# Pull automation account info
$RegistrationInfo = Get-AzureRmAutomationRegistrationInfo -ResourceGroupName $OpsResourceGroup -AutomationAccountName $AutoAccountName

# Add parameter variables for DSC registration with key
$registrationKey = ($RegistrationInfo.PrimaryKey | ConvertTo-SecureString -AsPlainText -Force)
$RegistrationUrl = $RegistrationInfo.Endpoint
# same for OMS workspace Key
$workspaceKey = ($workspaceSecret.SecretValueText | ConvertTo-SecureString -AsPlainText -Force)

# Add secure strings to parameters hash file separately. 
$params.Add("adminPassword", $adminPassword)
$params.Add("registrationKey", $registrationKey)
$params.Add("RegistrationUrl", $RegistrationUrl)
$params.Add("workspaceID", $workspaceId)
$params.Add("workspaceKey", $workspaceKey)

##Deploy the Vms 
Log-Output "Starting deployment."
try {
    $Deployment = New-AzureRmResourceGroupDeployment `
        -Name                        "NikeAzDayDeploy-$(([guid]::NewGuid()).Guid)" `
        -ResourceGroupName           $vmResourceGroup `
        -TemplateUri                 $vmTemplateUri `
        -TemplateParameterObject     $params `
        -Mode                        incremental `
        -Force `
        -Verbose
} catch { throw $_ }

##attach the NSG to the VM subnet
$subnetConfig = Set-AzureRmVirtualNetworkSubnetConfig `
    -Name $vmSubnetName `
    -AddressPrefix $subnets[1].AddressPrefix `
    -VirtualNetwork $vnet `
    -NetworkSecurityGroup $nsg 

Log-Output "attaching NSG to subnet $vmSubnetName"

$vnet = Set-AzureRmVirtualNetwork -VirtualNetwork $vnet

Log-Output "******deployment complete******"
