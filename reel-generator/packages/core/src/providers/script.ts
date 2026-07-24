import type { ReelRequest, Scene } from "../types.js";

/**
 * Turns a topic (or a user-supplied script) into a list of timed scenes.
 * Real impl: an LLM (e.g. Claude) prompted to produce hook + body + CTA
 * sized to the target duration, returning structured JSON.
 */
export interface ScriptProvider {
  plan(req: ReelRequest): Promise<Scene[]>;
}

const SECONDS_PER_SCENE = 4;

/**
 * Offline mock: splits the script (or a canned template around the topic)
 * into ~sentence-sized scenes with evenly spaced timings. Deterministic so
 * the skeleton runs with no API keys.
 */
export class MockScriptProvider implements ScriptProvider {
  async plan(req: ReelRequest): Promise<Scene[]> {
    const captionStyle = req.captionStyle ?? "karaoke-bold-yellow";
    const raw =
      req.script?.trim() ||
      [
        `Here's something wild about ${req.topic}.`,
        `Most people never stop to think about ${req.topic}.`,
        `But once you see it, you can't unsee it.`,
        `Follow for more on ${req.topic}.`,
      ].join(" ");

    const sentences = raw
      .split(/(?<=[.!?])\s+/)
      .map((s) => s.trim())
      .filter(Boolean);

    return sentences.map((text, i) => ({
      id: `s${i + 1}`,
      text,
      startSec: i * SECONDS_PER_SCENE,
      endSec: (i + 1) * SECONDS_PER_SCENE,
      visual: {
        type: "stock",
        query: keyword(text, req.topic),
        motion: i % 2 === 0 ? "zoom-in" : "zoom-out",
      },
      captionStyle,
      transitionOut: i < sentences.length - 1 ? "whip-pan" : "fade",
    }));
  }
}

function keyword(text: string, topic: string): string {
  const stop = new Set([
    "here", "heres", "something", "about", "most", "people", "never", "stop",
    "think", "once", "you", "youre", "see", "cant", "unsee", "follow", "more",
    "the", "a", "an", "and", "but", "for", "with", "this", "that", "wild",
  ]);
  const word = text
    .toLowerCase()
    .replace(/[^a-z\s]/g, "")
    .split(/\s+/)
    .find((w) => w.length > 3 && !stop.has(w));
  return word ?? topic;
}
