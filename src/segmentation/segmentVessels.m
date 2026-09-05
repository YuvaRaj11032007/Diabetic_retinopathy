function vesselResult = segmentVessels(imgRGB, options)
%SEGMENTVESSELS Segment retinal vasculature using matched filtering
%
%   vesselResult = segmentVessels(imgRGB) segments blood vessels from 
%   retinal fundus images using multi-scale multi-orientation matched filters.
%
%   vesselResult = segmentVessels(imgRGB, 'ModelPath', path) uses a 
%   pretrained deep learning model instead of classical filtering.
%
%   INPUTS:
%       imgRGB  - Enhanced RGB image or green channel (H x W x 3 or H x W uint8)
%
%   Name-Value pairs:
%       ModelPath - Optional. Full path to trained U-Net model (.mat)
%
%   OUTPUTS:
%       vesselResult - Struct containing fields:
%           .binaryMask      - Logical array of segmented vessels
%           .probabilityMap  - Matrix of vessel probabilities/responses
%           .vesselDensity   - Fraction of image pixels that are vessels
%           .branchPoints    - Logical array of vessel branching points
%           .endpoints       - Logical array of vessel endpoints
%
%   EXAMPLE:
%       img = imread('fundus.jpg');
%       res = segmentVessels(img);
%       imshow(res.binaryMask);
%
%   See also bwmorph, semanticseg

    arguments
        imgRGB {mustBeNumeric}
        options.ModelPath (1,:) char = ''
    end
    
    [H, W, C] = size(imgRGB);
    
    % a. Extract green channel (inverted)
    if C == 3
        greenChannel = im2double(imgRGB(:,:,2));
    else
        greenChannel = im2double(imgRGB);
    end
    
    if ~isempty(options.ModelPath)
        try
            loadedData = load(options.ModelPath);
            vars = fieldnames(loadedData);
            net = [];
            for i = 1:length(vars)
                if isa(loadedData.(vars{i}), 'DAGNetwork') || isa(loadedData.(vars{i}), 'dlnetwork') || isa(loadedData.(vars{i}), 'SeriesNetwork')
                    net = loadedData.(vars{i});
                    break;
                end
            end
            
            if isempty(net)
                error('No compatible network found in ModelPath');
            end
            
            if size(imgRGB, 3) == 1 && net.Layers(1).InputSize(3) == 3
                inputImg = cat(3, imgRGB, imgRGB, imgRGB);
            else
                inputImg = imgRGB;
            end
            
            pred = semanticseg(inputImg, net);
            cats = categories(pred);
            if length(cats) > 1
                binaryMask = (pred == cats{2}); 
            else
                binaryMask = (pred == cats{1});
            end
            
            probMap = double(binaryMask); 
            
        catch ME
            warning('DRPipeline:segmentation:segmentVessels:ModelError', ...
                'Failed to use deep learning model: %s. Falling back to classical method.', ME.message);
            options.ModelPath = ''; 
        end
    end
    
    if isempty(options.ModelPath)
        invertedGreen = 1 - greenChannel;
        
        % b. & c. Create and apply Gaussian matched filters
        scales = [1.5, 2.5, 3.5];
        orientations = 0:15:165;
        
        maxResponse = zeros(H, W);
        
        for s = scales
            sigma = s;
            L = round(3 * sigma);
            
            for theta = orientations
                angle = deg2rad(theta);
                
                kernel = zeros(2*L+1, 2*L+1);
                for i = 1:(2*L+1)
                    for j = 1:(2*L+1)
                        u = (j - L - 1)*cos(angle) + (i - L - 1)*sin(angle);
                        
                        if abs(u) <= 3*sigma
                            kernel(i,j) = -exp(-(u^2)/(2*sigma^2)) / (sqrt(2*pi)*sigma);
                        end
                    end
                end
                
                meanK = mean(kernel(:));
                kernel = kernel - meanK;
                
                response = imfilter(invertedGreen, kernel, 'replicate', 'same');
                maxResponse = max(maxResponse, response);
            end
        end
        
        maxResponse = maxResponse - min(maxResponse(:));
        maxResponse = maxResponse / max(maxResponse(:));
        probMap = maxResponse;
        
        % e. Apply hysteresis thresholding
        baseThresh = graythresh(probMap(probMap > 0.05));
        highThresh = baseThresh * 0.9;
        lowThresh = highThresh * 0.5;
        
        strong = probMap > highThresh;
        weak = (probMap > lowThresh) & (probMap <= highThresh);
        binaryMask = bwselect(strong | weak, find(strong), 8);
        
        % f. Post-process
        binaryMask = bwareaopen(binaryMask, 50); 
        binaryMask = imclose(binaryMask, strel('disk', 1)); 
    end
    
    skeleton = bwmorph(binaryMask, 'skel', inf);
    branchPoints = bwmorph(skeleton, 'branchpoints');
    endpoints = bwmorph(skeleton, 'endpoints');
    
    validPixelsMask = probMap > 0; 
    if ~any(validPixelsMask(:))
        validPixelsMask = true(H, W);
    end
    
    vesselArea = sum(binaryMask(:));
    totalArea = sum(validPixelsMask(:));
    vesselDensity = vesselArea / totalArea;
    
    vesselResult.binaryMask = binaryMask;
    vesselResult.probabilityMap = probMap;
    vesselResult.vesselDensity = vesselDensity;
    vesselResult.branchPoints = branchPoints;
    vesselResult.endpoints = endpoints;
end
