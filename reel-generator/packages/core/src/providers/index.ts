import { MockScriptProvider, type ScriptProvider } from "./script.js";
import { MockVoiceProvider, type VoiceProvider } from "./voice.js";
import { MockVisualProvider, type VisualProvider } from "./visuals.js";
import { MockAssemblyProvider, type AssemblyProvider } from "./assembly.js";

export * from "./script.js";
export * from "./voice.js";
export * from "./visuals.js";
export * from "./assembly.js";

/** The set of providers the pipeline needs to run. */
export interface Providers {
  script: ScriptProvider;
  voice: VoiceProvider;
  visuals: VisualProvider;
  assembly: AssemblyProvider;
}

/**
 * All-mock provider set: runs the full pipeline offline with no API keys.
 * Real deployments compose real providers behind the same interfaces and
 * swap them in here (or via dependency injection / env config).
 */
export function mockProviders(): Providers {
  return {
    script: new MockScriptProvider(),
    voice: new MockVoiceProvider(),
    visuals: new MockVisualProvider(),
    assembly: new MockAssemblyProvider(),
  };
}
