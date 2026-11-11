%% run_leaf.m  --  press the green Run button. No typing needed.
%
% Finds the MangoLeafBD dataset somewhere near this file, picks an image,
% and runs the full leaf pipeline on it.
%
% Three optional settings below. Leave them empty to let the script choose.

% Default: <repo>\dataset\MangoLeafBD. Replace with your own path if it is elsewhere.
DATASET = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'dataset', 'MangoLeafBD');

IMAGE   = '';      % optional: one exact photo, full path
CLASS   = '';      % optional: 'Sooty Mould' -> random image from that class only

%% ------------------------------------------------------------------------
clc;
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
addpath(here);                     % so the other leaf_*.m files are found

CLASSES = {'Healthy', 'Anthracnose', 'Bacterial Canker', 'Cutting Weevil', ...
           'Die Back', 'Gall Midge', 'Powdery Mildew', 'Sooty Mould'};

% ---- 1. An explicit image wins ------------------------------------------
if ~isempty(IMAGE)
    assert(isfile(IMAGE), 'IMAGE is set but that file does not exist:\n  %s', IMAGE);
    leaf_demo(IMAGE);
    return
end

% ---- 2. Locate the dataset ----------------------------------------------
if ~isempty(DATASET) && ~isfolder(DATASET)
    fprintf(2, 'DATASET is set but that folder does not exist:\n  %s\n', DATASET);
    fprintf(2, 'Falling back to searching for it...\n');
    DATASET = '';
end

if isempty(DATASET)
    fprintf('Looking for the MangoLeafBD dataset...\n');
    searchFrom = unique({here, pwd, fileparts(here), fileparts(pwd)}, 'stable');
    for k = 1:numel(searchFrom)
        base = searchFrom{k};
        if isempty(base) || ~isfolder(base), continue; end
        hits = dir(fullfile(base, '**', 'Healthy'));
        hits = hits([hits.isdir]);
        for h = 1:numel(hits)
            cand = hits(h).folder;                     % parent of 'Healthy'
            if isfolder(fullfile(cand, 'Sooty Mould')) % looks like the dataset
                DATASET = cand;
                break
            end
        end
        if ~isempty(DATASET), break; end
    end
end

if isempty(DATASET)
    fprintf(2, ['\nCould not find the dataset automatically.\n\n' ...
        'Do ONE of these, then press Run again:\n' ...
        '  (a) set DATASET at the top of this file to the folder that\n' ...
        '      contains the 8 class folders (Healthy, Sooty Mould, ...)\n' ...
        '  (b) set IMAGE at the top of this file to any single leaf photo\n\n' ...
        'Searched under:\n']);
    for k = 1:numel(searchFrom), fprintf(2, '  %s\n', searchFrom{k}); end
    return
end
% ---- 2b. Descend if the class folders are nested one or two levels down --
% Windows "Extract All" often creates  X\MangoLeafBD Dataset\MangoLeafBD Dataset\Healthy
for depth = 1:3
    if any(cellfun(@(c) isfolder(fullfile(DATASET, c)), CLASSES))
        break                                  % class folders are right here
    end
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
        if numel(subs) == 1                    % single wrapper folder: go in
            DATASET = fullfile(DATASET, subs(1).name);
        else
            break
        end
    end
end
fprintf('Dataset: %s\n', DATASET);

% ---- 3. Pick an image ----------------------------------------------------
avail = CLASSES(cellfun(@(c) isfolder(fullfile(DATASET, c)), CLASSES));

if isempty(avail)
    fprintf(2, '\nNo class folders (Healthy, Sooty Mould, ...) inside:\n  %s\n', DATASET);
    items = dir(DATASET);
    items = items(~startsWith({items.name}, '.'));
    if isempty(items)
        fprintf(2, 'That folder is EMPTY. The dataset zip was probably not extracted.\n');
    else
        fprintf(2, '\nWhat IS in there:\n');
        for k = 1:min(numel(items), 15)
            kind = 'file  ';
            if items(k).isdir, kind = 'FOLDER'; end
            fprintf(2, '  [%s] %s\n', kind, items(k).name);
        end
        if numel(items) > 15
            fprintf(2, '  ... and %d more\n', numel(items) - 15);
        end
    end
    fprintf(2, ['\nSet DATASET (line 8) to the folder that directly contains\n' ...
                'the 8 class folders, then press Run again.\n']);
    return
end

if isempty(CLASS)
    CLASS = avail{randi(numel(avail))};
end
classDir = fullfile(DATASET, CLASS);
if ~isfolder(classDir)
    fprintf(2, 'No folder called "%s". Available: %s\n', CLASS, strjoin(avail, ', '));
    return
end

files = [dir(fullfile(classDir, '*.jpg')); ...
         dir(fullfile(classDir, '*.jpeg')); ...
         dir(fullfile(classDir, '*.png'))];
if isempty(files)
    fprintf(2, 'No .jpg/.jpeg/.png images inside:\n  %s\n', classDir);
    return
end

rng('shuffle');
pick = files(randi(numel(files)));
imagePath = fullfile(pick.folder, pick.name);

fprintf('True class: %s\n', CLASS);

% ---- 4. Run the pipeline -------------------------------------------------
leaf_demo(imagePath);
