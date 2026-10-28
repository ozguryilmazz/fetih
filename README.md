# Fetih (çalışma adı)

state.io tarzı, sürükle-bırak strateji oyunu. Godot 4.6, Android, 2D.

## Şu an çalışanlar

- **Oyun çekirdeği:** üsler asker üretir, sürükle-bırak ile asker gönderilir, sayıca üstün olan üssü alır.
- **Çoklu seçim + eşit bölüştürme:**
  - Kendi üssünden sürüklemeye başla. Hedefe varmadan kendi diğer üslerinin üzerinden geçersen onlar da **kaynak** olur.
  - İlk hedefe değdikten sonra üzerinden geçtiğin her üs **hedef** olur.
  - Parmağını kaldırınca her kaynak askerini hedeflere **eşit böler** (100 asker, 2 hedef → 50 + 50).
  - Sadece kendi üslerinden geçip bırakırsan son üs hedef sayılır (takviye).
- **Asker kolları:** askerler sıra sıra yürür, hedefe tek tek girer.
- **Yol çarpışması:** rakip kollar yolda karşılaşınca durup birbirini eritir (15'e 15 → ikisi de yok olur). Kesişen yollarda vurulan kol ikiye bölünür.
- **Efektler ve titreşim:** çarpışma kıvılcımı, isabet, ele geçirme dalgası, ekran sarsıntısı; titreşim Ayarlar'dan kapatılabilir.
- **Solo mod (50 bölüm):** her maçta rastgele harita. Zorluk bantları: 1–10 Kolay-Orta, 11–20 Orta, 21–30 Orta-Zor, 31–40 Zor, 41–50 Çok Zor. 6. bölümden itibaren 2 bot.
- **Boss bölümleri:** her 10. bölüm; tek ama güçlü rakip, taçlı kale üssü (büyük, hızlı üretir, dayanıklı), çift altın.
- **Yıldızlar:** ★ kazan, ★ hedef sürede kazan, ★ en fazla 2 üs kaybet. Altın: 1★ 50, 2★ 75, 3★ 100 (rekor kırmayan tekrar oyunu %20).
- **Bot zekâsı:** savunma (düşecek üsse takviye), net değer hesabı ve sabır, risk hesabı (boşalan üssün kaybedilmesi), arkadaki askerleri cepheye toplama. Beceri bölümle artar.
- **Günlük ödül:** 7 günlük seri (50 → 300 altın); bir gün kaçırılırsa seri başa döner.
- **Duraklat menüsü:** II düğmesi, Android geri tuşu veya uygulama arka plana geçince.
- **Altın ve mağaza:** kazanılan her bölüm altın verir; altınla Üretim Hızı, Asker Hızı, Başlangıç Gücü ve Yol Savaşı (yol çarpışmalarında kademe başına +1 asker avantajı) alınır.
- **Ayarlar:** oyuncu adı, renk ve ikon (ikonlar şimdilik basit şekiller).
- **Kayıt:** her şey cihazda saklanır (`user://save.cfg`), hesap yok.
- **Çok oyunculu ekran:** arayüz hazır, online bağlantı henüz yok (sıradaki adım).

## Klasör yapısı

```
scenes/                 Ekranlar (her biri tek kök düğüm, arayüz kodla kuruluyor)
scripts/core/           Oyun kuralları — grafikten bağımsız
  game_config.gd          Tüm denge sayıları, üs tipleri, renkler, güçlendirmeler
  match_state.gd          Maçın durumu ve kuralları (host bunu çalıştıracak)
  map_generator.gd        Rastgele harita
  bot_ai.gd               Yapay zeka
  level_setup.gd          Bölüm kurulumu (bot'lar, boss) — oyun ve zorluk raporu ortak kullanır
  icon_draw.gd            Geçici ikon şekilleri
scripts/game/game.gd    Oyun ekranı: çizim, dokunmatik giriş, bitiş paneli
scripts/ui/             Menü, bölümler, mağaza, ayarlar, çok oyunculu
scripts/autoload/       SaveData (cihaz kaydı), Session (ekranlar arası bilgi)
tests/                  Ekransız testler (GitHub her derlemede çalıştırır)
tools/debug.keystore    APK imzası (sadece test sürümleri için)
```

Denge ayarlarıyla oynamak için ilk bakılacak yer: `scripts/core/game_config.gd`.

### Zorluk raporu

Zorluk eğrisi bir "oyuncu bot'u" ile 50 bölüm oynatılarak ayarlandı. Değişiklikten sonra tekrar ölçmek için:

```
godot --headless --path . -s tests/difficulty_report.gd -- 0.85 12        # oyuncu becerisi, bölüm başına maç
godot --headless --path . -s tests/difficulty_report.gd -- 0.85 20 boss   # sadece boss bölümleri
```

## Bilgisayarda çalıştırma

Godot 4.6 ile **Proje Al / Import** → bu klasördeki `project.godot`. F5 ile çalışır; fare dokunmatik gibi davranır.

## GitHub'dan APK alma

1. GitHub'da yeni bir depo aç ve bu klasörün içeriğini `main` dalına gönder.
2. **Actions** sekmesinde "Android APK" iş akışı otomatik başlar (ilk derleme ~5–8 dk, sonrakiler daha hızlı).
3. Bittiğinde APK iki yerde olur:
   - **Releases → "Son derleme #N"** (telefondan indirip kurmak için en kolayı)
   - İş akışının sayfasında **Artifacts** bölümünde
4. Telefonda "bilinmeyen kaynaklardan yükleme" izni gerekir. Her derlemenin sürüm kodu arttığı için yeni APK eskisinin üzerine kurulur.

İş akışı derlemeden önce testleri de çalıştırır; bir kural bozulursa APK üretilmez.

## Sıradaki adımlar

1. **Firebase ile online oda:** host 4 haneli kodla odayı rezerve eder, diğerleri katılır. Host maçı `MatchState` ile hesaplar, diğer oyuncuların hamleleri komut olarak gelir, host düzenli durum paketi gönderir (`setup_dict`, `snapshot`, `apply_snapshot` hazır).
2. Farklı üs tipleri (`BASE_TYPES` tablosuna eklenecek).
3. Gerçek ikon seti ve görsel iyileştirmeler (asker akışı animasyonu, ses).
4. Play Store için gerçek (release) imza anahtarı — GitHub Secrets'ta saklanacak.
