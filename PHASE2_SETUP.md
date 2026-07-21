# Phase 2 Setup — Recitation Checking Backend

Phase 2 needs a small server-side piece so your Groq API key never sits
inside the app itself. This uses Supabase Edge Functions, since you've
already used Supabase for ECOSTRUCT.

## 1. Get a free Groq API key

1. Go to https://console.groq.com and sign up (free tier available)
2. Create an API key
3. Keep it somewhere safe — you'll paste it once in step 4, never in the app

## 2. Set up the Supabase CLI (one-time)

If you don't already have a Supabase project for this app:
1. Go to https://supabase.com, create a new project
2. Note your **project reference** (the short ID in your project URL, e.g.
   `abcdefghijklmnop`)

On your computer (or in a GitHub Codespace / Cloud Shell if you don't have
Node.js locally):

```bash
npm install -g supabase
supabase login
```

## 3. Link and deploy the function

From inside the project folder (where the `supabase/` directory is):

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy check-recitation --no-verify-jwt
```

`--no-verify-jwt` is used here because the app doesn't have user login yet
(Phase 1-2 scope) — it makes the endpoint callable without an auth token.
**Note:** this means anyone with the URL could call it and use your Groq
quota. That's an acceptable tradeoff for testing/early use, but before a
public launch this should be locked down (e.g. requiring a Supabase auth
token, or adding basic rate limiting) — flag this to me when you're ready
for that.

## 4. Set your Groq API key as a server-side secret

```bash
supabase secrets set GROQ_API_KEY=your_groq_key_here
```

This key now lives only on Supabase's servers — it's never in the app or
in your GitHub repo.

## 5. Get your function's URL

It will be:

```
https://YOUR_PROJECT_REF.supabase.co/functions/v1/check-recitation
```

## 6. Configure the app

1. Build and install the updated APK (same GitHub Actions process as before)
2. Open the app → Settings → scroll to **Recognition Endpoint**
3. Paste the URL from step 5 → tap **Save**
4. Go to any verse → tap the mic button to start checking your recitation

## Testing checklist for Phase 2

- [ ] Tapping the mic button on the Recitation Screen prompts for
      microphone permission (first time only)
- [ ] While reciting, words in the ayah text turn green as you say them
      correctly
- [ ] Saying a wrong word turns it red, and you feel a vibration + hear a
      short tone within a couple of seconds
- [ ] Skipping a word shows it in orange once the app has moved past it
- [ ] Stopping shows a final "X/Y words correct" summary
- [ ] "Play Back" plays your full recitation for that verse
- [ ] Recognition still fails gracefully (shows a connection message, does
      not crash) if you turn off mobile data briefly mid-recitation
- [ ] Settings → Your Progress shows updated stats after a few attempts

## About cost and latency

Ask me to check current Groq pricing before you scale this to many users —
pricing can change, and I'd rather verify it fresh than quote a number that
might be stale by the time you read this. During testing, note the
`latency_ms` value the function returns (visible if you check the Supabase
function logs) — that's the real number to judge whether 2.5-second chunks
feel responsive enough, or need to be shorter.
