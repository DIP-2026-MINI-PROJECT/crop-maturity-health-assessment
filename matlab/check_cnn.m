%% check_cnn.m  --  press Run. Checks whether your MATLAB can do the CNN part.
% Prints exactly what is missing and how to install it. Changes nothing.

clc;
fprintf('Checking CNN prerequisites...\n\n');

ok = true;

% ---- 1. Deep Learning Toolbox ------------------------------------------
if license('test', 'Neural_Network_Toolbox') && ~isempty(ver('deeplearning'))
    v = ver('deeplearning');
    fprintf('[ OK ] Deep Learning Toolbox %s\n', v(1).Version);
else
    fprintf(2, '[MISSING] Deep Learning Toolbox\n');
    fprintf(2, '         Home tab -> Add-Ons -> Get Add-Ons -> search\n');
    fprintf(2, '         "Deep Learning Toolbox" -> Install\n');
    ok = false;
end

% ---- 2. Statistics toolbox (for the SVM) -------------------------------
if ~isempty(ver('stats'))
    fprintf('[ OK ] Statistics and Machine Learning Toolbox\n');
else
    fprintf(2, '[MISSING] Statistics and Machine Learning Toolbox\n');
    ok = false;
end

% ---- 3. A pretrained network -------------------------------------------
found = '';
for name = ["resnet18", "googlenet", "squeezenet"]
    try
        if exist('imagePretrainedNetwork', 'file')
            net = imagePretrainedNetwork(name);          %#ok<NASGU>  R2024b+
        else
            net = feval(char(name));                     %#ok<NASGU>  older MATLAB
        end
        found = char(name);
        break
    catch
        % not installed, try the next one
    end
end

if ~isempty(found)
    fprintf('[ OK ] Pretrained network available: %s\n', found);
else
    fprintf(2, '[MISSING] No pretrained network installed\n');
    fprintf(2, '         Home tab -> Add-Ons -> Get Add-Ons -> search\n');
    fprintf(2, '         "Deep Learning Toolbox Model for ResNet-18 Network"\n');
    fprintf(2, '         -> Install  (about 45 MB, one time)\n');
    ok = false;
end

% ---- 4. GPU (optional) --------------------------------------------------
try
    g = gpuDevice;
    fprintf('[ OK ] GPU available: %s (optional, just faster)\n', g.Name);
catch
    fprintf('[info] No GPU. CPU works fine, extraction is just slower.\n');
end

fprintf('\n');
if ok
    fprintf('All set. You can run run_cnn.m and leaf_cnn_demo.m\n');
else
    fprintf(2, 'Install what is marked MISSING above, then run this again.\n');
    fprintf(2, 'Without it, run_leaf.m and run_training.m still work as before.\n');
end
