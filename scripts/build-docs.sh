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
  local tag

  if command -v gh >/dev/null 2>&1; then
    tag="$(gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null || true)"
    if [[ -n "${tag}" && "${tag}" != "null" ]]; then
      echo "${tag}"
      return
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    local curl_args=(-fsSL -H "Accept: application/vnd.github+json")
    if [[ -n "${GH_TOKEN:-}" ]]; then
      curl_args+=(-H "Authorization: Bearer ${GH_TOKEN}")
    fi

    tag="$(
      curl "${curl_args[@]}" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1 \
        || true
    )"
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
    <meta
      name="description"
      content="Generated OpenHornet hardware and software documentation, release references, and builder resources."
    >
    <style>
      :root {
        color-scheme: light;
        --ink: #171b1f;
        --muted: #5b6b7a;
        --surface: #ffffff;
        --surface-soft: #f5f7f2;
        --surface-warm: #f8f1df;
        --surface-green: #e9f1ea;
        --line: #d9dfd5;
        --signal: #d5a72c;
        --signal-dark: #8b6617;
        --green: #2f6b62;
        --blue: #17465a;
        --footer-bg: #171b1f;
        --footer-ink: rgba(255, 255, 255, 0.78);
        --shadow: 0 18px 55px rgba(23, 27, 31, 0.12);
        --logo-filter: none;
        --radius: 8px;
      }

      @media (prefers-color-scheme: dark) {
        :root {
          color-scheme: dark;
          --ink: #f2f5ef;
          --muted: #b8c4bd;
          --surface: #151a1b;
          --surface-soft: #0e1213;
          --surface-warm: #2a2418;
          --surface-green: #152520;
          --line: #303a38;
          --signal: #e4bb4e;
          --signal-dark: #f0d37d;
          --green: #78c9b9;
          --blue: #89cfe1;
          --footer-bg: #0b0f10;
          --footer-ink: rgba(255, 255, 255, 0.76);
          --shadow: 0 18px 55px rgba(0, 0, 0, 0.45);
          --logo-filter: brightness(0) invert(1);
        }
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        background: var(--surface-soft);
        color: var(--ink);
        font: 16px/1.6 Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        text-rendering: optimizeLegibility;
      }

      img {
        display: block;
        max-width: 100%;
      }

      a {
        color: inherit;
        text-decoration-color: rgba(213, 167, 44, 0.8);
        text-decoration-thickness: 0.1em;
        text-underline-offset: 0.18em;
      }

      a:hover {
        color: var(--blue);
      }

      :focus-visible {
        outline: 3px solid var(--signal);
        outline-offset: 4px;
      }

      .site-header {
        position: sticky;
        top: 0;
        z-index: 10;
        border-bottom: 1px solid rgba(217, 223, 213, 0.9);
        background: rgba(255, 255, 255, 0.92);
        backdrop-filter: blur(16px);
      }

      @media (prefers-color-scheme: dark) {
        .site-header {
          border-bottom-color: rgba(48, 58, 56, 0.9);
          background: rgba(18, 22, 23, 0.92);
        }
      }

      .nav-wrap,
      main,
      .site-footer .inner {
        width: min(1180px, calc(100% - 32px));
        margin: 0 auto;
      }

      .nav-wrap {
        min-height: 78px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 24px;
      }

      .brand {
        display: inline-flex;
        align-items: center;
        text-decoration: none;
      }

      .brand img {
        width: 260px;
        filter: var(--logo-filter);
      }

      .nav-links {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        flex-wrap: wrap;
        gap: 6px;
      }

      .nav-links a {
        min-height: 40px;
        display: inline-flex;
        align-items: center;
        padding: 8px 12px;
        border-radius: var(--radius);
        color: var(--muted);
        text-decoration: none;
        font-size: 0.94rem;
        font-weight: 700;
      }

      .nav-links a:hover,
      .nav-links a:focus-visible {
        background: var(--surface-warm);
        color: var(--ink);
      }

      main {
        padding: 64px 0 72px;
      }

      .hero {
        display: grid;
        grid-template-columns: minmax(0, 1.1fr) minmax(280px, 0.9fr);
        gap: 32px;
        align-items: end;
        padding-bottom: 36px;
      }

      .eyebrow {
        margin: 0 0 12px;
        color: var(--signal-dark);
        font-size: 0.86rem;
        font-weight: 800;
        text-transform: uppercase;
      }

      h1 {
        margin: 0;
        max-width: 760px;
        font-size: 4rem;
        line-height: 1.04;
        letter-spacing: 0;
      }

      .lead {
        max-width: 760px;
        margin: 18px 0 0;
        color: var(--muted);
        font-size: 1.18rem;
      }

      p {
        margin: 0;
        color: var(--muted);
      }

      .action-row {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        margin-top: 28px;
      }

      .btn {
        min-height: 46px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 10px 16px;
        border: 1px solid var(--ink);
        border-radius: var(--radius);
        background: var(--ink);
        color: var(--surface);
        text-decoration: none;
        font-weight: 800;
      }

      .btn:hover {
        color: var(--surface);
        box-shadow: var(--shadow);
      }

      .btn.signal {
        border-color: var(--signal);
        background: var(--signal);
        color: #19150d;
      }

      .btn.secondary {
        border-color: var(--line);
        background: var(--surface);
        color: var(--ink);
      }

      .btn.secondary:hover {
        color: var(--ink);
      }

      .status-grid,
      .doc-grid,
      .resource-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 16px;
      }

      .status-grid {
        margin: 12px 0 28px;
      }

      .stat,
      .card {
        padding: 24px;
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--surface);
        color: inherit;
        text-decoration: none;
      }

      .stat {
        min-height: 136px;
      }

      .stat:hover,
      .stat:focus-visible,
      .card:hover,
      .card:focus-visible {
        border-color: var(--signal);
        box-shadow: var(--shadow);
        color: inherit;
      }

      .label {
        display: block;
        color: var(--muted);
        font-size: 0.84rem;
        font-weight: 800;
        text-transform: uppercase;
      }

      .value {
        display: block;
        margin-top: 8px;
        color: var(--ink);
        font-size: 1.55rem;
        font-weight: 850;
        line-height: 1.12;
      }

      .stat p {
        margin-top: 8px;
        font-size: 0.94rem;
      }

      .section {
        margin-top: 36px;
      }

      .section-head {
        display: flex;
        align-items: end;
        justify-content: space-between;
        gap: 24px;
        margin-bottom: 16px;
      }

      h2 {
        margin: 0;
        font-size: 2rem;
        line-height: 1.16;
        letter-spacing: 0;
      }

      .section-head p {
        max-width: 520px;
      }

      .doc-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .resource-grid {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }

      .card {
        min-height: 188px;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
      }

      .card h3 {
        margin: 0;
        color: var(--ink);
        font-size: 1.35rem;
        line-height: 1.2;
        letter-spacing: 0;
      }

      .card p {
        margin-top: 12px;
      }

      .card .meta {
        margin-top: 22px;
        color: var(--signal-dark);
        font-size: 0.9rem;
        font-weight: 800;
      }

      .panel {
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--surface-green);
        padding: 24px;
      }

      .panel strong {
        display: block;
        color: var(--ink);
        font-size: 1.2rem;
      }

      .panel p {
        margin-top: 8px;
      }

      .site-footer {
        background: var(--footer-bg);
        color: var(--footer-ink);
      }

      .site-footer .inner {
        min-height: 84px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        padding: 24px 0;
      }

      .site-footer a {
        color: rgba(255, 255, 255, 0.9);
      }

      @media (max-width: 900px) {
        .nav-wrap,
        .site-footer .inner {
          align-items: flex-start;
          flex-direction: column;
          justify-content: center;
          padding: 14px 0;
        }

        .hero,
        .status-grid,
        .doc-grid,
        .resource-grid {
          grid-template-columns: 1fr;
        }

        h1 {
          font-size: 2.6rem;
        }

        main {
          padding-top: 42px;
        }
      }

      @media (max-width: 520px) {
        .brand img {
          width: 210px;
        }

        h1 {
          font-size: 2.25rem;
        }

        .lead {
          font-size: 1.04rem;
        }

        .action-row {
          flex-direction: column;
        }

        .btn {
          width: 100%;
        }
      }
    </style>
  </head>
  <body>
    <header class="site-header">
      <div class="nav-wrap">
        <a class="brand" href="https://openhornet.com/" aria-label="OpenHornet website">
          <img src="software/oh_horiz.svg" alt="OpenHornet">
        </a>
        <nav class="nav-links" aria-label="Project links">
          <a href="https://openhornet.com/">Website</a>
          <a href="https://openhornet.com/start-here.html">Start Here</a>
          <a href="https://github.com/jrsteensen/OpenHornet">GitHub</a>
          <a href="https://discord.gg/openhornet">Discord</a>
          <a href="https://openhornet.com/donate.html">Donate</a>
        </nav>
      </div>
    </header>

    <main>
      <section class="hero">
        <div>
          <p class="eyebrow">Technical documentation</p>
          <h1>OpenHornet Documentation</h1>
          <p class="lead">Generated reference material for the OpenHornet hardware and software repositories, with quick paths for builders, contributors, and maintainers.</p>
          <div class="action-row" aria-label="Primary documentation links">
            <a class="btn signal" href="hardware/">Open hardware docs</a>
            <a class="btn secondary" href="software/">Open software docs</a>
            <a class="btn secondary" href="https://openhornet.com/start-here.html">Start the build</a>
          </div>
        </div>
        <aside class="panel" aria-label="Builder support">
          <strong>Need help while building?</strong>
          <p>The OpenHornet Discord is the fastest path to builder support, project discussion, and community troubleshooting.</p>
          <div class="action-row">
            <a class="btn secondary" href="https://discord.gg/openhornet">Join Discord</a>
            <a class="btn secondary" href="https://github.com/jrsteensen/OpenHornet/issues">File an issue</a>
          </div>
        </aside>
      </section>

      <section class="status-grid" aria-label="Project status">
        <a class="stat" href="hardware/">
          <span class="label">Hardware docs</span>
          <span class="value">__HARDWARE_VERSION__</span>
          <p>Generated hardware reference, tutorials, and release support material.</p>
        </a>
        <a class="stat" href="software/">
          <span class="label">Software docs</span>
          <span class="value">__SOFTWARE_VERSION__</span>
          <p>Firmware, sketches, libraries, classes, files, and API reference.</p>
        </a>
        <a class="stat" href="https://discord.gg/openhornet">
          <span class="label">Community</span>
          <span class="value">Discord</span>
          <p>Ask questions, share progress, and connect with other builders.</p>
        </a>
        <a class="stat" href="https://github.com/jrsteensen/OpenHornet/releases/latest">
          <span class="label">Latest release</span>
          <span class="value">Download</span>
          <p>Get the current OpenHornet hardware release package from GitHub.</p>
        </a>
      </section>

      <section class="section">
        <div class="section-head">
          <div>
            <p class="eyebrow">Documentation areas</p>
            <h2>Choose the reference you need.</h2>
          </div>
          <p>Hardware and software docs are generated from their source repositories during deployment.</p>
        </div>
        <div class="doc-grid">
          <a class="card" href="hardware/">
            <div>
              <h3>Hardware</h3>
              <p>Repository documentation, tutorials, MCAD reference links, ECAD notes, and builder-facing hardware material.</p>
            </div>
            <span class="meta">Open hardware documentation</span>
          </a>
          <a class="card" href="software/">
            <div>
              <h3>Software</h3>
              <p>Firmware, sketches, libraries, software manuals, flashing notes, and generated API documentation.</p>
            </div>
            <span class="meta">Open software documentation</span>
          </a>
        </div>
      </section>

      <section class="section">
        <div class="section-head">
          <div>
            <p class="eyebrow">Builder links</p>
            <h2>Move between docs, project, and support.</h2>
          </div>
        </div>
        <div class="resource-grid">
          <a class="card" href="https://openhornet.com/">
            <div>
              <h3>OpenHornet Website</h3>
              <p>Project overview, features, vendors, license notes, donation details, and build orientation.</p>
            </div>
            <span class="meta">Visit website</span>
          </a>
          <a class="card" href="https://github.com/jrsteensen/OpenHornet">
            <div>
              <h3>GitHub</h3>
              <p>Download releases, inspect source files, file issues, and follow development work.</p>
            </div>
            <span class="meta">Open repository</span>
          </a>
          <a class="card" href="https://openhornet.com/donate.html">
            <div>
              <h3>Donate</h3>
              <p>Support infrastructure, development, prototyping, and the documentation systems behind the project.</p>
            </div>
            <span class="meta">Support OpenHornet</span>
          </a>
        </div>
      </section>
    </main>

    <footer class="site-footer">
      <div class="inner">
        <p>Generated documentation for OpenHornet hardware and software.</p>
        <a href="https://openhornet.com/start-here.html">Start the build</a>
      </div>
    </footer>
  </body>
</html>
HTML

sed \
  -e "s|__HARDWARE_VERSION__|${hardware_version}|g" \
  -e "s|__SOFTWARE_VERSION__|${software_version}|g" \
  "${PUBLIC_DIR}/index.html" > "${PUBLIC_DIR}/index.html.tmp"
mv "${PUBLIC_DIR}/index.html.tmp" "${PUBLIC_DIR}/index.html"

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
