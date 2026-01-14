# Shared Git Hooks

This directory contains shared git hooks for the picframe_3.0 repository.

## Setup

After cloning the repository, run:

```bash
./.githooks/setup.sh
```

Or manually:

```bash
git config core.hooksPath .githooks
```

## Hooks

### pre-commit

Prevents accidental deletion of protected files:
- `.clinerules` - Project coding standards
- `CONTRIBUTING.md` - Contribution guidelines
- `README.md` - Project documentation

To bypass (if you really need to delete a protected file):
```bash
git commit --no-verify
```

## Disable Hooks

To disable shared hooks and use default .git/hooks:

```bash
git config --unset core.hooksPath
```
