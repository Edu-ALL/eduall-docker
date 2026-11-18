# Dokumentasi eduall-docker

Dokumen di folder ini menjelaskan repo infrastruktur Docker untuk aplikasi EduALL. Semuanya berbahasa Indonesia.

| Dokumen | Isi |
|---|---|
| [ARSITEKTUR.md](ARSITEKTUR.md) | Struktur repo, service, alur request, routing domain, cron dan queue, serta catatan masalah yang ditemukan |
| [MEMBUAT-PROJECT-BARU.md](MEMBUAT-PROJECT-BARU.md) | Langkah menambah aplikasi PHP, frontend statis, atau staging baru |
| [OPERASIONAL.md](OPERASIONAL.md) | Update aplikasi, perintah harian, pemecahan masalah, backup, dan keamanan dasar |
| [MIGRASI-KE-VPS.md](MIGRASI-KE-VPS.md) | Rencana memindahkan semua project aktif (eduall, assessment, timesheet dan staging-nya, helpdesk, asset-management, n8n) dari AWS ke VPS, dengan RDS, S3, dan Route 53 tetap di AWS. Isinya analisis tagihan, TLS dengan Route 53, cutover per domain, rollback, dan mematikan resource AWS |

Urutan baca yang disarankan untuk orang baru: arsitektur, operasional, lalu membuat project baru. Dokumen migrasi dibaca saat rencana pindah server mulai dijalankan.

Kode aplikasi tidak ada di repo ini. Setiap project punya repository sendiri yang di-clone ke `<project>/src`.
