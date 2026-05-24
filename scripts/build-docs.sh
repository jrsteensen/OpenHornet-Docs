#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLIC_DIR="${ROOT}/public"
SOFTWARE_SRC="${ROOT}/sources/software"
HARDWARE_SRC="${ROOT}/sources/hardware"
DOXYGEN_BIN="${DOXYGEN_BIN:-}"

if [[ -z "${DOXYGEN_BIN}" ]]; then
  if command -v doxygen >/dev/null 2>&1; then
    DOXYGEN_BIN="doxygen"
  elif command -v doxygen.exe >/dev/null 2>&1; then
    DOXYGEN_BIN="doxygen.exe"
  else
    echo "Doxygen is required but was not found in PATH." >&2
    exit 1
  fi
fi

require_path() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    echo "Missing required path: ${path}" >&2
    exit 1
  fi
}

latest_release_tag() {
  local repo="$1"
  local fallback_dir="$2"

  if command -v gh >/dev/null 2>&1; then
    local tag
    tag="$(gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null || true)"
    if [[ -n "${tag}" && "${tag}" != "null" ]]; then
      echo "${tag}"
      return
    fi
  fi

  git -C "${fallback_dir}" rev-parse --short HEAD
}

require_path "${SOFTWARE_SRC}/docs/Doxyfile"
require_path "${HARDWARE_SRC}/docs/Doxyfile"

rm -rf "${PUBLIC_DIR}"
mkdir -p "${PUBLIC_DIR}/software" "${PUBLIC_DIR}/hardware"

software_version="$(latest_release_tag "jrsteensen/OpenHornet-Software" "${SOFTWARE_SRC}")"
hardware_version="$(latest_release_tag "jrsteensen/OpenHornet" "${HARDWARE_SRC}")"

echo "Building software docs (${software_version})"
rm -rf "${SOFTWARE_SRC}/docs/html"
(
  cd "${SOFTWARE_SRC}/docs"
  PROJECT_VERSION="${software_version}" "${DOXYGEN_BIN}" Doxyfile
)
require_path "${SOFTWARE_SRC}/docs/html/index.html"
rsync -a --delete "${SOFTWARE_SRC}/docs/html/" "${PUBLIC_DIR}/software/"

echo "Building hardware docs (${hardware_version})"
rm -rf "${HARDWARE_SRC}/docs/html" "${HARDWARE_SRC}/docs/_doxygen"
mkdir -p "${HARDWARE_SRC}/docs/_doxygen/css" "${HARDWARE_SRC}/docs/_doxygen/img/logos"
rsync -a "${SOFTWARE_SRC}/docs/css/" "${HARDWARE_SRC}/docs/_doxygen/css/"
rsync -a "${SOFTWARE_SRC}/docs/img/logos/" "${HARDWARE_SRC}/docs/_doxygen/img/logos/"
(
  cd "${HARDWARE_SRC}/docs"
  PROJECT_VERSION="${hardware_version}" "${DOXYGEN_BIN}" Doxyfile
)
require_path "${HARDWARE_SRC}/docs/html/index.html"
rsync -a --delete "${HARDWARE_SRC}/docs/html/" "${PUBLIC_DIR}/hardware/"

cat > "${PUBLIC_DIR}/index.html" <<'HTML'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>OpenHornet Documentation</title>
    <style>
      :root {
        color-scheme: light dark;
        --bg: #f7f9fb;
        --fg: #18222c;
        --muted: #5b6b7a;
        --panel: #ffffff;
        --accent: #1779c4;
        --border: #d9e2ea;
      }

      @media (prefers-color-scheme: dark) {
        :root {
          --bg: #111820;
          --fg: #eef4f9;
          --muted: #aebbc7;
          --panel: #182430;
          --accent: #70b1e9;
          --border: #2d3b48;
        }
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background: var(--bg);
        color: var(--fg);
        font: 16px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }

      main {
        width: min(900px, calc(100% - 32px));
        padding: 48px 0;
      }

      h1 {
        margin: 0 0 12px;
        font-size: clamp(2rem, 5vw, 3.4rem);
        line-height: 1;
      }

      p {
        margin: 0;
        color: var(--muted);
      }

      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
        gap: 16px;
        margin-top: 32px;
      }

      a {
        display: block;
        min-height: 150px;
        padding: 24px;
        border: 1px solid var(--border);
        border-radius: 8px;
        background: var(--panel);
        color: inherit;
        text-decoration: none;
      }

      a:hover,
      a:focus-visible {
        border-color: var(--accent);
        outline: none;
      }

      strong {
        display: block;
        margin-bottom: 8px;
        color: var(--accent);
        font-size: 1.35rem;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>OpenHornet Documentation</h1>
      <p>Generated technical documentation for the OpenHornet hardware and software repositories.</p>
      <div class="grid" aria-label="Documentation areas">
        <a href="/software/">
          <strong>Software</strong>
          Firmware, sketches, libraries, and API documentation.
        </a>
        <a href="/hardware/">
          <strong>Hardware</strong>
          Repository documentation, tutorials, and hardware reference material.
        </a>
      </div>
    </main>
  </body>
</html>
HTML

cat > "${PUBLIC_DIR}/_redirects" <<'REDIRECTS'
/software /software/ 301
/hardware /hardware/ 301
REDIRECTS

cat > "${PUBLIC_DIR}/_headers" <<'HEADERS'
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()

/software/*
  Cache-Control: public, max-age=3600

/hardware/*
  Cache-Control: public, max-age=3600
HEADERS

require_path "${PUBLIC_DIR}/index.html"
require_path "${PUBLIC_DIR}/software/index.html"
require_path "${PUBLIC_DIR}/hardware/index.html"

echo "Docs site assembled in ${PUBLIC_DIR}"
