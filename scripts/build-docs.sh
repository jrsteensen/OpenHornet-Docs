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

normalize_github_blob_asset_urls() {
  local html_dir="$1"
  local file
  local tmp_file

  while IFS= read -r -d '' file; do
    tmp_file="${file}.tmp"
    sed \
      -e 's|src="https://github.com/jrsteensen/OpenHornet/blob/master/|src="https://raw.githubusercontent.com/jrsteensen/OpenHornet/master/|g' \
      -e 's|src="https://github.com/jrsteensen/OpenHornet/blob/main/|src="https://raw.githubusercontent.com/jrsteensen/OpenHornet/main/|g' \
      -e "s|src='https://github.com/jrsteensen/OpenHornet/blob/master/|src='https://raw.githubusercontent.com/jrsteensen/OpenHornet/master/|g" \
      -e "s|src='https://github.com/jrsteensen/OpenHornet/blob/main/|src='https://raw.githubusercontent.com/jrsteensen/OpenHornet/main/|g" \
      -e 's|src="https://github.com/jrsteensen/OpenHornet-Software/blob/master/|src="https://raw.githubusercontent.com/jrsteensen/OpenHornet-Software/master/|g' \
      -e 's|src="https://github.com/jrsteensen/OpenHornet-Software/blob/main/|src="https://raw.githubusercontent.com/jrsteensen/OpenHornet-Software/main/|g' \
      -e "s|src='https://github.com/jrsteensen/OpenHornet-Software/blob/master/|src='https://raw.githubusercontent.com/jrsteensen/OpenHornet-Software/master/|g" \
      -e "s|src='https://github.com/jrsteensen/OpenHornet-Software/blob/main/|src='https://raw.githubusercontent.com/jrsteensen/OpenHornet-Software/main/|g" \
      "${file}" > "${tmp_file}"
    mv "${tmp_file}" "${file}"
  done < <(find "${html_dir}" -type f -name '*.html' -print0)
}

doxygen_cache_bust_key() {
  local source_dir="$1"
  local docs_sha
  local source_sha
  local key

  docs_sha="$(git -C "${ROOT}" rev-parse --short=12 HEAD 2>/dev/null || true)"
  source_sha="$(git -C "${source_dir}" rev-parse --short=12 HEAD 2>/dev/null || true)"
  key="${docs_sha:-local}-${source_sha:-source}"

  printf '%s' "${key}" | tr -c 'A-Za-z0-9._-' '-'
}

version_doxygen_asset_urls() {
  local html_dir="$1"
  local cache_bust="$2"
  local query="?v=${cache_bust}"
  local file
  local tmp_file

  while IFS= read -r -d '' file; do
    tmp_file="${file}.tmp"
    sed \
      -e "s|\\(src=\"[^\"]*\\.js\\)\"|\\1${query}\"|g" \
      -e "s|\\(href=\"[^\"]*\\.css\\)\"|\\1${query}\"|g" \
      "${file}" > "${tmp_file}"
    mv "${tmp_file}" "${file}"
  done < <(find "${html_dir}" -type f -name '*.html' -print0)

  if [[ -f "${html_dir}/navtree.js" ]]; then
    tmp_file="${html_dir}/navtree.js.tmp"
    sed \
      -e "s|script.src = scriptName+'\\.js';|script.src = scriptName+'.js${query}';|g" \
      "${html_dir}/navtree.js" > "${tmp_file}"
    mv "${tmp_file}" "${html_dir}/navtree.js"
  fi

  if [[ -f "${html_dir}/search/search.js" ]]; then
    tmp_file="${html_dir}/search/search.js.tmp"
    sed \
      -e "s|scriptTag.src = url;|scriptTag.src = url + '${query}';|g" \
      "${html_dir}/search/search.js" > "${tmp_file}"
    mv "${tmp_file}" "${html_dir}/search/search.js"
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
current_year="$(date +%Y)"

echo "Building software docs (${software_version})"
rm -rf "${SOFTWARE_SRC}/docs/html"
(
  cd "${SOFTWARE_SRC}/docs"
  PROJECT_VERSION="${software_version}" "${DOXYGEN_BIN}" Doxyfile
)
require_path "${SOFTWARE_SRC}/docs/html/index.html"
normalize_github_blob_asset_urls "${SOFTWARE_SRC}/docs/html"
version_doxygen_asset_urls "${SOFTWARE_SRC}/docs/html" "$(doxygen_cache_bust_key "${SOFTWARE_SRC}")"
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
normalize_github_blob_asset_urls "${HARDWARE_SRC}/docs/html"
version_doxygen_asset_urls "${HARDWARE_SRC}/docs/html" "$(doxygen_cache_bust_key "${HARDWARE_SRC}")"
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
    <script>
      (function () {
        const storageKey = "openhornet-theme";
        const root = document.documentElement;

        function getStoredTheme() {
          try {
            const theme = window.localStorage.getItem(storageKey);
            return theme === "dark" || theme === "light" ? theme : "";
          } catch (error) {
            return "";
          }
        }

        const theme = getStoredTheme() || "light";
        root.dataset.theme = theme;
        root.style.colorScheme = theme;
      })();
    </script>
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
        --link-underline: rgba(213, 167, 44, 0.8);
        --footer-bg: #171b1f;
        --footer-ink: rgba(255, 255, 255, 0.78);
        --footer-link: rgba(255, 255, 255, 0.88);
        --footer-muted: rgba(255, 255, 255, 0.62);
        --footer-line: rgba(255, 255, 255, 0.12);
        --shadow: 0 18px 55px rgba(23, 27, 31, 0.12);
        --card-hover-shadow: 0 16px 32px rgba(23, 27, 31, 0.08);
        --header-bg: rgba(255, 255, 255, 0.92);
        --header-line: rgba(217, 223, 213, 0.9);
        --logo-filter: none;
        --radius: 8px;
      }

      :root[data-theme="dark"] {
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
        --link-underline: rgba(228, 187, 78, 0.82);
        --footer-bg: #0b0f10;
        --footer-ink: rgba(255, 255, 255, 0.76);
        --footer-link: rgba(255, 255, 255, 0.9);
        --footer-muted: rgba(255, 255, 255, 0.58);
        --footer-line: rgba(255, 255, 255, 0.14);
        --shadow: 0 18px 55px rgba(0, 0, 0, 0.45);
        --card-hover-shadow: 0 16px 32px rgba(0, 0, 0, 0.35);
        --header-bg: rgba(18, 22, 23, 0.92);
        --header-line: rgba(48, 58, 56, 0.9);
        --logo-filter: brightness(0) invert(1);
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
        transition: background-color 180ms ease, color 180ms ease;
      }

      img {
        display: block;
        max-width: 100%;
      }

      a {
        color: inherit;
        text-decoration-color: var(--link-underline);
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

      .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
        border: 0;
      }

      .site-header {
        position: sticky;
        top: 0;
        z-index: 10;
        border-bottom: 1px solid var(--header-line);
        background: var(--header-bg);
        backdrop-filter: blur(16px);
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

      .nav-controls {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        flex-wrap: wrap;
        gap: 10px;
      }

      .theme-toggle {
        flex: 0 0 auto;
        width: 54px;
        height: 36px;
        display: inline-grid;
        place-items: center;
        padding: 0;
        border: 1px solid var(--line);
        border-radius: 999px;
        background: var(--surface);
        color: var(--ink);
        cursor: pointer;
        transition: background-color 180ms ease, border-color 180ms ease, color 180ms ease, transform 180ms ease;
      }

      .theme-toggle:hover {
        border-color: var(--signal);
        transform: translateY(-1px);
      }

      .theme-toggle__track {
        position: relative;
        display: block;
        width: 44px;
        height: 24px;
      }

      .theme-toggle__icon,
      .theme-toggle__thumb {
        position: absolute;
        top: 50%;
        border-radius: 999px;
        transform: translateY(-50%);
      }

      .theme-toggle__icon {
        width: 14px;
        height: 14px;
        opacity: 0.6;
        transition: opacity 180ms ease;
      }

      .theme-toggle__sun {
        left: 5px;
        background: currentColor;
        box-shadow:
          0 -5px 0 -4px currentColor,
          0 5px 0 -4px currentColor,
          5px 0 0 -4px currentColor,
          -5px 0 0 -4px currentColor;
      }

      .theme-toggle__moon {
        right: 5px;
        background: transparent;
        box-shadow: inset -5px 0 0 currentColor;
      }

      .theme-toggle__thumb {
        left: 2px;
        z-index: 1;
        width: 20px;
        height: 20px;
        background: var(--signal);
        box-shadow: 0 2px 8px rgba(23, 27, 31, 0.22);
        transition: transform 180ms ease, background-color 180ms ease;
      }

      :root[data-theme="dark"] .theme-toggle__thumb {
        transform: translate(20px, -50%);
      }

      :root[data-theme="dark"] .theme-toggle__moon,
      :root[data-theme="light"] .theme-toggle__sun {
        opacity: 0.95;
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

      .social-links {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        flex-wrap: wrap;
        gap: 6px;
      }

      .social-link {
        width: 40px;
        height: 40px;
        display: inline-grid;
        place-items: center;
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--surface-soft);
        color: var(--ink);
        text-decoration: none;
        transition: background-color 180ms ease, border-color 180ms ease, color 180ms ease, transform 180ms ease;
      }

      .social-link:hover,
      .social-link:focus-visible {
        border-color: var(--ink);
        background: var(--ink);
        color: var(--surface);
        transform: translateY(-1px);
      }

      .social-link svg {
        width: 19px;
        height: 19px;
        fill: currentColor;
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
        box-shadow: var(--card-hover-shadow);
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
        display: grid;
        gap: 18px;
        padding: 24px 0;
      }

      .site-footer a {
        color: var(--footer-link);
      }

      .site-footer p {
        color: inherit;
      }

      .footer-main {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
      }

      .footer-bottom {
        margin: 0;
        padding-top: 18px;
        border-top: 1px solid var(--footer-line);
        color: var(--footer-muted);
        font-size: 0.92rem;
      }

      @media (max-width: 900px) {
        .nav-wrap {
          align-items: flex-start;
          flex-direction: column;
          justify-content: center;
          padding: 14px 0;
        }

        .site-footer .inner {
          padding: 24px 0;
        }

        .footer-main {
          align-items: flex-start;
          flex-direction: column;
        }

        .nav-controls {
          align-items: flex-start;
          justify-content: flex-start;
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

        .nav-links,
        .social-links {
          justify-content: flex-start;
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
        <div class="nav-controls">
          <nav class="nav-links" aria-label="Project links">
            <a href="https://openhornet.com/">Website</a>
            <a href="https://openhornet.com/start-here.html">Start Here</a>
            <a href="https://github.com/jrsteensen/OpenHornet">GitHub</a>
            <a href="https://discord.gg/openhornet">Discord</a>
            <a href="https://openhornet.com/donate.html">Donate</a>
          </nav>
          <button class="theme-toggle" type="button" data-theme-toggle aria-label="Switch to dark mode" aria-pressed="false" title="Switch to dark mode">
            <span class="theme-toggle__track" aria-hidden="true">
              <span class="theme-toggle__icon theme-toggle__sun"></span>
              <span class="theme-toggle__icon theme-toggle__moon"></span>
              <span class="theme-toggle__thumb"></span>
            </span>
            <span class="sr-only" data-theme-toggle-label>Switch to dark mode</span>
          </button>
          <nav class="social-links" aria-label="Social links">
            <a class="social-link" href="https://discord.gg/openhornet" target="_blank" rel="noopener" aria-label="Join OpenHornet on Discord">
              <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                <path d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z"></path>
              </svg>
              <span class="sr-only">Discord</span>
            </a>
            <a class="social-link" href="https://www.youtube.com/@OpenHornet" target="_blank" rel="noopener" aria-label="OpenHornet on YouTube">
              <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"></path>
              </svg>
              <span class="sr-only">YouTube</span>
            </a>
            <a class="social-link" href="https://www.facebook.com/profile.php?id=100092714572837" target="_blank" rel="noopener" aria-label="OpenHornet on Facebook">
              <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                <path d="M9.101 23.691v-7.98H6.627v-3.667h2.474v-1.58c0-4.085 1.848-5.978 5.858-5.978.401 0 .955.042 1.468.103a8.68 8.68 0 011.141.195v3.325a8.623 8.623 0 00-.653-.036 26.805 26.805 0 00-.733-.009c-.707 0-1.259.096-1.675.309a1.686 1.686 0 00-.679.622c-.258.42-.374.995-.374 1.752v1.297h3.919l-.386 2.103-.287 1.564h-3.246v8.245C19.396 23.238 24 18.179 24 12.044c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.628 3.874 10.35 9.101 11.647Z"></path>
              </svg>
              <span class="sr-only">Facebook</span>
            </a>
          </nav>
        </div>
      </div>
    </header>

    <main>
      <section class="hero">
        <div>
          <p class="eyebrow">Technical documentation</p>
          <h1>OpenHornet Documentation</h1>
          <p class="lead">Generated reference material for the OpenHornet hardware and software repositories, including tutorials, software guides, API references, and more.</p>
<!--          <div class="action-row" aria-label="Primary documentation links">
            <a class="btn signal" href="hardware/">Open hardware docs</a>
            <a class="btn secondary" href="software/">Open software docs</a>
            <a class="btn secondary" href="https://openhornet.com/start-here.html">Start the build</a>
          </div> -->
        </div>
        <aside class="panel" aria-label="Builder support">
          <strong>Need help while building?</strong>
          <p>The OpenHornet Discord is the fastest path to builder support, project discussion, and community troubleshooting.</p>
          <div class="action-row">
            <a class="btn secondary" href="https://discord.gg/openhornet">Join Discord</a>
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
        <a class="stat" href="https://github.com/jrsteensen/OpenHornet/issues">
          <span class="label">GitHub</span>
          <span class="value">Hardware issues</span>
          <p>Report hardware issues and track their resolution on GitHub.</p>
        </a>
        <a class="stat" href="https://github.com/jrsteensen/OpenHornet-Software/issues">
          <span class="label">GitHub</span>
          <span class="value">Software issues</span>
          <p>Report software issues and track their resolution on GitHub.</p>
        </a>
      </section>

<!--      <section class="section">
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
      </section> -->

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
        <div class="footer-main">
          <p>Generated documentation for OpenHornet hardware and software.</p>
          <a href="https://openhornet.com/start-here.html">Start the build</a>
        </div>
        <p class="footer-bottom">
          Copyright &copy; 2016 - __CURRENT_YEAR__ OpenHornet. OpenHornet works are licensed under
          <a href="https://creativecommons.org/licenses/by-nc-sa/4.0/">CC BY-NC-SA 4.0</a>.
        </p>
      </div>
    </footer>
    <script>
      (function () {
        const storageKey = "openhornet-theme";
        const toggles = Array.from(document.querySelectorAll("[data-theme-toggle]"));

        function getStoredTheme() {
          try {
            const theme = window.localStorage.getItem(storageKey);
            return theme === "dark" || theme === "light" ? theme : "";
          } catch (error) {
            return "";
          }
        }

        function storeTheme(theme) {
          try {
            window.localStorage.setItem(storageKey, theme);
          } catch (error) {
            // Theme persistence is optional; the active page can still update.
          }
        }

        function applyTheme(theme) {
          const resolvedTheme = theme === "dark" ? "dark" : "light";
          document.documentElement.dataset.theme = resolvedTheme;
          document.documentElement.style.colorScheme = resolvedTheme;
          return resolvedTheme;
        }

        function syncThemeControls(theme) {
          const label = theme === "dark" ? "Switch to light mode" : "Switch to dark mode";

          toggles.forEach((toggle) => {
            toggle.setAttribute("aria-label", label);
            toggle.setAttribute("aria-pressed", String(theme === "dark"));
            toggle.setAttribute("title", label);

            const textLabel = toggle.querySelector("[data-theme-toggle-label]");
            if (textLabel) {
              textLabel.textContent = label;
            }
          });
        }

        if (!toggles.length) {
          return;
        }

        let activeTheme = applyTheme(getStoredTheme() || "light");
        syncThemeControls(activeTheme);

        toggles.forEach((toggle) => {
          toggle.addEventListener("click", () => {
            activeTheme = activeTheme === "dark" ? "light" : "dark";
            storeTheme(activeTheme);
            applyTheme(activeTheme);
            syncThemeControls(activeTheme);
          });
        });
      })();
    </script>
  </body>
</html>
HTML

sed \
  -e "s|__HARDWARE_VERSION__|${hardware_version}|g" \
  -e "s|__SOFTWARE_VERSION__|${software_version}|g" \
  -e "s|__CURRENT_YEAR__|${current_year}|g" \
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
