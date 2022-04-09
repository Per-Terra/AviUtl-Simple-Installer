# AviUtl-Simple-Installer
 Install Aviutl using PowerShell

# 注意事項
- GitHubのAPIには制限があるので、デバッグ時などはシェル上で実行すること
    - URLが自動でキャッシュされる

# ワンライナー
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Per-Terra/AviUtl-Simple-Installer/main/installer.ps1') + "-Scrapbox")
```