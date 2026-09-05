function maResult = detectMicroaneurysms(img, vesselMask, options)
%DETECTMICROANEURYSMS Detect microaneurysms in retinal images
%
%   maResult = detectMicroaneurysms(img, vesselMask) detects microaneurysms
%   using morphological bottom-hat filtering and shape analysis.
%
%   maResult = detectMicroaneurysms(img, vesselMask, options) allows
%   specifying detection parameters.
%
%   INPUTS:
%       img        - Enhanced RGB retinal image (HxWx3 uint8 or double)
%       vesselMask - Binary mask of retinal vessels (HxW logical)
%       options    - Optional struct with fields:
%                    .minDiameter (default: 3)
%                    .maxDiameter (default: 40)
%                    .threshold (default: 0.05)
%
%   OUTPUTS:
%       maResult   - Struct with fields:
%                    .centroids   : Nx2 array of MA coordinates [x, y]
%                    .confidences : Nx1 array of confidence scores [0-1]
%                    .binaryMask  : HxW logical mask of detected MAs
%                    .count       : Number of detected MAs
%
%   EXAMPLE:
%       maResult = detectMicroaneurysms(enhancedImg, vesselMask);
%       imshow(img); hold on;
%       plot(maResult.centroids(:,1), maResult.centroids(:,2), 'ro');

    arguments
        img (:,:,3) {mustBeNumeric}
        vesselMask (:,:) logical
        options.minDiameter (1,1) double {mustBePositive} = 3
        options.maxDiameter (1,1) double {mustBePositive} = 40
        options.threshold (1,1) double {mustBePositive} = 0.05
    end

    try
        % 1. Extract green channel and invert (MAs are dark)
        if isinteger(img)
            imgDouble = im2double(img);
        else
            imgDouble = img;
        end
        greenChannel = imgDouble(:,:,2);
        invertedGreen = 1 - greenChannel;

        % 2. Morphological bottom-hat filtering
        % We use bottom-hat on the original green channel, or top-hat on inverted
        % Top-hat on inverted green extracts small bright structures (which were small dark structures)
        radii = [round(options.minDiameter/2), round(options.maxDiameter/2)];
        seSmall = strel('disk', radii(1));
        seLarge = strel('disk', radii(2));
        
        % Background estimation
        background = imopen(invertedGreen, seLarge);
        candidatesImage = invertedGreen - background;
        
        % 3. Threshold to extract candidates
        candidateMask = candidatesImage > options.threshold;
        
        % 4. Remove candidates overlapping vessel mask
        seVessel = strel('disk', 2);
        dilatedVessels = imdilate(vesselMask, seVessel);
        candidateMask(dilatedVessels) = false;
        
        % 5. Filter by size and shape
        stats = regionprops(candidateMask, invertedGreen, 'Centroid', 'Area', 'Eccentricity', 'MeanIntensity', 'PixelIdxList', 'Perimeter');
        
        minArea = pi * radii(1)^2;
        maxArea = pi * radii(2)^2;
        
        finalMask = false(size(candidateMask));
        validIdx = [];
        confidences = [];
        
        for i = 1:length(stats)
            area = stats(i).Area;
            if area >= minArea && area <= maxArea && stats(i).Eccentricity < 0.85
                % Compute compactness
                compactness = (stats(i).Perimeter^2) / (4 * pi * area);
                if compactness < 2.5 % roughly circular
                    validIdx(end+1) = i; %#ok<AGROW>
                    finalMask(stats(i).PixelIdxList) = true;
                    
                    % Composite score based on intensity and shape
                    score = min(1, stats(i).MeanIntensity * 2) * (1 - stats(i).Eccentricity);
                    confidences(end+1, 1) = score; %#ok<AGROW>
                end
            end
        end
        
        if isempty(validIdx)
            centroids = zeros(0, 2);
            confidences = zeros(0, 1);
        else
            centroids = cat(1, stats(validIdx).Centroid);
        end
        
        maResult = struct();
        maResult.centroids = centroids;
        maResult.confidences = confidences;
        maResult.binaryMask = finalMask;
        maResult.count = length(validIdx);
        
    catch ME
        error('DRPipeline:segmentation:MicroaneurysmDetectionError', ...
            'Failed to detect microaneurysms: %s', ME.message);
    end
end
