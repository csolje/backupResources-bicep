// Daily Azure VM backup policy (Enhanced / V2 policy).
@description('Name of the existing Recovery Services vault.')
param vaultName string

@description('Name of the backup policy.')
param policyName string = 'DailyVmPolicy'

@description('Daily backup time in UTC, as an ISO 8601 timestamp. Only the time-of-day part matters.')
param scheduleRunTime string = '2024-01-01T02:00:00Z'

@description('Number of days to keep daily recovery points.')
@minValue(7)
@maxValue(9999)
param dailyRetentionDays int = 30

@description('Number of weeks to keep the weekly (Sunday) recovery point. 0 disables weekly retention.')
@minValue(0)
@maxValue(5163)
param weeklyRetentionWeeks int = 12

@description('Number of months to keep the monthly (first Sunday) recovery point. 0 disables monthly retention.')
@minValue(0)
@maxValue(1188)
param monthlyRetentionMonths int = 12

@description('Days to keep instant restore snapshots (1-30).')
@minValue(1)
@maxValue(30)
param instantRpRetentionDays int = 2

@description('IANA/Windows time zone name for the schedule.')
param timeZone string = 'UTC'

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' existing = {
  name: vaultName
}

resource policy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  parent: vault
  name: policyName
  properties: {
    backupManagementType: 'AzureIaasVM'
    policyType: 'V2'
    instantRpRetentionRangeInDays: instantRpRetentionDays
    timeZone: timeZone
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicyV2'
      scheduleRunFrequency: 'Daily'
      dailySchedule: {
        scheduleRunTimes: [
          scheduleRunTime
        ]
      }
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
      weeklySchedule: weeklyRetentionWeeks > 0 ? {
        daysOfTheWeek: [
          'Sunday'
        ]
        retentionTimes: [
          scheduleRunTime
        ]
        retentionDuration: {
          count: weeklyRetentionWeeks
          durationType: 'Weeks'
        }
      } : null
      monthlySchedule: monthlyRetentionMonths > 0 ? {
        retentionScheduleFormatType: 'Weekly'
        retentionScheduleWeekly: {
          daysOfTheWeek: [
            'Sunday'
          ]
          weeksOfTheMonth: [
            'First'
          ]
        }
        retentionTimes: [
          scheduleRunTime
        ]
        retentionDuration: {
          count: monthlyRetentionMonths
          durationType: 'Months'
        }
      } : null
    }
  }
}

output policyId string = policy.id
output policyName string = policy.name
