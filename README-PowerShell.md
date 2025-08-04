# SharePoint to Azure Blob Storage Sync - PowerShell Version

A comprehensive PowerShell solution for automatically synchronizing files from SharePoint document libraries to Azure Blob Storage with enterprise-grade features including error handling, logging, notifications, and scheduling capabilities.

## 🚀 Features

- **Recursive Folder Traversal**: Automatically syncs all files and preserves folder structure
- **Service Principal Authentication**: Secure, automated authentication using Azure AD service principals
- **Flexible File Filtering**: Support for multiple file type filters (*.pdf, *.docx, *.png, *, etc.)
- **Comprehensive Error Handling**: PowerShell-native exception handling with detailed error reporting
- **Advanced Logging**: Color-coded console output with file-based logging and retention policies
- **Scheduled Execution**: Windows Task Scheduler integration for automated sync operations
- **Notification System**: Email, webhook, and Windows Event Log notifications
- **Security Validation**: Built-in security checks and best practices enforcement
- **Process Management**: Lock files prevent concurrent executions with timeout handling
- **Retry Logic**: Configurable retry attempts with exponential backoff
- **Network Resilience**: Automatic handling of network timeouts and connectivity issues

## 📋 Prerequisites

- **Windows 10/11** or **Windows Server 2016+**
- **PowerShell 5.1** or higher (PowerShell 7+ recommended)
- **Azure CLI** installed and configured
- **Azure subscription** with appropriate permissions
- **SharePoint Online** access with document libraries
- **Azure Storage Account** for blob storage

## 🔧 Installation & Setup

### 1. Clone or Download

```powershell
git clone https://github.com/johndohoneyjr/sharepoint-blob-sync.git
cd sharepoint-blob-sync
```

### 2. Configure Settings

```powershell
# Copy the template and customize your settings
Copy-Item config.env.template config.env
notepad config.env
```

**Required Configuration:**
```bash
# SharePoint Configuration
SHAREPOINT_SITE_URL="https://yourtenant.sharepoint.com/sites/yoursite"
SHAREPOINT_LIBRARY_NAME="Documents"
SHAREPOINT_FOLDER=""  # Optional: specific folder path

# Azure Storage Configuration
STORAGE_ACCOUNT_NAME="yourstorageaccount"
STORAGE_ACCOUNT_KEY="your-storage-account-key"
CONTAINER_NAME="sharepoint-files"

# Service Principal Configuration
SP_NAME="SharePoint-Blob-Sync-SP"

# Sync Configuration
FILE_FILTER="*.pdf"  # Supports *.pdf, *.docx, *.png, *, etc.
DELETE_AFTER_COPY="false"  # Use with caution
VERBOSE_LOGGING="false"

# Optional: Notification Configuration
SMTP_SERVER="smtp.yourdomain.com"
SMTP_FROM="sync@yourdomain.com"
SMTP_TO="admin@yourdomain.com"
SMTP_USERNAME="your-smtp-username"
SMTP_PASSWORD="your-smtp-password"
SMTP_PORT="587"
SMTP_USE_SSL="true"

WEBHOOK_URL="https://hooks.slack.com/services/..."  # Optional: Slack/Teams webhook

# Advanced Configuration
LOG_RETENTION_DAYS="30"
SYNC_TIMEOUT="3600"  # seconds
MAX_RETRIES="3"
RETRY_DELAY="300"  # seconds
```

### 3. Initial Setup

```powershell
# Run security validation
.\Security-Check.ps1

# Test environment setup
.\Quick-Test.ps1

# Create service principal and configure permissions
.\Copy-SharePointToBlob.ps1 -Setup
```

### 4. Test Sync Operation

```powershell
# Perform initial sync
.\Copy-SharePointToBlob.ps1

# List files in blob storage
.\Copy-SharePointToBlob.ps1 -ListContentsOfBlob
```

## 🎯 Usage Examples

### Basic Operations

```powershell
# Copy all PDF files with default settings
.\Copy-SharePointToBlob.ps1

# Copy Word documents from specific library
.\Copy-SharePointToBlob.ps1 -LibraryName "Shared Documents" -FileFilter "*.docx"

# Copy all files from specific folder
.\Copy-SharePointToBlob.ps1 -Folder "Archive" -FileFilter "*"

# Copy files and delete from SharePoint (use with caution)
.\Copy-SharePointToBlob.ps1 -DeleteAfter

# List current blob storage contents
.\Copy-SharePointToBlob.ps1 -ListContentsOfBlob
```

### Advanced Operations

```powershell
# Copy with custom filters
.\Copy-SharePointToBlob.ps1 -FileFilter "*.png" -LibraryName "Images"

# Multiple file types (using wildcard patterns)
.\Copy-SharePointToBlob.ps1 -FileFilter "*" -Folder "Mixed Content"

# Show detailed help
Get-Help .\Copy-SharePointToBlob.ps1 -Full
```

### Security and Validation

```powershell
# Run comprehensive security check
.\Security-Check.ps1 -Detailed

# Quick environment validation
.\Quick-Test.ps1 -Verbose

# Fix common security issues automatically
.\Security-Check.ps1 -Fix
```

## ⏰ Scheduled Execution

### Windows Task Scheduler Setup

```powershell
# Create daily scheduled task (requires Administrator privileges)
.\Setup-ScheduledTask.ps1

# Create hourly scheduled task
.\Setup-ScheduledTask.ps1 -Schedule Hourly -StartTime "09:00"

# Create test task (runs once in 2 minutes)
.\Setup-ScheduledTask.ps1 -TestRun

# Advanced scheduling with custom settings
.\Setup-ScheduledTask.ps1 -TaskName "SP-Sync-Production" -Schedule Daily -StartTime "02:00" -RunAsUser "DOMAIN\ServiceAccount"
```

### Manual Scheduled Task Execution

```powershell
# For automated environments, use the dedicated scheduled task script
.\SharePoint-Sync-ScheduledTask.ps1 -Quiet

# With custom configuration
.\SharePoint-Sync-ScheduledTask.ps1 -ConfigPath "C:\Config\production.env" -LogPath "C:\Logs\SPSync"

# With retry settings
.\SharePoint-Sync-ScheduledTask.ps1 -MaxRetries 5 -RetryDelaySeconds 600 -TimeoutSeconds 7200
```

## 📁 File Structure

```
sharepoint-blob-sync/
├── Copy-SharePointToBlob.ps1          # Main sync script (PowerShell)
├── SharePoint-Sync-ScheduledTask.ps1  # Scheduled task version
├── Setup-ScheduledTask.ps1             # Task Scheduler setup
├── Quick-Test.ps1                      # Environment validation
├── Security-Check.ps1                  # Security validation
├── config.env.template                 # Configuration template
├── config.env                          # Your configuration (create from template)
├── .sp_credentials                     # Service principal credentials (auto-generated)
├── .gitignore                          # Git ignore file
├── logs/                               # Log files directory
│   ├── sharepoint-sync-2025-08-01.log
│   └── sharepoint-sync-error-2025-08-01.log
└── README.md                           # This file
```

## 🔐 Security Features

### Built-in Security Validations

- **Sensitive File Detection**: Automatically scans for and warns about sensitive files
- **Git Ignore Validation**: Ensures sensitive files are properly excluded from version control
- **File Permission Checks**: Validates access controls on configuration files
- **Configuration Security**: Checks for placeholder values and hardcoded secrets
- **Service Principal Security**: Validates credentials and rotation policies
- **Network Security**: Validates TLS settings and proxy configurations

### Best Practices Implemented

- **Least Privilege Access**: Service principal with minimal required permissions
- **Credential Rotation**: Automated credential lifecycle management
- **Secure Logging**: Sensitive information excluded from log files
- **Process Isolation**: Lock files prevent concurrent executions
- **Timeout Management**: Prevents runaway processes
- **Error Containment**: Comprehensive exception handling

## 📊 Monitoring & Logging

### Log Files

- **Main Logs**: `logs/sharepoint-sync-YYYY-MM-DD.log`
- **Error Logs**: `logs/sharepoint-sync-error-YYYY-MM-DD.log`
- **Automatic Cleanup**: Configurable retention policy (default: 30 days)

### Notification Options

1. **Email Notifications**: SMTP-based alerts for success/failure
2. **Webhook Integration**: Slack, Teams, or custom webhook support
3. **Windows Event Logs**: Integration with Windows Event Viewer
4. **Console Output**: Color-coded real-time status updates

### Monitoring Commands

```powershell
# View recent log entries
Get-Content "logs\sharepoint-sync-$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 20

# Check scheduled task status
Get-ScheduledTaskInfo -TaskName "SharePoint-Blob-Sync"

# Monitor task execution
Get-ScheduledTask -TaskName "SharePoint-Blob-Sync" | Get-ScheduledTaskInfo
```

## 🛠️ Troubleshooting

### Common Issues

**1. Authentication Failures**
```powershell
# Re-run setup to refresh credentials
.\Copy-SharePointToBlob.ps1 -Setup

# Check Azure CLI login
az account show
```

**2. Permission Errors**
```powershell
# Validate service principal permissions
.\Security-Check.ps1 -Detailed

# Check Azure AD admin consent
# Navigate to Azure Portal > Azure AD > App registrations > Your App > API permissions
```

**3. Network Connectivity**
```powershell
# Test network connectivity
Test-NetConnection graph.microsoft.com -Port 443
Test-NetConnection yourstorageaccount.blob.core.windows.net -Port 443
```

**4. Configuration Issues**
```powershell
# Validate environment
.\Quick-Test.ps1 -Verbose

# Check configuration syntax
Get-Content config.env | Where-Object { $_ -match '=' }
```

### Advanced Troubleshooting

**Enable Debug Logging**
```powershell
# Temporary debug mode
$VerbosePreference = 'Continue'
.\Copy-SharePointToBlob.ps1 -Verbose
```

**Manual Service Principal Testing**
```powershell
# Test authentication manually
$tokenUrl = "https://login.microsoftonline.com/YOUR_TENANT_ID/oauth2/v2.0/token"
# Use Invoke-RestMethod to test token acquisition
```

**Task Scheduler Debugging**
```powershell
# View task history
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'; ID=201}

# Test task execution manually
Start-ScheduledTask -TaskName "SharePoint-Blob-Sync"
```

## 🔄 Migration from Bash Version

If you're migrating from the bash version:

1. **Configuration Compatibility**: Your existing `config.env` file should work as-is
2. **Service Principal**: Existing `.sp_credentials` file is compatible
3. **Scheduling**: Replace cron jobs with Windows Task Scheduler
4. **Logging**: Log format is similar but with PowerShell-specific enhancements

### Migration Steps

```powershell
# 1. Backup existing configuration
Copy-Item config.env config.env.backup
Copy-Item .sp_credentials .sp_credentials.backup

# 2. Test PowerShell version
.\Quick-Test.ps1

# 3. Run test sync
.\Copy-SharePointToBlob.ps1 -FileFilter "*.pdf"

# 4. Setup scheduled task
.\Setup-ScheduledTask.ps1

# 5. Remove old cron jobs (if any)
# crontab -e  # Remove old entries
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/johndohoneyjr/sharepoint-blob-sync/issues)
- **Discussions**: [GitHub Discussions](https://github.com/johndohoneyjr/sharepoint-blob-sync/discussions)
- **Wiki**: [Project Wiki](https://github.com/johndohoneyjr/sharepoint-blob-sync/wiki)

## 🎯 Roadmap

- [ ] Azure Key Vault integration for credential management
- [ ] PowerShell Gallery module distribution
- [ ] Azure DevOps pipeline templates
- [ ] Incremental sync with change detection
- [ ] Multi-tenant support
- [ ] PowerBI integration for sync analytics
- [ ] Docker container support
- [ ] Azure Functions serverless execution

## 📝 Changelog

### Version 2.0 (PowerShell Version)
- Complete PowerShell implementation
- Enhanced error handling and logging
- Windows Task Scheduler integration
- Advanced security validations
- Notification system improvements
- Process management and locking
- Retry logic with exponential backoff
- Comprehensive documentation

### Version 1.0 (Bash Version)
- Initial bash implementation
- Basic SharePoint to Blob sync
- Service principal authentication
- Cron job scheduling

---

**Made with ❤️ for enterprise SharePoint and Azure integration**
