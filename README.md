# Archura SyncGuard - Project Independent Version Controller

Bu proje, herhangi bir Windows uygulamasinin baslangicinda calistirilabilecek PowerShell tabanli, Git gerektirmeyen bir GitHub senkronizasyon sistemidir. Local `version controller/version.md` dosyasindaki SemVer degeri ile GitHub reposundaki ayni dosya karsilastirilir. Remote versiyon daha yeniyse repo zip olarak indirilir, local proje backup alinarak GitHub ile senkronize edilir.

## SEO Keywords

`#powershell` `#windows` `#github` `#version-control` `#auto-update` `#github-updater` `#windows-automation` `#semver` `#backup` `#sync-tool` `#deployment` `#developer-tools`

## Ornek Proje Yapisi

```text
ProjectRoot/
  version controller/
    version.md
    version-checker.ps1
    config.json
    update-log.md
    backups/
  README.md
  start.bat
  start.ps1
  app.exe
```

## Kurulum

1. `version controller` klasorunu projenizin root dizinine koyun.
2. `version controller/config.json` dosyasindaki `repositoryOwner`, `repositoryName` ve `branch` alanlarini duzenleyin.
3. GitHub reposunda da ayni pathte `version controller/version.md` dosyasinin bulundugundan emin olun.
4. Uygulamayi dogrudan `app.exe` yerine `start.bat` ile baslatin.

## GitHub Repo Ayarlari

Repo public ise ek ayara gerek yoktur. Script su iki URL mantigini kullanir:

```text
https://raw.githubusercontent.com/{owner}/{repo}/{branch}/version%20controller/version.md
https://codeload.github.com/{owner}/{repo}/zip/refs/heads/{branch}
```

Private repo destegi bu sade surumde token kullanmadigi icin yoktur. Private repo gerekiyorsa `Invoke-WebRequest` cagrisina GitHub token header'i eklenmelidir.

## version.md Nasil Guncellenir

Local ve remote versiyon dosyasi tek satir SemVer icermelidir:

```text
1.0.0
```

Yeni release yayinlamak icin GitHub reposundaki `version controller/version.md` degerini artirin:

```text
1.0.1
1.1.0
2.0.0
```

Script remote versiyonun local versiyondan buyuk oldugunu gorunce update baslatir.

## SemVer Aciklamasi

Format:

```text
MAJOR.MINOR.PATCH
```

Karsilastirma string olarak degil sayisal olarak yapilir:

```text
1.0.10 > 1.0.2
2.0.0 > 1.9.9
1.1.0 > 1.0.9
```

Pre-release veya build metadata bu temel surumde desteklenmez. Gecerli ornekler `1.0.0`, `1.0.1`, `2.1.1` bicimindedir.

## config.json Aciklamasi

```json
{
  "repositoryOwner": "KULLANICI_ADI",
  "repositoryName": "REPO_ADI",
  "branch": "main",
  "versionFilePath": "version controller/version.md",
  "downloadMode": "zip",
  "excludeFiles": [
    "version controller/config.json",
    ".env",
    "user-data.json",
    "settings.local.json"
  ],
  "backupBeforeUpdate": true,
  "backupFolder": "version controller/backups",
  "autoRestartAfterUpdate": false,
  "startCommand": "start.bat"
}
```

Alanlar:

- `repositoryOwner`: GitHub kullanici veya organizasyon adi.
- `repositoryName`: GitHub repo adi.
- `branch`: Kontrol edilecek branch. Genelde `main`.
- `versionFilePath`: Remote ve local versiyon dosyasi yolu.
- `downloadMode`: Bu surumde `zip` olmalidir.
- `excludeFiles`: Update sirasinda overwrite edilmeyecek veya silinmeyecek local dosyalar.
- `backupBeforeUpdate`: Update oncesi backup alinip alinmayacagi.
- `backupFolder`: Backup klasorlerinin tutulacagi relative path.
- `autoRestartAfterUpdate`: Update bitince `startCommand` calissin mi.
- `startCommand`: Otomatik yeniden baslatmada calistirilacak komut.

## start.bat ile Kullanim

`start.bat` once version checker'i calistirir, sonra ana uygulamayi baslatir:

```bat
@echo off
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1"
start "" "app.exe"
```

Bu repodaki `start.bat` daha guvenli bir ornek olarak proje root'a `pushd` yapar ve `app.exe` yoksa uyari verir.

## start.ps1 ile Kullanim

PowerShell alternatifi:

```powershell
powershell -ExecutionPolicy Bypass -File ".\start.ps1"
```

`start.ps1`, proje root dizinini otomatik algilar, update check calistirir ve ardindan `app.exe` dosyasini baslatir.

## .exe Baslamadan Once Update Check

Uygulamayi kullaniciya `app.exe` yerine `start.bat` ile actirin. Akis:

1. `start.bat` calisir.
2. `version-checker.ps1` local ve remote versiyonu okur.
3. Remote daha yeniyse zip indirilir ve proje senkronize edilir.
4. Hata olsa bile `start.bat` uygulamayi baslatmaya devam eder.

## Komut Ornekleri

```powershell
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1"
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --check-only
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --force
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --restore-latest-backup
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --no-backup
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --silent
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --help
```

## Parametreler

- `--check-only`: Sadece remote versiyonu kontrol eder. Zip indirmez, dosya degistirmez.
- `--force`: Versiyon ayni olsa bile zip indirir ve dosyalari yeniden senkronize eder.
- `--silent`: Konsol ciktisini azaltir.
- `--restore-latest-backup`: En son backup klasorunu geri yukler.
- `--no-backup`: Config backup acik olsa bile bu calistirmada backup almaz.
- `--help`: Yardim bilgisini gosterir.

## excludeFiles Mantigi

`excludeFiles` icindeki relative pathler update sirasinda korunur:

```json
[
  "version controller/config.json",
  ".env",
  "user-data.json",
  "settings.local.json"
]
```

Bu dosyalar remote zip icinde olsa bile local kopyalarinin ustune yazilmaz. Remote zip icinde yoksa da localden silinmez. Script ayrica `.git`, `version controller/backups` ve `version controller/update-log.md` yollarini dahili olarak korur.

## Backup Sistemi

`backupBeforeUpdate` true ise update oncesi tarih-saatli backup alinir:

```text
version controller/backups/backup-2026-05-17-14-30-00
```

Update yarida kalirsa script interaktif calismada backup'tan geri donmeyi sorar. Manuel geri yukleme:

```powershell
powershell -ExecutionPolicy Bypass -File "version controller\version-checker.ps1" --restore-latest-backup
```

## Log Sistemi

Her calisma `version controller/update-log.md` dosyasina yazilir:

- Tarih/saat
- Local version
- Remote version
- Update yapildi mi
- Degisen dosyalar
- Hata detayi

## Hata Cozumu

`config.json bulunamadi`: Script ornek config olusturur. GitHub bilgilerini doldurun.

`repositoryOwner ve repositoryName alanlarini guncelleyin`: Placeholder degerleri gercek repo bilgileriyle degistirin.

`Local version.md bulunamadi`: `version controller/version.md` dosyasini olusturun ve `1.0.0` gibi gecerli SemVer yazin.

`GitHub remote version okunamadi`: Internet baglantisini, repo adini, branch adini ve dosya yolunu kontrol edin.

`Zip indirme basarisiz`: GitHub erisimi, branch adi veya repo public/private durumunu kontrol edin.

`Gecersiz SemVer`: `1.0`, `v1.0.0`, `1.0.0-beta` bu temel surumde gecersizdir. `1.0.0` kullanin.

Execution policy hatasi: `start.bat` zaten `-ExecutionPolicy Bypass` kullanir. Manuel calistirirken de ayni komutu kullanin.

## Siklikla Yapilan Hatalar

- GitHub'daki `version.md` dosyasini root'a koymak, ama configte `version controller/version.md` beklemek.
- Branch adini `main` yerine `master` kullanan repoda configi guncellememek.
- `version.md` icine `v1.0.0` yazmak.
- `.env` gibi local dosyalari `excludeFiles` icine eklememek.
- `autoRestartAfterUpdate` true iken ayrica `start.bat` icinden uygulamayi ikinci kez baslatmak.

## Davranis Ozeti

- Remote version localden buyukse update yapilir.
- Versiyonlar esitse indirme yapilmaz.
- Remote version localden dusukse uyari verilir, islem yapilmaz.
- `--force` verilirse versiyon ayni olsa bile senkronizasyon yapilir.
- Hata durumlari loglanir ve uygulamanin baslamasi engellenmez.
