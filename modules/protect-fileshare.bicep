// Registers a storage account with the vault and protects one or more of its file shares.
// Deploy at the scope of the resource group that holds the VAULT.
@description('Name of the existing Recovery Services vault.')
param vaultName string

@description('Full resource ID of the storage account that owns the file shares.')
param storageAccountId string

@description('Names of the file shares in that storage account to protect.')
param fileShareNames array

@description('Name of the file share backup policy to create in the vault.')
param policyName string = 'DailyFileSharePolicy'

@description('Daily backup time in UTC, as an ISO 8601 timestamp.')
param scheduleRunTime string = '2024-01-01T03:00:00Z'

@description('Number of days to keep daily snapshots.')
@minValue(1)
@maxValue(200)
param dailyRetentionDays int = 30

var storageAccountResourceGroup = split(storageAccountId, '/')[4]
var storageAccountName = last(split(storageAccountId, '/'))

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' existing = {
  name: vaultName
}

resource policy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  parent: vault
  name: policyName
  properties: {
    backupManagementType: 'AzureStorage'
    workLoadType: 'AzureFileShare'
    timeZone: 'UTC'
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        scheduleRunTime
      ]
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          scheduleRunTime
        ]
        retentionDuration: {
          count: dailyRetentionDays
          durationType: 'Days'
        }
      }
    }
  }
}

// Unlike VMs, a storage account must be registered as a protection container first.
resource container 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers@2024-04-01' = {
  name: '${vaultName}/Azure/StorageContainer;Storage;${storageAccountResourceGroup};${storageAccountName}'
  properties: {
    backupManagementType: 'AzureStorage'
    containerType: 'StorageContainer'
    sourceResourceId: storageAccountId
  }
}

@batchSize(1)
resource protectedShares 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2024-04-01' = [for share in fileShareNames: {
  parent: container
  name: 'AzureFileShare;${share}'
  properties: {
    protectedItemType: 'AzureFileShareProtectedItem'
    policyId: policy.id
    sourceResourceId: storageAccountId
  }
}]

output containerId string = container.id
output protectedItemIds array = [for (share, i) in fileShareNames: protectedShares[i].id]
