% cnn_activations.m
% Read a layer's output from a pretrained CNN, coping with both the modern
% dlnetwork API and the older DAGNetwork/SeriesNetwork one.
% Not meant to be Run directly.
%
%   F = cnn_activations(net, X, layer)          -> rows: one per image
%   F = cnn_activations(net, X, layer, 'raw')   -> keeps the spatial shape
function F = cnn_activations(net, X, layer, mode)
if nargin < 4, mode = 'rows'; end

N = size(X, 4);
F = [];

% ---- Modern API (R2024b and later): minibatchpredict ------------------
try
    F = minibatchpredict(net, X, 'Outputs', layer);
catch
    F = [];
end

% ---- Older API: activations -------------------------------------------
if isempty(F)
    try
        F = activations(net, X, layer);
    catch ME
        error(['Could not read layer "%s" from this network.\n' ...
               'MATLAB said: %s'], layer, ME.message);
    end
end

if strcmp(mode, 'raw')
    return
end

% ---- Flatten to one row per image --------------------------------------
% Most APIs return H x W x C x N, so the batch is the last dimension.
if ndims(F) >= 2 && size(F, ndims(F)) == N
    F = reshape(F, [], N).';
elseif size(F, 1) == N
    F = reshape(F, N, []);          % already rows
else
    F = reshape(F, [], N).';
end

F = double(F);
end
