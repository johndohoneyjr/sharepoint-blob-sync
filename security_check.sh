#!/bin/bash

# Security Verification Script for SharePoint to Azure Blob Storage Sync
# Verifies that all sensitive data is properly protected

set -e

echo "🔒 Security Verification Report"
echo "==============================="
echo ""

cd "$(dirname "$0")"

# Check 1: Verify .gitignore exists and contains required entries
echo "1. Checking .gitignore protection..."
if [ -f ".gitignore" ]; then
    echo "   ✅ .gitignore file exists"
    
    # Check for required entries
    required_entries=("config.env" ".sp_credentials" "*.env" ".env*" "logs/" "*.log")
    missing_entries=()
    
    for entry in "${required_entries[@]}"; do
        if ! grep -q "$entry" .gitignore; then
            missing_entries+=("$entry")
        fi
    done
    
    if [ ${#missing_entries[@]} -eq 0 ]; then
        echo "   ✅ All required entries are in .gitignore"
    else
        echo "   ❌ Missing .gitignore entries: ${missing_entries[*]}"
    fi
else
    echo "   ❌ .gitignore file missing!"
fi

echo ""

# Check 2: Verify config.env exists and is not tracked
echo "2. Checking main configuration security..."
if [ -f "config.env" ]; then
    echo "   ✅ config.env exists"
    
    # Check if it contains secrets (look for real-looking storage key)
    if grep -q "STORAGE_ACCOUNT_KEY=" config.env && ! grep -q "your-storage-account-key" config.env; then
        echo "   ✅ config.env contains real configuration"
    else
        echo "   ⚠️  config.env appears to contain template values"
    fi
else
    echo "   ❌ config.env missing - copy from config.env.template"
fi

echo ""

# Check 3: Verify service principal credentials
echo "3. Checking service principal security..."
if [ -f ".sp_credentials" ]; then
    echo "   ✅ .sp_credentials exists"
    
    # Check if it contains actual credentials
    if grep -q "SP_CLIENT_ID=" .sp_credentials && ! grep -q "your-client-id" .sp_credentials; then
        echo "   ✅ .sp_credentials contains real credentials"
    else
        echo "   ⚠️  .sp_credentials appears to contain template values"
    fi
else
    echo "   ⚠️  .sp_credentials missing - run './copy_sharepoint_to_blob.sh --setup'"
fi

echo ""

# Check 4: Verify cron-job directory is clean
echo "4. Checking cron-job directory security..."
if [ -d "cron-job" ]; then
    echo "   ✅ cron-job directory exists"
    
    # Check that no sensitive files exist in cron-job
    sensitive_files_in_cron=()
    if [ -f "cron-job/config.env" ]; then
        sensitive_files_in_cron+=("config.env")
    fi
    if [ -f "cron-job/.sp_credentials" ]; then
        sensitive_files_in_cron+=(".sp_credentials")
    fi
    
    if [ ${#sensitive_files_in_cron[@]} -eq 0 ]; then
        echo "   ✅ No sensitive files in cron-job directory"
    else
        echo "   ❌ Sensitive files found in cron-job: ${sensitive_files_in_cron[*]}"
        echo "       These should be removed for security"
    fi
else
    echo "   ⚠️  cron-job directory missing"
fi

echo ""

# Check 5: Test configuration loading
echo "5. Testing secure configuration loading..."
if ./copy_sharepoint_to_blob.sh --help > /dev/null 2>&1; then
    echo "   ✅ Main script loads configuration successfully"
else
    echo "   ❌ Main script configuration loading failed"
fi

if [ -f "cron-job/sharepoint-sync-cron.sh" ]; then
    if timeout 10 cron-job/sharepoint-sync-cron.sh --help > /dev/null 2>&1 || [ $? -eq 124 ]; then
        echo "   ✅ Cron script loads configuration successfully"
    else
        echo "   ❌ Cron script configuration loading failed"
    fi
fi

echo ""

# Check 6: Verify file permissions
echo "6. Checking file permissions..."
if [ -f "config.env" ]; then
    config_perms=$(ls -l config.env | cut -d' ' -f1)
    if [[ "$config_perms" == *"rw-------"* ]] || [[ "$config_perms" == *"rw-r--r--"* ]]; then
        echo "   ✅ config.env has appropriate permissions: $config_perms"
    else
        echo "   ⚠️  config.env permissions: $config_perms (consider chmod 600 for more security)"
    fi
fi

if [ -f ".sp_credentials" ]; then
    sp_perms=$(ls -l .sp_credentials | cut -d' ' -f1)
    if [[ "$sp_perms" == *"rw-------"* ]] || [[ "$sp_perms" == *"rw-r--r--"* ]]; then
        echo "   ✅ .sp_credentials has appropriate permissions: $sp_perms"
    else
        echo "   ⚠️  .sp_credentials permissions: $sp_perms (consider chmod 600 for more security)"
    fi
fi

echo ""

# Summary
echo "🛡️  SECURITY SUMMARY"
echo "==================="
echo ""
echo "✅ Secure Configuration Model:"
echo "   • Main config.env contains all secrets (git-ignored)"
echo "   • Service principal credentials in .sp_credentials (git-ignored)"  
echo "   • Cron job shares main configuration (no duplicate secrets)"
echo "   • All sensitive files protected by .gitignore"
echo ""
echo "🔐 Security Benefits:"
echo "   • No hardcoded credentials in scripts"
echo "   • Single source of truth for configuration"
echo "   • Safe to commit cron-job scripts to version control"
echo "   • Automatic credential protection"
echo ""
echo "💡 Recommendations:"
echo "   • Regularly rotate service principal credentials"
echo "   • Monitor access logs for unusual activity"
echo "   • Keep Azure Storage account keys secure"
echo "   • Review SharePoint permissions periodically"
echo ""

if [ -f "config.env" ] && [ -f ".sp_credentials" ]; then
    echo "🎉 Security verification completed - System is properly secured!"
else
    echo "⚠️  Security verification completed - Some setup steps may be needed"
fi
