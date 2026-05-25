<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-24T20:45:00+08:00 | Updated: 2026-03-24T20:45:00+08:00 -->

# backups

## Purpose
Directory for storing backup files created by the AutoHotkey v2 Skill Manager. Currently empty as no backup operations have been performed.

## Key Files
(None)

## Subdirectories
(None)

## For AI Agents

### Working In This Directory
- Backup files are created by the BackupManager class in gui.ahk
- Typically contains exported configurations or state snapshots
- Safe to clean contents if needed for testing

### Testing Requirements
- Verify backup functionality through GUI controls
- Ensure restored backups work correctly
- Check that backup files are valid JSON or expected format

### Common Patterns
- Backups are typically timestamped
- Stored as JSON files for configuration data
- May include executable state or module configurations

## Dependencies

### Internal
- Written by BackupManager class in gui.ahk
- Reads from and writes to configuration system

### External
- None

<!-- MANUAL: -->