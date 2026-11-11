"""
Reusable UI Components for Crop Maturity & Health Assessment
Cards, stat tiles, image slots, sidebar, and page layouts.

Image slots accept an optional `source` (file path, bytes, PIL image or
numpy array). Results from the MATLAB backend (src/backend) are stored in
st.session_state.results and passed into the matching slots and tiles.
"""

import io
import json
from html import escape
from typing import Optional

import streamlit as st
from PIL import Image

from src.backend import BackendError, backend_status, run_analysis
from .styles import section_label


# The app opens on a home screen that leads to one of two sections.
SECTIONS = {
    "mango": {
        "name": "Mango ripeness",
        "crop": "Mango",
        "pages": [
            "Dashboard",
            "Image Processing",
            "Feature Analysis",
            "Maturity Assessment",
            "Final Report",
        ],
    },
    "leaf": {
        "name": "Leaf disease",
        "crop": "Mango leaf",
        "pages": [
            "Dashboard",
            "Image Processing",
            "Disease Assessment",
            "Final Report",
        ],
    },
}
# Mango maturity stages: (css class, name, hint). The trained SVM
# (mango_model.mat) returns the dataset folder name, matched to these names.
MATURITY_STAGES = [
    ("s-not", "Unripe", "Mostly green skin"),
    ("s-ready", "Partially ripe", "Colour turning"),
    ("s-over", "Ripe", "Fully coloured"),
]
# Below this SVM confidence (%) the stage is shown as "Uncertain".
MIN_CONFIDENCE = 60
_STAGE_SCALE = " · ".join(name for _, name, _ in MATURITY_STAGES)
# Stages of the MATLAB chain (crop_pipeline.m), shown as placeholders
# before the first analysis. Each stage takes the previous one's output.
PIPELINE_STAGES = [
    "Original",
    "Resized",
    "Denoised",
    "Contrast enhanced",
    "K-means clusters",
    "Initial mask",
    "Active contour",
    "Final mask",
    "Segmented fruit",
]
# Leaf chain (run_leaf_dashboard.m): images each step passes to the next.
# (image key, title, operation). "original" is the uploaded image.
LEAF_STAGES = [
    ("original", "Original", "Uploaded image"),
    ("resized", "Resized", "Sampling: bilinear resize, longest side 384 px, antialiased"),
    ("denoised", "Denoised", "3x3 median filter on each channel; every measurement uses this image"),
    ("clusters", "K-means clusters", "k-means (k = 5) on 0.5·L*, a*, b* of the denoised image"),
    ("cluster_union", "Leaf clusters merged", "Clusters owning more than 15% of the border are background; the rest are the leaf"),
    ("opened", "Opened", "Opening (disk 3), largest region kept"),
    ("mask", "Final leaf mask", "Closing (disk 5) and hole filling"),
    ("lesion_map", "Tissue class map", "Each leaf pixel: healthy, chlorotic, necrotic, powdery or sooty (L*a*b* + S thresholds)"),
    ("lesion_mask", "Lesion mask", "All non-healthy tissue; affected area = lesion / leaf pixels"),
]
# Images the leaf pipeline saves that the next step does not use.
LEAF_TRANSFORMS = [
    ("enhanced", "Contrast enhanced", "CLAHE on the L* channel (display and Canny only)"),
    ("colorspace", "L*a*b* channels", "RGB to L*a*b*: L*, a*, b* side by side"),
    ("segmented", "Segmented leaf", "Final mask applied to the denoised image"),
    ("overlay", "Leaf boundary", "Mask perimeter drawn on the denoised image"),
    ("lesion_overlay", "Lesion outlines", "Lesion boundaries drawn in red on the leaf"),
    ("specks", "Specks", "Black top-hat (disk 5), thresholded inside the leaf"),
    ("edges", "Edge map", "Canny edges of the enhanced image, inside the leaf"),
]
# Tissue class -> (feature key, display name, swatch colour matching the MATLAB colormap)
TISSUE = [
    ("frac_healthy", "Healthy", "#3DAB45"),
    ("frac_chlorotic", "Chlorotic", "#F0CC29"),
    ("frac_necrotic", "Necrotic", "#C7452E"),
    ("frac_powdery", "Powdery", "#EBEBF5"),
    ("frac_sooty", "Sooty", "#1A1A1F"),
]


# ============================================================================
# HELPERS
# ============================================================================

def _html(markup: str):
    """Render HTML. Lines are stripped so Markdown never treats them as code."""
    flat = "".join(line.strip() for line in markup.splitlines())
    st.markdown(flat, unsafe_allow_html=True)


def init_state():
    """Create the session keys the UI relies on."""
    defaults = {
        "image_bytes": None,
        "image_name": None,
        "crop_type": "Select crop",
        "section": None,  # None = home screen, else a key of SECTIONS
        "analysis_requested": False,
        "uploader_id": 0,
        # Filled in later by the processing backend:
        "results": {},
    }
    for key, value in defaults.items():
        st.session_state.setdefault(key, value)

    uploaded = st.session_state.get(f"uploader_{st.session_state.uploader_id}")
    if uploaded is not None:
        data = uploaded.getvalue()
        if data != st.session_state.image_bytes:
            st.session_state.image_bytes = data
            st.session_state.image_name = uploaded.name
            st.session_state.analysis_requested = False
            st.session_state.results = {}


def _clear_image():
    st.session_state.image_bytes = None
    st.session_state.image_name = None
    st.session_state.analysis_requested = False
    st.session_state.results = {}
    st.session_state.uploader_id += 1


def _open_section(section: Optional[str]):
    """Switch to a section (None = home). Each section starts with no image."""
    _clear_image()
    st.session_state.section = section
    st.session_state.crop_type = SECTIONS[section]["crop"] if section else "Select crop"


def _request_analysis():
    if st.session_state.image_bytes is not None and st.session_state.crop_type != "Select crop":
        st.session_state.analysis_requested = True


def _image_info() -> Optional[str]:
    """Return 'W x H px · size' for the stored image."""
    data = st.session_state.get("image_bytes")
    if not data:
        return None
    try:
        w, h = Image.open(io.BytesIO(data)).size
        return f"{w} x {h} px · {len(data) / 1024:.0f} KB"
    except Exception:
        return f"{len(data) / 1024:.0f} KB"


def _result(key: str) -> Optional[str]:
    """Read a backend result value, or None if not available yet."""
    return st.session_state.get("results", {}).get(key)


def _output(key: str) -> Optional[str]:
    """Path of a MATLAB output image, or None if not available yet."""
    return st.session_state.get("results", {}).get("images", {}).get(key)


def _fmt(value, spec: str = ".2f") -> str:
    return "n/a" if value is None else format(value, spec)


def _summarise(raw: dict) -> dict:
    """Turn the MATLAB results into the short strings the tiles display."""
    f = raw["features"]
    res = {
        "ok": raw["ok"],
        "stages": raw["stages"],
        "images": raw["images"],
        "features": f,
        "output_dir": raw["output_dir"],
        "crop": st.session_state.crop_type,
    }
    if not (raw["ok"] and f):
        return res
    if raw["mode"] == "leaf":
        _summarise_leaf(res, f, raw["health"])
        return res

    res["color_features"] = _fmt(f.get("mean_L"), ".1f")
    res["color_features_sub"] = (
        f"Mean L* · a* {_fmt(f.get('mean_a'))} · b* {_fmt(f.get('mean_b'))}"
    )
    res["texture_features"] = _fmt(f.get("mean_entropy"))
    res["texture_features_sub"] = f"Mean entropy · GLCM contrast {_fmt(f.get('glcm_contrast'))}"
    res["shape_features"] = _fmt(f.get("solidity"))
    res["shape_features_sub"] = f"Solidity · eccentricity {_fmt(f.get('eccentricity'))}"
    if f.get("dft_low") is not None:
        res["dft_features"] = f"{f['dft_low'] * 100:.0f}%"
        res["dft_features_sub"] = (
            f"Low-freq energy · mid {_fmt(f.get('dft_mid'))} · high {_fmt(f.get('dft_high'))}"
        )
    if f.get("area_fraction") is not None:
        res["fruit_area"] = f"{f['area_fraction'] * 100:.1f}%"

    m = raw.get("maturity") or {}
    if m.get("stage"):
        stage = _stage_name(m["stage"])
        conf = m.get("confidence")
        if isinstance(conf, (int, float)) and conf < MIN_CONFIDENCE:
            # too close between stages to name one
            res["maturity"] = "Uncertain"
            res["maturity_sub"] = f"Closest: {stage} · only {conf:.0f}% confidence"
        else:
            conf = f" · {conf:.0f}% confidence" if isinstance(conf, (int, float)) else ""
            res["maturity"] = stage
            res["maturity_sub"] = f"Linear SVM on colour (mango_model.mat){conf}"
    else:
        res["maturity_sub"] = "No mango_model.mat yet: run run_mango_training.m"

    hues = {
        "green": f.get("frac_green"),
        "yellow": f.get("frac_yellow"),
        "red-orange": f.get("frac_red"),
    }
    hues = {k: v for k, v in hues.items() if v is not None}
    if hues:
        name = max(hues, key=hues.get)
        res["maturity_evidence"] = f"{hues[name] * 100:.0f}% {name}"
        res["maturity_evidence_sub"] = "Largest hue class in fruit"
    return res


def _stage_name(label: str) -> str:
    """Dataset folder name (e.g. 'pArtially_ripe') -> stage name in MATURITY_STAGES."""
    key = "".join(ch for ch in label.lower() if ch.isalpha())
    for _, name, _ in MATURITY_STAGES:
        if key == name.lower().replace(" ", ""):
            return name
    return label.replace("_", " ").strip().capitalize()


def _summarise_leaf(res: dict, f: dict, h: dict):
    """Leaf verdict (classify_leaf.m) and feature tiles."""
    if h.get("condition"):
        res["condition"] = h["condition"]
    if h.get("severity"):
        res["severity"] = h["severity"]
    if h.get("affected_area") is not None:
        res["affected_area"] = f"{h['affected_area']:.1f}%"
    if h.get("symptom"):
        res["symptom"] = h["symptom"]
    conf = h.get("confidence")
    if isinstance(conf, (int, float)) and conf == conf:  # NaN when the rules decided
        res["confidence"] = f"{conf:.0f}%" + (" · low" if h.get("low_confidence") else "")
    res["decision_source"] = (
        f"Trained {h.get('model') or 'SVM'} (leaf_model.mat)" if h.get("source") == "model"
        else "Rule-based fallback (no leaf_model.mat)"
    )
    res["tissue"] = [(name, f.get(key) or 0.0, col) for key, name, col in TISSUE]

    res["lesion_features"] = str(int(round((f.get("lesion_count") or 0) * 100)))
    res["lesion_features_sub"] = (
        f"Lesion blobs · largest {(f.get('lesion_max_area') or 0) * 100:.1f}% of leaf"
    )
    res["speck_features"] = str(int(round((f.get("speck_count") or 0) * 100)))
    res["speck_features_sub"] = (
        f"Top-hat specks · {(f.get('speck_frac') or 0) * 100:.1f}% of leaf"
    )
    res["shape_features"] = _fmt(f.get("solidity"))
    res["shape_features_sub"] = f"Solidity · convex deficiency {_fmt(f.get('convex_deficiency'))}"
    res["texture_features"] = _fmt(f.get("mean_entropy"))
    res["texture_features_sub"] = f"Mean entropy · GLCM contrast {_fmt(f.get('glcm_contrast'))}"


def _sub(key: str, default: str) -> str:
    """Tile caption from the results, falling back to the static text."""
    return _result(f"{key}_sub") or default


def _run_backend():
    """Run this section's MATLAB pipeline on the stored image and save the results."""
    mode = "leaf" if st.session_state.section == "leaf" else "fruit"
    try:
        with st.spinner(f"Running MATLAB {mode} pipeline..."):
            raw = run_analysis(
                st.session_state.image_bytes,
                st.session_state.image_name or "input.png",
                mode=mode,
            )
    except BackendError as exc:
        st.session_state.analysis_requested = False
        st.error(str(exc))
        return
    st.session_state.results = _summarise(raw)
    st.session_state.analysis_requested = False
    if raw["ok"]:
        st.toast("Analysis complete.")
    else:
        target = "leaf" if mode == "leaf" else "fruit"
        st.toast(f"Segmentation did not find a plausible {target} region.")
    st.rerun()


# ============================================================================
# BUILDING BLOCKS
# ============================================================================

def page_header(eyebrow: str, title: str, subtitle: str = "", small: bool = True):
    """Animated page header. `title` may contain a <span class='cv-grad'>."""
    size = " cv-title-sm" if small else ""
    sub = f"<p class='cv-subtitle'>{subtitle}</p>" if subtitle else ""
    _html(f"""
        <div class="cv-eyebrow"><span class="cv-dot on"></span>{eyebrow}</div>
        <h1 class="cv-title{size}">{title}</h1>
        {sub}
    """)


def stat_tile(label: str, value: Optional[str], sub: str = "", tone: str = ""):
    """Small metric tile. value=None shows a pending dash."""
    shown = escape(value) if value else "&mdash;"
    pending = "" if value else " pending"
    tone_cls = f" tone-{tone}" if (tone and value) else ""
    _html(f"""
        <div class="cv-stat{tone_cls}">
            <div class="cv-stat-label">{label}</div>
            <div class="cv-stat-value{pending}">{shown}</div>
            <div class="cv-stat-sub">{sub}</div>
        </div>
    """)


def image_slot(title: str, key: str, source=None, empty_text: str = "Awaiting output",
               caption: str = ""):
    """
    Card that shows an image, or an animated placeholder if source is None.
    `key` must be unique on the page. `caption` (HTML) goes under the image.
    """
    with st.container(key=f"card_{key}"):
        tag = "<span class='cv-tag live'>Ready</span>" if source is not None else "<span class='cv-tag'>Pending</span>"
        _html(f"""
            <div class="cv-slot-head">
                <span class="cv-slot-title">{title}</span>{tag}
            </div>
        """)
        if source is not None:
            st.image(source, width="stretch")
        else:
            _html(f"""
                <div class="cv-placeholder">
                    <div class="cv-frame"></div>
                    <div>{empty_text}</div>
                </div>
            """)
        if caption:
            _html(f"<div class='cv-caption'>{caption}</div>")


def stage_slot(number: int, title: str, key: str, source=None,
               operation: str = "", input_title: str = ""):
    """Image card for one pipeline stage: step number, image, what was done."""
    with st.container(key=f"card_{key}"):
        tag = "<span class='cv-tag live'>Ready</span>" if source is not None else "<span class='cv-tag'>Pending</span>"
        _html(f"""
            <div class="cv-slot-head">
                <span style="display:flex;align-items:center;gap:0.6rem">
                    <span class="cv-step">{number:02d}</span>
                    <span class="cv-slot-title">{escape(title)}</span>
                </span>{tag}
            </div>
        """)
        if source is not None:
            st.image(source, width="stretch")
        else:
            _html("""
                <div class="cv-placeholder">
                    <div class="cv-frame"></div>
                    <div>Awaiting output</div>
                </div>
            """)
        if operation:
            src = f"<br>Input: {escape(input_title)}" if input_title else ""
            _html(f"<div class='cv-stat-sub' style='margin-top:0.6rem'>{escape(operation)}{src}</div>")


def notice(title: str, body: str, kind: str = "warning"):
    """Inline notice with a coloured bar. kind: warning | info."""
    cls = "info" if kind == "info" else ""
    _html(f"""
        <div class="cv-notice {cls}">
            <div class="cv-bar"></div>
            <div><b>{title}</b>&nbsp; {body}</div>
        </div>
    """)


def tissue_bar(rows):
    """Stacked bar of the five tissue classes, with a legend."""
    segs = "".join(
        f"<div style='flex:{max(frac, 0.0001)};background:{col}' title='{name}'></div>"
        for name, frac, col in rows if frac > 0.001
    )
    keys = "".join(
        f"<span class='cv-chip'><span style='width:10px;height:10px;border-radius:3px;"
        f"background:{col};display:inline-block'></span>{name} {frac * 100:.1f}%</span>"
        for name, frac, col in rows if frac > 0.001
    )
    _html(f"""
        <div class="cv-tissue">{segs}</div>
        <div class="cv-chips" style="margin:0 0 1rem 0">{keys}</div>
    """)


def _chips():
    """Status chips summarising the current session."""
    has_img = st.session_state.image_bytes is not None
    crop = st.session_state.crop_type
    has_crop = crop != "Select crop"
    queued = st.session_state.analysis_requested
    done = bool(st.session_state.results)
    _html(f"""
        <div class="cv-chips">
            <span class="cv-chip"><span class="cv-dot {'on' if has_img else ''}"></span>
                {'Image loaded' if has_img else 'No image'}</span>
            <span class="cv-chip"><span class="cv-dot {'on' if has_crop else ''}"></span>
                {escape(crop) if has_crop else 'No crop selected'}</span>
            <span class="cv-chip"><span class="cv-dot {'on' if done else 'wait' if queued else ''}"></span>
                {'Analysis complete' if done else 'Analysis queued' if queued else 'Idle'}</span>
        </div>
    """)


# ============================================================================
# SIDEBAR
# ============================================================================

def _brand(sub: str):
    _html(f"""
        <div class="cv-brand">
            <div class="cv-logo"></div>
            <div>
                <div class="cv-brand-name">CropVision</div>
                <div class="cv-brand-sub">{sub}</div>
            </div>
        </div>
    """)


def render_home_sidebar():
    """Sidebar for the home screen: brand and a short hint."""
    with st.sidebar:
        _brand("Maturity &amp; health")
        _html("""
            <div class="cv-side-label">Start</div>
            <div class="cv-stat-sub" style="margin-left:0.35rem">
                Choose a section on the right: mango ripeness or leaf disease.
            </div>
        """)


def render_sidebar(section: str) -> str:
    """Brand, navigation and session card. Returns the selected page."""
    with st.sidebar:
        _brand(SECTIONS[section]["name"])
        _html('<div class="cv-side-label">Navigate</div>')

        page = st.radio(
            "Navigation",
            SECTIONS[section]["pages"],
            label_visibility="collapsed",
            key=f"nav_{section}",
        )

        name = st.session_state.image_name or "None"
        crop = st.session_state.crop_type
        crop = crop if crop != "Select crop" else "None"
        if st.session_state.results:
            status = "Complete"
        else:
            status = "Queued" if st.session_state.analysis_requested else "Idle"
        _html(f"""
            <div class="cv-session">
                <div class="cv-side-label" style="margin-left:0">Session</div>
                <div class="cv-session-row"><span>Image</span><b>{escape(name)}</b></div>
                <div class="cv-session-row"><span>Crop</span><b>{escape(crop)}</b></div>
                <div class="cv-session-row"><span>Status</span><b>{status}</b></div>
            </div>
        """)
        try:
            bs = backend_status()
        except Exception:
            bs = {"backend": "none", "ready": False, "detail": "unavailable"}
        _html(f"""
            <div class="cv-session" style="margin-top:0.6rem">
                <div class="cv-side-label" style="margin-left:0">MATLAB</div>
                <div class="cv-session-row">
                    <span>{escape(bs['backend'])}</span>
                    <b>{'Ready' if bs['ready'] else 'Starting' if bs['detail'].startswith('Opening') else 'Not ready'}</b>
                </div>
                <div class="cv-stat-sub" style="margin-top:0.35rem">{escape(bs['detail'])}</div>
            </div>
        """)
        st.write("")
        st.button("Back to home", key="home_btn", width="stretch",
                  on_click=_open_section, args=(None,))
    return page


# ============================================================================
# HOME
# ============================================================================

def _choose_card(section: str, kicker: str, title: str, text: str, items, orb: str = ""):
    """One of the two big cards on the home screen."""
    with st.container(key=f"card_choose_{section}"):
        tags = "".join(f"<span>{escape(i)}</span>" for i in items)
        _html(f"""
            <div class="cv-orb {orb}"></div>
            <div class="cv-choose-kicker">{kicker}</div>
            <div class="cv-choose-title">{title}</div>
            <div class="cv-choose-text">{text}</div>
            <div class="cv-choose-list">{tags}</div>
        """)
        st.button(f"Open {SECTIONS[section]['name'].lower()}", key=f"open_{section}",
                  type="primary", width="stretch", on_click=_open_section, args=(section,))


def home_page():
    """Start screen: pick mango ripeness or leaf disease."""
    page_header(
        "Digital image processing",
        "Crop maturity<br><span class='cv-grad'>&amp; health</span>",
        "Choose what you want to assess. Each section has its own upload, "
        "processing pipeline and results.",
        small=False,
    )
    left, right = st.columns(2, gap="large")
    with left:
        _choose_card(
            "mango", "Section 01", "Mango ripeness",
            "Segment the fruit and measure colour, texture and shape to judge how ripe it is.",
            ["MATLAB pipeline", "Segmentation", "Features", "Maturity"],
        )
    with right:
        _choose_card(
            "leaf", "Section 02", "Leaf disease",
            "Find the leaf and the diseased spots on it to estimate the affected area.",
            ["MATLAB pipeline", "Lesions", "Affected area", "Disease class"],
            orb="leaf",
        )


# ============================================================================
# DASHBOARD
# ============================================================================

def _upload_card():
    """Upload card. Image bytes persist in session state across pages."""
    with st.container(key="card_upload"):
        _html("""
            <div class="cv-card-head">
                <span class="cv-step">01</span>
                <span class="cv-card-title">Upload image</span>
                <span class="cv-card-meta">JPG · JPEG · PNG</span>
            </div>
        """)
        st.file_uploader(
            "Crop image",
            type=["jpg", "jpeg", "png"],
            label_visibility="collapsed",
            key=f"uploader_{st.session_state.uploader_id}",
        )
        # (stored into session state by init_state on each run)

        if st.session_state.image_bytes is not None:
            st.image(st.session_state.image_bytes, width="stretch")
            info_col, btn_col = st.columns([3, 1], vertical_alignment="center")
            with info_col:
                _html(f"""
                    <div class="cv-stat-sub">
                        <b style="color:var(--cv-text)">{escape(st.session_state.image_name or '')}</b><br>
                        {_image_info() or ''}
                    </div>
                """)
            with btn_col:
                st.button("Clear", key="clear_img", type="tertiary", on_click=_clear_image)


def _configure_card():
    """Readiness checklist and the Analyze button. The crop is fixed by the section."""
    with st.container(key="card_config"):
        _html(f"""
            <div class="cv-card-head">
                <span class="cv-step">02</span>
                <span class="cv-card-title">Run the analysis</span>
            </div>
            <div class="cv-rows">
                <div class="cv-row"><span>Crop</span><b>{escape(st.session_state.crop_type)}</b></div>
            </div>
        """)

        has_img = st.session_state.image_bytes is not None
        try:
            matlab_ready = backend_status()["ready"]
        except Exception:
            matlab_ready = False
        _html(f"""
            <div class="cv-checklist">
                <div class="cv-check {'done' if has_img else ''}"><i></i>Image uploaded</div>
                <div class="cv-check {'done' if matlab_ready else ''}"><i></i>MATLAB reachable</div>
            </div>
        """)

        st.write("")
        if st.button("Analyze image", key="analyze_btn", type="primary", width="stretch",
                     on_click=_request_analysis):
            if has_img:
                _run_backend()
            else:
                st.warning("Upload an image first.")


def mango_dashboard_page():
    """Mango dashboard: upload, run, quick results."""
    page_header(
        "Mango ripeness",
        "Mango<br><span class='cv-grad'>ripeness</span>",
        "Upload a still image of a mango and run the MATLAB pipeline.",
        small=False,
    )
    _chips()

    left, right = st.columns([1.35, 1], gap="large")
    with left:
        _upload_card()
    with right:
        _configure_card()

    section_label("Results at a glance")
    c1, c2, c3, c4 = st.columns(4, gap="medium")
    with c1:
        stat_tile("Crop", "Mango", "This section", "accent")
    with c2:
        stat_tile("Maturity", _result("maturity"), _sub("maturity", _STAGE_SCALE), "accent")
    with c3:
        stat_tile("Evidence", _result("maturity_evidence"), _sub("maturity_evidence", "Largest hue class"))
    with c4:
        stat_tile("Fruit area", _result("fruit_area"), "Of image, from final mask")


def leaf_dashboard_page():
    """Leaf dashboard: upload, run, verdict tiles and tissue composition."""
    page_header(
        "Leaf disease",
        "Leaf<br><span class='cv-grad'>disease</span>",
        "Upload a still image of a single mango leaf and run the MATLAB leaf pipeline.",
        small=False,
    )
    _chips()

    left, right = st.columns([1.35, 1], gap="large")
    with left:
        _upload_card()
    with right:
        _configure_card()

    section_label("Results at a glance")
    c1, c2, c3, c4 = st.columns(4, gap="medium")
    with c1:
        stat_tile("Condition", _result("condition"), "Disease class", "accent")
    with c2:
        stat_tile("Affected area", _result("affected_area"), "Lesion area / leaf area", "danger")
    with c3:
        stat_tile("Severity", _result("severity"), "None · Mild · Moderate · Severe", "warning")
    with c4:
        stat_tile("Symptom", _result("symptom"), "Dominant visible symptom")
    if _result("tissue"):
        section_label("Tissue composition")
        tissue_bar(_result("tissue"))


# ============================================================================
# OTHER PAGES
# ============================================================================

def _stage_grid(cards, prefix: str):
    """Two-column grid of stage_slot cards: (title, source, operation, input title)."""
    for row in range(0, len(cards), 2):
        cols = st.columns(2, gap="medium")
        for i, col in enumerate(cols):
            n = row + i
            if n >= len(cards):
                break
            title, source, operation, input_title = cards[n]
            with col:
                stage_slot(n + 1, title, f"{prefix}_{n}", source, operation, input_title)


def transform_slot(title: str, key: str, source=None, transform: str = "",
                   note: str = "", empty_text: str = "Awaiting output"):
    """Image card captioned with the transform or filter that produced it."""
    caption = f"<b>Transform:</b> {escape(transform)}" if transform else ""
    if note:
        caption += f"<br>{escape(note)}"
    image_slot(title, key, source, empty_text, caption)


def _transform_grid(items, prefix: str, empty_text: str = "Awaiting output"):
    """Two-column grid of transform_slot cards: (title, source, transform, note)."""
    for row in range(0, len(items), 2):
        cols = st.columns(2, gap="medium")
        for i, col in enumerate(cols):
            n = row + i
            if n >= len(items):
                break
            title, source, transform, note = items[n]
            with col:
                transform_slot(title, f"{prefix}_{n}", source, transform, note, empty_text)


def mango_processing_page():
    """Pipeline tab: the images the MATLAB chain passes on. Other tab: the rest."""
    page_header(
        "Preprocessing and segmentation",
        "Processing <span class='cv-grad'>pipeline</span>",
        "Each stage takes the image produced by the stage before it.",
    )
    _chips()

    stages = _result("stages") or []
    if stages:
        titles = {s["key"]: s["title"] for s in stages}
        cards = [
            (s["title"], s["path"], s.get("operation", ""), titles.get(s.get("input"), ""))
            for s in stages
        ]
    else:
        cards = [(title, None, "", "") for title in PIPELINE_STAGES]
        cards[0] = (PIPELINE_STAGES[0], st.session_state.image_bytes, "", "")

    # Images MATLAB saved that are not passed to the next stage, e.g. the
    # "what changed" view of each stage
    others = [
        (f"{s['title']}: what changed", s["change_path"],
         s.get("operation", ""), s.get("change_note", ""))
        for s in stages if s.get("change_path")
    ]

    tab_main, tab_other = st.tabs(["Pipeline", "Other transforms"])
    with tab_main:
        _stage_grid(cards, "ip_stage")
    with tab_other:
        if others:
            notice("Not passed on",
                   "These images show what a stage did. The next stage does not use them.",
                   kind="info")
            _transform_grid(others, "ip_other")
        elif stages:
            notice("None saved",
                   "This version of crop_pipeline.m saves only the pipeline images.",
                   kind="info")
        else:
            notice("After analysis",
                   "Images that show what each filter changed appear here once the "
                   "pipeline has run.", kind="info")


def leaf_processing_page():
    """Pipeline tab: the images the leaf chain passes on. Other tab: the rest."""
    page_header(
        "Leaf preprocessing and segmentation",
        "Leaf <span class='cv-grad'>pipeline</span>",
        "Each stage takes the image produced by the stage before it.",
    )
    _chips()

    images = _result("images") or {}
    done = bool(images)
    cards = []
    for key, title, operation in LEAF_STAGES:
        source = st.session_state.image_bytes if key == "original" else images.get(key)
        if done and source is None:
            continue  # e.g. no cluster images when the border fallback was used
        cards.append((title, source, operation, cards[-1][0] if cards else ""))

    tab_main, tab_other = st.tabs(["Pipeline", "Other transforms"])
    with tab_main:
        _stage_grid(cards, "lf_stage")
    with tab_other:
        notice("Not passed on",
               "These images show what a transform or filter does. "
               "The next stage does not use them.", kind="info")
        items = [(title, images.get(key), transform, "")
                 for key, title, transform in LEAF_TRANSFORMS
                 if not done or key in images]
        _transform_grid(items, "lf_other")


def feature_analysis_page():
    """Extracted features and segmentation outputs."""
    page_header(
        "Segmentation and features",
        "Feature <span class='cv-grad'>analysis</span>",
    )
    _chips()

    c1, c2, c3, c4 = st.columns(4, gap="medium")
    with c1:
        stat_tile("Colour", _result("color_features"), _sub("color_features", "Colour moments"))
    with c2:
        stat_tile("Texture", _result("texture_features"), _sub("texture_features", "Texture analysis"))
    with c3:
        stat_tile("Shape", _result("shape_features"), _sub("shape_features", "Shape descriptors"))
    with c4:
        stat_tile("Frequency", _result("dft_features"), _sub("dft_features", "DFT energy bands"))

    section_label("Features are measured inside")
    c5, c6 = st.columns(2, gap="medium")
    with c5:
        image_slot("Final mask", "fa_mask", _output("mask"))
    with c6:
        image_slot("Segmented fruit", "fa_segmented", _output("segmented"))


def maturity_assessment_page():
    """Maturity stage scale and evidence."""
    page_header(
        "Maturity",
        "Maturity <span class='cv-grad'>assessment</span>",
    )
    _chips()

    current = _result("maturity")
    stages = MATURITY_STAGES
    cards = "".join(
        f"""<div class="cv-stage {cls} {'active' if current == name else ''}">
                <div class="cv-stage-bar"></div>
                <div class="cv-stage-name">{name}</div>
                <div class="cv-stage-hint">{hint}</div>
            </div>"""
        for cls, name, hint in stages
    )
    _html(f"<div class='cv-scale'>{cards}</div>")

    section_label("Results")
    tab1, tab2, tab3 = st.tabs(["Overview", "Visual evidence", "Details"])
    with tab1:
        c1, c2, c3 = st.columns(3, gap="medium")
        with c1:
            stat_tile("Stage", current, _sub("maturity", "Assessed maturity"), "accent")
        with c2:
            stat_tile("Crop", _result("crop"), "Analysed crop")
        with c3:
            stat_tile("Evidence", _result("maturity_evidence"), _sub("maturity_evidence", "Key measurement"))
    with tab2:
        c1, c2 = st.columns(2, gap="medium")
        with c1:
            image_slot("Input", "mt_input", st.session_state.image_bytes, "Upload an image on the dashboard")
        with c2:
            image_slot("Segmented fruit", "mt_segmented", _output("segmented"))
    with tab3:
        _measurements_card("mt_details")


def _measurements_card(key: str):
    """Every MATLAB measurement in one card."""
    with st.container(key=f"card_{key}"):
        features = _result("features")
        if features:
            rows = "".join(
                f"<div class='cv-row'><span>{escape(name)}</span><b>{_fmt(value, '.4f')}</b></div>"
                for name, value in features.items()
            )
            _html(f"""
                <div class="cv-slot-head"><span class="cv-slot-title">Measurements</span>
                <span class="cv-tag live">Ready</span></div>
                <div class="cv-rows">{rows}</div>
            """)
        else:
            _html("""
                <div class="cv-slot-head"><span class="cv-slot-title">Measurements</span>
                <span class="cv-tag">Pending</span></div>
                <div class="cv-stat-sub">Detailed measurements appear here after analysis.</div>
            """)


def leaf_disease_page():
    """Leaf verdict from classify_leaf.m, lesion images and all measurements."""
    page_header(
        "Leaf health",
        "Disease <span class='cv-grad'>assessment</span>",
    )
    _chips()

    c1, c2, c3, c4 = st.columns(4, gap="medium")
    with c1:
        stat_tile("Condition", _result("condition"), "Disease class", "accent")
    with c2:
        stat_tile("Affected area", _result("affected_area"), "Lesion area / leaf area", "danger")
    with c3:
        stat_tile("Severity", _result("severity"), "<2 · <10 · <25 · <50 · ≥50 %", "warning")
    with c4:
        stat_tile("Confidence", _result("confidence"),
                  _result("decision_source") or "SVM score, or rules")

    if _result("tissue"):
        section_label("Tissue composition")
        tissue_bar(_result("tissue"))

    tab1, tab2, tab3 = st.tabs(["Lesion maps", "Features", "Measurements"])
    with tab1:
        c5, c6 = st.columns(2, gap="medium")
        with c5:
            image_slot("Tissue class map", "ld_map", _output("lesion_map"))
        with c6:
            image_slot("Lesion mask", "ld_mask", _output("lesion_mask"))
    with tab2:
        c7, c8, c9, c10 = st.columns(4, gap="medium")
        with c7:
            stat_tile("Lesions", _result("lesion_features"), _sub("lesion_features", "Lesion blobs"))
        with c8:
            stat_tile("Specks", _result("speck_features"), _sub("speck_features", "Black top-hat"))
        with c9:
            stat_tile("Shape", _result("shape_features"), _sub("shape_features", "Solidity"))
        with c10:
            stat_tile("Texture", _result("texture_features"), _sub("texture_features", "Entropy"))
    with tab3:
        _measurements_card("ld_details")

    notice(
        "Disclaimer",
        "Image-based assessment of visible characteristics only. No pesticide, "
        "medication, or treatment recommendations. Validate results with an expert.",
    )


def final_report_page():
    """Summary of all results and export actions."""
    page_header(
        "Report",
        "Analysis <span class='cv-grad'>report</span>",
    )
    _chips()

    rows = [
        ("Input image", st.session_state.image_name),
        ("Crop", st.session_state.crop_type),
    ]
    if st.session_state.section == "leaf":
        rows += [
            ("Condition", _result("condition")),
            ("Affected area", _result("affected_area")),
            ("Severity", _result("severity")),
            ("Symptom", _result("symptom")),
        ]
    else:
        rows += [
            ("Maturity", _result("maturity")),
            ("Evidence", _result("maturity_evidence")),
            ("Fruit area", _result("fruit_area")),
        ]
    row_html = "".join(
        f"<div class='cv-row'><span>{label}</span>"
        f"<b class='{'' if value else 'pending'}'>{escape(value) if value else 'Pending'}</b></div>"
        for label, value in rows
    )

    left, right = st.columns([1.5, 1], gap="large")
    with left:
        _html(f"""
            <div class="cv-card">
                <div class="cv-card-head"><span class="cv-card-title">Summary</span></div>
                <div class="cv-rows">{row_html}</div>
            </div>
        """)
    with right:
        with st.container(key="card_export"):
            _html("""
                <div class="cv-card-head"><span class="cv-card-title">Export</span></div>
            """)
            done = bool(st.session_state.results)
            if done:
                st.download_button("Download report", _report_text(rows), "cropvision_report.txt",
                                   mime="text/plain", key="download_btn", width="stretch")
                st.download_button("Export results", json.dumps(_result("features") or {}, indent=2),
                                   "cropvision_features.json", mime="application/json",
                                   key="export_btn", width="stretch")
            else:
                st.button("Download report", key="download_btn", disabled=True, width="stretch")
                st.button("Export results", key="export_btn", disabled=True, width="stretch")
            hint = "Report and MATLAB measurements." if done else "Available after analysis completes."
            _html(f"<div class='cv-stat-sub' style='margin-top:0.5rem'>{hint}</div>")

        section_label("Input")
        image_slot("Input image", "rp_input", st.session_state.image_bytes, "No image uploaded")


def _report_text(rows) -> str:
    """Plain-text report: the summary rows plus every MATLAB measurement."""
    lines = ["CropVision - Crop maturity and health assessment", ""]
    lines += [f"{label}: {value or 'Pending'}" for label, value in rows]
    tissue = _result("tissue")
    if tissue:
        lines += ["", "Tissue composition"]
        lines += [f"  {name}: {frac * 100:.1f}%" for name, frac, _ in tissue]
    features = _result("features") or {}
    if features:
        lines += ["", "Measurements (MATLAB)"]
        lines += [f"  {name}: {_fmt(value, '.4f')}" for name, value in features.items()]
    lines += ["", "Image-based assessment of visible characteristics only."]
    return "\n".join(lines) + "\n"


def render_footer():
    """Small footer line."""
    _html("""
        <div class="cv-footer">
            <span>CropVision · Crop maturity &amp; health assessment</span>
            <span>Digital Image Processing mini project</span>
        </div>
    """)
