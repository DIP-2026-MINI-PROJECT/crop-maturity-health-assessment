%% run_transforms.m  --  press Run.
%
% Every panel here corresponds to something the pipeline actually does.
%
% Figure 1  Quantisation (as used by the GLCM) and the 2-D DFT, shown both
%           over the whole frame and over the segmented leaf, which is what
%           the dft_low / dft_mid / dft_high features are computed from.
%
% Figure 2  Frequency-domain low-pass filters (ideal, Butterworth, Gaussian)
%           against the 3x3 median filter the pipeline actually uses. This
%           is why the pipeline denoises in the spatial domain.

% Default: <repo>\dataset\MangoLeafBD. Replace with your own path if it is elsewhere.
DATASET = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'dataset', 'MangoLeafBD');
IMAGE   = '';      % optional: one exact photo
CLASS   = '';      % optional: 'Sooty Mould' -> random image from that class
D0      = 30;      % cutoff radius for the low-pass filters
BORDER  = 2;       % Butterworth order

%% ------------------------------------------------------------------------
clc;
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
addpath(here);

CLASSES = {'Healthy', 'Anthracnose', 'Bacterial Canker', 'Cutting Weevil', ...
           'Die Back', 'Gall Midge', 'Powdery Mildew', 'Sooty Mould'};

% ---- Pick an image ------------------------------------------------------
if ~isempty(IMAGE)
    assert(isfile(IMAGE), 'IMAGE does not exist:\n  %s', IMAGE);
    imagePath = IMAGE;  trueClass = '';
else
    assert(isfolder(DATASET), 'DATASET folder does not exist:\n  %s', DATASET);
    for depth = 1:3
        if any(cellfun(@(c) isfolder(fullfile(DATASET, c)), CLASSES)), break; end
        subs = dir(DATASET);
        subs = subs([subs.isdir] & ~startsWith({subs.name}, '.'));
        moved = false;
        for s = 1:numel(subs)
            cand = fullfile(DATASET, subs(s).name);
            if any(cellfun(@(c) isfolder(fullfile(cand, c)), CLASSES))
                DATASET = cand;  moved = true;  break
            end
        end
        if ~moved
            if numel(subs) == 1, DATASET = fullfile(DATASET, subs(1).name); else, break; end
        end
    end
    avail = CLASSES(cellfun(@(c) isfolder(fullfile(DATASET, c)), CLASSES));
    assert(~isempty(avail), 'No class folders inside:\n  %s', DATASET);
    if isempty(CLASS), CLASS = avail{randi(numel(avail))}; end
    trueClass = CLASS;
    files = [dir(fullfile(DATASET, CLASS, '*.jpg')); ...
             dir(fullfile(DATASET, CLASS, '*.jpeg')); ...
             dir(fullfile(DATASET, CLASS, '*.png'))];
    assert(~isempty(files), 'No images in %s', fullfile(DATASET, CLASS));
    rng('shuffle');
    pick = files(randi(numel(files)));
    imagePath = fullfile(pick.folder, pick.name);
    fprintf('Class: %s\n', trueClass);
end
fprintf('Image: %s\n\n', imagePath);

img = imread(imagePath);
if size(img,3) == 1, img = repmat(img, [1 1 3]); end
img = img(:,:,1:3);

% Run the real preprocessing and segmentation, so the panels below show
% exactly what the pipeline works on.
[den, ~, ~] = leaf_preprocess(img);
[mask, ok]  = segment_leaf(den, false, 'auto');
if ~ok
    warning('Segmentation failed; the masked panels will use the whole frame.');
    mask = true(size(den,1), size(den,2));
end

gray = rgb2gray(den);

%% ===================== FIGURE 1: quantisation + DFT =====================
% ---- Quantisation (Unit 1) ---------------------------------------------
% 32 levels is exactly what graycomatrix uses inside leaf_features.m
q32 = quantize_bits(gray, 5);
q4  = quantize_bits(gray, 2);

% ---- DFT over the whole frame (what the features USED to use) ----------
gWhole = im2double(imresize(gray, [256 256]));
[specWhole, bandsWhole] = dft_bands(gWhole);

% ---- DFT over the segmented leaf (what the features use NOW) -----------
st = regionprops(mask, 'BoundingBox');
bb = round(st(1).BoundingBox);
r1 = max(bb(2),1);  r2 = min(bb(2)+bb(4)-1, size(gray,1));
c1 = max(bb(1),1);  c2 = min(bb(1)+bb(3)-1, size(gray,2));
crop = gray(r1:r2, c1:c2);
cm   = mask(r1:r2, c1:c2);
crop(~cm) = uint8(mean(crop(cm)));            % neutral fill, as leaf_features does
gLeaf = im2double(imresize(crop, [256 256]));
[specLeaf, bandsLeaf] = dft_bands(gLeaf);

figure('Name', 'Leaf - quantisation and the 2-D DFT', 'Position', [40 60 1500 780]);

subplot(2,4,1); imshow(gray); title('1. Grey (8 bits, 256 levels)');
subplot(2,4,2); imshow(q32);  title('2. Quantised to 32 levels (GLCM input)');
subplot(2,4,3); imshow(q4);   title('3. Quantised to 4 levels');
subplot(2,4,4); imshow(den .* uint8(repmat(mask,[1 1 3])));
                title('4. Segmented leaf');

subplot(2,4,5); imshow(specWhole); title('5. DFT spectrum - whole frame');
subplot(2,4,6); imshow(gLeaf);     title('6. Leaf, background neutralised');
subplot(2,4,7); imshow(specLeaf);  title('7. DFT spectrum - leaf only');

subplot(2,4,8);
bar([bandsWhole(:), bandsLeaf(:)] * 100);
set(gca, 'XTickLabel', {'low','mid','high'});
ylabel('% of energy'); legend({'whole frame','leaf only'}, 'Location', 'north');
title('8. Radial band energy'); grid on

fprintf('DFT bands, whole frame : low %.1f%%  mid %.1f%%  high %.1f%%\n', bandsWhole*100);
fprintf('DFT bands, leaf only   : low %.1f%%  mid %.1f%%  high %.1f%%\n', bandsLeaf*100);
fprintf(['\nThe features use the LEAF version. Over the whole frame the\n' ...
         'background dominates the spectrum, so the numbers described the\n' ...
         'photo rather than the leaf.\n']);

%% ===================== FIGURE 2: frequency vs spatial denoising =========
F = fftshift(fft2(gWhole));
[X, Y] = meshgrid(1:256, 1:256);
D = hypot(X - 129, Y - 129);

Hideal = double(D <= D0);
Hbutt  = 1 ./ (1 + (D ./ D0).^(2 * BORDER));
Hgauss = exp(-(D.^2) / (2 * D0^2));

fIdeal = real(ifft2(ifftshift(Hideal .* F)));
fButt  = real(ifft2(ifftshift(Hbutt  .* F)));
fGauss = real(ifft2(ifftshift(Hgauss .* F)));
fMed   = medfilt2(gWhole, [3 3]);

figure('Name', 'Leaf - frequency domain filtering vs the median filter', ...
       'Position', [60 40 1500 780]);

subplot(2,4,1); imshow(gWhole);     title('1. Input');
subplot(2,4,2); imshow(Hideal);     title(sprintf('2. Ideal LPF mask (D0=%d)', D0));
subplot(2,4,3); imshow(Hbutt);      title(sprintf('3. Butterworth mask (n=%d)', BORDER));
subplot(2,4,4); imshow(Hgauss);     title('4. Gaussian mask');
subplot(2,4,5); imshow(fIdeal, []); title('5. Ideal result (rings)');
subplot(2,4,6); imshow(fButt,  []); title('6. Butterworth result');
subplot(2,4,7); imshow(fGauss, []); title('7. Gaussian result');
subplot(2,4,8); imshow(fMed);       title('8. 3x3 median (what we use)');

fprintf('\nGibbs overshoot past the original intensity range:\n');
fprintf('  original range   [%.3f, %.3f]\n', min(gWhole(:)), max(gWhole(:)));
for nf = {{'ideal', fIdeal}, {'butterworth', fButt}, {'gaussian', fGauss}}
    nm = nf{1}{1};  o = nf{1}{2};
    fprintf('  %-12s overshoot %.4f\n', nm, max(max(o(:)) - max(gWhole(:)), 0));
end
fprintf(['\nAll three low-pass filters blur the lesion edges that the\n' ...
         'segmentation depends on, and the ideal one rings. The median\n' ...
         'filter removes specks while leaving edges sharp, which is why\n' ...
         'leaf_preprocess.m uses it.\n']);


%% ------------------------------------------------------------------------
function q = quantize_bits(img, bits)
% Uniform quantisation to 2^bits grey levels.
levels = 2^bits;
step   = 256 / levels;
q = uint8(floor(double(img) / step) * step + step/2);
end

function [spec, bands] = dft_bands(g)
% Log spectrum and the fraction of power in 3 radial bands.
F = fftshift(fft2(g));
spec = mat2gray(log(1 + abs(F)));
P = abs(F).^2;
P(129, 129) = 0;                       % drop DC
[X, Y] = meshgrid(1:256, 1:256);
R = hypot(X - 129, Y - 129);
tot = sum(P(:));
if tot <= 0, tot = 1; end
bands = [sum(P(R <= 16)), sum(P(R > 16 & R <= 48)), sum(P(R > 48))] / tot;
end
