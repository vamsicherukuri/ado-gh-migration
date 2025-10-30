# ADO2GH Modular Migration Scripts

> 📖 **New to this migration process?** Start with the **[Migration Workflow Guide](./ADO%20to%20GHE%20migration%20workflow.md)** for a comprehensive overview of the ADO to GitHub Enterprise migration process.

---

This directory contains **9 modular scripts** for migrating Azure DevOps repositories to GitHub in a sequential, automated manner. Each script performs a specific phase of the migration process and can be run independently or orchestrated via GitHub Actions.

## 📋 Table of Contents
- [Overview](#overview)
- [Script Sequence](#script-sequence)
- [Input Variables Reference](#input-variables-reference)
- [Prerequisites](#prerequisites)
- [Manual Execution](#manual-execution)
- [GitHub Actions Automation](#github-actions-automation)
- [Script Details](#script-details)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

These modular scripts break down the ADO to GitHub migration process into **9 distinct steps**:

0. **Inventory** - Generate inventory of ADO repositories
1. **Check Active Processes** - Check for in-progress pipelines and active PRs (optional pre-check)
2. **Migrate Repository** - Lock ADO repo and execute parallel migration to GitHub
3. **Migration Validation** - Validate migrated repositories (commit/branch counts)
4. **Generate Mannequins** - Create CSV of placeholder user accounts (optional)
5. **Reclaim Mannequins** - Map mannequins to actual GitHub users (optional)
6. **Rewire Pipelines** - Update Azure Pipelines to use GitHub repos
7. **Integrate Boards** - Integrate Azure Boards with GitHub repositories (optional)
8. **Disable ADO Repositories** - Prevent further changes to source repositories

### ✅ Benefits
- **Modular**: Each script has a single responsibility
- **Reusable**: Run scripts independently or as a complete pipeline
- **Error Handling**: Easier to debug and retry specific steps
- **CI/CD Ready**: Perfect for GitHub Actions integration
- **Flexibility**: Manual or automated execution

---

## 🔄 Script Sequence

```
┌─────────────────────────────────────────────────────────────┐
│                  ADO to GitHub Migration Flow               │
└─────────────────────────────────────────────────────────────┘

Step 0: Generate Inventory
         ├─ Scan ADO organization
         ├─ Generate repos.csv with repository details
         └─ Identify repositories for migration
                      ⬇️
Step 1: Check Active Processes (Optional Pre-Check)
         ├─ Read from repos.csv OR use -Repository parameters
         ├─ Check for in-progress pipelines per repo
         ├─ Check for active pull requests per repo
         └─ Generate ready/blocked repository report (CONSOLE OUTPUT ONLY)
                      ⬇️
         [MANUAL STEP: Filter repos.csv based on console output if needed]
                      ⬇️
Step 2: Migrate Repository (Parallel Execution)
         ├─ Read from repos.csv input file
         ├─ Lock ADO repository
         ├─ Execute migration to GitHub (parallel jobs)
         ├─ Track success/failure per repository
         └─ Generate migration state file
                      ⬇️
Step 3: Migration Validation
         ├─ Read from migration state file
         ├─ Validate ADO source (commits, branches)
         ├─ Validate GitHub target (commits, branches)
         ├─ Compare results (informational)
         └─ Update state file with validation results
                      ⬇️
Step 4: Generate Mannequins (Optional)
         └─ Create CSV of placeholder user accounts (org-wide)
                      ⬇️
Step 5: Reclaim Mannequins (Optional)
         └─ Map mannequins to actual GitHub users
                      ⬇️
Step 6: Rewire Pipelines
         ├─ Read from migration state file (for repo mappings)
         ├─ Read pipelines from pipelines.csv (PRIMARY INPUT)
         ├─ Validate service connections per project
         ├─ Skip Classic pipelines (manual rewiring required)
         ├─ Skip already-rewired pipelines
         └─ Rewire YAML pipelines to GitHub repos
                      ⬇️
Step 7: Integrate Boards (Optional)
         ├─ Read from repos.csv (PRIMARY INPUT)
         ├─ Check for existing GitHub Boards connections
         ├─ Skip projects with existing connections
         └─ Integrate Azure Boards with GitHub repos
                      ⬇️
Step 8: Disable ADO Repositories
         ├─ Read from migration state file
         ├─ Confirm user intent
         ├─ Disable each ADO repository
         └─ Generate disable report
```

---

## ⚙️ Prerequisites

### Required Tools
- **PowerShell** 7.0 or later
- **GitHub CLI** (`gh`) - [Install](https://cli.github.com/)
- **Azure CLI** (`az`) - [Install](https://docs.microsoft.com/cli/azure/install-azure-cli)
- **gh-ado2gh extension** - Install via: `gh extension install github/gh-ado2gh`

### Required Environment Variables
```powershell
# Azure DevOps Personal Access Token (with full access)
$env:ADO_PAT = "your-ado-pat-token"

# GitHub Personal Access Token (with admin:org, repo, workflow scopes)
$env:GH_PAT = "your-github-pat-token"
```

### Configuration File
Ensure `migration-config.json` is configured with:
```json
{
  "adoOrganization": "contosodevopstest",
  "githubOrganization": "ADO2GH-Migration",
  "scripts": {
    "inventory": {
      "adoOrg": "contosodevopstest"
    },
    "checkActiveProcess": {
      "repoCSV": "repos.csv"
    },
    "migrateRepo": {
      "repoCSV": "repos.csv",
      "maxConcurrentJobs": 4,
      "pollingIntervalSeconds": 15,
      "jobTimeoutMinutes": 20
    },
    "generateMannequins": {
      "outputCSV": "mannequins.csv"
    },
    "reclaimMannequins": {
      "inputCSV": "mannequins.csv",
      "skipInvitation": false
    },
    "rewirePipelines": {
      "stateFile": "auto",
      "pipelinesCSV": "pipelines.csv"
    },
    "disableAdoRepos": {
      "stateFile": "auto"
    }
  }
}
```

---

## 🖥️ Manual Execution

### Run Scripts Sequentially

Navigate to the `scripts` directory:
```powershell
cd scripts
```

**Step 0: Generate Inventory**
```powershell
# Generate inventory of all ADO repositories
.\0_Inventory.ps1

# Or specify different ADO organization
.\0_Inventory.ps1 -AdoOrg "your-ado-org"

# This generates: repos.csv, team-projects.csv, orgs.csv, pipelines.csv
```

**Step 1: Check Active Processes (Optional)**
```powershell
# Pre-check: Identify repositories ready for migration
.\1_check_active_process.ps1

# Check specific team project only
.\1_check_active_process.ps1 -TeamProject "ProjectName"

# Check specific repository
.\1_check_active_process.ps1 -Repository "RepoName" -TeamProject "ProjectName"

# This generates: repos-ready-for-migration.csv
# Use this filtered CSV for migration to avoid blocked repositories
```

**Step 2: Migrate Repository (Parallel)**
```powershell
# Option A: Migrate all repos from inventory
.\2_migrate_repo.ps1 -RepoCSV "repos.csv"

# Option B: Migrate only ready repos (after pre-check)
.\2_migrate_repo.ps1 -RepoCSV "repos-ready-for-migration.csv"

# Option C: Use custom configuration
.\2_migrate_repo.ps1 -ConfigPath "custom-config.json" -MaxConcurrentJobs 6

# This generates: migration-state-comprehensive-YYYYMMDD-HHMMSS.json
```

**Step 3: Migration Validation**
```powershell
# Validate migrated repositories
.\3_migration_validation.ps1

# Or specify a specific state file
.\3_migration_validation.ps1 -StateFile "migration-state-comprehensive-20241014-232108.json"

# This generates: validation-log-YYYYMMDD-HHmmss.txt
# Updates state file with validation results
```

**Step 4: Generate Mannequins**
```powershell
.\4_generate_mannequins.ps1

# Or specify different config file
.\4_generate_mannequins.ps1 -ConfigPath "custom-config.json"
```

**Step 5: Reclaim Mannequins** *(Update CSV first!)*
```powershell
# 1. Review and update mannequins.csv with target GitHub users
# 2. Then run:
.\5_reclaim_mannequins.ps1

# Or specify different config file
.\5_reclaim_mannequins.ps1 -ConfigPath "custom-config.json"
```

**Step 6: Rewire Pipelines**
```powershell
# Reads from latest migration state file
.\6_rewire_pipelines.ps1

# Or specify state file and pipelines CSV
.\6_rewire_pipelines.ps1 -StateFile "migration-state-comprehensive-20241014-232108.json" -PipelinesCSV "pipelines.csv"
```

**Step 7: Integrate Boards (Optional)**
```powershell
# Integrate Azure Boards with GitHub repositories
.\7_integrate_boards.ps1

# Or specify a different repos file
.\7_integrate_boards.ps1 -ReposFile "repos.csv"

# This generates: boards-integration-log-YYYYMMDD-HHmmss.txt
```

**Step 8: Disable ADO Repositories**
```powershell
# Reads from latest migration state file
.\8_disable_ado_repos.ps1

# Or specify a specific state file
.\8_disable_ado_repos.ps1 -StateFile "migration-state-comprehensive-20241014-232108.json"
```

### Run Individual Steps

Each script can be run independently if you need to retry a specific step:

```powershell
# Retry validation only
.\3_migration_validation.ps1

# Retry pipeline rewiring only
.\6_rewire_pipelines.ps1

# Retry boards integration
.\7_integrate_boards.ps1

# Disable ADO repositories separately
.\8_disable_ado_repos.ps1
```

---

## 🤖 GitHub Actions Automation

### Workflow File
A GitHub Actions workflow can be created to automate the migration process. Currently, no workflow file is included in this repository, but you can create one based on the following template:

**Suggested workflow location**: `.github/workflows/ado-migration-pipeline.yml`

### Creating a Workflow

1. **Create the workflow directory**:
   ```powershell
   mkdir -p .github/workflows
   ```

2. **Create the workflow file** with the sequential execution of all scripts

3. **Set GitHub Secrets** in your repository:
   - `ADO_PAT` - Azure DevOps Personal Access Token
   - `GH_PAT` - GitHub Personal Access Token

### Required GitHub Secrets

Set these secrets in your GitHub repository:
- `ADO_PAT` - Azure DevOps Personal Access Token
- `GH_PAT` - GitHub Personal Access Token

**Setting Secrets:**
1. Go to: Repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each secret with appropriate values

### Workflow Benefits

✅ **Sequential Execution** - Steps run in order with dependencies  
✅ **Automatic Failure Handling** - Stops if any step fails  
✅ **Artifact Upload** - Logs and reports are saved  
✅ **Manual Trigger** - Run on-demand via workflow_dispatch  
✅ **Flexible Options** - Skip steps as needed  
✅ **Summary Report** - Shows status of all steps  

### Viewing Results

- **Logs**: Check each job's logs for detailed output
- **Artifacts**: Download logs and reports from the workflow run
- **Summary**: View overall status in the workflow summary

---

## 📖 Script Details

### 0️⃣ `0_Inventory.ps1`

**Purpose**  
Generate an ADO inventory report at the organization level to identify all repositories, team projects, organizations, and pipelines.

**Input Parameters**  
- `ConfigPath` (string) - Configuration file path (default: "migration-config.json")
- `AdoOrg` (string) - Azure DevOps organization name (optional override)

**Parameter Source**  
- `AdoOrg`: Uses config file value from `scripts.inventory.adoOrg` or parameter override
- `ADO_PAT`: Read from environment variable
- `GH_PAT`: Read from environment variable

**ADO2GH CLI/APIs Used**  
- `gh ado2gh inventory-report --ado-org $AdoOrg`

**Output**  
- `repos.csv` - Repository inventory with metadata
- `team-projects.csv` - Team project listing
- `orgs.csv` - Organization listing
- `pipelines.csv` - Pipeline inventory

**Important Note**  
⚠️ **Manual CSV Update Required**: After running this script, you must manually add two columns to `repos.csv`:
- `ghorg` - Target GitHub organization name
- `ghrepo` - Target GitHub repository name

**Example repos.csv format after manual update:**
```csv
org,teamproject,repo,visibility,last-push-date,git-source,ghorg,ghrepo
contosodevopstest,ContosoAir,ContosoAir,private,2023-07-27T18:53:54Z,AdoGit,MyGitHubOrg,contosoair-migrated
```

**Next Step**  
Execute `1_check_active_process.ps1` to check for active processes before migration, or proceed directly to `2_migrate_repo.ps1` to begin repository migration.

---

### 3️⃣ `3_migration_validation.ps1`

**Purpose**  
Validates migrated repositories by comparing ADO source and GitHub target repositories. Provides informational comparison of commit and branch counts.

**Input Parameters**  
- `StateFile` (string) - Migration state file (auto-detects most recent if not specified)

**Parameter Source**  
- State file from `2_migrate_repo.ps1` (auto-discovery or explicit path)
- `ADO_PAT`: Read from environment variable
- `GH_PAT`: Read from environment variable

**Prerequisites**  
- Repositories must be successfully migrated (Step 2)
- Migration state file must exist
- ADO_PAT for Azure DevOps REST API access
- GH_PAT for GitHub CLI access

**Validation Checks**  
- ✅ ADO source repository accessibility
- ✅ GitHub target repository accessibility  
- ✅ Commit count comparison (informational)
- ✅ Branch count comparison (informational)

**Actions**  
1. Loads migration state file (auto-detects most recent)
2. For each successfully migrated repository:
   - Retrieves ADO commit and branch counts via REST API
   - Retrieves GitHub commit and branch counts via GitHub CLI
   - Displays side-by-side comparison (informational only)
3. Updates state file with validation results
4. Generates timestamped transcript log

**ADO2GH CLI/APIs Used**  
```powershell
# ADO REST API calls for commit/branch counts
Invoke-RestMethod -Uri "https://dev.azure.com/$AdoOrg/$Project/_apis/git/repositories/$Repo/commits"
Invoke-RestMethod -Uri "https://dev.azure.com/$AdoOrg/$Project/_apis/git/repositories/$Repo/refs"

# GitHub CLI API calls
gh api "/repos/$GitHubOrg/$GitHubRepo/commits"
gh api "/repos/$GitHubOrg/$GitHubRepo/branches"
```

**Output**  
- `validation-log-YYYYMMDD-HHmmss.txt` - Detailed validation transcript
- Updates existing migration state file with validation results

**Example Console Output**  
```
🔍 Validating: contosodevopstest/ContosoAir/ContosoAir -> ADO2GH-Migration/contosoair
   📊 Validating ADO source...
      ✅ ADO: 150 commits, 5 branches
   📊 Validating GitHub target...
      ✅ GitHub: 150 commits, 5 branches
   📊 Comparison Results:
      📋 Commits: ADO=150 | GitHub=150
      📋 Branches: ADO=5 | GitHub=5
   ✅ Validation COMPLETED
```

**State File Updates**  
Adds `ValidationResults` section to existing state file:
```json
{
  "ValidationResults": [
    {
      "AdoOrganization": "contosodevopstest",
      "AdoTeamProject": "ContosoAir",
      "AdoRepository": "ContosoAir",
      "GitHubOrganization": "ADO2GH-Migration",
      "GitHubRepository": "contosoair",
      "ValidationStatus": "Success",
      "ValidationTimestamp": "2024-10-14 23:30:15",
      "AdoSourceValidation": {
        "CommitCount": 150,
        "BranchCount": 5,
        "Accessible": true
      },
      "GitHubTargetValidation": {
        "CommitCount": 150,
        "BranchCount": 5,
        "Accessible": true
      }
    }
  ]
}
```

**Important Notes**  
- Validation is **informational only** - displays counts side-by-side without pass/fail logic
- Counts may differ slightly due to timing or ADO/GitHub differences
- Main purpose: verify repositories are accessible on both platforms
- Updates state file for tracking validation history

**Next Step**  
Execute `4_generate_mannequins.ps1` if user mapping is needed (optional), or proceed to `6_rewire_pipelines.ps1` to rewire pipelines.

---

### 1️⃣ `1_check_active_process.ps1` (Optional Pre-Check)

**Purpose**: Checks for active processes before migration to identify ready repositories

**Input Parameters**: 
- `ConfigPath` (string) - Configuration file path (default: "migration-config.json")
- `RepoCSV` (string) - Repository CSV file (optional override)
- `AdoOrg` (string) - ADO organization (optional override)
- `TeamProject` (string) - Filter to specific team project (optional)
- `Repository` (string) - Check single repository (optional)
- `Repositories` (string[]) - Check multiple repositories (optional)

**Output**:
- `repos-ready-for-migration.csv` - Filtered list of repositories ready for migration
- `blocked-repositories-YYYYMMDD-HHMMSS.csv` - Report of blocked repositories

**Checks per Repository**:
- ✅ In-progress pipelines in the repository's team project
- ✅ Active pull requests for the specific repository

**Exit Codes**:
- `0` - All repositories ready, or some ready/some blocked
- `1` - All repositories blocked by active processes

**Example Output**:
```
✅ Ready for Migration: 15
🚫 Blocked (Active Processes): 2

📋 Repositories Ready for Migration:
   ✅ [myorg/project] repo1
   ✅ [myorg/project] repo2

📋 Blocked Repositories:
   🚫 [myorg/project] repo3
      - Active Pipelines: 2
      - Active PRs: 1
```

**Usage Examples**:
```powershell
# Check all repos from inventory
.\1_check_active_process.ps1

# Check specific team project
.\1_check_active_process.ps1 -TeamProject "ProjectName"

# Check specific repository
.\1_check_active_process.ps1 -Repository "RepoName" -TeamProject "ProjectName"

# Use generated CSV for migration
.\2_migrate_repo.ps1 -RepoCSV "repos-ready-for-migration.csv"
```

---

### 2️⃣ `2_migrate_repo.ps1` (Parallel Migration)

**Purpose**: Migrates repositories from ADO to GitHub with parallel execution

**Input Parameters**:
- `ConfigPath` (string) - Configuration file path (default: "migration-config.json")
- `RepoCSV` (string) - Repository CSV file (optional override)
- `MaxConcurrentJobs` (int) - Number of parallel jobs (optional override)
- `PollingIntervalSeconds` (int) - Job polling interval (optional override)
- `JobTimeoutMinutes` (int) - Job timeout (optional override)

**CSV Format Requirements**:
The input CSV must have these columns:
```csv
org,teamproject,repo,ghorg,ghrepo
contosodevopstest,ContosoAir,ContosoAir,MyGitHubOrg,contosoair-migrated
```

**Output**:
- `migration-state-comprehensive-YYYYMMDD-HHMMSS.json` - Comprehensive state file with migration results

**Features**:
- ✨ **Parallel Execution**: 4 concurrent migrations (configurable)
- ✨ **Queue Management**: Automatic job spawning as slots free
- ✨ **Real-time Progress**: Live status updates
- ✨ **Comprehensive Tracking**: Success/failure/timing per repository
- ✨ **Configuration-driven**: Uses migration-config.json for settings

**Actions per Repository**:
1. Lock ADO repository
2. Migrate to GitHub
3. Track result (success/failure)
4. Record timing information

**Commands Used**:
```powershell
gh ado2gh lock-ado-repo --ado-org $ADO_ORG --ado-team-project $PROJECT --ado-repo $REPO
gh ado2gh migrate-repo --ado-org $ADO_ORG --ado-team-project $PROJECT --ado-repo $REPO --github-org $GITHUB_ORG --github-repo $GITHUB_REPO
```

**Progress Output**:
```
📊 Progress: [85.0%] Running: 3 | Queued: 2 | ✅ 15 | ❌ 0 | Total: 20
```

**State File Format**:
```json
{
  "metadata": {
    "timestamp": "20241014-232108",
    "startTime": "2024-10-14T23:21:08.123Z",
    "endTime": "2024-10-14T23:25:15.456Z",
    "totalDuration": "00:04:07",
    "totalRepositories": 20,
    "successfulMigrations": 18,
    "failedMigrations": 2,
    "parallelJobs": 4
  },
  "migratedRepositories": [
    {
      "adoOrganization": "contosodevopstest",
      "adoTeamProject": "ContosoAir",
      "adoRepository": "ContosoAir",
      "githubOrganization": "ADO2GH-Migration",
      "githubRepository": "contosoair",
      "migrationResult": "Success",
      "startTime": "2024-10-14T23:21:15Z",
      "endTime": "2024-10-14T23:23:45Z",
      "duration": "00:02:30"
    }
  ]
}
```

---

### 4️⃣ `4_generate_mannequins.ps1`

**Purpose**: Generates CSV of mannequin user accounts (org-wide operation)

**What are Mannequins?**  
Mannequins are placeholder accounts created during migration for users that don't exist in the target GitHub organization.

**Input Parameters**:
- `ConfigPath` (string) - Configuration file path (default: "migration-config.json")

**Scope**: 
- ⚠️ **Organization-wide scan** - scans all repositories in GitHub org
- Cannot filter by repository (CLI tool limitation)

**Actions**:
1. Validates GH_PAT token
2. Generates mannequin CSV using `gh ado2gh generate-mannequin-csv`
3. Displays statistics

**Commands Used**:
```powershell
gh ado2gh generate-mannequin-csv --github-org $GITHUB_ORG --output mannequins.csv
```

**Output Files**:
- `mannequins.csv` - Contains mannequin user mapping

**CSV Format**:
```csv
mannequin-user,mannequin-id,target-user
john-doe_moc,12345,john-doe-actual
```

**Next Step**:
Execute `5_reclaim_mannequins.ps1` if user mappings need to be reclaimed. If skipping, proceed to `6_rewire_pipelines.ps1`.

---

### 5️⃣ `5_reclaim_mannequins.ps1`

**Purpose**: Reclaims mannequins by mapping to actual GitHub users

**Input Parameters**:
- `ConfigPath` (string) - Configuration file path (default: "migration-config.json")

**Prerequisites**:
- ⚠️ **IMPORTANT**: Update `mannequins.csv` with target GitHub usernames before running!

**Actions**:
1. Validates GH_PAT token
2. Reads and validates mannequins CSV
3. Executes `gh ado2gh reclaim-mannequin`
4. Maps mannequin contributions to real users

**Commands Used**:
```powershell
gh ado2gh reclaim-mannequin --github-org $GITHUB_ORG --csv mannequins.csv
```

**Notes**:
- Use `--skip-invitation` flag for EMU (Enterprise Managed User) organizations
- Ensure target users exist in the GitHub organization

**Next Step**:
Execute `6_rewire_pipelines.ps1` to rewire ADO pipelines to GitHub repositories.

---

### 6️⃣ `6_rewire_pipelines.ps1`

**Purpose**: Rewires Azure Pipelines to use GitHub repositories

**Input Parameters**:
- `ConfigPath` (string) - Configuration file path (default: "migration-config.json")
- `StateFile` (string) - Migration state file (auto-detects most recent if not specified)
- `PipelinesCSV` (string) - Pipelines CSV file (optional override)

**Prerequisites**:
- GitHub service connection must exist in Azure DevOps
- Pipelines CSV must be present
- Repositories must be successfully migrated

**Actions**:
1. Validates PAT tokens
2. Loads migrated repositories from state file
3. Loads pipeline data from CSV
4. Filters pipelines for migrated repositories only
5. Prompts for service connection selection
6. Rewires each pipeline to GitHub repo

**State File Support**:
- Auto-detects latest `migration-state-comprehensive-*.json` file
- Only rewires pipelines for successfully migrated repos

**Commands Used**:
```powershell
az devops service-endpoint list --org "https://dev.azure.com/$ADO_ORG" --project "$PROJECT"
gh ado2gh rewire-pipeline --ado-org $ADO_ORG --ado-team-project $PROJECT --ado-pipeline $PIPELINE --github-org $GITHUB_ORG --github-repo $REPO --service-connection-id $CONNECTION_ID
```

**Interactive Prompts**:
- Service connection selection

**Output Files**:
- `pipeline-rewiring-log-YYYYMMDD-HHMMSS.txt` - Detailed rewiring log

**Next Step**:
Execute `7_integrate_boards.ps1` to integrate Azure Boards (optional), or proceed to `8_disable_ado_repos.ps1` to disable ADO repositories.

---

### 7️⃣ `7_integrate_boards.ps1` (Optional Step)

**Purpose**: Integrates Azure Boards work items with GitHub repositories using Azure Boards integration app

**Input Parameters**:
- `ConfigPath` (string) - Configuration file path (default: "migration-config.json")
- `StateFile` (string) - Migration state file (auto-detects most recent if not specified)

**Parameter Source**:
- State file from `2_migrate_repo.ps1` (auto-discovery or explicit path)
- Configuration file provides:
  - Azure DevOps organization
  - GitHub organization
  - Personal Access Tokens (ADO_PAT, GH_PAT)

**Prerequisites**:
- ⚠️ **CRITICAL**: Azure Boards app must be pre-installed and configured in GitHub
- GitHub organization must have Azure Boards integration enabled
- Repositories must be successfully migrated (Step 2)
- Migration state file must exist
- ADO_PAT for Azure DevOps REST API access
- GH_PAT for GitHub CLI access

**Connection Pre-Check**:
Before attempting integration, the script verifies:
- ✅ Azure Boards app installation in GitHub organization
- ✅ ADO organization-level Azure Boards connection
- ⚠️ **If checks fail**, the script will **NOT proceed** with integration

**Actions**:
1. Loads migration state file (auto-detects most recent)
2. Verifies Azure Boards app installation in GitHub
3. For each successfully migrated repository:
   - Checks for existing Azure Boards connection in GitHub repo
   - Creates new connection if none exists
   - Skips if connection already present
4. Updates state file with integration results
5. Generates timestamped integration log

**GitHub CLI/API Commands Used**:
```powershell
# Check Azure Boards app installation in GitHub org
gh api "/orgs/$GitHubOrg/installations" | ConvertFrom-Json

# Check existing Azure Boards connection for repo
gh api "/repos/$GitHubOrg/$GitHubRepo/hooks" | ConvertFrom-Json

# Azure DevOps REST API - Create Azure Boards connection
Invoke-RestMethod -Method Post -Uri "https://dev.azure.com/$AdoOrg/_apis/serviceendpoint/endpoints"
```

**Output**:
- `boards-integration-log-YYYYMMDD-HHmmss.txt` - Detailed integration transcript
- Updates existing migration state file with integration results

**Example Console Output**:
```
🔗 Integrating Boards: contosodevopstest/ContosoAir/ContosoAir -> ADO2GH-Migration/contosoair
   ✅ Azure Boards connection created successfully

🔗 Integrating Boards: contosodevopstest/Project2/Repo2 -> ADO2GH-Migration/repo2
   ⚠️ Azure Boards connection already exists (skipped)

📊 Integration Summary:
   ✅ Connected: 12
   ⚠️ Already Connected: 3
   ❌ Failed: 0
```

**State File Updates**:
Adds `BoardsIntegrationResults` section to existing state file:
```json
{
  "BoardsIntegrationResults": [
    {
      "AdoOrganization": "contosodevopstest",
      "AdoTeamProject": "ContosoAir",
      "AdoRepository": "ContosoAir",
      "GitHubOrganization": "ADO2GH-Migration",
      "GitHubRepository": "contosoair",
      "IntegrationStatus": "Success",
      "IntegrationTimestamp": "2024-10-14 23:45:30",
      "ConnectionCreated": true,
      "AlreadyConnected": false
    }
  ]
}
```

**Important Notes**:
- This is an **optional step** - Azure Boards integration is not required for migration
- The script will **abort** if Azure Boards app is not pre-installed
- Skips repositories that already have Azure Boards connections
- Safe to re-run - will not duplicate connections

**Next Step**:
Execute `8_disable_ado_repos.ps1` to disable ADO repositories after all validations pass.

---

### 8️⃣ `8_disable_ado_repos.ps1`

**Purpose**: Disables ADO repositories to prevent further changes after successful migration

**Input Parameters**:
- `ConfigPath` (string) - Configuration file path (default: "migration-config.json")
- `StateFile` (string) - Migration state file (auto-detects most recent if not specified)

**Prerequisites**:
- Repositories must be successfully migrated (Step 2)
- Migration state file should exist

**Actions**:
1. Validates PAT tokens (ADO_PAT and GH_PAT)
2. Loads repository list from state file
3. Prompts for user confirmation
4. Disables each ADO repository
5. Generates disable report

**State File Support**:
- Auto-detects latest `migration-state-comprehensive-*.json` file
- Disables only successfully migrated repositories

**Commands Used**:
```powershell
gh ado2gh disable-ado-repo --ado-org $ADO_ORG --ado-team-project $PROJECT --ado-repo $REPO
```

**Output Files**:
- `disable-report-YYYYMMDD-HHMMSS.md` - Detailed disable report

**Interactive Prompts**:
- ⚠️ Warning and confirmation before disabling repositories

**Important Notes**:
- This is a **destructive operation** - ADO repos will be read-only after disabling
- Recommended to run this **AFTER** all validations pass and pipelines are rewired
- Can be run separately or as final step in migration workflow

---

## 🔧 Configuration

### Config File Structure
The `migration-config.json` file controls all script behaviors:
```json
{
  "adoOrganization": "contosodevopstest",
  "githubOrganization": "ADO2GH-Migration",
  "scripts": {
    "inventory": {
      "adoOrg": "contosodevopstest"
    },
    "checkActiveProcess": {
      "repoCSV": "repos.csv"
    },
    "migrateRepo": {
      "repoCSV": "repos.csv",
      "maxConcurrentJobs": 4,
      "pollingIntervalSeconds": 15,
      "jobTimeoutMinutes": 20
    },
    "generateMannequins": {
      "outputCSV": "mannequins.csv"
    },
    "reclaimMannequins": {
      "inputCSV": "mannequins.csv",
      "skipInvitation": false
    },
    "rewirePipelines": {
      "stateFile": "auto",
      "pipelinesCSV": "pipelines.csv"
    },
    "disableAdoRepos": {
      "stateFile": "auto"
    }
  }
}
```

### Repository CSV Format
The `repos.csv` file (after manual update) should have these columns:
```csv
org,teamproject,repo,visibility,last-push-date,git-source,ghorg,ghrepo
contosodevopstest,ContosoAir,ContosoAir,private,2023-07-27T18:53:54Z,AdoGit,ADO2GH-Migration,contosoair
contosodevopstest,ContosoUniversity,ContosoUniversity,private,2023-06-15T10:30:22Z,AdoGit,ADO2GH-Migration,contoso-university
```

**⚠️ Important**: The `ghorg` and `ghrepo` columns must be manually added after running the inventory script.

### Pipelines CSV Format
Create `pipelines.csv` with the following structure:
```csv
teamproject,repo,pipeline
ProjectName,RepositoryName,PipelineName
ProjectName,RepositoryName,AnotherPipelineName
```

---

## 🔍 Troubleshooting

### Common Issues

**Issue**: PAT token errors  
**Solution**: Ensure tokens have correct scopes and are not expired
```powershell
# Test ADO PAT
az devops project list --org https://dev.azure.com/$ADO_ORG

# Test GH PAT
gh auth status
```

**Issue**: Repository not found after migration  
**Solution**: Check GitHub organization permissions and verify migration completed
```powershell
gh repo view $GITHUB_ORG/$GITHUB_REPO
```

**Issue**: Active processes blocking migration  
**Solution**: Wait for pipelines to complete or cancel active PRs
```powershell
az pipelines runs list --project $PROJECT --status inProgress
az repos pr list --project $PROJECT --status active
```

**Issue**: Service connection not found  
**Solution**: Create GitHub service connection in Azure DevOps
1. Go to Project Settings → Service connections
2. Create new GitHub connection
3. Grant access to repositories

**Issue**: Mannequin CSV is empty  
**Solution**: This is normal if all users already exist in GitHub
```powershell
# Check if users need mapping
.\4_generate_mannequins.ps1
```

### Log Files Location
All logs are saved in the `scripts/` directory:
- `migration-state-comprehensive-*.json` - Migration state files
- `pipeline-rewiring-log-*.txt` - Pipeline rewiring logs
- `disable-report-*.md` - Repository disable reports
- `repos-ready-for-migration.csv` - Filtered repository list
- `blocked-repositories-*.csv` - Blocked repository reports

### Getting Help
- Review script output for detailed error messages
- Check GitHub Actions logs for workflow failures
- Verify configuration file is correct
- Ensure all prerequisites are installed

---

## 📊 Success Indicators

✅ **Step 0**: Inventory generated successfully  
✅ **Step 1**: No active processes found (optional)  
✅ **Step 2**: All repositories migrated successfully  
✅ **Step 3**: Migration validation completed (informational)
✅ **Step 4**: Mannequins CSV generated (optional)
✅ **Step 5**: Mannequins reclaimed (optional)
✅ **Step 6**: All pipelines rewired successfully  
✅ **Step 7**: Azure Boards integrated (optional)
✅ **Step 8**: All ADO repositories disabled successfully  

---

## 🎉 Next Steps After Migration

1. **Test Pipelines** - Run pipelines in Azure DevOps to verify GitHub integration
2. **Update Documentation** - Update team docs with new GitHub repository URLs
3. **Notify Team** - Communicate migration completion to stakeholders
4. **Clean Up** - Archive or delete old ADO repositories (after verification period)
5. **Monitor** - Watch for any issues in the first few days post-migration

---

## 📝 Notes

- **Always run scripts in order** for first-time migrations
- **Review logs** after each step for any warnings
- **Backup important data** before starting migration
- **Test in a pilot project** before migrating production repositories
- **Plan migration during low-activity periods** to minimize disruption

---

## 🤝 Support

For issues or questions:
1. Review this README thoroughly
2. Check log files for error details
3. Consult GitHub and Azure DevOps documentation
4. Contact your DevOps team or GitHub support

---

**Last Updated**: October 2024  
**Version**: 1.1.0  
**Author**: ADO2GH Migration Team
