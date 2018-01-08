#!/bin/sh
#Clone the git repository and run this script from the directory after modifying the variables here and parameters in the parameters files
#Run 'az login' to authenticate to an Azure Subscription from the CLI prior to running this script
#Azure CLI v2.0 required for this script to work https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

#VM Resource Group Name
VMRG=
#Resource Group Name for the VNET
VNETRG=
#Name of the deployment subscription
SUBSCRIPTIONNAME=
#Deployment Azure Region
LOCATION=
#KeyVault Name
KVNAME=
#LoadBalancer Name
LBNAME=
#Leave these values
VNETTEMPLATEFILE=./simplevnet.json
VNETPARAMSFILE=./simplevnet.parameters.json
VMTEMPLATEFILE=./Linux-CentOS-VM-Template.json
VMPARAMSFILE=./Linux-CentOS-VM-Template.parameters.json
#Name of the Public IP address for the NLB
PUBLICIPNAME=
#DNS Name servers are accessed by
DNSNAME=

az account set --subscription $SUBSCRIPTIONNAME
echo "Account set to $SUBSCRIPTIONNAME"

echo "Bulding VNET ResourceGroup $VNETRG..."

az group create --name $VNETRG --location $LOCATION

echo "Deploying the VNET..."

az group deployment create -n vnetDeployment -g $VNETRG --template-file $VNETTEMPLATEFILE --parameters @$VNETPARAMSFILE
az group deployment wait -n vnetDeployment -g $VNETRG --created


echo "Building the VM ResourceGroup $VMRG..."
az group create --name $VMRG --location $LOCATION

echo "Deploying VMs..."
az group deployment create -n vmdeployment -g $VMRG --template-file $VMTEMPLATEFILE --parameters @$VMPARAMSFILE


echo "Deploying Public IP..."
az network public-ip create -g $VNETRG -n $PUBLICIPNAME --dns-name $DNSNAME --allocation-method Dynamic

echo "Deploying the Network Load Balancer"

az network lb create -g $VNETRG -n $LBNAME --vnet-name $VNET 
az network lb frontend-ip create --lb-name $LBNAME -name lbipconfig -g $VNETRG --public-ip-address /subscriptions/$SUBSCRIPTIONID/resourceGroups/$VNETRG/providers/Microsoft.Network/publicIPAddresses/$PUBLICIPNAME

SUBSCRIPTIONID=$(az account show --query "id" | tr -d '"')
NICNAME=$(az network nic list -g $VMRG --query "[0].name" | tr -d '"')
IPCONFIG=$(az network nic show -n $NICNAME -g $VMRG --query "ipConfigurations[0].name" | tr -d '"')

az group deployment wait -n vmdeployment -g $VMRG --created
echo "Attaching Public IP to VM"
az network nic ip-config update -g $VMRG --nic-name $NICNAME --public-ip-address /subscriptions/$SUBSCRIPTIONID/resourceGroups/$VNETRG/providers/Microsoft.Network/publicIPAddresses/$PUBLICIPNAME --name $IPCONFIG

FQDN=$(az network public-ip show -n $PUBLICIPNAME -g $VNETRG --query "dnsSettings.fqdn")
IP=$(az network public-ip show -n $PUBLICIPNAME -g $VNETRG --query "ipAddress")

echo "All resources are complete.  Please login via SSH to $FQDN or $IP"

