# Setup & UAT — Gen-Z News Content Factory

Gunakan project baru agar data dan biaya tidak bercampur dengan Orbiz Operator Management. Jangan commit `.env`, service role key, atau OpenAI API key. Repo saat pemeriksaan awal bersifat public.

## 1. Preview dashboard di akun Netlify sendiri

1. Import existing project → GitHub → `imnaulsa/Gen-Z-News-Content-Factory`.
2. Pilih branch `feature/content-factory-v1` untuk situs testing terpisah. Jangan gunakan `main` dahulu karena hanya berisi bootstrap README.
3. Build command `npm run build`; publish directory `dist`; Node 22. `netlify.toml` sudah mengaturnya.
4. Deploy pertama boleh tanpa environment: demo workspace bisa dilihat, semua aksi produksi berhenti dengan pemberitahuan koneksi belum tersedia.
5. Setelah UAT dan merge, arahkan production branch ke `main`; aktifkan Deploy Previews untuk PR berikutnya.

## 2. Supabase

1. Buat project baru bernama `gen-z-news-content-factory`. Simpan password database secara privat.
2. Buka SQL Editor. Jalankan isi `supabase/migrations/202609140001_factory.sql` **sekali** di project baru.
3. Authentication → Users → buat user email/password untuk diri sendiri. Gunakan password unik. Nonaktifkan public signup karena app ini personal.
4. Salin UID user (bukan password), lalu SQL:

```sql
insert into public.factory_members(user_id) values ('GANTI_DENGAN_UID_USER');
```

5. Netlify environment build:

| Variable | Nilai |
| --- | --- |
| `PUBLIC_SUPABASE_URL` | Project URL Supabase |
| `PUBLIC_SUPABASE_ANON_KEY` | Publishable key atau legacy anon key |

6. Deploy ulang agar `config.js` dihasilkan dengan nilai baru. Dashboard menampilkan login, bukan demo.
7. Tambahkan URL Netlify ke Auth Site URL / redirect allowlist untuk alur auth yang mungkin ditambahkan kemudian. Login versi ini memakai email/password.
8. Storage `gameplay` (50 MB) dan `renders` (200 MB) private dibuat oleh SQL. Jangan ubah menjadi public.

## 3. API free-first untuk trial

Untuk tahap uji coba, berita masuk lewat RSS/Atom sehingga tidak memerlukan news API key. Masukkan feed HTTPS resmi di menu News sources. Worker hanya menyimpan ringkasan/feed body, judul, tanggal, dan tautan sumber; RSS yang hanya memberi cuplikan kurang dari 300 karakter sengaja dilewati agar AI tidak mengarang isi.

Script default memakai Gemini Developer API free tier:

1. Buka Google AI Studio → Get API key.
2. Buat key pada project khusus trial, lalu isi `GEMINI_API_KEY` di file `.env` lokal.
3. Default worker memakai `gemini-3.5-flash-lite`. Free tier memiliki kuota/rate limit dan data dapat digunakan Google untuk meningkatkan produknya, jadi kirim hanya materi berita publik.

Suara default memakai Edge TTS melalui worker lokal dan tidak memerlukan API key. Default-nya
`id-ID-ArdiNeural`; alternatif suara wanita adalah `id-ID-GadisNeural`.

ElevenLabs tetap tersedia sebagai opsi berbayar: ubah `TTS_PROVIDER=elevenlabs`, isi API key dan
Voice ID, lalu pastikan saldo ElevenAPI tersedia serta key memiliki akses Text to Speech.

OpenAI masih didukung sebagai opsi kemudian: set `TEXT_PROVIDER=openai` dan/atau `TTS_PROVIDER=openai`, isi `OPENAI_API_KEY`, lalu gunakan model di `.env`.

## 4. Worker render lokal

Dashboard tetap di Netlify, sedangkan AI call dan FFmpeg berjalan di laptop. Laptop serta Docker Desktop harus menyala selama antrean diproses. Tidak ada server worker cloud pada tahap trial.

1. Clone/download branch `feature/content-factory-v1`.
2. Salin `.env.example` menjadi `.env`.
3. Isi secret di `.env` lokal; jangan upload atau commit file tersebut.
4. Jalankan:

```sh
docker build -f worker/Dockerfile -t genz-factory .
docker run --name genz-factory --env-file .env genz-factory
```

Untuk menjalankan lagi setelah container berhenti: `docker start -a genz-factory`. Jika konfigurasi berubah, hapus container lama dengan `docker rm genz-factory`, lalu jalankan kembali perintah `docker run`.

| Variable worker | Isi |
| --- | --- |
| `SUPABASE_URL` | URL project baru |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key backend; hanya di laptop |
| `WORKER_OWNER_ID` | UID user yang sudah masuk `factory_members` |
| `TEXT_PROVIDER` | Default `gemini` |
| `GEMINI_API_KEY` | Key Google AI Studio |
| `GEMINI_TEXT_MODEL` | Default `gemini-3.5-flash-lite` |
| `TTS_PROVIDER` | Default `edge` |
| `EDGE_TTS_VOICE` | Default `id-ID-ArdiNeural` |
| `ELEVENLABS_API_KEY` | Opsional; key ElevenLabs berbayar |
| `ELEVENLABS_VOICE_ID` | Opsional; Voice ID ElevenLabs |
| `ELEVENLABS_MODEL_ID` | Default `eleven_multilingual_v2` |
| `MAX_VIDEOS_PER_DAY` | Default 3 percobaan; termasuk gagal, hari WIB |
| `POLL_SECONDS` | Default 10 detik |

Jalankan satu worker per owner. Queue claim memakai advisory lock dan menolak claim berikutnya selama masih ada job running milik owner tersebut. Tidak ada retry AI otomatis sehingga kegagalan tidak menghabiskan kuota berulang diam-diam.

## 5. Tes satu video dahulu

1. Login dashboard, buka Gameplay library. Upload MP4 yang direkam sendiri/berizin, maksimal 50 MB. Catatan: video landscape di-crop tengah.
2. Content studio → Tambah artikel manual. Isi judul, nama portal, URL HTTPS, tanggal WIB, teks minimal 300 karakter yang boleh digunakan.
3. Pilih artikel + gameplay + voice → Generate video.
4. Queue: `queued → checking_gameplay → writing_script → generating_voice → aligning_captions → rendering_video → uploading_result → completed`.
5. Finished cuts → Buka video. Dengarkan pelafalan nama/angka; periksa caption, safe area, durasi, keterbacaan sumber.
6. Link video signed berlaku satu jam. Buka lagi dari dashboard untuk membuat link baru.
7. Posting TikTok **manual**. Integrasi API TikTok merupakan tahap selanjutnya.

## 6. Aktifkan sumber dan automation

News sources → masukkan RSS HTTPS yang sudah diverifikasi dan boleh digunakan. URL artikel biasa bukan URL RSS. Tidak ada preset feed yang dianggap aktif tanpa tes. Worker mengambil maksimal 20 feed dan 50 item/feed, artikel <=48 jam dan teks >=300 karakter. Cuplikan pendek tidak dikembangkan menjadi berita buatan; gunakan artikel manual atau adapter full-text berizin pada iterasi berikutnya.

- **Cek berita terbaru**: scan saja.
- **Jalankan factory**: scan kemudian antrekan maksimal 3 kandidat belum pernah diproduksi dengan gameplay pilihan.
- Penjadwalan rutin belum ada di UI. Scheduler eksternal dapat menjalankan `python factory.py --scan --auto --asset UUID_ASSET --enqueue-only` dengan env yang sama; proses worker utama mengerjakan antrean sisanya. `--enqueue-only` hanya memasukkan scan ke antrean dan tidak menjalankan job; satu worker utama tetap mengerjakan produksi. `--once` tersedia untuk debugging satu job tertua. Scan aktif ganda ditolak unique index.

## 7. UAT yang wajib sebelum merge

| Tes | Hasil yang diharapkan |
| --- | --- |
| Preview tanpa config | Demo berlabel, tidak membuat MP4 palsu |
| Akun tanpa membership | Tidak dapat membaca/menambahkan data produksi |
| Dua akun member berbeda | Tidak dapat membaca artikel, jobs, assets, renders atau storage milik akun lain |
| Insert job dengan asset akun lain | Ditolak trigger ownership |
| Update status job dari browser | Ditolak permission database |
| Feed internal/metadata URL | Ditolak worker sebelum request |
| Scan dua kali | Judul sama/nyaris sama tidak bertambah |
| Feed invalid/pendek | Error/sumber terlewati ditampilkan; tanpa script khayalan |
| Gameplay salah/codec invalid | Gagal sebelum panggilan AI |
| Hasil TTS nyata | Audio Indonesia, subtitle sinkron, sumber tepat |
| Batas harian | Percobaan tambahan gagal sebelum panggilan AI |
| Refresh browser / tutup tab | Worker tetap memproses antrean |

Build dan uji FFmpeg lokal tidak membuktikan kredensial, RLS dan koneksi cloud telah lolos UAT. SQL perlu dijalankan di Supabase baru, lalu tes tabel di atas.

## Recovery worker

Jika worker mati, job `running` tidak otomatis diklaim ulang untuk menghindari tagihan ganda. Periksa log worker dan bucket renders dahulu. Setelah memastikan proses sudah berhenti, tandai job tertentu gagal lewat SQL, lalu retry dari dashboard:

```sql
update public.jobs set status='failed', stage='failed', error='Worker stopped; manual recovery', finished_at=now()
where id='GANTI_DENGAN_JOB_ID' and status='running';
```

Simpan backup/retensi Storage sesuai kebutuhan; MVP belum memiliki pembersihan video otomatis atau batas storage total. Kesalahan upload metadata asset dapat menyisakan file orphan; hapus melalui Storage setelah memastikan tidak dipakai job.
