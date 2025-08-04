# SharePoint Blob Sync - Windows Task Scheduler

This directory contains PowerShell scripts for setting up and managing automated SharePoint to Azure Blob Storage synchronization using Windows Task Scheduler with comprehensive logging, retry logic, and monitoring capabilities.

## 📁 Files Overview

- **`Setup-Scheduler.ps1`** - Creates and manages Windows scheduled tasks with flexible timing options
- **`Run-Sync.ps1`** - Sync runner optimized for scheduled execution with enterprise features
- **`Setup-Examples.ps1`** - Interactive helper for easy configuration and testing
- **`README-Scheduler.md`** - This comprehensive documentation file

## 🚀 Quick Start

### 1. Basic Setup (5-minute interval)
```powershell
# Run as Administrator (required for scheduled task management)
.\Setup-Scheduler.ps1
```

### 2. Custom Intervals
```powershell
# Every 10 minutes
.\Setup-Scheduler.ps1 -IntervalMinutes 10

# Every 2 hours  
.\Setup-Scheduler.ps1 -IntervalHours 2

# Daily at 9:00 AM
.\Setup-Scheduler.ps1 -DailyAt "09:00"

# Start task immediately after creation
.\Setup-Scheduler.ps1 -IntervalMinutes 15 -StartNow
```

### 3. Management Operations
```powershell
# Check current status
.\Setup-Scheduler.ps1 -Status

# Remove scheduled task
.\Setup-Scheduler.ps1 -Remove

# Interactive setup helper
.\Setup-Examples.ps1
```

## 🔧 Setup-Scheduler.ps1 Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `-IntervalMinutes` | Run every X minutes | 5 | `-IntervalMinutes 10` |
| `-IntervalHours` | Run every X hours | - | `-IntervalHours 2` |
| `-DailyAt` | Run daily at specific time (HH:MM) | - | `-DailyAt "09:00"` |
| `-TaskName` | Name of scheduled task | "SharePoint-Blob-Sync" | `-TaskName "My-Sync"` |
| `-RunAsUser` | User account to run task | Current user | `-RunAsUser "DOMAIN\User"` |
| `-LogPath` | Path for scheduler logs | `.\logs\scheduler.log` | `-LogPath "C:\Logs\sync.log"` |
| `-Remove` | Remove existing task | - | `-Remove` |
| `-Status` | Show task status | - | `-Status` |
| `-StartNow` | Start task immediately after creation | - | `-StartNow` |

## 🔄 Run-Sync.ps1 Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `-LogLevel` | Logging level (Minimal/Normal/Verbose) | Normal | `-LogLevel Verbose` |
| `-ForceSync` | Force sync even if recent | - | `-ForceSync` |
| `-SkipQuickTest` | Skip environment validation | - | `-SkipQuickTest` |
| `-MaxRetries` | Maximum retry attempts | 3 | `-MaxRetries 5` |
| `-RetryDelaySeconds` | Delay between retries | 30 | `-RetryDelaySeconds 60` |

## 🔐 Authentication Support

The scheduler supports both Azure Storage authentication methods:

### Storage Account Key Authentication
- **Configuration**: Set `USE_AZURE_AD_AUTH="false"` in `config.env`
- **Requirements**: Valid storage account key
- **Best for**: Development, testing, simple deployments

### Azure AD/RBAC Authentication
- **Configuration**: Set `USE_AZURE_AD_AUTH="true"` in `config.env`
- **Requirements**: Azure AD roles assigned (Storage Blob Data Contributor)
- **Best for**: Production, enterprise environments, compliance requirements

*The scheduler automatically detects and uses the configured authentication method.*

## 📋 Examples

### Setup Examples

```powershell
# Basic setup - every 5 minutes
.\Setup-Scheduler.ps1

# Every 15 minutes with immediate start
.\Setup-Scheduler.ps1 -IntervalMinutes 15 -StartNow

# Every 4 hours
.\Setup-Scheduler.ps1 -IntervalHours 4

# Daily at 2:30 PM
.\Setup-Scheduler.ps1 -DailyAt "14:30"

# Custom task name and user account
.\Setup-Scheduler.ps1 -TaskName "My-SharePoint-Sync" -RunAsUser "DOMAIN\ServiceAccount"

# Production setup with service account
.\Setup-Scheduler.ps1 -IntervalMinutes 30 -RunAsUser "CORP\SharePointSync" -TaskName "SP-Prod-Sync"
```

### Management Examples

```powershell
# Check current status
.\Setup-Scheduler.ps1 -Status

# Check status of custom task
.\Setup-Scheduler.ps1 -TaskName "My-SharePoint-Sync" -Status

# Remove the scheduled task
.\Setup-Scheduler.ps1 -Remove

# Remove custom named task
.\Setup-Scheduler.ps1 -TaskName "My-SharePoint-Sync" -Remove

# Interactive setup and testing
.\Setup-Examples.ps1
```

### Manual Sync Examples

```powershell
# Manual sync with default settings
.\Run-Sync.ps1

# Verbose logging for troubleshooting
.\Run-Sync.ps1 -LogLevel Verbose

# Force sync with more retries
.\Run-Sync.ps1 -ForceSync -MaxRetries 5 -RetryDelaySeconds 60

# Quick sync without environment check (not recommended for production)
.\Run-Sync.ps1 -SkipQuickTest -LogLevel Minimal

# Production sync with comprehensive logging
.\Run-Sync.ps1 -LogLevel Normal -MaxRetries 3
```

# Daily at 2:30 PM
.\Setup-Scheduler.ps1 -DailyAt "14:30"

# Custom task name and user
.\Setup-Scheduler.ps1 -TaskName "My-SharePoint-Sync" -RunAsUser "DOMAIN\ServiceAccount"
```

### Management Examples

```powershell
# Check current status
.\Setup-Scheduler.ps1 -Status

# Remove the scheduled task
.\Setup-Scheduler.ps1 -Remove

# Remove custom named task
.\Setup-Scheduler.ps1 -TaskName "My-SharePoint-Sync" -Remove
```

### Manual Sync Examples

```powershell
# Manual sync with default settings
.\Run-Sync.ps1

# Verbose logging
.\Run-Sync.ps1 -LogLevel Verbose

# Force sync with more retries
.\Run-Sync.ps1 -ForceSync -MaxRetries 5

# Quick sync without environment check
.\Run-Sync.ps1 -SkipQuickTest -LogLevel Minimal
```

## 📊 Logging and Monitoring

### Log Files

The scheduler system creates comprehensive logs for monitoring and troubleshooting:

- **Setup logs**: Console output during task creation/management
- **Sync logs**: `logs\sync_YYYYMMDD.log` (daily rotation with timestamps)
- **Status file**: `logs\sync_status.json` (real-time sync state in JSON format)
- **Windows Event Logs**: Task Scheduler events in Windows Event Viewer

### Log Levels

| Level | Description | Use Case |
|-------|-------------|----------|
| **Minimal** | Errors and critical information only | Production with minimal disk usage |
| **Normal** | Standard operations, warnings, errors | Recommended for most scenarios |
| **Verbose** | Detailed debugging and API responses | Troubleshooting and development |

### Status File Format

```json
{
  "Timestamp": "2025-08-04 14:30:15",
  "State": "SUCCESS",
  "Message": "Sync completed successfully",
  "Details": {
    "Duration": "00:02:45",
    "Attempts": "Single attempt",
    "FilesProcessed": 42,
    "AuthMethod": "AzureAD"
  },
  "ProcessId": 1234,
  "Duration": "00:02:45.123"
}
```

### Status States

| State | Description | Action Required |
|-------|-------------|-----------------|
| `STARTING` | Sync process initializing | None - normal startup |
| `RUNNING` | Sync in progress | None - operation ongoing |
| `SUCCESS` | Sync completed successfully | None - monitor for next run |
| `FAILED` | Sync failed after all retries | Check logs, fix issues |
| `RETRYING` | Retry attempt in progress | None - automatic recovery |
| `SKIPPED` | Concurrent run prevented | None - safety mechanism |
| `ERROR` | Fatal error occurred | Immediate attention required |

### Monitoring Commands

```powershell
# View recent sync logs
Get-Content .\logs\sync_$(Get-Date -Format 'yyyyMMdd').log -Tail 20

# Check current sync status
Get-Content .\logs\sync_status.json | ConvertFrom-Json | Format-List

# Monitor task status in real-time
.\Setup-Scheduler.ps1 -Status

# View task history in Windows
Get-ScheduledTask -TaskName "SharePoint-Blob-Sync" | Get-ScheduledTaskInfo

# Check Windows Event Logs
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'; ID=200} | Select-Object -First 10
```
    "Duration": "00:02:45",
    "Attempts": "Single attempt"
  },
  "ProcessId": 1234,
  "Duration": "00:02:45.123"
}
```

### Monitoring Task Status

```powershell
# PowerShell - Check task status
.\Setup-Scheduler.ps1 -Status

# Windows Task Scheduler GUI
# Run: taskschd.msc
# Navigate to Task Scheduler Library
# Look for "SharePoint-Blob-Sync" task
```

## 🛠️ Troubleshooting

### Common Issues

#### 1. "Administrator privileges required"
**Problem**: Script needs elevated permissions to manage scheduled tasks.

**Solution**:
```powershell
# Right-click PowerShell and "Run as Administrator"
# Or from elevated prompt:
.\Setup-Scheduler.ps1
```

#### 2. "Run-Sync.ps1 not found"
**Problem**: Scripts not in same directory or file permissions.

**Solutions**:
- Ensure both `Setup-Scheduler.ps1` and `Run-Sync.ps1` are in same directory
- Check file permissions and unblock if needed:
  ```powershell
  Unblock-File .\Run-Sync.ps1
  Unblock-File .\Setup-Scheduler.ps1
  ```

#### 3. "Task fails to run in Task Scheduler"
**Problem**: Scheduled task encounters permission or path issues.

**Solutions**:
```powershell
# Check task configuration
Get-ScheduledTask -TaskName "SharePoint-Blob-Sync" | Format-List

# Verify user account permissions
.\Setup-Scheduler.ps1 -Status

# Check Windows Event Viewer
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'} | Select-Object -First 5

# Review sync logs
Get-Content .\logs\sync_$(Get-Date -Format 'yyyyMMdd').log -Tail 20
```

#### 4. "Key based authentication is not permitted"
**Problem**: Storage account has key authentication disabled.

**Solution**:
```bash
# Update config.env
USE_AZURE_AD_AUTH="true"
STORAGE_ACCOUNT_KEY=""  # Remove key
```
Ensure you have "Storage Blob Data Contributor" role assigned.

#### 5. "Authentication failures with Azure AD"
**Problem**: Missing RBAC permissions or expired login.

**Solutions**:
```powershell
# Re-login to Azure
az login

# Check role assignments
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv)

# Verify service principal
.\Copy-SharePointToBlob.ps1 -Setup
```

#### 6. "Sync process appears to hang"
**Problem**: Multiple sync processes or network issues.

**Solutions**:
```powershell
# Check for running processes
Get-Process | Where-Object {$_.ProcessName -like "*powershell*" -and $_.CommandLine -like "*Run-Sync*"}

# Force kill if needed (use with caution)
Stop-Process -Name "powershell" -Force

# Check network connectivity
Test-NetConnection graph.microsoft.com -Port 443
```

### Debugging Steps

#### 1. Environment Validation
```powershell
# Run comprehensive tests
.\Quick-Test.ps1 -ShowDetails

# Check Azure CLI status
az account show
az --version
```

#### 2. Manual Sync Testing
```powershell
# Test sync manually with verbose logging
.\Run-Sync.ps1 -LogLevel Verbose -MaxRetries 1

# Test without environment checks
.\Run-Sync.ps1 -SkipQuickTest -LogLevel Verbose
```

#### 3. Check Log Files
```powershell
# View recent sync attempts
Get-Content .\logs\sync_$(Get-Date -Format 'yyyyMMdd').log -Tail 50

# Check current status
Get-Content .\logs\sync_status.json | ConvertFrom-Json | Format-List

# Monitor in real-time
Get-Content .\logs\sync_$(Get-Date -Format 'yyyyMMdd').log -Wait
```

#### 4. Verify Task Configuration
```powershell
# Detailed task information
Get-ScheduledTask -TaskName "SharePoint-Blob-Sync" | Select-Object -ExpandProperty Triggers
Get-ScheduledTask -TaskName "SharePoint-Blob-Sync" | Select-Object -ExpandProperty Actions

# Task execution history
Get-ScheduledTaskInfo -TaskName "SharePoint-Blob-Sync"
```

### Advanced Troubleshooting

#### Service Account Issues
```powershell
# Test with different user account
.\Setup-Scheduler.ps1 -Remove
.\Setup-Scheduler.ps1 -RunAsUser "DOMAIN\DifferentUser"

# Grant necessary permissions to service account:
# - Log on as a service
# - Log on as a batch job
# - Local login (if needed for testing)
```

#### Network and Connectivity
```powershell
# Test connectivity to required services
Test-NetConnection graph.microsoft.com -Port 443
Test-NetConnection login.microsoftonline.com -Port 443
Test-NetConnection your-storage-account.blob.core.windows.net -Port 443

# Check DNS resolution
Resolve-DnsName graph.microsoft.com
```

#### PowerShell Execution Policy
```powershell
# Check current execution policy
Get-ExecutionPolicy -List

# Set execution policy if needed (as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```
## 🔒 Security Best Practices

### Service Account Configuration

For production environments, use dedicated service accounts:

```powershell
# Create dedicated service account
# Grant minimal required permissions:
# - Log on as a service
# - Log on as a batch job
# - Azure AD roles for storage access

# Setup with service account
.\Setup-Scheduler.ps1 -RunAsUser "CORP\SharePointSyncService" -TaskName "Production-SP-Sync"
```

### Permissions Checklist

#### Windows Permissions (Service Account)
- ✅ Log on as a service
- ✅ Log on as a batch job  
- ✅ Read/Write access to script directory
- ✅ Read/Write access to logs directory

#### Azure Permissions
- ✅ **SharePoint**: Service principal with Sites.ReadWrite.All, Files.ReadWrite.All
- ✅ **Storage Account**: Storage Blob Data Contributor role (for RBAC auth)
- ✅ **Azure AD**: Application permissions granted with admin consent

### Configuration Security

```powershell
# Secure configuration file permissions
icacls config.env /grant:r "CORP\SharePointSyncService:(R)" /inheritance:r
icacls config.env /deny "Everyone:(F)"

# Secure log directory
icacls logs /grant:r "CORP\SharePointSyncService:(F)" /inheritance:r
```

### Monitoring and Alerting

```powershell
# Set up monitoring for failed sync operations
# Example PowerShell script to check sync status:

$status = Get-Content .\logs\sync_status.json | ConvertFrom-Json
if ($status.State -eq "FAILED") {
    # Send alert notification
    Send-MailMessage -To "admin@company.com" -Subject "SharePoint Sync Failed" -Body $status.Message
}
```

## 🏭 Production Recommendations

### 1. Scheduling Strategy

**High-Frequency (Every 5-15 minutes)**
- Best for: Critical documents, real-time requirements
- Considerations: Higher resource usage, potential rate limiting

**Medium-Frequency (Every 1-4 hours)**  
- Best for: Regular business documents, balanced approach
- Considerations: Good balance of timeliness and resource efficiency

**Low-Frequency (Daily)**
- Best for: Archive data, large bulk transfers
- Considerations: Lower resource usage, delayed availability

### 2. Environment-Specific Configurations

#### Development Environment
```powershell
# Frequent testing with verbose logging
.\Setup-Scheduler.ps1 -IntervalMinutes 30 -TaskName "Dev-SP-Sync"
# Configure Run-Sync.ps1 with -LogLevel Verbose
```

#### Production Environment
```powershell
# Conservative scheduling with retry logic
.\Setup-Scheduler.ps1 -IntervalHours 2 -TaskName "Prod-SP-Sync" -RunAsUser "CORP\ProdSyncService"
# Configure Run-Sync.ps1 with -LogLevel Normal -MaxRetries 5
```

### 3. Monitoring Integration

#### Windows Event Log Integration
```powershell
# Create custom event source for monitoring systems
New-EventLog -LogName Application -Source "SharePointSync"

# In monitoring script:
if ($syncFailed) {
    Write-EventLog -LogName Application -Source "SharePointSync" -EventId 1001 -EntryType Error -Message "Sync failed: $errorMessage"
}
```

#### SCOM/Nagios Integration
- Monitor sync status JSON file
- Alert on consecutive failures
- Track sync duration trends
- Monitor log file growth

### 4. Backup and Recovery

```powershell
# Backup configuration and credentials
Copy-Item config.env "\\backup-server\SharePointSync\config.env.$(Get-Date -Format 'yyyyMMdd')"
Copy-Item .sp_credentials "\\backup-server\SharePointSync\sp_credentials.$(Get-Date -Format 'yyyyMMdd')"

# Log retention policy
Get-ChildItem .\logs\sync_*.log | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | Remove-Item
```

## 📈 Performance Optimization

### 1. Resource Management
- **CPU**: PowerShell process typically uses minimal CPU
- **Memory**: Memory usage scales with file count and size
- **Network**: Monitor bandwidth usage during peak hours
- **Disk**: Ensure sufficient space for temporary files and logs

### 2. Optimization Tips
```powershell
# For large file volumes, consider:
# - Filtering by file type to reduce processing
# - Scheduling during off-peak hours
# - Using larger retry delays to avoid rate limiting

# Example optimized configuration:
.\Setup-Scheduler.ps1 -IntervalHours 4 -TaskName "Optimized-Sync"
# Run-Sync.ps1 with -MaxRetries 3 -RetryDelaySeconds 60
```

## 🔧 Integration Examples

### PowerShell DSC Integration
```powershell
# Example DSC configuration for automated deployment
Configuration SharePointSyncSetup {
    Script SetupScheduler {
        SetScript = {
            Set-Location "C:\SharePointSync"
            .\Setup-Scheduler.ps1 -IntervalHours 2 -RunAsUser "CORP\SyncService"
        }
        TestScript = {
            $task = Get-ScheduledTask -TaskName "SharePoint-Blob-Sync" -ErrorAction SilentlyContinue
            return $task -ne $null
        }
        GetScript = { return @{} }
    }
}
```

### Azure DevOps Integration
```yaml
# Example Azure DevOps pipeline for deployment
- task: PowerShell@2
  displayName: 'Deploy SharePoint Sync Scheduler'
  inputs:
    targetType: 'inline'
    script: |
      Set-Location $(Agent.BuildDirectory)\SharePointSync
      .\Setup-Scheduler.ps1 -IntervalHours 4 -TaskName "Production-SP-Sync"
```

## 🆘 Support and Maintenance

### Regular Maintenance Tasks

1. **Weekly**: Review sync logs for errors or warnings
2. **Monthly**: Check Azure AD service principal expiration
3. **Quarterly**: Rotate service principal client secrets
4. **Annually**: Review and update permissions

### Health Check Script
```powershell
# Create a health check script
function Test-SharePointSyncHealth {
    $results = @()
    
    # Check scheduled task
    $task = Get-ScheduledTask -TaskName "SharePoint-Blob-Sync" -ErrorAction SilentlyContinue
    $results += if ($task) { "✅ Scheduled task exists" } else { "❌ Scheduled task missing" }
    
    # Check last sync status
    if (Test-Path .\logs\sync_status.json) {
        $status = Get-Content .\logs\sync_status.json | ConvertFrom-Json
        $results += if ($status.State -eq "SUCCESS") { "✅ Last sync successful" } else { "⚠️ Last sync: $($status.State)" }
    }
    
    # Check Azure login
    $account = az account show 2>$null
    $results += if ($account) { "✅ Azure CLI logged in" } else { "❌ Azure CLI not logged in" }
    
    return $results
}

# Run health check
Test-SharePointSyncHealth
```

For additional support or issues not covered here, please refer to the main README.md file or create an issue in the project repository.
