#!/bin/sh
#Clone the git repository and run this script from the directory after modifying the variables here and parameters in the parameters files
#Run 'az login' to authenticate to an Azure Subscription from the CLI prior to running this script
#Azure CLI v2.0 required for this script to work https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

#Specify VM Resource Group Name
VMRG=""
#Resource Group Name for the VNET
VNETRG="Azd-VNET-RG"
#VNET Name - make sure this is the same value as in ./simplevnet.parameters.json
VNET="AzureDaysVNET"
#Name of the deployment subscription
SUBSCRIPTIONNAME=""
#Deployment Azure Region
LOCATION="East US"
#LoadBalancer Name
LBNAME=""
#Leave these values
VNETTEMPLATEFILE=./simplevnet.json
VNETPARAMSFILE=./simplevnet.parameters.json
VMTEMPLATEFILE=./Linux-CentOS-VM-Template.json
VMPARAMSFILE=./Linux-CentOS-VM-Template.parameters.json
#Name of the Public IP address for the NLB
PUBLICIPNAME=""
#DNS Name servers are accessed by
DNSNAME=""

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
az network lb frontend-ip create --lb-name $LBNAME -n lbipconfig -g $VNETRG --public-ip-address $PUBLICIPNAME
az network lb address-pool create --lb-name $LBNAME -n lbbackendpool -g $VNETRG
az network lb inbound-nat-rule create --frontend-ip-name lbipconfig --backend-port 22 --frontend-port 5022 --lb-name $LBNAME -n inbound-nat -g $VNETRG --protocol Tcp
az network lb probe create --lb-name $LBNAME -n probe --port 22 --protocol Tcp -g $VNETRG --interval 10 --threshold 5

az group deployment wait -n vmdeployment -g $VMRG --created

SUBSCRIPTIONID=$(az account show --query "id" | tr -d '"')
NIC1NAME=$(az network nic list -g $VMRG --query "[0].name" | tr -d '"')
NIC2NAME=$(az network nic list -g $VMRG --query "[1].name" | tr -d '"')
IPCONFIG1=$(az network nic show -n $NIC1NAME -g $VMRG --query "ipConfigurations[0].name" | tr -d '"')
IPCONFIG2=$(az network nic show -n $NIC2NAME -g $VMRG --query "ipConfigurations[0].name" | tr -d '"')
LBBACKENDPOOLID=$(az network lb address-pool show -g $VNETRG --lb-name $LBNAME -n lbbackendpool --query "id" | tr -d '"')

echo "Attaching VMs to Load Balancer Backend Pool"
az network nic ip-config update -g $VMRG --nic-name $NIC1NAME --lb-address-pools $LBBACKENDPOOLID --name $IPCONFIG1
az network nic ip-config update -g $VMRG --nic-name $NIC2NAME --lb-address-pools $LBBACKENDPOOLID --name $IPCONFIG2

FQDN=$(az network public-ip show -n $PUBLICIPNAME -g $VNETRG --query "dnsSettings.fqdn")
IP=$(az network public-ip show -n $PUBLICIPNAME -g $VNETRG --query "ipAddress")

echo "All resources are complete.  Please login via SSH to $FQDN or $IP over port 5022"

