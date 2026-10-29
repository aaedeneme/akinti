# Akıntı

qBittorrent benzeri, tamamen yerel (SwiftUI + libtorrent-rasterbar) macOS BitTorrent istemcisi.

## Özellikler
- Magnet bağlantısı ve .torrent dosyası ekleme (menü, sürükle-bırak, `magnet:` ve `.torrent` ile açma)
- Torrent tablosu: boyut, ilerleme, durum, eş sayısı, hız, kalan süre, oran
- Kenar çubuğu filtreleri (Tümü / İndiriliyor / Tohumlanıyor / Duraklatıldı / Aktif) ve arama
- Duraklat / sürdür / yeniden kontrol / listeden kaldır veya dosyalarla sil / Finder'da göster
- Ayrıntı paneli: dosya listesi ve dosya başına ilerleme
- İndirme/yükleme hız sınırı ve indirme klasörü (Ayarlar, ⌘,)
- Oturum kalıcılığı (resume data): uygulama kapanıp açılınca devam eder

## Derleme (Mac'te)
```bash
./build.sh
open Akinti.app
```
Gereken: macOS 13+, Xcode komut satırı araçları, Homebrew (betik `libtorrent-rasterbar` kurar).
Başka Mac'lere dağıtmak için `brew install dylibbundler` kurun; betik kütüphaneleri .app içine gömer.

Not: Bu kod Windows'ta yazıldı ve henüz bir Mac'te derlenmedi; ilk derlemede küçük düzeltmeler gerekebilir.
