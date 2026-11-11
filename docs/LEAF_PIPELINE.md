# Mango Leaf Health Assessment — Pipeline

Digital Image Processing mini project. Classical image processing in MATLAB,
with a Streamlit dashboard front end.

The project has two independent pipelines:

| Pipeline | Entry point | Question answered |
|---|---|---|
| Fruit (mango ripeness) | `matlab/crop_pipeline.m` | How ripe is this mango? |
| **Leaf (this document)** | `matlab/run_leaf_dashboard.m` | Is this leaf diseased, which disease, how badly? |

---

## 1. Dataset

**MangoLeafBD** — 4,000 images, 8 classes, 500 images per class:

`Healthy` · `Anthracnose` · `Bacterial Canker` · `Cutting Weevil` ·
`Die Back` · `Gall Midge` · `Powdery Mildew` · `Sooty Mould`

Images are 240×320 to 320×240, a single leaf on a plain background
(white, grey or blue depending on the capture session).

Expected location: `dataset/MangoLeafBD/<ClassName>/*.jpg`

---

## 2. Pipeline

```
input image
    |
    v
leaf_preprocess.m ........ sampling, noise removal, contrast
    |
    v
segment_leaf.m ........... k-means clustering -> leaf mask
    |
    v
leaf_lesions.m ........... every leaf pixel -> 1 of 5 tissue classes
    |
    v
leaf_features.m .......... 41 numeric features
    |
    v
classify_leaf.m .......... condition + severity + affected area
```

### 2.1 Preprocessing — `leaf_preprocess.m`

| Step | Operation | Syllabus unit |
|---|---|---|
| Sampling | `imresize` to longest side 384 px, bilinear + antialiasing | Unit 1 |
| Noise removal | 3×3 median filter per channel (`medfilt2`) — nonlinear | Unit 1, 3 |
| Contrast | CLAHE on the L\* channel only (`adapthisteq`) | Unit 3 |

Returns **two** images:

- `den` — resized + median filtered. **All measurements use this.**
- `enh` — `den` + CLAHE. **Display and Canny edges only.**

Equalisation changes the colour statistics the features depend on, so
measuring on `enh` would corrupt every colour feature. CLAHE is applied to
L\* alone so hue and chroma are untouched.

### 2.2 Segmentation — `segment_leaf.m`

Three methods, selected by argument: `'kmeans'` (default), `'border'`, `'auto'`.

**k-means (primary)**

1. Cluster every pixel in L\*a\*b\* with k = 5, features `[0.5·L*, a*, b*]`
   (lightness down-weighted so shading does not dominate hue).
   Fitted on a random 20,000-pixel subset for speed, then all pixels assigned.
2. Any cluster occupying **more than 15% of the image border** is background.
   A cluster whose mean a\*, b\* is within 8 of the background's is a cast
   shadow (shadows change L\*, not chromaticity) and is background too.
3. **Leaf = union of all remaining clusters.**
4. Morphology: opening (disk 3) → largest blob → closing (disk 5) → hole fill.

Step 3 is the key design decision. A diseased leaf is not one colour cluster
(an Anthracnose leaf is green + yellow + brown), so selecting a single cluster
captures only part of it.

Largest-blob is taken **before** closing: closing first can bridge the leaf to
a nearby shadow, after which "largest blob" keeps both as one object.

**Border/Otsu (fallback)**

Background colour estimated from a 4% border strip in L\*a\*b\*, colour distance
of every pixel from it, Otsu threshold, same morphological clean-up.

**Sanity check** — a mask is accepted only if it covers 2–92% of the frame and
occupies under 50% of the image border. `'auto'` runs k-means and falls back to
the border method if that check fails.

### 2.3 Lesion classification — `leaf_lesions.m`

Every pixel inside the mask is assigned one of five tissue classes using
L\*a\*b\* thresholds plus HSV saturation. L\*a\*b\* is used because one
threshold then works across the white, grey and blue backgrounds in the
dataset; hue alone does not.

| Class | Rule | Appearance |
|---|---|---|
| Healthy | a\* ≤ −8, S ≥ 0.20, L\* ≥ 22 | chlorophyll green |
| Sooty | L\* < 22 | black deposit / deep necrosis |
| Powdery | S < 0.20, L\* ≥ 40 | whitish-grey coating |
| Chlorotic | −8 < a\* < 8, b\* ≥ 14, S ≥ 0.20 | yellowing |
| Necrotic | everything else | brown dead tissue |

Each lesion class is then cleaned with an opening followed by a closing
(disk 2).

`lesion = chlorotic ∪ necrotic ∪ powdery ∪ sooty`

### 2.4 Features — `leaf_features.m`

41 numbers, all measured **inside the mask**.

| Group | Count | Features |
|---|---|---|
| Colour | 10 | mean + std of L\*, a\*, b\*, S, V |
| Lesion area | 6 | fraction healthy / chlorotic / necrotic / powdery / sooty / any |
| Lesion geometry | 3 | blob count, mean blob area, largest blob area |
| Texture | 6 | mean + std local entropy; GLCM contrast, homogeneity, energy, correlation (32 levels, 4 offsets) |
| Shape | 6 | area fraction, eccentricity, solidity, extent, circularity, convex deficiency |
| Granulometry | 5 | lesion area lost to openings at r = 1, 2, 4, 8, 16 |
| Specks | 2 | black top-hat speck fraction and count |
| Frequency | 3 | DFT energy in low / mid / high radial bands |

**Granulometry** measures the lesion *size distribution*: many tiny specks lose
area at small radii, a few large blotches lose area at large radii. This is what
separates sooty mould's scattered dots from anthracnose's blotches.

**Black top-hat** (`imbothat`, disk 5) isolates small dark spots on lighter
tissue.

**The DFT is computed on the segmented leaf**, not the whole frame — the
bounding box with background replaced by the leaf's mean grey level. See
§4.3 for why.

### 2.5 Classification — `classify_leaf.m`

Three outputs, computed three different ways:

**Affected area** — arithmetic:
```
affected % = non-healthy pixels / total leaf pixels × 100
```

**Severity** — fixed bands on that percentage (standard plant-pathology
disease-severity scale):

| Band | Affected area |
|---|---|
| None | < 2% |
| Mild | < 10% |
| Moderate | < 25% |
| Severe | < 50% |
| Very severe | ≥ 50% |

**Condition** — the only learned component, with two modes:

- **`matlab/leaf_model.mat` present** → trained linear SVM (one-vs-one ECOC).
  Decision scores are soft-maxed into a confidence percentage.
- **Absent** → `rule_label()`, a transparent `if/elseif` chain on the same
  features, so the dashboard works before training. No confidence is reported
  in this mode.

`classify_leaf.m` checks for the model file on every call, so training switches
modes with no code change.

---

## 3. Dashboard

The app opens on a home screen with two sections, **Mango ripeness** and
**Leaf disease**. The leaf section has four pages:

| Page | Contents |
|---|---|
| Dashboard | Upload, Analyze; condition, affected area, severity, symptom; tissue composition bar |
| Image Processing | *Pipeline* tab: original → resized → denoised → k-means clusters → merged leaf clusters → opened → final mask → tissue class map → lesion mask. *Other transforms* tab: CLAHE, L\*a\*b\* channels, segmented leaf, leaf boundary, lesion outlines, top-hat specks, Canny edges, each captioned |
| Disease Assessment | Verdict and confidence (says whether the SVM or the rules decided), tissue bar, lesion maps, feature tiles, all measurements |
| Final Report | Summary, text report and features JSON download |

### MATLAB connection

The app reaches MATLAB one of two ways, chosen automatically:

- **MATLAB Engine for Python**, if installed — direct call.
- **Folder watcher** — `matlab/watch_leaf.m` runs in MATLAB and polls
  `outputs/queue/`. The app writes the image plus a `.job` file; MATLAB
  processes it (leaf or fruit) and writes `results.json`. A `watcher.alive`
  heartbeat lets the app report whether MATLAB is reachable.

The watcher path exists because installing the MATLAB Engine requires write
access to `C:\Program Files\MATLAB\...`, which often fails without admin rights.

Results are cached per image hash in `outputs/dashboard/<mode>-<id>/`.

---

## 4. Validation

Measured on a reference implementation of the same algorithm. Re-run
`run_training.m` to confirm the figures on your machine.

### 4.1 Segmentation

240 images, 30 per class, method `'auto'`:

| Metric | Result |
|---|---|
| Hard failures (sanity check rejects) | **1.2%** (3/240) |
| Fallback to border method | 1.7% (4/240) |
| k-means vs border agreement, median IoU | 0.86 |

Per class, all failures were in one class:

| Class | Hard fail | Median IoU |
|---|---|---|
| Healthy | 0/30 | 0.98 |
| Anthracnose | 0/30 | 0.96 |
| Bacterial Canker | 0/30 | 0.95 |
| Powdery Mildew | 0/30 | 0.99 |
| Sooty Mould | 0/30 | 0.98 |
| Gall Midge | 0/30 | 0.88 |
| Die Back | 0/30 | 0.78 |
| **Cutting Weevil** | **3/30** | **0.38** |

### 4.2 Classification

Linear SVM, 8 classes, split so that both capture sessions appear in training
and test:

| Feature set | Accuracy |
|---|---|
| 38 features (no DFT) | **97.0%** |
| 41 features (DFT on leaf) | **97.0%** |
| 41 features (DFT on whole frame) | 96.6% |

### 4.3 Two measurement artefacts found and corrected

**Sampling bias.** Random 5-fold cross-validation gave **99.6%**. Training on
images 0–60 of each folder and testing on images 300–360 gave **61%** — the
same classes, unseen images. Images are stored in capture order, so each slice
of a folder is a different photo session. Sampling evenly across the whole
folder (`linspace`, in `run_training.m`) restored **96.4%**.

The 99.6% figure was measuring session recognition, not disease recognition.

**Background leakage in the frequency features.** The DFT bands were originally
computed over the whole frame. Random-forest importance ranked them 13, 15 and
25 of 44. Recomputed on the segmented leaf, they rank **41, 42 and 39** — the
leaf's own frequency content adds nothing beyond the entropy and GLCM features.
The whole-frame version was partly reading background texture, which correlates
with class because each class was photographed in its own session.

Accuracy is unchanged (97.0% either way), so the masked version is kept because
it measures what it claims to.

---

## 5. Known limitations

1. **Thin branched structures.** `Cutting Weevil` images are star-shaped stem
   clusters covering ~4% of the frame, not single leaves. `imopen(disk 3)`
   erodes arms a few pixels wide. 10% hard failure in that class. Would need a
   skeleton-based approach.

2. **Textured backgrounds.** The background can split into several clusters;
   one sitting inside the frame is then counted as leaf.

3. **Close-up leaves touching the frame edge.** The border strip is mostly
   leaf, so the fallback method's background estimate is wrong.

4. **Frequency features are redundant** given GLCM and entropy (§4.3). Retained
   for syllabus coverage of the 2-D DFT.

5. **Dataset labelling conventions.** The `Sooty Mould` class contains speckled
   leaves rather than the textbook continuous surface film, so model output and
   textbook diagnosis can legitimately differ.

6. **No treatment advice.** The system reports visible characteristics only.

---

## 6. Files

### MATLAB — `matlab/`

**Run these directly**

| File | Purpose |
|---|---|
| `run_leaf.m` | Full pipeline on one image, 3 figures |
| `run_transforms.m` | Quantisation, 2-D DFT, frequency-domain filters |
| `run_training.m` | Builds `leaf_features.csv`, trains the SVM, saves `leaf_model.mat` |
| `check_cnn.m` | Reports whether the CNN prerequisites are installed |
| `run_cnn.m` | Classical vs CNN vs combined feature comparison |
| `leaf_cnn_demo.m` | What the CNN sees, on one leaf |
| `watch_leaf.m` | Folder watcher that serves the dashboard |
| `crop_pipeline.m` | Mango ripeness pipeline (dashboard entry point; one argument shows a figure) |

**Called by the above**

`leaf_preprocess.m` · `segment_leaf.m` · `leaf_lesions.m` · `leaf_features.m` ·
`classify_leaf.m` · `leaf_demo.m` · `cnn_setup.m` · `cnn_activations.m` ·
`run_leaf_dashboard.m`

### Python — `src/`

| File | Purpose |
|---|---|
| `src/backend/matlab_bridge.py` | Engine or watcher backend; routes fruit/leaf |
| `src/ui/components.py` | Home screen, mango and leaf pages |
| `src/ui/styles.py` | Theme per section, animations |

### Not committed

`outputs/` · `dataset/` · `leaf_features.csv` · `leaf_model.mat` · `.venv/`

All are regenerable: run `run_training.m` to rebuild the CSV and model.

---

## 7. Running it

### MATLAB only

```matlab
cd <repo>\matlab
```

Then open and Run, in order:

1. `run_leaf.m` — pipeline on a random dataset image, 3 figures
2. `run_transforms.m` — transform and filtering figures
3. `run_training.m` — set `PER_CLASS = 20` to test, then `150` (~25 min)

### Dashboard

1. MATLAB: `cd <repo>\matlab`, run `watch_leaf`, leave it running
   (not needed if the MATLAB Engine for Python is installed)
2. PowerShell, in the repo: `.\.venv\Scripts\Activate.ps1`, then
   `python -m streamlit run app.py`
3. Browser: **Leaf disease** → upload a leaf → **Analyze image**

The sidebar shows whether MATLAB is reachable.

### Requirements

MATLAB with Image Processing Toolbox. Statistics and Machine Learning Toolbox
for `run_training.m` (without it `segment_leaf.m` uses `imsegkmeans` and the
condition comes from the rule-based fallback). Deep Learning Toolbox plus a
pretrained network only for the optional CNN comparison. Python 3.10+ with
Streamlit for the dashboard.
