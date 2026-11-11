%% leaf_cnn_demo.m  --  press Run. Shows what the CNN sees, on one leaf.
%
% Figure: original -> segmented (what the CNN is given) -> first-layer
% filters -> early feature maps -> deep feature map -> predicted class
% probabilities.
%
% Needs leaf_cnn_model.mat for the prediction bar chart, so run run_cnn.m
% first. Without it the figure still shows the activations.

% Default: <repo>\dataset\MangoLeafBD. Replace with your own path if it is elsewhere.
DATASET = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'dataset', 'MangoLeafBD');
IMAGE   = '';      % optional: one exact photo
CLASS   = '';      % optional: 'Sooty Mould' -> random image from that class
NETWORK = "";      % "" = auto

%% ------------------------------------------------------------------------
clc;
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
addpath(here);

CLASSES = {'Healthy', 'Anthracnose', 'Bacterial Canker', 'Cutting Weevil', ...
           'Die Back', 'Gall Midge', 'Powdery Mildew', 'Sooty Mould'};

% ---- Pick an image ------------------------------------------------------
trueClass = '';
if ~isempty(IMAGE)
    assert(isfile(IMAGE), 'IMAGE does not exist:\n  %s', IMAGE);
    imagePath = IMAGE;
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
    fprintf('True class: %s\n', trueClass);
end
fprintf('Image: %s\n', imagePath);

% ---- Classical pipeline: segment first ----------------------------------
[net, featLayer, inSize] = cnn_setup(NETWORK);

img = imread(imagePath);
[den, ~, ~] = leaf_preprocess(img);
[mask, ok]  = segment_leaf(den, false, 'auto');
if ~ok
    warning('Segmentation failed its sanity check; feeding the whole frame.');
    mask = true(size(den,1), size(den,2));
end
seg = den .* uint8(repmat(mask, [1 1 3]));
segR = imresize(seg, inSize(1:2));

% ---- First convolutional layer: filters and activations -----------------
L = net.Layers;
types = arrayfun(@(l) string(class(l)), L);
ci = find(contains(types, "Convolution2DLayer"), 1, 'first');
firstConv = L(ci).Name;

actEarly = cnn_activations(net, segR, firstConv, 'raw');
actDeep  = cnn_activations(net, segR, featLayer, 'rows');

% weights of the first conv layer, for the filter montage
W = [];
try
    W = L(ci).Weights;
catch
end

% ---- Predict, if a trained model exists ---------------------------------
probs = []; classNames = {}; predLabel = '';
modelFile = fullfile(here, 'leaf_cnn_model.mat');
if isfile(modelFile)
    try
        S = load(modelFile);
        M = leaf_lesions(den, mask);
        [fc, ~] = leaf_features(den, mask, M);
        switch S.whichSet
            case 'CNN only',      xq = actDeep;
            case 'Both combined', xq = [fc, actDeep];
            otherwise,            xq = fc;
        end
        [predLabel, score] = predict(S.mdl, xq);
        predLabel = char(string(predLabel));
        classNames = categories(S.mdl.ClassNames);
        if isempty(classNames), classNames = cellstr(string(S.mdl.ClassNames)); end
        sc = double(score);
        sc = exp(sc - max(sc));  probs = sc / sum(sc);
    catch ME
        fprintf(2, 'Could not predict: %s\n', ME.message);
    end
end

%% ===================== FIGURE ===========================================
figure('Name', 'Leaf - what the CNN sees', 'Position', [60 40 1500 760]);

subplot(2,4,1); imshow(img);  title('1. Original');
subplot(2,4,2); imshow(seg);  title('2. Segmented (classical DIP)');
subplot(2,4,3); imshow(segR); title(sprintf('3. Resized %dx%d -> CNN', inSize(1), inSize(2)));

% first-layer filters
subplot(2,4,4);
if ~isempty(W)
    n = min(size(W,4), 36);
    tiles = cell(1, n);
    for q = 1:n
        f = W(:,:,:,q);
        if size(f,3) ~= 3, f = mean(f,3); end
        tiles{q} = imresize(mat2gray(f), [32 32], 'nearest');
    end
    montage(tiles, 'Size', [6 6]);
    title(sprintf('4. %s filters', firstConv), 'Interpreter', 'none');
else
    axis off; title('4. filters unavailable');
end

% early activations: a few channels
subplot(2,4,5);
if ~isempty(actEarly)
    A = squeeze(actEarly);
    nch = min(size(A,3), 16);
    tiles = cell(1, nch);
    for q = 1:nch
        tiles{q} = mat2gray(A(:,:,q));
    end
    montage(tiles, 'Size', [4 4]);
    title('5. Early feature maps');
else
    axis off; title('5. activations unavailable');
end

% strongest early channel
subplot(2,4,6);
if ~isempty(actEarly)
    A = squeeze(actEarly);
    e = squeeze(sum(sum(A, 1), 2));
    [~, bi] = max(e);
    imshow(mat2gray(A(:,:,bi)));
    title(sprintf('6. Strongest channel (#%d)', bi));
else
    axis off;
end

% deep feature vector
subplot(2,4,7);
if ~isempty(actDeep)
    bar(actDeep(1:min(numel(actDeep), 128)));
    xlabel('feature #'); ylabel('activation');
    title(sprintf('7. %s (first 128 of %d)', featLayer, numel(actDeep)), ...
          'Interpreter', 'none');
    axis tight; grid on
else
    axis off;
end

% prediction
subplot(2,4,8);
if ~isempty(probs)
    barh(probs * 100);
    set(gca, 'YTickLabel', classNames, 'YTick', 1:numel(classNames));
    xlabel('%'); xlim([0 100]); grid on
    t = sprintf('8. Predicted: %s', predLabel);
    if ~isempty(trueClass), t = sprintf('%s\n(true: %s)', t, trueClass); end
    title(t);
else
    axis off
    text(0, 0.6, '8. No trained model yet.', 'FontWeight', 'bold');
    text(0, 0.45, 'Run run_cnn.m first to get', 'FontSize', 10);
    text(0, 0.35, 'the prediction chart here.', 'FontSize', 10);
end

fprintf('\nCNN feature vector length: %d\n', numel(actDeep));
if ~isempty(predLabel)
    fprintf('Predicted: %s\n', predLabel);
end
