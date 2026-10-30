# TokenBar Promo Remotion Project

## Voiceover

- Service: Microsoft Edge neural TTS via `edge-tts`
- Voice: `zh-CN-XiaoxiaoNeural`
- Rate: `+4%`
- Pitch: `-2Hz`
- Duration: about 78.6 seconds

Regenerate narration:

```bash
uvx edge-tts \
  --file scripts/narration-zh.txt \
  --voice zh-CN-XiaoxiaoNeural \
  --rate=+4% \
  --pitch=-2Hz \
  --write-media public/audio/narration.mp3 \
  --write-subtitles public/audio/narration.vtt
npm run captions
```

## Preview and render

```bash
npm install
npm run lint
npm run dev
npm run render
```

Composition ID: `TokenBarPromo`
