@{
    RootModule = 'ChatGptMathTools.psm1'
    ModuleVersion = '0.1.0'
    GUID = '2152f6e5-83f1-47dd-9e63-9eb2a875b8a7'
    Author = 'Contributors'
    CompanyName = ''
    Copyright = '(c) Contributors'
    Description = 'Convert ChatGPT-style math delimiters for Markdown, Logseq, and similar note tools.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Convert-ChatGptMathText',
        'Convert-ChatGptMathFile',
        'Convert-ChatGptMathClipboard'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
