<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-24T20:45:00+08:00 | Updated: 2026-03-24T20:45:00+08:00 -->

# config_backup

## Purpose
Directory for storing backup configuration files created by the AutoHotkey v2 Skill Manager. Currently empty as no backup operations have been performed.

## Key Files
(None)

## Subdirectories
(None)

## For AI Agents

### Working In This Directory
- Configuration backups are created by the ExportConfigToJson function
- Typically contains exported config.json files at different points in time
- Safe to clean contents if needed for testing

### Testing Requirements
- Verify backup functionality through ExportConfigToJson calls
- Ensure restored configurations work correctly
- Check that backup files are valid JSON

### Common Patterns
- Backups are typically timestamped or versioned
- Stored as JSON files matching config.json format
- May include export presets or configuration snapshots

## Dependencies

### Internal
- Written by ExportConfigToJson function in asd.ahk
- Reads from the global GroupSettings and configuration system

### External
- None

<!-- MANUAL: -->