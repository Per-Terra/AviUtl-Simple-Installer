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
    [Parameter(Mandatory=$false,
    Position=0)]
    [String]
    $InstallPath = (New-Item 'test' -ItemType Directory -Force),
    [Parameter()]
    [String]
    $WorkingDirectry = (New-Item (Join-Path $env:TEMP aviutl) -ItemType Directory -Force),
    [Parameter()]
    [Switch]
    $KeepForeignData
)

Set-StrictMode -Version Latest
Set-Location -Path $InstallPath

# ディレクトリが存在しない場合に作成してパスを返す
function New-DirectryIfNotExist {
    param (
        [Parameter(Mandatory=$true,
        Position=0)]
        [String]
        $Directry
    )

    if (Test-Path $Directry) {
        return $Directry
    } else {
        return New-Item $Directry -ItemType Directory
    }
}

# zipファイルを投げると解凍して中身を返す
function Get-ArchiveItems {
    param (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        Position=0)]
        [String]
        $Archive,

        # 作業用のディレクトリ
        [Parameter(Position=1)]
        [String]
        $Directry = $WorkingDirectry
    )

    # アーカイブ名のフォルダを解凍先に指定する
    $DestinationPath = Join-Path $Directry ([System.IO.Path]::GetFileNameWithoutExtension($Archive))
    Expand-Archive $Archive -DestinationPath $DestinationPath -Force
    $items = Get-ChildItem $DestinationPath
    # 1階層目に単一のフォルダが存在する場合はその中身を取得
    # @()で囲うことで要素が一つの場合でも配列として扱う
    # https://social.technet.microsoft.com/Forums/ja-JP/230719ec-e5a8-4b32-9cf9-b7bdec0b50c3/22793259681239526684320131237312428123901235612427389173044612?forum=powershellja
    if (@($items).Count -eq 1 -and $items.PSIsContainer) {
        return Get-ChildItem $items
    } else {
        return $items
    }
}

# Uriの末尾をもとにファイル名を取得する(URLでもパスでも可)
Function Get-FileName($Uri) {
    return [System.IO.Path]::GetFileName($Uri)
}

# URLを投げると出力先に存在しなければ取ってくる
function Get-UriFile {
    param (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        Position=0)]
        [String]
        $Uri,
        [Parameter()]
        [String]
        $DestinationPath = $WorkingDirectry
    )
    
    $o = Join-Path $DestinationPath (Get-FileName($Uri))
    if (!(Test-Path $o)) {
        Invoke-WebRequest $Uri -OutFile $o
    }
    return Convert-Path $o
}

# GitHubのReleasesに存在する最新のファイルのUrlを取得する
#   第一引数: GitHubのReleasesを取得するAPIのURL (https://api.github.com/repos/<OWNER>/<REPOSITORY>/releases/latest)
#   第二引数: (省略可) 取得するファイルのキーワード (x86, AviUtl など)
function Get-GithubLatestUrl {
    param (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        Position=0)]
        [String]
        $Uri,
        [Parameter(Position=1)]
        [String]
        $Keyword
    )

    $Json = Invoke-WebRequest $Uri | ConvertFrom-Json

    if(!$Keyword) {
        return $json.assets.browser_download_url[0].ToString()
    } else {
        return ($json.assets.browser_download_url | Select-String $KeyWord)[0].ToString()
    }
}

function Install-UriArchive {
    param(
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        Position=0)]
        [String]
        $Uri,

        [Parameter(Mandatory=$true,
        Position=1)]
        [String]
        $Path,

        # インストール対象
        [Parameter()]
        [String]
        $Filter,

        # 対象外のファイル(ディレクトリ)に付ける接頭辞
        # 指定した場合は対象外のファイルも接頭辞が付いた状態でインストールされる
        [Parameter()]
        [String]
        $Prefix,

        # Prefix指定時に除外するファイル(ディレクトリ)
        [Parameter()]
        [String]
        $Exclude
    )

    $items = Get-UriFile $Uri | Get-ArchiveItems
    
    if (!$Filter) {
        $items | Copy-Item -Destination $Path -Force
    } else {
        $items | Where-Object {$_.Name -like $Filter} |
        Copy-Item -Destination $Path -Force

        if ($Prefix) {
            $items | Where-Object {$_.Name -notlike $Filter} | Where-Object {$_.Name -notlike $Exclude} |
            ForEach-Object{
                $Prefixed = $Prefix + $_.Name
                Copy-Item $_ -Destination $Path\$Prefixed -Force
            }
        }
    }
}

# URLs
[String]$aviutl = "http://spring-fragrance.mints.ne.jp/aviutl/aviutl110.zip"
[String]$exedit = "http://spring-fragrance.mints.ne.jp/aviutl/exedit92.zip"
[String]$lw = Get-GithubLatestUrl "https://api.github.com/repos/Mr-Ojii/L-SMASH-Works-Auto-Builds/releases/latest" "Mr-Ojii_AviUtl.zip"
[String]$InputPipePlugin = Get-GithubLatestUrl "https://api.github.com/repos/amate/InputPipePlugin/releases/latest"
[String]$easymp4 = "https://aoytsk.blog.jp/aviutl/easymp4.zip"
[String]$patchaul = "https://scrapbox.io/files/6242bf590ea51d001d275052.zip"
[String]$luajit = Get-GithubLatestUrl "https://api.github.com/repos/Per-Terra/LuaJIT-Auto-Builds/releases/latest" "Win_x86.zip"

# 処理ここから
[String]$root = New-DirectryIfNotExist $InstallPath
[String]$plugins = New-DirectryIfNotExist (Join-Path $InstallPath 'plugins')
[String]$script = New-DirectryIfNotExist (Join-Path $InstallPath 'script')

Install-UriArchive $aviutl $root
Install-UriArchive $exedit $root
Install-UriArchive $lw $plugins -Filter "*.au*" -Prefix "lw_" -Exclude "Licenses"
Install-UriArchive $InputPipePlugin $plugins -Filter "*.au*" -Prefix "InputPipePlugin_"
Install-UriArchive $easymp4 $plugins -Filter "easymp4*" -Prefix "easymp4_"
Install-UriArchive $patchaul $root
Install-UriArchive $luajit $root -Filter "lua51.dll"

if (!$KeepForeignData) {
    Remove-Item $WorkingDirectry -Recurse -Force
}