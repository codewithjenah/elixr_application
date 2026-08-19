// Convenience pointer. Run the privileged migrator from its package:
//
//   cd scripts/legacy_coaching_provenance
//   dart test
//   npm install
//   node backfill.mjs --dry-run --project=elixr-app-2026
//   node backfill.mjs --write --project=elixr-app-2026
//
// Write mode is human-approved only. Do not run it from Flutter UI.
void main() {
  throw UnsupportedError(
    'Run from scripts/legacy_coaching_provenance: '
    '`node backfill.mjs --dry-run --project=elixr-app-2026`.',
  );
}
