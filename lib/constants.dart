import 'package:flutter/material.dart';

const String kApiUrl = 'https://sigma-social-backend.onrender.com/api';
const String kSupabaseUrl = 'https://uvbyxkrtyjqrorxnckvw.supabase.co';
const String kSupabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV2Ynl4a3J0eWpxcm9yeG5ja3Z3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTg5MDM4NiwiZXhwIjoyMDk1NDY2Mzg2fQ.oP8PhoIqP8F6QJnKM4p-gujW_nfe12ZWsePg_Scc_8A';

// ─── NEBULA DARK PALETTE ─────────────────────────────────────────────────────
const Color kBg        = Color(0xFF09090B); // zinc-950
const Color kSurface   = Color(0xFF18181B); // zinc-900
const Color kSurface2  = Color(0xFF27272A); // zinc-800
const Color kBorder    = Color(0xFF3F3F46); // zinc-700
const Color kAccent    = Color(0xFF7C3AED); // violet-700
const Color kAccentLit = Color(0xFFA78BFA); // violet-400
const Color kPink      = Color(0xFFEC4899); // pink-500  (likes)
const Color kBlue      = Color(0xFF3B82F6); // blue-500  (links)
const Color kGreen     = Color(0xFF22C55E); // green-500 (online)
const Color kText      = Color(0xFFFAFAFA); // zinc-50
const Color kMuted     = Color(0xFFA1A1AA); // zinc-400
const Color kDim       = Color(0xFF71717A); // zinc-500

// Legacy aliases so old code compiles
const Color kGold   = kAccent;
const Color kDark   = kBg;
const Color kCard   = kSurface;

// Gradient used on story rings and buttons
const LinearGradient kStoryGradient = LinearGradient(
  colors: [Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFFF97316)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kButtonGradient = LinearGradient(
  colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
