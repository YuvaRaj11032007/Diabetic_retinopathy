function odResult = localizeOpticDisc(imgRGB, options)
%LOCALIZEOPTICDISC Detect and localize the optic disc center and boundary
%
%   odResult = localizeOpticDisc(imgRGB) localizes the optic disc using
%   brightness-based candidate detection and circular Hough transform.
%
%   odResult = localizeOpticDisc(imgRGB, 'ModelPath', path) uses a 
%   pretrained deep learning U-Net model for segmentation if provided.
%
%   INPUTS:
%       imgRGB  - Enhanced RGB fundus image (H x W x 3 uint8)
%
%   Name-Value pairs:
%       ModelPath - Optional. Full path to a trained U-Net model (.mat)
%
%   OUTPUTS:
%       odResult - Struct containing fields:
%           .center     - [x, y] coordinates of OD center
%           .radius     - Estimated radius of the optic disc
%           .mask       - Binary mask of the optic disc (H x W logical)
%           .confidence - Confidence score [0, 1]
%
%   EXAMPLE:
%       img = imread('fundus.jpg');
%       odResult = localizeOpticDisc(img);
%       imshow(img); hold on;
%       viscircles(odResult.center, odResult.radius, 'Color', 'b');
%
%   See also imfindcircles, regionprops, semanticseg

    arguments
        imgRGB (:,:,3) uint8
        options.ModelPath (1,:) char = ''
    end

    [H, W, ~] = size(imgRGB);
    
    if ~isempty(options.ModelPath)
        try
            loadedData = load(options.ModelPath);
            if isfield(loadedData, 'net')
                net = loadedData.net;
            else
                vars = fieldnames(loadedData);
                for i = 1:length(vars)
                    if isa(loadedData.(vars{i}), 'DAGNetwork') || isa(loadedData.(vars{i}), 'dlnetwork') || isa(loadedData.(vars{i}), 'SeriesNetwork')
                        net = loadedData.(vars{i});
                        break;
                    end
                end
            end
            
            pred = semanticseg(imgRGB, net);
            cats = categories(pred);
            if length(cats) > 1
                odMask = (pred == cats{2}); 
            else
                odMask = (pred == cats{1});
            end
            
            props = regionprops(odMask, 'Centroid', 'EquivDiameter');
            if ~isempty(props)
                [~, idx] = max([props.EquivDiameter]);
                odResult.center = props(idx).Centroid;
                odResult.radius = props(idx).EquivDiameter / 2;
                odResult.mask = odMask;
                odResult.confidence = 0.9;
                return;
            end
        catch ME
            warning('DRPipeline:segmentation:localizeOpticDisc:ModelError', ...
                'Failed to use deep learning model: %s. Falling back to classical method.', ME.message);
        end
    end

    % Classical Method
    % a. Extract red channel, apply Gaussian blur
    redChannel = imgRGB(:,:,1);
    blurred = imgaussfilt(redChannel, 5);
    
    % b. Threshold to find bright candidates
    thresh = prctile(blurred(:), 99);
    brightMask = blurred > thresh;
    
    % c. Apply morphological operations
    se = strel('disk', 5);
    morphMask = imopen(brightMask, se);
    morphMask = imclose(morphMask, se);
    
    % d. Use regionprops to find largest circular region
    props = regionprops(morphMask, 'Area', 'Centroid', 'BoundingBox', 'Solidity');
    if isempty(props)
        error('DRPipeline:segmentation:localizeOpticDisc:NoCandidates', ...
            'Could not find any optic disc candidates.');
    end
    
    areas = [props.Area];
    solidities = [props.Solidity];
    scores = areas .* solidities;
    [~, bestIdx] = max(scores);
    
    roiCenter = props(bestIdx).Centroid;
    
    % Validate reasonable radius bounds (1/15 to 1/5 of image width)
    minRadius = floor(W / 15);
    maxRadius = ceil(W / 5);
    
    cropSize = maxRadius * 3;
    x1 = max(1, floor(roiCenter(1) - cropSize/2));
    y1 = max(1, floor(roiCenter(2) - cropSize/2));
    x2 = min(W, floor(roiCenter(1) + cropSize/2));
    y2 = min(H, floor(roiCenter(2) + cropSize/2));
    
    roiImg = blurred(y1:y2, x1:x2);
    
    % e. Fit a circle using imfindcircles
    [centers, radii, metric] = imfindcircles(roiImg, [minRadius, maxRadius], ...
        'ObjectPolarity', 'bright', 'Sensitivity', 0.85, 'Method', 'TwoStage');
    
    if ~isempty(centers)
        bestCenterRoi = centers(1,:);
        bestRadius = radii(1);
        conf = metric(1);
        bestCenter = bestCenterRoi + [x1 - 1, y1 - 1];
    else
        bestCenter = roiCenter;
        bestRadius = sqrt(props(bestIdx).Area / pi);
        conf = 0.5;
    end
    
    if bestCenter(1) < 1 || bestCenter(1) > W || bestCenter(2) < 1 || bestCenter(2) > H
        error('DRPipeline:segmentation:localizeOpticDisc:InvalidCenter', ...
            'Optic disc center out of image bounds.');
    end
    
    if bestRadius < minRadius || bestRadius > maxRadius
        bestRadius = max(minRadius, min(bestRadius, maxRadius));
        conf = conf * 0.5;
    end
    
    [X, Y] = meshgrid(1:W, 1:H);
    distSq = (X - bestCenter(1)).^2 + (Y - bestCenter(2)).^2;
    mask = distSq <= bestRadius^2;
    
    odResult.center = bestCenter;
    odResult.radius = bestRadius;
    odResult.mask = mask;
    odResult.confidence = conf;
end
