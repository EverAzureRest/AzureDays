#create VMs
Param
(
    # prefix for VM names
    [Parameter(Mandatory=$true, HelpMessage="prefix for VM names")]
    [string]$vmNamePrefix,

    # availability set name
    [Parameter(Mandatory=$true, HelpMessage="name for Availability set for VMs")]
    [string]$availabilitySetName,

    # VM Size
    [Parameter(Mandatory=$True, HelpMessage="Enter the Vm Size.")]
    [ValidateSet("Standard_D2_v2", "Standard_D3_v2")]
    [String]$VmSize,

    # number of VMs to deploy
    [Parameter(Mandatory=$true, HelpMessage="number of identical VMs to deploy")]
    [int]$numberofInstances,
    
    # prefix for VM names
    [Parameter(Mandatory=$true, HelpMessage="DSC configuration to apply")]
    [ValidateSet("IIS", "SQL")]
    [string]$nodeConfigurationName
)
# Function to log output with timestamp.
function Log-Output($msg) {
    Write-Output "[$(get-date -Format HH:mm:ss)] $msg"
}

#initial steps --if you have access to multiple subscriptions uncomment below & add correct sub name
#login-azureRmAccount
$subscription = Get-AzureRmSubscription
$subscriptionName = $subscription[0].Name
$armContext = Set-AzureRmContext -Subscription $subscriptionName
$artifactsLocation = "https://raw.githubusercontent.com/Lorax79/AzureDays/master"
$location = "East US"
$vnetresourceGroup = "azd-vnet-rg-01"
$vmResourceGroup = "azd-vm-rg-01"
$OpsResourceGroup = "azd-ops-rg-01"
$keyvault = Get-AzureRmKeyVault -ResourceGroupName $OpsResourceGroup
$adminSecret = Get-AzureKeyVaultSecret -VaultName $keyvault.VaultName -Name 'vmAdminPassword'
$adminPassword = $adminSecret.SecretValueText


Log-Output ("connected to subscription " + $armContext.Subscription +" as " + $armContext.Account.Id)
Log-Output "secrets being retrieved from keyvault = $keyvault"

#get VNET info
$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $vnetresourceGroup
$vnetName = $vnet.Name
$subnets = $vnet.Subnets
$vmSubnetName = $subnets[1].Name

Log-Output ("VMs will be placed in VNET = " + $vnetName + ", subnet = " + $vmSubnetName)

#get Automation info for DSC
$Account = Get-AzureRmAutomationAccount -ResourceGroupName $OpsResourceGroup
$autoAccountName = $account.AutomationAccountName
$RegistrationInfo = $Account | Get-AzureRmAutomationRegistrationInfo
$registrationUrl = $RegistrationInfo.Endpoint
$registrationKey = $RegistrationInfo.PrimaryKey
#$registrationKey = $registrationPrimaryKey | ConvertTo-SecureString -AsPlainText -Force
$adminCredential = Get-AzureRmAutomationCredential -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Name AzureCredentials
$adminUser = $adminCredential.UserName.Split('@', 2)
$adminUsername = $adminUser[0]

#get OMS workspace info
$omsWorkspace = Get-AzureRmOperationalInsightsWorkspace -ResourceGroupName $OpsResourceGroup
$workspaceId = $omsWorkspace.Name
$workspaceSecret = Get-AzureKeyVaultSecret -VaultName $keyvault.VaultName -Name 'omsKey'
$workspaceKey = $workspaceSecret.SecretValueText

Log-Output ("automation account $autoAccountName found")
Log-Output ("DSC registration URL $registrationUrl will be used")
Log-Output ("OMS workspace " + $omsWorkspace.Name + " will be used for Log Analytics")

New-AzureRmResourceGroup -Name $vmResourceGroup -Location $location

#$vmTemplateUri = "$artifactsLocation/Windows-2016-VM-Template.json"
$vmTemplateUri = "C:\Users\mamorga\Source\Repos\AzureDays\Windows-2016-VM-Template.json"

Log-Output "Setting template parameters."
$params = @{
    adminUsername               = $adminUsername;
    adminPassword               = $adminPassword
    availabilitySetName         = $availabilitySetName;
    vmNamePrefix                = $vmNamePrefix;
    vmSize                      = $VmSize;
    virtualNetworkName          = $vnetName;
    virtualNetworkResourceGroup = $vnetResourceGroup;
    subnetName                  = $vmSubnetName;
    workspaceId                 = $workspaceId;
    workspaceKey                = $workspaceKey
    registrationUrl             = $registrationUrl;
    registrationKey             = $registrationKey;
    nodeConfigurationName       = $nodeConfigurationName;

}
# Deploy the Vm
Log-Output "Starting deployment."
try {
    $Deployment = New-AzureRmResourceGroupDeployment `
        -Name                        "AzdaysVmDeploy" `
        -ResourceGroupName           $vmResourceGroup `
        -TemplateUri                 $vmTemplateUri `
        -TemplateParameterObject     $params `
        -Mode                        incremental `
        -Force `
        -Verbose
} catch { throw $_ }
