# Test Scripts for SharePoint to Blob Storage Sync

This directory contains test and verification scripts to validate the SharePoint to Azure Blob Storage sync operation.

## Scripts

### `verify_blob_contents.sh`

Comprehensive verification script that analyzes the Azure Blob Storage container after a sync operation.

#### Features:
- 📊 **File Count**: Total number of files copied
- 📁 **Folder Structure**: Complete directory hierarchy
- 📋 **File Types**: Distribution of file extensions
- 💾 **Size Statistics**: Total and average file sizes
- 🕒 **Recent Files**: Last 10 modified files
- 📄 **File Listing**: Complete hierarchy with details

#### Usage:

```bash
# Run verification after sync
./verify_blob_contents.sh

# Show help
./verify_blob_contents.sh --help
```

#### Sample Output:

```
🧪 Azure Blob Storage Test Report
Generated: 2025-07-23 14:30:45
==================================================

📊 SUMMARY
==========================================
Total files in container: 13
Storage Account: blobtargetrg
Container: backups

📂 FOLDER STRUCTURE
==========================================
📁 subfolder1/ (3 files)
📁 subfolder2/ (2 files)

📋 FILE TYPES
==========================================
  .pdf: 8 files
  .docx: 3 files
  .xlsx: 2 files

💾 SIZE STATISTICS
==========================================
Total size: 15 MB
Average file size: 1250000 bytes

📁 FILE HIERARCHY
==========================================
📄 document1.pdf (1024000 bytes) [Modified: 2025-07-23]
  📄 nested-doc.pdf (512000 bytes) [Modified: 2025-07-23]
    📄 deep-file.xlsx (256000 bytes) [Modified: 2025-07-23]
```

## Requirements

- Azure CLI installed and configured
- Valid `config.env` file in parent directory
- Access to the Azure Storage Account specified in configuration

## Running Tests

1. **After Initial Setup:**
   ```bash
   cd test/
   ./verify_blob_contents.sh
   ```

2. **After Each Sync:**
   ```bash
   # Run sync
   ../copy_sharepoint_to_blob.sh
   
   # Verify results
   ./verify_blob_contents.sh
   ```

## Understanding the Output

### File Count
Shows total number of files successfully copied to blob storage.

### Folder Structure
Displays the directory hierarchy preserved from SharePoint, including file counts per folder.

### File Types
Breaks down files by extension to show what types of content were copied.

### Size Statistics
Provides storage usage information including total size and average file size.

### Recent Files
Shows the 10 most recently modified files, useful for tracking new additions.

### File Hierarchy
Complete listing with indentation showing the full folder structure, file sizes, and modification dates.

## Troubleshooting

### "No files found"
- Ensure the sync script has run successfully
- Check that files were actually copied to blob storage
- Verify container name in configuration

### "Container does not exist"
- Run the main sync script first: `../copy_sharepoint_to_blob.sh`
- Check Azure Storage Account configuration

### "Access denied"
- Verify Azure Storage Account key in `config.env`
- Ensure Azure CLI has proper permissions

## Integration

These test scripts can be integrated into:
- CI/CD pipelines for validation
- Monitoring systems for regular checks
- Backup verification workflows
- Automated reporting systems
