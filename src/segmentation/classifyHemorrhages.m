function hemorrhageResult = classifyHemorrhages(img, vesselMask)
%CLASSIFYHEMORRHAGES Detect and classify retinal hemorrhages
%
%   hemorrhageResult = classifyHemorrhages(img, vesselMask) detects
%   and classifies hemorrhages into dot/blot, flame-shaped, or preretinal.
%
%   INPUTS:
%       img        - Enhanced RGB retinal image (HxWx3 uint8 or double)
%       vesselMask - Binary mask of retinal vessels (HxW logical)
%
%   OUTPUTS:
%       hemorrhageResult - Struct with fields:
%                          .binaryMask : HxW logical mask of all hemorrhages
%                          .count      : Total number of hemorrhages
%                          .types      : Cell array of strings classifying each region
%                          .regions    : regionprops struct with types added
%
%   EXAMPLE:
%       hemResult = classifyHemorrhages(img, vesselMask);
%       disp(hemResult.types);

    arguments
        img (:,:,3) {mustBeNumeric}
        vesselMask = []
    end

    try
        if isinteger(img)
            imgDouble = im2double(img);
        else
            imgDouble = img;
        end
        [H, W, ~] = size(imgDouble);
        if isempty(vesselMask) || ~islogical(vesselMask) || ~isequal(size(vesselMask), [H, W])
            vesselMask = false(H, W);
        end
        
        % 1. Extract green channel and invert
        greenChannel = imgDouble(:,:,2);
        invertedGreen = 1 - greenChannel;
        
        % Generate fundus mask
        grayImg = rgb2gray(imgDouble);
        fundusMask = grayImg > 0.05;
        
        % 2. Morphological opening to estimate background
        seLarge = strel('disk', 25);
        background = imopen(invertedGreen, seLarge);
        
        % 3. Subtract background
        darkLesions = invertedGreen - background;
        
        % 4. Remove vessel pixels (dilated vessel mask)
        seVessel = strel('disk', 3);
        dilatedVessels = imdilate(vesselMask, seVessel);
        
        % 5. Threshold and extract connected components
        % Adaptive thresholding based on fundus statistics
        validPixels = darkLesions(fundusMask & ~dilatedVessels);
        if isempty(validPixels)
            thresh = 0.05;
        else
            thresh = mean(validPixels) + 2.5 * std(validPixels);
        end
        
        candidateMask = (darkLesions > thresh) & fundusMask;
        candidateMask(dilatedVessels) = false;
        
        % Clean up noise
        candidateMask = bwareaopen(candidateMask, 15);
        
        % 6. Compute shape features and classify
        stats = regionprops(candidateMask, 'Area', 'Eccentricity', 'Solidity', 'MajorAxisLength', 'MinorAxisLength', 'PixelIdxList', 'Centroid');
        
        finalMask = false(size(candidateMask));
        validRegions = struct('Area', {}, 'Eccentricity', {}, 'Solidity', {}, 'Centroid', {}, 'Type', {});
        types = {};
        
        idx = 1;
        for i = 1:length(stats)
            area = stats(i).Area;
            ecc = stats(i).Eccentricity;
            solidity = stats(i).Solidity;
            
            % Ignore very small regions
            if area < 20
                continue;
            end
            
            % Classify based on shape
            type = 'unknown';
            
            if area > 2000 && solidity > 0.8
                type = 'preretinal';
            elseif ecc > 0.7 && area > 100
                type = 'flame';
            elseif ecc <= 0.7
                type = 'dot/blot';
            end
            
            if ~strcmp(type, 'unknown')
                finalMask(stats(i).PixelIdxList) = true;
                validRegions(idx).Area = area;
                validRegions(idx).Eccentricity = ecc;
                validRegions(idx).Solidity = solidity;
                validRegions(idx).Centroid = stats(i).Centroid;
                validRegions(idx).Type = type;
                types{idx} = type; %#ok<AGROW>
                idx = idx + 1;
            end
        end
        
        hemorrhageResult = struct();
        hemorrhageResult.binaryMask = finalMask;
        hemorrhageResult.count = length(validRegions);
        hemorrhageResult.types = types;
        hemorrhageResult.regions = validRegions;
        
    catch ME
        error('DRPipeline:segmentation:HemorrhageClassificationError', ...
            'Failed to classify hemorrhages: %s', ME.message);
    end
end
