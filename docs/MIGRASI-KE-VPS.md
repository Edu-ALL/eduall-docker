# Migrasi dari AWS (EC2) ke VPS

Dokumen ini adalah rencana kerja untuk memindahkan semua project yang masih aktif dari EC2 ke VPS. Migrasinya belum dijadwalkan, jadi anggap ini draf yang perlu diperiksa ulang sebelum eksekusi. Beberapa hal tentang server AWS saat ini belum tercatat, dan ditandai sebagai "perlu dipastikan".

Baca `docs/ARSITEKTUR.md` lebih dulu untuk memahami komponennya.

## Lingkup migrasi

Project yang masih aktif dan dipindah ke VPS:

| Project | Domain |
|---|---|
| eduall | `edu-all.com` |
| eduall staging | `staging.edu-all.com` |
| assessment | `assessment.edu-all.com` |
| assessment staging | `staging-assessment.edu-all.com` |
| timesheet | `timesheet.edu-all.com` |
| timesheet staging | `staging-timesheet.edu-all.com` |
| helpdesk | `helpdesk.edu-all.com` |
| asset-management | `asset.edu-all.com` |
| n8n | `workflow.edu-all.com` |

Repo ini tidak punya staging untuk helpdesk dan asset-management.

Project yang sudah tidak aktif dan tidak dipindah: crm (sudah dimatikan, diganti Odoo), staging-crm, editing, editing_v2, mentoring, authorization, junior, serta frontend statis `registration` dan `assistant` (kedua frontend ini ikut dalam kategori "project lain" menurut tim, tolong dikonfirmasi). Semuanya tidak perlu hadir di VPS.

Hal yang tetap di AWS:

- Database: RDS di region `ap-southeast-3` (Jakarta). Catatan penamaan: `ap-southeast-3` adalah region, sedangkan `ap-southeast-3a` adalah availability zone di dalamnya.
- File upload: S3.
- DNS: Route 53 untuk semua subdomain.

Alasan migrasi adalah efisiensi anggaran. Tagihan AWS bulan Oktober 2026 sebesar USD 250 (tim menyebutnya sekitar Rp5 juta per bulan). Rinciannya ada di bagian "Rincian tagihan Oktober 2026". Karena hanya dua project lain yang masih aktif (asset-management dan n8n) dan keduanya ikut pindah, skenario yang dipakai dokumen ini adalah skenario B: semua komputasi pindah ke VPS, sedangkan RDS, S3, dan Route 53 tetap di AWS.

Konsekuensinya:

- Setelah masa stabilisasi, EC2, load balancer, WAF, dan resource jaringan terkait bisa dimatikan. Itu sumber penghematan utamanya. Syaratnya tidak ada server lain yang masih membutuhkan resource itu (misalnya server Odoo, bila berada di akun AWS yang sama).
- Setelah EC2 dimatikan, tidak ada lagi "jalan pulang" ke AWS untuk rollback. Rollback hanya tersedia selama masa stabilisasi, saat EC2 masih menyala.
- VPS menjalankan nginx, delapan container PHP-FPM (eduall, assessment, timesheet masing-masing production dan staging, helpdesk, asset-management), dan n8n. Compose di VPS adalah subset dari `docker-compose.yml`, bukan salinan penuh.
- Aplikasi di VPS terhubung ke RDS dan S3 lewat internet. Latensi, keamanan, dan biaya data transfer dari koneksi itu menjadi risiko utama (Tahap 3). Karena EC2 akan dimatikan, VPN lewat EC2 tidak bisa jadi pilihan.
- RDS kemungkinan masih memuat database project yang sudah mati (crm, editing, mentoring, authorization). Arsipkan lalu bersihkan (lihat "Mematikan resource AWS").
- Cutover dilakukan per domain lewat Route 53. Database dan file upload dipakai bersama sehingga tidak perlu disinkronkan. Yang harus dijaga: scheduler (dan jadwal workflow n8n) tidak boleh berjalan di dua tempat sekaligus.
- Redis: menurut tim, belum pernah ada yang menyentuhnya. Kemungkinan tidak dibutuhkan. Cek `.env` (Tahap 2).
- Staging dipindah lebih dulu sebagai gladi resik sebelum production (Tahap 6).

## Periksa biaya sebelum mulai

Tujuan migrasi adalah menekan tagihan. Penghematan hanya terjadi bila komponen AWS yang mahal benar-benar bisa dimatikan, dan bila biaya baru (VPS dan data transfer) lebih kecil dari yang hilang. Bagian ini dan rincian tagihan di bawahnya menjelaskan hitungannya.

1. Lihat rincian tagihan 3 bulan terakhir di Cost Explorer: kelompokkan per Service, lalu per Usage type. Catat nominal untuk EC2 (instance, EBS, snapshot), RDS (instance, storage, backup, Multi-AZ), data transfer, S3, Route 53, NAT gateway, load balancer, public IPv4, dan CloudWatch.
2. Pahami biaya baru akibat pemisahan. Saat aplikasi di EC2 dan database di RDS satu region, lalu lintas antar keduanya, serta antara EC2 dan S3 di region yang sama, umumnya tidak dikenai biaya data transfer. Setelah aplikasi pindah ke VPS, setiap hasil query dari RDS dan setiap file yang diunduh dari S3 keluar dari AWS ke internet dan dihitung sebagai data transfer out per GB. Cek tarif untuk `ap-southeast-3` di halaman harga AWS dan perkirakan volumenya dari metrik (`NetworkOut` RDS, metrik request S3, atau Cost Explorer).
3. Hitung penghematan bersih:

   ```
   penghematan = biaya EC2 yang berkurang
               + biaya komponen lain yang ikut hilang (EBS, IP, dan seterusnya)
               - biaya VPS
               - biaya data transfer baru (RDS dan S3 ke VPS)
   ```

4. Putuskan menurut komponen terbesar:

   | Komponen terbesar | Dampak migrasi sebagian | Arah yang masuk akal |
   |---|---|---|
   | EC2 | Efektif, dengan syarat data transfer baru kecil | Lanjut sesuai dokumen ini |
   | RDS | Memindahkan aplikasi tidak mengurangi tagihan RDS | Pertimbangkan memperkecil instance, mematikan Multi-AZ untuk staging, Reserved Instance, atau memindahkan database ke MySQL di VPS (lebih murah, tetapi backup, update, dan ketersediaan menjadi tanggung jawab Anda) |
   | Data transfer, NAT gateway, atau public IPv4 | Perlu dicari sumbernya dulu | Telusuri per usage type sebelum memutuskan |
   | S3 | Biaya egress ke VPS bisa naik | Pertimbangkan CDN di depan S3, atau objek storage lain yang tanpa biaya egress |

5. Periksa juga penghematan tanpa pindah server: perkecil ukuran instance (right-sizing), Savings Plans atau Reserved Instance, hapus snapshot dan volume EBS yang tidak terpakai, dan matikan staging di luar jam kerja. Kadang ini sudah menurunkan tagihan cukup besar dengan risiko jauh lebih kecil.

Staging punya peluang hemat tersendiri. Kalau staging memakai instance RDS sendiri, memindahkan database staging ke MySQL di VPS biasanya paling aman dan murah, karena datanya tidak kritis dan latensi ke RDS tidak lagi terlibat (Tahap 3).

## Rincian tagihan Oktober 2026

| Komponen | USD | Porsi |
|---|---|---|
| EC2 | 127 | 51% |
| RDS | 41 | 16% |
| Tax | 25 | 10% |
| Elastic Load Balancing | 20 | 8% |
| VPC | 15 | 6% |
| EC2-Other | 10 | 4% |
| WAF | 10 | 4% |
| Route 53 | 1 | 0,4% |
| S3 | 0,25 | 0,1% |
| Total | sekitar 250 | |

Hal yang terlihat dari angka ini:

- Subtotal sebelum pajak sekitar USD 225, dan pajak USD 25 kira-kira 11% darinya. Artinya setiap dolar yang dihemat sebenarnya menghemat sekitar USD 1,11.
- Komputasi dan jaringan (EC2, Elastic Load Balancing, VPC, EC2-Other, WAF) bernilai USD 182, atau sekitar 73% dari subtotal. RDS hanya USD 41, dan S3 serta Route 53 nyaris tidak berarti. Jadi sasaran penghematan yang masuk akal adalah komputasi dan jaringan, bukan data.
- Kekhawatiran soal biaya data transfer S3 tidak berat: tagihan S3 hanya USD 0,25, jadi volume data di sana kecil. Yang masih perlu dicek adalah lalu lintas dari RDS ke VPS (lihat metrik `NetworkTransmitThroughput` RDS).
- Elastic Load Balancing, WAF, dan sebagian VPC kemungkinan terkait satu sama lain. Load balancer biasanya tempat sertifikat HTTPS diterminasi, dan WAF biasanya menempel pada load balancer. Kalau masih ada project yang dilayani lewat load balancer itu di AWS, komponen-komponen ini tetap ditagih.
- Angka USD 15 di VPC biasanya berasal dari alamat public IPv4 atau NAT gateway, dan USD 10 di EC2-Other biasanya EBS, snapshot, atau data transfer. Konfirmasi lewat Cost Explorer dengan mengelompokkan per Usage type (misalnya `PublicIPv4:InUseAddress`, `NatGateway-Hours`, `EBS:VolumeUsage`, `EBS:SnapshotUsage`, `DataTransfer-Out-Bytes`). Dugaan di sini belum diverifikasi.

### Skenario cakupan

Angka di bawah memakai subtotal USD 225 dan pajak sekitar 11%. Biaya VPS, biaya data transfer baru, dan sisa komponen yang tidak bisa dimatikan belum dimasukkan, jadi anggap ini batas atas penghematan.

| Skenario | Yang tersisa di AWS | Perkiraan tagihan AWS setelahnya | Catatan |
|---|---|---|---|
| Sekarang | Semuanya | USD 250 | |
| A. Tujuh aplikasi pindah, EC2 dikecilkan | EC2 (lebih kecil), RDS, ELB, WAF, VPC, S3, Route 53 | Turun sebesar pengurangan EC2 dikali 1,11. Misalnya EC2 turun separuh: sekitar USD 180 | Penghematan hanya terjadi bila instance benar-benar bisa diperkecil atau dihentikan. Kalau semua project berbagi satu EC2 yang tidak bisa dikecilkan, penghematannya mendekati nol dan Anda malah menambah biaya VPS |
| B. Semua aplikasi pindah, RDS tetap | RDS, S3, Route 53 (dan IP publik RDS bila publicly accessible) | Sekitar USD 47 (42,25 dikali 1,11) | ELB, WAF, EC2, EBS, dan sebagian VPC hilang. Penghematan kasar sekitar USD 200 per bulan sebelum biaya VPS dan data transfer |
| C. Semua pindah termasuk database | S3 dan Route 53 | Sekitar USD 1,5 | Penghematan tambahan hanya sekitar USD 45 (RDS) dibanding B, dengan konsekuensi backup, update, dan ketersediaan database ada di tangan Anda |

Pelajaran dari tabel ini:

- Skenario A paling rapuh. Hasilnya bergantung pada apakah EC2 bisa dikecilkan setelah aplikasi pergi.
- Skenario B menghemat jauh lebih banyak dan secara teknis lebih sederhana: seluruh stack aktif dipindah dengan konfigurasi yang hampir sama, tanpa memisah konfigurasi dan tanpa SSO yang terbelah antara dua server. Karena project lain sudah tidak aktif, B adalah skenario yang dipakai dokumen ini.
- RDS yang hanya USD 41 adalah alasan untuk tidak buru-buru memindahkan database. Mulailah dari B, ukur latensi dan biaya, lalu putuskan C belakangan.
- Perkiraan di skenario B mengasumsikan EC2, ELB, WAF, EC2-Other, dan VPC (selain IP publik RDS) benar-benar bisa dimatikan. Kalau ada server lain di akun yang sama (misalnya Odoo), tagihan EC2 tidak akan hilang seluruhnya.

### Cara melihat instance EC2 dan isinya

Dari konsol AWS:

- EC2 > Instances. Pilih region Asia Pacific (Jakarta) `ap-southeast-3`, lalu lihat kolom Instance type dan State. Periksa juga region lain lewat dropdown region atau EC2 Global View, karena instance bisa saja berada di region berbeda.
- EC2 > Load Balancers > pilih load balancer > Listeners dan Target groups > Targets. Di sini terlihat instance mana yang berada di belakang load balancer.
- Cost Explorer, kelompokkan per Usage type. Entri seperti `APS3-BoxUsage:t3.large` menunjukkan tipe instance dan jam pemakaiannya, jadi Anda bisa memperkirakan jumlah dan ukuran instance dari tagihan.

Dari AWS CLI (butuh kredensial dengan akses baca):

```bash
# daftar instance beserta tipe dan nama
aws ec2 describe-instances --region ap-southeast-3 \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,PrivateIpAddress,PublicIpAddress,Tags[?Key==`Name`]|[0].Value]' \
  --output table

# volume EBS, Elastic IP, load balancer, dan web ACL WAF
aws ec2 describe-volumes --region ap-southeast-3 \
  --query 'Volumes[].[VolumeId,Size,VolumeType,State,Attachments[0].InstanceId]' --output table
aws ec2 describe-addresses --region ap-southeast-3 --output table
aws elbv2 describe-load-balancers --region ap-southeast-3 \
  --query 'LoadBalancers[].[LoadBalancerName,Type,DNSName]' --output table
aws wafv2 list-web-acls --scope REGIONAL --region ap-southeast-3
```

Dari dalam server (untuk tahu apa yang berjalan di instance itu):

```bash
# tipe instance (IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type

# spesifikasi dan pemakaian
nproc; free -h; df -h

# container yang berjalan dan pemakaian sumber dayanya
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
docker stats --no-stream
```

Satu hal yang perlu dipastikan: apakah masih ada instance lain di akun yang sama yang tidak menjalankan stack ini, misalnya server Odoo, bastion, atau instance lama. Kalau ada, instance itu menentukan apakah EC2 bisa dimatikan sepenuhnya.

### Pertanyaan yang masih terbuka

1. Berapa instance EC2 yang ada, dan apakah ada instance selain yang menjalankan stack ini (terutama Odoo)?
2. Apakah `registration`, `assistant`, dan redirect `thecornerstone` benar-benar sudah tidak dipakai?
3. Kalau Odoo berada di akun AWS yang sama, apakah ikut pindah atau tetap di AWS?

### Penghematan tanpa pindah server

Hal-hal ini bisa dikerjakan di AWS dengan risiko kecil, dan sebagian besar bisa dikerjakan sebelum atau tanpa migrasi:

- EC2 ($127): periksa pemakaian CPU dan memori dari CloudWatch dan AWS Compute Optimizer (gratis). Kalau rata-rata CPU rendah, turunkan ukuran. Pertimbangkan Savings Plans atau Reserved Instance satu tahun untuk beban yang pasti jalan terus.
- RDS ($41): periksa apakah Multi-AZ aktif dan perlu, ukuran storage, dan retensi backup. Reserved Instance juga tersedia untuk RDS.
- VPC ($15): cari tahu apakah ini NAT gateway atau alamat public IPv4. Lepaskan Elastic IP yang tidak terpasang dan hapus NAT gateway yang tidak dipakai.
- WAF ($10): tinjau aturan yang aktif. Lepaskan web ACL yang tidak menempel ke resource atau yang tidak lagi dibutuhkan. Kalau WAF dipertahankan karena perlindungan, bandingkan dengan alternatif lain setelah migrasi.
- EC2-Other ($10): hapus volume EBS yang tidak terpasang dan snapshot lama.
- Elastic Load Balancing ($20): pastikan semua target group dan load balancer yang ada memang dipakai.

Pengaman di sisi VPS: WAF tidak ikut pindah. Pertimbangkan pembatasan laju di nginx (`limit_req`), `fail2ban`, dan pembaruan keamanan otomatis. Perlindungan seperti Cloudflare butuh zona DNS dipindah dari Route 53, dan itu baru layak dipertimbangkan bila semua domain pindah.

## Yang berubah dan yang tidak

Tidak berubah: isi repo ini, Dockerfile, `docker-fpm.ini`, konfigurasi nginx per domain, pola `src` di repo terpisah. Semuanya berjalan di Docker, jadi bisa dibawa apa adanya.

Berubah atau perlu diganti:

| Hal | Di AWS sekarang | Yang harus disiapkan di VPS |
|---|---|---|
| Sertifikat HTTPS | Diurus AWS, TLS selesai sebelum nginx | Pasang sendiri (lihat bagian TLS) |
| Firewall | Security group | `ufw` atau firewall dari penyedia VPS |
| DNS | Route 53 | Tetap di Route 53, record sembilan domain diarahkan ke IP VPS |
| EC2, ELB, WAF, EBS | Menjalankan semua project | Dimatikan setelah masa stabilisasi |
| Database | RDS di AWS (Jakarta) | Tetap di RDS, VPS terhubung lewat jaringan (Tahap 3) |
| Redis | Ada di compose AWS, tim belum pernah menyentuhnya | Kemungkinan tidak dibutuhkan, cek `.env` (Tahap 2) |
| Scheduler Laravel | Di container nginx AWS | Pindah ke nginx VPS per aplikasi, tidak boleh aktif di dua tempat |
| File upload | S3 | Tetap di S3, VPS butuh kredensial IAM (Tahap 2) |
| Backup | Perlu dipastikan (snapshot EBS?) | Jadwal backup baru |
| Alamat IP publik | IP atau Elastic IP AWS | IP VPS, dan whitelist di layanan pihak ketiga |

## Tahap 0: inventaris di server AWS

Lakukan ini sebelum menyentuh VPS. Hasilnya menentukan seberapa besar pekerjaan sebenarnya.

1. Catat komponen AWS yang menangani sertifikat dan traffic masuk (load balancer, CloudFront, atau lainnya), termasuk domain apa saja yang tercakup sertifikatnya. Cek di konsol AWS.
2. Catat detail RDS yang tetap di AWS. `docker-compose.yml` tidak punya service MySQL, padahal semua aplikasi memakai `pdo_mysql`. Lihat `DB_HOST` di `.env` tiap project, lalu pastikan di konsol AWS: kelas instance dan harganya, Multi-AZ aktif atau tidak, apakah publicly accessible, security group dan aturan inbound port 3306, versi MySQL, nilai `max_connections`, dan apakah `require_secure_transport` aktif. Catat juga apakah database staging berada di instance RDS yang sama dengan production atau di instance terpisah.
3. Salin daftar `.env` semua project. Buka `<project>/src/.env` satu per satu dan catat variabel yang bergantung pada AWS: S3 bucket, SES atau SMTP, SQS, dan IP whitelist.
4. Catat daftar repo dan branch yang sedang aktif di tiap `<project>/src`:

   ```bash
   for d in */src */*/src; do [ -d "$d/.git" ] && echo "$d: $(git -C $d remote get-url origin) @ $(git -C $d rev-parse --abbrev-ref HEAD)"; done
   ```

5. Ukur kebutuhan sumber daya:

   ```bash
   docker stats --no-stream
   free -h
   df -h
   du -sh */src redis-data n8n_data nginx/logs 2>/dev/null
   ```

6. Cek cron di host (di luar container) yang mungkin ikut berjalan: `crontab -l` dan `ls /etc/cron.d`. Scheduler Laravel ada di container nginx, tetapi mungkin ada job lain di host.
7. Cek layanan luar yang membatasi akses berdasarkan IP server lama (database, API pihak ketiga, SMTP, payment). IP VPS yang baru harus didaftarkan di sana.
8. Periksa ketergantungan delapan aplikasi PHP (production dan staging) pada hal yang tetap di AWS:

   ```bash
   grep -nE 'REDIS_|SESSION_DRIVER|CACHE_DRIVER|CACHE_STORE|QUEUE_CONNECTION|DB_HOST|APP_URL|php_|auth|sso|n8n|workflow' \
     eduall/src/.env eduall-staging/src/.env assessment/src/.env assessment-staging/src/.env \
     helpdesk/src/.env asset-management/src/.env timesheet/src/.env timesheet-staging/src/.env
   ```

   Hal yang dicari: apakah `SESSION_DRIVER`, `CACHE_DRIVER`, atau `QUEUE_CONNECTION` memakai Redis; apakah session atau token dibagi dengan `authorization` (SSO) lewat Redis yang sama; apakah ada URL internal seperti `http://php_authorization:9000` yang tidak akan bisa dijangkau dari VPS dan harus diganti dengan URL publik; dan apakah aplikasi lain mengantre job lewat Redis yang sama (di `queue.sh` hanya CRM dan editing yang punya worker, tetapi pastikan tidak ada job dari aplikasi yang pindah yang diproses di sana).
9. Catat cara aplikasi mengakses S3. Lihat `FILESYSTEM_DISK` (atau `FILESYSTEM_DRIVER`) dan variabel `AWS_*` di `.env`. Hal yang menentukan: apakah autentikasi memakai access key di `.env` atau IAM role yang menempel pada EC2 (instance profile). Kalau memakai IAM role, di VPS tidak ada role itu, jadi Anda perlu IAM user khusus dengan access key. Periksa juga bucket policy (apakah membatasi akses ke VPC atau IP tertentu), pengaturan CORS, region bucket, dan apakah file dilayani langsung oleh S3 (URL publik atau presigned) atau lewat aplikasi.
10. Catat record Route 53 untuk semua domain (sembilan domain yang pindah, ditambah record project nonaktif yang akan dibersihkan): hosted zone, jenis record (alias ke resource AWS atau A record), nilai, dan TTL. Alias ke resource AWS (misalnya load balancer atau Elastic IP) harus diganti dengan A record ke IP VPS saat cutover.
11. Inventaris resource AWS yang akan dimatikan: instance EC2, volume EBS, snapshot, Elastic IP, load balancer, target group, web ACL WAF, dan NAT gateway. Cara melihatnya ada di bagian "Cara melihat instance EC2 dan isinya". Pastikan juga tidak ada project aktif lain di instance yang sama.
12. Catat konfigurasi n8n: versi image (`docker inspect n8n --format '{{.Config.Image}}'`, dan versi sebenarnya di UI), isi `n8n_data` (apakah `database.sqlite` atau database eksternal), apakah `N8N_ENCRYPTION_KEY` diatur lewat environment, daftar workflow aktif, dan layanan luar yang memanggil webhook n8n.

## Tahap 1: siapkan VPS

Spesifikasi acuan: VPS menjalankan nginx, n8n, dan delapan container PHP-FPM (`php_eduall`, `php_staging_eduall`, `php_assessment`, `php_assessment_staging`, `php_timesheet`, `php_timesheet_staging`, `php_helpdesk`, `php_asset`), tanpa Redis bila ternyata tidak dipakai. Ambil angka RAM dan CPU dari `docker stats` untuk container-container itu saja di Tahap 0, bukan dari seluruh stack. Sediakan sedikit ruang lebih dan swap. Pilih data center di Jakarta supaya jaraknya ke RDS di `ap-southeast-3` sependek mungkin.

```bash
# Sistem dasar (contoh Ubuntu/Debian)
sudo apt update && sudo apt upgrade -y
sudo apt install -y git ufw curl rsync

# Docker Engine dan plugin compose, ikuti panduan resmi untuk distro Anda
# https://docs.docker.com/engine/install/

# User non-root yang boleh menjalankan docker
sudo adduser deploy
sudo usermod -aG docker deploy

# Firewall: hanya SSH, HTTP, HTTPS
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Catatan firewall: Docker menulis aturan iptables sendiri dan melewati `ufw` untuk port yang dipublikasikan (`ports:` di compose). Port seperti 9001 sampai 9012, 6379, dan 5678 akan tetap terbuka walau `ufw` menutupnya. Ada dua cara menanganinya. Ubah pemetaan di compose menjadi `127.0.0.1:9001:9000`, atau hapus `ports:` untuk service yang tidak perlu diakses dari host (nginx sudah memanggil container lewat nama di jaringan Docker). Untuk Redis dan n8n, pastikan memang tidak perlu diakses dari luar. Lakukan perubahan ini sekaligus saat migrasi.

Atur zona waktu, karena n8n memakai `Asia/Jakarta` dan jadwal cron bergantung pada waktu server:

```bash
sudo timedatectl set-timezone Asia/Jakarta
```

## Tahap 2: bawa repo dan kode aplikasi

```bash
cd /home/deploy
git clone <url-repo-eduall-docker> eduall-docker
cd eduall-docker
```

Masalah yang tercatat di `docs/ARSITEKTUR.md` (folder `staging-crm` yang tidak ada, `cronfile` yang merujuk `/editing`) menyangkut project nonaktif. Selama VPS memakai compose khusus VPS (di bawah), keduanya tidak berpengaruh.

### Clone aplikasi

Clone repo delapan aplikasi PHP ke `src`, dengan branch yang sama seperti di AWS (hasil Tahap 0 nomor 4):

```bash
git clone -b <branch> <url-repo-eduall> eduall/src
git clone -b <branch> <url-repo-eduall> eduall-staging/src
git clone -b <branch> <url-repo-assessment> assessment/src
git clone -b <branch> <url-repo-assessment> assessment-staging/src
git clone -b <branch> <url-repo-helpdesk> helpdesk/src
git clone -b <branch> <url-repo-asset-management> asset-management/src
git clone -b <branch> <url-repo-timesheet> timesheet/src
git clone -b <branch> <url-repo-timesheet> timesheet-staging/src
```

n8n tidak punya repo aplikasi di sini. Ia memakai image resmi, dan datanya dibahas di bagian n8n di bawah. Folder project nonaktif (`crm`, `editing_v2`, `mentoring`, `authorization`, dan seterusnya) tidak perlu dibuat di VPS.

### Salin dan sesuaikan .env

```bash
for p in eduall eduall-staging assessment assessment-staging helpdesk asset-management timesheet timesheet-staging; do
  rsync -avz -e ssh \
    ubuntu@<ip-aws>:/path/ke/eduall-docker/$p/src/.env \
    /home/deploy/eduall-docker/$p/src/.env
done
```

Jangan menyalin mentah-mentah. Periksa tiap `.env`:

- `DB_HOST`: kalau berupa nama endpoint RDS (`xxx.ap-southeast-3.rds.amazonaws.com`), nama itu bisa dipakai dari VPS selama RDS dapat dijangkau (Tahap 3). Kalau berupa IP privat, harus diganti.
- Kredensial S3: kalau di AWS aplikasi memakai IAM role, buat IAM user khusus dengan izin seperlunya (hanya baca, tulis, dan hapus objek di bucket yang dipakai, tanpa izin lain), lalu isi `AWS_ACCESS_KEY_ID` dan `AWS_SECRET_ACCESS_KEY` di `.env` VPS. Jangan memakai kredensial admin.
- URL internal seperti `http://php_authorization:9000`, yang tidak bisa dijangkau dari VPS dan harus diganti dengan URL publik.
- `APP_URL` dan `APP_ENV` untuk staging dan production tetap sesuai domain masing-masing.
- Variabel lain yang mengikat ke AWS: SES, SQS, dan sejenisnya.

Karena file upload ada di S3, tidak ada file upload yang perlu disalin. Namun cek apakah ada file lokal yang penting, misalnya `storage/app` non-publik atau laporan yang digenerate:

```bash
du -sh eduall/src/storage/app assessment/src/storage/app helpdesk/src/storage/app asset-management/src/storage/app timesheet/src/storage/app 2>/dev/null
```

Kalau ada isinya yang tidak bisa dibuat ulang, salin dengan `rsync`.

### Compose dan konfigurasi khusus VPS

Jangan menyalin `docker-compose.yml` dan `default.conf` utuh. Buat file terpisah di repo ini supaya konfigurasi AWS tidak tersentuh:

- `docker-compose.vps.yml`: hanya service `php_eduall`, `php_staging_eduall`, `php_assessment`, `php_assessment_staging`, `php_timesheet`, `php_timesheet_staging`, `php_helpdesk`, `php_asset`, `n8n`, dan `nginx`. Mount `src` di nginx hanya untuk delapan project PHP itu, dan `depends_on` hanya untuk container yang dipakai. Buang service nonaktif. Tambahkan `redis` hanya bila Anda memutuskan memakainya (lihat bawah). Pindahkan password n8n dari `docker-compose.yml` ke file `.env`.
- `nginx/default.vps.conf`: sembilan server block (EDUALL, EDUALL STAGING, TIMESHEET, TIMESHEET STAGING, ASSESSMENT, ASSESSMENT STAGING, HELPDESK, ASSET MANAGEMENT, N8N), disalin dari `default.conf` lalu disesuaikan untuk TLS (Tahap 4). Blok-blok project nonaktif tidak dibawa. Mount-nya di compose VPS mengarah ke file ini.
- `nginx/cron/cronfile.vps`: `schedule:run` untuk `/eduall` dan `/timesheet`, sesuai `cronfile` AWS saat ini. Staging tidak ada di `cronfile` AWS, jadi ikuti itu kecuali Anda tahu staging butuh scheduler. Baris `queue.sh` tidak perlu, karena `queue.sh` hanya mengurus CRM dan editing.

Jalankan dengan:

```bash
docker compose -f docker-compose.vps.yml up -d
```

Pola ini membuat file AWS dan VPS hidup berdampingan di satu repo. Pastikan dua server tidak tertukar saat `git pull` atau `docker compose up`, misalnya dengan selalu menulis `-f` secara eksplisit di VPS.

### Redis di VPS

Menurut tim, belum ada yang bersinggungan dengan Redis. Cek di `.env` kedelapan aplikasi PHP: kalau `SESSION_DRIVER`, `CACHE_DRIVER` (atau `CACHE_STORE`), dan `QUEUE_CONNECTION` tidak bernilai `redis`, jangan jalankan Redis di VPS. Hapus service dan mount-nya dari compose VPS.

Periksa juga nilainya kalau berupa `database`: session atau cache yang disimpan di tabel database berarti setiap request membaca dan menulis ke RDS lewat jaringan, dan itu menambah latensi. Di satu VPS, `SESSION_DRIVER=file` dan `CACHE_DRIVER=file` sudah memadai dan mengurangi query ke RDS. Perubahan ini membuat pengguna login ulang sekali saat cutover. Kalau ternyata ada yang memakai `redis`, pakai Redis lokal di VPS, dan jangan buka port 6379 ke publik.

### n8n di VPS

n8n memakai image resmi `n8nio/n8n`, dan datanya ada di folder `n8n_data`. Compose AWS tidak mengatur database eksternal, jadi kemungkinan datanya di SQLite (`n8n_data/database.sqlite`). Pastikan dulu dengan melihat isi folder itu.

- Pin versi image di compose VPS ke versi yang sama dengan di AWS, jangan `latest`. Lompat versi saat pindah server menambah risiko migrasi data n8n.
- Kunci enkripsi (`N8N_ENCRYPTION_KEY`) menentukan apakah kredensial yang tersimpan bisa dibuka. Kalau tidak diatur lewat environment, n8n menyimpannya di `n8n_data/config`, dan ikut terbawa saat folder disalin. Kalau diatur lewat environment, nilainya harus sama di VPS.
- n8n yang aktif menjalankan trigger terjadwal dan menerima webhook. Kalau dua instance berjalan bersamaan dengan data yang sama, workflow bisa tereksekusi dua kali. Karena itu jangan jalankan n8n dengan data produksi di VPS sebelum cutover. Untuk uji, jalankan n8n kosong atau nonaktifkan semua workflow di salinan datanya.
- Pemindahan data dilakukan saat cutover n8n (Tahap 6): hentikan n8n di AWS, salin `n8n_data`, jalankan di VPS, lalu ubah DNS.
- Variabel `N8N_HOST`, `WEBHOOK_URL`, dan `N8N_EDITOR_BASE_URL` tetap memakai `workflow.edu-all.com`, jadi webhook yang sudah didaftarkan di layanan luar tidak perlu diubah.
- Ganti password basic auth n8n yang tertulis di compose.

## Tahap 3: koneksi ke database di AWS

Database tidak ikut dipindah. Aplikasi di VPS akan terhubung ke RDS di AWS lewat internet. Tidak ada data database yang perlu disalin, tetapi tiga hal harus beres: koneksinya aman, latensinya tertahankan, dan versi kode di dua server sama selama masa tumpang tindih.

### Pilih cara terhubung

| Cara | Kelebihan | Kekurangan |
|---|---|---|
| A. Buka port 3306 hanya untuk IP VPS (security group) dan wajibkan TLS | Paling sederhana | Database harus bisa dijangkau dari internet (untuk RDS: publicly accessible). Keamanan bergantung pada allowlist IP dan password |
| B. VPN WireGuard antara VPS dan VPC AWS | Database tetap privat, tidak terpapar internet | Butuh gateway di dalam VPC. EC2 yang sekarang akan dimatikan, jadi gateway ini berarti instance kecil tambahan (ada biayanya) atau Site-to-Site VPN (biaya per jam, cek halaman harga). Mengurangi sebagian penghematan |
| C. SSH tunnel | Cepat dibuat untuk uji coba | Rapuh untuk produksi (tunnel putus, tidak otomatis pulih) |

Saran saya: cara A (publicly accessible, security group hanya mengizinkan IP VPS, TLS wajib), karena EC2 akan dimatikan dan biaya gateway VPN mengurangi penghematan. Cara B hanya bila kebijakan keamanan mengharuskan database tidak boleh terpapar internet. Cara C hanya untuk uji coba. Catat bahwa RDS yang publicly accessible memakai satu alamat public IPv4 yang ditagih per jam (sekitar USD 3-4 per bulan menurut tarif umum, cek halaman harga). Apa pun pilihannya:

- Jangan buka 3306 ke `0.0.0.0/0`.
- Gunakan TLS untuk koneksi database. Di RDS, aktifkan `require_secure_transport` lewat parameter group. Di Laravel, arahkan opsi `PDO::MYSQL_ATTR_SSL_CA` ke sertifikat CA di `config/database.php`. Untuk cara B (di dalam VPN) tetap disarankan memakai TLS.
- Buat user database khusus untuk tiap aplikasi dengan hak seperlunya, dan batasi host-nya ke IP VPS (atau IP VPN).
- Daftarkan IP VPS yang tetap di security group database. Pastikan IP VPS tidak berubah.

### Ukur latensi sebelum memutuskan

Jalankan dari VPS ke database:

```bash
# round trip jaringan
ping -c 20 <host-database>

# waktu query sederhana, diulang
time (for i in $(seq 1 100); do mysql -h <host-database> -u <user> -p'<password>' -e 'SELECT 1' >/dev/null; done)
```

Hasil `time` di atas ikut menghitung waktu koneksi, jadi bacalah sebagai batas atas. Aturan kasar: satu halaman Laravel sering menjalankan 20 sampai 100 query. Latensi 1 ms per query hampir tidak terasa. Latensi 20 ms per query berarti 0,4 sampai 2 detik tambahan per halaman, dan lebih buruk lagi bila koneksi baru dengan TLS dibuka pada setiap request. RDS ada di `ap-southeast-3` (Jakarta), jadi pilih VPS di data center Jakarta. Latensi bergantung pada penyedia dan peering jaringannya, jadi ukur dulu dari VPS sebelum berlangganan jangka panjang (banyak penyedia menawarkan trial atau tagihan bulanan).

### Kurangi dampak latensi

- Cache lebih banyak ke Redis lokal di VPS (hasil query yang sering dibaca, konfigurasi, dan session).
- Perbaiki query N+1 di halaman yang paling sering diakses (`with()` di Eloquent).
- Pertimbangkan koneksi persisten (`PDO::ATTR_PERSISTENT`) untuk menghemat handshake TLS pada tiap request. Ini menambah jumlah koneksi terbuka ke database, jadi cek `max_connections` dan uji dulu.
- Pantau transfer data keluar dari AWS. Hasil query besar yang mengalir dari RDS ke VPS, dan file S3 yang diunduh lewat VPS, dihitung sebagai data transfer out dan bisa memakan penghematan yang Anda cari. Lihat bagian "Periksa biaya sebelum mulai".

### Hal lain yang perlu dijaga

- Selama aplikasi berjalan di dua tempat (masa uji dan cutover), kode di AWS dan VPS harus berada di branch dan commit yang sama. Jalankan `php artisan migrate` hanya dari satu tempat, dan hanya dengan kode yang sudah disepakati.
- `max_connections` database harus cukup untuk dua server yang aktif bersamaan.
- Staging: tentukan apakah database staging di instance RDS terpisah atau satu instance dengan production. Kalau terpisah dan harganya signifikan, memindahkan database staging ke MySQL di VPS adalah penghematan berisiko rendah. Kalau satu instance dengan production, jangan biarkan staging VPS memakai kredensial yang bisa menyentuh data production.
- Kalau VPS atau koneksi ke AWS terputus, aplikasi yang sudah pindah ikut mati. Pertimbangkan halaman maintenance dan monitoring dari awal (lihat bagian optimasi).
- Kalau hasil ukur menunjukkan latensi tidak bisa diterima, jalur cadangannya adalah memindahkan databasenya juga (lihat di bawah).

### Jika nanti database ikut dipindah

Bagian ini berlaku bila hasil pemeriksaan biaya menunjukkan RDS sebagai komponen terbesar, bila latensi tidak bisa diterima, atau bila Anda hanya memindahkan database staging. Untuk RDS, ambil dump dengan `mysqldump` seperti di bawah, dan buat snapshot RDS final sebelum menghapus atau memperkecil instance. Ingat bahwa project yang tetap di AWS (CRM, editing, mentoring, authorization) mungkin memakai instance RDS yang sama.

```bash
# dump dari sumber
mysqldump -h <host-lama> -u <user> -p --single-transaction --routines --triggers <nama_db> > nama_db.sql

# restore di tujuan
mysql -h <host-baru> -u <user> -p <nama_db> < nama_db.sql
```

Untuk database yang aktif menerima tulis, rencanakan jendela waktu dan dump final setelah aplikasi dimatikan atau dibuat read-only. Ubah `DB_HOST` di semua `.env`. Ingat juga bahwa RDS mungkin memuat database project nonaktif (CRM, editing, dan sebagainya). Pastikan siapa saja yang masih memakai tiap database sebelum memindahkan atau menghapusnya.

## Tahap 4: TLS di VPS

Di AWS, sertifikat selesai sebelum nginx. Di VPS, pilih salah satu.

Semua domain yang pindah berupa subdomain satu tingkat dari `edu-all.com` (kecuali `edu-all.com` sendiri), dan DNS-nya ada di Route 53. Itu memungkinkan sertifikat wildcard `*.edu-all.com` plus `edu-all.com` dengan validasi DNS-01 lewat plugin Certbot untuk Route 53. Keuntungannya: sertifikat bisa diterbitkan sebelum cutover (HTTP-01 butuh domain sudah mengarah ke VPS), dan pembaruan berjalan otomatis. Sertifikat dari AWS Certificate Manager tidak bisa diekspor, jadi sertifikat di VPS harus diterbitkan sendiri. Sertifikat di AWS tidak perlu diubah selama EC2 dan load balancer masih menyala.

### Opsi A: proxy di depan nginx (perubahan konfigurasi paling kecil)

Pasang reverse proxy yang mengurus TLS, misalnya Caddy di host, atau pakai Cloudflare dengan mode proxy. Mode proxy Cloudflare mengharuskan zona DNS dikelola di Cloudflare. Karena semua domain aktif pindah ke VPS, memindahkan zona dari Route 53 menjadi layak, tetapi semua record tetap harus dipindah dengan teliti (termasuk MX dan TXT bila dipakai untuk email, dan record project nonaktif yang perlu dibersihkan). Route 53 hanya sekitar USD 1 per bulan, jadi tidak ada urgensi memindahkannya. Cloudflare di depan juga bisa menggantikan sebagian fungsi WAF AWS. Proxy meneruskan ke nginx lewat HTTP dan mengirim header `X-Forwarded-Proto: https`. `default.conf` tidak perlu diubah, karena pola `fastcgi_param HTTPS $http_x_forwarded_proto` sudah menyesuaikan.

Kalau proxy berjalan di host yang sama, port 80 nginx tidak boleh bentrok dengannya. Ubah pemetaan nginx di compose menjadi `"127.0.0.1:8080:80"` dan arahkan proxy ke port itu. Hapus pemetaan `443:443` bila tidak dipakai.

### Opsi B: TLS langsung di nginx dengan Let's Encrypt

1. Terbitkan sertifikat dengan validasi DNS lewat Route 53. Pasang plugin dan buat IAM user khusus untuk Certbot dengan izin terbatas (`route53:ListHostedZones`, `route53:GetChange`, dan `route53:ChangeResourceRecordSets` pada hosted zone `edu-all.com` saja):

   ```bash
   sudo apt install -y certbot python3-certbot-dns-route53
   # kredensial IAM khusus certbot di ~/.aws/credentials milik root, izin file 600
   sudo certbot certonly --dns-route53 -d 'edu-all.com' -d '*.edu-all.com'
   ```

   Plugin ini juga dipakai saat pembaruan otomatis. Simpan kredensialnya terpisah dari kredensial aplikasi dan jangan beri izin selain yang disebut di atas.

2. Mount sertifikat ke container nginx. Ganti mount lama di `docker-compose.yml`:

   ```yaml
   - /etc/letsencrypt:/etc/letsencrypt:ro
   ```

3. Ubah setiap server block di `default.conf`. Pola: satu blok port 80 untuk redirect, satu blok 443 untuk aplikasi. Pakai `include` supaya pengaturan SSL tidak diulang di tiap blok.

   ```nginx
   server {
       listen 80;
       server_name payroll.edu-all.com;
       return 301 https://$host$request_uri;
   }

   server {
       listen 443 ssl;
       server_name payroll.edu-all.com;

       ssl_certificate     /etc/letsencrypt/live/edu-all.com/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/edu-all.com/privkey.pem;

       # ... isi blok seperti sebelumnya
   }
   ```

4. Ganti dua baris ini di setiap blok PHP, karena `X-Forwarded-Proto` tidak ada lagi:

   ```nginx
   fastcgi_param HTTPS on;
   fastcgi_param HTTP_X_FORWARDED_PROTO https;
   ```

   Nginx bisa ditulis `$scheme` untuk `HTTP_X_FORWARDED_PROTO` bila lebih suka.

5. Atur pembaruan otomatis (cron atau `certbot.timer`) dan reload nginx sesudahnya:

   ```bash
   sudo certbot renew --deploy-hook "docker exec nginx nginx -s reload"
   ```

Catatan `nginx.conf` yang sekarang: `ssl_stapling on` dan `resolver` sudah ada, jadi konfigurasi global TLS sudah siap. `nginx/editing.conf` dan `security.conf` bisa dijadikan acuan, tetapi `security.conf` memuat `listen 443 quic` dan `ssl_protocols TLSv1.3` yang harus dites dulu sebelum dipakai.

## Tahap 5: build dan uji di VPS sebelum cutover

Jalankan stack di VPS saat DNS masih mengarah ke AWS:

```bash
docker compose build
docker compose up -d
docker compose ps
```

Install dependency di setiap project PHP (`composer install --no-dev --optimize-autoloader`), dan atur izin `storage` serta `bootstrap/cache`. Lalu uji setiap domain tanpa mengubah DNS publik, dengan menembak IP VPS langsung:

```bash
curl -i --resolve timesheet.edu-all.com:443:<ip-vps> https://timesheet.edu-all.com/health
curl -i -H 'Host: timesheet.edu-all.com' http://<ip-vps>/health      # untuk opsi A atau uji internal
```

Atau tambahkan entri `/etc/hosts` di komputer Anda yang mengarahkan domain ke IP VPS, lalu buka lewat browser dan uji alur penting: login lewat `auth.edu-all.com`, upload file, kirim email, dan antrean.

Pastikan scheduler dan queue jalan:

```bash
docker compose exec nginx pgrep -af 'queue:work'
docker compose exec nginx tail -n 20 /var/log/cronjob.log
```

Jangan biarkan dua server menjalankan scheduler untuk database yang sama pada waktu yang sama, karena job terjadwal bisa terproses dua kali (email terkirim ganda, misalnya). Untuk aplikasi yang pindah hanya scheduler yang relevan: `cronfile` AWS menjalankan `schedule:run` untuk eduall dan timesheet, sedangkan `queue.sh` tidak punya worker untuk satu pun dari mereka. Selama masa uji, biarkan `cronfile.vps` kosong atau seluruh barisnya dikomentari, lalu aktifkan per aplikasi saat cutover (Tahap 6).

Karena database dipakai bersama, uji dengan hati-hati: login, upload, dan alur lain di VPS menulis ke database yang sama dengan yang dipakai pengguna sungguhan. Gunakan akun uji, dan hindari aksi yang mengirim email atau notifikasi ke pengguna asli.

## Tahap 6: cutover per domain

Karena database (RDS) dan file upload (S3) dipakai bersama, aplikasi di AWS dan di VPS bisa berjalan bersamaan dengan data yang sama. Cutover cukup lewat Route 53, satu domain demi satu domain.

Urutan yang disarankan:

1. Staging dulu: `staging-timesheet.edu-all.com`, `staging-assessment.edu-all.com`, lalu `staging.edu-all.com`. Anggap ini gladi resik untuk seluruh prosedur (TLS, DNS, scheduler, pemantauan, rollback).
2. Production dengan risiko paling kecil: `helpdesk.edu-all.com`, `asset.edu-all.com`, dan `timesheet.edu-all.com`.
3. `assessment.edu-all.com`.
4. `workflow.edu-all.com` (n8n), dengan langkah khusus di bawah.
5. `edu-all.com` terakhir, karena itu aplikasi utama.

Persiapan umum:

1. Turunkan TTL record di Route 53 ke nilai kecil (misalnya 60 sampai 300 detik) minimal 24 jam sebelumnya. TTL yang lama menahan perpindahan dan rollback.
2. Pastikan versi kode di AWS dan VPS sama (branch dan commit).
3. Pastikan sertifikat TLS di VPS sudah siap untuk domain itu (Tahap 4).
4. Pastikan VPS bisa mengakses RDS dan S3 (Tahap 2 dan 3), dengan uji aksi nyata: login, baca dan tulis data, upload dan unduh file.
5. Umumkan jendela perawatan singkat bila aplikasi dipakai aktif.

Langkah untuk setiap domain aplikasi PHP:

1. Pindahkan scheduler: hapus baris `schedule:run` aplikasi itu dari `nginx/cron/cronfile` di AWS, lalu restart container nginx di AWS (di jam sepi, karena restart ini menyentuh semua domain yang masih di AWS). Aktifkan baris yang sama di `cronfile.vps`. Jangan sampai scheduler berjalan di dua tempat, karena job terjadwal bisa terproses dua kali (email ganda, laporan ganda).
2. Di Route 53, ubah record domain itu. Kalau recordnya alias ke resource AWS, ganti dengan A record ke IP VPS.
3. Pantau:

   ```bash
   docker compose -f docker-compose.vps.yml logs -f nginx
   tail -f nginx/logs/error.log
   ```

   Cek juga log aplikasi di `storage/logs`, dan pastikan koneksi RDS serta S3 stabil.
4. Setelah TTL lama berlalu, pastikan traffic di AWS untuk domain itu sudah hampir nol (lihat `nginx/logs/access.log` di AWS).

Karena file upload ada di S3, tidak ada file yang perlu disinkronkan antar server, dan mode maintenance tidak wajib.

### Langkah khusus n8n

n8n menyimpan data di folder lokal, bukan di database bersama, dan menjalankan trigger terjadwal. Prosedurnya:

1. Umumkan jendela perawatan singkat. Workflow yang sedang berjalan atau webhook yang masuk selama jendela ini bisa terlewat.
2. Di AWS: hentikan n8n (`docker compose stop n8n`) supaya tidak ada eksekusi baru dan datanya konsisten.
3. Salin `n8n_data` ke VPS:

   ```bash
   rsync -avz ubuntu@<ip-aws>:/path/ke/eduall-docker/n8n_data/ ./n8n_data/
   ```

4. Di VPS: jalankan n8n dengan versi image yang sama (Tahap 2), lalu cek bahwa login, kredensial, dan daftar workflow muncul, dan jalankan satu workflow uji.
5. Ubah record `workflow.edu-all.com` di Route 53 ke IP VPS. Webhook yang diarahkan ke domain ini otomatis menuju VPS setelah DNS menyebar.
6. Pantau eksekusi workflow dan pastikan trigger terjadwal berjalan satu kali, bukan dua kali.

Jangan menyalakan n8n di AWS lagi setelah langkah 5, kecuali untuk rollback.

### Alternatif cutover bertahap

Weighted routing di Route 53: buat dua record dengan nama sama, satu menuju AWS dan satu menuju VPS, dengan bobot misalnya 90 dan 10, lalu naikkan bertahap. Cara ini hanya aman bila session tidak disimpan di file lokal masing-masing server. Kalau `SESSION_DRIVER` berupa `file`, pengguna yang berpindah server akan kehilangan session dan bisa terlempar ke halaman login berulang. Kalau session ada di database bersama, atau Anda menerima login ulang sekali, weighted routing layak dipakai. Cara ini tidak cocok untuk n8n.

Satu catatan soal session untuk cutover biasa: kalau session disimpan di file lokal atau Redis di server, pengguna akan logout sekali saat pindah. Beri tahu pengguna sebelumnya.

## Rollback

Selama EC2 di AWS masih menyala, rollback ringan karena database dan S3 tidak berpindah: kembalikan record Route 53 ke nilai semula (sudah dicatat di Tahap 0 nomor 10), pindahkan scheduler kembali ke AWS (aktifkan lagi baris `schedule:run` di AWS dan nonaktifkan di VPS), dan pastikan versi kode tidak tertinggal dari migrasi database yang sudah dijalankan. Untuk n8n, hentikan n8n di VPS, salin `n8n_data` kembali ke AWS (bila ada perubahan), dan nyalakan n8n di AWS.

Karena itu, selama masa stabilisasi (saran: minimal dua minggu), biarkan container aplikasi di AWS tetap ada tetapi tanpa scheduler dan tanpa traffic. Setelah EC2 dimatikan, rollback ke AWS tidak lagi tersedia, kecuali Anda memulihkan dari snapshot.

## Mematikan resource AWS

Lakukan setelah masa stabilisasi berakhir dan Anda yakin tidak ada project atau server lain yang bergantung pada resource yang dimatikan. Tujuannya mewujudkan penghematan, jadi bagian ini sama pentingnya dengan cutover.

1. Konfirmasi tidak ada traffic tersisa ke EC2 dan load balancer (cek metrik `RequestCount` dan access log).
2. Buat cadangan terakhir: AMI atau snapshot EBS dari instance, dan simpan sekitar satu bulan sebelum dihapus.
3. Arsipkan lalu bersihkan database project nonaktif di RDS. Ambil `mysqldump` untuk database crm, editing, mentoring, authorization, dan lainnya yang tidak dipakai lagi, simpan di S3 (kelas penyimpanan arsip bila perlu), lalu hapus dari RDS. Ini mengecilkan storage dan bisa membuka peluang memperkecil instance RDS.
4. Hapus atau hentikan resource yang ditagih: terminate instance EC2, hapus volume EBS dan snapshot yang tidak lagi dibutuhkan, lepaskan Elastic IP, hapus load balancer dan target group, hapus web ACL WAF, dan hapus NAT gateway bila ada.
5. Bersihkan Route 53: hapus record domain project nonaktif supaya tidak ada record menggantung (dangling record bisa disalahgunakan), dan pertahankan hosted zone.
6. Pasang AWS Budgets dengan peringatan di angka yang masuk akal (misalnya sedikit di atas perkiraan skenario B), supaya tagihan yang naik kembali langsung ketahuan.
7. Bandingkan tagihan bulan berikutnya dengan perhitungan awal, lalu perbarui dokumen ini bila hasilnya berbeda.

## Optimasi yang disarankan

Migrasi adalah saat yang tepat untuk membenahi beberapa hal, tetapi jangan mengubah semuanya sekaligus. Jika terjadi masalah setelah cutover, Anda perlu tahu apakah penyebabnya pindah server atau perubahan konfigurasi. Daftar di bawah dibagi menjadi tiga kelompok menurut waktu pengerjaannya. Beberapa temuan berasal dari membaca repo dan belum diuji di server Anda, jadi ukur dampaknya sebelum dan sesudah.

### Kelompok 1: sebelum atau saat migrasi

Perubahannya kecil, dan sebagian besar menyangkut keamanan atau ketahanan server.

- Restart policy. Hanya Redis yang punya `restart: unless-stopped`. Container PHP dan nginx tidak, jadi kalau VPS reboot atau Docker restart, sebagian besar stack tetap mati. Tambahkan ke semua service:

  ```yaml
  restart: unless-stopped
  ```

- Batasi port yang dipetakan. Docker melewati `ufw`, jadi `ports: "9001:9000"` membuka PHP-FPM ke internet. Nginx memanggil container lewat nama di `app-network`, jadi port itu tidak dibutuhkan dari luar. Ubah menjadi `127.0.0.1:9001:9000` atau hapus. Hal yang sama berlaku untuk Redis (6379) dan n8n (5678). Redis tanpa password yang terbuka ke publik adalah celah yang umum dieksploitasi. Hanya nginx yang perlu `80:80` (dan `443:443` bila TLS dipasang di nginx).
- Rotasi log Docker. Tanpa batas, log container memenuhi disk. Tambahkan per service, atau atur global di `/etc/docker/daemon.json`:

  ```yaml
  logging:
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"
  ```

  Log nginx di `nginx/logs` ditulis ke file di host, jadi pasang juga `logrotate` untuk folder itu.
- Pindahkan secret ke `.env`. Password n8n dan Elasticsearch yang tertulis di `docker-compose.yml` dan `logstash.conf` sebaiknya diganti, bukan hanya dipindahkan, karena sudah ada di riwayat Git. Rujuk dengan `${NAMA_VARIABEL}` di compose dan tambahkan `.env` ke `.gitignore`.
- Jaga jarak ke database. Database tetap di AWS, jadi setiap query dari VPS melewati jaringan. Ini sudah dibahas di Tahap 3. Dalam optimasi, artinya: pilih lokasi VPS sedekat mungkin dengan region database, ukur latensinya sebelum cutover, dan prioritaskan cache serta perbaikan query N+1 pada halaman yang paling sering dibuka.
- Pilih lokasi VPS yang dekat dengan database sekaligus dekat dengan pengguna. Kalau keduanya berbeda arah, jarak ke database biasanya lebih menentukan, karena satu halaman bisa memicu puluhan query.

### Kelompok 2: optimasi di repo ini

Bisa dikerjakan saat migrasi atau setelah stack stabil, satu per satu.

- Aktifkan OPcache. `docker-fpm.ini` tidak mengatur OPcache, dan di image `php:8.2-fpm-alpine` ekstensi ini tidak aktif secara default. Biasanya ini peningkatan performa PHP terbesar yang paling murah. Tambahkan `opcache` ke `docker-php-ext-install` di Dockerfile, lalu tambahkan ke `docker-fpm.ini`:

  ```ini
  opcache.enable=1
  opcache.memory_consumption=128
  opcache.max_accelerated_files=20000
  opcache.validate_timestamps=1
  opcache.revalidate_freq=2
  ```

  Karena `src` diperbarui lewat `git pull`, biarkan `validate_timestamps=1` supaya perubahan kode terbaca. Kalau Anda mematikannya demi performa, restart container PHP setiap selesai deploy.
- Atur pool PHP-FPM per project. Semua container memakai konfigurasi bawaan image, termasuk `pm.max_children = 5`. Project sibuk seperti `eduall` atau `timesheet` bisa kehabisan worker, sedangkan project yang jarang dipakai menyimpan memori yang tidak perlu. Tentukan `pm.max_children` dari memori rata-rata per proses PHP (cek lewat `docker stats` dan `ps`), lalu mount file pool sendiri (misalnya `zz-pool.conf` ke `/usr/local/etc/php-fpm.d/`).
- Turunkan timeout. `fastcgi_read_timeout 14400` (4 jam) dan `max_execution_time = 3000` membuat satu request macet menahan satu worker FPM berjam-jam. Pindahkan pekerjaan panjang (import, laporan besar) ke queue, lalu turunkan timeout web ke 60 sampai 300 detik. Cek dulu endpoint mana yang memang butuh waktu lama, supaya tidak memutus proses yang sah.
- Perkecil image PHP dan nginx. Setiap Dockerfile PHP memasang `nodejs` dan `npm`, padahal frontend dibuild di lokal. Hapus dari image runtime kecuali ada project yang benar-benar memanggil Node di server. Image nginx juga memasang `php-fpm`, `nodejs`, dan `npm` yang kemungkinan tidak dipakai (nginx hanya butuh `php-cli` untuk menjalankan `artisan`). Image lebih kecil membuat build lebih cepat dan permukaan serangan lebih sempit.
- Kurangi duplikasi Dockerfile. Dua belas Dockerfile hampir identik. Satu base image bersama, dengan `ARG` untuk ekstensi dan nama path, berarti menaikkan versi PHP cukup mengubah satu tempat.
- Hapus `chmod -R 777 storage/`. Pakai pemilik `www-data` dengan izin `775`.
- Rapikan Redis, kalau memang dipakai (kalau tidak, jangan jalankan containernya). Masukkan ke `app-network`, pin versi image (jangan `latest`), dan atur `maxmemory` beserta `maxmemory-policy` yang sesuai. Aplikasi sebaiknya memakai host `redis`, bukan port host.
- Pasang batas sumber daya. Atur `mem_limit` per container supaya satu aplikasi yang bocor memori tidak mematikan seluruh VPS. Nilainya diambil dari hasil `docker stats` di Tahap 0.
- Aktifkan konfigurasi yang sudah ada. Dari yang terbaca di repo, `default.conf` tidak meng-`include` `general.conf` maupun `security.conf`, padahal keduanya di-mount ke container. Artinya aturan cache aset dan header keamanan di dua file itu kemungkinan tidak aktif. Periksa apakah itu disengaja, lalu aktifkan lewat `include` di blok yang relevan. Brotli sudah terpasang di image nginx tetapi belum diaktifkan di `nginx.conf`.
- Perketat header keamanan bertahap. CSP di `default.conf` dan `security.conf` memakai `'unsafe-inline' 'unsafe-eval'` dan sumber `https:` yang luas, sehingga perlindungannya terbatas. Perketat per aplikasi bila memungkinkan, dan uji dulu di staging.

### Kelompok 3: arsitektur, setelah migrasi stabil

Jangan digabung dengan cutover.

- Pisahkan queue worker dan scheduler dari container nginx. Untuk project yang dimigrasikan, hanya scheduler yang berjalan (tidak ada worker di `queue.sh`), jadi prioritasnya lebih rendah di VPS. Worker di `queue.sh` hanya ada untuk CRM dan editing, yang sudah tidak aktif, jadi pola itu tidak perlu dibawa ke VPS. Bila nanti ada aplikasi yang butuh worker, saran berikut berlaku. Sebelumnya worker dijalankan watchdog `queue.sh` berbasis `pgrep` di dalam nginx. Pola ini rapuh: kalau nginx restart, worker ikut mati, dan worker berbagi sumber daya dengan web server. Lebih baik satu container per worker memakai image PHP project itu, dengan `restart: unless-stopped`, misalnya:

  ```yaml
  worker_app:
    build:
      context: ./<project>
    container_name: worker_app
    command: php artisan queue:work --queue=default,mail
    working_dir: /<project>
    volumes:
      - ./<project>/src:/<project>
    networks:
      - app-network
    restart: unless-stopped
  ```

  Scheduler dipisah dengan cara yang sama memakai `php artisan schedule:work`. Setelah itu nginx tidak lagi butuh `cron`, `php-cli`, dan mount `src` untuk kebutuhan `artisan`.
- Tinjau staging. Tiga container staging (eduall, timesheet, assessment) ikut pindah ke VPS dan memakan RAM 24 jam. Pertimbangkan Compose profile supaya hanya dinyalakan saat dibutuhkan, dan database staging di MySQL pada VPS (Tahap 3) bila sebelumnya memakai instance RDS sendiri.
- Otomatisasi deploy. Saat ini deploy berarti SSH lalu `git pull` manual. Workflow GitHub Actions yang SSH ke server dan menjalankan skrip deploy (pull, composer, migrate, cache, restart worker) mengurangi kesalahan manusia dan meninggalkan riwayat deploy.

### Optimasi infrastruktur

- CDN dan proxy. Cloudflare di depan (Opsi A di Tahap 4) memberi TLS, cache aset statis, dan perlindungan DDoS dasar, dengan perubahan nginx yang hampir tidak ada. Kalau IP asli server perlu dilindungi, batasi port 80 dan 443 hanya untuk rentang IP Cloudflare.
- Biaya data transfer S3. Setelah aplikasi pindah, file yang diunduh lewat VPS dihitung sebagai data transfer out. Kalau volumenya besar, pertimbangkan CDN di depan S3, menyajikan file langsung dari S3 lewat presigned URL, atau memindahkan file ke penyimpanan objek yang tidak mengenakan biaya egress. Putuskan setelah Anda tahu volumenya dari Cost Explorer.
- Monitoring. Konfigurasi Loki, Promtail, dan Logstash ada di repo tetapi tidak berjalan. Mulai dari yang ringan: uptime monitor eksternal (misalnya Uptime Kuma) untuk semua domain, ditambah alert untuk disk, RAM, dan container yang mati. Aktifkan stack log hanya bila memang akan dipakai, karena Elasticsearch dan Loki sendiri membutuhkan banyak RAM.
- Backup di luar server. Backup yang disimpan di VPS yang sama tidak berguna bila VPS hilang. Simpan di object storage atau server lain, dan uji restore. Untuk database, tambahkan dump terjadwal, atau binlog bila butuh pemulihan ke titik waktu tertentu.
- Hardening host. SSH hanya dengan key, nonaktifkan login root dan password, pasang `fail2ban` dan `unattended-upgrades`. Snapshot VPS dari penyedia bisa jadi lapisan tambahan.
- Ukuran VPS. Jalankan `docker stats` di AWS selama beberapa hari (termasuk jam sibuk dan saat batch atau import berjalan), lalu pilih spesifikasi dari angka puncak, bukan rata-rata. RAM yang pas-pasan memicu OOM kill pada container PHP.
- Reproduksibilitas. Catat langkah provisioning VPS dalam skrip atau Ansible. Saat server perlu dibangun ulang, Anda tidak bergantung pada ingatan, dan itu sekaligus menjadi rencana pemulihan bencana.

### Urutan yang disarankan

1. Sebelum cutover: restart policy, pembatasan port, rotasi log, secret, OPcache, dan keputusan lokasi database.
2. Saat cutover: ubah sesedikit mungkin selain yang wajib (TLS, DNS, data).
3. Sekitar dua minggu sesudahnya, bila stabil: tuning FPM, timeout, perkecil image, pisahkan worker, otomatisasi deploy, dan monitoring.

## Setelah migrasi

- Naikkan TTL DNS ke nilai normal.
- Pasang backup terjadwal (lihat `docs/OPERASIONAL.md`).
- Rotasi password dan kunci yang tersimpan sebagai teks biasa di repo (n8n dan Elasticsearch di `docker-compose.yml` dan `logstash.conf`). Pindahkan ke `.env` yang tidak masuk Git.
- Batasi akses SSH (hanya key, nonaktifkan login root dan password).
- Perbarui `README.md` dan dokumen di `docs/` agar menjelaskan kondisi baru: semua project aktif di VPS, RDS, S3, dan Route 53 di AWS. Tandai project nonaktif di `docker-compose.yml` atau hapus dari repo.
- Matikan resource AWS mengikuti bagian "Mematikan resource AWS", lalu bandingkan tagihan dengan perhitungan awal.

## Checklist ringkas

- [ ] Komponen AWS untuk sertifikat dan traffic sudah dicatat
- [ ] Rincian tagihan AWS sudah diperiksa dan penghematan bersih sudah dihitung
- [ ] Detail RDS sudah dicatat (kelas instance, Multi-AZ, security group, apakah staging satu instance dengan production)
- [ ] Cara koneksi ke database sudah dipilih (allowlist IP dengan TLS, atau VPN) dan diuji
- [ ] Latensi VPS ke database sudah diukur dan bisa diterima
- [ ] Ketergantungan aplikasi yang pindah pada Redis, SSO, dan layanan AWS lain sudah diperiksa
- [ ] `docker-compose.vps.yml`, `default.vps.conf`, dan `cronfile.vps` sudah dibuat
- [ ] Scheduler tidak aktif di dua tempat untuk aplikasi yang sama
- [ ] n8n: versi image, `N8N_ENCRYPTION_KEY`, dan isi `n8n_data` sudah dicatat, dan workflow tidak berjalan di dua tempat
- [ ] Inventaris EC2, EBS, ELB, WAF, dan Elastic IP sudah dibuat, dan tidak ada server lain yang bergantung padanya
- [ ] Database project nonaktif sudah diarsipkan, resource AWS sudah dimatikan, dan AWS Budgets sudah dipasang
- [ ] Semua `.env` sudah disalin dan disesuaikan, dan akses S3 dari VPS (IAM user, bukan instance role) sudah diuji
- [ ] Record Route 53 sembilan domain sudah dicatat (jenis, nilai, TTL), dan TTL sudah diturunkan
- [ ] Daftar branch tiap project sudah dicatat
- [ ] VPS siap: Docker, user deploy, firewall, timezone
- [ ] Pemetaan port compose sudah dibatasi ke `127.0.0.1` atau dihapus
- [ ] `restart: unless-stopped` dan rotasi log sudah dipasang di semua service
- [ ] OPcache aktif dan pool FPM sudah disetel (bisa menyusul setelah stabil)
- [ ] Keputusan TLS (opsi A atau B) sudah dibuat dan diuji
- [ ] Stack berjalan di VPS dan semua domain lolos uji `/health`
- [ ] IP VPS sudah didaftarkan di layanan pihak ketiga yang memakai whitelist
- [ ] TTL DNS sudah diturunkan
- [ ] Rencana rollback dan batas waktunya sudah disepakati
- [ ] Backup terjadwal di VPS aktif
