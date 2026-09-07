# Azure Recovery Services vault with Bicep

Deploys a Recovery Services vault, a daily VM backup policy, and enrols existing
Azure VMs and Azure Files shares into the vault.

```
main.bicep                     orchestrator (deploy this)
main.bicepparam                parameters: vault name, VMs and file shares to protect
modules/vault.bicep            the vault + storage redundancy
modules/vm-backup-policy.bicep daily VM policy (Enhanced/V2) with daily/weekly/monthly retention
modules/protect-vm.bicep       enrols one VM
modules/protect-fileshare.bicep registers a storage account and enrols its file shares
deploy.sh                      what-if + deploy helper
examples/vm-with-backup.bicep  creates a VM and backs it up in one deployment
```

## Deploy

```bash
az login
az account set --subscription <subscription-id>

# edit main.bicepparam first, then:
./deploy.sh rg-backup-prod westeurope
```

Or directly:

```bash
az deployment group create -g rg-backup-prod -f main.bicep -p main.bicepparam
```

## How resources are added to the vault

In Bicep, "adding a resource to the vault" means creating a **protected item**
under the vault. The resource type is always:

```
Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems
```

The trick is the resource **name**, which is a four-segment path that encodes the
source resource. The protected item is deployed into the *vault's* resource
group, even when the source VM lives elsewhere.

### Azure VM

```bicep
resource protectedVm 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2024-04-01' = {
  //     <vault>  /Azure/iaasvmcontainer;iaasvmcontainerv2;<vm-rg>;<vm-name>/vm;iaasvmcontainerv2;<vm-rg>;<vm-name>
  name: '${vaultName}/Azure/iaasvmcontainer;iaasvmcontainerv2;${vmRg};${vmName}/vm;iaasvmcontainerv2;${vmRg};${vmName}'
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    policyId: policy.id
    sourceResourceId: vm.id
  }
}
```

No container registration is needed for VMs. `modules/protect-vm.bicep` does this
given a VM resource ID.

### Azure Files share

Storage accounts must be **registered as a protection container** first, then
each share becomes a protected item under it:

```bicep
resource container 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers@2024-04-01' = {
  name: '${vaultName}/Azure/StorageContainer;Storage;${saRg};${saName}'
  properties: {
    backupManagementType: 'AzureStorage'
    containerType: 'StorageContainer'
    sourceResourceId: storageAccount.id
  }
}

resource protectedShare '...protectionContainers/protectedItems@2024-04-01' = {
  parent: container
  name: 'AzureFileShare;${shareName}'
  properties: {
    protectedItemType: 'AzureFileShareProtectedItem'
    policyId: fileSharePolicy.id
    sourceResourceId: storageAccount.id
  }
}
```

`modules/protect-fileshare.bicep` does both, plus creates the file share policy.

### Adding more resources

1. Append the VM resource ID to `vmResourceIds` in `main.bicepparam`, or add a
   storage account block to `fileShares`.
2. Re-run the deployment. Existing protected items are idempotent.

To protect a VM you are creating in the same template, pass `vm.id` to the
`protect-vm` module and Bicep will order the deployment for you:

```bicep
module protectNewVm 'modules/protect-vm.bicep' = {
  name: 'protect-${vm.name}'
  params: {
    vaultName: vault.outputs.vaultName
    policyId: vmPolicy.outputs.policyId
    vmResourceId: vm.id
  }
}
```

A complete, runnable version of this is in `examples/vm-with-backup.bicep`. It
creates a VNet, NSG, NIC and an Ubuntu VM, then enrols the VM into a fresh vault:

```bash
az deployment group create -g rg-backup-demo -f examples/vm-with-backup.bicep \
  -p examples/vm-with-backup.bicepparam \
  -p adminSshPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
```

If the VM is in a **different resource group** from the vault, call the module
with `scope: resourceGroup('<vault-rg>')` so the protected item lands in the
vault's resource group.

### Other workload types

The same pattern applies with different names and `protectedItemType` values:

| Workload | Container name | Protected item name | protectedItemType |
|---|---|---|---|
| Azure VM | `iaasvmcontainer;iaasvmcontainerv2;<rg>;<vm>` | `vm;iaasvmcontainerv2;<rg>;<vm>` | `Microsoft.Compute/virtualMachines` |
| Azure Files | `StorageContainer;Storage;<rg>;<sa>` | `AzureFileShare;<share>` | `AzureFileShareProtectedItem` |
| SQL in Azure VM | `VMAppContainer;Compute;<rg>;<vm>` | `SQLDataBase;<instance>;<db>` | `AzureVmWorkloadSQLDatabase` |

SQL and SAP HANA in-VM workloads also require the container to be registered and
databases discovered, which the ARM API does not fully expose. Those are usually
enrolled via the portal, CLI or PowerShell after the vault exists.

## Things to know

- **Region**: the vault and the resources it protects must be in the same region.
- **Storage redundancy** (`storageRedundancy`) is locked once the first item is
  protected. Decide GRS vs LRS/ZRS up front.
- **Soft delete** is enabled with 14-day retention. Deleting the vault requires
  stopping protection and purging soft-deleted items first.
- **Concurrency**: the vault rejects parallel configuration changes, so the
  modules use `@batchSize(1)`.
- **Permissions**: the deploying identity needs `Backup Contributor` on the vault
  resource group and `Virtual Machine Contributor` (or read on the VM) for VMs
  in other resource groups.
- **First backup**: enrolling a resource schedules the initial backup at the next
  policy run. Trigger one immediately with:

  ```bash
  az backup protection backup-now -g <vault-rg> -v <vault> \
    --container-name <vm-name> --item-name <vm-name> --backup-management-type AzureIaasVM
  ```
