#!/bin/sh
#Clone the git repository and run this script from the directory after modifying the variables here and parameters in the parameters files
#Run 'az login' to authenticate to an Azure Subscription from the CLI prior to running this script
#Azure CLI v2.0 required for this script to work https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

#This script also requires the blobxfer python utility for python2 or python3, please refer to https://http://blobxfer.readthedocs.io/en/latest/01-installation/

#Resource Group Name for OMS and Keyvault
SUPPORTRG="azd-CHANGEME-ops-rg-01"
STORAGEACCOUNTNAME=$(az storage account list -g $SUPPORTRG --query "[0].name" | tr -d '"')
BLOBENDPOINT=$(az storage account list -g $SUPPORTRG --query "[0].primaryEndpoints.blob" | tr -d '"')
CONTENTPATH="./website"
STORAGEKEY=$(az storage account keys list -n $STORAGEACCOUNTNAME -g $SUPPORTRG --query "[0].value" | tr -d '"')

#Create the container for the website data
az storage container create -n website --account-name $STORAGEACCOUNTNAME --public-access container

#ensure container permissions are set to public
az storage container set-permission -n website --account-name $STORAGEACCOUNTNAME --public-access container

#Deploy the content to the storage endpoint
blobxfer upload --local-path $CONTENTPATH --storage-account $STORAGEACCOUNTNAME --remote-path /website --storage-account-key $STORAGEKEY


echo "Website content deployed to "$BLOBENDPOINT"website/ - Copy this value down to use in the cloud-init config"