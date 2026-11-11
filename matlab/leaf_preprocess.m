% matlab/leaf_preprocess.m
% Unit 1 (sampling, quantisation, noise) + Unit 3 (histogram processing)
% applied to a leaf photograph.
%
%   den  - resized + median filtered. ALL measurements are made on this.
%   enh  - den + CLAHE on L*. For display only: equalisation changes the
%          colour statistics, so it must not be used for feature extraction.
function [den, enh, resized] = leaf_preprocess(img)

if size(img, 3) == 1, img = repmat(img, [1 1 3]); end
img = img(:,:,1:3);

% ---- Sampling: resize so the longest side is 384 px -------------------
scale   = 384 / max(size(img, 1), size(img, 2));
resized = imresize(img, scale, 'bilinear', 'Antialiasing', true);

% ---- Noise reduction: 3x3 median filter (non-linear spatial filter) ---
den = resized;
for c = 1:3
    den(:,:,c) = medfilt2(resized(:,:,c), [3 3]);
end

% ---- Contrast: CLAHE on L* only, so hue and chroma are left alone -----
lab = rgb2lab(den);
lab(:,:,1) = adapthisteq(lab(:,:,1) / 100, 'ClipLimit', 0.01) * 100;
enh = im2uint8(lab2rgb(lab));
end
