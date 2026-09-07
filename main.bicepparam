using 'main.bicep'

param vaultName = 'rsv-backup-prod-001'
param storageRedundancy = 'GeoRedundant'
param crossRegionRestore = false

// VMs to protect. Replace with your subscription ID, resource group and VM names.
param vmResourceIds = [
  '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod/providers/Microsoft.Compute/virtualMachines/vm-web-01'
  '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod/providers/Microsoft.Compute/virtualMachines/vm-sql-01'
]

param vmBackupTime = '2024-01-01T02:00:00Z'
param vmDailyRetentionDays = 30
param vmWeeklyRetentionWeeks = 12
param vmMonthlyRetentionMonths = 12

// File shares to protect. Leave empty ([]) if none.
param fileShares = [
  {
    storageAccountId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod/providers/Microsoft.Storage/storageAccounts/stappprod001'
    shareNames: [
      'appdata'
    ]
  }
]

param tags = {
  environment: 'prod'
  workload: 'backup'
}
