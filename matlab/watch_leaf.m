%% watch_leaf.m  --  press Run, then LEAVE IT RUNNING while you use the app.
%
% This replaces the MATLAB Engine for Python. Instead of the app calling
% MATLAB, MATLAB watches a folder:
%
%   1. the app saves your uploaded image and drops a small .job file
%   2. this script notices it, runs the real pipeline, writes results.json
%   3. the app reads the results and fills the page
%
% Stop it with Ctrl+C in the Command Window, or by pressing the Stop button.
%
% Nothing to configure: the queue lives next to this file, in ..\outputs\

POLL = 0.4;        % seconds between checks

%% ------------------------------------------------------------------------
clc;
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
addpath(here);

root = fileparts(here);                            % the folder above matlab\

% ---- Am I the right copy of this file? ---------------------------------
% The queue folder is derived from this file's location, so running the
% copy that sits anywhere else would watch the wrong folder and never see
% the app's jobs.
[~, hereName] = fileparts(here);
if ~strcmpi(hereName, 'matlab')
    fprintf(2, '\nWRONG COPY OF watch_leaf.m\n\n');
    fprintf(2, 'This file is in:\n  %s\n\n', here);
    fprintf(2, 'It must be run from the app''s "matlab" folder, because the\n');
    fprintf(2, 'queue folder is worked out from where this file sits.\n\n');
    fprintf(2, 'Open crop-maturity-health-assessment\\matlab\\watch_leaf.m instead.\n\n');
    return
end

queueDir = fullfile(root, 'outputs', 'queue');
dashDir  = fullfile(root, 'outputs', 'dashboard');
if ~isfolder(queueDir), mkdir(queueDir); end
if ~isfolder(dashDir),  mkdir(dashDir);  end

alive = fullfile(queueDir, 'watcher.alive');

fprintf('================================================\n');
fprintf(' CropVision MATLAB watcher -- RUNNING\n');
fprintf('================================================\n');
fprintf('Queue : %s\n', queueDir);
fprintf('\nLeave this running while you use the app.\n');
fprintf('Stop it with Ctrl+C in the Command Window.\n\n');
fprintf('While this is running MATLAB shows "Busy" and you cannot\n');
fprintf('type here. That is normal -- it means the watcher is alive.\n\n');
fprintf('Waiting for jobs');

nDone = 0;
tTick = tic;
tBeat = tic;
beatFirst = true;

while true
    % ---- heartbeat so the app knows the watcher is alive ---------------
    if beatFirst || toc(tBeat) > 2
        fid = fopen(alive, 'w');
        if fid > 0
            fprintf(fid, '%s', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
            fclose(fid);
        end
        tBeat = tic;
        beatFirst = false;
    end

    % ---- a dot every 15 s, so you can see it is alive -------------------
    if toc(tTick) > 15
        fprintf('.');
        tTick = tic;
    end

    % ---- any jobs waiting? ----------------------------------------------
    jobs = dir(fullfile(queueDir, '*.job'));
    for j = 1:numel(jobs)
        jobPath = fullfile(queueDir, jobs(j).name);
        [~, jobName] = fileparts(jobs(j).name);        % e.g. leaf-a1b2c3d4e5f6
        outDir = fullfile(dashDir, jobName);

        fprintf('\n[%s] job %s\n', char(datetime('now', 'Format', 'HH:mm:ss')), jobName);

        try
            % mode is the part before the first hyphen
            k = strfind(jobName, '-');
            if isempty(k)
                error('Malformed job name "%s".', jobName);
            end
            mode = jobName(1:k(1)-1);

            % find the input image the app saved
            inputs = [dir(fullfile(outDir, 'input.*'))];
            inputs = inputs(~[inputs.isdir]);
            if isempty(inputs)
                error('No input image found in %s', outDir);
            end
            inputPath = fullfile(outDir, inputs(1).name);

            % pick up any edits to the pipeline files made while the
            % watcher was running (otherwise MATLAB keeps the old copy)
            rehash;
            clear('functions');

            switch lower(mode)
                case 'leaf'
                    run_leaf_dashboard(inputPath, outDir);
                case 'fruit'
                    crop_pipeline(inputPath, outDir);
                otherwise
                    error('Unknown mode "%s".', mode);
            end

            nDone = nDone + 1;
            fprintf('         done  (%d total)\n', nDone);
            fprintf('Waiting for jobs');

        catch ME
            fprintf(2, '         FAILED: %s\n', ME.message);
            % tell the app what went wrong
            efid = fopen(fullfile(outDir, 'error.txt'), 'w');
            if efid > 0
                fprintf(efid, '%s', ME.message);
                fclose(efid);
            end
        end

        % job handled either way - remove it so it is not retried
        delete(jobPath);
    end

    pause(POLL);
end

% Note: there is deliberately no onCleanup here. The app decides whether the
% watcher is alive from the age of watcher.alive (stale after ~20 s), so a
% leftover heartbeat file after Ctrl+C is harmless and self-correcting.
