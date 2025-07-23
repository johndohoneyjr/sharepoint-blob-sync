#!/bin/bash

# Quick Test Script for SharePoint to Azure Blob Storage Sync
# This script runs basic tests to verify the system is working

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🧪 SharePoint to Azure Blob Storage - Quick Test Suite${NC}"
echo "=========================================================="
echo ""

cd "$(dirname "$0")"

# Test 1: Configuration and Help
echo -e "${YELLOW}Test 1: Configuration and Help${NC}"
if ./copy_sharepoint_to_blob.sh --help > /dev/null 2>&1; then
    echo -e "✅ Help command works"
else
    echo -e "❌ Help command failed"
    exit 1
fi

# Test 2: Blob Storage Listing
echo -e "${YELLOW}Test 2: Blob Storage Listing${NC}"
if ./copy_sharepoint_to_blob.sh --list-contents-of-blob > /dev/null 2>&1; then
    echo -e "✅ Blob listing works"
    
    # Get file count
    file_count=$(./copy_sharepoint_to_blob.sh --list-contents-of-blob 2>/dev/null | grep "Total files:" | awk '{print $3}')
    echo -e "   📊 Current files in blob storage: $file_count"
else
    echo -e "❌ Blob listing failed"
    echo -e "   💡 This might be normal if no sync has been run yet"
fi

# Test 3: Detailed Verification (if test directory exists)
if [ -d "test" ]; then
    echo -e "${YELLOW}Test 3: Detailed Verification${NC}"
    cd test
    if timeout 30 ./verify_blob_contents.sh > /tmp/detailed_test.log 2>&1; then
        echo -e "✅ Detailed verification works"
        
        # Get detailed stats
        if grep -q "Total size:" /tmp/detailed_test.log; then
            total_size=$(grep "Total size:" /tmp/detailed_test.log | awk '{print $3" "$4}')
            echo -e "   💾 Total storage used: $total_size"
        fi
    else
        echo -e "❌ Detailed verification failed or timed out"
        echo -e "   💡 This might be normal if no sync has been run yet"
    fi
    cd ..
    rm -f /tmp/detailed_test.log
fi

# Test 4: Cron Job Status (if cron-job directory exists)
if [ -d "cron-job" ]; then
    echo -e "${YELLOW}Test 4: Cron Job Status${NC}"
    cd cron-job
    if ./setup-cron.sh --status > /dev/null 2>&1; then
        echo -e "✅ Cron job management works"
        
        # Check if cron job is installed
        if crontab -l 2>/dev/null | grep -q "sharepoint-sync-cron.sh"; then
            echo -e "   ⏰ Cron job is installed and active"
        else
            echo -e "   ⏰ Cron job is not installed"
        fi
    else
        echo -e "❌ Cron job management failed"
    fi
    cd ..
fi

echo ""
echo -e "${GREEN}🎉 Quick test suite completed!${NC}"
echo ""
echo -e "${CYAN}💡 Available Commands:${NC}"
echo "   ./copy_sharepoint_to_blob.sh --help              # Show help"
echo "   ./copy_sharepoint_to_blob.sh --list-contents-of-blob  # List blob contents"
echo "   ./copy_sharepoint_to_blob.sh                     # Run sync"
echo "   cd test && ./verify_blob_contents.sh             # Detailed verification"
echo "   cd cron-job && ./setup-cron.sh --status          # Check cron status"
echo ""
echo -e "${CYAN}📚 Documentation:${NC}"
echo "   README.md     # Main setup guide"
echo "   TESTING.md    # Comprehensive testing guide"
