# SharePoint to Azure Blob Storage Sync - PowerShell Edition

A comprehensive PowerShell solution for automatically synchronizing files from SharePoint document libraries to Azure Blob Storage with enterprise-grade features including error handling, logging, and Windows Task Scheduler integration.

## 📁 Solution Components

This solution consists of three main components:

### 1. 🔧 Core Sync Engine (`Copy-SharePointToBlob.ps1`)
The main synchronization script with comprehensive features:
- 🔒 **Secure Authentication**: Azure AD Service Principal with Microsoft Graph API permissions
- 📁 **Recursive Folder Traversal**: Automatically syncs all files and preserves folder structure
- 🎯 **Flexible File Filtering**: Support for multiple file type filters (*.pdf, *.docx, *.png, *, etc.)
- ⚡️ **Comprehensive Error Handling**: PowerShell-native exception handling with detailed error reporting
- 📊 **Built-in Blob Management**: List, create, and manage Azure Blob Storage containers
- 🔄 **Duplicate Detection**: Intelligent file comparison and overwrite handling
- 🗑️ **Optional Cleanup**: Configurable deletion of source files after successful copy

### 2. ⏰ Scheduling System (`Setup-Scheduler.ps1` + `Run-Sync.ps1`)
Enterprise-ready task scheduling with automation features:
- 🕒 **Flexible Scheduling**: Configure minutes, hours, or daily intervals
- 🔒 **Mutex-based Locking**: Prevents concurrent sync operations with proper resource management
- 📊 **Advanced Logging**: Daily log rotation with configurable verbosity levels (Normal, Verbose, Minimal)
- 🔁 **Retry Logic**: Configurable retry attempts with customizable delays
- 📈 **Status Monitoring**: JSON status files for integration with monitoring systems
- ⚙️ **Environment Validation**: Pre-sync health checks with comprehensive reporting
- 🛡️ **Process Safety**: Graceful handling of interruptions and system shutdowns

### 3. 🔧 Utilities & Examples
- 📋 **Quick-Test.ps1**: Environment validation and health checks
- 📖 **Setup-Examples.ps1**: Interactive configuration and testing helper
- 📚 **Comprehensive Documentation**: Detailed setup guides and troubleshooting

## 🔐 Authentication Methods

This solution supports both Azure Storage authentication methods to meet different security requirements:

### Method 1: 🔑 Storage Account Key Authentication
- **✅ Pros**: Simple setup, direct access, no additional permissions required
- **⚠️ Cons**: Requires key management, broad access permissions
- **Best for**: Development, testing, simple deployments
- **Configuration**: Set `USE_AZURE_AD_AUTH="false"` and provide `STORAGE_ACCOUNT_KEY`

### Method 2: 🎫 Azure AD/RBAC Authentication  
- **✅ Pros**: Enhanced security, granular permissions, audit trail, key rotation
- **⚠️ Cons**: More complex setup, requires Azure AD roles
- **Best for**: Production, enterprise environments, compliance requirements
- **Configuration**: Set `USE_AZURE_AD_AUTH="true"` and leave `STORAGE_ACCOUNT_KEY=""` empty

*Detailed setup instructions for both methods are provided in the [Authentication Setup](#authentication-setup) section below.*

## 📋 Prerequisites

- **Windows 10/11** or **Windows Server 2016+**
- **PowerShell 5.1** or higher (PowerShell 7+ recommended)
- **Azure CLI** installed and configured
- **Azure subscription** with appropriate permissions
- **SharePoint Online** access with document libraries
- **Azure Storage Account** for blob storage

### Install Dependencies (Windows)

**Azure CLI:**
1. Download from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-windows
2. Or use package managers:

```powershell
# Using PowerShell (requires PowerShell 5.1+)
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
Remove-Item .\AzureCLI.msi

# Using Chocolatey
choco install azure-cli

# Using winget
winget install Microsoft.AzureCLI
```

**Verify Installation:**
```powershell
az --version
$PSVersionTable.PSVersion  # Should be 5.1 or higher
```

## 🚀 Quick Start

### 1. Initial Setup

```powershell
# Clone or download the repository
git clone https://github.com/johndohoneyjr/sharepoint-blob-sync.git
cd sharepoint-blob-sync

# Copy configuration template
Copy-Item config.env.template config.env

# Edit configuration with your values
notepad config.env
```

### 2. Configure Your Settings

Edit `config.env` with your specific values:

```bash
# SharePoint Configuration
SHAREPOINT_SITE_URL="https://your-tenant.sharepoint.com/sites/your-site"
SHAREPOINT_LIBRARY_NAME="Documents"  # or "Shared Documents", "mylib", etc.
SHAREPOINT_FOLDER=""  # Leave empty for root, or "Archive/2024"

# Azure Storage Configuration
STORAGE_ACCOUNT_NAME="your-storage-account"
STORAGE_ACCOUNT_KEY="your-storage-account-key"  # Required only if USE_AZURE_AD_AUTH="false"
CONTAINER_NAME="sharepoint-files"

# Storage Authentication Method (choose one)
USE_AZURE_AD_AUTH="false"  # Set to "true" for Azure AD/RBAC, "false" for storage key

# File Filter (what files to copy)
FILE_FILTER="*.pdf"  # All files (*), PDFs (*.pdf), Word docs (*.docx), etc.

# Service Principal Configuration
SP_NAME="sharepoint-blob-sync-sp"  # Name for the service principal
```

## 🔐 Authentication Setup

### Authentication Method 1: Storage Account Key

This method uses the storage account access key for authentication. It's simpler to set up but requires storing the key in your configuration.

#### Configuration
```bash
# In config.env
USE_AZURE_AD_AUTH="false"
STORAGE_ACCOUNT_KEY="your-storage-account-access-key"
```

#### How to get your Storage Account Key:
1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to your Storage Account
3. Click **"Access keys"** in the left menu
4. Copy either **key1** or **key2** value
5. Paste it into your `config.env` file

#### Pros & Cons:
- ✅ Simple setup - no additional permissions needed
- ✅ Works immediately after configuration
- ✅ No RBAC role assignments required
- ⚠️ Requires storing sensitive key in configuration file
- ⚠️ Key has full access to storage account

### Authentication Method 2: Azure AD/RBAC

This method uses Azure Active Directory authentication with Role-Based Access Control. It's more secure but requires additional permission setup.

#### Configuration
```bash
# In config.env
USE_AZURE_AD_AUTH="true"
STORAGE_ACCOUNT_KEY=""  # Leave empty or remove this line
```

#### Required Azure RBAC Role Assignment:

You need to assign one of these roles to your user account or service principal on the Storage Account:

- **Storage Blob Data Contributor** (Recommended) - Read, write, and delete access to blob containers and data
- **Storage Blob Data Owner** - Full access including setting permissions
- **Storage Account Contributor** - Full account management (use with caution)

#### How to assign RBAC roles:

**Option 1: Azure Portal**
1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to your Storage Account
3. Click **"Access control (IAM)"** in the left menu
4. Click **"+ Add"** → **"Add role assignment"**
5. Select **"Storage Blob Data Contributor"** role
6. Select your user account or service principal
7. Click **"Save"**

**Option 2: Azure CLI**
```bash
# Get your user principal ID
az ad signed-in-user show --query id -o tsv

# Assign Storage Blob Data Contributor role
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee YOUR_USER_PRINCIPAL_ID \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/YOUR_RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/YOUR_STORAGE_ACCOUNT"
```

#### Pros & Cons:
- ✅ Enhanced security with granular permissions
- ✅ No sensitive keys stored in configuration
- ✅ Comprehensive audit trail
- ✅ Supports key rotation and managed identities
- ⚠️ More complex initial setup
- ⚠️ Requires Azure AD role assignments

### 3. Login to Azure

```powershell
# Login to Azure (interactive)
az login

# Verify you're logged in to the correct tenant/subscription
az account show
```

### 4. First-Time Setup (Service Principal Creation)

**Important**: This step is required regardless of which Azure Storage authentication method you choose. The service principal is used to access SharePoint via Microsoft Graph API.

```powershell
# Create the service principal and configure SharePoint permissions
.\Copy-SharePointToBlob.ps1 -Setup
```

This will:
- Create an Azure AD service principal
- Add Microsoft Graph API permissions (Sites.ReadWrite.All, Files.ReadWrite.All)
- Attempt to grant admin consent automatically
- Save credentials for future use

**If automatic consent fails**, you'll see instructions to manually grant permissions via Azure Portal.

### 5. Test Environment

```powershell
# Run comprehensive environment test
.\Quick-Test.ps1 -ShowDetails
```

### 6. Test Manual Sync

```powershell
# Test a manual sync
.\Copy-SharePointToBlob.ps1

# Test with different file filters
.\Copy-SharePointToBlob.ps1 -FileFilter "*.docx"
.\Copy-SharePointToBlob.ps1 -FileFilter "*"
```

## 📄 Core Script Usage (`Copy-SharePointToBlob.ps1`)

### Basic Commands

```powershell
# First-time setup (creates service principal)
.\Copy-SharePointToBlob.ps1 -Setup

# Basic sync with config.env settings
.\Copy-SharePointToBlob.ps1

# List what's currently in blob storage
.\Copy-SharePointToBlob.ps1 -ListContentsOfBlob

# Show help and usage examples
.\Copy-SharePointToBlob.ps1 -Help
```

### Advanced Commands

```powershell
# Sync specific file types
.\Copy-SharePointToBlob.ps1 -FileFilter "*.pdf"
.\Copy-SharePointToBlob.ps1 -FileFilter "*.docx"
.\Copy-SharePointToBlob.ps1 -FileFilter "*"  # All files

# Sync from specific library and folder
.\Copy-SharePointToBlob.ps1 -LibraryName "Documents" -Folder "Archive/2024"

# Override configuration settings
.\Copy-SharePointToBlob.ps1 -LibraryName "Shared Documents" -FileFilter "*.png"

# Sync with cleanup (DANGER: deletes files from SharePoint after copy)
.\Copy-SharePointToBlob.ps1 -DeleteAfter
```

### Command Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-Setup` | Create service principal and setup permissions | `.\Copy-SharePointToBlob.ps1 -Setup` |
| `-ListContentsOfBlob` | List all files in blob storage container | `.\Copy-SharePointToBlob.ps1 -ListContentsOfBlob` |
| `-LibraryName` | Override SharePoint library name | `-LibraryName "Documents"` |
| `-FileFilter` | Override file filter pattern | `-FileFilter "*.pdf"` |
| `-Folder` | Override SharePoint folder path | `-Folder "Archive/2024"` |
| `-DeleteAfter` | Delete from SharePoint after copy (use with caution) | `-DeleteAfter` |
| `-Help` | Show detailed help information | `-Help` |

## ⏰ Scheduling Operations

### Setup Windows Task Scheduler

The solution includes enterprise-ready scheduling with the `Setup-Scheduler.ps1` script:

```powershell
# Basic setup - every 5 minutes (default)
.\Setup-Scheduler.ps1

# Every 10 minutes
.\Setup-Scheduler.ps1 -IntervalMinutes 10

# Every 2 hours
.\Setup-Scheduler.ps1 -IntervalHours 2

# Daily at 9:00 AM
.\Setup-Scheduler.ps1 -DailyAt "09:00"

# Custom task name and start immediately
.\Setup-Scheduler.ps1 -TaskName "My-SharePoint-Sync" -StartNow
```

### Scheduler Management

```powershell
# Check task status
.\Setup-Scheduler.ps1 -Status

# Remove scheduled task
.\Setup-Scheduler.ps1 -Remove

# Remove specific task
.\Setup-Scheduler.ps1 -TaskName "My-SharePoint-Sync" -Remove
```

### Scheduler Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `-IntervalMinutes` | Run every X minutes | 5 | `-IntervalMinutes 15` |
| `-IntervalHours` | Run every X hours | - | `-IntervalHours 4` |
| `-DailyAt` | Run daily at specific time (HH:MM) | - | `-DailyAt "14:30"` |
| `-TaskName` | Name of scheduled task | "SharePoint-Blob-Sync" | `-TaskName "My-Sync"` |
| `-RunAsUser` | User account to run task | Current user | `-RunAsUser "DOMAIN\ServiceAccount"` |
| `-LogPath` | Path for scheduler logs | `.\logs\scheduler.log` | `-LogPath "C:\Logs\sync.log"` |
| `-StartNow` | Start task immediately after creation | - | `-StartNow` |
| `-Status` | Show task status | - | `-Status` |
| `-Remove` | Remove existing task | - | `-Remove` |

## 🔄 Sync Runner (`Run-Sync.ps1`)

The `Run-Sync.ps1` script is automatically called by the Windows Task Scheduler but can also be run manually for testing:

### Manual Execution

```powershell
# Basic scheduled run
.\Run-Sync.ps1

# Verbose logging
.\Run-Sync.ps1 -LogLevel Verbose

# Force sync with more retries
.\Run-Sync.ps1 -ForceSync -MaxRetries 5

# Skip environment validation
.\Run-Sync.ps1 -SkipQuickTest -LogLevel Minimal
```

### Run-Sync Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `-LogLevel` | Logging verbosity (Minimal/Normal/Verbose) | Normal | `-LogLevel Verbose` |
| `-ForceSync` | Force sync even if last sync was recent | - | `-ForceSync` |
| `-SkipQuickTest` | Skip environment validation | - | `-SkipQuickTest` |
| `-MaxRetries` | Maximum retry attempts on failure | 3 | `-MaxRetries 5` |
| `-RetryDelaySeconds` | Delay between retry attempts | 30 | `-RetryDelaySeconds 60` |

## 📊 Logging and Monitoring

### Log Files

The solution creates comprehensive logs in the `logs\` directory:

- **Scheduler logs**: `logs\scheduler.log` - Setup and management operations
- **Sync logs**: `logs\sync_YYYYMMDD.log` - Daily sync operation logs with rotation
- **Status file**: `logs\sync_status.json` - Current sync state in JSON format

### Log Levels

- **Minimal**: Errors and critical information only
- **Normal**: Standard operations, warnings, and errors
- **Verbose**: Detailed debugging information and API responses

### Status File Format

```json
{
  "Timestamp": "2025-08-04 14:30:15",
  "State": "SUCCESS",
  "Message": "Sync completed successfully",
  "Details": {
    "Duration": "00:02:45",
    "Attempts": "Single attempt"
  },
  "ProcessId": 1234,
  "Duration": "00:02:45.123"
}
```

### Monitoring Commands

```powershell
# View recent sync logs
Get-Content .\logs\sync_$(Get-Date -Format 'yyyyMMdd').log -Tail 20

# Check current sync status
Get-Content .\logs\sync_status.json | ConvertFrom-Json

# Monitor task status
.\Setup-Scheduler.ps1 -Status
```

## 🔧 Configuration Reference

### config.env File

```bash
# SharePoint Configuration
SHAREPOINT_SITE_URL="https://your-tenant.sharepoint.com/sites/your-site"
SHAREPOINT_LIBRARY_NAME="Documents"
SHAREPOINT_FOLDER=""  # Leave empty for root folder, or specify like "Archive/2024"

# Azure Storage Configuration
STORAGE_ACCOUNT_NAME="your-storage-account"
STORAGE_ACCOUNT_KEY="your-storage-account-key"  # Only needed if USE_AZURE_AD_AUTH="false"
CONTAINER_NAME="sharepoint-files"

# Authentication Method
USE_AZURE_AD_AUTH="false"  # Set to "true" for Azure AD/RBAC, "false" for storage key

# File Filter Configuration
# Examples:
#   "*" or "*.*"         - All files
#   "*.pdf"              - Only PDF files
#   "*.png"              - Only PNG files
#   "*.docx"             - Only Word documents
#   "*.{pdf,docx,xlsx}"  - Multiple file types (PowerShell pattern)
FILE_FILTER="*"

# Copy Configuration
DELETE_AFTER_COPY=false  # Set to true to delete files from SharePoint after copying (use with caution)

# Service Principal Configuration
SP_NAME="sharepoint-blob-sync-sp"  # Name for the service principal

# Optional Advanced Settings
FORCE_RECREATE_SP=false  # Set to true to recreate service principal
VERBOSE_LOGGING=false    # Set to true for detailed logging
```

### File Filter Examples

| Pattern | Description | Matches |
|---------|-------------|---------|
| `*` or `*.*` | All files | All files |
| `*.pdf` | PDF files only | document.pdf, report.pdf |
| `*.docx` | Word documents | letter.docx, proposal.docx |
| `*.png` | PNG images | logo.png, screenshot.png |
| `*.{pdf,docx}` | Multiple types | Both PDF and Word files |
| `Report_*` | Files starting with "Report_" | Report_2024.pdf, Report_Q1.docx |

## 🛠️ Troubleshooting

### Common Issues and Solutions

#### 1. "Key based authentication is not permitted on this storage account"

**Problem**: Your storage account has key-based authentication disabled for security.

**Solution**: Switch to Azure AD authentication:
```bash
# In config.env
USE_AZURE_AD_AUTH="true"
STORAGE_ACCOUNT_KEY=""  # Remove or leave empty
```

Ensure you have the **Storage Blob Data Contributor** role assigned to your account.

#### 2. "Not logged in to Azure"

**Problem**: Azure CLI authentication has expired.

**Solution**:
```powershell
az login
# Verify correct subscription
az account show
```

#### 3. "Service Principal authentication failed"

**Problem**: Service principal permissions not granted or expired.

**Solutions**:
1. **Re-run setup**: `.\Copy-SharePointToBlob.ps1 -Setup`
2. **Manual consent**: Go to Azure Portal → App registrations → Your app → API permissions → Grant admin consent
3. **Check permissions**: Ensure Sites.ReadWrite.All and Files.ReadWrite.All are granted

#### 4. "Library not found"

**Problem**: SharePoint library name doesn't match.

**Solutions**:
1. **Check library name**: Verify exact name in SharePoint (case-sensitive)
2. **List available libraries**: The script will show available libraries when it fails
3. **Try common names**: "Documents", "Shared Documents", "Site Assets"

#### 5. "Cannot access SharePoint site"

**Problem**: Service principal doesn't have access to SharePoint site.

**Solutions**:
1. **Verify site URL**: Check the exact URL in `config.env`
2. **Check permissions**: Ensure service principal has Sites.ReadWrite.All permission
3. **Grant site access**: You may need to add the service principal to SharePoint site permissions

#### 6. "Task fails to run in Task Scheduler"

**Problem**: Scheduled task encounters permission or path issues.

**Solutions**:
1. **Check user account**: Ensure the task runs as a user with appropriate permissions
2. **Verify paths**: Use absolute paths in task configuration
3. **Check logs**: Review `logs\sync_*.log` files for detailed error information
4. **Test manually**: Run `.\Run-Sync.ps1` manually to identify issues

### Debug Commands

```powershell
# Comprehensive environment test
.\Quick-Test.ps1 -ShowDetails

# Test with verbose logging
.\Copy-SharePointToBlob.ps1 -Help  # Show all options
.\Run-Sync.ps1 -LogLevel Verbose

# Check Azure login status
az account show

# List storage account permissions
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) --scope "/subscriptions/$(az account show --query id -o tsv)"

# Verify service principal
az ad sp show --id $(Get-Content .sp_credentials | Select-String "SP_CLIENT_ID" | ForEach-Object { $_.Line.Split('"')[1] })
```

### Getting Help

1. **Check logs**: Always check the `logs\` directory for detailed error information
2. **Run tests**: Use `.\Quick-Test.ps1 -ShowDetails` to validate your environment
3. **Verify permissions**: Ensure all Azure AD and RBAC permissions are correctly assigned
4. **Test manually**: Run operations manually before setting up scheduling

### Advanced Troubleshooting

For complex issues, enable verbose logging and check:

1. **Azure AD service principal permissions**
2. **Storage account RBAC roles**
3. **SharePoint site access permissions**
4. **Network connectivity to Microsoft Graph and Azure Storage**
5. **PowerShell execution policies**

## 🔒 Security Best Practices

### Service Principal Security
- Use dedicated service principal for this application only
- Regularly rotate client secrets (recommended: every 6 months)
- Apply principle of least privilege
- Monitor service principal usage in Azure AD logs

### Storage Account Security
- Use Azure AD/RBAC authentication when possible
- If using storage keys, rotate them regularly
- Consider using Managed Identity in Azure environments
- Enable storage account logging and monitoring

### Configuration Security
- Never commit `config.env` to version control
- Store configuration files with restricted permissions
- Use Azure Key Vault for sensitive configuration in enterprise environments
- Regularly audit access to configuration files

### Network Security
- Consider using private endpoints for storage accounts
- Implement network restrictions if needed
- Monitor network traffic for unusual patterns

## 📚 Additional Resources

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [Microsoft Graph API](https://docs.microsoft.com/en-us/graph/)
- [Azure Blob Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Windows Task Scheduler](https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🔄 Version History

- **v2.0** - Added Windows Task Scheduler integration, RBAC authentication, comprehensive logging
- **v1.0** - Initial PowerShell implementation with basic sync functionality

---

**Note**: This is the PowerShell implementation. For the Bash version, see the `bash-implementation/` directory.
