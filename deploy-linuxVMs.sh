#!/bin/sh
#Clone the git repository and run this script from the directory after modifying the variables here and parameters in the parameters files
#Run 'az login' to authenticate to an Azure Subscription from the CLI prior to running this script
#Azure CLI v2.0 required for this script to work https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

#Specify VM Resource Group Name
VMRG="azd-CHANGEME-vm-rg-01"
#Resource Group Name for the VNET
VNETRG="azd-CHANGEME-vnet-rg-01"
#VNET Name - make sure this is the same value as in ./simplevnet.parameters.json
VNET="AzureDaysVNET"
#Name of the deployment subscription
SUBSCRIPTIONNAME="az-training-01"
#Deployment Azure Region
LOCATION="westeurope"
#LoadBalancer Name
LBNAME=""
#Name of the Public IP address for the NLB - needs to be unique, so use a creative convention
PUBLICIPNAME=""
#DNS simple name for the load balancer. Will be appended to FQDN.  Must be unique per region, so use a creative convention. 
DNSNAME=""
#Leave these values
VNETTEMPLATEFILE=./simplevnet.json
VNETPARAMSFILE=./simplevnet.parameters.json
VMTEMPLATEFILE=./Linux-Ubuntu-VM-Template.json
VMPARAMSFILE=./Linux-Ubuntu-VM-Template.parameters.json
#Cloud-init yml configuration - don't change this
CLOUDINIT="./cloudconfig-ubuntu.txt"
FEPORT="3441"

az account set --subscription $SUBSCRIPTIONNAME
echo "Account set to $SUBSCRIPTIONNAME"

#not needed for EHQ AzureDays
#echo "Bulding VNET ResourceGroup $VNETRG..."

#az group create --name $VNETRG --location $LOCATION

echo "Deploying the VNET..."

az group deployment create -n vnetDeployment -g $VNETRG --template-file $VNETTEMPLATEFILE --parameters @$VNETPARAMSFILE
az group deployment wait -n vnetDeployment -g $VNETRG --created


echo "Building the VM ResourceGroup $VMRG..."
az group create --name $VMRG --location $LOCATION

echo "Deploying VMs..."
INITCONTENT=`cat "$CLOUDINIT"|base64 -w 0 || cat "$CLOUDINIT"|base64`
echo "\"customData\":{\"value\":\"$INITCONTENT\"}" > updatepattern.txt

cat $VMPARAMSFILE | tr '\n' ' ' | sed "s/\"customData[^{]*{[^}]*}/$(sed 's:/:\\/:g' updatepattern.txt)/" > params.json

az group deployment create -n vmdeployment -g $VMRG --template-file $VMTEMPLATEFILE --parameters @params.json

rm updatepattern.txt
rm params.json

echo "Deploying Public IP..."
az network public-ip create -g $VNETRG -n $PUBLICIPNAME -l $LOCATION --dns-name $DNSNAME --allocation-method Dynamic

echo "Deploying the Network Load Balancer..."

az network lb create -g $VNETRG -n $LBNAME -l $LOCATION --frontend-ip-name lbfrontipconfig --backend-pool-name lbbackendpool --public-ip-address $PUBLICIPNAME 
az network lb inbound-nat-rule create --frontend-ip-name lbfrontipconfig --backend-port 22 --frontend-port $FEPORT --lb-name $LBNAME -n inbound-nat -g $VNETRG --protocol Tcp
az network lb rule create --lb-name $LBNAME -g $VNETRG -n lbrule --frontend-port 80 --backend-port 80 --protocol Tcp --frontend-ip-name lbfrontipconfig --backend-pool-name lbbackendpool
az network lb probe create --lb-name $LBNAME -n probe --port 22 --protocol Tcp -g $VNETRG --interval 10 --threshold 5

az group deployment wait -n vmdeployment -g $VMRG --created

SUBSCRIPTIONID=$(az account show --query "id" | tr -d '"')
NIC1NAME=$(az network nic list -g $VMRG --query "[0].name" | tr -d '"')
NIC2NAME=$(az network nic list -g $VMRG --query "[1].name" | tr -d '"')
IPCONFIG1=$(az network nic show -n $NIC1NAME -g $VMRG --query "ipConfigurations[0].name" | tr -d '"')
IPCONFIG2=$(az network nic show -n $NIC2NAME -g $VMRG --query "ipConfigurations[0].name" | tr -d '"')
LBBACKENDPOOLID=$(az network lb address-pool show -g $VNETRG --lb-name $LBNAME -n lbbackendpool --query "id" | tr -d '"')
LBNATID=$(az network lb inbound-nat-rule show -g $VNETRG --lb-name $LBNAME -n inbound-nat --query "id" | tr -d '"')

echo "Attaching VMs to Load Balancer Backend Pool"
az network nic ip-config update -g $VMRG --nic-name $NIC1NAME --lb-address-pools $LBBACKENDPOOLID --lb-inbound-nat-rules $LBNATID --lb-name $LBNAME --name $IPCONFIG1
az network nic ip-config update -g $VMRG --nic-name $NIC2NAME --lb-address-pools $LBBACKENDPOOLID --lb-name $LBNAME --name $IPCONFIG2

FQDN=$(az network public-ip show -n $PUBLICIPNAME -g $VNETRG --query "dnsSettings.fqdn" | tr -d '"')
IP=$(az network public-ip show -n $PUBLICIPNAME -g $VNETRG --query "ipAddress" | tr -d '"')

echo "All resources are complete.
Please login to $IP over port $FEPORT: ssh adminuser@$IP -p $FEPORT.
Access the load balanced website at http://$FQDN/index.html"

