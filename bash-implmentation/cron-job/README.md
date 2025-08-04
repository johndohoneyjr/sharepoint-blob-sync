# SharePoint to Azure Blob Storage - Automated Cron Job

This directory contains the automated scheduling system for SharePoint to Azure Blob Storage synchronization.

## Features

- 🕐 **Hourly Automated Sync**: Runs every hour to copy new/modified files
- 🔒 **Secure Configuration**: Uses parent directory's config.env (no secrets in cron-job folder)
- 📊 **Comprehensive Logging**: Detailed logs with automatic rotation
- 🔒 **Lock File Protection**: Prevents multiple instances from running simultaneously
- 📧 **Notification Support**: Optional email/Slack/Teams notifications
- ⚙️ **Easy Management**: Simple install/uninstall/status commands

## Prerequisites

1. **Main Script Setup**: Ensure the main SharePoint sync script is working:
   ```bash
   cd ..
   ./copy_sharepoint_to_blob.sh --setup  # First time only
   ./copy_sharepoint_to_blob.sh          # Test sync
   ```

2. **Configuration**: The main `config.env` file must exist in the parent directory:
   ```bash
   # Ensure config.env exists in parent directory
   ls -la ../config.env
   ```

## Security Model

### 🔒 Secure Configuration Approach

The cron job system uses a secure configuration model:

- **No secrets in cron-job directory**: All sensitive data stays in parent `config.env`
- **Git-safe**: cron-job files can be safely committed to version control
- **Shared configuration**: Uses the same config as the main script
- **Credential isolation**: Service principal credentials remain in parent `.sp_credentials`

### Configuration Flow
```
cron-job/sharepoint-sync-cron.sh
    ↓ (loads config from)
../config.env  (contains secrets - git-ignored)
    ↓ (references)
../.sp_credentials  (service principal - git-ignored)
```

## Files

- **`sharepoint-sync-cron.sh`** - Main cron-optimized sync script (uses parent config)
- **`setup-cron.sh`** - Crontab management script
- **`logs/`** - Directory for log files (created automatically)

## Quick Start

### 1. Initial Setup (One-time)

First, ensure you have completed the initial setup from the parent directory:

```bash
# Go to parent directory and run initial setup
cd ..
./copy_sharepoint_to_blob.sh --setup
```

This creates the service principal and saves credentials to `.sp_credentials`.

### 2. Verify Configuration

Ensure the main configuration file exists and is properly configured:

```bash
# Check if config exists in parent directory
ls -la ../config.env

# Verify configuration by testing the main script
cd ..
./copy_sharepoint_to_blob.sh --help
cd cron-job
```

### 3. Install the Cron Job

```bash
# Make scripts executable
chmod +x *.sh

# Install hourly cron job
./setup-cron.sh --install
```

### 4. Verify Installation

```bash
# Check cron job status
./setup-cron.sh --status

# View current crontab
crontab -l

# Test the cron script manually
./sharepoint-sync-cron.sh

# Check logs
tail -f logs/sharepoint-sync-$(date '+%Y-%m-%d').log
```

# Install hourly cron job
./setup-cron.sh --install

# Or install with custom schedule (every 2 hours)
./setup-cron.sh --install-custom "0 */2 * * *"
```

### 4. Verify Installation

```bash
# Check cron job status
./setup-cron.sh --status

# Test the sync script manually
./setup-cron.sh --test
```

## Cron Schedule Examples

| Schedule | Cron Expression | Description |
|----------|----------------|-------------|
| Every hour | `0 * * * *` | Run at the top of every hour |
| Every 2 hours | `0 */2 * * *` | Run every 2 hours |
| Every 6 hours | `0 */6 * * *` | Run every 6 hours |
| Twice daily | `0 9,17 * * *` | Run at 9 AM and 5 PM |
| Daily at 2 AM | `0 2 * * *` | Run once per day at 2 AM |
| Weekdays only | `0 9 * * 1-5` | Run at 9 AM, Monday-Friday |

## Configuration

The cron job uses the main configuration file located at `../config.env`. This ensures:

- **No secrets in cron-job directory**: All sensitive data remains secure
- **Single source of truth**: Both main script and cron job use same config
- **Git safety**: No risk of committing secrets

### Configuration Variables Used by Cron Job

From `../config.env`:
```bash
# SharePoint Configuration
SHAREPOINT_SITE_URL="https://tenant.sharepoint.com/sites/site"
SHAREPOINT_LIBRARY_NAME="Documents"
SHAREPOINT_FOLDER=""  # Optional: specific folder path

# Azure Storage Configuration  
STORAGE_ACCOUNT_NAME="storageaccount"
STORAGE_ACCOUNT_KEY="your-storage-key"
CONTAINER_NAME="backups"

# File Filter Configuration
FILE_FILTER="*"  # What files to sync

# Cron-Specific Settings (optional)
LOG_RETENTION_DAYS="30"    # How long to keep log files
SYNC_TIMEOUT="3600"        # Max sync time in seconds
MAX_RETRIES="3"            # Number of retries on failure
RETRY_DELAY="300"          # Delay between retries in seconds
```

### Notification Configuration (Optional)

You can enable notifications by adding these to `../config.env`:

```bash
# Email notifications (configure your mail system)
EMAIL_NOTIFICATIONS="true"
EMAIL_TO="admin@example.com"
EMAIL_FROM="noreply@example.com"

# Slack notifications (get webhook URL from Slack)
SLACK_NOTIFICATIONS="true"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# Microsoft Teams notifications (get webhook URL from Teams)
TEAMS_NOTIFICATIONS="true"
TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/YOUR/TEAMS/WEBHOOK"
```

### File Filters
- `"*"` - All files
- `"*.pdf"` - Only PDF files
- `"*.{pdf,docx,xlsx}"` - Multiple file types
- `"*.png"` - Only PNG files

## Monitoring and Logs

### Log Files
Logs are stored in the `logs/` directory:
- `sharepoint-sync-YYYY-MM-DD.log` - Daily sync logs
- `sharepoint-sync-error-YYYY-MM-DD.log` - Error logs only

### View Recent Logs
```bash
# View today's log
tail -f logs/sharepoint-sync-$(date '+%Y-%m-%d').log

# View recent errors
tail -f logs/sharepoint-sync-error-$(date '+%Y-%m-%d').log

# Check log directory
ls -la logs/
```

### Check Cron Job Status
```bash
# Show if cron job is installed
./setup-cron.sh --status

# View crontab directly
crontab -l
```

## Management Commands

### Install/Update Cron Job
```bash
# Install standard hourly sync
./setup-cron.sh --install

# Install custom schedule
./setup-cron.sh --install-custom "0 */3 * * *"  # Every 3 hours
```

### Remove Cron Job
```bash
# Safely remove the cron job
./setup-cron.sh --uninstall

# Verify removal
./setup-cron.sh --status
```

**Note**: The uninstall command:
- ✅ Safely removes only the SharePoint sync cron job
- ✅ Preserves other existing cron jobs 
- ✅ Handles cases where no cron job exists gracefully
- ✅ Provides confirmation of successful removal
- ⚠️ **Does NOT** remove log files (manual cleanup if needed)

### Test Sync Manually
```bash
# Test the sync process
./setup-cron.sh --test

# Run sync script directly (with full output)
./sharepoint-sync-cron.sh
```

### Check Status and Logs
```bash
# Check if cron job is installed and view recent activity
./setup-cron.sh --status

# View real-time logs
tail -f logs/sharepoint-sync-$(date '+%Y-%m-%d').log

# View error logs only
tail -f logs/sharepoint-sync-error-$(date '+%Y-%m-%d').log
```

## Maintenance and Cleanup

### Log File Management
```bash
# View log file sizes
du -h logs/

# Manual cleanup of old logs (keeps last 7 days)
find logs/ -name "*.log" -type f -mtime +7 -delete

# View disk usage
df -h .
```

### Complete Removal
If you want to completely remove the SharePoint sync setup:

```bash
# 1. Remove the cron job
./setup-cron.sh --uninstall

# 2. Remove log files (optional)
rm -rf logs/

# 3. Remove service principal (from parent directory)
cd .. && rm -f .sp_credentials

# 4. Remove cron-job directory (if desired)
cd .. && rm -rf cron-job/
```

### Backup Configuration
```bash
# Backup your configuration
cp config.env config.env.backup

# Backup service principal credentials
cp ../.sp_credentials .sp_credentials.backup
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x *.sh
   ```

2. **Service Principal Not Found**
   ```bash
   cd .. && ./copy_sharepoint_to_blob.sh --setup
   ```

3. **Commands Not Found in Cron**
   - The script automatically sets PATH for common locations
   - Check that Azure CLI is installed: `which az`

4. **Sync Failing**
   ```bash
   # Test manually first
   ./setup-cron.sh --test
   
   # Check error logs
   cat logs/sharepoint-sync-error-$(date '+%Y-%m-%d').log
   ```

### Debug Mode
Run the sync script directly to see detailed output:
```bash
./sharepoint-sync-cron.sh
```

### Check Cron Logs
On macOS, cron logs to system log:
```bash
log show --style syslog --predicate 'process == "cron"' --last 1h
```

## Features

- ✅ **Automated hourly sync** (or custom schedule)
- ✅ **Recursive folder traversal** with preserved structure
- ✅ **Comprehensive logging** with daily log files
- ✅ **Lock file protection** prevents multiple instances
- ✅ **Environment detection** optimized for cron
- ✅ **Error handling** with notifications
- ✅ **Log rotation** (keeps 30 days by default)
- ✅ **Easy configuration** via config.env file

## Security Notes

- Service principal credentials are stored in parent directory `.sp_credentials`
- Log files may contain file paths but no sensitive data
- Azure storage account key is in `config.env` - protect this file
- Consider using Azure Key Vault for production environments

## Production Recommendations

1. **Use Azure Key Vault** for storage account keys
2. **Set up monitoring** and alerting
3. **Configure notifications** (email, Slack, Teams)
4. **Regular backup** of configuration files
5. **Monitor log disk usage** in production environments
6. **Test sync process** before production deployment
