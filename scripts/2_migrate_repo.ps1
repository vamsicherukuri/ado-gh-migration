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

# ADO2GH Repository Migration Script
# 
# Description:
#   This script performs large-scale repository migration from Azure DevOps to GitHub Enterprise
#   with parallel processing and state tracking. It migrates repositories in batches while 
#   maintaining detailed logs for follow-up actions.
# 
# Prerequisites: 
#   - Set the ADO_PAT and GH_PAT environment variables with their respective Personal Access Tokens.
#   - migration-config.json configuration file
#   - CSV file with columns: org, teamproject, repo, ghorg, ghrepo
#
# Usage: 
#   .\2_migrate_repo.ps1
#   .\2_migrate_repo.ps1 [-RepoCSV "repos.csv"]
#   .\2_migrate_repo.ps1 [-MaxParallelJobs 3]  # Reduce concurrent migrations
#
# Order of operations:
#   [1/5] Validate PAT tokens (ADO_PAT and GH_PAT environment variables)
#   [2/5] Load configuration from migration-config.json with parameter overrides
#   [3/5] Load repository data from CSV file with required columns
#   [4/5] Execute batched migrations (respects GitHub's 5 concurrent migration limit)
#   [5/5] Generate state file and display summary with next steps
# 
# Output Files:
#   - migration-state-comprehensive-YYYYMMDD-HHMMSS.json (state file for automation and follow-up scripts)
#   - migration-log-YYYYMMDD-HHMMSS.csv (detailed CSV log with MigrationId and GitHubRepoUrl for analysis)

param(
    [string]$ConfigPath = "migration-config.json",
    [string]$RepoCSV = "",  # Optional override
    [int]$MaxParallelJobs = 5  # GitHub allows max 5 concurrent migrations
)

# Import helper module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\MigrationHelpers.psm1" -Force -ErrorAction Stop

# Global variable for tracking start time
$Global:MigrationStartTime = Get-Date

# Generate state file
function Export-MigrationState {
    param(
        [array]$AllResults, 
        [string]$SourceCsv,
        [int]$TotalRepos
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stateFile = "migration-state-comprehensive-$timestamp.json"
    
    $successfulMigrations = $AllResults | Where-Object { $_.Status -eq "Success" }
    $failedMigrations = $AllResults | Where-Object { $_.Status -eq "Failed" }
    
    $stateData = @{
        MigrationTimestamp = $timestamp
        SourceFile = $SourceCsv
        MigrationStartTime = $Global:MigrationStartTime.ToString("yyyy-MM-dd HH:mm:ss")
        MigrationEndTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        TotalDuration = ((Get-Date) - $Global:MigrationStartTime).ToString()
        
        # Summary statistics  
        TotalRepositories = $TotalRepos
        SuccessfulMigrations = $successfulMigrations.Count
        FailedMigrations = $failedMigrations.Count
        
        # Successful migrations with full details
        MigratedRepositories = @($successfulMigrations | ForEach-Object {
            @{
                AdoOrganization = $_.AdoOrganization
                AdoTeamProject = $_.AdoTeamProject
                AdoRepository = $_.AdoRepository
                GitHubOrganization = $_.GitHubOrganization
                GitHubRepository = $_.GitHubRepository
                MigratedAt = $_.EndTime.ToString("yyyy-MM-dd HH:mm:ss")
                Duration = $_.Duration
            }
        })
        
        # Failed migrations for troubleshooting
        FailedRepositories = @($failedMigrations | ForEach-Object {
            @{
                AdoOrganization = $_.AdoOrganization
                AdoTeamProject = $_.AdoTeamProject
                AdoRepository = $_.AdoRepository
                GitHubOrganization = $_.GitHubOrganization
                GitHubRepository = $_.GitHubRepository
                ErrorMessage = $_.ErrorMessage
                FailedAt = $_.EndTime.ToString("yyyy-MM-dd HH:mm:ss")
                Duration = $_.Duration
            }
        })
        
        # Follow-up actions required
        FollowUpActions = @{
            ValidationRequired = @{
                Message = "Run 3_migration_validation.ps1 to validate all migrated repositories"
                RequiredFor = $successfulMigrations.Count
            }
            PipelineRewiring = @{
                Message = "Run 6_rewire_pipelines.ps1 after validation completes"
                RequiredFor = $successfulMigrations.Count
                ReadyRepositories = @($successfulMigrations | ForEach-Object {
                    @{
                        AdoTeamProject = $_.AdoTeamProject
                        AdoRepository = $_.AdoRepository
                        GitHubRepository = $_.GitHubRepository
                    }
                })
            }
            AdoRepositoryDisabling = @{
                Message = "Run 8_disable_ado_repos.ps1 after validation and pipeline rewiring"
                RequiredFor = $successfulMigrations.Count
                RepositoriesToDisable = @($successfulMigrations | ForEach-Object {
                    @{
                        AdoOrganization = $_.AdoOrganization
                        AdoTeamProject = $_.AdoTeamProject
                        AdoRepository = $_.AdoRepository
                    }
                })
            }
        }
    }
    
    $stateData | ConvertTo-Json -Depth 10 | Out-File -FilePath $stateFile -Encoding UTF8
    Write-Host "`n📄 Migration state exported to: $stateFile" -ForegroundColor Green
    
    return $stateFile
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  ADO2GH Comprehensive Migration Script" -ForegroundColor Cyan
Write-Host "           🚀 PRODUCTION MODE" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. Validate PAT tokens
Write-Host "[1/5] Validating PAT tokens..." -ForegroundColor Yellow
if (!(Test-RequiredPATs)) { exit 1 }

# 2. Load Configuration (migration-config.json)
Write-Host "`n[2/5] Loading configuration..." -ForegroundColor Yellow
$config = Get-MigrationConfig -ConfigPath $ConfigPath
if (!$config) { exit 1 }

# Use parameter override if provided, otherwise load from config
if ([string]::IsNullOrEmpty($RepoCSV)) {
    $RepoCSV = $config.scripts.migrateRepo.repoCSV
}

Write-Host "   CSV File: $RepoCSV" -ForegroundColor Gray

# 3. Load repository data from repo.csv
Write-Host "`n[3/5] Loading repository data from CSV..." -ForegroundColor Yellow

if (-not (Test-Path $RepoCSV)) {
    Write-Host "❌ ERROR: Repository CSV file not found: $RepoCSV" -ForegroundColor Red
    exit 1
}

try {
    $csvData = Import-Csv -Path $RepoCSV | Where-Object { 
        $_.org -and $_.teamproject -and $_.repo -and $_.ghorg -and $_.ghrepo
    }
    
    if ($csvData.Count -eq 0) {
        Write-Host "❌ ERROR: No valid repository data found in CSV" -ForegroundColor Red
        Write-Host "   Ensure CSV has columns: org, teamproject, repo, ghorg, ghrepo" -ForegroundColor Yellow
        exit 1
    }
    

    Write-Host "✅ Loaded $($csvData.Count) repositories from $RepoCSV" -ForegroundColor Green
    
} catch {
    Write-Host "❌ ERROR: Failed to load CSV: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 4. Execute batched migrations (queue + monitor in parallel)
Write-Host "`n[4/5] Executing batched migrations (max $MaxParallelJobs concurrent)..." -ForegroundColor Yellow
Write-Host "Total repositories to migrate: $($csvData.Count)" -ForegroundColor Gray

$completedResults = @()
$activeMigrations = @()
$pendingRepos = [System.Collections.Queue]::new()
$migrationStartTime = Get-Date

# Add all repos to pending queue
for ($i = 0; $i -lt $csvData.Count; $i++) {
    $repo = $csvData[$i]
    $repoInfo = [PSCustomObject]@{
        Index = $i
        JobId = "Job-$($i + 1)"
        Org = $repo.org
        TeamProject = $repo.teamproject
        Repo = $repo.repo
        GhOrg = $repo.ghorg
        GhRepo = $repo.ghrepo
    }
    $pendingRepos.Enqueue($repoInfo)
}

# Function to queue and start monitoring a single migration
function Start-MigrationJob {
    param($RepoInfo)
    
    Write-Host "`n[$($RepoInfo.JobId)] Starting: $($RepoInfo.TeamProject)/$($RepoInfo.Repo) -> $($RepoInfo.GhOrg)/$($RepoInfo.GhRepo)" -ForegroundColor Cyan
    
    try {
        # Lock ADO repository
        Write-Host "[$($RepoInfo.JobId)]   🔒 Locking repository..." -ForegroundColor Yellow
        & gh ado2gh lock-ado-repo --ado-org $RepoInfo.Org --ado-team-project $RepoInfo.TeamProject --ado-repo $RepoInfo.Repo 2>&1 | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to lock repository"
        }
        
        # Queue migration
        Write-Host "[$($RepoInfo.JobId)]   🚀 Queueing migration..." -ForegroundColor Yellow
        $output = & gh ado2gh migrate-repo --ado-org $RepoInfo.Org --ado-team-project $RepoInfo.TeamProject --ado-repo $RepoInfo.Repo --github-org $RepoInfo.GhOrg --github-repo $RepoInfo.GhRepo --queue-only 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to queue migration: $output"
        }
        
        # Extract migration ID
        $migrationId = $null
        $outputString = $output -join "`n"
        if ($outputString -match "A repository migration \(ID: (RM_\S+)\) was successfully queued") {
            $migrationId = $Matches[1]
        } elseif ($outputString -match "Migration queued successfully\. Migration ID: (\S+)") {
            $migrationId = $Matches[1]
        } elseif ($outputString -match "migration_id[:\s]+(\S+)") {
            $migrationId = $Matches[1]
        }
        
        if ($migrationId) {
            Write-Host "[$($RepoInfo.JobId)]   📋 Migration ID: $migrationId" -ForegroundColor Gray
        } else {
            Write-Host "[$($RepoInfo.JobId)]   ⚠️  Using fallback monitoring method" -ForegroundColor Yellow
        }
        
        # Start monitoring job
        $queuedAt = Get-Date
        $job = Start-Job -Name $RepoInfo.JobId -ScriptBlock {
            param($MigrationId, $GhOrg, $GhRepo, $JobId, $QueuedAt, $AdoOrg, $AdoTeam, $AdoRepo)
            
            $startTime = Get-Date
            $githubRepoUrl = "https://github.com/$GhOrg/$GhRepo"
            
            try {
                if ($MigrationId) {
                    $output = & gh ado2gh wait-for-migration --migration-id $MigrationId 2>&1
                } else {
                    $output = & gh ado2gh wait-for-migration --github-org $GhOrg --github-repo $GhRepo 2>&1
                }
                
                $endTime = Get-Date
                $duration = $endTime - $startTime
                
                if ($LASTEXITCODE -eq 0) {
                    return [PSCustomObject]@{
                        JobId = $JobId
                        AdoOrganization = $AdoOrg
                        AdoTeamProject = $AdoTeam
                        AdoRepository = $AdoRepo
                        GitHubOrganization = $GhOrg
                        GitHubRepository = $GhRepo
                        MigrationId = $MigrationId
                        GitHubRepoUrl = $githubRepoUrl
                        Status = "Success"
                        StartTime = $QueuedAt
                        EndTime = $endTime
                        Duration = $duration.ToString()
                    }
                } else {
                    throw "Migration failed: $($output -join ' ')"
                }
            } catch {
                $endTime = Get-Date
                $duration = $endTime - $startTime
                
                return [PSCustomObject]@{
                    JobId = $JobId
                    AdoOrganization = $AdoOrg
                    AdoTeamProject = $AdoTeam
                    AdoRepository = $AdoRepo
                    GitHubOrganization = $GhOrg
                    GitHubRepository = $GhRepo
                    MigrationId = $MigrationId
                    GitHubRepoUrl = $githubRepoUrl
                    Status = "Failed"
                    StartTime = $QueuedAt
                    EndTime = $endTime
                    Duration = $duration.ToString()
                    ErrorMessage = $_.Exception.Message
                }
            }
        } -ArgumentList $migrationId, $RepoInfo.GhOrg, $RepoInfo.GhRepo, $RepoInfo.JobId, $queuedAt, $RepoInfo.Org, $RepoInfo.TeamProject, $RepoInfo.Repo
        
        Write-Host "[$($RepoInfo.JobId)]   ✅ Queued and monitoring started" -ForegroundColor Green
        
        return [PSCustomObject]@{
            Job = $job
            RepoInfo = $RepoInfo
            QueuedAt = $queuedAt
        }
        
    } catch {
        Write-Host "[$($RepoInfo.JobId)]   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
        
        # Return failed result immediately
        return [PSCustomObject]@{
            Job = $null
            RepoInfo = $RepoInfo
            Result = [PSCustomObject]@{
                JobId = $RepoInfo.JobId
                AdoOrganization = $RepoInfo.Org
                AdoTeamProject = $RepoInfo.TeamProject
                AdoRepository = $RepoInfo.Repo
                GitHubOrganization = $RepoInfo.GhOrg
                GitHubRepository = $RepoInfo.GhRepo
                MigrationId = $null
                GitHubRepoUrl = "https://github.com/$($RepoInfo.GhOrg)/$($RepoInfo.GhRepo)"
                Status = "Failed"
                StartTime = Get-Date
                EndTime = Get-Date
                Duration = "00:00:00"
                ErrorMessage = $_.Exception.Message
            }
        }
    }
}

Write-Host "`n⏳ Starting batched migration execution..." -ForegroundColor Cyan

# Start initial batch
$initialBatchSize = [Math]::Min($MaxParallelJobs, $pendingRepos.Count)
Write-Host "Starting initial batch of $initialBatchSize migrations..." -ForegroundColor Gray

for ($i = 0; $i -lt $initialBatchSize; $i++) {
    $repoInfo = $pendingRepos.Dequeue()
    $migrationJob = Start-MigrationJob -RepoInfo $repoInfo
    
    if ($migrationJob.Job) {
        $activeMigrations += $migrationJob
    } else {
        # Failed to queue, add result immediately
        $completedResults += $migrationJob.Result
    }
}

Write-Host "`n⏳ Monitoring active migrations ($($activeMigrations.Count) active, $($pendingRepos.Count) pending)..." -ForegroundColor Cyan

# Monitor and process completions
$lastUpdate = Get-Date

while ($activeMigrations.Count -gt 0 -or $pendingRepos.Count -gt 0) {
    $stillActive = @()
    
    foreach ($migration in $activeMigrations) {
        if ($migration.Job.State -eq 'Completed') {
            $result = Receive-Job -Job $migration.Job
            Remove-Job -Job $migration.Job
            
            $completedResults += $result
            
            if ($result.Status -eq "Success") {
                Write-Host "✅ [$($result.JobId)] $($result.GitHubRepository) completed in $($result.Duration)" -ForegroundColor Green
            } else {
                Write-Host "❌ [$($result.JobId)] $($result.GitHubRepository) failed: $($result.ErrorMessage)" -ForegroundColor Red
            }
            
            # Start next migration if available
            if ($pendingRepos.Count -gt 0) {
                $nextRepo = $pendingRepos.Dequeue()
                $nextMigration = Start-MigrationJob -RepoInfo $nextRepo
                
                if ($nextMigration.Job) {
                    $stillActive += $nextMigration
                } else {
                    $completedResults += $nextMigration.Result
                }
            }
            
        } elseif ($migration.Job.State -eq 'Failed') {
            Write-Host "❌ [$($migration.RepoInfo.JobId)] Monitoring job failed" -ForegroundColor Red
            
            $completedResults += [PSCustomObject]@{
                JobId = $migration.RepoInfo.JobId
                AdoOrganization = $migration.RepoInfo.Org
                AdoTeamProject = $migration.RepoInfo.TeamProject
                AdoRepository = $migration.RepoInfo.Repo
                GitHubOrganization = $migration.RepoInfo.GhOrg
                GitHubRepository = $migration.RepoInfo.GhRepo
                Status = "Failed"
                StartTime = $migration.QueuedAt
                EndTime = Get-Date
                Duration = "00:00:00"
                ErrorMessage = "Monitoring job failed"
            }
            
            Remove-Job -Job $migration.Job -Force
            
            # Start next migration if available
            if ($pendingRepos.Count -gt 0) {
                $nextRepo = $pendingRepos.Dequeue()
                $nextMigration = Start-MigrationJob -RepoInfo $nextRepo
                
                if ($nextMigration.Job) {
                    $stillActive += $nextMigration
                } else {
                    $completedResults += $nextMigration.Result
                }
            }
        } else {
            $stillActive += $migration
        }
    }
    
    $activeMigrations = $stillActive
    
    # Progress update every 10 seconds
    if (((Get-Date) - $lastUpdate).TotalSeconds -ge 10 -and ($activeMigrations.Count -gt 0 -or $pendingRepos.Count -gt 0)) {
        Write-Host "  ⏳ Active: $($activeMigrations.Count), Pending: $($pendingRepos.Count), Completed: $($completedResults.Count)/$($csvData.Count)" -ForegroundColor Gray
        $lastUpdate = Get-Date
    }
    
    if ($activeMigrations.Count -gt 0 -or $pendingRepos.Count -gt 0) {
        Start-Sleep -Seconds 2
    }
}

$migrationDuration = (Get-Date) - $migrationStartTime
Write-Host "`n✅ All migrations completed in $($migrationDuration.ToString('mm\:ss'))" -ForegroundColor Green

# Export detailed CSV log for analysis
$csvLogFile = "migration-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$completedResults | Select-Object JobId, AdoOrganization, AdoTeamProject, AdoRepository, GitHubOrganization, GitHubRepository, MigrationId, GitHubRepoUrl, Status, StartTime, EndTime, Duration, ErrorMessage | Export-Csv -Path $csvLogFile -NoTypeInformation
Write-Host "📊 Detailed log exported to: $csvLogFile" -ForegroundColor Green

# 5. Generate state file
Write-Host "[5/5] Generating migration state file..." -ForegroundColor Yellow

$stateFile = Export-MigrationState -AllResults $completedResults -SourceCsv $RepoCSV -TotalRepos $csvData.Count

# Final Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Migration Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$successCount = ($completedResults | Where-Object { $_.Status -eq "Success" }).Count
$failedCount = ($completedResults | Where-Object { $_.Status -eq "Failed" }).Count
$totalDuration = (Get-Date) - $Global:MigrationStartTime

Write-Host "📊 Total Repositories: $($csvData.Count)" -ForegroundColor White
Write-Host "✅ Successful Migrations: $successCount" -ForegroundColor Green
Write-Host "❌ Failed Migrations: $failedCount" -ForegroundColor Red
Write-Host "⏱️  Total Duration: $($totalDuration.ToString())" -ForegroundColor Gray
Write-Host "📄 State File: $stateFile" -ForegroundColor Cyan

if ($successCount -gt 0) {
    Write-Host "`n🎯 Next Steps:" -ForegroundColor Yellow
    Write-Host "   1. Run 3_migration_validation.ps1 to validate all migrated repositories" -ForegroundColor Gray
    Write-Host "   2. (Optional) Run 4_generate_mannequins.ps1 to identify user mappings" -ForegroundColor Gray
    Write-Host "   3. (Optional) Run 5_reclaim_mannequins.ps1 to reclaim mannequin accounts" -ForegroundColor Gray
    Write-Host "   4. Run 6_rewire_pipelines.ps1 after validation completes" -ForegroundColor Gray
    Write-Host "   5. (Optional) Run 7_integrate_boards.ps1 for Azure Boards integration" -ForegroundColor Gray
    Write-Host "   6. (Optional) Run 8_disable_ado_repos.ps1 after validation and pipeline rewiring" -ForegroundColor Gray
}

if ($failedCount -gt 0) {
    Write-Host "`n⚠️  Failed Migrations:" -ForegroundColor Yellow
    $failedMigrations = $completedResults | Where-Object { $_.Status -eq "Failed" }
    foreach ($failed in $failedMigrations) {
        Write-Host "   - $($failed.AdoOrganization)/$($failed.AdoTeamProject)/$($failed.AdoRepository): $($failed.ErrorMessage)" -ForegroundColor Red
    }
}

Write-Host "`n🏁 Migration process completed!" -ForegroundColor Green