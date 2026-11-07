const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

// The Gemini API key lives ONLY here, in Firebase Secret Manager. It is never
// compiled into the app, so it cannot be extracted from the shipped APK/JS.
const GEMINI_KEY = defineSecret("GEMINI_API_KEY");

// Flutter web sends Content-Type: application/json, which triggers a CORS
// preflight — handle it here (permissive origin, since the app is public).
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

/**
 * Thin pass-through proxy for Google's generateContent endpoint.
 *
 * Client  ->  POST { model, payload }  (no key)
 * Proxy   ->  POST .../models/{model}:generateContent  (adds secret key)
 * Proxy   ->  returns Google's EXACT status code + body
 *
 * Passing the status/body through untouched means every error path in the app
 * (400 grounding fallback, 404 model-not-found, 429 rate limit, 5xx retry)
 * behaves identically whether you use the proxy or a direct key.
 */
exports.geminiProxy = onRequest(
  {
    secrets: [GEMINI_KEY],
    region: "us-central1",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (req, res) => {
    for (const [k, v] of Object.entries(CORS)) res.set(k, v);

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ error: { message: "Method Not Allowed" } });
      return;
    }

    const { model, payload } = req.body || {};
    if (typeof model !== "string" || !model || typeof payload !== "object" || payload === null) {
      res.status(400).json({
        error: { message: "Body must be { model: string, payload: object }." },
      });
      return;
    }

    // Allow only the model name — no path traversal / URL injection.
    const safeModel = String(model).replace(/[^a-zA-Z0-9.\-]/g, "");
    if (!safeModel) {
      res.status(400).json({ error: { message: "Invalid model name." } });
      return;
    }

    const url =
      "https://generativelanguage.googleapis.com/v1beta/models/" +
      encodeURIComponent(safeModel) +
      ":generateContent";

    try {
      const r = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": GEMINI_KEY.value(),
        },
        body: JSON.stringify(payload),
      });

      // Pass bytes + status through untouched so the client sees the real
      // Gemini response.
      const buf = Buffer.from(await r.arrayBuffer());
      const ct = r.headers.get("content-type") || "application/json";
      res.status(r.status).set("Content-Type", ct).send(buf);
    } catch (e) {
      res.status(502).json({
        error: { message: "Upstream fetch failed: " + (e && e.message ? e.message : String(e)) },
      });
    }
  }
);
