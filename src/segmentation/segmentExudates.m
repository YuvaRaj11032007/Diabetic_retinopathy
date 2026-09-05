function exudateResult = segmentExudates(img, odMask, vesselMask)
%SEGMENTEXUDATES Segment hard and soft exudates in retinal images
%
%   exudateResult = segmentExudates(img, odMask, vesselMask) segments
%   bright lesions (hard exudates and cotton-wool spots) using L*a*b*
%   color space thresholding and morphological operations.
%
%   INPUTS:
%       img        - Enhanced RGB retinal image (HxWx3 uint8 or double)
%       odMask     - Binary mask of optic disc (HxW logical)
%       vesselMask - Binary mask of retinal vessels (HxW logical)
%
%   OUTPUTS:
%       exudateResult - Struct with fields:
%                       .hardExudateMask : HxW logical mask of hard exudates
%                       .softExudateMask : HxW logical mask of soft exudates
%                       .totalArea       : Total area of all exudates (pixels)
%                       .count           : Total number of distinct exudates
%                       .regions         : regionprops struct with details
%
%   EXAMPLE:
%       result = segmentExudates(img, odMask, vesselMask);
%       imshow(result.hardExudateMask | result.softExudateMask);

    arguments
        img (:,:,3) {mustBeNumeric}
        odMask (:,:) logical
        vesselMask (:,:) logical
    end

    try
        if isinteger(img)
            imgDouble = im2double(img);
        else
            imgDouble = img;
        end
        
        % Generate fundus mask (simple threshold to exclude dark background)
        grayImg = rgb2gray(imgDouble);
        fundusMask = grayImg > 0.05;
        
        % 1. Convert to L*a*b* color space
        labImg = rgb2lab(imgDouble);
        L = labImg(:,:,1);
        b = labImg(:,:,3);
        
        % 2. Thresholding
        % Extract values only within the fundus
        L_fundus = L(fundusMask);
        b_fundus = b(fundusMask);
        
        if isempty(L_fundus)
            error('DRPipeline:segmentation:InvalidFundusMask', 'No valid fundus area detected.');
        end
        
        L_thresh = prctile(L_fundus, 90); % Top 10% brightest pixels
        b_thresh = prctile(b_fundus, 80); % High yellow component
        
        brightMask = (L > L_thresh) & fundusMask;
        yellowMask = (b > b_thresh) & fundusMask;
        
        % Combine masks
        candidateMask = brightMask & yellowMask;
        
        % 3. Morphological reconstruction to get full exudate bodies
        markerMask = imerode(candidateMask, strel('disk', 1));
        reconstructedMask = imreconstruct(markerMask, candidateMask);
        
        % 4. Exclude OD region (dilate OD mask by 1.5x radius)
        odStats = regionprops(odMask, 'EquivDiameter');
        if ~isempty(odStats)
            odRadius = max([odStats.EquivDiameter]) / 2;
            seOD = strel('disk', round(odRadius * 1.5));
            expandedOD = imdilate(odMask, seOD);
            reconstructedMask(expandedOD) = false;
        end
        
        % Remove vessels just in case
        reconstructedMask(vesselMask) = false;
        
        % 5. Differentiate Hard and Soft Exudates by size and intensity
        stats = regionprops(reconstructedMask, L, 'Area', 'MeanIntensity', 'PixelIdxList', 'BoundingBox');
        
        hardMask = false(size(reconstructedMask));
        softMask = false(size(reconstructedMask));
        
        for i = 1:length(stats)
            % Ignore very small artifacts
            if stats(i).Area < 10
                continue;
            end
            
            % Soft exudates (cotton-wool spots) tend to be larger and slightly less intense
            if stats(i).Area > 300 && stats(i).MeanIntensity < prctile(L_fundus, 98)
                softMask(stats(i).PixelIdxList) = true;
            else
                hardMask(stats(i).PixelIdxList) = true;
            end
        end
        
        % Combine for output regions
        finalMask = hardMask | softMask;
        regions = regionprops(finalMask, 'Area', 'Centroid', 'BoundingBox');
        
        exudateResult = struct();
        exudateResult.hardExudateMask = hardMask;
        exudateResult.softExudateMask = softMask;
        exudateResult.totalArea = sum(finalMask, 'all');
        exudateResult.count = length(regions);
        exudateResult.regions = regions;
        
    catch ME
        error('DRPipeline:segmentation:ExudateSegmentationError', ...
            'Failed to segment exudates: %s', ME.message);
    end
end
