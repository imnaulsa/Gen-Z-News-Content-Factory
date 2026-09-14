# Validation — 2026-09-14

## Passed locally

- `npm run check`: ES module syntax, dashboard + REST/auth client.
- `npm run build`: static dashboard and explicit public config allowlist.
- `python3 -m unittest discover -s tests -v`: 10 tests passed.
- Tests include fresh/old/future/missing-date RSS, Atom, short feed rejection, invalid feed rejection, normalized title dedupe, private IPv4/IPv6 DNS rejection, unsafe URL rejection, script evidence validation, caption escaping/timestamps.
- FFmpeg integration test creates synthetic visual/audio fixtures, burns ASS subtitles, and verifies output H.264 1080×1920, AAC audio, 2-second duration. It does not invoke OpenAI and is not a real news video.

## Not yet verified

- Browser visual check attempted; session browser returned `net::ERR_BLOCKED_BY_CLIENT` for local server. No visual/browser pass claimed. Check desktop/mobile via Netlify preview.
- Supabase migration execution, RLS tests against two real users, login and Storage upload/signing: requires new Supabase project.
- OpenAI live text/TTS/transcription: requires user API credentials/billing.
- Publisher-specific feeds, including Detik/Kompas/Kumparan: no active feed endpoints configured yet.
- Netlify cloud build and real worker hosting: requires user account setup.

See SETUP.md for UAT gates. This branch is ready for setup and review, not a declaration that live production is running.
