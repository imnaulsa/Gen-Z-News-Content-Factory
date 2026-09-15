# Gen-Z News Content Factory

Web dashboard + background worker untuk mengubah artikel berita menjadi video pendek dengan dubbing Indonesia, subtitle dan gameplay. Target hosting dashboard: **Netlify milik pengguna**; database/auth/storage: **Supabase project baru**.

## Mulai

1. Baca **[docs/SETUP.md](docs/SETUP.md)** untuk setup Netlify, Supabase, worker, dan API.
2. Baca **[docs/FLOW.md](docs/FLOW.md)** untuk alur dan batas MVP.
3. Review perubahan di branch `feature/content-factory-v1` sebelum merge ke `main`.

```sh
npm run build
python3 -m http.server 4173 --directory dist
```

Tanpa environment Supabase, dashboard menampilkan **mode demo dengan data ilustrasi**. Tidak ada panggilan AI, render palsu, atau klaim berita terkini pada mode ini.

## Komponen yang sudah diimplementasikan

- Dashboard: News radar, Content studio, antrean, gameplay library, sumber RSS dan setup.
- Login Supabase, membership allowlist, RLS data per pemilik, dan private storage.
- Artikel manual dan collector RSS/Atom dengan validasi tanggal, panjang teks, pembatasan ukuran serta perlindungan SSRF.
- Deduplikasi judul exact dan near-duplicate (bukan semantic clustering lintas media).
- Queue claim atomik; job status, retry manual, output tersimpan.
- Script dengan evidence kutipan sumber dan pemeriksaan kesetiaan sumber oleh AI.
- Default free-first: Gemini Flash-Lite untuk script dan Edge TTS suara Indonesia untuk dubbing + timing caption; ElevenLabs/OpenAI tetap opsional.
- Subtitle ASS dan render lokal FFmpeg H.264/AAC 1080×1920.
- Scan sekaligus auto-enqueue maksimal tiga artikel yang belum diproduksi.
- Worker Docker dan CI build + unit/integration tests tanpa API key.

## Belum dinyatakan live

- Netlify dan Supabase sudah dipasang pengguna; login dan upload gameplay sudah lolos smoke test manual.
- Gemini/Edge TTS live, scan RSS, queue, render, dan download output masih perlu UAT pada worker lokal.
- RSS Detik, Kompas, Kumparan belum dikonfigurasi atau diuji. Tidak ada klaim akses seluruh portal.
- Scraping full article, cross-source fact verification, semantic clustering, auto-post TikTok, analytics dan penjadwal UI belum diimplementasikan.
- Worker berjalan single instance per owner. Jadwal dapat dijalankan oleh scheduler eksternal melalui CLI.

## Pemeriksaan lokal

```sh
npm run check
npm run build
python3 -m unittest discover -s tests -v
```

Frontend memakai HTML/CSS/ES modules tanpa dependency npm runtime; build Node menanamkan hanya dua nilai Supabase publik. Worker memakai Python standard library dan FFmpeg. Pilihan ini membuat bootstrap ringan dan tidak membutuhkan instalasi library browser untuk runtime.

## Sumber dokumentasi API

- [Gemini Developer API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Gemini generateContent](https://ai.google.dev/api/generate-content)
- [edge-tts](https://github.com/rany2/edge-tts) untuk trial lokal tanpa API key
- [ElevenLabs speech with timing](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps) (opsional berbayar)
- [OpenAI TTS (opsional)](https://developers.openai.com/api/docs/guides/text-to-speech)
- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Netlify file configuration](https://docs.netlify.com/build/configure-builds/file-based-configuration/)
