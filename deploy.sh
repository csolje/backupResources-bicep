#!/usr/bin/env bash
# Deploys the Recovery Services vault and enrols the resources listed in main.bicepparam.
set -euo pipefail

RESOURCE_GROUP="${1:?Usage: ./deploy.sh <resource-group> [location]}"
LOCATION="${2:-westeurope}"
PARAMS="${PARAMS:-main.bicepparam}"

cd "$(dirname "$0")"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

echo "Validating..."
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file main.bicep \
  --parameters "$PARAMS"

echo "Deploying..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "rsv-$(date +%Y%m%d%H%M%S)" \
  --template-file main.bicep \
  --parameters "$PARAMS" \
  --output table
