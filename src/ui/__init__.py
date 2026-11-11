"""
UI Module for Crop Maturity & Health Assessment
Provides styles, components, and page layouts
"""

from .styles import (
    THEME,
    SECTION_THEMES,
    apply_section_theme,
    load_global_css,
    section_label,
)
from .components import (
    SECTIONS,
    init_state,
    render_home_sidebar,
    render_sidebar,
    render_footer,
    page_header,
    stat_tile,
    image_slot,
    transform_slot,
    notice,
    home_page,
    mango_dashboard_page,
    mango_processing_page,
    feature_analysis_page,
    maturity_assessment_page,
    leaf_dashboard_page,
    leaf_processing_page,
    leaf_disease_page,
    final_report_page,
)

__all__ = [
    "THEME",
    "SECTION_THEMES",
    "apply_section_theme",
    "load_global_css",
    "section_label",
    "SECTIONS",
    "init_state",
    "render_home_sidebar",
    "render_sidebar",
    "render_footer",
    "page_header",
    "stat_tile",
    "image_slot",
    "transform_slot",
    "notice",
    "home_page",
    "mango_dashboard_page",
    "mango_processing_page",
    "feature_analysis_page",
    "maturity_assessment_page",
    "leaf_dashboard_page",
    "leaf_processing_page",
    "leaf_disease_page",
    "final_report_page",
]
