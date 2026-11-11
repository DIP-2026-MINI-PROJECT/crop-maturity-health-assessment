% matlab/leaf_demo.m
% Run this in MATLAB to see every stage of the leaf pipeline on one image.
%
%   leaf_demo                    % random image from the dataset
%   leaf_demo('path\to\leaf.jpg')
%
% Produces three figures and prints the verdict in the Command Window.
function leaf_demo(imagePath)

% Make sure the other leaf_*.m files are reachable: they live next to this
% file, wherever you put it. No particular project layout is required.
addpath(fileparts(mfilename('fullpath')));

if nargin < 1 || isempty(imagePath)
    % Only this branch needs the dataset and the project folder layout.
    root = find_root();
    dataDir = fullfile(root, 'dataset', 'MangoLeafBD');
    assert(isfolder(dataDir), ...
        ['No image path given, so leaf_demo looked for the dataset at %s ' ...
         'and did not find it.\nEither put the MangoLeafBD class folders ' ...
         'there, or just call:\n    leaf_demo(''C:\\path\\to\\a_leaf.jpg'')'], dataDir);
    ds = imageDatastore(dataDir, 'IncludeSubfolders', true, 'LabelSource', 'foldernames');
    rng('shuffle');
    i = randi(numel(ds.Files));
    imagePath = ds.Files{i};
    fprintf('True class: %s\n', char(string(ds.Labels(i))));
end
fprintf('Image: %s\n', imagePath);

img = imread(imagePath);
if size(img, 3) == 1, img = repmat(img, [1 1 3]); end
img = img(:,:,1:3);

% ===================== FIGURE 1: preprocessing ========================
scale   = 384 / max(size(img, 1), size(img, 2));
resized = imresize(img, scale, 'bilinear', 'Antialiasing', true);
den = resized;
for c = 1:3, den(:,:,c) = medfilt2(resized(:,:,c), [3 3]); end
removed = mat2gray(rgb2gray(imabsdiff(resized, den)));

lab = rgb2lab(den);
Lbefore = lab(:,:,1);
Lafter  = adapthisteq(Lbefore / 100, 'ClipLimit', 0.01) * 100;
labE = lab; labE(:,:,1) = Lafter;
enh = im2uint8(lab2rgb(labE));

figure('Name', 'Leaf - Unit 1 and 3: preprocessing', 'Position', [40 60 1500 760]);
subplot(2,4,1); imshow(img);      title(sprintf('1. Original (%dx%d)', size(img,2), size(img,1)));
subplot(2,4,2); imshow(resized);  title(sprintf('2. Sampling: %dx%d', size(resized,2), size(resized,1)));
subplot(2,4,3); imshow(den);      title('3. 3x3 median filter');
subplot(2,4,4); imshow(removed);  title('   noise removed (amplified)');
subplot(2,4,5); imshow(mat2gray(Lbefore)); title('4. L* before CLAHE');
subplot(2,4,6); imshow(mat2gray(Lafter));  title('5. L* after CLAHE');
subplot(2,4,7);
histogram(Lbefore(:), 64); hold on; histogram(Lafter(:), 64); hold off;
legend('before', 'after', 'Location', 'north'); title('6. L* histogram'); axis tight
subplot(2,4,8); imshow(enh); title('7. Contrast enhanced (display only)');

% ===================== FIGURE 2: segmentation + morphology ============
% stages holds the real intermediate images, so nothing is recomputed here
% and this figure can never drift out of step with segment_leaf.m
[mask, ok, info, stages] = segment_leaf(den, false, 'auto');
fprintf('Segmentation: %s  ok=%d  (area %.1f%% of frame)\n', ...
        info.method, ok, 100*info.area_fraction);

BTHR = 0.15;
cmap   = stages.clusters;
union0 = stages.union;
opened = stages.opened;
closed = stages.cleaned;

% border occupancy of each cluster, for the bar chart
if ~isempty(cmap)
    K = max(cmap(:));
    bc = zeros(1, K);
    for c = 1:K
        m = (cmap == c);
        bc(c) = mean([m(1,:), m(end,:), m(:,1)', m(:,end)']);
    end
    nLeaf = nnz(bc <= BTHR);
else
    K = 0;  bc = [];  nLeaf = 0;
end

figure('Name', 'Leaf - Unit 4: k-means segmentation and morphology', ...
       'Position', [60 40 1500 760]);
subplot(2,4,1); imshow(den);  title('1. Input (denoised)');

subplot(2,4,2);
if ~isempty(cmap)
    imshow(label2rgb(cmap, 'jet', 'k', 'shuffle'));
    title(sprintf('2. k-means clusters (k=%d)', K));
else
    imshow(union0); title('2. Otsu threshold (border method)');
end

subplot(2,4,3);
if ~isempty(bc)
    bar(bc * 100); hold on; yline(BTHR*100, 'r--', 'LineWidth', 1.4); hold off
    xlabel('cluster'); ylabel('% of image border');
    title('3. Border occupancy'); grid on; ylim([0 100])
else
    axis off; title('3. (not used by the border method)');
end

subplot(2,4,4); imshow(union0);
if ~isempty(cmap)
    title(sprintf('4. Union of %d leaf clusters', nLeaf));
else
    title('4. Raw threshold');
end
subplot(2,4,5); imshow(opened);   title('5. Opening + largest blob');
subplot(2,4,6); imshow(closed);   title('6. Closing + hole fill');
subplot(2,4,7); imshow(imoverlay(den, bwperim(mask,8), [0 1 0]));
                title(sprintf('7. Final boundary (%s)', info.method));
subplot(2,4,8); imshow(den .* uint8(repmat(mask,[1 1 3])));
                title('8. Segmented leaf');

if ~ok
    warning('Segmentation failed its sanity check - stopping here.');
    return
end

% ===================== FIGURE 3: lesions and verdict ==================
M = leaf_lesions(den, mask);
labels = uint8(1*M.healthy + 2*M.chlorotic + 3*M.necrotic + 4*M.powdery + 5*M.sooty);
cmap = [0 0 0; 0.24 0.67 0.27; 0.94 0.80 0.16; 0.78 0.27 0.18; 0.92 0.92 0.96; 0.10 0.10 0.12];

gray = rgb2gray(den);
bh = imbothat(gray, strel('disk', 5));
v = double(bh(mask)); sv = sort(v);
p99 = sv(max(1, ceil(0.99*numel(sv))));
specks = imopen(bh > max(0.05*255, p99*0.5) & mask, strel('disk',1));

[f, names] = leaf_features(den, mask, M);
H = classify_leaf(f, names, M);

figure('Name', 'Leaf - health assessment', 'Position', [80 20 1500 760]);
subplot(2,4,1); imshow(den);                        title('Leaf');
subplot(2,4,2); imshow(ind2rgb(labels, cmap));      title('Lesion classes');
subplot(2,4,3); imshow(M.lesion);                   title('Lesion mask (binary)');
subplot(2,4,4); imshow(imoverlay(den, M.lesion & ~imerode(M.lesion, strel('disk',1)), [1 0 0]));
                                                    title('Lesion outlines');
subplot(2,4,5); imshow(bh, []);                     title('Black top-hat');
subplot(2,4,6); imshow(specks);                     title('Detected specks');
subplot(2,4,7);
bar([H.frac_healthy, H.frac_chlorotic, H.frac_necrotic, H.frac_powdery, H.frac_sooty]*100);
set(gca, 'XTickLabel', {'healthy','chlorotic','necrotic','powdery','sooty'});
ylabel('% of leaf'); title('Tissue composition'); xtickangle(30); grid on
subplot(2,4,8); axis off
text(0, 0.9, sprintf('Condition: %s', H.condition), 'FontWeight', 'bold', 'FontSize', 12);
text(0, 0.7, sprintf('Severity: %s', H.severity), 'FontSize', 11);
text(0, 0.55, sprintf('Affected area: %.1f%%', H.affected_area), 'FontSize', 11);
text(0, 0.40, sprintf('Symptom: %s', H.symptom), 'FontSize', 11);
if ~isnan(H.confidence)
    text(0, 0.25, sprintf('Confidence: %.0f%% (%s)', H.confidence, H.source), 'FontSize', 11);
else
    text(0, 0.25, sprintf('Decided by: %s', H.source), 'FontSize', 11);
end

fprintf('\n--- VERDICT ---\nCondition : %s\nSeverity  : %s\nAffected  : %.1f%%\nSymptom   : %s\n', ...
        H.condition, H.severity, H.affected_area, H.symptom);
fprintf('\n--- FEATURES ---\n');
for k = 1:numel(names)
    fprintf('  %-20s %10.4f\n', names{k}, f(k));
end
end


function root = find_root()
here = fileparts(mfilename('fullpath'));
root = here;
while ~isfolder(fullfile(root, 'matlab'))
    p = fileparts(root);
    if strcmp(p, root)
        error(['Could not find a "matlab" folder above %s.\n' ...
               'Pass an image path instead:  leaf_demo(''C:\\path\\to\\leaf.jpg'')'], here);
    end
    root = p;
end
end
