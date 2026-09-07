using 'vm-with-backup.bicep'

param vmName = 'vm-demo-01'
param vmSize = 'Standard_B2s'
param adminUsername = 'azureuser'

// Pass the key on the command line instead of committing it:
//   -p adminSshPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
param adminSshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY', '')

param tags = {
  environment: 'demo'
  workload: 'backup-example'
}
