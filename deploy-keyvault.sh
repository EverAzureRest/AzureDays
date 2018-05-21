#!/bin/sh
#Clone the git repository and run this script from the directory after modifying the variables here and parameters in the parameters files
#Run 'az login' to authenticate to an Azure Subscription from the CLI prior to running this script
#Azure CLI v2.0 required for this script to work https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

#Resource Group Name for OMS and Keyvault
SUPPORTRG="azd-CHANGEME-ops-rg-01"
#Name of the deployment subscription
SUBSCRIPTIONNAME="az-training-01"
#Deployment Azure Region
LOCATION="westeurope"
#KeyVault Name - must be globally unique, so be creative!
KVNAME=""
#OMS Key from the OMS Deployment Script
OMSKEY=""
#RSA Public Key Path - change if not the default path to your key
SSHPUBKEYFILE="~/.ssh/id_rsa.pub"

#Set the target subscription
az account set --subscription $SUBSCRIPTIONNAME
echo "Account set to $SUBSCRIPTIONNAME"

echo "Building KeyVault..."

az keyvault create -n $KVNAME -g $SUPPORTRG -l $LOCATION --enabled-for-template-deployment

#Create a secret for the OMS Key in Keyvault
az keyvault secret set -n omssecret --vault-name $KVNAME --value $OMSKEY

#Create a secret for your SSH public key that will be used in VM Deployment

az keyvault secret set -n sshsecret --vault-name $KVNAME --file $SSHPUBKEYFILE

KEYVAULTID=$(az keyvault show -n $KVNAME -g $SUPPORTRG --query "id" | tr -d '"')

echo "Your Keyvault ID is: $KEYVAULTID - please copy this value to use in the VM Deployment Parameters file"