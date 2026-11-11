%% run_cnn.m  --  press Run. CNN feature extraction + comparison.
%
% For every image:
%   1. the CLASSICAL pipeline segments the leaf (background removed)
%   2. the segmented leaf is fed to a pretrained CNN
%   3. the CNN's pooling layer output becomes a feature vector
%
% Then three classifiers are trained and compared:
%   A. classical features only  (59 numbers: colour, lesion, texture, shape)
%   B. CNN features only        (512 numbers from the network)
%   C. both together
%
% Saves leaf_cnn_model.mat next to this script.
% Run check_cnn.m first if you are not sure the toolbox is installed.

% Default: <repo>\dataset\MangoLeafBD. Replace with your own path if it is elsewhere.
DATASET   = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'dataset', 'MangoLeafBD');
PER_CLASS = 100;      % 20 for a quick test, 100-150 for the real run
NETWORK   = "";       % "" = auto. Or "resnet18" / "googlenet" / "squeezenet"

%% ------------------------------------------------------------------------
clc;
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
addpath(here);

CLASSES = {'Healthy', 'Anthracnose', 'Bacterial Canker', 'Cutting Weevil', ...
           'Die Back', 'Gall Midge', 'Powdery Mildew', 'Sooty Mould'};

% ---- Resolve dataset (handles the nested folder) -----------------------
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

% ---- Load the CNN -------------------------------------------------------
[net, featLayer, inSize] = cnn_setup(NETWORK);
fprintf('Dataset: %s\n\n', DATASET);

%% ===================== Pass over the dataset ============================
classicRows = {};  cnnBatch = {};  labels = {};  names = {};
failed = 0;  t0 = tic;

for k = 1:numel(avail)
    classDir = fullfile(DATASET, avail{k});
    files = [dir(fullfile(classDir, '*.jpg')); ...
             dir(fullfile(classDir, '*.jpeg')); ...
             dir(fullfile(classDir, '*.png'))];
    if isempty(files), continue; end

    % Spread the sample over the whole folder (see the note in run_training.m)
    n   = min(PER_CLASS, numel(files));
    idx = unique(round(linspace(1, numel(files), n)));

    okCount = 0;
    for i = idx
        try
            img = imread(fullfile(files(i).folder, files(i).name));

            % --- classical pipeline: preprocess + segment ---------------
            [den, ~, ~] = leaf_preprocess(img);
            [mask, ok]  = segment_leaf(den, false, 'auto');
            if ~ok, failed = failed + 1; continue; end
            M = leaf_lesions(den, mask);
            [f, names] = leaf_features(den, mask, M);

            % --- the CNN sees the SEGMENTED leaf, background blacked out
            seg = den .* uint8(repmat(mask, [1 1 3]));
            seg = imresize(seg, inSize(1:2));
            if inSize(3) == 1, seg = rgb2gray(seg); end

            classicRows{end+1} = f;              %#ok<SAGROW>
            cnnBatch{end+1}    = seg;            %#ok<SAGROW>
            labels{end+1}      = avail{k};       %#ok<SAGROW>
            okCount = okCount + 1;
        catch
            failed = failed + 1;
        end
    end
    fprintf('  %-18s %3d ok  (%.0f s)\n', avail{k}, okCount, toc(t0));
end

assert(numel(labels) > 20, 'Too few images processed (%d).', numel(labels));

%% ===================== CNN forward pass =================================
fprintf('\nRunning %d images through the CNN...\n', numel(cnnBatch));
X = cat(4, cnnBatch{:});
clear cnnBatch

% In batches, so a big run does not exhaust memory
B = 64;
Fcnn = [];
for s = 1:B:size(X, 4)
    e = min(s + B - 1, size(X, 4));
    part = cnn_activations(net, X(:,:,:,s:e), featLayer);
    if isempty(Fcnn), Fcnn = zeros(size(X,4), size(part,2)); end
    Fcnn(s:e, :) = part;   %#ok<SAGROW>
    fprintf('  %d / %d\n', e, size(X,4));
end
fprintf('CNN features: %d x %d\n\n', size(Fcnn,1), size(Fcnn,2));

Fclassic = vertcat(classicRows{:});
y = categorical(string(labels(:)));

%% ===================== Train and compare ================================
tmpl = templateSVM('KernelFunction', 'linear', 'Standardize', true);

sets = { 'Classical only', Fclassic, ...
         'CNN only',       Fcnn, ...
         'Both combined',  [Fclassic, Fcnn] };

fprintf('%-16s %8s %10s\n', 'FEATURES', 'COUNT', 'CV ACC');
fprintf('%s\n', repmat('-', 1, 36));

best = struct('acc', -1);
for s = 1:3:numel(sets)
    nm = sets{s};  Xf = sets{s+1};
    mdl = fitcecoc(Xf, y, 'Learners', tmpl, 'Coding', 'onevsone');
    acc = 1 - kfoldLoss(crossval(mdl, 'KFold', 5));
    fprintf('%-16s %8d %9.1f%%\n', nm, size(Xf,2), acc*100);
    if acc > best.acc
        best = struct('acc', acc, 'name', nm, 'mdl', mdl, 'n', size(Xf,2));
    end
end

fprintf('\nBest: %s (%.1f%%)\n', best.name, best.acc*100);

% Confusion matrix for the best one
predBest = kfoldPredict(crossval(best.mdl, 'KFold', 5));
figure('Name', 'CNN comparison - confusion matrix');
confusionchart(y, predBest);
title(sprintf('%s  (%.1f%% CV accuracy)', best.name, best.acc*100));

% ---- Save ---------------------------------------------------------------
mdl       = best.mdl;
featNames = names;
acc       = best.acc;
whichSet  = best.name;
cnnName   = featLayer;
save(fullfile(here, 'leaf_cnn_model.mat'), ...
     'mdl', 'featNames', 'acc', 'whichSet', 'cnnName');

fprintf('\nSaved %s\n', fullfile(here, 'leaf_cnn_model.mat'));
fprintf(['\nNote: run_leaf.m keeps using the classical model (leaf_model.mat).\n' ...
         'This script is for the comparison figure and the accuracy table.\n']);
