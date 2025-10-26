# Copyright (c) 2025 Vamsi Cherukuri, Microsoft
# 
# MIT License
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# ADO2GH Migration Helper Functions
# 
# This module contains shared helper functions used across all migration scripts
# to eliminate code duplication and provide consistent behavior.
#
# Usage: Import-Module "$scriptPath\MigrationHelpers.psm1" -Force

# ========================================
# 1. PAT Token Validation
# ========================================

<#
.SYNOPSIS
    Validates required Personal Access Tokens (PATs) are set in environment variables.

.DESCRIPTION
    Checks if ADO_PAT and/or GH_PAT environment variables are set based on requirements.
    Used by all scripts to ensure authentication tokens are available before proceeding.

.PARAMETER ADORequired
    Whether Azure DevOps PAT is required. Default is $true.

.PARAMETER GitHubRequired
    Whether GitHub PAT is required. Default is $true.

.EXAMPLE
    if (!(Test-RequiredPATs)) { exit 1 }

.EXAMPLE
    if (!(Test-RequiredPATs -ADORequired $false)) { exit 1 }  # Only GitHub PAT needed
#>
function Test-RequiredPATs {
    param(
        [bool]$ADORequired = $true,
        [bool]$GitHubRequired = $true
    )
    
    $allValid = $true
    
    if ($ADORequired -and !$env:ADO_PAT) {
        Write-Host "❌ ADO_PAT environment variable not set" -ForegroundColor Red
        Write-Host "   Please set your Azure DevOps Personal Access Token" -ForegroundColor Yellow
        $allValid = $false
    }
    
    if ($GitHubRequired -and !$env:GH_PAT) {
        Write-Host "❌ GH_PAT environment variable not set" -ForegroundColor Red
        Write-Host "   Please set your GitHub Personal Access Token" -ForegroundColor Yellow
        $allValid = $false
    }
    
    if ($allValid) {
        Write-Host "✅ PAT tokens validated" -ForegroundColor Green
    }
    
    return $allValid
}

# ========================================
# 2. Configuration File Loading
# ========================================

<#
.SYNOPSIS
    Loads and parses the migration configuration JSON file.

.DESCRIPTION
    Reads the migration-config.json file, parses it, and returns the configuration object.
    Provides consistent error handling and messaging across all scripts.

.PARAMETER ConfigPath
    Path to the configuration JSON file. Default is "migration-config.json".

.EXAMPLE
    $config = Get-MigrationConfig -ConfigPath $ConfigPath
    if (!$config) { exit 1 }

.EXAMPLE
    $config = Get-MigrationConfig
    $adoOrg = $config.adoOrganization
#>
function Get-MigrationConfig {
    param(
        [string]$ConfigPath = "migration-config.json"
    )
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "❌ Configuration file not found: $ConfigPath" -ForegroundColor Red
        return $null
    }
    
    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Write-Host "✅ Configuration loaded successfully" -ForegroundColor Green
        return $config
    } catch {
        Write-Host "❌ Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ========================================
# 3. State File Discovery
# ========================================

<#
.SYNOPSIS
    Finds the most recent migration state file or validates a specified file.

.DESCRIPTION
    Auto-discovers the latest migration state file when not specified or when set to "auto".
    Provides consistent state file handling across validation, rewiring, and disable scripts.

.PARAMETER StateFile
    Path to a specific state file, or "auto" to discover latest, or empty to discover.

.PARAMETER Pattern
    File pattern to search for. Default is "migration-state-*.json".

.EXAMPLE
    $StateFile = Get-LatestStateFile -StateFile $StateFile
    if (!$StateFile) { exit 1 }

.EXAMPLE
    $StateFile = Get-LatestStateFile -StateFile "" -Pattern "migration-state-comprehensive-*.json"
#>
function Get-LatestStateFile {
    param(
        [string]$StateFile = "",
        [string]$Pattern = "migration-state-*.json"
    )
    
    # If a specific file is provided and it's not "auto", validate and return it
    if (![string]::IsNullOrEmpty($StateFile) -and $StateFile -ne "auto") {
        if (Test-Path $StateFile) {
            return $StateFile
        } else {
            Write-Host "❌ ERROR: Specified state file not found: $StateFile" -ForegroundColor Red
            return $null
        }
    }
    
    # Auto-discover the most recent state file
    $stateFiles = Get-ChildItem -Path "." -Filter $Pattern -ErrorAction SilentlyContinue | 
                  Sort-Object LastWriteTime -Descending
    
    if ($stateFiles.Count -eq 0) {
        Write-Host "❌ ERROR: No migration state files found matching pattern: $Pattern" -ForegroundColor Red
        Write-Host "   Please run 2_migrate_repo.ps1 first or specify -StateFile parameter" -ForegroundColor Yellow
        return $null
    }
    
    $discoveredFile = $stateFiles[0].Name
    Write-Host "📄 Auto-discovered state file: $discoveredFile" -ForegroundColor Cyan
    
    return $discoveredFile
}

# ========================================
# 4. Service Connection Queries
# ========================================

<#
.SYNOPSIS
    Queries Azure DevOps service connections (endpoints) for a project.

.DESCRIPTION
    Retrieves GitHub/GitHub Enterprise service connections from an ADO project.
    Provides consistent service connection querying for pipeline rewiring and boards integration.

.PARAMETER AdoOrg
    Azure DevOps organization name.

.PARAMETER ProjectName
    Azure DevOps project name.

.PARAMETER ConnectionTypes
    Array of connection types to filter. Default is @('github', 'githubenterprise').

.EXAMPLE
    $connections = Get-ProjectServiceConnections -AdoOrg $ADO_ORG -ProjectName $projectName
    if ($connections -and $connections.Count -gt 0) { ... }

.EXAMPLE
    $connections = Get-ProjectServiceConnections -AdoOrg $org -ProjectName $proj -ConnectionTypes @('github')
#>
function Get-ProjectServiceConnections {
    param(
        [Parameter(Mandatory)]
        [string]$AdoOrg,
        
        [Parameter(Mandatory)]
        [string]$ProjectName,
        
        [string[]]$ConnectionTypes = @('github', 'githubenterprise')
    )
    
    try {
        # Build the type filter for the query
        $typeFilter = ($ConnectionTypes | ForEach-Object { "type=='$_'" }) -join ' || '
        
        $connections = az devops service-endpoint list `
            --org "https://dev.azure.com/$AdoOrg" `
            --project "$ProjectName" `
            --query "[?$typeFilter].{name:name, id:id, type:type, isReady:isReady, url:url}" `
            -o json 2>$null | ConvertFrom-Json
        
        return $connections
    } catch {
        Write-Host "⚠️  Failed to query service connections for project '$ProjectName': $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# ========================================
# 5. Repository Mapping
# ========================================

<#
.SYNOPSIS
    Creates a standardized repository mapping from ADO to GitHub.

.DESCRIPTION
    Builds a hashtable mapping ADO repositories to GitHub repositories using a consistent structure.
    Key format: "TeamProject|RepositoryName"

.PARAMETER Repositories
    Array of repository objects with ADO and GitHub properties.

.EXAMPLE
    $mapping = New-RepositoryMapping -Repositories $REPOSITORIES
    $githubRepo = $mapping["MyProject|MyRepo"].GitHubRepo

.EXAMPLE
    $mapping = New-RepositoryMapping -Repositories $migrationState.MigratedRepositories
    foreach ($key in $mapping.Keys) {
        Write-Host "$key -> $($mapping[$key].GitHubRepo)"
    }
#>
function New-RepositoryMapping {
    param(
        [Parameter(Mandatory)]
        [object[]]$Repositories
    )
    
    $mapping = @{}
    
    foreach ($repo in $Repositories) {
        $key = "$($repo.AdoTeamProject)|$($repo.AdoRepository)"
        
        $mapping[$key] = @{
            AdoOrganization = $repo.AdoOrganization
            AdoTeamProject = $repo.AdoTeamProject
            AdoRepository = $repo.AdoRepository
            GitHubOrganization = $repo.GitHubOrganization
            GitHubRepository = $repo.GitHubRepository
        }
    }
    
    return $mapping
}

# ========================================
# Module Exports
# ========================================

Export-ModuleMember -Function @(
    'Test-RequiredPATs',
    'Get-MigrationConfig',
    'Get-LatestStateFile',
    'Get-ProjectServiceConnections',
    'New-RepositoryMapping'
)
