#!/usr/bin/env pwsh

#requires -version 5.0

<#
.SYNOPSIS
    AviUtlの環境を構築します
.PARAMETER InstallPath
    インストール先のパスを指定します。デフォルトではカレントディレクトリ内のtestディレクトリが指定されます。
.PARAMETER WorkingDirectry
    作業用フォルダを指定します。デフォルトでは C:\<User>\AppData\Local\TEMP\aviutl が使用されます。
.PARAMETER KeepForeignData
    インストール後に作業用フォルダを保持する場合に使用します。
.EXAMPLE
    installer.ps1 C:\Path\To\Aviutl -Scrapbox
.EXAMPLE
    installer.ps1 C:\Path\To\aviutl -exedit -KeepForeignData
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
    $KeepForeignData,

    [Parameter()]
    [switch]
    $All,$Scrapbox,

    [Parameter()]
    [switch]$exedit, [switch]$lw, [switch]$InputPipePlugin, [switch]$easymp4, [switch]$patchaul, [switch]$rikkky_module, [switch]$LuaJIT,

    # rigaya
    [Parameter()]
    [switch]$x264guiEx, [switch]$x265guiEx, [switch]$svtAV1guiEx, [switch]$QSVEnc, [switch]$NVEnc, [switch]$VCEEnc, [switch]$ffmpegOut
)

#Set-StrictMode -Version Latest
Push-Location -Path $InstallPath

# 7Zip4Powershellモジュールのインストール
if (!(Get-Command Expand-7Zip -ea SilentlyContinue)) {
    Install-Module -Name 7Zip4Powershell -Scope CurrentUser
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
            return Get-ChildItem $items.FullName
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
    if (!(Test-Path $DestinationPath)) {
        New-Item $DestinationPath -ItemType Directory
    }
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
        $Url = $json.assets.browser_download_url | Select-String $KeyWord
        if ($Url) {
            return $Url[0].ToString()
        }
        else {
            Write-Error "Resource not found on GitHub"
            return $null
        }
    }
}

function Get-AmazonArchive {
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

    # キャッシュの存在確認
    if ($AmazonFileName[$Id] -and (Test-Path Join-Path $DestinationPath $AmazonFileName[$Id])) {
        return Join-Path $DestinationPath $AmazonFileName[$Id]
    } else {
        $response = Invoke-WebRequest -Headers @{"Referer" = "https://hazumurhythm.com/wev/amazon/?script=$Id" } https://hazumurhythm.com/php/amazon_download.php?name=$Id

        # ファイル名取得
        [string]$response.Headers."Content-Disposition" -match 'filename="(?<filename>.*?)"'
        # ファイル名をキャッシュ
        $AmazonFileName += @{"$Id" = "$filename"}

        $file = Join-Path $DestinationPath $Matches.filename
        [System.IO.File]::WriteAllBytes($file, $response.Content)
        return Convert-Path $file
    }
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
        Copy-Item -Destination $Path -Recurse -Force

        if ($Prefix) {
            $Items | Where-Object { $_.Name -notlike $Filter } | Where-Object { $_.Name -notlike $Exclude } |
            ForEach-Object {
                $Prefixed = $Prefix + $_.Name
                Copy-Item $_.FullName -Destination (Join-Path $Path $Prefixed) -Recurse -Force
            }
        }
    }
    else {
        $Items | Copy-Item -Destination $Path -Recurse -Force
    }
}

function Install-Item {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [string]
        $Name
    )

    $item = $itemTable[$Name]

    if ($item.url) {
        $items = $item.url | Get-UriFile | Get-ArchiveItems
    }
    elseif ($item.github) {
        $GitHubDownloadUrl = Get-GithubDownloadUrl $item.github.url $item.github.keyword
        if ($null -ne $GitHubDownloadUrl) {
            $item.url = $GitHubDownloadUrl # URLのキャッシュ
            $items = $item.url | Get-UriFile | Get-ArchiveItems
        }
    }
    elseif ($item.amazon) {
        $items = Get-AmazonArchive $item.amazon.id | Get-ArchiveItems
    }

    if ($items) {
        Install-Items $items -Path (Get-Variable $item.path -ValueOnly) -Filter $item.filter -Prefix $item.prefix -Exclude $item.exclude
    }
}

# itemTable
$coreTable = @{
    "aviutl" = @{
        "url"  = "http://spring-fragrance.mints.ne.jp/aviutl/aviutl110.zip"
        "path" = "root"
    }
    "exedit" = @{
        "url"  = "http://spring-fragrance.mints.ne.jp/aviutl/exedit92.zip"
        "path" = "root"
    }
}

$pluginTable = @{
    # input
    "lw"              = @{
        "github"  = @{"url" = "https://api.github.com/repos/Mr-Ojii/L-SMASH-Works-Auto-Builds/releases/latest"; "KeyWord" = "Mr-Ojii_AviUtl.zip" }
        "path"    = "plugins"
        "filter"  = "*.au*"
        "prefix"  = "lw_"
        "exclude" = "Licenses"
    }

    "InputPipePlugin" = @{
        "github" = @{"url" = "https://api.github.com/repos/amate/InputPipePlugin/releases/latest" }
        "path"   = "plugins"
        "filter" = "*.au*"
        "prefix" = "InputPipePlugin_"
    }

    # output
    "easymp4"         = @{
        "url"    = "https://aoytsk.blog.jp/aviutl/easymp4.zip"
        "path"   = "plugins"
        "filter" = "easymp4*"
        "prefix" = "easymp4_"
    }

    # utility
    "patchaul"        = @{
        "github" = @{"url" = "https://api.github.com/repos/ePi5131/patch.aul/releases/latest" }
        "path"   = "root"
        "filter" = "*.au*"
    }

    # module
    "rikky_module"    = @{
        "amazon" = @{"id" = "rikkymodulea2Z" }
        "path"   = "root"
        "filter" = "rikky_*"
    }
}

$rigayaTable = @{
    "x264guiEx"   = @{
        "github" = @{"url" = "https://api.github.com/repos/rigaya/x264guiEx/releases/latest" }
        "path"   = "root"
    }
    "x265guiEx"   = @{
        "github" = @{"url" = "https://api.github.com/repos/rigaya/x265guiEx/releases/latest" }
        "path"   = "root"
    }
    "svtAV1guiEX" = @{
        "github" = @{"url" = "https://api.github.com/repos/rigaya/svtAV1guiEx/releases/latest" }
        "path"   = "root"
    }
    "ffmpegOut"   = @{
        "github" = @{"url" = "https://api.github.com/repos/rigaya/ffmpegOut/releases/latest" }
        "path"   = "root"
    }
    "NVEnc"       = @{
        # AviUtl用のパッケージがGitHub上にないので、暫定対応
        "url" = "https://drive.google.com/uc?id=1TMSQlb5v4N4cQAYjmhIdmpIhQmQp962j"
        "github" = @{"url" = "https://api.github.com/repos/rigaya/NVEnc/releases/latest"; "KeyWord" = "AviUtl" }
        "path"   = "root"
    }
    "QSVEnc"      = @{
        "github" = @{"url" = "https://api.github.com/repos/rigaya/QSVEnc/releases/latest"; "KeyWord" = "AviUtl" }
        "path"   = "root"
    }
    "VCEEnc"      = @{
        # NVEncと同様
        "url" = "https://drive.google.com/uc?id=1aCXBtHgis9z_wYoCffQ7a7ZXBRlk18bR"
        "github" = @{"url" = "https://api.github.com/repos/rigaya/VCEEnc/releases/latest"; "KeyWord" = "AviUtl" }
        "path"   = "root"
    }
}

$otherTable = @{
    "LuaJIT" = @{
        "github" = @{"url" = "https://api.github.com/repos/Per-Terra/LuaJIT-Auto-Builds/releases/latest"; "KeyWord" = "Win_x86.zip" }
        "path"   = "root"
        "filter" = "lua51.dll"
    }
}

$itemTable = $coreTable + $pluginTable + $rigayaTable + $otherTable

# 初期化処理
[string]$root = New-DirectryIfNotExist $InstallPath
[string]$plugins = New-DirectryIfNotExist (Join-Path $InstallPath 'plugins')
[string]$script = New-DirectryIfNotExist (Join-Path $InstallPath 'script')

# インストール
if ($All) {
    foreach ($item in $itemTable.Keys) {
        Install-Item $item
    }
} else {
    Install-Item aviutl
}

if ($Scrapbox) {
    $exedit = $true
    $lw = $true
    $easymp4 = $true
    $patchaul = $true
}

if ($exedit) {Install-Item exedit}
# input
if ($lw) {Install-Item lw}
if ($InputPipePlugin) {Install-Item InputPipePlugin}
# output
if ($easymp4) {Install-Item easymp4}
# utility
if ($patchaul) {Install-Item patchaul}
# module
if ($rikky_module) {Install-Item rikky_module}
# rigaya
if ($x264guiEx) {Install-Item x264guiEx}
if ($x265guiEx) {Install-Item x265guiEx}
if ($svtAV1guiEX) {Install-Item svtAV1guiEX}
if ($ffmpegOut) {Install-Item ffmpegOut}
if ($NVEnc) {Install-Item NVEnc}
if ($QSVEnc) {Install-Item QSVEnc}
if ($VCEEnc) {Install-Item VCEEnc}
# others
if ($LuaJIT) {Install-Item LuaJIT}

if (!$KeepForeignData) {
    Remove-Item $WorkingDirectry -Recurse -Force
}

Pop-Location