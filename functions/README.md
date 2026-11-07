# Rig Music — Gemini key proxy

This Cloud Function holds your Gemini API key **server-side** (Firebase Secret
Manager), so the key is never compiled into the app and cannot be extracted from
the APK/JS. The app calls this function; the function calls Google.

## How it works

```
App  --POST { model, payload }-->  geminiProxy  --adds secret key-->  Gemini
App  <----- exact status+body ----  geminiProxy  <--- status+body ---- Gemini
```

The proxy returns Google's **exact** status code and body, so every error path
in the app (model fallback, grounding retry, rate-limit, timeout) works the same
whether you use the proxy or a direct key.

## Deploy (one time)

Prereqs: `npm install -g firebase-tools`, then `firebase login`, and the project
is already pointed at `rigmusic-a203e` via `.firebaserc`.

```bash
# 1. Install function deps
cd functions && npm install && cd ..

# 2. Store your Gemini key as a secret (paste the key when prompted)
firebase functions:secrets:set GEMINI_API_KEY

# 3. Deploy the function
firebase deploy --only functions
```

After deploy, note the printed URL. It looks like:

```
https://us-central1-rigmusic-a203e.cloudfunctions.net/geminiProxy
```

## Wire it into the app

Paste that URL into `_proxyUrl` in `lib/services/gemini_service.dart`
(the constant sits right next to `_bundledKey`). Rebuild the app.

- `_proxyUrl` set  → all Oracle calls go through the proxy (key stays on the
  server; `_bundledKey` is ignored).
- `_proxyUrl` empty → the app calls Google directly using a user-pasted key or
  `_bundledKey` (the old behaviour), so nothing breaks before you deploy.

## Notes

- The function allows any origin (`Access-Control-Allow-Origin: *`) because the
  app is public. That is safe here: the function only forwards the payload to
  Google and the secret never leaves the server.
- To rotate the key: `firebase functions:secrets:set GEMINI_API_KEY` again (new
  version), then redeploy / restart — no app update needed.
