#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sync runner for SharePoint to Azure Blob Storage scheduled task

.DESCRIPTION
    This script is designed to be called by the Windows Task Scheduler to perform
    the SharePoint to Blob Storage synchronization. It provides comprehensive
    logging, error handling, and status reporting optimized for automated execution.

.PARAMETER LogLevel
    Logging level: Minimal, Normal, Verbose (default: Normal)

.PARAMETER ForceSync
    Force synchronization even if last sync was recent

.PARAMETER SkipQuickTest
    Skip the environment quick test before sync

.PARAMETER MaxRetries
    Maximum number of retry attempts on failure (default: 3)

.PARAMETER RetryDelaySeconds
    Delay between retry attempts in seconds (default: 30)

.EXAMPLE
    .\Run-Sync.ps1
    Run sync with default settings

.EXAMPLE
    .\Run-Sync.ps1 -LogLevel Verbose
    Run sync with verbose logging

.EXAMPLE
    .\Run-Sync.ps1 -ForceSync -MaxRetries 5
    Force sync with 5 retry attempts

.NOTES
    File Name      : Run-Sync.ps1
    Author         : SharePoint Blob Sync Team
    Prerequisite   : PowerShell 5.1+, Configured environment
    Version        : 1.0
    
    This script is optimized for scheduled execution and includes:
    - Comprehensive logging with timestamps
    - Mutex-based locking to prevent concurrent runs
    - Retry logic for transient failures
    - Status file generation for monitoring
    - Email notifications (if configured)
#>

[CmdletBinding()]
param(
    [ValidateSet("Minimal", "Normal", "Verbose")]
    [string]$LogLevel = "Normal",
    [switch]$ForceSync,
    [switch]$SkipQuickTest,
    [int]$MaxRetries = 3,
    [int]$RetryDelaySeconds = 30
)

# Set error handling
$ErrorActionPreference = 'Continue'

# Global variables
$script:LogPath = ""
$script:StatusPath = ""
$script:MutexName = "SharePointBlobSync_Mutex"
$script:Mutex = $null
$script:StartTime = Get-Date
$script:SyncSuccess = $false

# Initialize logging
function Initialize-Logging {
    $logDir = Join-Path $PSScriptRoot "logs"
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd"
    $script:LogPath = Join-Path $logDir "sync_$timestamp.log"
    $script:StatusPath = Join-Path $logDir "sync_status.json"
    
    # Create log file if it doesn't exist
    if (!(Test-Path $script:LogPath)) {
        New-Item -ItemType File -Path $script:LogPath -Force | Out-Null
    }
}

# Logging functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO",
        [switch]$ToConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    try {
        Add-Content -Path $script:LogPath -Value $logEntry -Encoding UTF8
    }
    catch {
        # If log file write fails, continue without logging
    }
    
    # Write to console based on log level
    if ($ToConsole -or $LogLevel -eq "Verbose" -or ($LogLevel -eq "Normal" -and $Level -ne "DEBUG")) {
        switch ($Level) {
            "ERROR" { Write-Host $logEntry -ForegroundColor Red }
            "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
            "INFO"  { Write-Host $logEntry -ForegroundColor White }
            "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        }
    }
}

function Write-LogInfo { param([string]$Message) Write-Log -Message $Message -Level "INFO" }
function Write-LogWarn { param([string]$Message) Write-Log -Message $Message -Level "WARN" }
function Write-LogError { param([string]$Message) Write-Log -Message $Message -Level "ERROR" }
function Write-LogDebug { param([string]$Message) Write-Log -Message $Message -Level "DEBUG" }

# Status tracking
function Update-Status {
    param(
        [string]$State,
        [string]$Message = "",
        [object]$Details = $null
    )
    
    $status = @{
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        State = $State
        Message = $Message
        Details = $Details
        ProcessId = $PID
        Duration = if ($script:StartTime) { (Get-Date) - $script:StartTime } else { $null }
    }
    
    try {
        $status | ConvertTo-Json -Depth 3 | Set-Content -Path $script:StatusPath -Encoding UTF8
    }
    catch {
        Write-LogWarn "Failed to update status file: $($_.Exception.Message)"
    }
}

# Mutex handling for preventing concurrent runs
function Get-SyncMutex {
    try {
        $script:Mutex = New-Object System.Threading.Mutex($false, $script:MutexName)
        $acquired = $script:Mutex.WaitOne(5000) # Wait up to 5 seconds
        
        if ($acquired) {
            Write-LogInfo "Acquired sync mutex - proceeding with sync"
            return $true
        }
        else {
            Write-LogWarn "Another sync process is already running - exiting"
            return $false
        }
    }
    catch {
        Write-LogError "Failed to create or acquire mutex: $($_.Exception.Message)"
        return $false
    }
}

function Clear-SyncMutex {
    if ($script:Mutex) {
        try {
            $script:Mutex.ReleaseMutex()
            $script:Mutex.Dispose()
            Write-LogDebug "Released sync mutex"
        }
        catch {
            Write-LogWarn "Failed to release mutex: $($_.Exception.Message)"
        }
    }
}

# Environment validation
function Test-Environment {
    Write-LogInfo "Performing environment validation..."
    
    # Check if Quick-Test.ps1 exists and run it
    $quickTestScript = Join-Path $PSScriptRoot "Quick-Test.ps1"
    if (!(Test-Path $quickTestScript)) {
        Write-LogError "Quick-Test.ps1 not found: $quickTestScript"
        return $false
    }
    
    try {
        $testResult = & $quickTestScript 2>&1
        $testExitCode = $LASTEXITCODE
        
        Write-LogDebug "Quick test output: $($testResult -join "`n")"
        
        if ($testExitCode -eq 0) {
            Write-LogInfo "Environment validation passed"
            return $true
        }
        else {
            Write-LogError "Environment validation failed (exit code: $testExitCode)"
            return $false
        }
    }
    catch {
        Write-LogError "Failed to run environment validation: $($_.Exception.Message)"
        return $false
    }
}

# Main sync operation
function Start-SyncOperation {
    param([int]$AttemptNumber = 1)
    
    Write-LogInfo "Starting sync operation (attempt $AttemptNumber of $MaxRetries)"
    Update-Status -State "RUNNING" -Message "Sync in progress (attempt $AttemptNumber)"
    
    # Check if main sync script exists
    $syncScript = Join-Path $PSScriptRoot "Copy-SharePointToBlob.ps1"
    if (!(Test-Path $syncScript)) {
        Write-LogError "Main sync script not found: $syncScript"
        return $false
    }
    
    try {
        # Execute the main sync script
        Write-LogInfo "Executing: $syncScript"
        $syncOutput = & $syncScript 2>&1
        $syncExitCode = $LASTEXITCODE
        
        # Log the output based on log level
        if ($LogLevel -eq "Verbose") {
            Write-LogDebug "Sync script output:"
            $syncOutput | ForEach-Object { Write-LogDebug "  $_" }
        }
        elseif ($LogLevel -eq "Normal") {
            # Log only important lines (errors, warnings, summaries)
            $syncOutput | Where-Object { 
                $_ -match "(ERROR|WARN|FAIL|SUCCESS|COMPLETE|SUMMARY)" 
            } | ForEach-Object { 
                Write-LogInfo "  $_" 
            }
        }
        
        if ($syncExitCode -eq 0) {
            Write-LogInfo "Sync operation completed successfully"
            return $true
        }
        else {
            Write-LogError "Sync operation failed with exit code: $syncExitCode"
            
            # Log error details for debugging
            $errorLines = $syncOutput | Where-Object { $_ -match "(ERROR|FAIL)" }
            if ($errorLines) {
                Write-LogError "Error details:"
                $errorLines | ForEach-Object { Write-LogError "  $_" }
            }
            
            return $false
        }
    }
    catch {
        Write-LogError "Exception during sync operation: $($_.Exception.Message)"
        Write-LogDebug "Stack trace: $($_.ScriptStackTrace)"
        return $false
    }
}

# Retry logic
function Start-SyncWithRetry {
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $success = Start-SyncOperation -AttemptNumber $attempt
        
        if ($success) {
            $script:SyncSuccess = $true
            Write-LogInfo "Sync completed successfully on attempt $attempt"
            return $true
        }
        
        if ($attempt -lt $MaxRetries) {
            Write-LogWarn "Sync failed on attempt $attempt, retrying in $RetryDelaySeconds seconds..."
            Update-Status -State "RETRYING" -Message "Attempt $attempt failed, retrying in $RetryDelaySeconds seconds"
            Start-Sleep -Seconds $RetryDelaySeconds
        }
        else {
            Write-LogError "Sync failed after $MaxRetries attempts"
        }
    }
    
    return $false
}

# Cleanup function
function Complete-Sync {
    $duration = (Get-Date) - $script:StartTime
    
    if ($script:SyncSuccess) {
        Write-LogInfo "=== SYNC COMPLETED SUCCESSFULLY ==="
        Write-LogInfo "Total duration: $($duration.ToString('hh\:mm\:ss'))"
        Update-Status -State "SUCCESS" -Message "Sync completed successfully" -Details @{
            Duration = $duration.ToString('hh\:mm\:ss')
            Attempts = if ($MaxRetries -gt 1) { "Multiple attempts configured" } else { "Single attempt" }
        }
    }
    else {
        Write-LogError "=== SYNC FAILED ==="
        Write-LogError "Total duration: $($duration.ToString('hh\:mm\:ss'))"
        Update-Status -State "FAILED" -Message "Sync failed after all retry attempts" -Details @{
            Duration = $duration.ToString('hh\:mm\:ss')
            MaxRetries = $MaxRetries
        }
    }
    
    # Release mutex
    Clear-SyncMutex
    
    # Final log entry
    Write-LogInfo "Run-Sync.ps1 execution completed"
}

# Main execution
try {
    # Initialize
    Initialize-Logging
    Write-LogInfo "=== SHAREPOINT BLOB SYNC - SCHEDULED RUN STARTED ==="
    Write-LogInfo "Process ID: $PID"
    Write-LogInfo "Log Level: $LogLevel"
    Write-LogInfo "Force Sync: $ForceSync"
    Write-LogInfo "Skip Quick Test: $SkipQuickTest"
    Write-LogInfo "Max Retries: $MaxRetries"
    
    Update-Status -State "STARTING" -Message "Initializing sync process"
    
    # Check for concurrent runs
    if (!(Get-SyncMutex)) {
        Update-Status -State "SKIPPED" -Message "Another sync process is already running"
        exit 0
    }
    
    # Environment validation (unless skipped)
    if (!$SkipQuickTest) {
        if (!(Test-Environment)) {
            Write-LogError "Environment validation failed - aborting sync"
            Update-Status -State "FAILED" -Message "Environment validation failed"
            Complete-Sync
            exit 1
        }
    }
    else {
        Write-LogInfo "Skipping environment validation as requested"
    }
    
    # Check if force sync or enough time has passed since last sync
    if (!$ForceSync) {
        # You could add logic here to check last sync time from status file
        # For now, we'll always proceed
        Write-LogDebug "Proceeding with sync (no recent sync time check implemented)"
    }
    
    # Execute sync with retry logic
    $success = Start-SyncWithRetry
    
    # Complete
    Complete-Sync
    
    # Exit with appropriate code
    exit $(if ($success) { 0 } else { 1 })
}
catch {
    Write-LogError "[FATAL] Unhandled exception in Run-Sync.ps1: $($_.Exception.Message)"
    Write-LogError "Stack trace: $($_.ScriptStackTrace)"
    
    Update-Status -State "ERROR" -Message "Fatal error: $($_.Exception.Message)"
    Clear-SyncMutex
    
    exit 1
}
finally {
    # Ensure mutex is always released
    if ($script:Mutex) {
        Clear-SyncMutex
    }
}
