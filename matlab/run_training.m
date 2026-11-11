%% run_training.m - extract leaf features and train the classifier
%
% 1. features for every sampled image, plus one augmented "field photo"
%    copy (zoomed in, exposure / white balance changed, slight blur)
%    -> leaf_features.csv
% 2. 5-fold CV of linear SVM, RBF SVM and random forest (folds split by
%    original image, so a copy never leaks across folds); best one saved
%    -> leaf_model.mat
%
% ~25-40 min at PER_CLASS = 150; use 20 for a quick check.

DATASET   = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'dataset', 'MangoLeafBD');
PER_CLASS = 150;      % images per class (max 500)
AUGMENT   = true;     % add an augmented copy of each image

%% ------------------------------------------------------------------------
clc;
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
addpath(here);

CLASSES = {'Healthy', 'Anthracnose', 'Bacterial Canker', 'Cutting Weevil', ...
           'Die Back', 'Gall Midge', 'Powdery Mildew', 'Sooty Mould'};

% find the folder that actually holds the class folders (zip may nest it)
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
assert(~isempty(avail), 'No class folders found inside:\n  %s', DATASET);
fprintf('Dataset: %s\n', DATASET);
fprintf('Classes: %s\n\n', strjoin(avail, ', '));

%% 1. features
csvPath = fullfile(here, 'leaf_features.csv');

rows = {}; labels = {}; groups = []; isAug = []; names = {};
failed = 0; total = 0; gid = 0;
t0 = tic;
rng(1);    % same augmentation every run

for k = 1:numel(avail)
    classDir = fullfile(DATASET, avail{k});
    files = [dir(fullfile(classDir, '*.jpg')); ...
             dir(fullfile(classDir, '*.jpeg')); ...
             dir(fullfile(classDir, '*.png'))];
    if isempty(files)
        fprintf('  %-18s no images, skipped\n', avail{k});
        continue
    end

    % spread the sample over the whole folder - files are in capture
    % order, so the first N would all be one photo session
    n = min(PER_CLASS, numel(files));
    idx = unique(round(linspace(1, numel(files), n)));

    okCount = 0;
    for i = idx
        gid = gid + 1;
        try
            img = imread(fullfile(files(i).folder, files(i).name));
        catch
            failed = failed + 1;  continue
        end
        versions = {img};
        if AUGMENT, versions{2} = augment_field(img); end
        for v = 1:numel(versions)
            total = total + 1;
            try
                [den, ~, ~] = leaf_preprocess(versions{v});
                [mask, ok] = segment_leaf(den, false, 'auto');
                if ~ok, failed = failed + 1; continue; end
                M = leaf_lesions(den, mask);
                [f, names] = leaf_features(den, mask, M);
                rows{end+1}   = f;           %#ok<SAGROW>
                labels{end+1} = avail{k};    %#ok<SAGROW>
                groups(end+1) = gid;         %#ok<SAGROW>
                isAug(end+1)  = v == 2;      %#ok<SAGROW>
                okCount = okCount + 1;
            catch
                failed = failed + 1;
            end
        end
    end
    fprintf('  %-18s %3d ok  (%.0f s elapsed)\n', avail{k}, okCount, toc(t0));
end

assert(~isempty(rows), 'No images processed successfully.');

T = array2table(vertcat(rows{:}), 'VariableNames', names);
T.label = categorical(string(labels(:)));
writetable(T, csvPath);
fprintf('\nStep 1 done: %d rows (%d augmented), %d failed segmentation.\n', ...
        height(T), nnz(isAug), failed);
fprintf('Saved %s\n\n', csvPath);

%% 2. compare classifiers
X = T{:, 1:end-1};
y = T.label;
featNames = T.Properties.VariableNames(1:end-1);
groups = groups(:);  isAug = logical(isAug(:));

fprintf('Training on %d samples, %d features, %d classes...\n\n', ...
        size(X,1), size(X,2), numel(categories(y)));

% folds by original image; the augmented copy goes with its original
ug = unique(groups);
rng(0);
foldOfGroup = mod(randperm(numel(ug)), 5) + 1;
fold = zeros(size(groups));
for g = 1:numel(ug), fold(groups == ug(g)) = foldOfGroup(g); end

makers = { ...
  'Linear SVM',    @(X, y) fitcecoc(X, y, 'Coding', 'onevsone', 'Learners', ...
                       templateSVM('KernelFunction', 'linear', 'Standardize', true)); ...
  'RBF SVM',       @(X, y) fitcecoc(X, y, 'Coding', 'onevsone', 'Learners', ...
                       templateSVM('KernelFunction', 'gaussian', 'KernelScale', 'auto', ...
                                   'Standardize', true, 'BoxConstraint', 10)); ...
  'Random forest', @(X, y) fitcensemble(X, y, 'Method', 'Bag', 'NumLearningCycles', 300, ...
                       'Learners', templateTree('NumVariablesToSample', ...
                                   round(sqrt(size(X, 2))), 'Reproducible', true))};

res = zeros(size(makers, 1), 3);    % all / originals / augmented
preds = cell(size(makers, 1), 1);
for m = 1:size(makers, 1)
    p = y;
    for k = 1:5
        tr = fold ~= k;  te = fold == k;
        mdl = makers{m, 2}(X(tr,:), y(tr));
        p(te) = predict(mdl, X(te,:));
    end
    preds{m} = p;
    res(m, 1) = mean(p == y);
    res(m, 2) = mean(p(~isAug) == y(~isAug));
    if any(isAug), res(m, 3) = mean(p(isAug) == y(isAug)); else, res(m, 3) = NaN; end
    fprintf('  %-14s  CV accuracy %5.1f%%   original photos %5.1f%%   field-style copies %5.1f%%\n', ...
            makers{m, 1}, 100 * res(m, :));
end

[~, best] = max(res(:, 1));
modelName = makers{best, 1};
acc = res(best, 1);
fprintf('\nBest: %s (%.1f%% 5-fold CV accuracy)\n', modelName, acc * 100);

figure('Name', 'Leaf classifier - confusion matrix');
confusionchart(y, preds{best});
title(sprintf('%s (%.1f%% CV accuracy)', modelName, acc * 100));

% final model on all data; SVMs are refitted with FitPosterior so the
% dashboard confidence is a probability
if contains(modelName, 'SVM')
    if startsWith(modelName, 'RBF')
        t = templateSVM('KernelFunction', 'gaussian', 'KernelScale', 'auto', ...
                        'Standardize', true, 'BoxConstraint', 10);
    else
        t = templateSVM('KernelFunction', 'linear', 'Standardize', true);
    end
    mdl = fitcecoc(X, y, 'Coding', 'onevsone', 'Learners', t, 'FitPosterior', true);
else
    mdl = makers{best, 2}(X, y);
end
mdl = compact(mdl);
cvTable = table(makers(:, 1), 100 * res(:, 1), 100 * res(:, 2), 100 * res(:, 3), ...
    'VariableNames', {'model', 'cv_all', 'cv_original', 'cv_augmented'});
save(fullfile(here, 'leaf_model.mat'), 'mdl', 'featNames', 'acc', 'modelName', 'cvTable');
fprintf('\nSaved %s\n', fullfile(here, 'leaf_model.mat'));


%% ------------------------------------------------------------------------
function out = augment_field(img)
% Studio photo -> rough "phone in the field" photo: crop 55-80% (leaf
% may touch the edge), exposure x0.7-1.3, gamma 0.8-1.25, per-channel
% gain 0.9-1.1, Gaussian blur sigma up to 1.2.
img = im2double(img(:,:,1:3));
[h, w, ~] = size(img);
s  = 0.55 + 0.25 * rand;
ch = round(s * h);  cw = round(s * w);
r0 = round((h - ch) / 2 + (rand - 0.5) * 0.3 * (h - ch)) + 1;
c0 = round((w - cw) / 2 + (rand - 0.5) * 0.3 * (w - cw)) + 1;
r0 = min(max(r0, 1), h - ch + 1);  c0 = min(max(c0, 1), w - cw + 1);
out = img(r0:r0+ch-1, c0:c0+cw-1, :);
out = out * (0.7 + 0.6 * rand);
out = out .^ (0.8 + 0.45 * rand);
out = out .* reshape(0.9 + 0.2 * rand(1, 3), 1, 1, 3);
sig = 1.2 * rand;
if sig > 0.3, out = imgaussfilt(out, sig); end
out = im2uint8(min(max(out, 0), 1));
end
