#create VMs

# Function to log output with timestamp.
function Log-Output($msg) {
    Write-Output "[$(get-date -Format HH:mm:ss)] $msg"
}

#initial steps --if you have access to multiple subscriptions uncomment below & add correct sub name
login-azureRmAccount
$subscription = Get-AzureRmSubscription
$subscriptionName = $subscription[0].Name
$armContext = Set-AzureRmContext -Subscription $subscriptionName
$artifactsLocation = "https://raw.githubusercontent.com/mmcsa/AzureDays/master"
$location = "East US"
$vnetresourceGroup = "azd-vnet-rg-01"
$vmResourceGroup = "azd-vm-rg-01"
$OpsResourceGroup = "azd-ops-rg-01"

Log-Output ("connected to subscription " + $armContext.Subscription +" as " + $armContext.Account.Id)

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



New-AzureRmResourceGroup -Name $vmResourceGroup -Location $location

$vmTemplatePath = "$artifactsLocation/Windows-2016-VM-Template.json"
$vmParameterPath = "C:\Users\mamorga\Source\Repos\AzureDays\Windows-2016-VM-Template.parameters.json"

New-AzureRmResourceGroupDeployment -Name AzdVmDeploy -ResourceGroupName $vmResourceGroup -TemplateFile $templatePath -TemplateParameterFile $parameterPath -Verbose -Force -registrationKey ($RegistrationInfo.PrimaryKey | ConvertTo-SecureString -AsPlainText -Force) -RegistrationUrl $RegistrationInfo.Endpoint 
