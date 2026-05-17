# Archura SyncGuard - Project Independent Version Controller

Archura SyncGuard is a reusable PowerShell-based version controller for Windows projects. It checks the version stored in a GitHub repository, compares it with the local project version, and synchronizes the local project folder when the remote version is newer.

The system does not require Git to be installed on the target machine. It uses GitHub raw file URLs for version checks and GitHub codeload zip downloads for updates.

## SEO Keywords

`#powershell` `#windows` `#github` `#version-control` `#auto-update` `#github-updater` `#windows-automation` `#semver` `#backup` `#sync-tool` `#deployment` `#developer-tools`

## Example Project Structure

```text
ProjectRoot/
  version controller/
    version.md
    version-checker.ps1
    config.json
    update-log.md
    backups/
  README.md
  start.bat
  start.ps1
  app.exe
```

## Installation

1. Place the `version controller` folder in the root directory of your project.
2. Edit `version controller/config.json`.
3. Set `repositoryOwner`, `repositoryName`, and `branch` to match your GitHub repository.
4. Make sure the GitHub repository also contains `version controller/version.md`.
5. Launch your application through `start.bat` instead of starting `app.exe` directly.

## GitHub Repository Settings

If the repository is public, no additional authentication is required.

The script uses these URL patterns:

```text
https://raw.githubusercontent.com/{owner}/{repo}/{branch}/version%20controller/version.md
https://codeload.github.com/{owner}/{repo}/zip/refs/heads/{branch}
```

Private repositories are not supported in this minimal version because the script does not include token-based authentication. To support private repositories, add a GitHub token header to the `Invoke-WebRequest` calls.

## How To Update version.md

Both local and remote version files must contain a single SemVer value:

```text
1.0.0
```

To publish a new release, increase the value in the GitHub repository:

```text
1.0.1
1.1.0
2.0.0
```

When the script detects that the remote version is newer than the local version, it starts the update process.

## SemVer Rules

The supported version format is:

```text
MAJOR.MINOR.PATCH
```

Versions are compared numerically, not as strings:

```text
1.0.10 > 1.0.2
2.0.0 > 1.9.9
1.1.0 > 1.0.9
```

Pre-release labels and build metadata are not supported in this basic implementation. Valid examples are `1.0.0`, `1.0.1`, and `2.1.1`.

## config.json Reference

```json
{
  "repositoryOwner": "USER_NAME",
  "repositoryName": "REPOSITORY_NAME",
  "branch": "main",
  "versionFilePath": "version controller/version.md",
  "downloadMode": "zip",
  "excludeFiles": [
    "version controller/config.json",
    ".env",
    "user-data.json",
    "settings.local.json"
  ],
  "backupBeforeUpdate": true,
  "backupFolder": "version controller/backups",
  "autoRestartAfterUpdate": false,
  "startCommand": "start.bat"
}
```

Fields:

- `repositoryOwner`: GitHub user or organization name.
- `repositoryName`: GitHub repository name.
- `branch`: Branch to check. Usually `main`.
- `versionFilePath`: Path to the version file in both the local project and the remote repository.
- `downloadMode`: Must be `zip` in this version.
- `excludeFiles`: Local files that must not be overwritten or deleted during updates.
- `backupBeforeUpdate`: Enables or disables backup creation before updates.
- `backupFolder`: Relative path where backup folders are stored.
- `autoRestartAfterUpdate`: Runs `startCommand` after a successful update when enabled.
- `startCommand`: Command used for optional automatic restart.

## Using start.bat

`start.bat` runs the version checker first, then starts the main application:

```bat
@echo off
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1"
start "" "app.exe"
```

The included `start.bat` is slightly safer: it changes into the project root with `pushd` and shows a clear warning when `app.exe` is missing.

## Using start.ps1

PowerShell alternative:

```powershell
powershell -ExecutionPolicy Bypass -File ".\start.ps1"
```

`start.ps1` detects the project root, runs the update check, and then starts `app.exe`.

## Update Check Before Starting app.exe

Users should launch the project through `start.bat` instead of opening `app.exe` directly.

Flow:

1. `start.bat` starts.
2. `version-checker.ps1` reads the local and remote versions.
3. If the remote version is newer, the repository zip is downloaded and the project is synchronized.
4. If an error occurs, the error is logged and the application can still continue starting.

## Command Examples

```powershell
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1"
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --check-only
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --force
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --restore-latest-backup
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --no-backup
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --silent
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --help
```

## Parameters

- `--check-only`: Checks whether an update is available. It does not download or modify files.
- `--force`: Downloads and synchronizes files even when the local and remote versions are equal.
- `--silent`: Reduces console output.
- `--restore-latest-backup`: Restores the most recent backup.
- `--no-backup`: Skips backup creation for the current run, even if backups are enabled in config.
- `--help`: Shows usage information.

## excludeFiles Behavior

Relative paths listed in `excludeFiles` are protected during updates:

```json
[
  "version controller/config.json",
  ".env",
  "user-data.json",
  "settings.local.json"
]
```

These files are not overwritten even if they exist in the remote zip. They are also not deleted if they do not exist in the remote repository.

The script also protects `.git`, `version controller/backups`, and `version controller/update-log.md` internally.

## Backup System

When `backupBeforeUpdate` is set to `true`, a timestamped backup is created before updating:

```text
version controller/backups/backup-2026-05-17-14-30-00
```

If an update fails halfway through, the script can ask whether the latest backup should be restored in interactive mode.

Manual restore command:

```powershell
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --restore-latest-backup
```

## Logging

Every run is written to `version controller/update-log.md`.

The log includes:

- Date and time
- Local version
- Remote version
- Whether an update was performed
- Changed files
- Error details, if any

## Troubleshooting

`config.json not found`: The script creates a sample config file. Fill in the GitHub repository details.

`repositoryOwner and repositoryName must be updated`: Replace placeholder values with real GitHub repository information.

`Local version.md not found`: Create `version controller/version.md` and write a valid SemVer value such as `1.0.0`.

`Could not read GitHub remote version`: Check your internet connection, repository name, branch name, and version file path.

`Zip download failed`: Check GitHub availability, the branch name, and whether the repository is public or private.

`Invalid SemVer`: Values such as `1.0`, `v1.0.0`, or `1.0.0-beta` are not valid for this basic version. Use `1.0.0`.

Execution policy error: `start.bat` already uses `-ExecutionPolicy Bypass`. Use the same option when running the script manually.

## Common Mistakes

- Placing `version.md` at the repository root while the config expects `version controller/version.md`.
- Using a `master` branch while the config is still set to `main`.
- Writing `v1.0.0` instead of `1.0.0`.
- Forgetting to add `.env` or other local-only files to `excludeFiles`.
- Enabling `autoRestartAfterUpdate` while also starting the app again from `start.bat`.

## Behavior Summary

- If the remote version is newer than the local version, an update is performed.
- If both versions are equal, no download is performed.
- If the remote version is older than the local version, the script shows a warning and does nothing.
- If `--force` is used, synchronization runs even when versions are equal.
- Errors are logged and do not prevent the application startup flow from continuing.
