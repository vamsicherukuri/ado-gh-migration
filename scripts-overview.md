# 🚀Automating Azure DevOps to GitHub Enterprise Migration Using ADO2GH extension



*Published: October 28, 2025*

---

## 🧭 Overview

Migrating from **Azure DevOps (ADO)** to **GitHub Enterprise (GHE)** is a complex undertaking that requires careful planning, execution, and validation. While manual migration is possible for a handful of repositories, organizations with dozens or hundreds of repositories need an automated, repeatable, and traceable approach.

This article marks the **first installment in a detailed series** introducing the **ADO2GH Migration PowerShell Scripts** - a **collection of modular automation scripts** purpose-built to simplify, orchestrate, and validate each stage of the migration journey, from initial preparation to final post-migration checks.

---

## 🗂️Table of Contents

- 🧰[Prerequisites: Setting Up Your Environment](#prerequisites-setting-up-your-environment)
- 🔐[Personal Access Token Scope Requirements](#personal-access-token-scope-requirements)
- 🧭[Understanding the Migration Workflow](#understanding-the-migration-workflow)
- ⚙️[Configuration File Setup](#configuration-file-setup)
- ✅[Validating Your Setup](#validating-your-setup)
- 🗂️[Script 0: Inventory Script (0_Inventory.ps1)](#script-0-inventory-script-0_inventoryps1)
- 🔍[Script 1: Active Process Check (1_check_active_process.ps1)](#script-1-active-process-check-1_check_active_processps1)
- 🚚[Script 2: Repository Migration (2_migrate_repo.ps1)](#script-2-repository-migration-2_migrate_repops1)
- 🧾[Script 3: Migration Validation (3_migration_validation.ps1)](#script-3-migration-validation-3_migration_validationps1)
- 🧍‍♂️[Script 4: Generate Mannequins (4_generate_mannequins.ps1)](#script-4-generate-mannequins-4_generate_mannequinsps1)
- 🔁[Script 5: Reclaim Mannequins (5_reclaim_mannequins.ps1)](#script-5-reclaim-mannequins-5_reclaim_mannequinsps1)
- 🔗[Script 6: Rewire Pipelines (6_rewire_pipelines.ps1)](#script-6-rewire-pipelines-6_rewire_pipelinesps1)
- 📋[Script 7: Integrate Boards (7_integrate_boards.ps1)](#script-7-integrate-boards-7_integrate_boardsps1)
- 🛑[Script 8: Disable ADO Repositories (8_disable_ado_repos.ps1)](#script-8-disable-ado-repositories-8_disable_ado_reposps1)

---

## Prerequisites: Setting Up Your Environment

Before you can run any script in this migration suite, you need to ensure your environment is properly configured. This section covers all the tools, permissions, and configuration required.

### Required Tools and Software

#### 1. PowerShell 7.0 or Later

The migration scripts are built on PowerShell 7+ to leverage cross-platform capabilities and modern scripting features.

**Installation:**
```powershell
# Windows (using winget)
winget install Microsoft.PowerShell

# Or download from: https://github.com/PowerShell/PowerShell/releases
```

**Verify Installation:**
```powershell
$PSVersionTable.PSVersion
# Should show version 7.0 or higher
```

#### 2. GitHub CLI (gh)

The GitHub CLI is essential for interacting with GitHub repositories, organizations, and the ADO2GH extension.

**Installation:**
```powershell
# Windows (using winget)
winget install GitHub.cli

# Or download from: https://cli.github.com/
```

**Verify Installation:**
```powershell
gh --version
# Should show gh version 2.x or higher
```

**Authentication:**
```powershell
# Authenticate with your GitHub Enterprise instance
gh auth login --hostname github.com

# Follow the prompts to complete authentication
```

#### 3. Azure CLI (az)

The Azure CLI is used for querying Azure DevOps resources, checking pipeline status, and managing service connections.

**Installation:**
```powershell
# Windows (using winget)
winget install Microsoft.AzureCLI

# Or download from: https://docs.microsoft.com/cli/azure/install-azure-cli
```

**Verify Installation:**
```powershell
# Should show azure-cli version 2.x or higher
az --version
```

**Azure DevOps Extension:**
```powershell
# Add the Azure DevOps extension to Azure CLI
az extension add --name azure-devops

# Verify the extension is installed
az extension list --output table
```

#### 4. GitHub ADO2GH Extension

This is the critical tool that enables repository migration from Azure DevOps to GitHub.

**Installation:**
```powershell
# Install the ADO2GH extension for GitHub CLI
gh extension install github/gh-ado2gh

# Verify installation
gh extension list
```

**Keeping Extensions Updated:**
```powershell
# Update the ADO2GH extension to the latest version
gh extension upgrade gh-ado2gh

# Or update all extensions
gh extension upgrade --all
```

---

### Personal Access Token Scope Requirements

#### Azure DevOps Personal Access Token (ADO_PAT)

The ADO_PAT token is used to authenticate with Azure DevOps and perform operations on repositories, pipelines, Azure Boards, Service connections and projects.

To generate the Azure DevOps inventory report, a PAT with full access or elevated administrator privileges is mandatory. This is a one-time requirement used solely for inventory generation.

💡 _Tip:_ You can minimize risk by setting the token expiration to **less than one day** for this step.

**Recommended PAT Scopes for Migration:**
- `Analytics: Read`
- `Build: Read`
- `Code: Full` (required for disabling ADO repositories)
- `GitHub Connections: Read & Manage`
- `Graph: Read`
- `Identity: Read`
- `Pipeline Resources: Use`
- `User Profile: Read`
- `Project and Team: Read`
- `Release: Read`
- `Security: Manage`
- `Service Connections: Read & Query`
- `Work Items: Read`


**Creating the Token:**
1. Navigate to Azure DevOps: `https://dev.azure.com/{your-org}`
2. Click on **User Settings** (top-right) → **Personal Access Tokens**
3. Click **+ New Token**
4. Set an expiration date (consider your migration timeline)
5. Select **Full Access** for inventory report generation or specific scopes listed above
6. Click **Create** and **copy the token immediately**

**Setting the Environment Variable:**
```powershell
# Windows PowerShell (current session)
$env:ADO_PAT = "your-ado-pat-token-here"

# Windows PowerShell (persistent)
[System.Environment]::SetEnvironmentVariable('ADO_PAT', 'your-ado-pat-token-here', 'User')

# Verify it's set
$env:ADO_PAT
```

⚠️ **Security Best Practice:** PAT tokens function much like passwords, so they must be handled and stored with extreme caution. 
Never commit PAT tokens to version control. Always store them securely using a password manager, environment variable, or a secret management tool (such as Azure Key Vault or GitHub Secrets).

#### GitHub Personal Access Token (GH_PAT)

The GH_PAT token authenticates with GitHub Enterprise and is required for organization-level operations.

**Required Scopes:**
- `repo` - Full control of private repositories
- `workflow` - Update GitHub Actions workflows
- `admin:org` - Full control of organizations and teams
- `user:read` - Read user profile data
- `user:email` - Access user email addresses
- `write:discussion` - Create and manage discussions
- `delete_repo` — Delete repositories (optional, for rollback scenarios)

**Creating the Token:**
1. Navigate to GitHub Settings: `https://github.com/settings/tokens`
2. Click **Generate new token** → **Generate new token (classic)**
3. Give it a descriptive name (e.g., "ADO Migration Tool")
4. Set an expiration (consider your migration timeline)
5. Select all the scopes listed above
6. Click **Generate token** and **copy it immediately**

**Setting the Environment Variable:**
```powershell
# Windows PowerShell (current session)
$env:GH_PAT = "your-github-pat-token-here"

# Windows PowerShell (persistent)
[System.Environment]::SetEnvironmentVariable('GH_PAT', 'your-github-pat-token-here', 'User')

# Verify it's set
$env:GH_PAT
```

---

### Configuration File Setup

The migration scripts use a centralized configuration file (`migration-config.json`) to manage settings consistently across all scripts.

**Create the Configuration File:**

1. Navigate to the `scripts` directory in your migration workspace
2. Copy the sample configuration file:

```powershell
cd scripts
Copy-Item migration-config.json.sample migration-config.json
```

3. Edit `migration-config.json` with your organization details:

```json
{
  "adoOrganization": "your-ado-org-name",
  "githubOrganization": "your-github-org-name",
  "scripts": {
    "inventory": {
      "adoOrg": "your-ado-org-name"
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

**Configuration Parameters Explained:**

| Parameter | Description | Example |
|-----------|-------------|---------|
| `adoOrganization` | Your Azure DevOps organization name | `contosodevopstest` |
| `githubOrganization` | Your target GitHub organization | `ADO2GH-Migration` |
| `scripts.inventory.adoOrg` | ADO org for inventory generation | `contosodevopstest` |
| `scripts.migrateRepo.maxConcurrentJobs` | Parallel migration limit | `4` (max 5 per GitHub) |
| `scripts.migrateRepo.repoCSV` | Input CSV file for migration | `repos.csv` |

---

### Validating Your Setup

Before running the inventory script, validate that everything is configured correctly:

```powershell
# 1. Check PowerShell version
$PSVersionTable.PSVersion

# 2. Check GitHub CLI authentication
gh auth status

# 3. Check Azure CLI installation
az --version

# 4. Check ADO2GH extension
gh extension list | Select-String "ado2gh"

# 5. Verify environment variables are set
Write-Host "ADO_PAT: $($env:ADO_PAT -ne $null)" -ForegroundColor $(if($env:ADO_PAT) {"Green"} else {"Red"})
Write-Host "GH_PAT: $($env:GH_PAT -ne $null)" -ForegroundColor $(if($env:GH_PAT) {"Green"} else {"Red"})

# 6. Test Azure DevOps connectivity
az devops project list --org "https://dev.azure.com/your-ado-org"

# 7. Test GitHub connectivity
gh repo list your-github-org --limit 5
```

If all checks pass, you're ready to proceed! ✅

---

## Understanding the Migration Workflow

Before diving into the inventory script specifically, it's helpful to understand where it fits in the overall migration process.

**Insert the image???**

### The Big Picture: 9-Step Migration Approach

The **ADO to GitHub migration process** is structured as a **nine-step sequential workflow**, where each step builds upon the previous one to ensure a smooth and validated migration:

```
Step 0: Inventory Generation ← YOU ARE HERE
    ↓
Step 1: Active Process Check (Pre-Migration Validation)
    ↓
Step 2: Repository Migration (Parallel Execution)
    ↓
Step 3: Migration Validation (Post-Migration)
    ↓
Step 4: Generate Mannequins (Optional User Mapping)
    ↓
Step 5: Reclaim Mannequins (Optional User Attribution)
    ↓
Step 6: Rewire Pipelines (CI/CD Integration)
    ↓
Step 7: Integrate Boards (Optional Work Item Linking)
    ↓
Step 8: Disable ADO Repositories (Finalization)
```

## Script 0: Inventory Script (0_Inventory.ps1)
📝 **Description:**
 
This script generates an inventory report of Azure DevOps repositories at the organization level using the gh ado2gh CLI extension. This report is used to identify repositories for migration planning.

🧰 **Prerequisites:**
- **ADO_PAT** environment variable set with full access scope
- **gh ado2gh CLI** extension installed
- **migration-config.json** exists with proper configuration

⚙️ **Order of operations:**
- **[1/3]** Validate **ADO PAT** tokens.
- **[2/3]** Load configuration from **migration-config.json** with parameter overrides
- **[3/3]** Generate inventory report using **gh ado2gh** CLI

💻 **Script Usage:**
- Run with default settings: `.\0_Inventory.ps1` 
- Specify an Azure DevOps organization: `.\0_Inventory.ps1 -AdoOrg "your-ado-org"` 
- Use a custom configuration file: `.\0_Inventory.ps1 -ConfigPath "custom-config.json"` 


**🗂️ Output Files Generated:**
- Contains the list of **Azure DevOps organizations**: `orgs.csv`
- Captures all **team projects** within each organization: `team-projects.csv`
- Lists all **repositories** (used as input for subsequent scripts): `repos.csv`
- Enumerates all **pipeline**s associated with the **projects**: `pipelines.csv`


## Script 1: Active Process Check (1_check_active_process.ps1)


📝 **Description:** 

This script checks for active processes **(pipelines and PRs)** on ADO repositories before migration. It should be run **BEFORE** starting the migration to ensure repositories are ready for migration.

🧰 **Prerequisites:**
- **ADO_PAT** environment variable set with ADO migration PAT tokens.
- **Azure CLI** - Used to query Azure DevOps pipelines and pull requests. Must include Azure DevOps extension: `az extension add --name azure-devops`
- **Azure CLI Authentication** Must be logged into Azure CLI: `az login`
- The **helper module** `MigrationHelpers.psm1` must be present in the same directory as the script.
- `migration-config.json` - Must exist in the same directory. Should contain:
`adoOrganization` - Your ADO organization name
`scripts.checkActiveProcess.repoCSV` - Path to repository CSV file.
- `repos.csv` (or configured CSV file) with columns: `org`, `teamproject`, `repo`

⚙️ **Order of operations:**
- **[1/5]** Validate ADO PAT tokens. 
- **[2/5]** Load configuration from `migration-config.json` with parameter overrides
- **[3/5]** Normalize repository input from parameters or CSV file
- **[4/5]** Check active processes **(pipelines and PRs)** for each repository
- **[5/5]** Summarize results and provide next steps


💻 **Script Usage:**
- Check all repos reading from repo.csv generated from inventory report.
`.\1_check_active_process.ps1` 
- Check specific projects
`.\1_check_active_process.ps1 -TeamProject "project"`
- Check specific repositories within a project
`.\1_check_active_process.ps1 -Repository "repo1" -TeamProject "project"`
- Check multiple repositories within a project
`.\1_check_active_process.ps1 -Repositories @("repo1", "repo2") -TeamProject "project"`


**🗂️ Output Files generated:**

*Displays output to the console (progress messages, results, summary)*


## Script 2: Repository Migration (2_migrate_repo.ps1)

📝 **Description:** 

This script performs large-scale repository migration from Azure DevOps to GitHub Enterprise with parallel processing and state tracking. It migrates repositories in batches while maintaining detailed logs for follow-up actions.


🧰 **Prerequisites:**
- Set `ADO_PAT` and `GH_PAT` as environment variables with the correct permission scopes.
- `migration-config.json` & `MigrationHelpers.psm1` - Must exist in the same directory
- `repos.csv` (or configured CSV path) with 5 required columns: `org`, `teamproject`, `repo`, `ghorg`, `ghrepo`
- `migration-config.json` configuration file
- **Maximum 5 concurrent migrations** per organization (enforced by GitHub). Script respects this limit with the `$MaxParallelJobs` parameter (default: 5)
- Ideally, `1_check_active_process.ps1` should be executed first to verify that there are no active **pipelines** or **pull requests**, followed by `0_Inventory.ps1` to generate the repository inventory.


⚙️ **Order of operations:**
- **[1/5]** Validate PAT tokens (ADO_PAT and GH_PAT environment variables)
- **[2/5]** Load configuration from `migration-config.json` with parameter overrides
- **[3/5]** Load repository data from CSV file with required columns
- **[4/5]** Execute batched migrations (respects GitHub's 5 concurrent migration limit)
   - **Queue all repos** → `$pendingRepos`
  - **Start initial batch** *(max 5 concurrent)*
  - **For each repo:**
    - Lock ADO repo
    - Queue migration → `gh ado2gh migrate-repo`
    - Extract Migration ID
    - Start monitoring job → `gh ado2gh wait-for-migration`
  - **Monitor loop**
    - Check job completion
    - Record results
    - Start next pending migration
  - **Wait for all jobs to complete**

- **[5/5]** Generate state file and display summary with next steps
  - Export `migration-log-YYYYMMDD-HHMMSS.csv`
  - Export `migration-state-comprehensive-YYYYMMDD-HHMMSS.json`
  - Display summary and next steps

💻 **Script Usage:**
- Reads **repos.csv** from migration-config.json settings: `.\2_migrate_repo.ps1`
- Override the default CSV file path specified in **migration-config.json**: `.\2_migrate_repo.ps1 [-RepoCSV "repos.csv"]`
- Limit parallel migrations (**default: 5, GitHub's maximum concurrent limit**): `.\2_migrate_repo.ps1 [-MaxParallelJobs 3]` 

**🗂️ Output Files generated:**
- state file for automation and follow-up scripts: `migration-state-comprehensive-YYYYMMDD-HHMMSS.json`
- detailed CSV log with `MigrationId` and `GitHubRepoUrl` for analysis: `migration-log-YYYYMMDD-HHMMSS.csv` 


## Script 3: Migration Validation (3_migration_validation.ps1)


📝 **Description:** 


This script validates migrated repositories by retrieving data from both **ADO** source and **GitHub** target. It uses the state file generated by `2_migrate_repo.ps1` to identify repositories to validate. Provides informational comparison of commit and branch counts between systems.

🧰 **Prerequisites:**
- GitHub CLI (gh) installed and authenticated
- ADO_PAT & GH_PAT environment variable set.
- State file from `2_migrate_repo.ps1`


⚙️ **Order of operations:**
- **[1/3]** Load migration state file from 2_migrate_repo.ps1
- **[2/3]** Validate each repository (ADO source and GitHub target)
- **[3/3]** Update state file with validation results

💻 **Script Usage:**
- Automatically finds and uses the latest migration-state-comprehensive-*.json file:: `.\3_migration_validation.ps1`
- Use this when you have multiple migration state files and want to validate a specific one from your migration: `.\3_migration_validation.ps1 -StateFile "migration-state-comprehensive-YYYYMMDD-HHMMSS.json"`


**🗂️ Output Files generated:**
- Updated state file with validation results (commit/branch counts from both systems): `migration-state-comprehensive-YYYYMMDD-HHMMSS.json`
- Console display showing side-by-side comparison
- Timestamped log file (`validation-log-YYYYMMDD-HHmmss.txt`)


## Script 4: Generate Mannequins (4_generate_mannequins.ps1)

📝 **Description:** 

This script generates a CSV file of mannequin users (placeholder accounts) that were created during the migration process. This CSV is used in the next step to reclaim and map these mannequins to actual GitHub users.


🧰 **Prerequisites:**

- GH_PAT environment variable set (GitHub Personal Access Token)
- Repositories must be migrated first (run 2_migrate_repo.ps1)
- migration-config.json configuration file


⚙️ **Order of operations:**
- **[1/3]** Validate GitHub PAT token
- **[2/3]** Load configuration from `migration-config.json`
- **[3/3]** Generate `mannequin.csv` using **gh ado2gh CLI**


💻 **Script Usage:**
- Uses settings from `migration-config.json` (default output: **mannequins.csv**): `.\4_generate_mannequins.ps1`
- Use a custom configuration file: `.\4_generate_mannequins.ps1 [-ConfigPath "migration-config.json"]`
- Generate **mannequins** to a custom CSV file location: `.\4_generate_mannequins.ps1 [-OutputCSV "custom-mannequins.csv"]`


**🗂️ Output Files generated:**
- list of placeholder users requiring GitHub mapping: `mannequins.csv` 


## Script 5: Reclaim Mannequins (5_reclaim_mannequins.ps1)
📝 **Description:** 

This script reclaims **mannequin** users (placeholder accounts) by mapping them to actual **GitHub user accounts**. The **mannequins CSV** should be updated with target **GitHub usernames** before running this script.


🧰 **Prerequisites:**
- **GH_PAT** environment variable set (GitHub Personal Access Token)
- Script 4 **(4_generate_mannequins.ps1)** has been run to generate **mannequins.csv**
- **Mannequins CSV** has been reviewed and updated with **target GitHub usernames**
- **migration-config.json** exists with proper configuration


⚙️ **Order of operations:**
- [1/4] Validate **GitHub PAT** token
- [2/4] Load migration configuration from `migration-config.json`
- [3/4] Validate **mannequins CSV** file exists and contains data
- [4/4] Execute mannequin reclaim using **gh ado2gh CLI**


💻 **Script Usage:**
- Uses settings from **migration-config.json** (default input: mannequins.csv): `.\5_reclaim_mannequins.ps1`
- Use a custom CSV file location instead of the default: `.\5_reclaim_mannequins.ps1 -MannequinsCSV "custom-mannequins.csv"`



**🗂️ Output Files generated:**
- generated by 4_generate_mannequins.ps1, updated with target users: `mannequins.csv` 
- contains GitHub org and CSV path configuration: `migration-config.json`


## Script 6: Rewire Pipelines (6_rewire_pipelines.ps1)
📝 **Description:** 

This script **rewires Azure DevOps pipelines** to use the new **GitHub repositories**. It reads pipeline inventory from `pipelines.csv` and updates **YAML pipelines** to point to the corresponding GitHub repositories using a service connection.


🧰 **Prerequisites:**
- **ADO_PAT** and **GH_PAT** environment variables set
- **GitHub service connection** configured in Azure DevOps
- Migration state file from `2_migrate_repo.ps1`
- `pipelines.csv` from `0_Inventory.ps1`
- `migration-config.json` exists with proper configuration


⚙️ **Order of operations:**
- [1/7] Validate PAT tokens (**ADO_PAT** and **GH_PAT**)
- [2/7] Load configuration from `migration-config.json` with parameter overrides
- [3/7] Load migration state file with successfully migrated repositories
- [4/7] Load pipeline inventory from `pipelines.csv` (source of truth)
- [5/7] Process pipelines from inventory:
  - Query pipeline details (YAML vs Classic, already on GitHub)
  - Skip **Classic pipelines** (require manual rewiring)
  - Skip **pipelines** already rewired to **GitHub**
  - Map **ADO repo** to **GitHub repo** using migration state
- [6/7] Validate **service connections** per project:
  - Query **GitHub service connections** for each project
  - Test connection authentication with dry-run
  - Exclude **projects** with no connections or invalid credentials
- [7/7] **Rewire pipelines** using project-specific service connections


💻 **Script Usage:**
- finds the latest migration state file and uses default settings: `.\6_rewire_pipelines.ps1`
- If you want to use a specific one state file: `.\6_rewire_pipelines.ps1 -StateFile "migration-state-YYYYMMDD-HHMMSS.json"`


**🗂️ Output Files generated:**
- detailed rewiring log: `pipeline-rewiring-log-YYYYMMDD-HHMMSS.txt`


## Script 7: Integrate Boards (7_integrate_boards.ps1)
📝 **Description:** 

This script integrates **Azure Boards**  with the **migrated GitHub repositories**. It reads repository inventory from `repos.csv` and integrates each repository with **Azure Boards** for cross-platform **workItem** linking.

🧰 **Prerequisites:**
- **ADO_PAT** and **GH_PAT** environment variables set
- `repos.csv` from `0_Inventory.ps1`
- Repositories already migrated to GitHub
- Proper **PAT** permissions for **Boards integration**

⚙️ **Order of operations:**
- **[1/5]** Validate PAT tokens (**ADO_PAT** and **GH_PAT**)
- **[2/5]** Load repository inventory from `repos.csv` (source of truth)
- **[3/5]** Check for existing **GitHub connections** (prevent VS403674 error)
- **[4/5]** **Integrate boards** for each repository
- **[5/5]** Generate integration **summary and log**

💻 **Script Usage:**
- Uses repos.csv from the current directory (generated by 0_Inventory.ps1): `.\7_integrate_boards.ps1`
- Specify a different CSV file with repository information: `.\7_integrate_boards.ps1 -ReposFile "custom-repos.csv"`

**🗂️ Output Files generated:**
- detailed integration log: `boards-integration-log-YYYYMMDD-HHmmss.txt`


## Script 8: Disable ADO Repositories (8_disable_ado_repos.ps1)
📝 **Description:** 

This script disables **Azure Devops repositories** after successful migration and validation. It prevents further changes to the source repositories.

🧰 **Prerequisites:**
- **ADO_PAT** and **GH_PAT** environment variables set
- Repositories must be successfully migrated (Step 2 - `2_migrate_repo.ps1`)
- Repositories must be validated (Step 3 - `3_migration_validation.ps1`)
- **Migration state file** from `2_migrate_repo.ps1` must exist
- **GitHub CLI** with `gh-ado2gh` extension installed
- `migration-config.json` configuration file


⚙️ **Order of operations:**
- [1/4] Validate **ADO_PAT** and **GH_PAT** PAT tokens
- [2/4] Load configuration from `migration-config.json` with parameter overrides
- [3/4] Load repository information from **migration state file**
- [4/4] **Disable ADO** repositories (with user confirmation)
  - Display warning about destructive operation
  - Request explicit user confirmation
  - Disable each repository using `gh ado2gh disable-ado-repo`
  - Generate disable report

💻 **Script Usage:**
- finds the latest migration state file and uses default configuration: `.\8_disable_ado_repos.ps1`
- provide a customer statefile: `.\8_disable_ado_repos.ps1 -StateFile "migration-state-20251027-124627.json"`
- Specify a different `migration-config.json` file: `.\8_disable_ado_repos.ps1 -ConfigPath "custom-config.json"`


**🗂️ Output Files generated:**
- repository disable report with audit trail: `disable-report-YYYYMMDD-HHmmss.md`


