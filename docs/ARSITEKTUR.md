# Arsitektur repo eduall-docker

Repo ini hanya berisi konfigurasi infrastruktur untuk menjalankan semua aplikasi EduALL di satu server dengan Docker Compose. Kode aplikasinya tidak ada di sini. Setiap aplikasi punya repository sendiri, dan repository itu di-clone ke direktori `src` di dalam folder project masing-masing. Karena itu `src` masuk `.gitignore` dan tidak akan terlihat di repo ini.

## Lingkungan server

Repo ini dipakai di server AWS (EC2). Sertifikat HTTPS diurus oleh AWS, bukan oleh nginx di repo ini. Rencananya server akan dimigrasikan dari AWS ke VPS, tetapi belum ada tanggalnya. Beberapa bagian repo bergantung pada kondisi AWS dan perlu ditinjau saat migrasi, lihat bagian "Catatan migrasi ke VPS" di bawah.

## Gambaran umum

```
Internet
   |
   v
nginx (port 80/443)          <- satu-satunya pintu masuk HTTP
   |  server block per domain (nginx/default.conf)
   |
   +-- aplikasi PHP/Laravel --> fastcgi_pass ke container php_<nama>:9000
   +-- aplikasi frontend ----> file statis dari <project>/src/dist
   +-- n8n -------------------> proxy_pass ke n8n:5678

Semua container berada di jaringan bridge `app-network`.
Redis dan n8n berjalan sebagai container pendukung.
```

Nginx menerima request, mencocokkan `server_name`, lalu meneruskannya. Untuk aplikasi PHP, nginx membaca file dari direktori `public` dan mengirim file `.php` ke container PHP-FPM lewat FastCGI. Untuk aplikasi frontend (Vue/React hasil build), nginx langsung menyajikan isi `dist`.

## Alur deploy frontend

Server tidak menjalankan build frontend. Prosesnya:

1. Build dijalankan di komputer lokal (`npm run build` atau sejenisnya).
2. Hasil build (folder `dist`) di-push ke GitHub, di repo frontend yang bersangkutan.
3. Di server, repo itu di-pull ke `<project>/src`, sehingga `<project>/src/dist` berisi hasil build terbaru.
4. Nginx langsung menyajikan folder tersebut. Tidak perlu restart container.

Karena itu `dist` harus ikut ter-commit di repo frontend (tidak masuk `.gitignore` repo itu), dan versi Node di mesin lokal menentukan hasil build. Aplikasi PHP memakai alur yang sama untuk kodenya: `git pull` di `<project>/src`, lalu `composer install` atau migrasi bila perlu.

## Struktur direktori

```
eduall-docker/
├── docker-compose.yml        definisi semua service (versi aktif)
├── docker-compose_v1.yml     versi lama, masih ada service php_junior
├── nginx/
│   ├── Dockerfile            image nginx + PHP CLI + cron
│   ├── nginx.conf            pengaturan global (gzip, SSL, log, timeout)
│   ├── default.conf          server block semua domain
│   ├── general.conf          aturan cache dan kompresi aset
│   ├── security.conf         header keamanan
│   ├── editing.conf          server block HTTPS khusus editing (tidak di-mount)
│   ├── queue.sh              watchdog untuk queue worker Laravel
│   └── cron/cronfile         jadwal cron (schedule:run dan queue.sh)
├── <project>/
│   ├── Dockerfile            image PHP-FPM untuk project itu
│   ├── docker-fpm.ini        override php.ini
│   └── src/                  repo aplikasi (tidak ikut repo ini)
├── mentoring/back-end/       project dengan back-end dan front-end terpisah
├── editing_v2/back-end/      sama seperti mentoring
├── logstash.conf             konfigurasi log pipeline (belum dipakai compose)
├── loki-config.yaml          konfigurasi Loki (belum dipakai compose)
└── promtail-config.yaml      konfigurasi Promtail (belum dipakai compose)
```

Project yang punya back-end dan front-end memakai subfolder `back-end/` dan `front-end/`. Back-end punya Dockerfile sendiri. Front-end tidak butuh container, karena hasil build-nya disajikan nginx.

## Service di docker-compose.yml

### Container PHP-FPM

Setiap aplikasi PHP punya satu container bernama `php_<nama>`. Semuanya dibangun dari `php:8.2-fpm-alpine` dan mendengarkan port 9000 di dalam container. Port host dipetakan satu per satu supaya tidak bentrok.

| Service | Direktori | Port host | Keterangan |
|---|---|---|---|
| `php_eduall` | `eduall` | 9001 | Aplikasi utama |
| `php_staging_eduall` | `eduall-staging` | 9100 | Staging aplikasi utama |
| `php_timesheet` | `timesheet` | 9003 | Timesheet |
| `php_timesheet_staging` | `timesheet-staging` | 9101 | Staging timesheet |
| `php_assessment` | `assessment` | 9004 | Assessment |
| `php_assessment_staging` | `assessment-staging` | 9102 | Staging assessment |
| `php_crm` | `crm` | 9006 | CRM |
| `staging_php_crm` | `staging-crm` | 9007 | Staging CRM |
| `php_editing_v2` | `editing_v2/back-end` | 9008 | Back-end editing |
| `php_mentoring` | `mentoring/back-end` | 9009 | Back-end mentoring |
| `php_authorization` | `authorization` | 9010 | SSO dan otorisasi |
| `php_asset` | `asset-management` | 9011 | Manajemen aset |
| `php_helpdesk` | `helpdesk` | 9012 | Helpdesk |

Pola penomoran: production memakai 9001 sampai 9012, staging memakai 9100 ke atas (kecuali CRM staging di 9007). Karena nginx memanggil container lewat nama di jaringan Docker (`php_crm:9000`), port host ini sebenarnya tidak dipakai nginx. Port tersebut hanya berguna kalau Anda ingin menembak PHP-FPM dari luar container.

### Nginx

Container nginx dibangun dari `nginx:stable` dan ditambah PHP CLI, `cron`, Node.js, dan `brotli`. PHP CLI ada karena nginx juga menjalankan scheduler dan queue worker Laravel (lihat bagian cron di bawah).

Nginx me-mount `src` dari semua project ke path yang sama dengan yang dipakai container PHP-nya, misalnya `./crm/src:/crm`. Ini penting: nginx perlu membaca file statis dan memeriksa `try_files` sendiri, sedangkan container PHP hanya menjalankan skrip. Kalau path di kedua container berbeda, `SCRIPT_FILENAME` yang dikirim nginx tidak akan ditemukan oleh PHP-FPM.

Konfigurasi yang di-mount ke nginx: `nginx.conf`, `default.conf` (ke `conf.d`), `security.conf`, `general.conf`, `queue.sh`, dan `cron/cronfile`. Log ditulis ke `./nginx/logs`. Sertifikat Let's Encrypt dibaca dari `/etc/letsencrypt/live/edu-all.com-0002/` di host.

### Redis dan n8n

Redis (`redis:latest`) dipakai bersama oleh aplikasi untuk cache dan session. Datanya tersimpan di `./redis-data`. Redis tidak dimasukkan ke `app-network`, jadi container lain sebaiknya mengaksesnya lewat port host 6379 atau Anda perlu menambahkannya ke jaringan itu kalau ingin memakai nama `redis`.

n8n (`n8nio/n8n:latest`) menjalankan workflow otomatis di `workflow.edu-all.com`. Datanya tersimpan di `./n8n_data`. Nginx menerusnya dengan `proxy_pass` lengkap dengan header WebSocket.

### Jaringan

Hanya ada satu jaringan, `app-network` (bridge). Nginx dan semua container PHP serta n8n ada di dalamnya, sehingga nginx bisa memanggil `php_crm:9000` dan sejenisnya berdasarkan nama container.

## Cara satu request diproses

Contoh untuk `crm.edu-all.com`:

1. Browser mengirim request ke server. Nginx mencocokkan `server_name crm.edu-all.com` di `default.conf`.
2. Nginx mencari file di `/crm/public`. Kalau file ada (misalnya gambar atau CSS), nginx menyajikannya langsung.
3. Kalau tidak ada, `try_files` meneruskan ke `/index.php?$query_string`.
4. Blok `location ~ \.php$` mengirim request ke `php_crm:9000` lewat FastCGI, dengan `SCRIPT_FILENAME` bernilai `/crm/public/index.php`.
5. PHP-FPM di container `php_crm` membaca file itu dari `./crm/src` (hasil mount) dan mengirim respons balik.

Header `HTTPS` dan `HTTP_X_FORWARDED_PROTO` diisi dari `$http_x_forwarded_proto`. Ini membuat Laravel mengenali bahwa request asli memakai HTTPS. Itu sesuai dengan kondisi di server: sertifikat diurus oleh AWS, sehingga TLS selesai sebelum request sampai ke nginx, dan `default.conf` cukup mendengarkan port 80. Detail komponen AWS yang menangani sertifikat (misalnya load balancer) belum dicatat di sini dan perlu dipastikan dari konsol AWS.

## Domain dan routing

Semua dikonfigurasi di `nginx/default.conf`, satu blok per domain, diberi komentar pembuka dan penutup seperti `# CRM START` dan `# CRM END`.

| Domain | Tujuan |
|---|---|
| `edu-all.com` | `php_eduall` |
| `staging.edu-all.com` | `php_staging_eduall` |
| `timesheet.edu-all.com` | `php_timesheet` |
| `staging-timesheet.edu-all.com` | `php_timesheet_staging` |
| `assessment.edu-all.com` | `php_assessment` (root `/assessment/v2/public`) |
| `staging-assessment.edu-all.com` | `php_assessment_staging` |
| `crm.edu-all.com` | `php_crm` |
| `staging-crm.edu-all.com` | `staging_php_crm` |
| `api-mentoring.edu-all.com` | `php_mentoring` |
| `mentoring.edu-all.com` | front-end statis `/mentoring/front-end/dist` |
| `api-editing.edu-all.com` | `php_editing_v2` |
| `editing.edu-all.com` | front-end statis `/editing_v2/front-end/dist` |
| `auth.edu-all.com` | `php_authorization` |
| `asset.edu-all.com` | `php_asset` |
| `helpdesk.edu-all.com` | `php_helpdesk` (root `/helpdesk`, tanpa `public`) |
| `registration.edu-all.com` | front-end statis `/registration/dist` |
| `assistant.edu-all.com` | front-end statis `/assistant/dist` |
| `workflow.edu-all.com` | n8n |
| `www.thecornerstone.edu-all.com` | redirect 301 ke `thecornerstone.edu-all.com` |

Setiap blok punya endpoint `/health` yang membalas `200 OK`, berguna untuk pengecekan dari luar.

## Cron dan queue worker

Scheduler dan queue Laravel berjalan di dalam container nginx, bukan di container PHP masing-masing.

- `nginx/cron/cronfile` menjalankan `php artisan schedule:run` setiap menit untuk eduall, editing, crm, editing_v2, dan timesheet. Baris terakhir menjalankan `/queue.sh` setiap menit.
- `nginx/queue.sh` adalah watchdog: ia memeriksa dengan `pgrep` apakah `queue:work` untuk CRM dan editing v2 sedang berjalan, dan menyalakannya kalau belum. Log worker ditulis ke `storage/logs/queue_output.log` di masing-masing project.
- Worker staging CRM sudah ada di `queue.sh` tapi dikomentari.

Konsekuensinya, project yang butuh scheduler atau queue harus ada di mount nginx (karena `artisan` dijalankan dari sana) dan harus didaftarkan di `cronfile` atau `queue.sh`.

## Konfigurasi PHP

Semua Dockerfile PHP mengikuti satu pola: base image `php:8.2-fpm-alpine`, paket `curl bash zip unzip nano nodejs npm` ditambah library gambar, ekstensi `pdo pdo_mysql bcmath gd`, dan Composer. Yang berbeda antar project hanya:

- ekstensi tambahan (`zip`, `mbstring`, `exif`, `mysqli` sesuai kebutuhan aplikasi),
- `WORKDIR` dan tujuan `COPY ./src`,
- apakah `composer install` dan `chmod -R 777 storage/` dijalankan saat build.

Setiap project punya `docker-fpm.ini` yang di-mount ke `/usr/local/etc/php/conf.d/`. Isi dasarnya: `memory_limit = 512M`, `upload_max_filesize = 50M`, `post_max_size = 50M`, dan `max_execution_time = 3000`. Beberapa project (crm, asset-management, helpdesk, mentoring) memakai nilai yang sedikit berbeda.

## Logging dan monitoring

`logstash.conf`, `loki-config.yaml`, dan `promtail-config.yaml` ada di repo, tetapi tidak ada service untuk Logstash, Loki, atau Promtail di `docker-compose.yml`. Kemungkinan keduanya dijalankan dari compose lain di server atau belum diaktifkan. Promtail membaca `/<project>/logs/*.log`, sedangkan Logstash membaca log nginx dan mengirimnya ke Elasticsearch. Log nginx sendiri tersedia di `nginx/logs`.

## Catatan migrasi ke VPS

Langkah lengkapnya ada di `docs/MIGRASI-KE-VPS.md`. Lingkup rencananya: semua project yang masih aktif pindah ke VPS, yaitu eduall, assessment, timesheet (masing-masing dengan staging), helpdesk, asset-management, dan n8n. Project lain (crm yang sudah diganti Odoo, editing, editing_v2, mentoring, authorization, junior, serta frontend `registration` dan `assistant`) sudah tidak aktif dan tidak dipindah. RDS (Jakarta), S3, dan Route 53 tetap di AWS. Setelah masa stabilisasi, EC2, load balancer, dan WAF dimatikan. Motivasinya efisiensi anggaran: tagihan AWS Oktober 2026 sekitar USD 250, dan komputasi serta jaringan (EC2, ELB, VPC, EC2-Other, WAF) menyumbang sekitar 73% dari subtotal.

Hal-hal yang sekarang ditangani AWS atau bergantung padanya, dan harus punya pengganti atau penyesuaian di VPS:

- Sertifikat HTTPS. Di AWS, TLS selesai sebelum nginx. Di VPS, tidak ada yang melakukannya kecuali Anda menyiapkannya. Pilihannya: pasang TLS di nginx (Certbot dengan Let's Encrypt dan plugin DNS Route 53, lalu `listen 443 ssl` di server block), atau taruh reverse proxy seperti Caddy atau Cloudflare di depan. Bila TLS dipasang di nginx, header `X-Forwarded-Proto` dari `$http_x_forwarded_proto` tidak akan terisi, jadi baris `fastcgi_param HTTPS` perlu diubah menjadi `$scheme`. Bila memakai proxy di depan, pola yang sekarang tetap berlaku.
- Mount sertifikat `/etc/letsencrypt/live/edu-all.com-0002/...` di compose merujuk file di host server lama. Hapus atau sesuaikan sesuai pilihan di atas. `nginx/editing.conf` dan `security.conf` sudah memuat contoh konfigurasi SSL, tetapi belum dipakai.
- Firewall dan WAF. Aturan akses (security group) dan WAF AWS perlu diganti dengan firewall di VPS (misalnya `ufw`, hanya port 80 dan 443), pembatasan laju di nginx, dan `fail2ban`. Port 9001 sampai 9012, 6379, dan 5678 yang dipetakan di compose sebaiknya tidak terbuka ke publik.
- DNS. DNS tetap di Route 53. Sembilan domain diarahkan ke IP VPS. Record yang berupa alias ke resource AWS harus diganti dengan A record. Cutover bisa dilakukan satu per satu, staging dulu.
- Database dan S3. Tetap di AWS, sehingga latensi, keamanan, dan biaya data transfer dari VPS ke AWS menjadi risiko utama. Karena EC2 akan dimatikan, cara koneksi ke RDS yang praktis adalah allowlist IP VPS dengan TLS. Aplikasi butuh kredensial IAM khusus untuk S3 bila di AWS memakai IAM role.
- Data. Clone ulang `src` delapan aplikasi PHP dari repo masing-masing (tidak ada di repo ini), lalu salin dan sesuaikan `.env`. File upload ada di S3, sehingga tidak perlu disalin. `n8n_data` dipindahkan saat cutover n8n. `redis-data` tidak perlu dipindah.
- Scheduler dan n8n. Baris `schedule:run` untuk eduall dan timesheet harus dipindah dari `cronfile` AWS ke VPS, dan workflow n8n tidak boleh aktif di dua tempat. Keduanya bisa menjalankan pekerjaan dua kali bila aktif bersamaan.
- Spesifikasi. VPS menjalankan nginx, n8n, dan delapan container PHP-FPM (Redis hanya bila ternyata dipakai), jauh lebih ringan dari stack penuh. Ukur dari `docker stats` untuk container-container itu.

## Hal yang perlu diketahui

Beberapa temuan saat membaca repo. Ini bukan perubahan yang saya buat, hanya catatan.

- `docker-compose.yml` merujuk `./staging-crm`, tetapi folder itu tidak ada di repo (yang ada hanya `crm`). Service `staging_php_crm` tidak akan bisa di-build dari checkout bersih sampai folder tersebut dibuat atau compose disesuaikan.
- Nginx me-mount `./registration/src`, `./assistant/src`, `./mentoring/front-end/src`, dan `./editing_v2/front-end/src`. Keempatnya tidak punya Dockerfile karena hanya menyajikan hasil build statis.
- `cronfile` menjalankan `/editing/artisan`, tetapi `./editing/src` tidak di-mount ke nginx. Entri itu tidak akan berfungsi.
- `docker-compose.yml` dan `logstash.conf` memuat password dalam bentuk teks biasa (n8n dan Elasticsearch). Sebaiknya dipindah ke file `.env` atau Docker secrets.
- `.gitignore` hanya mencantumkan sebagian folder `src`. Project seperti `authorization`, `helpdesk`, `mentoring`, `editing_v2`, dan versi staging belum tercantum, jadi `src`-nya bisa ikut ter-commit kalau tidak hati-hati.
- `README.md` di root masih menulis 13 service dan sebagian detail yang tidak sama dengan compose saat ini (misalnya klaim health check dan sertifikat yang dikelola otomatis).
- `editing.conf` berisi server block HTTPS untuk editing, tetapi tidak di-mount ke container nginx, jadi tidak aktif.
