# SharePoint to Azure Blob Storage Copy Script

A secure, automated script to copy files from SharePoint document libraries to Azure Blob Storage with recursive folder support and service principal authentication.

## Features

- 🔒 **Secure Authentication**: Uses Azure AD Service Principal with proper permissions
- 📁 **Recursive Folder Support**: Maintains complete folder structure in blob storage
- 🎯 **File Filtering**: Support for multiple file type filters
- 🔄 **Automated Setup**: One-command service principal creation
- 📊 **Comprehensive Logging**: Detailed logging with error handling
- ⚙️ **Configurable**: External configuration file for easy customization

## Prerequisites

- Azure CLI installed and configured
- `curl` and `jq` utilities
- Access to SharePoint site with appropriate permissions
- Azure Storage Account with access keys

### Install Dependencies (macOS)

```bash
# Install Azure CLI
brew install azure-cli

# Install required utilities
brew install curl jq
```

## Quick Start

### 1. Initial Setup

```bash
# Clone or download the script
git clone <your-repo> && cd <your-repo>

# Copy configuration template
cp config.env.template config.env

# Edit configuration with your values
nano config.env
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
STORAGE_ACCOUNT_KEY="your-storage-account-key"
CONTAINER_NAME="backups"

# File Filter (what files to copy)
FILE_FILTER="*"  # All files, or "*.pdf", "*.docx", etc.
```

### 3. Login to Azure and Setup Service Principal

```bash
# Login to Azure
az login

# Run initial setup (creates service principal with permissions)
./copy_sharepoint_to_blob.sh --setup
```

### 4. Run the Copy Operation

```bash
# Copy files with current configuration
./copy_sharepoint_to_blob.sh

# Or with custom options
./copy_sharepoint_to_blob.sh --file-filter "*.docx" --library-name "Documents"

# List what's currently in blob storage
./copy_sharepoint_to_blob.sh --list-contents-of-blob
```

## Testing and Verification

### Quick Test Suite
```bash
# Run all basic tests
./quick_test.sh
```

### Manual Testing
```bash
# Test individual components
./copy_sharepoint_to_blob.sh --help
./copy_sharepoint_to_blob.sh --list-contents-of-blob
cd test && ./verify_blob_contents.sh
```

### Comprehensive Testing
See [TESTING.md](TESTING.md) for detailed testing procedures and troubleshooting.

## Configuration Options

### File Filters

| Filter | Description |
|--------|-------------|
| `"*"` or `"*.*"` | All files |
| `"*.pdf"` | Only PDF files |
| `"*.docx"` | Only Word documents |
| `"*.{pdf,docx,xlsx}"` | Multiple file types |
| `"*.png"` | Only PNG images |

### Folder Structure

The script preserves the complete SharePoint folder hierarchy in blob storage:

```
SharePoint: /Documents/Archive/2024/Reports/file.pdf
Blob Path: Archive/2024/Reports/file.pdf
```

## Command Line Options

```bash
./copy_sharepoint_to_blob.sh [OPTIONS]

Options:
  --setup                     Create service principal and setup permissions
  --library-name NAME         SharePoint library name (overrides config)
  --file-filter FILTER        File filter (overrides config)
  --folder FOLDER             SharePoint folder path (overrides config)
  --delete-after              Delete files from SharePoint after copy
  --help                      Show detailed help
```

## Examples

```bash
# First-time setup
./copy_sharepoint_to_blob.sh --setup

# Copy all files from root folder
./copy_sharepoint_to_blob.sh

# Copy only PDFs from specific library
./copy_sharepoint_to_blob.sh --library-name "Documents" --file-filter "*.pdf"

# Copy all files from specific folder (recursively)
./copy_sharepoint_to_blob.sh --folder "Archive/2024"

# Copy Word documents and delete from SharePoint after
./copy_sharepoint_to_blob.sh --file-filter "*.docx" --delete-after
```

## Security Best Practices

### Configuration Security

- ✅ `config.env` is in `.gitignore` and never committed to version control
- ✅ Service principal credentials stored in separate `.sp_credentials` file
- ✅ Azure Storage account keys are not hardcoded in scripts
- ✅ Service principal uses minimal required permissions
- ✅ Cron job system shares secure configuration (no duplicate secrets)

### Permissions

The script creates a service principal with these Microsoft Graph permissions:
- `Sites.ReadWrite.All` - Read SharePoint sites and libraries
- `Files.ReadWrite.All` - Read and download files

### File Protection

- Configuration files are automatically excluded from git
- Temporary files are cleaned up after operations
- Error handling prevents credential exposure in logs
- Cron job logs use secure configuration without exposing secrets

### Shared Security Model

Both the main script and cron job system use the same secure configuration:

```
Main Script:               Cron Job:
config.env ←──────────────→ cron-job/sharepoint-sync-cron.sh
.sp_credentials ←──────────→ (shared service principal)
```

This ensures:
- **Single source of truth**: One config file to secure
- **No secret duplication**: Reduces risk of exposure
- **Consistent security**: Same protection across all components

## How It Works

1. **Authentication**: Uses Azure AD Service Principal with Microsoft Graph API
2. **Discovery**: Finds SharePoint site and document library via Graph API
3. **File Listing**: Recursively scans folders and applies file filters
4. **Download**: Downloads files from SharePoint with proper authentication
5. **Upload**: Uploads to Azure Blob Storage preserving folder structure
6. **Cleanup**: Removes temporary files and reports results

## Troubleshooting

### Common Issues

**"Configuration file not found"**
```bash
cp config.env.template config.env
# Edit config.env with your values
```

**"Service principal authentication failed"**
```bash
# Recreate service principal
rm .sp_credentials
./copy_sharepoint_to_blob.sh --setup
```

**"Library not found"**
- Check SharePoint library name spelling
- Verify you have access to the SharePoint site
- Try logging into SharePoint web interface to confirm

**"No files found"**
- Check file filter pattern
- Verify files exist in specified folder
- Try with `--file-filter "*"` to see all files

### Debugging

Enable verbose logging by editing `config.env`:
```bash
VERBOSE_LOGGING=true
```

Or check the detailed output during script execution.

## Files and Structure

```
.
├── copy_sharepoint_to_blob.sh     # Main script
├── config.env.template            # Configuration template
├── config.env                     # Your configuration (created from template)
├── .sp_credentials                # Service principal credentials (auto-created)
├── .gitignore                     # Protects sensitive files
└── README.md                      # This file
```

## Advanced Usage

### Automated Scheduling

For automated runs, use the secure cron job system:

```bash
cd cron-job/

# Install hourly automated sync (uses main config.env)
./setup-cron.sh --install  

# Check status
./setup-cron.sh --status

# View logs
tail -f logs/sharepoint-sync-$(date '+%Y-%m-%d').log

# Uninstall if needed
./setup-cron.sh --uninstall
```

**Security Note**: The cron job automatically uses the main `config.env` file, ensuring no secrets need to be duplicated or stored in the cron-job directory.

### Integration with CI/CD

For CI/CD pipelines, you can:
1. Store configuration in Azure Key Vault
2. Use managed identities instead of service principals
3. Trigger runs based on SharePoint webhooks

## License

This script is provided as-is for educational and operational purposes. Please review and test thoroughly before production use.
