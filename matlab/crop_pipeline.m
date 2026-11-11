% matlab/crop_pipeline.m
% The whole pipeline in one file. Each stage takes the image produced by the
% stage before it:
%   original -> resized -> denoised -> contrast enhanced            (Unit 1)
%   -> k-means cluster map -> initial mask -> active contour
%   -> final mask -> segmented fruit                                (segmentation)
%   -> colour / texture / shape / DFT features                      (Units 1-2)
%   -> maturity stage (linear SVM, mango_model.mat from run_mango_training.m)
%
% Dashboard:  jsonPath = crop_pipeline(imagePath, outDir)
%   saves every stage as NN_<key>.png in outDir and writes results.json.
% MATLAB:     crop_pipeline('langra-mango-plant.jpg')
%   same, saved to a temp folder, and shows all stages in one figure.
function jsonPath = crop_pipeline(imagePath, outDir)
showFigure = nargin < 2;
if showFigure, outDir = fullfile(tempdir, 'crop_pipeline'); end
if ~isfolder(outDir), mkdir(outDir); end
stages = struct('key', {}, 'title', {}, 'operation', {}, 'input', {}, 'file', {}, ...
    'change', {}, 'change_note', {});

% ======================= 1. ORIGINAL =======================
img = imread(imagePath);
if size(img, 3) == 1, img = repmat(img, [1 1 3]); end   % greyscale -> RGB
img = img(:,:,1:3);                                      % drop alpha channel
stages = save_stage(stages, outDir, img, 'original', 'Original', ...
    'Uploaded image, converted to 3-channel RGB', '');

% ======================= 2. SAMPLING (Unit 1) =======================
% Resize so the longest side is 512 px, aspect ratio same
scale = 512 / max(size(img, 1), size(img, 2));
resized = imresize(img, scale, 'bilinear', 'Antialiasing', true);
stages = save_stage(stages, outDir, resized, 'resized', 'Resized', ...
    'Sampling: bilinear resize, longest side 512 px', 'original');

% ======================= 3. NOISE REDUCTION =======================
% 3x3 median filter on each colour channel
den = resized;
for c = 1:3
    den(:,:,c) = medfilt2(resized(:,:,c), [3 3]);
end
stages = save_stage(stages, outDir, den, 'denoised', 'Denoised', ...
    '3x3 median filter on each colour channel', 'resized', resized);

% ======================= 4. CONTRAST ENHANCEMENT =======================
% Histogram equalisation on brightness (V) only
hsv = rgb2hsv(den);
hsv(:,:,3) = histeq(hsv(:,:,3));
enhanced = im2uint8(hsv2rgb(hsv));
stages = save_stage(stages, outDir, enhanced, 'enhanced', 'Contrast enhanced', ...
    'Histogram equalisation of the V channel (HSV)', 'denoised', den);

% ======================= 5. K-MEANS CLUSTERING (segment.m) =======================
lab = rgb2lab(enhanced);
a = lab(:,:,2);
b = lab(:,:,3);

[rows, cols, ~] = size(enhanced);
[X, Y] = meshgrid(1:cols, 1:rows);
cX = cols / 2;
cY = rows / 2;
dist_center = sqrt((X - cX).^2 + (Y - cY).^2);
dist_center = dist_center / max(dist_center(:));

% Same features as segment.m (a*, b*, 10 x distance from centre), stacked as
% a 3-layer image so imsegkmeans (Image Processing Toolbox) can cluster them.
% kmeans() would need the Statistics and Machine Learning Toolbox.
features = single(cat(3, a, b, 10 * dist_center));

rng(0);   % same clusters every run, so the dashboard result is repeatable
cluster_map = double(imsegkmeans(features, 4, 'NumAttempts', 5));
stages = save_stage(stages, outDir, label2rgb(cluster_map), 'clusters', 'K-means clusters', ...
    'k-means (k = 4) on a*, b* and distance from the centre', 'enhanced');

% ======================= 6. INITIAL MASK =======================
% Which clusters are fruit depends on the background.
k = max(cluster_map(:));
border = false(rows, cols);
border([1 end], :) = true;  border(:, [1 end]) = true;

% Is the background plain? Spread of the border chromaticity (a*, b*)
% around its median: a few units for a studio backdrop, 15+ for foliage.
bAB = [a(border), b(border)];
spread = median(hypot(bAB(:,1) - median(bAB(:,1)), bAB(:,2) - median(bAB(:,2))));
cluttered = spread > 8;

if ~cluttered
    % Plain background. A ripening mango is not one colour (red top,
    % yellow-green bottom), so keeping a single cluster keeps only part of
    % the fruit. Instead:
    %  1. a cluster that covers much of the image border is background;
    %  2. a cluster whose chromaticity (a*, b*) is close to the background's
    %     is a shadow or reflection: shadows change lightness L*, not colour;
    %  3. the fruit is the union of all remaining clusters.
    contact = zeros(1, k);
    for c = 1:k
        contact(c) = nnz(cluster_map(border) == c) / nnz(border);
    end
    isBg = contact > 0.15;
    if ~any(isBg), [~, c] = max(contact); isBg(c) = true; end

    bgPix = ismember(cluster_map, find(isBg));
    bgAB  = [mean(a(bgPix)), mean(b(bgPix))];
    for c = find(~isBg)
        m = (cluster_map == c);
        if hypot(mean(a(m)) - bgAB(1), mean(b(m)) - bgAB(2)) < 10
            isBg(c) = true;    % same colour as the background, only darker/lighter
        end
    end
    initial_mask = ismember(cluster_map, find(~isBg));
    maskNote = 'Plain background: clusters that are not border background or shadow';
else
    % Cluttered background (leaves, branches, sky): the border has many
    % colours, so it cannot define "background". Use shape instead: a mango
    % is a large, compact, convex blob near the middle; leaves and stems are
    % thin and elongated. Every connected region of every cluster is scored
    %   score = solidity^2 * circularity * centrality * sqrt(area),
    % regions touching the border are penalised, and the best one is the
    % seed. A neighbouring region is added if the union stays convex (the
    % red and the yellow half of one fruit).
    r = max(2, round(0.015 * min(rows, cols)));
    cand = struct('score', {}, 'mask', {}, 'solidity', {});
    for c = 1:k
        cc = bwconncomp(imopen(cluster_map == c, strel('disk', r)));
        for j = 1:cc.NumObjects
            if numel(cc.PixelIdxList{j}) < 0.01 * rows * cols, continue; end
            m = false(rows, cols);  m(cc.PixelIdxList{j}) = true;
            m = imfill(m, 'holes');
            p = regionprops(m, 'Area', 'Perimeter', 'Solidity', 'Centroid');
            circ  = min(1, 4 * pi * p.Area / max(p.Perimeter, 1)^2);
            cen   = hypot(p.Centroid(1) - cols/2, p.Centroid(2) - rows/2) / hypot(cols/2, rows/2);
            touch = nnz(m & border) / nnz(border);
            score = p.Solidity^2 * circ * (1 - 0.6 * cen) * sqrt(p.Area / (rows * cols)) ...
                    * max(0, 1 - 5 * touch);
            cand(end+1) = struct('score', score, 'mask', m, 'solidity', p.Solidity); %#ok<AGROW>
        end
    end
    if isempty(cand)
        initial_mask = (cluster_map == mode(cluster_map(dist_center < 0.25)));
    else
        [~, order] = sort([cand.score], 'descend');
        cand = cand(order);
        initial_mask = cand(1).mask;  sol = cand(1).solidity;
        for j = 2:numel(cand)
            if any(any(imdilate(initial_mask, strel('disk', 2)) & cand(j).mask))
                u = imfill(initial_mask | cand(j).mask, 'holes');
                us = regionprops(u, 'Solidity');
                if numel(us) == 1 && us.Solidity >= max(0.85, 0.9 * sol)
                    initial_mask = u;  sol = us.Solidity;
                end
            end
        end
    end
    maskNote = 'Cluttered background: most fruit-shaped region (convex, compact, central)';
end

if ~any(initial_mask(:))   % nothing left: fall back to the centre cluster
    initial_mask = (cluster_map == mode(cluster_map(dist_center < 0.25)));
end
initial_mask = imfill(initial_mask, 'holes');
initial_mask = bwareafilt(initial_mask, 1);
stages = save_stage(stages, outDir, initial_mask, 'initial_mask', 'Initial mask', ...
    [maskNote ', holes filled, largest region kept'], 'clusters');

% ======================= 7. ACTIVE CONTOUR =======================
% Run on chromaticity only (a*, b*): a shadow changes L*, not colour.
refined_mask = activecontour(lab(:,:,2:3), initial_mask, 100, 'Chan-Vese');
% Only let the contour adjust the edge, not grow into new regions.
refined_mask = refined_mask & imdilate(initial_mask, strel('disk', 10));% Chan-Vese splits the image into two colour regions. On a busy background
% it can spill into leaves of a similar colour, so if the area changes by
% more than 40% the contour is not trusted and the initial mask is kept.
grow = nnz(refined_mask) / max(1, nnz(initial_mask));
if cluttered && (grow > 1.4 || grow < 0.6)
    refined_mask = initial_mask;
end
stages = save_stage(stages, outDir, refined_mask, 'active_contour', 'Active contour', ...
    'Chan-Vese active contour, 100 iterations on L*a*b*', 'initial_mask', initial_mask);

% ======================= 8. MORPHOLOGICAL CLEAN-UP =======================
mask = imopen(refined_mask, strel('disk', 3));
mask = imclose(mask, strel('disk', 5));
mask = imfill(mask, 'holes');
mask = bwareafilt(mask, 1);
% Opening with a disk about 1/12 of the fruit's diameter removes anything
% thinner than that still attached to it: stems, stalks, leaf tips.
eqd = sqrt(4 * nnz(mask) / pi);
mask = imopen(mask, strel('disk', max(3, round(eqd / 12))));
mask = imfill(mask, 'holes');
mask = bwareafilt(mask, 1);
stages = save_stage(stages, outDir, mask, 'mask', 'Final mask', ...
    'Opening, closing, hole filling, large opening (removes stems), largest region kept', 'active_contour', refined_mask);

% Sanity check: fruit should cover a plausible fraction of the image
frac = nnz(mask) / numel(mask);
ok = frac > 0.03 && frac < 0.90;

% ======================= 9. SEGMENTED FRUIT =======================
segmented_img = enhanced;
segmented_img(repmat(~mask, [1 1 3])) = 0;
stages = save_stage(stages, outDir, segmented_img, 'segmented', 'Segmented fruit', ...
    'Final mask applied to the enhanced image, background set to black', 'mask', enhanced);

% ======================= 10. FEATURES (Units 1-2) =======================
feats = struct();
if ok
    [f, names] = extract_features(enhanced, mask);
    for k = 1:numel(f)
        feats.(names{k}) = f(k);   % each feature becomes a named field
    end
end

% ======================= 11. MATURITY STAGE =======================
% Linear SVM trained by run_mango_training.m on the features above
% (mango_model.mat next to this file). Without it the stage stays empty.
maturity = struct('stage', '', 'confidence', NaN, 'source', 'none');
modelFile = fullfile(fileparts(mfilename('fullpath')), 'mango_model.mat');
if ok && isfile(modelFile)
    S = load(modelFile);                   % S.mdl, S.featNames
    x = zeros(1, numel(S.featNames));
    for k = 1:numel(S.featNames)
        if isfield(feats, S.featNames{k}), x(k) = feats.(S.featNames{k}); end
    end
    % Without the Statistics and Machine Learning Toolbox the model loads as
    % an unusable object and predict fails, so the stage just stays empty.
    try
        [lab, score] = predict(S.mdl, x);
        s = exp(score - max(score));  s = s / sum(s);   % soft-max over SVM scores
        maturity.stage = char(string(lab));
        maturity.confidence = max(s) * 100;
        maturity.source = 'model';
    catch err
        warning('Maturity stage skipped: %s', err.message);
    end
end

% ======================= SAVE RESULTS =======================
out = struct();
out.version = 7;   % 5: mask = all non-background clusters; 6: maturity stage; 7: cluttered backgrounds
out.ok = ok;
out.stages = stages;
out.images = struct();
for k = 1:numel(stages)
    out.images.(stages(k).key) = stages(k).file;
end
out.features = feats;
out.maturity = maturity;

jsonPath = fullfile(outDir, 'results.json');
fid = fopen(jsonPath, 'w');
fwrite(fid, jsonencode(out, 'PrettyPrint', true), 'char');
fclose(fid);

if showFigure
    figure('Name', 'Crop pipeline', 'Position', [50 50 1500 700]);
    for k = 1:numel(stages)
        subplot(2, ceil(numel(stages) / 2), k);
        imshow(imread(fullfile(outDir, stages(k).file)));
        title(sprintf('%d. %s', k, stages(k).title));
    end
    fprintf('Stage images saved in %s\n', outDir);
end
end


% ======================= HELPERS =======================

function stages = save_stage(stages, outDir, im, key, title, operation, inputKey, prev)
% Write one stage image as NN_<key>.png and add it to the stage list.
% If prev (the stage's input image) is given, also save NN_<key>_change.png
% showing what this stage changed.
n = numel(stages) + 1;
file = sprintf('%02d_%s.png', n, key);
if ~islogical(im), im = im2uint8(im); end   % 8-bit PNG the browser can show
imwrite(im, fullfile(outDir, file));
stages(n).key = key;
stages(n).title = title;
stages(n).operation = operation;
stages(n).input = inputKey;
stages(n).file = file;
stages(n).change = '';
stages(n).change_note = '';
if nargin < 8, return; end

if islogical(im) && islogical(prev)
    % Masks: green = pixels added, red = pixels removed, grey = unchanged
    added = im & ~prev;  removed = ~im & prev;  kept = im & prev;
    view = cat(3, removed, added, false(size(im))) + 0.35 * repmat(kept, [1 1 3]);
    note = sprintf('%.1f%% of pixels added, %.1f%% removed', ...
        100 * mean(added(:)), 100 * mean(removed(:)));
else
    % Images: absolute difference, stretched so small changes are visible
    if ~islogical(prev), prev = im2uint8(prev); end
    d = sum(abs(double(im) - double(prev)), 3) / size(im, 3);
    v = sort(d(:));
    hi = max(v(ceil(0.99 * numel(v))), eps);   % 99th percentile = white
    view = min(d / hi, 1);
    note = sprintf('%.1f%% of pixels changed, mean change %.1f grey levels', ...
        100 * mean(d(:) > 0), mean(d(:)));
end
changeFile = sprintf('%02d_%s_change.png', n, key);
imwrite(im2uint8(view), fullfile(outDir, changeFile));
stages(n).change = changeFile;
stages(n).change_note = note;
end


function [f, names] = extract_features(img, mask)
% Same as extract_features.m
f = []; names = {};

% ---- Colour features (inside the mask only) ----
lab = rgb2lab(img);  hsv = rgb2hsv(img);
chans = {lab(:,:,1), lab(:,:,2), lab(:,:,3), hsv(:,:,2), hsv(:,:,3)};
cn    = {'L', 'a', 'b', 'S', 'V'};
for k = 1:5
    v = chans{k}(mask);
    f(end+1) = mean(v);  names{end+1} = ['mean_' cn{k}];
    f(end+1) = std(v);   names{end+1} = ['std_'  cn{k}];
end

% Fraction of fruit pixels that are green / yellow / red-orange
H = hsv(:,:,1);  S = hsv(:,:,2);
Hm = H(mask);    Sm = S(mask);
f(end+1) = mean(Hm >= 0.17 & Hm < 0.45 & Sm > 0.2);  names{end+1} = 'frac_green';
f(end+1) = mean(Hm >= 0.08 & Hm < 0.17 & Sm > 0.2);  names{end+1} = 'frac_yellow';
f(end+1) = mean((Hm < 0.08 | Hm > 0.95) & Sm > 0.2); names{end+1} = 'frac_red';

% ---- Texture features ----
gray = rgb2gray(img);
ent = entropyfilt(gray);                    % local entropy map
f(end+1) = mean(ent(mask));  names{end+1} = 'mean_entropy';

stats = regionprops(mask, 'BoundingBox', 'Area', 'Eccentricity', ...
    'Solidity', 'Extent');
bb = round(stats(1).BoundingBox);
crop = gray(bb(2):bb(2)+bb(4)-1, bb(1):bb(1)+bb(3)-1);
cm   = mask(bb(2):bb(2)+bb(4)-1, bb(1):bb(1)+bb(3)-1);
crop(~cm) = uint8(mean(crop(cm)));          % neutral fill outside fruit
glcm = graycomatrix(crop, 'NumLevels', 32, 'Offset', [0 1; -1 1; -1 0; -1 -1]);
gp = graycoprops(glcm, {'Contrast', 'Homogeneity', 'Energy'});
f(end+1) = mean(gp.Contrast);     names{end+1} = 'glcm_contrast';
f(end+1) = mean(gp.Homogeneity);  names{end+1} = 'glcm_homogeneity';
f(end+1) = mean(gp.Energy);       names{end+1} = 'glcm_energy';

% ---- Shape / area features ----
f(end+1) = stats(1).Area / numel(mask);  names{end+1} = 'area_fraction';
f(end+1) = stats(1).Eccentricity;        names{end+1} = 'eccentricity';
f(end+1) = stats(1).Solidity;            names{end+1} = 'solidity';
f(end+1) = stats(1).Extent;              names{end+1} = 'extent';

[bands, ~] = dft_bands(img);
f = [f bands];
names = [names, {'dft_low', 'dft_mid', 'dft_high'}];
end


function [bands, spectrum] = dft_bands(img)
% Same as dft_bands.m (Unit 2)
g = im2double(rgb2gray(imresize(img, [256 256])));
F = fftshift(fft2(g));                  % 2-D DFT, zero frequency moved to the centre
spectrum = mat2gray(log(1 + abs(F)));   % log scale so the spectrum is visible

P = abs(F).^2;                          % power at each frequency
P(129,129) = 0;                         % remove DC term (average brightness)
[X, Y] = meshgrid(1:256, 1:256);
R = hypot(X - 129, Y - 129);            % distance from centre = spatial frequency
total = sum(P(:));
bands = [sum(P(R <= 16)) / total, ...
    sum(P(R > 16 & R <= 48)) / total, ...
    sum(P(R > 48)) / total];       % fraction of energy: low, mid, high
end
