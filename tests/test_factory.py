import asyncio
import datetime as dt
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from worker.factory import parse_feed, fingerprint, public_addresses, fetch_feed, validate_script, captions, ass_time, alignment_words, edge_speech, render, probe

class FactoryTests(unittest.TestCase):
    def setUp(self):
        self.clock=dt.datetime(2026,9,14,12,tzinfo=dt.timezone.utc)
        self.body='Sebuah laporan menjelaskan perkembangan perusahaan dan perubahan produknya. '*8
    def feed(self, date='Mon, 14 Sep 2026 10:00:00 +0000',body=None):
        return f'<rss><channel><item><title>Berita contoh</title><link>https://example.com/news</link><pubDate>{date}</pubDate><description>{body or self.body}</description></item></channel></rss>'.encode()
    def test_fresh_rss(self):
        articles=parse_feed(self.feed(),{'name':'Example'},self.clock)
        self.assertEqual(len(articles),1);self.assertEqual(articles[0]['source_name'],'Example')
    def test_skip_old_future_missing_dates_and_short_body(self):
        for raw in [self.feed('Mon, 01 Sep 2025 10:00:00 +0000'),self.feed('Tue, 15 Sep 2026 10:00:00 +0000'),self.feed(''),self.feed(body='Hanya judul')]:
            self.assertEqual(parse_feed(raw,{'name':'Example'},self.clock),[])
    def test_atom(self):
        raw=f'<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Contoh Atom</title><link href="https://example.com/a"/><updated>2026-09-14T11:00:00Z</updated><content>{self.body}</content></entry></feed>'.encode()
        self.assertEqual(parse_feed(raw,{'name':'Atom'},self.clock)[0]['title'],'Contoh Atom')
    def test_not_a_feed(self):
        with self.assertRaises(ValueError):parse_feed(b'<html><body>Error</body></html>',{'name':'Bad'},self.clock)
    def test_dedupe_fingerprint(self): self.assertEqual(fingerprint('Berita BARU!'),fingerprint('berita baru'))
    def test_ssrf_private_ipv4_and_ipv6(self):
        for address in ['127.0.0.1','169.254.169.254','10.0.0.1','::1','fc00::1','::ffff:127.0.0.1']:
            with patch('socket.getaddrinfo',return_value=[(2,1,6,'',(address,443))]):
                with self.assertRaises(ValueError):public_addresses('example.test')
    def test_unsafe_urls_rejected(self):
        for url in ['http://example.com/rss','file:///etc/passwd','https://user:pass@example.com/rss','https://example.com:8080/rss']:
            with self.assertRaises(ValueError):fetch_feed(url)
    def test_script_evidence_and_length(self):
        text='Ini contoh kalimat panjang dengan informasi yang berasal dari artikel sumber yang sedang dibahas.'
        script={'title':'Judul','sentences':[{'text':text,'evidence':self.body[:40]} for _ in range(5)]}
        validate_script(script,{'body':self.body})
        script['sentences'][0]['evidence']='Fakta ini tidak ada dalam sumber.'
        with self.assertRaises(ValueError):validate_script(script,{'body':self.body})
    def test_character_alignment_becomes_word_timestamps(self):
        alignment={
          'characters':list('Halo dunia!'),
          'character_start_times_seconds':[i/10 for i in range(11)],
          'character_end_times_seconds':[(i+1)/10 for i in range(11)]
        }
        self.assertEqual(alignment_words(alignment),[
          {'word':'Halo','start':0.0,'end':0.4},
          {'word':'dunia!','start':0.5,'end':1.1}
        ])
        with self.assertRaises(ValueError): alignment_words({'characters':['x'],'character_start_times_seconds':[],'character_end_times_seconds':[]})

    def test_edge_tts_audio_timing_and_legacy_voice_fallback(self):
        selected={}
        class FakeCommunicate:
            def __init__(self,text,voice,**options): selected['voice']=voice
            async def stream(self):
                yield {'type':'audio','data':b'mp3'}
                yield {'type':'WordBoundary','text':'Halo','offset':10_000_000,'duration':5_000_000}
        fake=SimpleNamespace(Communicate=FakeCommunicate)
        with patch.dict(sys.modules,{'edge_tts':fake}),patch.dict(os.environ,{'EDGE_TTS_VOICE':'id-ID-ArdiNeural'}):
            audio,words=asyncio.run(edge_speech('Halo','alloy'))
        self.assertEqual(selected['voice'],'id-ID-ArdiNeural')
        self.assertEqual(audio,b'mp3')
        self.assertEqual(words,[{'word':'Halo','start':1.0,'end':1.5}])

    def test_caption_escaping_and_timing(self):
        output=captions([{'word':'{\\an8}test','start':0,'end':1}], 'Judul','Sumber',2)
        self.assertNotIn('{\\an8}',output)
        self.assertIn('0:00:01.00',output);self.assertEqual(ass_time(59.999),'0:01:00.00')
        with self.assertRaises(ValueError):captions([{'word':'bad','start':3,'end':2}],'t','s',5)

@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'),'FFmpeg required')
class RenderIntegrationTest(unittest.TestCase):
    def test_real_mp4_has_portrait_video_audio_and_expected_duration(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)
            # Synthetic fixtures only: not presented as generated narration/gameplay.
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=c=0x28432a:s=360x640:r=30','-t','2','-pix_fmt','yuv420p',str(p/'gameplay.mp4')],check=True,capture_output=True)
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','sine=frequency=440:sample_rate=44100','-t','2',str(p/'voice.mp3')],check=True,capture_output=True)
            (p/'captions.ass').write_text(captions([{'word':'BERITA','start':0,'end':.8},{'word':'CONTOH','start':.8,'end':1.7}],'UJI RENDER','Fixture lokal',2))
            render(tmp,2)
            result=probe(p/'video.mp4')
            video=next(s for s in result['streams'] if s['codec_type']=='video')
            self.assertEqual((video['width'],video['height']),(1080,1920))
            self.assertEqual(video['codec_name'],'h264')
            self.assertTrue(any(s['codec_type']=='audio' and s['codec_name']=='aac' for s in result['streams']))
            self.assertAlmostEqual(float(result['format']['duration']),2,delta=.15)

if __name__=='__main__':unittest.main()
