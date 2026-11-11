%% run_mango_training.m  --  press Run. Builds the feature table AND trains the model.
%
% Step 1: runs crop_pipeline.m over the mango ripeness dataset -> mango_features.csv
% Step 2: trains a linear SVM on the colour features          -> mango_model.mat
%
% DATASET must hold one sub-folder per ripeness stage (for example Unripe,
% Partially_Ripe, Ripe). The folder names become the stage names in the app.
% Both files are written next to this script; crop_pipeline.m picks up
% mango_model.mat automatically.

% Default: <repo>\dataset\MangoRipeness. Replace with your own path if it is elsewhere.
DATASET   = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'dataset', 'MangoRipeness');
PER_CLASS = 250;      % images per class. 20 for a quick test.

% The classifier uses colour inside the fruit mask only. Shape, texture and
% DFT features depend on the camera, distance and background (the dataset
% is studio photos on white), so they do not carry over to photos taken on
% the tree. Chromaticity (a*, b*), saturation and the hue fractions do.
% Lightness (L*, V) is left out too: it changes with the lighting.
COLOUR_FEATURES = {'mean_a', 'std_a', 'mean_b', 'std_b', 'mean_S', 'std_S', ...
                   'frac_green', 'frac_yellow', 'frac_red'};

%% ------------------------------------------------------------------------
clc;
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
addpath(here);

% ---- Find the class folders (handles one extra level of nesting) --------
assert(isfolder(DATASET), 'DATASET folder does not exist:\n  %s', DATASET);
classes = image_subfolders(DATASET);
while isempty(classes)
    subs = dir(DATASET);
    subs = subs([subs.isdir] & ~startsWith({subs.name}, '.'));
    assert(numel(subs) == 1, 'No class folders with images inside:\n  %s', DATASET);
    DATASET = fullfile(DATASET, subs(1).name);
    classes = image_subfolders(DATASET);
end
fprintf('Dataset: %s\n', DATASET);
fprintf('Classes: %s\n\n', strjoin(classes, ', '));

%% ===================== STEP 1: extract features =========================
csvPath = fullfile(here, 'mango_features.csv');
tmpDir  = fullfile(tempdir, 'mango_training');

rows = {}; labels = {}; names = {}; failed = 0;
t0 = tic;

for k = 1:numel(classes)
    files = list_images(fullfile(DATASET, classes{k}));
    % Spread the sample over the whole folder, not the first N
    % (images sit in capture order).
    n = min(PER_CLASS, numel(files));
    idx = unique(round(linspace(1, numel(files), n)));

    okCount = 0;
    for i = idx
        try
            % Camera images are ~20 MP. crop_pipeline resizes to 512 px anyway,
            % so shrink to 1024 px first to skip saving huge stage images.
            img = imread(fullfile(files(i).folder, files(i).name));
            img = imresize(img, min(1, 1024 / max(size(img, 1), size(img, 2))));
            small = fullfile(tempdir, 'mango_training_input.png');
            imwrite(img, small);
            jsonPath = crop_pipeline(small, tmpDir);
            r = jsondecode(fileread(jsonPath));
            if ~r.ok || ~isstruct(r.features), failed = failed + 1; continue; end
            names = fieldnames(r.features)';
            rows{end+1}   = cellfun(@(c) r.features.(c), names);   %#ok<SAGROW>
            labels{end+1} = classes{k};                            %#ok<SAGROW>
            okCount = okCount + 1;
        catch
            failed = failed + 1;
        end
    end
    fprintf('  %-18s %3d ok  (%.0f s elapsed)\n', classes{k}, okCount, toc(t0));
end

assert(~isempty(rows), 'No images processed successfully.');

T = array2table(vertcat(rows{:}), 'VariableNames', names);
T.label = categorical(string(labels(:)));
writetable(T, csvPath);
fprintf('\nStep 1 done: %d rows, %d failed segmentation.\n', height(T), failed);
fprintf('Saved %s\n\n', csvPath);

%% ===================== STEP 2: train the classifier =====================
featNames = COLOUR_FEATURES;
X = T{:, featNames};
y = T.label;

fprintf('Training on %d samples, %d features, %d classes...\n', ...
        size(X,1), size(X,2), numel(categories(y)));

t = templateSVM('KernelFunction', 'linear', 'Standardize', true);
mdl = fitcecoc(X, y, 'Learners', t, 'Coding', 'onevsone');

rng(0);
cvm = crossval(mdl, 'KFold', 5);
acc = 1 - kfoldLoss(cvm);
fprintf('5-fold cross-validated accuracy: %.1f%%\n', acc * 100);

pred = kfoldPredict(cvm);
figure('Name', 'Mango maturity classifier - confusion matrix');
confusionchart(y, pred);
title(sprintf('Mango maturity classifier (%.1f%% CV accuracy)', acc * 100));

save(fullfile(here, 'mango_model.mat'), 'mdl', 'featNames', 'acc');
fprintf('\nSaved %s\n', fullfile(here, 'mango_model.mat'));


function classes = image_subfolders(folder)
% Names of the sub-folders of folder that contain images.
subs = dir(folder);
subs = subs([subs.isdir] & ~startsWith({subs.name}, '.'));
classes = {};
for s = 1:numel(subs)
    if ~isempty(list_images(fullfile(folder, subs(s).name)))
        classes{end+1} = subs(s).name; %#ok<AGROW>
    end
end
end

function files = list_images(folder)
files = [dir(fullfile(folder, '*.jpg')); dir(fullfile(folder, '*.jpeg')); ...
         dir(fullfile(folder, '*.png'))];
end
