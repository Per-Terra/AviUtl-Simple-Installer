#!/usr/bin/env pwsh

#requires -version 3.0

<#
.SYNOPSIS
    AviUtlの環境を構築します
.DESCRIPTION
    https://scrapbox.io/aviutl/インストール に基づき、AviUtlと周辺プラグインを含めた環境を構築します。
.LINK
    https://scrapbox.io/aviutl/インストール
#>

param(
    [Parameter(Mandatory=$false,
    Position=0)]
    [String]
    $installPath = "test"
)

Set-StrictMode -Version Latest

if (!(Test-Path $installPath)) {
    New-Item $installPath -ItemType Directory
}

[String]$path = Convert-Path -Path $installPath
[String]$temp = "$path\_temp"
[String]$plugins = "$path\plugins"

if (!(Test-Path $temp)) {
    New-Item $temp -ItemType Directory
}
if (!(Test-Path $plugins)) {
    New-Item $plugins -ItemType Directory
}


[String]$aviutl = "http://spring-fragrance.mints.ne.jp/aviutl/aviutl110.zip"
[String]$exedit = "http://spring-fragrance.mints.ne.jp/aviutl/exedit92.zip"
[String]$lw = "https://api.github.com/repos/Mr-Ojii/L-SMASH-Works-Auto-Builds/releases"
[String]$lw_KeyWord = "Mr-Ojii_AviUtl.zip"

Set-Location -Path $path

Function Get-FileName($Uri) {
    [System.IO.Path]::GetFileName($Uri)
}

function Get-IfNotExist {
    param (
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        Position=0)]
        [String]
        $Uri,
        [Parameter(Mandatory=$true,
        Position=1)]
        [String]
        $DestinationPath
    )
    
    $o = Join-Path $DestinationPath (Get-FileName($Uri))
    if (!(Test-Path $o)) {
        Invoke-WebRequest $Uri -OutFile $o
    }
    Convert-Path $o
}

function Get-GithubLatestUrl {
    param (
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline=$true,
            Position=0)]
        [string]
        $Uri,
        [Parameter(Position=1)]
        [String]
        $KeyWord
    )

    $Json = curl $Uri | ConvertFrom-Json
    if($null -eq $KeyWord) {
        $json.assets.browser_download_url[0].ToString()
    } else {
        ($json.assets.browser_download_url | Select-String $KeyWord)[0].ToString()
    }
}

Function Install-Uri() {
    param(
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        Position=0)]
        [String]
        $Uri,

        [Parameter(Position=1)]
        [String]
        $Type
    )
    $File = Get-IfNotExist $Uri $temp
    if ("plugins" -eq $Type) {
        Expand-Archive $File -DestinationPath $plugins -Force
    } else {
        Expand-Archive $File -DestinationPath $path -Force
    }
}

function Install-Uri-lw {
    param(
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        Position=0)]
        [String]
        $Uri
    )
    $File = Get-IfNotExist $Uri $temp
    Expand-Archive -Force -Path $File -DestinationPath $temp\lw
    Get-ChildItem $temp\lw -Filter *.au* |
        Copy-Item -Force -Destination $plugins
    Get-ChildItem $temp\lw -Exclude *.au*,Licenses |
    ForEach-Object{
        $Prefixed = "lw_" + $_.Name
        Copy-Item -Force $_ -Destination $plugins\$Prefixed
    }
    Remove-Item $temp\lw -Recurse -Force
}

Install-Uri $aviutl
Install-Uri $exedit
Install-Uri-lw (Get-GithubLatestUrl $lw $lw_KeyWord)
