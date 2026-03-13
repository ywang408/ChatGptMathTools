Import-Module ChatGptMathTools -Force

function mathclip {
    Convert-ChatGptMathClipboard @args
}

function mathfile {
    Convert-ChatGptMathFile @args
}
