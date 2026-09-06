function exudateResult = segmentExudates(img, odMask, vesselMask, options)
%SEGMENTEXUDATES Segment hard and soft exudates in retinal fundus images.
%
%   exudateResult = segmentExudates(img, odMask, vesselMask) segments
%   bright lesions (hard exudates and cotton-wool spots) using dual-channel
%   morphological top-hat filtering and L*a*b* color thresholding.
%
%   INPUTS:
%       img        - Enhanced RGB retinal image (HxWx3 uint8 or double)
%       odMask     - Binary mask of optic disc (HxW logical, optional)
%       vesselMask - Binary mask of retinal vessels (HxW logical, optional)
%       options    - Optional struct or Name-Value pairs:
%                    .model - Pretrained model struct (optional)
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
        odMask = []
        vesselMask = []
        options.model = []
    end

    try
        if isinteger(img)
            imgDouble = im2double(img);
        else
            imgDouble = img;
        end
        [H, W, ~] = size(imgDouble);

        if isempty(odMask) || ~islogical(odMask) || ~isequal(size(odMask), [H, W])
            odMask = false(H, W);
        end
        if isempty(vesselMask) || ~islogical(vesselMask) || ~isequal(size(vesselMask), [H, W])
            vesselMask = false(H, W);
        end

        % 1. Robust fundus mask (erode border to avoid camera glare/ring artifacts)
        grayImg = rgb2gray(imgDouble);
        fundusMask = grayImg > 0.04;
        fundusMask = imfill(fundusMask, 'holes');
        fundusMask = imerode(fundusMask, strel('disk', 15));

        % 2. Multi-channel representation (RGB & L*a*b*)
        R = imgDouble(:, :, 1);
        G = imgDouble(:, :, 2);
        B = imgDouble(:, :, 3);
        labImg = rgb2lab(imgDouble);
        L = labImg(:, :, 1);
        b = labImg(:, :, 3);

        L_fundus = L(fundusMask);
        b_fundus = b(fundusMask);

        if isempty(L_fundus)
            error('DRPipeline:segmentation:InvalidFundusMask', 'No valid fundus area detected.');
        end

        % 3. Morphological Top-Hat filter for local contrast isolation
        tophatG = imtophat(G, strel('disk', 12));
        tophatL = imtophat(L / 100, strel('disk', 12));
        contrastBright = max(tophatG, tophatL);

        % Real hard exudates have sharp local contrast (> 0.075), not subtle background texture
        contrastMask = (contrastBright > 0.075) & fundusMask;

        % 4. Color & Brightness thresholding
        % Real exudates are among the brightest pixels with strong yellow component
        pL92 = prctile(L_fundus, 92);
        pb75 = prctile(b_fundus, 75);

        brightL = (L > pL92) & fundusMask;
        yellowB = (b > pb75) & fundusMask;

        % Color verification: exudates are yellow-white (high R and G, lower B)
        isYellowish = (R > B + 0.08) & (G > B) & (R > 0.45);

        % Candidates must have high local contrast AND high brightness AND yellow hue
        candidateMask = contrastMask & brightL & yellowB & isYellowish & fundusMask;

        % 5. Optic Disc Exclusion
        odStats = regionprops(odMask, 'EquivDiameter');
        if ~isempty(odStats)
            odDiam = max([odStats.EquivDiameter]);
            odRadius = odDiam / 2;
            seMargin = max(5, min(14, round(odRadius * 0.15)));
            expandedOD = imdilate(odMask, strel('disk', seMargin));
            candidateMask(expandedOD) = false;
        end

        % 6. Vessel Exclusion
        if any(vesselMask(:))
            candidateMask(vesselMask) = false;
        end

        % 7. Remove small noise (minimum 10 pixels for genuine exudates)
        candidateMask = bwareaopen(candidateMask, 10);

        % 8. Morphological reconstruction to restore full lesion borders
        marker = imerode(candidateMask, strel('disk', 1));
        if any(marker(:))
            reconstructedMask = imreconstruct(marker, candidateMask);
        else
            reconstructedMask = candidateMask;
        end

        % 9. Differentiate Hard and Soft Exudates
        stats = regionprops(reconstructedMask, L, 'Area', 'MeanIntensity', 'PixelIdxList', 'BoundingBox');

        hardMask = false(H, W);
        softMask = false(H, W);

        for i = 1:length(stats)
            if stats(i).Area < 6
                continue;
            end

            % Soft exudates (cotton-wool spots) are larger, diffuse, and slightly less bright
            if stats(i).Area > 280 && stats(i).MeanIntensity < prctile(L_fundus, 96)
                softMask(stats(i).PixelIdxList) = true;
            else
                hardMask(stats(i).PixelIdxList) = true;
            end
        end

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
