#!/bin/sh
#Clone the git repository and run this script from the directory after modifying the variables here and parameters in the parameters files
#Run 'az login' to authenticate to an Azure Subscription from the CLI prior to running this script
#Azure CLI v2.0 required for this script to work https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

#Resource Group Name for OMS and Keyvault
SUPPORTRG=""
#Name of the deployment subscription
SUBSCRIPTIONNAME=""
#Deployment Azure Region
LOCATION="EastUS"
#OMS Template file locations
OMSTEMPLATE=./OMS/omsMaster-deploy.json
OMSPARAMSFILE=./OMS/omsMaster.parameters.json
#Enter the name of the workspace used in the parameters file above
OMSWORKSPACENAME=""

#Set the target subscription
az account set --subscription $SUBSCRIPTIONNAME
echo "Account set to $SUBSCRIPTIONNAME"

#Create the Resource Group for the Keyvault and OMS
echo "Building Resource Group for OMS and Keyvault..."
az group create --name $SUPPORTRG --location $LOCATION

#Deploy the workspace
echo "Deploying OMS workspace"
az group deployment create -n OMSdeployment -g $SUPPORTRG --template-file $OMSTEMPLATE --parameters @$OMSPARAMSFILE

WORKSPACEID=$(az resource show -n $OMSWORKSPACENAME -g $SUPPORTRG --resource-type Microsoft.OperationalInsights/workspaces --query "properties.customerId" | tr -d '"')

echo "Deployment Complete - your OMS Workspace ID is: $WORKSPACEID - please note this value"
