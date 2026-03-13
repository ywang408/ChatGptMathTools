# ChatGptMathTools

~~Vibe Coding Project~~

PowerShell tools for converting ChatGPT-style math delimiters into Markdown-friendly delimiters used by VS Code Markdown extensions, Obsidian, and similar note tools.

Supported conversions:

- `\(...\)` -> `$...$`
- `\[...\]` -> `$$ ... $$`
- common stripped variants such as `(x^2)` and bare block lines `[` / `]` when they still look math-like

The converter skips fenced code blocks and inline code spans.

## Repo layout

- [`ChatGptMathTools.psm1`](./ChatGptMathTools.psm1): module implementation
- [`ChatGptMathTools.psd1`](./ChatGptMathTools.psd1): module manifest
- [`Convert-ChatGptMathClipboard.ps1`](./Convert-ChatGptMathClipboard.ps1): clipboard wrapper script
- [`Convert-ChatGptMathDelimiters.ps1`](./Convert-ChatGptMathDelimiters.ps1): file conversion wrapper script
- [`PowerShellProfile.ChatGptMath.example.ps1`](./PowerShellProfile.ChatGptMath.example.ps1): example profile snippet
- [`mathclip.cmd`](./mathclip.cmd): launcher for execution-policy-restricted environments

## Quick start

If you only want a one-off clipboard command from the repository folder:

```powershell
.\mathclip.cmd
```

That command:

1. reads plain text from the clipboard
2. saves a Markdown backup
3. converts supported math delimiters
4. writes the converted text back to the clipboard

To convert files:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-ChatGptMathDelimiters.ps1 .\note.md
powershell -ExecutionPolicy Bypass -File .\Convert-ChatGptMathDelimiters.ps1 .\note.md -InPlace
```

## Install as a module

For a clean long-term setup, place the repository in a standard PowerShell module directory under a folder named `ChatGptMathTools`.

Windows PowerShell 5.1 user module path:

```text
$HOME\Documents\WindowsPowerShell\Modules\ChatGptMathTools
```

PowerShell 7 user module path:

```text
$HOME\Documents\PowerShell\Modules\ChatGptMathTools
```

Once the folder is there, you can import it by name:

```powershell
Import-Module ChatGptMathTools -Force
```

Available commands:

```powershell
Convert-ChatGptMathClipboard
Convert-ChatGptMathClipboard -NoBackup
Convert-ChatGptMathFile -InputPath .\note.md
'Inline: \(x+y\)' | Convert-ChatGptMathText
```

## Put it in your PowerShell profile

If you want `mathclip` and `mathfile` available in every PowerShell session, add this to your profile:

```powershell
Import-Module ChatGptMathTools -Force

function mathclip {
    Convert-ChatGptMathClipboard @args
}

function mathfile {
    Convert-ChatGptMathFile @args
}
```

You can use [`PowerShellProfile.ChatGptMath.example.ps1`](./PowerShellProfile.ChatGptMath.example.ps1) as the starting point.

If your current execution policy blocks profile/module loading, the lowest-impact temporary option is:

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
```

If you want profile loading to work persistently for your own user account:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Use `CurrentUser`, not `LocalMachine`, unless you intentionally want a machine-wide change.

## Backup behavior

By default, clipboard backups are written under a dated folder tree relative to the module/script location:

```text
clipboard-backups\YYYY-MM-DD\chatgpt-math-clipboard-backup-HHmmss-fff.md
```

Example:

```text
clipboard-backups\2026-03-12\chatgpt-math-clipboard-backup-221530-418.md
```

You can override the backup path:

```powershell
Convert-ChatGptMathClipboard -BackupPath 'D:\NoteBackups\mathclip\backup.md'
```

Or skip the backup:

```powershell
Convert-ChatGptMathClipboard -NoBackup
```

## Safety notes

- Clipboard conversion overwrites the current clipboard text with the converted plain-text result.
- Clipboard backups are plain Markdown text files. Clipboard formatting such as HTML, rich text, or images is not preserved.
- The stripped-parentheses support is heuristic. It works well for common copied ChatGPT output, but rare false positives are possible in plain prose.
- The repository ignores generated backup folders and converted output files through [`.gitignore`](./.gitignore), so normal use should not clutter commits.

## Notes for contributors

- The module targets PowerShell 5.1+.
- Wrapper scripts are thin entry points around the module so the core behavior stays in one place.
- Public-facing docs and examples intentionally avoid machine-specific usernames and absolute paths.
