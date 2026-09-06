<div align="center">

# safari

Read Safari bookmarks, Reading List entries, and history from the command line.

<br/>

![safari in action](https://s.electerious.com/images/aufgabe/readme-day.jpg)

</div>

## Contents

- [Description](#description)
- [Requirements](#requirements)
- [Install](#install)
- [Usage](#usage)
- [Configuration](#configuration)
- [Development](#development)
- [Troubleshooting](#troubleshooting)

## Description

`safari` is a macOS CLI for reading Safari bookmarks, Reading List entries, and history. It reads Safari's local data files without modifying them and supports both human-readable and JSON output.

## Requirements

- macOS
- Bash 3.2 or newer (included with macOS)
- Swift, included with Xcode Command Line Tools
- For testing: [bats-core](https://github.com/bats-core/bats-core), `jq`, and `sqlite3`

## Install

Clone the repository:

```bash
git clone <repository-url>
cd safari
```

Make the script executable:

```bash
chmod +x bin/safari
```

Run it directly:

```bash
bin/safari bookmarks list
bin/safari reading-list list
bin/safari history list
```

Add it to your `PATH` (optional):

```bash
# Using symlink
sudo ln -s "$(pwd)/bin/safari" /usr/local/bin/safari

# Or add the bin directory to your shell profile
export PATH="$PATH:$(pwd)/bin"
```

## Usage

### List Bookmarks

```bash
# List bookmarks
safari bookmarks list

# `ls` is an alias for `list`
safari bookmarks ls
```

Human-readable output includes the folder path and URL:

```
- Favorites / Example
  https://example.com/
```

### List Reading List Entries

```bash
safari reading-list list
safari reading-list ls
```

Human-readable output includes the title and URL:

```
- Article title
  https://example.com/article
```

### List History

```bash
safari history list
safari history ls
```

Human-readable history output includes the page title, visit time, and URL:

```
- Example
  2026-08-31 12:34:56
  https://example.com/
```

### JSON Output

Pass `--json` to either list command:

```bash
safari bookmarks list --json
safari reading-list list --json
safari history list --json
```

### Help and Version

```bash
# Show help
safari --help
safari -h

# Show version
safari --version
safari -v
```

## Configuration

### Environment Variables

- `SAFARI_BOOKMARKS_FILE` - Custom `Bookmarks.plist` path (default: `~/Library/Safari/Bookmarks.plist`)
- `SAFARI_HISTORY_FILE` - Custom `History.db` path (default: `~/Library/Safari/History.db`)

Use a copied plist while developing or testing:

```bash
export SAFARI_BOOKMARKS_FILE="./Bookmarks.plist"
safari bookmarks list
```

The `--file` option can be used instead:

```bash
safari bookmarks list --file ./Bookmarks.plist
safari reading-list list --file ./Bookmarks.plist
safari history list --file ./History.db
```

### Safari Data

Safari stores bookmarks and Reading List entries together in:

```
~/Library/Safari/Bookmarks.plist
```

Safari stores browsing history in:

```
~/Library/Safari/History.db
```

The CLI reads these files directly and never writes to them.

## Development

Install [bats-core](https://github.com/bats-core/bats-core):

```bash
# Using Homebrew
brew install bats-core

# Or using npm
npm install -g bats
```

Run the test suite:

```bash
# Run all tests
bats tests/

# Run with verbose output
bats -t tests/
```

The tests use a sanitized plist fixture and do not access real Safari data.

## Troubleshooting

**Permission denied when reading Safari data**

Recent macOS versions protect Safari data with privacy controls. Grant Full Disk Access to the terminal or application that runs the CLI in System Settings > Privacy & Security > Full Disk Access.

**Bookmarks file not found**

Verify that Safari has created the default file:

```bash
ls -l "$HOME/Library/Safari/Bookmarks.plist"
```

If you are using a copy, check the path passed to `--file` or `SAFARI_BOOKMARKS_FILE`.
