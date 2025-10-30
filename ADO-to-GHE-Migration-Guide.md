# Migrating from Azure DevOps to GitHub Enterprise: A Hybrid Approach

As organizations modernize their DevOps ecosystems, many are moving from Azure DevOps (ADO) to GitHub Enterprise (GHE) to consolidate development workflows, improve collaboration, and adopt modern CI/CD practices.

However, migrating from ADO to GHE is far more complex than simply moving code repositories. Because of platform feature parity differences, not all components—such as boards, pipelines, wikis, test plans, and artifacts—can be migrated seamlessly without affecting ongoing software development.

## ⚙️ Understanding the Migration Challenge

While pipelines can be partially migrated using the GitHub Importer tool, Microsoft's documentation notes that only about 80% of pipelines can be transferred automatically. The remaining 20% often require manual configuration or rewrites within GitHub Actions.

Similarly, Azure Boards differ significantly from GitHub Issues and GitHub Projects, meaning organizations will need to plan carefully, allocate time, and redesign workflows for complete project management migration.

Attempting to migrate everything at once can lead to disruptions in CI/CD operations and developer productivity. The key, therefore, is to **evolve, not replace** and that's where the hybrid approach comes in.

## 🌐 Why a Hybrid Approach Works

To overcome these challenges, a hybrid approach provides the best balance allowing you to leverage the strengths of both platforms while maintaining operational continuity.

In this model, your organization pays only for GitHub Enterprise licenses, which also include Azure DevOps entitlements, allowing you to use both environments without additional cost overhead [1].

### 🎯 The Goal of the Hybrid Model

- **Migrate repositories** → Move your codebase to GitHub Enterprise for a modern source control experience and collaborative workflows.
- **Retain Azure DevOps** → Continue using ADO for pipelines, testing, artifact management, and project tracking.
- **Enable seamless integration** → Connect both systems so your development teams can continue their CI/CD and project workflows without disruption.

This approach ensures that repositories are seamlessly migrated, pipelines remain connected, and work-item tracking stays fully synchronized empowering teams to modernize without downtime while leveraging the best capabilities of both platforms.

Over time, this approach gives your organization the flexibility to plan and execute a complete platform migration, including rewriting pipelines in GitHub Actions and adopting GitHub Issues and Projects for unified project management.

## 🗺️ Visual Overview: ADO to GHE Migration Process Flow

This visual framework represents a six-phase structured approach for migrating repositories and integrating workflows between Azure DevOps and GitHub Enterprise. The sequence ensures minimal disruption, complete validation, and full continuity of your CI/CD and work item management processes.

---

## 1️⃣ Prerequisites: Pre-Migration Configuration

### 🔐 Install the GitHub CLI

Install the GitHub CLI on your machine to interact with GitHub directly from the terminal. You can download it from the [GitHub CLI official site](https://cli.github.com/).

### 🔌 Install the ADO2GH Extension

Once the GitHub CLI is installed, add the ADO2GH extension to enable Azure DevOps to GitHub migration commands:

```bash
gh extension install github/gh-ado2gh
```

💡 **Tip:** Keep both the GitHub CLI and the ADO2GH extension updated to ensure compatibility with the latest migration features.

### Authenticate with GitHub

Authenticate the GitHub CLI with your GitHub account for the specified hostname:

```bash
gh auth login --hostname github.com
```

### 🔐 Generate Personal Access Tokens

Generate Personal Access Tokens for both Azure DevOps and GitHub Enterprise with the required access privileges.

#### 🔑 Azure DevOps PAT

Grant **Full Access** permissions to enable complete control during repository migration. This token is used for authenticating with Azure DevOps services such as Repositories, Pipelines, and Service Connections.

#### 🔑 GitHub Enterprise PAT

Grant the following specific scopes to ensure proper access for migration and integration tasks:

- `repo` – Full control of private repositories
- `workflow` – Manage and trigger GitHub Actions workflows
- `admin:org` – Full control of organizations and teams
- `user:read` – Read user profile data
- `write:discussion` – Create and manage discussions

💡 **Note:** Store these tokens securely as environment variables before running any migration scripts.

```powershell
$env:ADO_PAT = "YOUR-ADO-PAT"
$env:GH_PAT = "YOUR-GH-PAT"
```

### 🌐 Create Service Connections

Establish trusted connectivity for pipelines and integration tasks between ADO and GHE. Service connections are made at org and project level in ADO but can be shared across all projects using UI or CLI.

```bash
# List all connections in an ADO repo
az devops service-endpoint list --organization https://dev.azure.com/<your-ado-org> --project <your-ado-project>
```

---

## 2️⃣ Planning: Preparing for a Controlled Migration

To plan the migration strategically by classifying repositories, defining priorities, and scheduling migration windows to avoid impacting active development.

### 📊 Run Azure DevOps Inventory Report

Start by running the Azure DevOps Inventory Report, which provides a list of repositories along with their associated pipeline details. This helps in identifying which repositories are in scope for migration.

```bash
gh ado2gh inventory-report --ado-org "your-ado-org"
```

### Classify Repositories by Size or Tier

Use categories such as **small, medium, large** or **hot, warm, cold, archive** to plan migration.

After identifying the repositories, perform a T-shirt sizing exercise to classify them into:

**Example:**
- **Small** (repos size <200MB)
- **Medium** (repo size 200MB-1GB)
- **Large** (repo size >1GB)

**Prioritize migrations based on:**
- Expected CI/CD process downtime
- Post-migration validation effort required

### Plan SCM Downtime Window

Schedule a migration window that minimizes disruption to active development and CI/CD operations.

### Prepare a Post-Migration Validation Plan

Define validation checks (commit history, branches, tags, pipelines triggers, Azure boards etc.) to ensure completeness after migration.

---

## 3️⃣ Migration: Moving Repositories to GitHub Enterprise

To execute the core repository migration process while maintaining version history, integrity, and traceability of source control data.

### Check for Active Pipelines or Pull Requests

Before executing the repository migration, it's strongly recommended to verify that there are no in-progress pipelines or active pull requests within the Azure DevOps team project. Running a migration while these processes are active may lead to:

- Incomplete or inconsistent migration results
- Potential data loss or missing repository information

**To avoid such issues:**

✅ Check for any in-progress pipelines at the team project level  
✅ Review and close or merge any active pull requests

💡 **Tip:** Always perform this validation step before locking and migrating repositories to ensure data consistency and a clean migration process.

```bash
# If you don't know the pipeline IDs, list all pipelines currently in progress:
az pipelines runs list --project $TeamProject --status inProgress --output table

# If you have pipeline IDs, get detailed runs for a specific pipeline:
az pipelines runs list --project $TeamProject --status inProgress --output table
```

### Lock ADO Repository (Read-Only Mode)

Prevent changes during migration to ensure consistency.

It's highly recommended to perform a **Proof of Concept or Pilot Migration** with 2-3 representative repositories. This helps validate the end-to-end workflow, identify gaps, and fine-tune automation scripts before scaling to bulk migrations.

🚀 **Note:** Before starting the migration, ensure:
- Your GitHub organization, teams, and user permissions are properly configured
- The destination repository name has been finalized but not yet created — it will be created automatically during the migration process

```bash
# Lock the ADO repository:
gh ado2gh lock-ado-repo --ado-org $ADO_ORG --ado-team-project $ADO_TEAM_PROJECT --ado-repo $ADO_REPO
```

### Execute Repository Migration

Use the ADO2GH CLI extension to migrate repositories with full commit history, branches, and tags.

```bash
# Migrate ADO repo to GitHub
gh ado2gh migrate-repo --ado-org <ORG> --ado-team-project <PROJECT> --ado-repo <REPO> --github-org <GITHUB_ORG> --github-repo <GITHUB_REPO>
```

### 👥 Mannequin User Management

After migrating repositories using the ADO2GH extension of the GitHub CLI, GitHub creates "mannequin" users whenever Azure DevOps user accounts can't be matched to GitHub accounts — such as when email addresses differ or users haven't joined the organization yet. These mannequins preserve historical actions like issues, pull requests, and comments without losing attribution context.

You can validate mannequins post-migration by generating a list using:

```bash
gh ado2gh generate-mannequin-csv --github-org <org> --output mannequins.csv
```

This CSV allows administrators to review which placeholder identities exist and prepare the corresponding GitHub usernames for reclaiming.

**Reclaiming mannequins** links these placeholder identities to actual GitHub organization members, thereby reattributing activity history. It ensures historical PRs, issues, and comments display the correct user identity instead of a mannequin placeholder.

```bash
gh ado2gh reclaim-mannequin --github-org <org> --csv mannequins.csv
```

If using Enterprise Managed Users (EMU), you can skip the acceptance prompt by adding `--skip-invitation`. Once accepted, the mannequin's history fully transfers to the mapped account.

---

## 4️⃣ Post-Migration Validation

After each migration, repository owners should conduct post-migration validation, either manually or using automated scripts.

**Recommended validation checks include:**

- 🔁 Commit history
- 🌿 Branches
- 🏷️ Tags and releases
- 📦 Repository size
- 🌐 Default branch
- ⚙️ Build and pipeline validation (only after the rewiring step is complete)

These checks are performed against the repositories that have been migrated to GitHub Enterprise.

### GitHub Enterprise Validation Commands

```powershell
## Get list of migrated repositories
gh repo view "$GITHUB_ORG/$repo" --json name,description,createdAt,diskUsage,defaultBranchRef | ConvertFrom-Json

## Check for branch protection
gh api "/repos/$GITHUB_ORG/$repo/branches/main/protection" --silent | Out-Null

## Check recent activity
gh api "/repos/$GITHUB_ORG/$repo/commits" | ConvertFrom-Json | Select-Object -First 1
```

### Azure DevOps Validation Commands

You can now perform similar validation checks on the Azure DevOps repositories to verify and cross-check the migration results.

```powershell
# Get repository details (similar to gh repo view):
az repos show --repository $repo --project $TeamProject --output json | ConvertFrom-Json

# Check branch protection on a branch (similar to GHE branch protection check):
az repos policy list --project $TeamProject --repository-id $repoId | ConvertFrom-Json

# You can get repository ID using:
az repos show --repository $repo --project $TeamProject --query id

# Check recent commit activity (similar to gh api /commits):
az repos pr list --repository $repo --project $TeamProject --top 1 --output json | ConvertFrom-Json
```

⚠️ **Note:** The only rollback option is to delete the GitHub repository and repeat the migration step.

---

## 5️⃣ ADO - GHE Integration: Enabling Hybrid Workflows

To connect ADO and GHE so development teams can continue using both platforms in a synchronized, hybrid model during the transition period.

### Rewire ADO Pipelines

Now that the migration and post-migration validation are successfully completed, the next step is to verify the service connection between GitHub Enterprise and Azure DevOps.

Once the service endpoint is confirmed, proceed to rewire the pipelines — this means updating each pipeline's source repository to point to the newly migrated repository in GitHub.

⚙️ **This step is critical** to ensure that your CI/CD processes continue seamlessly in the hybrid DevOps model, maintaining workflow continuity without any disruptions.

```bash
## List all service connections in a specified Azure DevOps project
az devops service-endpoint list --org https://dev.azure.com/<ADO_ORG_NAME> --project <ADO_PROJECT_NAME> --query "[?name=='<SERVICE_CONNECTION_NAME>'].id" -o tsv

# Rewire the pipeline
gh ado2gh rewire-pipeline --ado-org "<ADO_ORG_NAME>" --ado-team-project "<ADO_PROJECT_NAME>" --ado-pipeline "<ADO_PIPELINE_NAME>" --github-org "<GITHUB_ORG_NAME>" --github-repo "<GITHUB_REPO_NAME>" --service-connection-id "<SERVICE_CONNECTION_ID>"
```

### Integrate Azure Boards with GHE

Link ADO work items to GitHub pull requests, allowing status updates.

Integration between Azure Boards and GitHub Enterprise requires a GitHub PAT with these scopes: `repo`, `admin:repo_hook`, `read:user`, and `user:email`.

```bash
gh ado2gh integrate-boards --github-org <github-org> --github-repo <github-repo> --ado-org <ado-org> --ado-team-project <team-project>
```

### Disable ADO Repositories

Now that the rewiring and pipeline testing are complete, proceed to the next phase - **Disabling the Azure DevOps repositories**. This step ensures that no further changes or activities occur on the ADO repository.

```bash
# Avoid any activities on the ADO repo; disable it by command:
gh ado2gh disable-ado-repo --ado-org $ADO_ORG --ado-team-project $ADO_TEAM_PROJECT --ado-repo $ADO_REPO
```

---

## 6️⃣ Post-Integration Validation: Ensuring End-to-End Consistency

To verify that the migration and integration are successful, ensuring both platforms operate in harmony and no data or workflow integrity has been lost.

### Validate Pipeline Triggers

Confirm that commits or pull requests from GHE correctly trigger builds and releases in ADO.

### Validate Work Item Sync

Ensure that linked work items in Azure Boards are automatically updated based on activity in GitHub (e.g., PR merged, status changed).

---

## Conclusion

By following these six phases—**Prerequisites → Planning → Migration → Post-Migration Validation → Integration → Post-Integration Validation**—organizations can achieve a smooth, low-risk transition from Azure DevOps to GitHub Enterprise.

Ultimately, your teams gain the agility of GitHub's ecosystem while maintaining the reliability of existing ADO infrastructure during the transformation journey.

---

## 🤖 Automation Scripts

For bulk migrations and to streamline the entire process, I've created a comprehensive set of PowerShell automation scripts that implement all the steps outlined in this workflow.
