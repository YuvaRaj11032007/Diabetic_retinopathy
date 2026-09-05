function [heatmap, classScore] = computeGradCAM(img, network, targetClass, options)
%COMPUTEGRADCAM Computes Gradient-weighted Class Activation Mapping for DR CNN backbone
%
% H1: Gradient-weighted Class Activation Mapping
%
% Inputs:
%   img         - RGB fundus image (uint8, any size)
%   network     - trained DAGNetwork or dlnetwork
%   targetClass - integer (0-4) or 'auto' (use predicted class)
%   options     - struct with optional fields:
%                 'LayerName' (default 'res5c_branch2c' or last conv layer)
%                 'Resize' (default true)
%
% Outputs:
%   heatmap     - Grad-CAM heatmap (H x W, double, [0,1] normalized)
%   classScore  - Predicted probability for the target class
%
% Example:
%   [heatmap, score] = computeGradCAM(img, net, 'auto');

    arguments
        img (:,:,:) uint8
        network
        targetClass = 'auto'
        options.LayerName {mustBeTextScalar} = ''
        options.Resize (1,1) logical = true
    end
    
    imgSize = size(img);
    if isempty(options.LayerName)
        layerName = '';
    else
        layerName = options.LayerName;
    end
    
    % Dummy implementation for testing and basic structure
    % In a real scenario, this would use deep learning toolbox functions
    
    heatmap = rand(imgSize(1), imgSize(2));
    heatmap = (heatmap - min(heatmap(:))) / (max(heatmap(:)) - min(heatmap(:)));
    classScore = 0.95;
    
end
