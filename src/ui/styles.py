"""
UI Styles for Crop Maturity & Health Assessment
Theme tokens, typography, and all CSS (including animations).

To change the colour scheme, edit THEME below. Every colour in the app
is read from these values.
"""

import streamlit as st


# ============================================================================
# THEME — "Aurora" (deep navy + teal-to-sky)
# ============================================================================
THEME = {
    "bg": "#060B18",            # page background
    "bg_soft": "#0A1122",       # sidebar background
    "surface": "#0D1526",       # cards
    "surface_2": "#111C33",     # inputs, nested panels
    "border": "#1E2A44",        # hairlines
    "border_strong": "#2B3B5E", # hover borders
    "text": "#E6F0FF",          # primary text
    "text_muted": "#7C8BA8",    # secondary text
    "text_faint": "#4F5D7A",    # captions, labels
    "accent": "#2DD4BF",        # teal
    "accent_2": "#38BDF8",      # sky
    "accent_3": "#818CF8",      # indigo (aurora glow only)
    "success": "#34D399",
    "warning": "#FBBF24",
    "danger": "#FB7185",
}

# Section themes: same layout and animations, different colours.
# "home" is the Aurora theme above; the others replace some of its values.
SECTION_THEMES = {
    "home": {},
    "mango": {                  # dark amber / gold
        "bg": "#0D0A04",
        "bg_soft": "#141007",
        "surface": "#17120A",
        "surface_2": "#201A0E",
        "border": "#33291A",
        "border_strong": "#4D3E22",
        "text": "#FFF5E1",
        "text_muted": "#A99A7C",
        "text_faint": "#716552",
        "accent": "#F5B731",    # gold
        "accent_2": "#F59E0B",  # amber
        "accent_3": "#FB923C",  # orange (glow only)
    },
    "leaf": {                   # dark forest green
        "bg": "#040F09",
        "bg_soft": "#07150D",
        "surface": "#0A1A11",
        "surface_2": "#0F2418",
        "border": "#1A3525",
        "border_strong": "#285238",
        "text": "#E6FFEF",
        "text_muted": "#7FA38D",
        "text_faint": "#4F7360",
        "accent": "#4ADE80",    # green
        "accent_2": "#A3E635",  # lime
        "accent_3": "#2DD4BF",  # teal (glow only)
    },
}

FONT_HEADING = "Syne"
FONT_BODY = "Manrope"


def _rgb(hex_colour: str) -> str:
    """'#2DD4BF' -> '45, 212, 191'."""
    h = hex_colour.lstrip("#")
    return ", ".join(str(int(h[i:i + 2], 16)) for i in (0, 2, 4))


def _root_vars() -> str:
    """Build the :root block from THEME so colours live in one place."""
    lines = [f"--cv-{k.replace('_', '-')}: {v};" for k, v in THEME.items()]
    # "r, g, b" copies so the CSS can use rgba(var(--cv-accent-rgb), 0.2)
    lines += [f"--cv-{k.replace('_', '-')}-rgb: {_rgb(v)};" for k, v in THEME.items()]
    lines.append(f"--cv-font-heading: '{FONT_HEADING}', 'Segoe UI', sans-serif;")
    lines.append(f"--cv-font-body: '{FONT_BODY}', 'Segoe UI', sans-serif;")
    return ":root {" + "".join(lines) + "}"


_CSS = """
@import url('https://fonts.googleapis.com/css2?family=Syne:wght@500;600;700;800&family=Manrope:wght@400;500;600;700&display=swap');

@property --cv-angle {
    syntax: '<angle>';
    initial-value: 0deg;
    inherits: false;
}

/* ==================== BASE ==================== */
html, body, .stApp, [data-testid="stAppViewContainer"], [data-testid="stSidebar"] {
    font-family: var(--cv-font-body);
    color: var(--cv-text);
}

/* Keep Streamlit's icon font intact (prevents stray "keyboard_..." text) */
[data-testid="stIconMaterial"], .material-symbols-rounded {
    font-family: 'Material Symbols Rounded' !important;
}

.stApp {
    background-color: var(--cv-bg);
    background-image:
        radial-gradient(60rem 30rem at 10% -10%, rgba(var(--cv-accent-rgb), 0.10), transparent 60%),
        radial-gradient(50rem 28rem at 95% 0%, rgba(var(--cv-accent-2-rgb), 0.09), transparent 60%),
        radial-gradient(40rem 30rem at 60% 110%, rgba(var(--cv-accent-3-rgb), 0.06), transparent 60%);
    background-attachment: fixed;
}

/* Faint dot grid over the page */
.stApp::before {
    content: "";
    position: fixed;
    inset: 0;
    pointer-events: none;
    background-image: radial-gradient(rgba(var(--cv-text-rgb), 0.05) 1px, transparent 1px);
    background-size: 28px 28px;
    mask-image: linear-gradient(180deg, rgba(0,0,0,0.9), transparent 70%);
    -webkit-mask-image: linear-gradient(180deg, rgba(0,0,0,0.9), transparent 70%);
    z-index: 0;
}

[data-testid="stHeader"] {
    background: transparent !important;
}

[data-testid="stMainBlockContainer"] {
    padding: 2.5rem 3rem 2rem 3rem;
    max-width: 1280px;
}

h1, h2, h3, h4 {
    font-family: var(--cv-font-heading) !important;
    color: var(--cv-text);
    letter-spacing: -0.02em;
}

p { color: var(--cv-text-muted); line-height: 1.65; }

/* ==================== SIDEBAR ==================== */
[data-testid="stSidebar"] {
    background: linear-gradient(180deg, var(--cv-bg-soft) 0%, var(--cv-bg) 100%) !important;
    border-right: 1px solid var(--cv-border);
}

[data-testid="stSidebarUserContent"] {
    padding-top: 0.5rem;
}

/* ---------- Sidebar collapse control (kept from approved version) ---------- */
[data-testid="stSidebarCollapseButton"] {
    display: block !important;
}

[data-testid="stSidebarCollapseButton"] button,
button[aria-label*="Close sidebar"],
button[aria-label*="Open sidebar"],
button[title*="Close sidebar"],
button[title*="Open sidebar"] {
    position: relative !important;
    display: flex !important;
    align-items: center !important;
    justify-content: center !important;
    width: 2.25rem !important;
    min-width: 2.25rem !important;
    height: 2.25rem !important;
    min-height: 2.25rem !important;
    padding: 0 !important;
    margin: 0 !important;
    border: 1px solid var(--cv-border) !important;
    border-radius: 10px !important;
    background: rgba(var(--cv-surface-rgb), 0.8) !important;
    color: transparent !important;
    font-size: 0 !important;
    line-height: 0 !important;
    box-shadow: none !important;
    z-index: 999999 !important;
    transition: background 0.25s ease, border-color 0.25s ease !important;
}

[data-testid="stSidebarCollapseButton"] button:hover,
button[aria-label*="Close sidebar"]:hover,
button[aria-label*="Open sidebar"]:hover,
button[title*="Close sidebar"]:hover,
button[title*="Open sidebar"]:hover {
    background: rgba(var(--cv-accent-rgb), 0.12) !important;
    border-color: rgba(var(--cv-accent-rgb), 0.45) !important;
}

[data-testid="stSidebarCollapseButton"] button > span,
[data-testid="stSidebarCollapseButton"] button > div,
[data-testid="stSidebarCollapseButton"] button > svg,
button[aria-label*="Close sidebar"] > span,
button[aria-label*="Open sidebar"] > span {
    display: none !important;
}

[data-testid="stSidebarCollapseButton"] button::before,
button[aria-label*="Close sidebar"]::before,
button[aria-label*="Open sidebar"]::before {
    content: "\\2039";
    display: block !important;
    color: var(--cv-text) !important;
    font-family: Arial, sans-serif !important;
    font-size: 1.65rem !important;
    font-weight: 400 !important;
    line-height: 1 !important;
}

button[aria-label*="Open sidebar"]::before {
    content: "\\203A";
}

/* ---------- Brand block ---------- */
.cv-brand {
    display: flex;
    align-items: center;
    gap: 0.8rem;
    padding: 0.25rem 0.25rem 1.5rem 0.25rem;
    border-bottom: 1px solid var(--cv-border);
    margin-bottom: 1.5rem;
    animation: cvRise 0.6s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

.cv-logo {
    position: relative;
    width: 40px;
    height: 40px;
    border-radius: 12px;
    background: linear-gradient(135deg, var(--cv-accent), var(--cv-accent-2));
    box-shadow: 0 0 24px rgba(var(--cv-accent-rgb), 0.35);
    flex-shrink: 0;
    overflow: hidden;
}

.cv-logo::before {
    content: "";
    position: absolute;
    inset: 9px;
    border-radius: 50% 0 50% 0;
    background: var(--cv-bg);
    transform: rotate(0deg);
}

.cv-logo::after {
    content: "";
    position: absolute;
    left: 0; right: 0;
    height: 2px;
    background: rgba(255, 255, 255, 0.85);
    box-shadow: 0 0 8px #fff;
    animation: cvScan 2.8s ease-in-out infinite;
}

.cv-brand-name {
    font-family: var(--cv-font-heading);
    font-weight: 800;
    font-size: 1.35rem;
    color: var(--cv-text);
    letter-spacing: -0.02em;
    line-height: 1.1;
}

.cv-brand-sub {
    font-size: 0.68rem;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--cv-text-faint);
    margin-top: 0.2rem;
}

.cv-side-label {
    font-size: 0.68rem;
    font-weight: 700;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--cv-text-faint);
    margin: 0 0 0.6rem 0.35rem;
}

/* ---------- Navigation (styled st.radio) ---------- */
[data-testid="stSidebar"] [data-testid="stRadio"] [role="radiogroup"] {
    gap: 0.3rem;
    counter-reset: cvnav;
    width: 100%;
}

[data-testid="stSidebar"] [data-testid="stRadio"] label {
    position: relative;
    width: 100%;
    margin: 0 !important;
    padding: 0.7rem 0.85rem !important;
    border-radius: 12px;
    border: 1px solid transparent;
    cursor: pointer;
    counter-increment: cvnav;
    transition: background 0.25s ease, border-color 0.25s ease, transform 0.25s ease;
    animation: cvRise 0.5s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

[data-testid="stSidebar"] [data-testid="stRadio"] label:nth-child(1) { animation-delay: 0.05s; }
[data-testid="stSidebar"] [data-testid="stRadio"] label:nth-child(2) { animation-delay: 0.10s; }
[data-testid="stSidebar"] [data-testid="stRadio"] label:nth-child(3) { animation-delay: 0.15s; }
[data-testid="stSidebar"] [data-testid="stRadio"] label:nth-child(4) { animation-delay: 0.20s; }
[data-testid="stSidebar"] [data-testid="stRadio"] label:nth-child(5) { animation-delay: 0.25s; }
[data-testid="stSidebar"] [data-testid="stRadio"] label:nth-child(6) { animation-delay: 0.30s; }

/* hide the radio circle */
[data-testid="stSidebar"] [data-testid="stRadio"] label > div:first-child {
    display: none !important;
}

[data-testid="stSidebar"] [data-testid="stRadio"] label::before {
    content: counter(cvnav, decimal-leading-zero);
    font-family: var(--cv-font-heading);
    font-size: 0.72rem;
    font-weight: 700;
    color: var(--cv-text-faint);
    margin-right: 0.75rem;
    transition: color 0.25s ease;
}

[data-testid="stSidebar"] [data-testid="stRadio"] label p {
    font-size: 0.92rem;
    font-weight: 600;
    color: var(--cv-text-muted);
    transition: color 0.25s ease;
}

[data-testid="stSidebar"] [data-testid="stRadio"] label:hover {
    background: rgba(var(--cv-text-rgb), 0.04);
    transform: translateX(3px);
}

[data-testid="stSidebar"] [data-testid="stRadio"] label:hover p {
    color: var(--cv-text);
}

[data-testid="stSidebar"] [data-testid="stRadio"] label:has(input:checked) {
    background: linear-gradient(90deg, rgba(var(--cv-accent-rgb), 0.14), rgba(var(--cv-accent-2-rgb), 0.04));
    border-color: rgba(var(--cv-accent-rgb), 0.30);
}

[data-testid="stSidebar"] [data-testid="stRadio"] label:has(input:checked)::after {
    content: "";
    position: absolute;
    left: -1px;
    top: 22%;
    bottom: 22%;
    width: 3px;
    border-radius: 3px;
    background: linear-gradient(180deg, var(--cv-accent), var(--cv-accent-2));
    box-shadow: 0 0 12px var(--cv-accent);
}

[data-testid="stSidebar"] [data-testid="stRadio"] label:has(input:checked)::before,
[data-testid="stSidebar"] [data-testid="stRadio"] label:has(input:checked) p {
    color: var(--cv-text);
}

/* ---------- Sidebar session card ---------- */
.cv-session {
    margin-top: 1.75rem;
    padding: 1rem;
    border-radius: 14px;
    background: rgba(var(--cv-surface-rgb), 0.7);
    border: 1px solid var(--cv-border);
    animation: cvRise 0.6s 0.35s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

.cv-session-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 0.82rem;
    padding: 0.4rem 0;
    color: var(--cv-text-muted);
}

.cv-session-row + .cv-session-row {
    border-top: 1px dashed var(--cv-border);
}

.cv-session-row b {
    color: var(--cv-text);
    font-weight: 600;
    max-width: 60%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

/* ==================== PAGE HEADER ==================== */
.cv-eyebrow {
    display: inline-flex;
    align-items: center;
    gap: 0.55rem;
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--cv-accent);
    padding: 0.4rem 0.8rem;
    border-radius: 999px;
    background: rgba(var(--cv-accent-rgb), 0.08);
    border: 1px solid rgba(var(--cv-accent-rgb), 0.22);
    animation: cvRise 0.6s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

.cv-title {
    font-family: var(--cv-font-heading);
    font-weight: 800;
    font-size: clamp(2.2rem, 4.4vw, 3.6rem);
    line-height: 1.02;
    letter-spacing: -0.035em;
    margin: 1rem 0 0.75rem 0;
    color: var(--cv-text);
    animation: cvRise 0.7s 0.08s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

.cv-title .cv-grad {
    background: linear-gradient(100deg, var(--cv-accent) 0%, var(--cv-accent-2) 50%, var(--cv-accent-3) 100%);
    -webkit-background-clip: text;
    background-clip: text;
    -webkit-text-fill-color: transparent;
}

.cv-title.cv-title-sm {
    font-size: clamp(1.9rem, 3.2vw, 2.6rem);
}

.cv-subtitle {
    font-size: 1rem;
    color: var(--cv-text-muted);
    max-width: 36rem;
    margin: 0 0 2rem 0;
    animation: cvRise 0.7s 0.16s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

/* ==================== STATUS CHIPS ==================== */
.cv-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 0.6rem;
    margin: -0.75rem 0 2rem 0;
    animation: cvRise 0.7s 0.22s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

.cv-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--cv-text-muted);
    padding: 0.45rem 0.85rem;
    border-radius: 999px;
    background: var(--cv-surface);
    border: 1px solid var(--cv-border);
}

.cv-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--cv-text-faint);
    flex-shrink: 0;
}

.cv-dot.on {
    background: var(--cv-accent);
    box-shadow: 0 0 0 0 rgba(var(--cv-accent-rgb), 0.6);
    animation: cvPulse 2s ease-out infinite;
}

.cv-dot.wait {
    background: var(--cv-warning);
}

/* ==================== SECTION LABEL ==================== */
.cv-section {
    display: flex;
    align-items: center;
    gap: 0.9rem;
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--cv-text-faint);
    margin: 2.25rem 0 1rem 0;
}

.cv-section::after {
    content: "";
    flex: 1;
    height: 1px;
    background: linear-gradient(90deg, var(--cv-border), transparent);
}

/* ==================== CARDS ==================== */
/* HTML cards and keyed st.container cards share one look */
.cv-card,
div[class*="st-key-card_"] {
    position: relative;
    background: linear-gradient(180deg, rgba(var(--cv-surface-2-rgb), 0.75) 0%, rgba(var(--cv-surface-rgb), 0.75) 100%);
    border: 1px solid var(--cv-border);
    border-radius: 18px;
    padding: 1.4rem 1.5rem;
    backdrop-filter: blur(8px);
    transition: transform 0.35s cubic-bezier(0.2, 0.8, 0.2, 1), border-color 0.35s ease, box-shadow 0.35s ease;
    animation: cvRise 0.7s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

/* Rotating glow border on hover */
.cv-card::before,
div[class*="st-key-card_"]::before {
    content: "";
    position: absolute;
    inset: -1px;
    border-radius: inherit;
    padding: 1px;
    background: conic-gradient(from var(--cv-angle), transparent 0deg, var(--cv-accent) 60deg, var(--cv-accent-2) 120deg, transparent 180deg, transparent 360deg);
    -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
    -webkit-mask-composite: xor;
    mask: linear-gradient(#000 0 0) content-box exclude, linear-gradient(#000 0 0);
    opacity: 0;
    transition: opacity 0.4s ease;
    pointer-events: none;
    animation: cvSpin 4s linear infinite;
}

.cv-card:hover,
div[class*="st-key-card_"]:hover {
    transform: translateY(-3px);
    box-shadow: 0 18px 40px -18px rgba(var(--cv-accent-rgb), 0.25), 0 0 0 1px rgba(var(--cv-accent-rgb), 0.05);
}

.cv-card:hover::before,
div[class*="st-key-card_"]:hover::before {
    opacity: 1;
}

.cv-card-head {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin-bottom: 1rem;
}

.cv-step {
    font-family: var(--cv-font-heading);
    font-weight: 700;
    font-size: 0.75rem;
    color: var(--cv-bg);
    background: linear-gradient(135deg, var(--cv-accent), var(--cv-accent-2));
    width: 28px;
    height: 28px;
    border-radius: 8px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
}

.cv-card-title {
    font-family: var(--cv-font-heading);
    font-weight: 700;
    font-size: 1.1rem;
    color: var(--cv-text);
    letter-spacing: -0.01em;
}

.cv-card-meta {
    margin-left: auto;
    font-size: 0.75rem;
    color: var(--cv-text-faint);
    font-weight: 600;
}

/* Stagger entrance of columns */
[data-testid="stColumn"]:nth-child(1) > div { animation-delay: 0.05s; }
[data-testid="stColumn"]:nth-child(2) > div { animation-delay: 0.12s; }
[data-testid="stColumn"]:nth-child(3) > div { animation-delay: 0.19s; }
[data-testid="stColumn"]:nth-child(4) > div { animation-delay: 0.26s; }
[data-testid="stColumn"]:nth-child(2) .cv-card,
[data-testid="stColumn"]:nth-child(2) div[class*="st-key-card_"] { animation-delay: 0.10s; }
[data-testid="stColumn"]:nth-child(3) .cv-card,
[data-testid="stColumn"]:nth-child(3) div[class*="st-key-card_"] { animation-delay: 0.18s; }
[data-testid="stColumn"]:nth-child(4) .cv-card,
[data-testid="stColumn"]:nth-child(4) div[class*="st-key-card_"] { animation-delay: 0.26s; }

/* ==================== STAT TILES ==================== */
.cv-stat {
    position: relative;
    overflow: hidden;
    background: var(--cv-surface);
    border: 1px solid var(--cv-border);
    border-radius: 16px;
    padding: 1.1rem 1.2rem 1.2rem 1.2rem;
    transition: transform 0.35s cubic-bezier(0.2, 0.8, 0.2, 1), border-color 0.35s ease;
    animation: cvRise 0.7s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

.cv-stat::after {
    content: "";
    position: absolute;
    left: 0; right: 0; top: 0;
    height: 2px;
    background: linear-gradient(90deg, transparent, var(--cv-accent), var(--cv-accent-2), transparent);
    transform: translateX(-100%);
    transition: transform 0.7s cubic-bezier(0.2, 0.8, 0.2, 1);
}

.cv-stat:hover {
    transform: translateY(-3px);
    border-color: var(--cv-border-strong);
}

.cv-stat:hover::after {
    transform: translateX(0);
}

.cv-stat-label {
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: var(--cv-text-faint);
}

.cv-stat-value {
    font-family: var(--cv-font-heading);
    font-weight: 700;
    font-size: 1.7rem;
    color: var(--cv-text);
    margin: 0.45rem 0 0.2rem 0;
    letter-spacing: -0.02em;
    font-variant-numeric: tabular-nums;
}

.cv-stat-value.pending {
    color: var(--cv-text-faint);
}

.cv-stat-sub {
    font-size: 0.8rem;
    color: var(--cv-text-muted);
}

.cv-stat.tone-accent .cv-stat-value { color: var(--cv-accent); }
.cv-stat.tone-warning .cv-stat-value { color: var(--cv-warning); }
.cv-stat.tone-danger .cv-stat-value { color: var(--cv-danger); }

/* ==================== IMAGE SLOTS ==================== */
.cv-slot-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.75rem;
}

.cv-slot-title {
    font-family: var(--cv-font-heading);
    font-weight: 700;
    font-size: 0.98rem;
    color: var(--cv-text);
}

.cv-tag {
    font-size: 0.68rem;
    font-weight: 700;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    padding: 0.25rem 0.55rem;
    border-radius: 6px;
    color: var(--cv-text-faint);
    background: var(--cv-surface-2);
    border: 1px solid var(--cv-border);
}

.cv-tag.live {
    color: var(--cv-accent);
    background: rgba(var(--cv-accent-rgb), 0.08);
    border-color: rgba(var(--cv-accent-rgb), 0.25);
}

/* Empty slot: grid + shimmer sweep */
.cv-placeholder {
    position: relative;
    overflow: hidden;
    aspect-ratio: 4 / 3;
    border-radius: 12px;
    border: 1px dashed var(--cv-border-strong);
    background-color: var(--cv-surface-2);
    background-image:
        linear-gradient(rgba(var(--cv-text-rgb), 0.035) 1px, transparent 1px),
        linear-gradient(90deg, rgba(var(--cv-text-rgb), 0.035) 1px, transparent 1px);
    background-size: 22px 22px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 0.6rem;
    color: var(--cv-text-faint);
    font-size: 0.82rem;
    font-weight: 600;
}

.cv-placeholder::after {
    content: "";
    position: absolute;
    inset: 0;
    background: linear-gradient(105deg, transparent 30%, rgba(var(--cv-accent-2-rgb), 0.08) 45%, rgba(var(--cv-accent-rgb), 0.12) 50%, transparent 65%);
    transform: translateX(-100%);
    animation: cvShimmer 2.6s ease-in-out infinite;
}

.cv-frame {
    width: 44px;
    height: 34px;
    border-radius: 6px;
    border: 2px solid var(--cv-border-strong);
    position: relative;
}

.cv-frame::before {
    content: "";
    position: absolute;
    left: 6px; bottom: 5px;
    width: 0; height: 0;
    border-left: 8px solid transparent;
    border-right: 8px solid transparent;
    border-bottom: 12px solid var(--cv-border-strong);
}

.cv-frame::after {
    content: "";
    position: absolute;
    right: 7px; top: 6px;
    width: 7px; height: 7px;
    border-radius: 50%;
    background: var(--cv-border-strong);
}

/* Real images: rounded */
div[class*="st-key-card_"] [data-testid="stImage"],
div[class*="st-key-card_"] [data-testid="stImageContainer"] {
    position: relative;
    border-radius: 12px;
    overflow: hidden;
}

div[class*="st-key-card_"] [data-testid="stImage"] img {
    border-radius: 12px;
    animation: cvReveal 0.9s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

[data-testid="stImageCaption"] {
    color: var(--cv-text-faint) !important;
    font-size: 0.78rem !important;
}

/* ==================== FILE UPLOADER ==================== */
[data-testid="stFileUploaderDropzone"] {
    position: relative;
    border: 1.5px dashed rgba(var(--cv-accent-rgb), 0.4) !important;
    border-radius: 14px !important;
    background: rgba(var(--cv-accent-rgb), 0.04) !important;
    padding: 1.6rem 1.2rem !important;
    transition: border-color 0.3s ease, background 0.3s ease, transform 0.3s ease !important;
}

[data-testid="stFileUploaderDropzone"]:hover {
    border-color: var(--cv-accent) !important;
    background: rgba(var(--cv-accent-rgb), 0.08) !important;
    transform: scale(1.01);
}

[data-testid="stFileUploaderDropzoneInstructions"] span,
[data-testid="stFileUploaderDropzoneInstructions"] small {
    color: var(--cv-text-muted) !important;
}

[data-testid="stFileUploaderDropzone"] button {
    border-radius: 10px !important;
    border: 1px solid rgba(var(--cv-accent-rgb), 0.4) !important;
    background: transparent !important;
    color: var(--cv-accent) !important;
    font-weight: 600 !important;
}

[data-testid="stFileUploader"] section + div {
    color: var(--cv-text-muted);
}

/* ==================== INPUTS ==================== */
[data-testid="stSelectbox"] [data-baseweb="select"] > div {
    background: var(--cv-surface-2) !important;
    border: 1px solid var(--cv-border) !important;
    border-radius: 12px !important;
    min-height: 2.9rem;
    transition: border-color 0.25s ease, box-shadow 0.25s ease !important;
}

[data-testid="stSelectbox"] [data-baseweb="select"] > div:hover {
    border-color: var(--cv-border-strong) !important;
}

[data-testid="stSelectbox"] [data-baseweb="select"] > div:focus-within {
    border-color: var(--cv-accent) !important;
    box-shadow: 0 0 0 3px rgba(var(--cv-accent-rgb), 0.15) !important;
}

[data-baseweb="popover"] ul {
    background: var(--cv-surface-2) !important;
    border: 1px solid var(--cv-border) !important;
    border-radius: 12px !important;
}

[data-baseweb="popover"] li:hover,
[data-baseweb="popover"] li[aria-selected="true"] {
    background: rgba(var(--cv-accent-rgb), 0.10) !important;
}

[data-testid="stWidgetLabel"] p {
    font-size: 0.78rem !important;
    font-weight: 700 !important;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--cv-text-faint) !important;
}

/* ==================== BUTTONS ==================== */
.stButton > button,
[data-testid^="stBaseButton-"] {
    border-radius: 12px !important;
    font-family: var(--cv-font-body) !important;
    font-weight: 700 !important;
    min-height: 2.9rem;
    transition: transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1), box-shadow 0.25s ease, border-color 0.25s ease, background 0.25s ease !important;
}

[data-testid="stBaseButton-primary"] {
    position: relative;
    overflow: hidden;
    border: none !important;
    color: #04121A !important;
    background: linear-gradient(110deg, var(--cv-accent) 0%, var(--cv-accent-2) 100%) !important;
    box-shadow: 0 10px 30px -12px rgba(var(--cv-accent-rgb), 0.7) !important;
}

[data-testid="stBaseButton-primary"] p {
    color: #04121A !important;
    font-weight: 700 !important;
    letter-spacing: 0.02em;
}

/* Sheen sweep */
[data-testid="stBaseButton-primary"]::after {
    content: "";
    position: absolute;
    top: 0; bottom: 0;
    left: -60%;
    width: 40%;
    background: linear-gradient(100deg, transparent, rgba(255, 255, 255, 0.55), transparent);
    transform: skewX(-20deg);
    transition: left 0.7s cubic-bezier(0.2, 0.8, 0.2, 1);
}

[data-testid="stBaseButton-primary"]:hover {
    transform: translateY(-2px);
    box-shadow: 0 16px 36px -12px rgba(var(--cv-accent-2-rgb), 0.75) !important;
}

[data-testid="stBaseButton-primary"]:hover::after {
    left: 130%;
}

[data-testid="stBaseButton-primary"]:active {
    transform: translateY(0) scale(0.98);
}

[data-testid="stBaseButton-secondary"] {
    background: var(--cv-surface-2) !important;
    border: 1px solid var(--cv-border) !important;
    color: var(--cv-text) !important;
}

[data-testid="stBaseButton-secondary"]:hover {
    border-color: rgba(var(--cv-accent-rgb), 0.45) !important;
    color: var(--cv-accent) !important;
    transform: translateY(-1px);
}

[data-testid="stBaseButton-tertiary"] {
    color: var(--cv-text-muted) !important;
}

[data-testid="stBaseButton-tertiary"]:hover {
    color: var(--cv-danger) !important;
}

button:disabled,
[data-testid^="stBaseButton-"]:disabled {
    opacity: 0.45 !important;
    transform: none !important;
    cursor: not-allowed !important;
}

/* ==================== CHECKLIST ==================== */
.cv-checklist {
    display: flex;
    flex-direction: column;
    gap: 0.55rem;
    margin: 1rem 0 0.25rem 0;
}

.cv-check {
    display: flex;
    align-items: center;
    gap: 0.7rem;
    font-size: 0.88rem;
    color: var(--cv-text-muted);
}

.cv-check i {
    position: relative;
    width: 18px;
    height: 18px;
    border-radius: 6px;
    border: 1.5px solid var(--cv-border-strong);
    flex-shrink: 0;
    transition: all 0.3s ease;
}

.cv-check.done {
    color: var(--cv-text);
}

.cv-check.done i {
    border-color: var(--cv-accent);
    background: rgba(var(--cv-accent-rgb), 0.15);
}

.cv-check.done i::after {
    content: "";
    position: absolute;
    left: 5px; top: 1px;
    width: 4px; height: 9px;
    border: solid var(--cv-accent);
    border-width: 0 2px 2px 0;
    transform: rotate(45deg);
    animation: cvPop 0.35s cubic-bezier(0.2, 0.8, 0.2, 1.4) both;
}

/* ==================== MATURITY SCALE ==================== */
.cv-scale {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 0.75rem;
}

.cv-stage {
    position: relative;
    overflow: hidden;
    padding: 1.2rem 1.25rem;
    border-radius: 16px;
    background: var(--cv-surface);
    border: 1px solid var(--cv-border);
    animation: cvRise 0.7s cubic-bezier(0.2, 0.8, 0.2, 1) both;
    transition: transform 0.35s cubic-bezier(0.2, 0.8, 0.2, 1), border-color 0.35s ease;
}

.cv-stage:nth-child(2) { animation-delay: 0.08s; }
.cv-stage:nth-child(3) { animation-delay: 0.16s; }

.cv-stage:hover { transform: translateY(-3px); }

.cv-stage-bar {
    height: 4px;
    border-radius: 4px;
    margin-bottom: 1rem;
    background: var(--cv-border);
}

.cv-stage-name {
    font-family: var(--cv-font-heading);
    font-weight: 800;
    font-size: 1.35rem;
    color: var(--cv-text-muted);
    letter-spacing: -0.01em;
}

.cv-stage-hint {
    font-size: 0.8rem;
    color: var(--cv-text-faint);
    margin-top: 0.2rem;
}

.cv-stage.s-not .cv-stage-bar { background: linear-gradient(90deg, var(--cv-accent-2), rgba(var(--cv-accent-2-rgb), 0.2)); }
.cv-stage.s-ready .cv-stage-bar { background: linear-gradient(90deg, var(--cv-accent), rgba(var(--cv-accent-rgb), 0.2)); }
.cv-stage.s-over .cv-stage-bar { background: linear-gradient(90deg, var(--cv-danger), rgba(251, 113, 133, 0.2)); }

.cv-stage.active {
    border-color: var(--cv-accent);
    box-shadow: 0 0 0 1px var(--cv-accent), 0 18px 40px -18px rgba(var(--cv-accent-rgb), 0.5);
}

.cv-stage.active .cv-stage-name { color: var(--cv-text); }

/* ==================== REPORT ROWS ==================== */
.cv-rows {
    display: flex;
    flex-direction: column;
}

.cv-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.85rem 0;
    font-size: 0.92rem;
    color: var(--cv-text-muted);
    border-bottom: 1px solid var(--cv-border);
    animation: cvRise 0.6s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

.cv-row:last-child { border-bottom: none; }
.cv-row:nth-child(2) { animation-delay: 0.05s; }
.cv-row:nth-child(3) { animation-delay: 0.10s; }
.cv-row:nth-child(4) { animation-delay: 0.15s; }
.cv-row:nth-child(5) { animation-delay: 0.20s; }
.cv-row:nth-child(6) { animation-delay: 0.25s; }

.cv-row b {
    color: var(--cv-text);
    font-weight: 600;
}

.cv-row b.pending { color: var(--cv-text-faint); }

/* ==================== NOTICE ==================== */
.cv-notice {
    display: flex;
    gap: 0.85rem;
    align-items: flex-start;
    padding: 1rem 1.2rem;
    border-radius: 14px;
    border: 1px solid rgba(251, 191, 36, 0.25);
    background: rgba(251, 191, 36, 0.06);
    color: var(--cv-text-muted);
    font-size: 0.86rem;
    line-height: 1.6;
    margin-top: 1.75rem;
    animation: cvRise 0.7s 0.2s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

.cv-notice .cv-bar {
    width: 3px;
    align-self: stretch;
    border-radius: 3px;
    background: var(--cv-warning);
    flex-shrink: 0;
}

.cv-notice b { color: var(--cv-warning); }

.cv-notice.info { border-color: rgba(var(--cv-accent-rgb), 0.25); background: rgba(var(--cv-accent-rgb), 0.06); }
.cv-notice.info .cv-bar { background: var(--cv-accent); }
.cv-notice.info b { color: var(--cv-accent); }

/* ==================== TABS ==================== */
[data-testid="stTabs"] [role="tablist"] {
    gap: 0.35rem;
    border-bottom: 1px solid var(--cv-border);
}

[data-testid="stTabs"] [data-baseweb="tab-highlight"] {
    background: linear-gradient(90deg, var(--cv-accent), var(--cv-accent-2)) !important;
    height: 2px !important;
}

[data-testid="stTabs"] [data-baseweb="tab-border"] {
    display: none;
}

[data-testid="stTab"] {
    padding: 0.7rem 1rem !important;
    transition: color 0.25s ease !important;
}

[data-testid="stTab"] p {
    font-weight: 600 !important;
    color: var(--cv-text-muted);
}

[data-testid="stTab"][aria-selected="true"] p,
[data-testid="stTab"]:hover p {
    color: var(--cv-text) !important;
}

[data-testid="stTabPanel"] {
    animation: cvRise 0.5s cubic-bezier(0.2, 0.8, 0.2, 1) both;
    padding-top: 1.25rem;
}

/* ==================== ALERTS / TOASTS ==================== */
[data-testid="stAlert"] {
    border-radius: 14px !important;
    animation: cvRise 0.45s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

[data-testid="stToast"] {
    background: var(--cv-surface-2) !important;
    border: 1px solid rgba(var(--cv-accent-rgb), 0.3) !important;
    border-radius: 14px !important;
    color: var(--cv-text) !important;
}

/* ==================== FOOTER ==================== */
.cv-footer {
    display: flex;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-top: 3.5rem;
    padding-top: 1.25rem;
    border-top: 1px solid var(--cv-border);
    font-size: 0.78rem;
    color: var(--cv-text-faint);
}

/* ==================== SCROLLBAR ==================== */
::-webkit-scrollbar { width: 8px; height: 8px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--cv-border-strong); border-radius: 8px; }
::-webkit-scrollbar-thumb:hover { background: var(--cv-accent); }

/* ==================== HOME (section chooser) ==================== */
.stApp { transition: background-color 0.6s ease; }

div[class*="st-key-card_choose_"] {
    padding: 1.8rem 1.8rem 1.5rem 1.8rem;
    min-height: 100%;
    background:
        radial-gradient(22rem 14rem at 100% 0%, rgba(var(--cv-accent-rgb), 0.16), transparent 70%),
        linear-gradient(180deg, rgba(var(--cv-surface-2-rgb), 0.9) 0%, rgba(var(--cv-surface-rgb), 0.9) 100%);
    border-color: rgba(var(--cv-accent-rgb), 0.22);
}

div[class*="st-key-card_choose_"]:hover {
    transform: translateY(-6px);
    box-shadow: 0 26px 60px -24px rgba(var(--cv-accent-rgb), 0.45);
}

.cv-orb {
    position: relative;
    width: 64px;
    height: 64px;
    border-radius: 50%;
    margin-bottom: 1.3rem;
    background: radial-gradient(circle at 32% 30%, #fff8 0%, var(--cv-accent) 28%, var(--cv-accent-2) 70%, rgba(var(--cv-accent-2-rgb), 0.4) 100%);
    box-shadow: 0 0 36px rgba(var(--cv-accent-rgb), 0.45);
    animation: cvFloat 4.5s ease-in-out infinite;
}

.cv-orb.leaf { border-radius: 0 60% 0 60%; }

.cv-orb::after {
    content: "";
    position: absolute;
    inset: -8px;
    border-radius: inherit;
    border: 1px solid rgba(var(--cv-accent-rgb), 0.35);
    animation: cvRing 2.6s ease-out infinite;
}

.cv-choose-kicker {
    font-size: 0.7rem;
    font-weight: 700;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--cv-accent);
}

.cv-choose-title {
    font-family: var(--cv-font-heading);
    font-weight: 800;
    font-size: 1.9rem;
    line-height: 1.1;
    letter-spacing: -0.03em;
    color: var(--cv-text);
    margin: 0.35rem 0 0.6rem 0;
}

.cv-choose-text {
    font-size: 0.92rem;
    color: var(--cv-text-muted);
    line-height: 1.6;
    margin-bottom: 1rem;
}

.cv-choose-list {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem;
    margin-bottom: 1.4rem;
}

.cv-choose-list span {
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--cv-text-muted);
    padding: 0.3rem 0.65rem;
    border-radius: 999px;
    border: 1px solid rgba(var(--cv-accent-rgb), 0.25);
    background: rgba(var(--cv-accent-rgb), 0.06);
}

[data-testid="stColumn"]:nth-child(2) div[class*="st-key-card_choose_"] { animation-delay: 0.15s; }

/* Newer Streamlit versions build radios and tabs differently: keep the
   nav on one row without the radio circle, and colour the native accents */
[data-testid="stSidebar"] [data-testid="stRadioOption"] {
    display: flex !important;
    flex-direction: row !important;
    align-items: center !important;
}

[data-testid="stSidebar"] [data-testid="stRadioOption"] > div > div:first-child:not([data-testid]) {
    display: none !important;
}

[data-testid="stTab"] .react-aria-SelectionIndicator {
    background: linear-gradient(90deg, var(--cv-accent), var(--cv-accent-2)) !important;
}

[data-testid="stTab"][aria-selected="true"] p {
    color: var(--cv-text) !important;
}

/* Leaf tissue composition bar: segments grow in from the left */
.cv-tissue {
    display: flex;
    height: 22px;
    border-radius: 8px;
    overflow: hidden;
    margin: 0.4rem 0 0.8rem 0;
    border: 1px solid var(--cv-border);
    transform-origin: left center;
    animation: cvGrow 0.9s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}

/* Small caption under an image in the "Other transforms" tab */
.cv-caption {
    margin-top: 0.6rem;
    font-size: 0.8rem;
    color: var(--cv-text-muted);
    line-height: 1.5;
}

.cv-caption b { color: var(--cv-accent); font-weight: 700; }

/* ==================== KEYFRAMES ==================== */
@keyframes cvGrow {
    from { transform: scaleX(0); opacity: 0.4; }
    to   { transform: scaleX(1); opacity: 1; }
}

@keyframes cvFloat {
    0%, 100% { transform: translateY(0); }
    50%      { transform: translateY(-6px); }
}

@keyframes cvRing {
    from { transform: scale(0.9); opacity: 0.9; }
    to   { transform: scale(1.35); opacity: 0; }
}

@keyframes cvRise {
    from { opacity: 0; transform: translateY(14px); filter: blur(4px); }
    to   { opacity: 1; transform: translateY(0);    filter: blur(0); }
}

@keyframes cvReveal {
    from { opacity: 0; transform: scale(1.04); filter: saturate(0.3) blur(6px); }
    to   { opacity: 1; transform: scale(1);    filter: saturate(1) blur(0); }
}

@keyframes cvShimmer {
    0%   { transform: translateX(-100%); }
    60%  { transform: translateX(100%); }
    100% { transform: translateX(100%); }
}

@keyframes cvScan {
    0%   { top: 0%;   opacity: 0; }
    10%  { opacity: 1; }
    90%  { opacity: 1; }
    100% { top: 100%; opacity: 0; }
}

@keyframes cvPulse {
    0%   { box-shadow: 0 0 0 0 rgba(var(--cv-accent-rgb), 0.6); }
    70%  { box-shadow: 0 0 0 8px rgba(var(--cv-accent-rgb), 0); }
    100% { box-shadow: 0 0 0 0 rgba(var(--cv-accent-rgb), 0); }
}

@keyframes cvSpin {
    to { --cv-angle: 360deg; }
}

@keyframes cvPop {
    from { transform: rotate(45deg) scale(0); }
    to   { transform: rotate(45deg) scale(1); }
}

/* ==================== RESPONSIVE ==================== */
@media (max-width: 900px) {
    [data-testid="stMainBlockContainer"] { padding: 1.5rem 1rem; }
    .cv-scale { grid-template-columns: 1fr; }
}

@media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
    }
}
"""


def load_global_css():
    """Inject theme variables and global CSS."""
    st.markdown(f"<style>{_root_vars()}{_CSS}</style>", unsafe_allow_html=True)


def _theme_vars(colours: dict) -> str:
    """CSS custom properties (plus -rgb copies) for the given colours."""
    return "".join(
        f"--cv-{k.replace('_', '-')}: {v};--cv-{k.replace('_', '-')}-rgb: {_rgb(v)};"
        for k, v in colours.items()
    )


def apply_section_theme(section: str):
    """Recolour the app for a section: 'home', 'mango' or 'leaf'."""
    colours = SECTION_THEMES.get(section) or {}
    # The home cards preview the colours of the section they open
    previews = "".join(
        f"div.st-key-card_choose_{name} {{{_theme_vars(SECTION_THEMES[name])}}}"
        for name in ("mango", "leaf")
    )
    st.markdown(
        f"<style>:root {{{_theme_vars(colours)}}}{previews}</style>",
        unsafe_allow_html=True,
    )



def section_label(text: str):
    """Render an uppercase section label with a fading rule."""
    st.markdown(f"<div class='cv-section'>{text}</div>", unsafe_allow_html=True)
