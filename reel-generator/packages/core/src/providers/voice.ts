import type { Scene, Voiceover, WordTiming } from "../types.js";

/**
 * Synthesizes narration audio and returns per-word timings used to sync
 * captions. Real impl: ElevenLabs / OpenAI TTS (some return timestamps
 * directly; otherwise run whisper over the audio to recover them).
 */
export interface VoiceProvider {
  synthesize(scenes: Scene[], voiceId: string): Promise<Voiceover>;
}

/**
 * Offline mock: derives plausible word timings from the scene timeline
 * (words spread evenly across each scene's span) and returns a fake audio
 * URL. No audio is produced, but the timing contract downstream is real.
 */
export class MockVoiceProvider implements VoiceProvider {
  async synthesize(scenes: Scene[], voiceId: string): Promise<Voiceover> {
    const words: WordTiming[] = [];
    for (const scene of scenes) {
      const tokens = scene.text.split(/\s+/).filter(Boolean);
      const span = Math.max(0.001, scene.endSec - scene.startSec);
      const per = span / tokens.length;
      tokens.forEach((word, i) => {
        words.push({
          word,
          startSec: +(scene.startSec + i * per).toFixed(3),
          endSec: +(scene.startSec + (i + 1) * per).toFixed(3),
        });
      });
    }
    return {
      voiceId,
      audioUrl: `mock://voiceover/${voiceId}.wav`,
      words,
    };
  }
}
