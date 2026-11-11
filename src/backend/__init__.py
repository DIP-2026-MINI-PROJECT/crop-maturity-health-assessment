"""
Processing backend: runs the MATLAB pipelines and returns their outputs.
"""

from .matlab_bridge import (
    BackendError,
    ENTRY,
    backend_status,
    project_root,
    run_analysis,
)

__all__ = [
    "BackendError",
    "ENTRY",
    "backend_status",
    "project_root",
    "run_analysis",
]
