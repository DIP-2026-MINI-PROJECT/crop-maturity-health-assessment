"""
Bridge between the Streamlit UI and the MATLAB pipelines.

Two pipelines, one per section of the app:
    "fruit" -> matlab/crop_pipeline.m        mango ripeness
    "leaf"  -> matlab/run_leaf_dashboard.m   leaf disease

The uploaded image is saved to outputs/dashboard/<mode>-<id>/, MATLAB runs
the pipeline there and writes results.json, which is read back into a dict.

Two ways of reaching MATLAB, chosen automatically:

    engine   MATLAB Engine for Python is installed: call MATLAB directly.
    watcher  No Engine: write the image plus a small .job file into
             outputs/queue/ and wait for matlab/watch_leaf.m to write
             results.json. One watcher serves both sections. If it is not
             running, the app opens MATLAB with watch_leaf itself.

Set CROPVISION_BACKEND=engine or =watcher to force one.
Set CROPVISION_ROOT to override where the project root is.
Set CROPVISION_MATLAB to the full path of matlab.exe if it is not found.
Set CROPVISION_AUTOSTART=0 to start the watcher by hand instead.

Folder layout (the project root is found automatically):

    <root>/                               <- has matlab/
    |-- matlab/                           <- the .m files
    |-- outputs/queue/                    <- job files + watcher heartbeat
    `-- outputs/dashboard/<mode>-<id>/    <- one folder per analysis

The root can be this repo itself (it has a matlab/ folder) or a folder above it.
"""

import glob
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

import streamlit as st


REPO_DIR = Path(__file__).resolve().parents[2]

ENTRY = {
    "fruit": "crop_pipeline",
    "leaf": "run_leaf_dashboard",
}

# Bump together with out.version in crop_pipeline.m / run_leaf_dashboard.m;
# older saved results are re-run.
PIPELINE_VERSION = {"fruit": 7, "leaf": 6}

# How long to wait for the watcher to produce results, and how fresh the
# heartbeat must be for us to believe the watcher is running.
WATCH_TIMEOUT = 300.0
WATCH_POLL = 0.3
HEARTBEAT_MAX_AGE = 20.0
# MATLAB takes up to a minute or two to open; don't launch it twice meanwhile.
WATCHER_START_GRACE = 150.0


class BackendError(RuntimeError):
    """Raised with a message that can be shown to the user as-is."""


# ---------------------------------------------------------------- locating

def _has_pipeline(folder: Path) -> bool:
    return any((folder / "matlab" / f"{entry}.m").is_file() for entry in ENTRY.values())


def project_root() -> Optional[Path]:
    """Folder whose matlab/ holds a pipeline entry point, or None if not found."""
    env = os.environ.get("CROPVISION_ROOT")
    if env:
        root = Path(env)
        return root if _has_pipeline(root) else None
    for folder in [REPO_DIR, *REPO_DIR.parents]:
        if _has_pipeline(folder):
            return folder
    return None


def engine_available() -> bool:
    """True if MATLAB Engine for Python can be imported."""
    try:
        import matlab.engine  # noqa: F401
        return True
    except Exception:
        return False


def watcher_alive(root: Path) -> bool:
    """True if watch_leaf.m is running and its heartbeat is recent."""
    beat = root / "outputs" / "queue" / "watcher.alive"
    try:
        return (time.time() - beat.stat().st_mtime) < HEARTBEAT_MAX_AGE
    except Exception:
        return False


def _find_matlab() -> Optional[str]:
    """Path of the MATLAB launcher, or None if MATLAB is not installed."""
    env = os.environ.get("CROPVISION_MATLAB")
    if env and Path(env).is_file():
        return env
    found = shutil.which("matlab")
    if found:
        return found
    pattern = r"C:\Program Files\MATLAB\R*\bin\matlab.exe"
    installs = sorted(glob.glob(pattern))     # R2025b < R2026a, newest last
    return installs[-1] if installs else None


def start_watcher(root: Path) -> str:
    """
    Make sure watch_leaf.m is running. Returns "running", "starting"
    (MATLAB was opened and is still loading) or "manual" (could not start it).
    """
    if watcher_alive(root):
        return "running"
    if (os.environ.get("CROPVISION_AUTOSTART") or "1").strip() == "0":
        return "manual"

    # A marker file, so a page refresh or a second browser tab does not open
    # a second MATLAB while the first one is still loading.
    marker = root / "outputs" / "queue" / "watcher.starting"
    try:
        if time.time() - marker.stat().st_mtime < WATCHER_START_GRACE:
            return "starting"
    except OSError:
        pass

    exe = _find_matlab()
    if exe is None:
        return "manual"
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(time.strftime("%Y-%m-%d %H:%M:%S"), encoding="utf-8")
    flags = getattr(subprocess, "DETACHED_PROCESS", 0) if sys.platform == "win32" else 0
    try:
        # Opens the normal MATLAB window, in matlab/, running watch_leaf.
        subprocess.Popen(
            [exe, "-sd", str(root / "matlab"), "-r", "watch_leaf"],
            cwd=str(root / "matlab"),
            creationflags=flags,
            close_fds=True,
        )
    except OSError:
        marker.unlink(missing_ok=True)
        return "manual"
    return "starting"


def chosen_backend(root: Path) -> str:
    """Which route to MATLAB to use: 'engine' or 'watcher'."""
    forced = (os.environ.get("CROPVISION_BACKEND") or "").strip().lower()
    if forced in ("engine", "watcher"):
        return forced
    return "engine" if engine_available() else "watcher"


def backend_status(root: Optional[Path] = None) -> dict:
    """Small summary the UI can show in the sidebar."""
    if root is None:
        root = project_root()
    if root is None:
        return {"backend": "none", "ready": False, "detail": "No matlab/ folder found"}
    backend = chosen_backend(root)
    if backend == "engine":
        ok = engine_available()
        return {
            "backend": "engine",
            "ready": ok,
            "detail": "MATLAB Engine" if ok else "MATLAB Engine not importable",
        }
    state = start_watcher(root)
    detail = {
        "running": "MATLAB watcher running",
        "starting": "Opening MATLAB with the watcher (about a minute)",
        "manual": "Run matlab/watch_leaf.m in MATLAB",
    }[state]
    return {"backend": "watcher", "ready": state == "running", "detail": detail}


# ----------------------------------------------------------------- engine

@st.cache_resource(show_spinner="Starting MATLAB (first run only)...")
def _engine(matlab_dir: str):
    """Start one MATLAB session and keep it for the whole Streamlit server."""
    try:
        import matlab.engine
    except ImportError as exc:
        raise BackendError(
            "MATLAB Engine for Python is not installed in this environment."
        ) from exc
    eng = matlab.engine.start_matlab()
    eng.addpath(matlab_dir, nargout=0)
    return eng


def _run_via_engine(matlab_dir: Path, entry: str, input_path: Path, out_dir: Path) -> Path:
    try:
        eng = _engine(str(matlab_dir))
        fn = getattr(eng, entry)
        return Path(fn(str(input_path), str(out_dir), nargout=1))
    except BackendError:
        raise
    except Exception as exc:
        raise BackendError(f"MATLAB reported an error: {exc}") from exc


# ---------------------------------------------------------------- watcher

def _run_via_watcher(root: Path, job_name: str, out_dir: Path) -> Path:
    """Queue a job and wait for watch_leaf.m to produce results.json."""
    queue_dir = root / "outputs" / "queue"
    queue_dir.mkdir(parents=True, exist_ok=True)

    if start_watcher(root) == "starting":
        # MATLAB was just opened: wait for its first heartbeat
        deadline = time.time() + WATCHER_START_GRACE
        while not watcher_alive(root) and time.time() < deadline:
            time.sleep(1.0)
    if not watcher_alive(root):
        raise BackendError(
            "The MATLAB watcher is not running.\n\n"
            "In MATLAB: open matlab/watch_leaf.m, press Run, and leave it "
            "running. Then click Analyze again."
        )

    json_path = out_dir / "results.json"
    err_path = out_dir / "error.txt"
    for stale in (json_path, err_path):
        if stale.exists():
            stale.unlink()

    job_path = queue_dir / f"{job_name}.job"
    job_path.write_text(job_name, encoding="utf-8")

    deadline = time.time() + WATCH_TIMEOUT
    while time.time() < deadline:
        if json_path.is_file():
            time.sleep(0.15)        # let MATLAB finish closing the file
            return json_path
        if err_path.is_file():
            msg = err_path.read_text(encoding="utf-8", errors="replace").strip()
            raise BackendError(f"MATLAB reported an error:\n\n{msg}")
        if not job_path.exists() and not json_path.is_file():
            # watcher consumed the job but wrote nothing - give it a moment
            time.sleep(0.5)
            if json_path.is_file():
                return json_path
            raise BackendError(
                "The MATLAB watcher picked up the job but produced no results. "
                "Check the MATLAB Command Window for an error."
            )
        if not watcher_alive(root):
            raise BackendError(
                "The MATLAB watcher stopped while the job was running. "
                "Restart watch_leaf.m in MATLAB and try again."
            )
        time.sleep(WATCH_POLL)

    raise BackendError(
        f"Timed out after {WATCH_TIMEOUT:.0f}s waiting for MATLAB. "
        "Check the MATLAB Command Window."
    )


# -------------------------------------------------------------------- main

def run_analysis(image_bytes: bytes, image_name: str, mode: str = "fruit") -> dict:
    """
    Run one MATLAB pipeline on one image and return its results:
    {"ok", "mode", "backend", "output_dir", "images": {key: path},
     "features": {name: float},
     "stages": [{key, title, operation, input, path, change_path}, ...],
     "maturity": {stage, confidence, source}  (fruit),
     "health": {...}, "segment": {...}  (leaf)}
    Results for an image already analysed in the same mode are reused.
    """
    if mode not in ENTRY:
        raise BackendError(f"Unknown analysis mode {mode!r}.")

    root = project_root()
    if root is None:
        raise BackendError(
            "Could not find the matlab/ folder with the pipeline files. Keep "
            "matlab/ inside this repo (or a folder above it), or set CROPVISION_ROOT."
        )
    matlab_dir = root / "matlab"
    entry = ENTRY[mode]
    if not (matlab_dir / f"{entry}.m").is_file():
        raise BackendError(f"{entry}.m is missing from {matlab_dir}.")

    run_id = hashlib.sha1(image_bytes).hexdigest()[:12]
    job_name = f"{mode}-{run_id}"
    out_dir = root / "outputs" / "dashboard" / job_name
    json_path = out_dir / "results.json"
    backend = chosen_backend(root)

    if not _is_current(json_path, mode):
        out_dir.mkdir(parents=True, exist_ok=True)
        ext = Path(image_name).suffix.lower() or ".png"
        if ext not in (".jpg", ".jpeg", ".png"):
            ext = ".png"
        for old in out_dir.glob("input.*"):  # the watcher takes the first input.*
            old.unlink()
        input_path = out_dir / f"input{ext}"
        input_path.write_bytes(image_bytes)

        if backend == "engine":
            json_path = _run_via_engine(matlab_dir, entry, input_path, out_dir)
        else:
            json_path = _run_via_watcher(root, job_name, out_dir)

    data = json.loads(Path(json_path).read_text(encoding="utf-8"))
    images = {
        key: str(out_dir / name)
        for key, name in (data.get("images") or {}).items()
        if (out_dir / name).is_file()
    }
    stages = data.get("stages") or []
    if isinstance(stages, dict):  # jsonencode writes a 1x1 struct array as an object
        stages = [stages]
    stages = [
        {**stage, "path": str(out_dir / stage["file"]), "change_path": _change_path(out_dir, stage)}
        for stage in stages
        if (out_dir / stage.get("file", "")).is_file()
    ]

    def _as_dict(value):
        # jsonencode writes an empty struct as []
        return value if isinstance(value, dict) else {}

    return {
        "ok": bool(data.get("ok")),
        "mode": mode,
        "backend": backend,
        "output_dir": str(out_dir),
        "images": images,
        "stages": stages,
        "features": _as_dict(data.get("features")),
        "health": _as_dict(data.get("health")),
        "segment": _as_dict(data.get("segment")),
        "maturity": _as_dict(data.get("maturity")),
    }


def _change_path(out_dir: Path, stage: dict) -> Optional[str]:
    """Path of the stage's "what changed" image, if MATLAB saved one."""
    name = stage.get("change") or ""
    return str(out_dir / name) if name and (out_dir / name).is_file() else None


def _is_current(json_path: Path, mode: str) -> bool:
    """True if results.json exists and was written by this pipeline version."""
    if not json_path.is_file():
        return False
    try:
        data = json.loads(json_path.read_text(encoding="utf-8"))
    except ValueError:
        return False
    return data.get("version") == PIPELINE_VERSION[mode]
