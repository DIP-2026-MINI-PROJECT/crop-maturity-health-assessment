% leaf_features.m - 59 features for one segmented leaf, measured on den
% (median filtered, not contrast equalised)
%
%   colour 10 | lesion area 6 | lesion blobs 3 | texture 6 | shape 6 |
%   granulometry 5 | specks 2 | DFT bands 3 | hue histogram 8 | LBP 10
function [f, names] = leaf_features(den, mask, M)

f = [];  names = {};
    function add(nm, v)
        f(end+1) = double(v);  names{end+1} = nm;  %#ok<AGROW>
    end

lab = rgb2lab(den);  hsv = rgb2hsv(den);
area = max(nnz(mask), 1);

% colour: mean and std per channel
chans = {lab(:,:,1), lab(:,:,2), lab(:,:,3), hsv(:,:,2), hsv(:,:,3)};
cn    = {'L', 'a', 'b', 'S', 'V'};
for k = 1:5
    v = chans{k}(mask);
    add(['mean_' cn{k}], mean(v));
    add(['std_'  cn{k}], std(v));
end

% lesion area fractions
add('frac_healthy',   nnz(M.healthy)   / area);
add('frac_chlorotic', nnz(M.chlorotic) / area);
add('frac_necrotic',  nnz(M.necrotic)  / area);
add('frac_powdery',   nnz(M.powdery)   / area);
add('frac_sooty',     nnz(M.sooty)     / area);
add('frac_lesion',    nnz(M.lesion)    / area);

% lesion blobs: count and size
cc = bwconncomp(M.lesion);
blobAreas = cellfun(@numel, cc.PixelIdxList);
blobAreas = blobAreas(blobAreas > 15);
add('lesion_count',     min(numel(blobAreas), 500) / 100);
if isempty(blobAreas)
    add('lesion_mean_area', 0);  add('lesion_max_area', 0);
else
    add('lesion_mean_area', mean(blobAreas) / area);
    add('lesion_max_area',  max(blobAreas)  / area);
end

% texture: local entropy and GLCM on the leaf's bounding box
gray = rgb2gray(den);
ent  = entropyfilt(gray, true(11));
add('mean_entropy', mean(ent(mask)));
add('std_entropy',  std(ent(mask)));

st = regionprops(mask, 'BoundingBox', 'Area', 'Eccentricity', 'Solidity', ...
                       'Extent', 'Perimeter', 'ConvexArea');
bb = round(st(1).BoundingBox);
r1 = max(bb(2), 1);  r2 = min(bb(2) + bb(4) - 1, size(gray, 1));
c1 = max(bb(1), 1);  c2 = min(bb(1) + bb(3) - 1, size(gray, 2));
crop = gray(r1:r2, c1:c2);
cm   = mask(r1:r2, c1:c2);
crop(~cm) = uint8(mean(crop(cm)));            % fill outside the leaf with its mean
glcm = graycomatrix(crop, 'NumLevels', 32, 'Offset', [0 1; -1 1; -1 0; -1 -1]);
gp = graycoprops(glcm, {'Contrast', 'Homogeneity', 'Energy', 'Correlation'});
add('glcm_contrast',    mean(gp.Contrast));
add('glcm_homogeneity', mean(gp.Homogeneity));
add('glcm_energy',      mean(gp.Energy));
add('glcm_correlation', mean(gp.Correlation));

% shape (chewed margins lower solidity / circularity)
add('area_fraction', st(1).Area / numel(mask));
add('eccentricity',  st(1).Eccentricity);
add('solidity',      st(1).Solidity);
add('extent',        st(1).Extent);
add('circularity',   4 * pi * st(1).Area / (st(1).Perimeter^2 + eps));
add('convex_deficiency', 1 - st(1).Area / max(st(1).ConvexArea, 1));

% granulometry: share of lesion area removed by openings of growing radius
radii = [1 2 4 8 16];
total = nnz(M.lesion);
prev  = total;
for r = radii
    if total == 0
        add(sprintf('gran_%d', r), 0);
    else
        aLeft = nnz(imopen(M.lesion, strel('disk', r)));
        add(sprintf('gran_%d', r), (prev - aLeft) / total);
        prev = aLeft;
    end
end

% specks: black top-hat for small dark spots
bh = imbothat(gray, strel('disk', 5));
v  = double(bh(mask));
if isempty(v)
    sp = false(size(mask));
else
    sv  = sort(v);
    p99 = sv(max(1, ceil(0.99 * numel(sv))));
    thr = max(0.05 * 255, p99 * 0.5);
    sp  = imopen(bh > thr & mask, strel('disk', 1));
end
add('speck_frac',  nnz(sp) / area);
nSp = bwconncomp(sp).NumObjects;
add('speck_count', min(nSp, 500) / 100);

% DFT energy in low / mid / high radial bands, on the masked crop
% (whole-frame DFT was mostly measuring the background)
gf = im2double(imresize(crop, [256 256]));
F = fftshift(fft2(gf));
P = abs(F).^2;
P(129, 129) = 0;                       % drop DC
[X, Y] = meshgrid(1:256, 1:256);
R = hypot(X - 129, Y - 129);
tot = sum(P(:));
if tot <= 0, tot = 1; end
add('dft_low',  sum(P(R <= 16))             / tot);
add('dft_mid',  sum(P(R > 16 & R <= 48))    / tot);
add('dft_high', sum(P(R > 48))              / tot);

% hue histogram of coloured leaf pixels (chroma > 5), 8 bins
Am = lab(:,:,2);  Bm = lab(:,:,3);
hueL = atan2d(Bm(mask), Am(mask));
chrL = hypot(Am(mask), Bm(mask));
hueL = hueL(chrL > 5);
edgesH = [-180 0 30 60 90 110 130 150 180];
if isempty(hueL)
    hh = zeros(1, 8);
else
    hh = histcounts(hueL, edgesH) / numel(hueL);
end
hnames = {'hue_neg', 'hue_0_30', 'hue_30_60', 'hue_60_90', ...
          'hue_90_110', 'hue_110_130', 'hue_130_150', 'hue_150_180'};
for k = 1:8, add(hnames{k}, hh(k)); end

% LBP (uniform, rotation invariant, 8 neighbours, r = 1) on the same crop
lbp = extractLBPFeatures(crop, 'Upright', false, 'NumNeighbors', 8, 'Radius', 1);
lbp = lbp / max(sum(lbp), eps);
for k = 1:numel(lbp), add(sprintf('lbp_%d', k), lbp(k)); end
end
