% segment_leaf.m - separate the leaf from the background
%
%   [mask, ok, info, stages] = segment_leaf(den, refine, method)
%
%   den     preprocessed RGB image (see leaf_preprocess.m)
%   refine  run a Chan-Vese active contour afterwards (default false;
%           it tends to grow into the soft shadow around the leaf)
%   method  'kmeans' (default), 'border', 'edges', 'focus' or 'auto'
%
%   kmeans  cluster L*a*b* + local sharpness; border clusters that are not
%           leaf-coloured (or are blurred) are background
%   border  background colour from the image border, Otsu on distance
%   edges   Canny outline, closed and filled, most leaf-like blob
%   focus   sharp (in-focus) region, for photos taken on the tree
%   auto    kmeans, falling back to focus / edges / border when the
%           kmeans mask looks wrong
%
%   stages  intermediate images for the dashboard (clusters, union,
%           opened, cleaned)
function [mask, ok, info, stages] = segment_leaf(den, refine, method)

if nargin < 2 || isempty(refine), refine = false;    end
if nargin < 3 || isempty(method), method = 'kmeans'; end

CLUTTER = 8;    % border colour spread above this = busy background

switch lower(method)
    case 'border'
        [mask, stages] = seg_border(den);
        used = 'border';
    case 'kmeans'
        [mask, stages] = seg_kmeans(den);
        used = 'kmeans';
    case 'edges'
        [mask, stages] = seg_edges(den);
        used = 'edges';
    case 'focus'
        [mask, stages] = seg_focus(den);
        used = 'focus';
    case 'auto'
        [mask, stages] = seg_kmeans(den);
        used = 'kmeans';

        % taken on the tree: background is green too but out of focus
        if (border_contact(mask) > 0.05 || nnz(mask) > 0.5 * numel(mask)) && ...
                blurred_leafy_border(den)
            [mf, stf] = seg_focus(den);
            if plausible(mf)
                mask = mf;  stages = stf;
                used = 'focus (blurred green background)';
            end
        end

        % cluttered background and the mask runs into the frame
        if startsWith(used, 'kmeans') && border_spread(den) > CLUTTER && ...
                (border_contact(mask) > 0.10 || ~plausible(mask))
            [me, ste] = seg_edges(den);
            if plausible(me) && border_contact(me) < 0.02
                mask = me;  stages = ste;
                used = 'edges (busy background)';
            end
        end

        if ~plausible(mask)
            [mask, stages] = seg_border(den);
            used = 'border (kmeans failed)';
        end
    otherwise
        error('Unknown method "%s". Use kmeans, border or auto.', method);
end

if refine && nnz(mask) > 50
    try
        lab = rgb2lab(den);
        refined = activecontour(lab, mask, 60, 'Chan-Vese');
        refined = imfill(imclose(refined, strel('disk', 3)), 'holes');
        refined = bwareafilt(refined, 1);
        overlap = nnz(refined & mask) / max(nnz(refined | mask), 1);
        if plausible(refined) && overlap > 0.6
            mask = refined;
        end
    catch
        % keep the unrefined mask
    end
end

ok = plausible(mask);
info = struct('area_fraction', nnz(mask) / numel(mask), ...
              'border_contact', border_contact(mask), ...
              'method', used, 'refined', refine, ...
              'border_spread', border_spread(den));
end


% ---------------------------------------------------------------------
function [mask, stages] = seg_kmeans(den)
% k-means on L*, a*, b* and sharpness, then pick the leaf clusters.
K       = 6;
BTHR    = 0.15;    % share of the border that makes a cluster a "border cluster"
MAXFIT  = 20000;   % pixels used to fit the centres
SHADOW  = 8;       % a*b* distance to the background that counts as shadow
W_SHARP = 15;      % weight of the sharpness feature

lab = rgb2lab(den);
L = lab(:,:,1);  A = lab(:,:,2);  B = lab(:,:,3);
[h, w] = size(L);

% local sharpness = smoothed high-pass, scaled to roughly 0..1
sharp = imgaussfilt(abs(L - imgaussfilt(L, 2)), 4);
sharp = sharp / max(prctile(sharp(:), 95), eps);

X = [L(:) * 0.5, A(:), B(:), W_SHARP * min(sharp(:), 1.5)];

% fit on a random subset, then assign every pixel to its nearest centre
n = size(X, 1);
rng(0);
sel = randperm(n, min(n, MAXFIT));
if exist('kmeans', 'file') == 2
    [~, C] = kmeans(X(sel,:), K, 'Replicates', 3, 'MaxIter', 200);
else
    % no Statistics toolbox: imsegkmeans on the same subset as an n x 1 x 4 image
    [~, C] = imsegkmeans(single(reshape(X(sel,:), [], 1, 4)), K, 'NumAttempts', 3);
    C = double(C);
end
d = zeros(n, K);
for j = 1:K
    d(:,j) = sum((X - C(j,:)).^2, 2);
end
[~, idx] = min(d, [], 2);
cmap = reshape(idx, h, w);

% per-cluster border share, colour and sharpness
bshare = zeros(1, K);  chroma = zeros(1, K);  hue = zeros(1, K);  foc = zeros(1, K);
for c = 1:K
    m = (cmap == c);
    bshare(c) = border_contact(m);
    ma = mean(A(m));  mb = mean(B(m));
    chroma(c) = hypot(ma, mb);
    hue(c)    = atan2d(mb, ma);
    foc(c)    = mean(sharp(m));
end
leafCol = leaf_colour(chroma, hue, 5, 12);
blurry  = foc < 0.35 * max([foc(leafCol), eps]);

isBg = bshare > BTHR & (~leafCol | blurry);

% shadows: background chromaticity, just darker and smooth
if any(isBg)
    bg = ismember(cmap, find(isBg));
    bgAB = [mean(A(bg)), mean(B(bg))];
    for c = find(~isBg)
        m = (cmap == c);
        if ~leafCol(c) && foc(c) < 0.5 && ...
                hypot(mean(A(m)) - bgAB(1), mean(B(m)) - bgAB(2)) < SHADOW
            isBg(c) = true;
        end
    end
end
leaf = ismember(cmap, find(~isBg));

if ~any(leaf(:))
    [~, c] = min(bshare);
    leaf = (cmap == c);
end

opened  = bwareafilt(imopen(leaf, strel('disk', 3)), 1);
cleaned = bwareafilt(imfill(imclose(opened, strel('disk', 5)), 'holes'), 1);

% trim the pale halo / shadow strip along the outline: non-leaf pixels in
% an 8 px band that connect to the outside (geodesic reconstruction)
pixLeaf = leaf_colour(hypot(A, B), atan2d(B, A), 5, 12);
band  = cleaned & ~imerode(cleaned, strel('disk', 8));
cand  = band & ~pixLeaf;
seed  = cand & imdilate(~cleaned, strel('disk', 1));
cleaned = cleaned & ~imreconstruct(seed, cand);
cleaned = bwareafilt(imfill(imopen(cleaned, strel('disk', 2)), 'holes'), 1);
mask    = cleaned;

stages = struct('clusters', cmap, 'union', leaf, ...
                'opened', opened, 'cleaned', cleaned);
end


% ---------------------------------------------------------------------
function [mask, stages] = seg_edges(den)
% Canny on L* with high thresholds (80th/90th percentile of the gradient)
% so only the in-focus outline survives; close, fill, then keep the most
% solid, compact, central blob that stays off the border.
lab = rgb2lab(den);
L = lab(:,:,1) / 100;
[h, w] = size(L);

g  = imgradient(imgaussfilt(L, 1));
thr = prctile(g(:) / max(g(:)), [80 90]);
e  = edge(L, 'canny', thr, 1);

closed = imfill(imclose(e, strel('disk', 5)), 'holes');
opened = imopen(closed, strel('disk', 7));

cc = bwconncomp(opened);
best = 0;  bestScore = -1;
if cc.NumObjects > 0
    st = regionprops(cc, 'Area', 'Solidity', 'Perimeter', 'Centroid');
    for k = 1:cc.NumObjects
        if st(k).Area < 0.01 * h * w, continue; end
        r = false(h, w);  r(cc.PixelIdxList{k}) = true;
        bt   = border_contact(r);
        cen  = hypot((st(k).Centroid(2) - h/2) / (h/2), ...
                     (st(k).Centroid(1) - w/2) / (w/2)) / sqrt(2);
        circ = min(1, 4 * pi * st(k).Area / max(st(k).Perimeter, 1)^2);
        sc = st(k).Solidity^2 * circ * (1 - 0.6 * cen) * sqrt(st(k).Area) ...
             * max(0, 1 - 5 * bt);
        if sc > bestScore, bestScore = sc; best = k; end
    end
end
cleaned = false(h, w);
if best > 0
    cleaned(cc.PixelIdxList{best}) = true;
    cleaned = imfill(cleaned, 'holes');
end
mask = cleaned;

stages = struct('clusters', [], 'union', e, 'opened', opened, 'cleaned', cleaned);
end


% ---------------------------------------------------------------------
function [mask, stages] = seg_focus(den)
% In-focus region: Otsu on the log sharpness map, close, fill, open,
% largest blob. Works when the background is blurred foliage.
lab = rgb2lab(den);
L = lab(:,:,1);
[h, w] = size(L);
hp = imgaussfilt(abs(L - imgaussfilt(L, 2)), 3);
lg = log(hp + 0.05);
lg = mat2gray(lg, double([prctile(lg(:), 1), prctile(lg(:), 99.5)]));
raw = imbinarize(lg, graythresh(lg));

r = max(3, round(0.015 * min(h, w)));
closed  = imfill(imclose(raw, strel('disk', r)), 'holes');
opened  = imopen(closed, strel('disk', r));
cleaned = imfill(bwareafilt(opened, 1), 'holes');
mask = cleaned;

stages = struct('clusters', [], 'union', raw, 'opened', opened, 'cleaned', cleaned);
end


% ---------------------------------------------------------------------
function [mask, stages] = seg_border(den)
% Background = median colour of the border strip; Otsu on distance to it.
lab = rgb2lab(den);
bm = border_strip(size(lab, 1), size(lab, 2), 0.04);
bg = zeros(1, 3);
for c = 1:3
    ch = lab(:,:,c);
    bg(c) = median(ch(bm));
end

dist = sqrt((lab(:,:,1) - bg(1)).^2 + (lab(:,:,2) - bg(2)).^2 + (lab(:,:,3) - bg(3)).^2);
dist = mat2gray(dist);

raw     = imbinarize(dist, graythresh(dist));
opened  = bwareafilt(imopen(raw, strel('disk', 3)), 1);
cleaned = bwareafilt(imfill(imclose(opened, strel('disk', 5)), 'holes'), 1);
mask    = cleaned;

stages = struct('clusters', [], 'union', raw, 'opened', opened, 'cleaned', cleaned);
end


% ---------------------------------------------------------------------
function tf = blurred_leafy_border(den)
% Border mostly foliage-coloured and out of focus -> photo on the tree.
% Stricter chroma than leaf_colour's default so a greyish-green backdrop
% does not count.
lab = rgb2lab(den);
L = lab(:,:,1);  A = lab(:,:,2);  B = lab(:,:,3);
leafy = leaf_colour(hypot(A, B), atan2d(B, A), 10, 15);
hp = imgaussfilt(abs(L - imgaussfilt(L, 2)), 3);
bm = border_strip(size(L, 1), size(L, 2), 0.06);
fracLeafy = nnz(bm & leafy) / nnz(bm);
blurRatio = median(hp(bm)) / max(prctile(hp(:), 95), eps);
tf = fracLeafy > 0.6 && blurRatio < 0.2;
end


% ---------------------------------------------------------------------
function s = border_spread(den)
% Median a*b* distance of border pixels from their median: ~1-3 for a
% plain backdrop, higher for a cluttered scene.
lab = rgb2lab(den);
bm = border_strip(size(lab, 1), size(lab, 2), 0.04);
A = lab(:,:,2);  B = lab(:,:,3);
a = A(bm);  b = B(bm);
s = median(hypot(a - median(a), b - median(b)));
end


% ---------------------------------------------------------------------
function tf = leaf_colour(C, H, cGreen, cWarm)
% Greens (hue 85-175) above cGreen chroma, or yellows/browns (hue 15-85)
% above cWarm chroma. White, grey, blue and black fail.
tf = (C > cGreen & H >= 85 & H < 175) | (C > cWarm & H > 15 & H < 85);
end


function bm = border_strip(h, w, frac)
b = max(5, round(frac * min(h, w)));
bm = true(h, w);
bm(b+1:end-b, b+1:end-b) = false;
end


function f = border_contact(m)
f = mean([m(1,:), m(end,:), m(:,1)', m(:,end)']);
end


function tf = plausible(m)
f = nnz(m) / numel(m);
tf = f > 0.02 && f <= 1;
end
