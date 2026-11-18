# Operasional harian

Kumpulan prosedur untuk menjalankan, memperbarui, dan memeriksa stack ini. Perintah dijalankan dari root repo (`eduall-docker/`). Untuk konteks arsitektur, lihat `docs/ARSITEKTUR.md`.

## Memperbarui aplikasi

### Aplikasi PHP/Laravel

Kode aplikasi diperbarui di folder `src`, bukan lewat build image. Karena `src` di-mount ke container, perubahan langsung terlihat.

```bash
cd crm/src
git pull
cd ../..

docker compose exec php_crm composer install --no-dev --optimize-autoloader
docker compose exec php_crm php artisan migrate --force
docker compose exec php_crm php artisan config:cache
docker compose exec php_crm php artisan route:cache
docker compose exec php_crm php artisan view:cache
```

Jalankan hanya langkah yang relevan. Jika aplikasi memakai queue, restart worker supaya memuat kode baru. Worker dijalankan oleh `queue.sh` di container nginx, jadi hentikan prosesnya dan biarkan watchdog menyalakannya kembali pada menit berikutnya:

```bash
docker compose exec nginx pkill -f 'artisan queue:work'
```

Perintah itu menghentikan semua worker (CRM dan editing). Watchdog akan menyalakan keduanya lagi dalam satu menit.

### Aplikasi frontend

Build dilakukan di lokal dan hasilnya di-push ke GitHub (lihat `docs/ARSITEKTUR.md`). Di server cukup:

```bash
cd mentoring/front-end/src
git pull
```

Tidak ada restart yang diperlukan. Bila browser masih menampilkan versi lama, kemungkinan cache. `general.conf` dan `security.conf` menetapkan masa cache sampai 7 hari untuk aset statis dan 60 menit untuk HTML, jadi pastikan hasil build memakai nama file berhash.

### Perubahan Dockerfile atau docker-fpm.ini

```bash
# Dockerfile berubah
docker compose build php_crm
docker compose up -d php_crm

# docker-fpm.ini berubah (cukup restart)
docker compose restart php_crm
```

### Perubahan konfigurasi nginx

```bash
docker compose exec nginx nginx -t           # selalu cek sintaks dulu
docker compose exec nginx nginx -s reload    # tanpa downtime
```

Reload cukup untuk perubahan di `default.conf`, `general.conf`, `security.conf`, dan `nginx.conf`. Perubahan di `cron/cronfile`, penambahan volume, atau perubahan `depends_on` butuh container dibuat ulang (`docker compose up -d nginx`), yang menyebabkan downtime singkat untuk semua domain.

## Perintah sehari-hari

```bash
docker compose ps                              # status semua container
docker compose logs -f --tail 100 php_crm      # log satu service
docker compose logs -f nginx
docker compose exec php_crm bash               # masuk container
docker compose restart php_timesheet           # restart satu service
docker compose up -d --build php_eduall        # build ulang dan jalankan
docker stats --no-stream                       # pemakaian CPU dan memori
```

Log aplikasi Laravel ada di `<project>/src/storage/logs/`. Log nginx ada di `nginx/logs/access.log` dan `nginx/logs/error.log`. Log scheduler dan queue ada di dalam container nginx (`/var/log/cronjob.log`, `/var/log/cron_error.log`, `/var/log/queue_watchdog.log`) dan di `storage/logs/queue_output.log` tiap project.

## Pemeriksaan kesehatan

Setiap server block punya `/health` yang membalas `200 OK`. Itu hanya membuktikan nginx hidup untuk domain itu, bukan bahwa aplikasi PHP sehat. Untuk pemeriksaan lebih jujur, minta halaman yang melewati PHP:

```bash
for d in edu-all.com crm.edu-all.com timesheet.edu-all.com assessment.edu-all.com auth.edu-all.com; do
  printf '%s ' "$d"; curl -s -o /dev/null -w '%{http_code}\n' "https://$d/"
done
```

## Pemecahan masalah

| Gejala | Kemungkinan penyebab | Cara memeriksa |
|---|---|---|
| 502 Bad Gateway | Container PHP mati, atau nama di `fastcgi_pass` salah | `docker compose ps`, lalu `docker compose logs php_<nama>` |
| 504 Gateway Timeout | Request lebih lama dari `fastcgi_read_timeout`, atau PHP macet | Lihat `nginx/logs/error.log`, periksa query lambat |
| "File not found." | Path di nginx dan di container PHP tidak sama | Bandingkan `root` di nginx, volume PHP, dan volume nginx |
| 404 dari nginx | `root` salah atau `src` kosong | `docker compose exec nginx ls /<project>/public` |
| 403 di semua halaman | Izin file atau `location ~ /\.` ikut menangkap path | Periksa izin folder dan `error.log` |
| 500 dari Laravel | Error aplikasi, `.env` salah, izin `storage` | `tail storage/logs/laravel.log` |
| Redirect loop HTTPS | Header `X-Forwarded-Proto` tidak sampai | Periksa proxy di depan nginx dan `fastcgi_param HTTPS` |
| Perubahan kode tidak terlihat | Cache config Laravel atau OPcache | `php artisan config:clear`, restart container PHP |
| Email atau job tidak jalan | Queue worker mati | `docker compose exec nginx pgrep -af queue:work`, lihat `queue_watchdog.log` |
| Scheduler tidak jalan | `cronfile` tidak termuat atau path salah | `docker compose exec nginx crontab -l` dan `/var/log/cron_error.log` |
| Build gagal di `COPY ./src` | Folder `src` belum ada | Clone repo aplikasi ke `src` dulu |
| Build gagal karena folder tidak ditemukan | Compose merujuk folder yang tidak ada (contoh `staging-crm`) | Buat foldernya atau sesuaikan compose |
| Disk penuh | Log nginx, log Laravel, image Docker lama | `df -h`, `docker system df`, `du -sh nginx/logs */src/storage/logs` |

## Pembersihan disk

```bash
docker system df                    # lihat pemakaian
docker image prune -f               # hapus image tanpa tag
docker builder prune -f             # hapus cache build
```

Hati-hati dengan `docker system prune -a --volumes`. Perintah itu bisa menghapus data yang dibutuhkan. Log nginx di `nginx/logs` tidak diputar otomatis di repo ini. Pertimbangkan `logrotate` di host, atau pindahkan log ke `stdout` supaya dikelola Docker.

## Backup

Yang perlu dibackup, karena tidak ada di Git:

| Data | Lokasi | Catatan |
|---|---|---|
| Database aplikasi | Perlu dipastikan (lihat `docs/MIGRASI-KE-VPS.md`) | `mysqldump` terjadwal |
| File `.env` tiap project | `<project>/src/.env` | Berisi kredensial, simpan terenkripsi |
| File upload user | `storage/app/public` atau lokasi sejenis per project | Tergantung aplikasi |
| Data n8n | `n8n_data/` | Workflow dan kredensial terenkripsi |
| Data Redis | `redis-data/` | Hanya penting bila Redis menyimpan data yang tidak bisa dibuat ulang |
| Konfigurasi repo ini | Sudah di Git | Pastikan sudah di-push |

Contoh backup sederhana, dijalankan lewat cron di host:

```bash
#!/bin/bash
set -e
DEST=/backup/$(date +%F)
mkdir -p "$DEST"
tar czf "$DEST/n8n_data.tgz" -C /home/deploy/eduall-docker n8n_data
for p in eduall crm timesheet assessment authorization asset-management helpdesk; do
  cp "/home/deploy/eduall-docker/$p/src/.env" "$DEST/$p.env" 2>/dev/null || true
done
# tambahkan mysqldump dan salinan folder upload sesuai hasil inventaris
find /backup -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
```

Simpan backup di tempat lain dari server utama (object storage atau server berbeda), dan coba restore secara berkala. Backup yang belum pernah dicoba restore belum bisa dianggap ada.

## Keamanan dasar

- Jangan simpan password di `docker-compose.yml` atau `logstash.conf`. Pindahkan ke file `.env` di root repo (tambahkan ke `.gitignore`) dan rujuk dengan `${NAMA_VARIABEL}`. Password n8n dan Elasticsearch yang sekarang tertulis di repo sebaiknya diganti, karena sudah masuk riwayat Git.
- Batasi port yang dipetakan. Nginx sudah memanggil container lewat nama di `app-network`, jadi port `9001`, `9003`, dan seterusnya tidak perlu terbuka ke publik. Pakai `127.0.0.1:9001:9000` atau hapus `ports:`.
- `chmod -R 777 storage/` di beberapa Dockerfile terlalu longgar. Lebih aman memakai pemilik `www-data` dengan izin `775`.
- Header CSP di `default.conf` dan `security.conf` memakai `'unsafe-inline' 'unsafe-eval'` dan sumber `https:` yang luas. Itu membatasi perlindungannya. Perketat bertahap per aplikasi bila memungkinkan.
- Gunakan tag versi untuk image `redis` dan `n8nio/n8n` (bukan `latest`), supaya update tidak datang tanpa disengaja.
- `n8n` memakai autentikasi dasar dengan satu kredensial bersama. Pertimbangkan pembatasan IP atau SSO untuk `workflow.edu-all.com`.
