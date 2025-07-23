# SharePoint to Azure Blob Storage - Testing Guide

This guide provides comprehensive testing procedures for the SharePoint to Azure Blob Storage sync automation.

## Quick Test Commands

```bash
# 1. Test help and configuration
./copy_sharepoint_to_blob.sh --help

# 2. List current blob storage contents
./copy_sharepoint_to_blob.sh --list-contents-of-blob

# 3. Run a sync operation
./copy_sharepoint_to_blob.sh

# 4. Verify sync results
./copy_sharepoint_to_blob.sh --list-contents-of-blob

# 5. Use dedicated test script for detailed analysis
cd test/
./verify_blob_contents.sh

# 6. Run security verification
./security_check.sh

# 7. Run complete test suite
./quick_test.sh
```

## Complete Testing Workflow

### Phase 1: Initial Setup Testing

#### 1.1 Prerequisites Check
```bash
# Check Azure CLI
az --version

# Check required utilities
curl --version
jq --version

# Login to Azure
az login
```

#### 1.2 Configuration Testing
```bash
# Check if configuration exists
ls -la config.env

# If not, create from template
cp config.env.template config.env
# Edit config.env with your settings

# Test configuration loading (this will fail gracefully if config is missing)
./copy_sharepoint_to_blob.sh --help
```

#### 1.3 Service Principal Setup
```bash
# First-time setup
./copy_sharepoint_to_blob.sh --setup

# Verify service principal creation
ls -la .sp_credentials
cat .sp_credentials

# Check Azure AD
az ad sp list --display-name "sharepoint-blob-copy-sp" --query "[].{appId:appId,displayName:displayName}" --output table
```

### Phase 2: Connectivity Testing

#### 2.1 Azure Storage Testing
```bash
# Test Azure Storage connectivity
az storage container show \
    --name "backups" \
    --account-name "your-storage-account" \
    --account-key "your-key"

# If container doesn't exist, it will be created during sync
```

#### 2.2 SharePoint Access Testing
```bash
# Test SharePoint connectivity (this will show library listing if connection fails)
./copy_sharepoint_to_blob.sh --library-name "nonexistent" 2>&1 | grep -A 10 "Available libraries"
```

### Phase 3: Sync Operation Testing

#### 3.1 Basic Sync Test
```bash
# Run with default configuration
./copy_sharepoint_to_blob.sh

# Check results immediately
./copy_sharepoint_to_blob.sh --list-contents-of-blob
```

#### 3.2 File Filter Testing
```bash
# Test different file filters
./copy_sharepoint_to_blob.sh --file-filter "*.pdf"
./copy_sharepoint_to_blob.sh --file-filter "*.docx"
./copy_sharepoint_to_blob.sh --file-filter "*"

# Verify each result
./copy_sharepoint_to_blob.sh --list-contents-of-blob
```

#### 3.3 Folder Structure Testing
```bash
# Test specific folder sync
./copy_sharepoint_to_blob.sh --folder "Archive"
./copy_sharepoint_to_blob.sh --folder "Subfolder/DeepFolder"

# Test root folder (empty folder parameter)
./copy_sharepoint_to_blob.sh --folder ""
```

#### 3.4 Library Testing
```bash
# Test different libraries
./copy_sharepoint_to_blob.sh --library-name "Documents"
./copy_sharepoint_to_blob.sh --library-name "Shared Documents"
./copy_sharepoint_to_blob.sh --library-name "mylib"
```

### Phase 4: Results Verification

#### 4.1 Built-in Verification
```bash
# Use built-in blob listing
./copy_sharepoint_to_blob.sh --list-contents-of-blob
```

#### 4.2 Detailed Verification
```bash
# Use comprehensive test script
cd test/
./verify_blob_contents.sh

# Check specific aspects
./verify_blob_contents.sh | grep "Total files"
./verify_blob_contents.sh | grep "Total size"
```

#### 4.3 Azure Portal Verification
1. Open [Azure Portal](https://portal.azure.com)
2. Navigate to your Storage Account
3. Go to Containers → backups
4. Verify file structure and contents

### Phase 5: Error Scenario Testing

#### 5.1 Configuration Errors
```bash
# Test missing configuration
mv config.env config.env.backup
./copy_sharepoint_to_blob.sh
mv config.env.backup config.env

# Test invalid configuration
# Temporarily edit config.env with wrong values
```

#### 5.2 Permission Errors
```bash
# Test with wrong storage account key
# Temporarily edit config.env with incorrect storage key
./copy_sharepoint_to_blob.sh

# Test with wrong SharePoint URL
# Temporarily edit config.env with incorrect SharePoint URL
./copy_sharepoint_to_blob.sh
```

#### 5.3 Network Errors
```bash
# Test offline scenario (disconnect internet)
./copy_sharepoint_to_blob.sh

# Test with non-existent library
./copy_sharepoint_to_blob.sh --library-name "NonExistentLibrary"
```

### Phase 6: Performance Testing

#### 6.1 Large File Testing
```bash
# Test with large files (if available in SharePoint)
./copy_sharepoint_to_blob.sh --file-filter "*"

# Monitor progress
./copy_sharepoint_to_blob.sh --file-filter "*" | tee sync_log.txt
```

#### 6.2 Many Files Testing
```bash
# Test with many small files
./copy_sharepoint_to_blob.sh --folder "FolderWithManyFiles"

# Time the operation
time ./copy_sharepoint_to_blob.sh
```

## Expected Results

### Successful Sync Output
```
[2025-07-23 15:09:13] Starting SharePoint to Azure Blob Storage copy operation
============================================================
[2025-07-23 15:09:13] INFO: Configuration:
[2025-07-23 15:09:13] INFO:   SharePoint Site: https://tenant.sharepoint.com/sites/site
[2025-07-23 15:09:13] INFO:   Library Name: mylib
[2025-07-23 15:09:13] INFO:   Storage Account: storageaccount
[2025-07-23 15:09:13] INFO:   Container: backups
[2025-07-23 15:09:13] INFO:   File Filter: *.pdf
[2025-07-23 15:09:13] INFO:   SharePoint Folder: (root)
[2025-07-23 15:09:13] Checking dependencies...
[2025-07-23 15:09:13] All dependencies are available
[2025-07-23 15:09:13] INFO: Loading existing service principal credentials...
[2025-07-23 15:09:13] Using existing service principal: 12345678-1234-1234-1234-123456789abc
[2025-07-23 15:09:13] STEP: Authenticating with Service Principal
[2025-07-23 15:09:14] Successfully authenticated with Service Principal
[2025-07-23 15:09:14] INFO: Access token obtained for Microsoft Graph
[2025-07-23 15:09:14] STEP: Getting SharePoint site information
[2025-07-23 15:09:14] INFO: Tenant: tenant
[2025-07-23 15:09:14] INFO: Site: sitename
[2025-07-23 15:09:15] Successfully connected to SharePoint site: Site Name
[2025-07-23 15:09:15] INFO: Site ID: site-id-here
[2025-07-23 15:09:15] STEP: Finding document library: mylib
[2025-07-23 15:09:16] Found library 'mylib' with ID: library-id
[2025-07-23 15:09:16] INFO: Found associated drive ID: drive-id
[2025-07-23 15:09:16] STEP: Ensuring blob container exists: backups
[2025-07-23 15:09:17] Container already exists
[2025-07-23 15:09:17] STEP: Listing files in SharePoint library (including nested folders)
[2025-07-23 15:09:17] INFO: Scanning root folder
[2025-07-23 15:09:18] Found 13 files matching filter: *.pdf
  - document1.pdf (1024000 bytes)
  - folder1/document2.pdf (512000 bytes)
  - folder2/subfolder/document3.pdf (256000 bytes)
[2025-07-23 15:09:18] STEP: Starting file copy operation
[2025-07-23 15:09:18] INFO: Processing file: document1.pdf -> document1.pdf
[2025-07-23 15:09:19] ✅ Successfully uploaded: document1.pdf
[2025-07-23 15:09:19] INFO: Processing file: document2.pdf -> folder1/document2.pdf
[2025-07-23 15:09:20] ✅ Successfully uploaded: folder1/document2.pdf
[2025-07-23 15:09:20] Copy operation completed:
[2025-07-23 15:09:20]   ✅ Successfully copied: 13 files
[2025-07-23 15:09:20] 🎉 Operation completed successfully!
```

### Successful Blob Listing Output
```
📊 CONTAINER SUMMARY
==========================================
Storage Account: storageaccount
Container: backups
Total files: 13
Total size: 15 MB

📁 FILE HIERARCHY
==========================================
📁 folder1/ (5 files)
📁 folder2/ (3 files)
📁 folder2/subfolder/ (2 files)

📄 document1.pdf (1024000 bytes) [Modified: 2025-07-23]
  📄 folder1/document2.pdf (512000 bytes) [Modified: 2025-07-23]
  📄 folder2/document3.pdf (256000 bytes) [Modified: 2025-07-23]
    📄 folder2/subfolder/document4.pdf (128000 bytes) [Modified: 2025-07-23]

✅ Container listing completed!
```

## Troubleshooting Common Issues

### Issue: "Configuration file not found"
```bash
# Solution
cp config.env.template config.env
# Edit config.env with your values
```

### Issue: "Service principal authentication failed"
```bash
# Solution: Recreate service principal
rm .sp_credentials
./copy_sharepoint_to_blob.sh --setup
```

### Issue: "Library not found"
```bash
# Solution: Check available libraries
./copy_sharepoint_to_blob.sh --library-name "nonexistent" 2>&1 | grep -A 10 "Available libraries"
```

### Issue: "Container does not exist" (for --list-contents-of-blob)
```bash
# Solution: Run sync first
./copy_sharepoint_to_blob.sh
```

### Issue: "No files found"
```bash
# Solutions:
# 1. Check file filter
./copy_sharepoint_to_blob.sh --file-filter "*"

# 2. Check folder path
./copy_sharepoint_to_blob.sh --folder ""

# 3. Verify SharePoint has files
# Visit SharePoint site manually
```

## Automated Testing Script

Create a comprehensive test script:

```bash
#!/bin/bash
# File: run_all_tests.sh

echo "🧪 Running Complete Test Suite"
echo "=============================="

# Test 1: Configuration
echo "1. Testing configuration..."
./copy_sharepoint_to_blob.sh --help > /dev/null && echo "✅ Help works" || echo "❌ Help failed"

# Test 2: Blob listing
echo "2. Testing blob listing..."
./copy_sharepoint_to_blob.sh --list-contents-of-blob > /dev/null && echo "✅ Blob listing works" || echo "❌ Blob listing failed"

# Test 3: Sync operation
echo "3. Testing sync operation..."
./copy_sharepoint_to_blob.sh > /dev/null && echo "✅ Sync works" || echo "❌ Sync failed"

# Test 4: Results verification
echo "4. Testing results verification..."
cd test/
./verify_blob_contents.sh > /dev/null && echo "✅ Verification works" || echo "❌ Verification failed"

echo "🎉 Test suite completed!"
```

## Integration Testing

### CI/CD Pipeline Testing
```yaml
# Example GitHub Actions workflow
name: Test SharePoint Sync
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Azure CLI
        run: |
          curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
      - name: Test Configuration
        run: |
          ./copy_sharepoint_to_blob.sh --help
      - name: Test Blob Listing
        env:
          AZURE_STORAGE_ACCOUNT: ${{ secrets.STORAGE_ACCOUNT }}
          AZURE_STORAGE_KEY: ${{ secrets.STORAGE_KEY }}
        run: |
          ./copy_sharepoint_to_blob.sh --list-contents-of-blob
```

This comprehensive testing guide ensures your SharePoint to Azure Blob Storage sync operates reliably in all scenarios! 🎯
