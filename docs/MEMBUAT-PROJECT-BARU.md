# Membuat project baru di repo eduall-docker

Panduan ini menjelaskan langkah menambahkan satu aplikasi baru ke server. Contoh yang dipakai: aplikasi Laravel bernama `payroll` yang diakses lewat `payroll.edu-all.com`. Ganti `payroll` dengan nama project Anda. Untuk gambaran arsitektur, baca `docs/ARSITEKTUR.md`.

## Sebelum mulai

Siapkan hal berikut:

- URL repository aplikasi (kode aplikasi ada di repo terpisah).
- Nama project, domain, dan versi PHP yang dibutuhkan (repo ini memakai PHP 8.2).
- Port host yang belum terpakai. Cek dengan `grep -n '"9' docker-compose.yml`. Port production terakhir yang terpakai adalah 9012, staging di 9100 sampai 9102.
- DNS untuk domain baru sudah mengarah ke server.
- Sertifikat HTTPS untuk domain baru tersedia. Saat ini sertifikat diurus oleh AWS, jadi domain baru perlu dicakup di sisi AWS (misalnya ditambahkan ke sertifikat atau cocok dengan wildcard yang ada). Nginx di repo ini tidak menangani TLS. Setelah migrasi ke VPS, langkah ini akan berubah, lihat "Catatan migrasi ke VPS" di `docs/ARSITEKTUR.md`.
- Port 80 pada server dapat dijangkau dari komponen AWS yang meneruskan traffic ke nginx.

Pilih tipe project:

- Aplikasi PHP/Laravel: butuh container PHP-FPM sendiri (langkah 1 sampai 8).
- Aplikasi frontend statis (hasil build Vue/React): tidak butuh container PHP. Lompat ke bagian "Project frontend statis" di bawah.

## Langkah untuk aplikasi PHP

### 1. Buat folder project

```bash
mkdir payroll
```

Untuk project dengan back-end dan front-end terpisah, pakai `payroll/back-end/` untuk bagian PHP, seperti `mentoring/back-end`.

### 2. Buat Dockerfile

Salin Dockerfile dari project yang paling mirip, lalu ganti nama path-nya.

```bash
cp crm/Dockerfile payroll/Dockerfile
```

Pola dasarnya:

```dockerfile
FROM php:8.2-fpm-alpine

RUN apk add --no-cache \
    curl \
    bash \
    libpng-dev \
    libjpeg-turbo-dev \
    libwebp-dev \
    freetype-dev \
    libzip-dev \
    oniguruma-dev \
    zip \
    unzip \
    nano \
    nodejs \
    npm \
    && docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp \
    && docker-php-ext-install pdo pdo_mysql bcmath gd zip mbstring

WORKDIR /payroll

COPY ./src /payroll/
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

EXPOSE 9000

CMD ["sh", "-c", "php-fpm"]
```

Yang perlu Anda sesuaikan:

- Semua `payroll` pada `WORKDIR` dan `COPY` harus sama dengan nama path yang nanti dipakai di compose dan nginx.
- Tambah atau kurangi ekstensi PHP sesuai kebutuhan. Contoh: `mysqli` dipakai helpdesk, `exif` dipakai asset-management. Ekstensi yang butuh library sistem (seperti `zip` butuh `libzip-dev`, `mbstring` butuh `oniguruma-dev`) harus ditambahkan di `apk add`.
- `composer install` dan `chmod -R 777 storage/` boleh ditambahkan saat build, seperti di `crm`. Karena `src` di-mount saat runtime, hasil `composer install` di image akan tertimpa mount. Jadi cara yang lebih aman adalah menjalankannya di dalam container setelah container hidup (langkah 7).

`COPY ./src` mengharuskan folder `src` ada saat `docker compose build`, jadi clone repo dulu (langkah 4) sebelum build.

### 3. Buat docker-fpm.ini

```bash
cp eduall/docker-fpm.ini payroll/docker-fpm.ini
```

Isi bawaannya:

```ini
default_socket_timeout = 3000
fastcgi.logging = Off
max_allowed_packet = 64M
max_execution_time = 3000
max_input_time = 3000
memory_limit = 512M
post_max_size = 50M
upload_max_filesize = 50M
```

Ubah nilainya hanya kalau aplikasi benar-benar butuh, misalnya upload file lebih besar dari 50 MB.

### 4. Clone repo aplikasi ke src

```bash
git clone <url-repo-payroll> payroll/src
```

Lalu tambahkan folder ini ke `.gitignore` supaya kode aplikasi tidak ikut ter-commit ke repo docker. Isi `.gitignore` saat ini hanya memuat sebagian project, jadi periksa dulu.

```bash
printf '\npayroll/src\n' >> .gitignore
```

Siapkan juga `.env` aplikasi di `payroll/src/.env` (database, Redis, URL, dan sebagainya). File ini ada di dalam `src`, jadi tidak masuk repo docker.

### 5. Daftarkan service di docker-compose.yml

Tambahkan blok service PHP, mengikuti pola project lain:

```yaml
  php_payroll:
    build:
      context: ./payroll
      dockerfile: Dockerfile
    container_name: php_payroll
    volumes:
      - ./payroll/src:/payroll
      - ./payroll/docker-fpm.ini:/usr/local/etc/php/conf.d/docker-fpm.ini
    networks:
      - app-network
    ports:
      - "9013:9000"
```

Aturan yang perlu dijaga:

- Path di sisi kanan volume (`/payroll`) harus sama dengan `WORKDIR` di Dockerfile dan dengan mount di nginx.
- Port sisi kiri (`9013`) harus unik. Sisi kanan selalu `9000`.
- `container_name` dipakai nginx sebagai hostname, jadi nama ini harus sama persis dengan yang ada di `fastcgi_pass`.

Pada service `nginx`, tambahkan dua hal:

```yaml
  nginx:
    volumes:
      # ... mount yang sudah ada
      - ./payroll/src:/payroll
    depends_on:
      # ... service yang sudah ada
      - php_payroll
```

Mount ini wajib. Nginx perlu membaca `/payroll/public` untuk file statis dan memeriksa `try_files`.

### 6. Tambahkan server block di nginx

Buka `nginx/default.conf` dan tambahkan blok baru dengan komentar pembuka dan penutup, seperti project lain. Contoh untuk Laravel standar:

```nginx
# PAYROLL START
    server {
        listen 80;
        server_name payroll.edu-all.com;
        root /payroll/public;
        index index.php index.html;

        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }

        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }

        location ~ \.php$ {
            try_files $uri =404;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass php_payroll:9000;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $fastcgi_path_info;

            # Supaya Laravel tahu request aslinya HTTPS
            fastcgi_param HTTPS $http_x_forwarded_proto;
            fastcgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto;

            fastcgi_connect_timeout 600s;
            fastcgi_send_timeout    600s;
            fastcgi_read_timeout    600s;
        }

        location ~ /\.(?!well-known).* {
            deny all;
        }
    }
# PAYROLL END
```

Hal yang perlu dicocokkan:

- `server_name` sama dengan domain.
- `root` mengarah ke folder `public` aplikasi. Beberapa aplikasi non-Laravel (seperti helpdesk) memakai root tanpa `public`.
- `fastcgi_pass` memakai `container_name` dari langkah 5.
- Timeout: project lama memakai 14400 detik (4 jam) atau 600 detik. Pilih sesuai kebutuhan, jangan asal menyalin angka terbesar.

### 7. Build dan jalankan

```bash
docker compose build php_payroll
docker compose up -d php_payroll
```

Install dependency dan siapkan aplikasi di dalam container:

```bash
docker compose exec php_payroll composer install --no-dev --optimize-autoloader
docker compose exec php_payroll php artisan key:generate   # hanya kalau APP_KEY belum ada
docker compose exec php_payroll php artisan migrate --force
docker compose exec php_payroll chmod -R 777 storage bootstrap/cache
```

Lalu muat ulang nginx. Cek konfigurasinya dulu supaya tidak menjatuhkan semua domain kalau ada salah ketik:

```bash
docker compose exec nginx nginx -t
docker compose up -d nginx    # perlu karena ada volume dan depends_on baru
docker compose exec nginx nginx -s reload
```

Perhatikan bahwa `up -d nginx` membuat ulang container nginx kalau definisinya berubah, dan itu menyebabkan downtime singkat untuk semua domain. Lakukan di jam sepi. Kalau yang berubah hanya `default.conf`, `nginx -s reload` sudah cukup.

### 8. Scheduler dan queue (kalau dibutuhkan)

Scheduler dan queue worker berjalan di container nginx. Kalau aplikasi memakai `schedule:run`, tambahkan satu baris di `nginx/cron/cronfile`:

```cron
* * * * * /usr/bin/php /payroll/artisan schedule:run >> /var/log/cronjob.log 2>> /var/log/cron_error.log
```

Kalau aplikasi memakai queue, tambahkan pemanggilan di `nginx/queue.sh`:

```bash
# PAYROLL
run_if_not_running "PAYROLL" \
    "/usr/bin/php /payroll/artisan queue:work --queue=default,mail" \
    "/payroll/storage/logs/queue_output.log"
```

Dua file itu di-mount ke container, tetapi cron membaca `cronfile` saat container start. Setelah mengubahnya, restart container nginx: `docker compose restart nginx`.

### 9. Verifikasi

```bash
docker compose ps                         # php_payroll harus Up
docker compose logs php_payroll --tail 50
curl -i http://payroll.edu-all.com/health # harus 200 OK
```

Kalau halaman tampil 502, biasanya `fastcgi_pass` salah nama atau container PHP belum jalan. Kalau 404 dari nginx, periksa `root` dan mount di nginx. Kalau 403 atau "File not found.", path di Dockerfile, compose, dan nginx kemungkinan tidak sama.

### 10. Commit

Hanya file konfigurasi yang masuk repo ini:

```bash
git add payroll/Dockerfile payroll/docker-fpm.ini docker-compose.yml nginx/default.conf .gitignore
# tambahkan nginx/cron/cronfile dan nginx/queue.sh kalau diubah
git status    # pastikan payroll/src tidak muncul
git commit -m "add payroll project"
```

## Project frontend statis

Aplikasi Vue/React yang sudah di-build tidak butuh container PHP. Yang diperlukan hanya mount di nginx dan satu server block.

1. Build dilakukan di komputer lokal, bukan di server. Jalankan `npm run build`, lalu commit dan push hasilnya (folder `dist`) ke GitHub. Pastikan `dist` tidak masuk `.gitignore` di repo frontend. Di server, clone repo itu ke `payroll-web/src` sehingga hasil build ada di `payroll-web/src/dist`. Untuk update berikutnya, cukup `git pull` di folder tersebut.
2. Tambahkan folder `src` ke `.gitignore`.
3. Tambahkan mount ke service `nginx`:

   ```yaml
   - ./payroll-web/src:/payroll-web
   ```

4. Tambahkan server block di `nginx/default.conf`:

   ```nginx
   # PAYROLL WEB START
       server {
           listen 80;
           server_name payroll-web.edu-all.com;
           root /payroll-web/dist;
           index index.html;

           location / {
               try_files $uri $uri/ /index.html;
           }

           location /health {
               return 200 'OK';
               add_header Content-Type text/plain;
           }
       }
   # PAYROLL WEB END
   ```

5. Recreate nginx seperti di langkah 7.

Kalau frontend itu pasangan dari sebuah back-end, ikuti pola `mentoring` dan `editing_v2`: satu folder project dengan `back-end/` dan `front-end/`, dan nginx me-mount keduanya.

## Project staging

Staging diperlakukan sebagai project terpisah dengan folder, container, dan domain sendiri, seperti `eduall-staging` dan `timesheet-staging`. Salin folder production, ganti semua nama path menjadi `<nama>-staging`, pakai port di rentang 9100 ke atas, dan domain `staging-<nama>.edu-all.com`. Clone branch staging ke `src`.

## Checklist

Pastikan semua titik ini konsisten, karena sebagian besar error muncul dari nama yang tidak sama:

- Nama path `payroll` sama di `WORKDIR`, `COPY`, volume PHP, volume nginx, dan `root` di nginx.
- `container_name` sama dengan hostname di `fastcgi_pass`.
- Port host unik.
- `payroll/src` ada di `.gitignore`.
- `php_payroll` ada di `depends_on` nginx.
- Domain sudah mengarah ke server.
- `nginx -t` lolos sebelum reload.
- Kalau memakai scheduler atau queue: `cronfile` dan `queue.sh` sudah diubah dan nginx sudah di-restart.
