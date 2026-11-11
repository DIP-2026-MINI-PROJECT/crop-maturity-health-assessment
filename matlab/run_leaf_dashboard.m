% matlab/run_leaf_dashboard.m
% Entry point called by the Streamlit app (through the MATLAB Engine, or
% through watch_leaf.m). Writes every image the dashboard shows and saves
% results.json in outDir. Returns the path of that file.
%
% The images form a CHAIN: each one is the input to the next step.
%
%   01 resized      sampling                -> input to denoising
%   02 denoised     3x3 median              -> ALL measurements use this
%   03 enhanced     CLAHE on L*             -> display + Canny edges
%   04 lab          L*a*b* channels         -> the space clustering works in
%   05 clusters     k-means labels          -> input to cluster selection
%   06 union        leaf clusters merged    -> input to morphology
%   07 opened       opening + largest blob  -> input to closing
%   08 mask         final leaf mask         -> input to lesions + features
%   09 segmented    leaf on black           -> what the CNN would see
%   10 overlay      boundary on the leaf    (visual check of 08)
%   11 lesion_map   five tissue classes     -> affected area, severity
%   12 lesion_mask  binary not-healthy      -> affected area %
%   13 lesion_over  lesion outlines         (visual check of 11)
%   14 specks       black top-hat           -> speck features
%   15 edges        Canny inside the mask   -> edge density
function jsonPath = run_leaf_dashboard(imagePath, outDir)
if ~isfolder(outDir), mkdir(outDir); end

img = imread(imagePath);

% ---- 1. Preprocess ----------------------------------------------------
[den, enh, resized] = leaf_preprocess(img);
imwrite(resized, fullfile(outDir, 'resized.png'));
imwrite(den,     fullfile(outDir, 'denoised.png'));
imwrite(enh,     fullfile(outDir, 'enhanced.png'));

% L*a*b* channels: the colour space every later step works in
lab = rgb2lab(den);
imwrite([mat2gray(lab(:,:,1)), mat2gray(lab(:,:,2)), mat2gray(lab(:,:,3))], ...
        fullfile(outDir, 'colorspace_lab.png'));

% ---- 2. Segment -------------------------------------------------------
[mask, ok, seginfo, stages] = segment_leaf(den, false, 'auto');

% intermediate steps of the segmentation
if ~isempty(stages.clusters)
    imwrite(label2rgb(stages.clusters, 'jet', 'k', 'shuffle'), ...
            fullfile(outDir, 'clusters.png'));
end
if ~isempty(stages.union)
    imwrite(stages.union,  fullfile(outDir, 'cluster_union.png'));
end
if ~isempty(stages.opened)
    imwrite(stages.opened, fullfile(outDir, 'opened.png'));
end

imwrite(mask, fullfile(outDir, 'mask.png'));
imwrite(den .* uint8(repmat(mask, [1 1 3])), fullfile(outDir, 'segmented.png'));
imwrite(imoverlay(den, bwperim(mask, 8), [0 1 0]), fullfile(outDir, 'overlay.png'));

out = struct();
out.ok = ok;

baseImages = struct( ...
    'resized',       'resized.png', ...
    'denoised',      'denoised.png', ...
    'enhanced',      'enhanced.png', ...
    'colorspace',    'colorspace_lab.png', ...
    'clusters',      'clusters.png', ...
    'cluster_union', 'cluster_union.png', ...
    'opened',        'opened.png', ...
    'mask',          'mask.png', ...
    'segmented',     'segmented.png', ...
    'overlay',       'overlay.png');

if ~ok
    out.images   = baseImages;
    out.features = struct();
    out.health   = struct();
    out.segment  = seginfo;
    out.kind     = 'leaf';
    jsonPath = write_json(out, outDir);
    return
end

% ---- 3. Lesion maps ---------------------------------------------------
M = leaf_lesions(den, mask);

% Pseudocolour map of the five tissue classes (Unit 4)
%  1 healthy green | 2 chlorotic yellow | 3 necrotic red | 4 powdery white | 5 sooty black
labels = uint8(1*M.healthy + 2*M.chlorotic + 3*M.necrotic + 4*M.powdery + 5*M.sooty);
cmap = [0 0 0; 0.24 0.67 0.27; 0.94 0.80 0.16; 0.78 0.27 0.18; 0.92 0.92 0.96; 0.10 0.10 0.12];
imwrite(ind2rgb(labels, cmap), fullfile(outDir, 'lesion_map.png'));

imwrite(M.lesion, fullfile(outDir, 'lesion_mask.png'));
imwrite(imoverlay(den, M.lesion & ~imerode(M.lesion, strel('disk', 1)), [1 0 0]), ...
        fullfile(outDir, 'lesion_overlay.png'));

% Black top-hat speck map
gray = rgb2gray(den);
bh = imbothat(gray, strel('disk', 5));
v  = double(bh(mask));
sv = sort(v);
p99 = sv(max(1, ceil(0.99 * numel(sv))));
specks = imopen(bh > max(0.05 * 255, p99 * 0.5) & mask, strel('disk', 1));
imwrite(specks, fullfile(outDir, 'specks.png'));

% Canny edges inside the leaf
edges = edge(rgb2gray(enh), 'canny') & mask;
imwrite(edges, fullfile(outDir, 'edges.png'));

% ---- 4. Features and verdict -----------------------------------------
[f, names] = leaf_features(den, mask, M);
H = classify_leaf(f, names, M);

% ---- 5. Pack up -------------------------------------------------------
out.images = baseImages;
out.images.lesion_map     = 'lesion_map.png';
out.images.lesion_mask    = 'lesion_mask.png';
out.images.lesion_overlay = 'lesion_overlay.png';
out.images.specks         = 'specks.png';
out.images.edges          = 'edges.png';

feat = struct();
for k = 1:numel(names)
    feat.(names{k}) = f(k);
end
feat.edge_density = nnz(edges) / max(nnz(mask), 1);
out.features = feat;
out.health   = H;
out.segment  = seginfo;
out.kind     = 'leaf';

jsonPath = write_json(out, outDir);
end


function jsonPath = write_json(out, outDir)
out.version = 6;   % bump with LEAF_VERSION in matlab_bridge.py; 2: shadow removal, 3: busy backgrounds, 4: v3 segmentation + new model, 5: low-confidence flag, 6: focus segmentation for blurred green backgrounds
jsonPath = fullfile(outDir, 'results.json');
fid = fopen(jsonPath, 'w');
fwrite(fid, jsonencode(out, 'PrettyPrint', true), 'char');
fclose(fid);
end
