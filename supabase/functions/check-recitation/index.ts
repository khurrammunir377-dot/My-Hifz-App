// Supabase Edge Function: check-recitation
//
// Receives a short WAV audio chunk from the Flutter app, sends it to Groq's
// Whisper API for Arabic transcription, and returns the transcript text.
// The Groq API key lives here as a server-side secret and is never embedded
// in the app, per the security requirement in the Phase 2 spec.
//
// Deploy with:
//   supabase functions deploy check-recitation
// Set the secret with:
//   supabase secrets set GROQ_API_KEY=your_key_here

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
const GROQ_URL = "https://api.groq.com/openai/v1/audio/transcriptions";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!GROQ_API_KEY) {
    return new Response(
      JSON.stringify({ error: "GROQ_API_KEY secret not configured on the server" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const startedAt = Date.now();

    // The app sends the raw WAV audio bytes as the request body, with the
    // Surah/Ayah reference passed as query params for logging/debugging.
    const audioBytes = new Uint8Array(await req.arrayBuffer());
    console.log(`Received audio chunk: ${audioBytes.length} bytes`);
    if (audioBytes.length === 0) {
      return new Response(
        JSON.stringify({ error: "No audio data received" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    // Log the first 12 bytes as hex - a valid WAV file must start with
    // "RIFF" (52 49 46 46) followed 8 bytes in by "WAVE" (57 41 56 45).
    // If this doesn't match, the app is sending malformed audio, not a
    // Groq-side problem.
    const headerHex = Array.from(audioBytes.slice(0, 12))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join(" ");
    console.log(`First 12 bytes (hex): ${headerHex}`);

    const formData = new FormData();
    formData.append(
      "file",
      new Blob([audioBytes], { type: "audio/wav" }),
      "chunk.wav",
    );
    formData.append("model", "whisper-large-v3");
    formData.append("language", "ar");
    formData.append("response_format", "json");
    // Encourage word-for-word transcription rather than paraphrasing.
    formData.append(
      "prompt",
      "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ Quranic Arabic recitation, exact Uthmani wording.",
    );

    const groqResponse = await fetch(GROQ_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${GROQ_API_KEY}` },
      body: formData,
    });

    if (!groqResponse.ok) {
      const errText = await groqResponse.text();
      return new Response(
        JSON.stringify({ error: `Groq API error: ${errText}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const result = await groqResponse.json();
    const latencyMs = Date.now() - startedAt;

    return new Response(
      JSON.stringify({
        transcript: result.text ?? "",
        latency_ms: latencyMs,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: `Unexpected error: ${err instanceof Error ? err.message : String(err)}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
