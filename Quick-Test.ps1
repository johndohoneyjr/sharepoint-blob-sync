#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick environment test for SharePoint to Azure Blob Storage sync (PowerShell Version)

.DESCRIPTION
    This script performs essential environment checks to ensure all dependencies
    and configurations are properly set up for the SharePoint to Blob copy operation.

.PARAMETER ShowDetails
    Enable detailed output showing configuration details and verbose information.

.EXAMPLE
    .\Quick-Test.ps1
    Run basic environment tests

.EXAMPLE
    .\Quick-Test.ps1 -ShowDetails
    Run tests with detailed output

.NOTES
    File Name      : Quick-Test.ps1
    Author         : SharePoint Blob Sync Team
    Prerequisite   : PowerShell 5.1+, Azure CLI
#>

[CmdletBinding()]
param(
    [switch]$ShowDetails
)

# Set error handling
$ErrorActionPreference = 'Continue'

# Set console encoding for proper character display
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $OutputEncoding = [System.Text.Encoding]::UTF8
}
else {
    # For PowerShell 5.1, try to set console to UTF-8
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    }
    catch {
        # Fallback - continue without UTF-8 if not supported
    }
}

# Global test counters
$script:TestsPassed = 0
$script:TestsFailed = 0

# Color functions for consistent output
function Write-ColoredText {
    param(
        [string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host $Text -ForegroundColor $Color
}

function Write-Step { param([string]$Text) Write-ColoredText $Text -Color Cyan }
function Write-Success { param([string]$Text) Write-ColoredText $Text -Color Green }
function Write-Warning { param([string]$Text) Write-ColoredText $Text -Color Yellow }
function Write-Error { param([string]$Text) Write-ColoredText $Text -Color Red }
function Write-Info { param([string]$Text) Write-ColoredText $Text -Color Gray }

function Start-Test {
    param([string]$TestName)
    Write-Host "Testing: $TestName" -NoNewline
}

function Complete-TestSuccess {
    param([string]$Message)
    Write-ColoredText " [OK] $Message" -Color Green
    $script:TestsPassed++
}

function Complete-TestWarning {
    param([string]$Message)
    Write-ColoredText " [WARN] $Message" -Color Yellow
}

function Complete-TestFailure {
    param([string]$Message)
    Write-ColoredText " [FAIL] $Message" -Color Red
    $script:TestsFailed++
}

# Main test execution
try {
    Write-Step "*** SharePoint to Blob Copy - Quick Test (PowerShell Version) ***"
    Write-Step "=================================================================="
    Write-Host ""

    # Test 1: PowerShell version
    Start-Test "PowerShell version compatibility..."
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        Complete-TestSuccess "PowerShell $($psVersion) detected"
        if ($ShowDetails) {
            Write-Info "   Edition: $($PSVersionTable.PSEdition)"
            Write-Info "   OS: $($PSVersionTable.OS)"
        }
    }
    else {
        Complete-TestFailure "PowerShell 5.1+ required. Found version: $psVersion"
    }

    # Test 2: Configuration file
    Start-Test "Configuration file..."
    $configFile = "config.env"
    if (Test-Path $configFile) {
        Complete-TestSuccess "config.env file found"
        
        if ($ShowDetails) {
            try {
                $configContent = Get-Content $configFile -ErrorAction Stop
                $configLines = ($configContent | Where-Object { $_ -match '^[^#].*=' }).Count
                Write-Info "   Configuration file contains $configLines settings"
            }
            catch {
                Write-Info "   Could not read configuration details"
            }
        }
    }
    else {
        Complete-TestFailure "config.env file not found"
        Write-Info "Please copy config.env.template to config.env and configure it"
    }

    # Test 3: Azure CLI
    Start-Test "Azure CLI installation..."
    try {
        $azVersion = & az version 2>$null | ConvertFrom-Json
        if ($azVersion) {
            Complete-TestSuccess "Azure CLI installed"
            if ($ShowDetails) {
                Write-Info "   Version: $($azVersion.'azure-cli')"
            }
        }
        else {
            Complete-TestFailure "Azure CLI not found or not working"
        }
    }
    catch {
        Complete-TestFailure "Azure CLI not available"
        Write-Info "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    }

    # Test 4: Azure login status
    Start-Test "Azure login status..."
    try {
        $azQuery = "{name:name,tenantId:tenantId}"
        $accountInfo = & az account show --query $azQuery -o json 2>$null
        
        if ($LASTEXITCODE -eq 0 -and $accountInfo) {
            $account = $accountInfo | ConvertFrom-Json
            Complete-TestSuccess "Logged in to Azure as: $($account.name)"
            
            if ($ShowDetails) {
                Write-Info "   Tenant ID: $($account.tenantId)"
            }
        }
        else {
            Complete-TestWarning "Not logged in to Azure"
            Write-Info "Please run: az login"
        }
    }
    catch {
        Complete-TestWarning "Could not check Azure login status"
        Write-Info "Please run: az login"
    }

    # Test 5: Network connectivity
    Start-Test "Network connectivity..."
    try {
        $testResult = Test-NetConnection -ComputerName "graph.microsoft.com" -Port 443 -InformationLevel Quiet -ErrorAction Stop
        if ($testResult) {
            Complete-TestSuccess "Network connectivity OK"
        }
        else {
            Complete-TestWarning "Network connectivity issues detected"
        }
    }
    catch {
        Complete-TestWarning "Could not test network connectivity"
    }

    # Summary
    Write-Host ""
    Write-Step "*** TEST SUMMARY ***"
    Write-Step "==================="
    Write-Success "[PASS] Tests passed: $script:TestsPassed"
    if ($script:TestsFailed -gt 0) {
        Write-Error "[FAIL] Tests failed: $script:TestsFailed"
    }

    Write-Host ""
    Write-Step "*** NEXT STEPS ***"
    Write-Step "=================="
    
    if ($script:TestsFailed -gt 0) {
        Write-Error "[ACTION REQUIRED] Please fix the failed tests before proceeding"
        Write-Info "1. Install missing dependencies"
        Write-Info "2. Configure missing files"
        Write-Info "3. Re-run this test script"
    }
    else {
        Write-Info "1. Run setup: .\Copy-SharePointToBlob.ps1 -Setup"
        Write-Info "2. Test the copy: .\Copy-SharePointToBlob.ps1"
    }

    Write-Host ""
    Write-Success "[COMPLETE] Quick test completed!"
    
    # Exit with appropriate code
    if ($script:TestsFailed -gt 0) {
        exit 1
    }
    else {
        exit 0
    }
}
catch {
    Write-Error "[ERROR] Test script failed: $($_.Exception.Message)"
    Write-Info "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
