#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ResolvedChatGptMathFilePaths {
    param(
        [string[]]$InputPaths
    )

    $resolved = New-Object System.Collections.Generic.List[string]

    foreach ($inputPath in $InputPaths) {
        $items = Resolve-Path -Path $inputPath -ErrorAction Stop
        foreach ($item in $items) {
            $literalPath = $item.ProviderPath
            if (-not (Test-Path -LiteralPath $literalPath -PathType Leaf)) {
                throw "Path is not a file: $literalPath"
            }

            $resolved.Add($literalPath)
        }
    }

    return $resolved
}

function Ensure-DirectoryExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    }
}

function Ensure-ParentDirectoryExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $directory = Split-Path -Path $FilePath -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        Ensure-DirectoryExists -Path $directory
    }
}

function Get-ChatGptMathFileEncodingInfo {
    param(
        [byte[]]$Bytes
    )

    if ($Bytes.Length -ge 4) {
        if (($Bytes[0] -eq 0xFF) -and ($Bytes[1] -eq 0xFE) -and ($Bytes[2] -eq 0x00) -and ($Bytes[3] -eq 0x00)) {
            return @{
                Encoding = [System.Text.UTF32Encoding]::new($false, $true)
                Preamble = [byte[]](0xFF, 0xFE, 0x00, 0x00)
            }
        }

        if (($Bytes[0] -eq 0x00) -and ($Bytes[1] -eq 0x00) -and ($Bytes[2] -eq 0xFE) -and ($Bytes[3] -eq 0xFF)) {
            return @{
                Encoding = [System.Text.UTF32Encoding]::new($true, $true)
                Preamble = [byte[]](0x00, 0x00, 0xFE, 0xFF)
            }
        }
    }

    if ($Bytes.Length -ge 3) {
        if (($Bytes[0] -eq 0xEF) -and ($Bytes[1] -eq 0xBB) -and ($Bytes[2] -eq 0xBF)) {
            return @{
                Encoding = [System.Text.UTF8Encoding]::new($true, $true)
                Preamble = [byte[]](0xEF, 0xBB, 0xBF)
            }
        }
    }

    if ($Bytes.Length -ge 2) {
        if (($Bytes[0] -eq 0xFF) -and ($Bytes[1] -eq 0xFE)) {
            return @{
                Encoding = [System.Text.UnicodeEncoding]::new($false, $true, $true)
                Preamble = [byte[]](0xFF, 0xFE)
            }
        }

        if (($Bytes[0] -eq 0xFE) -and ($Bytes[1] -eq 0xFF)) {
            return @{
                Encoding = [System.Text.UnicodeEncoding]::new($true, $true, $true)
                Preamble = [byte[]](0xFE, 0xFF)
            }
        }
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)

    try {
        [void]$utf8NoBom.GetString($Bytes)
        return @{
            Encoding = $utf8NoBom
            Preamble = [byte[]]@()
        }
    }
    catch {
        return @{
            Encoding = [System.Text.Encoding]::Default
            Preamble = [byte[]]@()
        }
    }
}

function Get-MatchingClosingParenthesisIndex {
    param(
        [string]$Text,
        [int]$OpenIndex
    )

    $depth = 0

    for ($i = $OpenIndex; $i -lt $Text.Length; $i++) {
        $char = $Text[$i]

        if ($char -eq '(') {
            $depth++
            continue
        }

        if ($char -eq ')') {
            $depth--
            if ($depth -eq 0) {
                return $i
            }
        }
    }

    return -1
}

function Test-MathLikeContent {
    param(
        [string]$Candidate
    )

    $trimmed = $Candidate.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $false
    }

    if ($trimmed -match '\\[A-Za-z]+') {
        return $true
    }

    if ($trimmed -match '[_^{}=<>]') {
        return $true
    }

    if ($trimmed -match '^\[[A-Za-z](\s*,\s*[A-Za-z0-9\\]+)+\]$') {
        return $true
    }

    if ($trimmed -match '^\([A-Za-z](\s*,\s*[A-Za-z0-9\\]+)+\)$') {
        return $true
    }

    if ($trimmed -match '^\([0-9.]+(\s*,\s*[0-9.]+)+\)$') {
        return $true
    }

    if ($trimmed -match '^[A-Za-z](\s*,\s*[A-Za-z0-9\\]+)+$') {
        return $true
    }

    if ($trimmed -match '^[A-Za-z]$') {
        return $true
    }

    if ($trimmed -match '^[A-Z]{2,5}$') {
        return $true
    }

    if ($trimmed -match '^[A-Za-z0-9\\]+(?:_[A-Za-z0-9\\{}]+)+$') {
        return $true
    }

    if ($trimmed -match '^[A-Za-z0-9\\%]+(?:\s*[=<>~]\s*[A-Za-z0-9\\%+\-./]+)+$') {
        return $true
    }

    if ($trimmed -match '^[A-Za-z](?:\s*[-+*/]\s*[A-Za-z0-9\\_{}]+)+$') {
        return $true
    }

    return $false
}

<#
.SYNOPSIS
Converts ChatGPT-style math delimiters in a text string.

.DESCRIPTION
Converts inline math from \(...\) to $...$ and block math from \[...\] to $$...$$.
It also recognizes common stripped variants where the backslashes are missing,
while avoiding fenced code blocks and inline code spans.

.PARAMETER Text
The text to convert.

.EXAMPLE
'Inline: \(x+y\)' | Convert-ChatGptMathText
#>
function Convert-ChatGptMathText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    process {
        $lineEnding = "`n"
        if ($Text.Contains("`r`n")) {
            $lineEnding = "`r`n"
        }
        elseif ($Text.Contains("`r")) {
            $lineEnding = "`r"
        }

        $hasTrailingNewline = $Text -match "(`r`n|`n|`r)$"
        $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
        $lines = $normalized -split "`n"
        if ($hasTrailingNewline -and $lines.Length -gt 0 -and $lines[$lines.Length - 1] -eq '') {
            if ($lines.Length -eq 1) {
                $lines = @()
            }
            else {
                $lines = $lines[0..($lines.Length - 2)]
            }
        }

        $convertedLines = New-Object System.Collections.Generic.List[string]
        $inFence = $false
        $inMathBlock = $false

        foreach ($line in $lines) {
            if ($line -match '^\s*(```|~~~)') {
                $inFence = -not $inFence
                $convertedLines.Add($line)
                continue
            }

            if ($inFence) {
                $convertedLines.Add($line)
                continue
            }

            if ($line -match '^(\s*)(\\)?\[(\s*)$') {
                $inMathBlock = $true
                $convertedLines.Add("$($matches[1])`$`$$($matches[3])")
                continue
            }

            if ($line -match '^(\s*)(\\)?\](\s*)$') {
                $inMathBlock = $false
                $convertedLines.Add("$($matches[1])`$`$$($matches[3])")
                continue
            }

            if ($inMathBlock) {
                $convertedLines.Add($line)
                continue
            }

            $builder = New-Object System.Text.StringBuilder
            $inInlineCode = $false
            $index = 0

            while ($index -lt $line.Length) {
                $char = $line[$index]

                if ($char -eq '`') {
                    $inInlineCode = -not $inInlineCode
                    [void]$builder.Append($char)
                    $index++
                    continue
                }

                if (-not $inInlineCode -and $char -eq '\' -and ($index + 1) -lt $line.Length) {
                    $next = $line[$index + 1]

                    if ($next -eq '(' -or $next -eq ')') {
                        [void]$builder.Append('$')
                        $index += 2
                        continue
                    }

                    if ($next -eq '[' -or $next -eq ']') {
                        [void]$builder.Append('$$')
                        $index += 2
                        continue
                    }
                }

                if (-not $inInlineCode -and $char -eq '(' -and ($index -eq 0 -or $line[$index - 1] -ne ']')) {
                    $closingIndex = Get-MatchingClosingParenthesisIndex -Text $line -OpenIndex $index
                    if ($closingIndex -gt $index) {
                        $candidate = $line.Substring($index + 1, $closingIndex - $index - 1)
                        if (Test-MathLikeContent -Candidate $candidate) {
                            [void]$builder.Append('$')
                            [void]$builder.Append($candidate)
                            [void]$builder.Append('$')
                            $index = $closingIndex + 1
                            continue
                        }
                    }
                }

                [void]$builder.Append($char)
                $index++
            }

            $convertedLines.Add($builder.ToString())
        }

        $result = $convertedLines -join $lineEnding
        if ($hasTrailingNewline) {
            $result += $lineEnding
        }

        return $result
    }
}

function Get-ChatGptMathOutputPath {
    param(
        [string]$InputPath,
        [bool]$WriteInPlace,
        [string]$OutputSuffix
    )

    if ($WriteInPlace) {
        return $InputPath
    }

    $directory = Split-Path -Path $InputPath -Parent
    $extension = [System.IO.Path]::GetExtension($InputPath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    return [System.IO.Path]::Combine($directory, "$baseName$OutputSuffix$extension")
}

function Get-DefaultChatGptMathClipboardBackupPath {
    $dateFolder = Get-Date -Format 'yyyy-MM-dd'
    $timestamp = Get-Date -Format 'HHmmss-fff'
    $backupDirectory = [System.IO.Path]::Combine($PSScriptRoot, 'clipboard-backups', $dateFolder)

    Ensure-DirectoryExists -Path $backupDirectory

    return [System.IO.Path]::Combine($backupDirectory, "chatgpt-math-clipboard-backup-$timestamp.md")
}

<#
.SYNOPSIS
Converts ChatGPT-style math delimiters in one or more files.

.DESCRIPTION
Reads the source file using its detected text encoding, converts supported math delimiters,
and writes either an in-place update or a sibling file with a suffix such as `.converted`.

.PARAMETER InputPath
One or more file paths to convert.

.PARAMETER InPlace
Overwrite the original file instead of writing a sibling output file.

.PARAMETER Suffix
The suffix inserted before the file extension when not using -InPlace.

.EXAMPLE
Convert-ChatGptMathFile -InputPath '.\note.md'

.EXAMPLE
Convert-ChatGptMathFile -InputPath '.\note.md' -InPlace
#>
function Convert-ChatGptMathFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [Alias('Path', 'FullName')]
        [string[]]$InputPath,

        [switch]$InPlace,

        [string]$Suffix = '.converted'
    )

    $filePaths = Get-ResolvedChatGptMathFilePaths -InputPaths $InputPath

    foreach ($filePath in $filePaths) {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $encodingInfo = Get-ChatGptMathFileEncodingInfo -Bytes $bytes
        $encoding = $encodingInfo.Encoding
        $preamble = $encodingInfo.Preamble
        $contentStart = $preamble.Length
        $contentLength = $bytes.Length - $contentStart

        if ($contentLength -lt 0) {
            throw "Unable to read file content: $filePath"
        }

        $content = $encoding.GetString($bytes, $contentStart, $contentLength)
        $converted = Convert-ChatGptMathText -Text $content
        $outputPath = Get-ChatGptMathOutputPath -InputPath $filePath -WriteInPlace:$InPlace.IsPresent -OutputSuffix $Suffix
        $convertedBytes = $encoding.GetBytes($converted)
        $outputBytes = New-Object byte[] ($preamble.Length + $convertedBytes.Length)

        if ($preamble.Length -gt 0) {
            [System.Array]::Copy($preamble, 0, $outputBytes, 0, $preamble.Length)
        }

        if ($convertedBytes.Length -gt 0) {
            [System.Array]::Copy($convertedBytes, 0, $outputBytes, $preamble.Length, $convertedBytes.Length)
        }

        [System.IO.File]::WriteAllBytes($outputPath, $outputBytes)
        [PSCustomObject]@{
            InputPath = $filePath
            OutputPath = $outputPath
            InPlace = $InPlace.IsPresent
        }
    }
}

<#
.SYNOPSIS
Converts clipboard text and writes the converted result back to the clipboard.

.DESCRIPTION
Reads plain text from the clipboard, optionally writes a Markdown backup file,
converts supported math delimiters, and stores the result back in the clipboard.

.PARAMETER BackupPath
Optional explicit path for the clipboard backup file.

.PARAMETER NoBackup
Skip writing the clipboard backup file.

.PARAMETER PassThru
Return the converted text instead of a status object.

.EXAMPLE
Convert-ChatGptMathClipboard

.EXAMPLE
Convert-ChatGptMathClipboard -NoBackup -PassThru
#>
function Convert-ChatGptMathClipboard {
    [CmdletBinding()]
    param(
        [string]$BackupPath,

        [switch]$NoBackup,

        [switch]$PassThru
    )

    $clipboardText = Get-Clipboard -Raw
    if ($null -eq $clipboardText) {
        throw 'The clipboard does not contain text content.'
    }

    if (-not $NoBackup) {
        if ([string]::IsNullOrWhiteSpace($BackupPath)) {
            $BackupPath = Get-DefaultChatGptMathClipboardBackupPath
        }

        Ensure-ParentDirectoryExists -FilePath $BackupPath
        $backupEncoding = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($BackupPath, $clipboardText, $backupEncoding)
    }

    $converted = Convert-ChatGptMathText -Text $clipboardText
    Set-Clipboard -Value $converted

    if ($PassThru) {
        return $converted
    }

    [PSCustomObject]@{
        BackupPath = if ($NoBackup) { $null } else { $BackupPath }
        ClipboardUpdated = $true
    }
}

Export-ModuleMember -Function Convert-ChatGptMathText, Convert-ChatGptMathFile, Convert-ChatGptMathClipboard
