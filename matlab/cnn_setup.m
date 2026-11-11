% cnn_setup.m
% Loads a pretrained CNN and works out which layer to read features from.
% Called by run_cnn.m and leaf_cnn_demo.m. Not meant to be Run directly.
%
%   [net, featLayer, inSize] = cnn_setup()
%   [net, featLayer, inSize] = cnn_setup("googlenet")
function [net, featLayer, inSize] = cnn_setup(preferred)

if nargin < 1 || isempty(preferred)
    candidates = ["resnet18", "googlenet", "squeezenet"];
else
    candidates = string(preferred);
end

net = [];
for name = candidates
    try
        if exist('imagePretrainedNetwork', 'file')
            net = imagePretrainedNetwork(name);       % R2024b and later
        else
            net = feval(char(name));                  % older MATLAB
        end
        fprintf('CNN: %s\n', name);
        break
    catch
        % try the next one
    end
end

if isempty(net)
    error(['No pretrained CNN is installed.\n' ...
           'Run check_cnn.m - it says exactly what to install.']);
end

% ---- Input size --------------------------------------------------------
L = net.Layers;
inSize = L(1).InputSize;

% ---- Feature layer: the last pooling layer before the classifier -------
% For resnet18 this is "pool5", googlenet "pool5-7x7_s1", squeezenet "pool10".
% Detecting it by type avoids hard-coding a name per network.
types = arrayfun(@(l) string(class(l)), L);
isPool = contains(types, "GlobalAveragePooling2DLayer") | ...
         contains(types, "AveragePooling2DLayer");
gi = find(isPool, 1, 'last');

if isempty(gi)
    % Fall back: the layer feeding the final fully-connected layer
    isFC = contains(types, "FullyConnectedLayer");
    fi = find(isFC, 1, 'last');
    assert(~isempty(fi) && fi > 1, 'Could not find a feature layer in this network.');
    gi = fi - 1;
end

featLayer = L(gi).Name;
fprintf('Feature layer: %s   Input size: %dx%dx%d\n', ...
        featLayer, inSize(1), inSize(2), inSize(3));
end
