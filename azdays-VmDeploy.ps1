#create multiple VMs from ARM Template with provided parameters. 
#DSC and OMS extensions configured with DSC node config as selected. 
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
    [int]$numberOfInstances,
    
    # prefix for VM names
    [Parameter(Mandatory=$true, HelpMessage="DSC configuration to apply")]
    [ValidateSet("Web", "SQL")]
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

#get VNET info and set subnet based on config selected
$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $vnetresourceGroup
$vnetName = $vnet.Name
$subnets = $vnet.Subnets
switch ($nodeConfigurationName)
{
    'Web' {$vmSubnetName = $subnets[1].Name}
    'Sql' {$vmSubnetName = $subnets[2].Name}
}

Log-Output ("VMs will be placed in VNET = " + $vnetName + ", subnet = " + $vmSubnetName)

#get Automation info for DSC
$Account = Get-AzureRmAutomationAccount -ResourceGroupName $OpsResourceGroup
$autoAccountName = $account.AutomationAccountName
$adminCredential = Get-AzureRmAutomationCredential -ResourceGroupName $OpsResourceGroup -AutomationAccountName $autoAccountName -Name AzureCredentials
$adminUser = $adminCredential.UserName.Split('@', 2)
$adminUsername = $adminUser[0]
$nodeConfiguration = "WebConfig.$nodeConfigurationName"

#get OMS workspace info
$omsWorkspace = Get-AzureRmOperationalInsightsWorkspace -ResourceGroupName $OpsResourceGroup
$workspaceId = $omsWorkspace.CustomerId.Guid
$workspaceSecret = Get-AzureKeyVaultSecret -VaultName $keyvault.VaultName -Name 'omsKey'
$workspaceKey = ($workspaceSecret.SecretValueText | ConvertTo-SecureString -AsPlainText -Force)

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
# Add to parameters hash file
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
