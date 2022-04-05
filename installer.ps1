#!/usr/bin/env pwsh

#requires -version 3.0

<#
.SYNOPSIS
    AviUtlの環境を構築します
.DESCRIPTION
    https://scrapbox.io/aviutl/セットアップ に基づき、AviUtlと周辺プラグインを含めた環境を構築します。
.PARAMETER InstallPath
    インストール先のパスを指定します。デフォルトではカレントディレクトリ内のtestディレクトリが指定されます。
.PARAMETER WorkingDirectry
    作業用フォルダを指定します。デフォルトでは TEMP\aviutl が使用されます。
.PARAMETER KeepForeignData
    インストール後に作業用フォルダを保持する場合に使用します。
.EXAMPLE
    installer.ps1 C:\Path\To\Aviutl
.LINK
    https://scrapbox.io/aviutl/セットアップ
#>

# 2022/04/04
# 関数の戻り値を明確にするためにreturnを用いることとする

param(
    [Parameter(Mandatory = $false,
        Position = 0)]
    [string]
    $InstallPath = (New-Item 'test' -ItemType Directory -Force),
    [Parameter()]
    [string]
    $WorkingDirectry = (New-Item (Join-Path $env:TEMP aviutl) -ItemType Directory -Force),
    [Parameter()]
    [switch]
    $KeepForeignData
)

Set-StrictMode -Version Latest
Push-Location -Path $InstallPath

# 7Zip4Powershellモジュールのインストール
if (!(Get-Command Expand-7Zip -ea SilentlyContinue)) {
    Install-Module -Name 7Zip4Powershell
}

# ディレクトリが存在しない場合に作成してパスを返す
function New-DirectryIfNotExist {
    param (
        [Parameter(Mandatory = $true,
            Position = 0)]
        [string]
        $Path
    )

    if (Test-Path $Path) {
        return $Path
    }
    else {
        return New-Item $Path -ItemType Directory
    }
}

# zipファイルを投げると解凍して中身を返す
# Directry指定時はその中身、指定していなければ1階層目のフォルダを無視した中身
function Get-ArchiveItems {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [string]
        $Path,

        # 取得対象の子ディレクトリ
        [Parameter(Position = 1)]
        [string]
        $Directry,

        # 作業用のディレクトリ
        [Parameter(Position = 2)]
        [string]
        $WorkDir = $WorkingDirectry
    )

    # アーカイブ名のフォルダを解凍先に指定する
    $DestinationPath = Join-Path $WorkDir ([System.IO.Path]::GetFileNameWithoutExtension($Path))
    Expand-7Zip $Path -TargetPath $DestinationPath

    if ($Directry) {
        return Get-ChildItem (Join-Path $DestinationPath $Directry)
    }
    else {
        $items = Get-ChildItem $DestinationPath
        # 1階層目に単一のフォルダのみが存在する場合はその中身を取得
        # @()で囲うことで要素が一つの場合でも配列として扱う
        # https://social.technet.microsoft.com/Forums/ja-JP/230719ec-e5a8-4b32-9cf9-b7bdec0b50c3/22793259681239526684320131237312428123901235612427389173044612?forum=powershellja
        if (@($items).Count -eq 1 -and $items.PSIsContainer) {
            return Get-ChildItem $items
        }
        else {
            return $items
        }
    }
}

# URLを投げると出力先に存在しなければ取ってくる
function Get-UriFile {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [string]
        $Uri,
        [Parameter()]
        [string]
        $DestinationPath = $WorkingDirectry
    )

    $o = Join-Path $DestinationPath ([System.IO.Path]::GetFileName($Uri))
    if (!(Test-Path $o)) {
        Invoke-WebRequest $Uri -OutFile $o
    }
    return Convert-Path $o
}

# GitHubのReleasesに存在するファイルのUrlを取得する
#   第一引数: GitHubのReleasesを取得するAPIのURL (https://api.github.com/repos/<OWNER>/<REPOSITORY>/releases/<RELEASE_ID>)
#   第二引数: (省略可) 取得するファイルのキーワード (x86, AviUtl など)
function Get-GithubDownloadUrl {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [string]
        $Uri,
        [Parameter(Position = 1)]
        [string]
        $Keyword
    )

    $Json = Invoke-WebRequest $Uri | ConvertFrom-Json

    if (!$Keyword) {
        # ここも@()で配列として扱うやつ お前もか
        return @($json.assets.browser_download_url)[0].ToString()
    }
    else {
        return ($json.assets.browser_download_url | Select-String $KeyWord)[0].ToString()
    }
}

function Get-AmazonpoiArchive {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [string]
        $Id,
        [Parameter()]
        [string]
        $DestinationPath = $WorkingDirectry
    )

    $d = Invoke-WebRequest -Headers @{"Referer" = "https://hazumurhythm.com/wev/amazon/?script=$Id" } https://hazumurhythm.com/php/amazon_download.php?name=$Id

    # ファイル名取得
    [string]$d.Headers."Content-Disposition" -match 'filename="(?<filename>.*?)"'
    $o = Join-Path $DestinationPath $Matches.filename

    if (!(Test-Path $o)) {
        [System.IO.File]::WriteAllBytes($o, $d.Content)
    }
    return Convert-Path $o
}

function Install-Items {
    param(
        [Parameter(Mandatory = $true,
            Position = 0)]
        [array]
        $Items,

        [Parameter(Mandatory = $true,
            Position = 1)]
        [string]
        $Path,

        # インストール対象
        [Parameter()]
        [string]
        $Filter,

        # 対象外のファイル(ディレクトリ)に付ける接頭辞
        # 指定した場合は対象外のファイルも接頭辞が付いた状態でインストールされる
        [Parameter()]
        [string]
        $Prefix,

        # Prefix指定時に除外するファイル(ディレクトリ)
        [Parameter()]
        [string]
        $Exclude
    )

    if ($Filter) {
        $Items | Where-Object { $_.Name -like $Filter } |
        Copy-Item -Destination $Path -Force

        if ($Prefix) {
            $Items | Where-Object { $_.Name -notlike $Filter } | Where-Object { $_.Name -notlike $Exclude } |
            ForEach-Object {
                $Prefixed = $Prefix + $_.Name
                Copy-Item $_ -Destination $Path\$Prefixed -Force
            }
        }
    }
    else {
        $Items | Copy-Item -Destination $Path -Force
    }
}

function Install-UriArchive {
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [string]
        $Uri,

        [Parameter(Mandatory = $true,
            Position = 1)]
        [string]
        $Path,

        [Parameter()]
        [string]
        $Filter,

        [Parameter()]
        [string]
        $Prefix,

        [Parameter()]
        [string]
        $Exclude
    )

    $Items = Get-UriFile $Uri | Get-ArchiveItems
    Install-Items $Items -Path $Path -Filter $Filter -Prefix $Prefix -Exclude $Exclude
}

function Install-AmazonpoiArchive {
    param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [string]
        $Id,

        [Parameter(Mandatory = $true,
            Position = 1)]
        [string]
        $Path,

        [Parameter()]
        [string]
        $Filter,

        [Parameter()]
        [string]
        $Prefix,

        [Parameter()]
        [string]
        $Exclude
    )

    $Items = Get-AmazonpoiArchive $Id | Get-ArchiveItems
    Install-Items $Items -Path $Path -Filter $Filter -Prefix $Prefix -Exclude $Exclude
}

# URLs
## Recomended
[string]$aviutl = "http://spring-fragrance.mints.ne.jp/aviutl/aviutl110.zip"
[string]$exedit = "http://spring-fragrance.mints.ne.jp/aviutl/exedit92.zip"
[string]$lw = Get-GithubDownloadUrl "https://api.github.com/repos/Mr-Ojii/L-SMASH-Works-Auto-Builds/releases/latest" "Mr-Ojii_AviUtl.zip"
[string]$InputPipePlugin = Get-GithubDownloadUrl "https://api.github.com/repos/amate/InputPipePlugin/releases/latest"
[string]$easymp4 = "https://aoytsk.blog.jp/aviutl/easymp4.zip"
[string]$patchaul = "https://scrapbox.io/files/6242bf590ea51d001d275052.zip"
[string]$luajit = Get-GithubDownloadUrl "https://api.github.com/repos/Per-Terra/LuaJIT-Auto-Builds/releases/latest" "Win_x86.zip"

## rikky
[string]$rikkky_module = "rikkymodulea2Z"

# 処理ここから
[string]$root = New-DirectryIfNotExist $InstallPath
[string]$plugins = New-DirectryIfNotExist (Join-Path $InstallPath 'plugins')
[string]$script = New-DirectryIfNotExist (Join-Path $InstallPath 'script')

Install-UriArchive $aviutl $root
Install-UriArchive $exedit $root
Install-UriArchive $lw $plugins -Filter "*.au*" -Prefix "lw_" -Exclude "Licenses"
Install-UriArchive $InputPipePlugin $plugins -Filter "*.au*" -Prefix "InputPipePlugin_"
Install-UriArchive $easymp4 $plugins -Filter "easymp4*" -Prefix "easymp4_"
Install-UriArchive $patchaul $root
Install-UriArchive $luajit $root -Filter "lua51.dll"

Install-AmazonpoiArchive $rikkky_module $root -Filter "rikky_*"

if (!$KeepForeignData) {
    Remove-Item $WorkingDirectry -Recurse -Force
}

Pop-Location