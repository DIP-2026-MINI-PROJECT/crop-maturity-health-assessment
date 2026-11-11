"""
CropVision — Crop Maturity & Health Assessment
Digital Image Processing mini project (Streamlit front end).

Main entry point: page config, global styles, home screen, sidebar
navigation and routing. The app opens on a home screen that leads to the
mango ripeness section or the leaf disease section.
"""

import streamlit as st

from src.ui import apply_section_theme, load_global_css
from src.ui.components import (
    init_state,
    render_home_sidebar,
    render_sidebar,
    render_footer,
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


st.set_page_config(
    page_title="CropVision - Maturity & Health Assessment",
    layout="wide",
    initial_sidebar_state="expanded",
)

load_global_css()
init_state()

ROUTES = {
    "mango": {
        "Dashboard": mango_dashboard_page,
        "Image Processing": mango_processing_page,
        "Feature Analysis": feature_analysis_page,
        "Maturity Assessment": maturity_assessment_page,
        "Final Report": final_report_page,
    },
    "leaf": {
        "Dashboard": leaf_dashboard_page,
        "Image Processing": leaf_processing_page,
        "Disease Assessment": leaf_disease_page,
        "Final Report": final_report_page,
    },
}

section = st.session_state.section
apply_section_theme(section or "home")

if section is None:
    render_home_sidebar()
    home_page()
else:
    page = render_sidebar(section)
    ROUTES[section][page]()
render_footer()
