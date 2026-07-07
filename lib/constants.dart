// ─── API CONFIG ──────────────────────────────────────────────────────────────
// All storage uploads go through the server (POST /api/upload). The Supabase
// service_role key lives ONLY on the server, never in the client.
const String kApiUrl = 'https://sigma-social-backend.onrender.com/api';

// ─── MATRIX CHAT ───────────────────────────────────────────────────────────
// Chat runs on a separate Matrix homeserver — not in Sigma DB.
// POC default: matrix.org (login with an existing account for testing).
// Production: point to your own Conduit/Synapse, e.g. https://chat.sigma.ru
const String kMatrixHomeserver = 'https://matrix.org';
const String kMatrixServerName = 'matrix.org';

/// When true, Sigma login also tries to register @username on the homeserver.
const bool kMatrixAutoRegister = false;
