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

        % 3. Multi-Scale Morphological Top-Hat filter for local contrast isolation
        % Captures both small punctate flecks and large confluent plaques
        tophatG = max(cat(3, ...
            imtophat(G, strel('disk', 6)), ...
            imtophat(G, strel('disk', 15)), ...
            imtophat(G, strel('disk', 30))), [], 3);
        
        tophatL = max(cat(3, ...
            imtophat(L / 100, strel('disk', 6)), ...
            imtophat(L / 100, strel('disk', 15)), ...
            imtophat(L / 100, strel('disk', 30))), [], 3);
        
        contrastBright = max(tophatG, tophatL);

        % 4. Color & Contrast Thresholding for Hard Exudates
        % Hard exudates are distinct, bright yellow-white lipid deposits.
        % They exhibit high local contrast against the retinal background (>0.06),
        % high luminance, elevated green channel intensity, and strong yellow component (b* > 0).
        pL85 = prctile(L_fundus, 85);
        pb75 = prctile(b_fundus, 75);
        pG80 = prctile(G(fundusMask), 80);

        % Core seeds: MUST have high local contrast (> 0.065) AND high brightness AND yellow hue
        % Normal smooth retina has contrast < 0.02, completely eliminating false positives on healthy eyes
        isYellowCore = (b > pb75) & (G > B + 0.08) & (G ./ (R + 1e-4) > 0.58);
        coreSeeds = (contrastBright > 0.065) & (L > pL85) & (G > pG80) & isYellowCore & fundusMask;

        % Boundary for morphological reconstruction (region growing)
        isYellowBound = (b > median(b_fundus)) & (G > B + 0.03) & (G ./ (R + 1e-4) > 0.48);
        boundaryMask = (contrastBright > 0.035) & (L > median(L_fundus)) & isYellowBound & fundusMask;

        % 5. Optic Disc Exclusion
        odStats = regionprops(odMask, 'EquivDiameter');
        if ~isempty(odStats)
            odDiam = max([odStats.EquivDiameter]);
            odRadius = odDiam / 2;
            seMargin = max(6, min(18, round(odRadius * 0.20)));
            expandedOD = imdilate(odMask, strel('disk', seMargin));
            coreSeeds(expandedOD) = false;
            boundaryMask(expandedOD) = false;
        end

        % 6. Vessel Exclusion
        if any(vesselMask(:))
            coreSeeds(vesselMask) = false;
            boundaryMask(vesselMask) = false;
        end

        % 7. Morphological reconstruction to recover full confluent lesions
        if any(coreSeeds(:))
            reconstructedMask = imreconstruct(coreSeeds, boundaryMask);
        else
            reconstructedMask = false(H, W);
        end

        % 8. Remove small noise (minimum 10 pixels for genuine exudates)
        reconstructedMask = bwareaopen(reconstructedMask, 10);

        % 9. Differentiate Hard and Soft Exudates
        stats = regionprops(reconstructedMask, L, 'Area', 'MeanIntensity', 'PixelIdxList', 'BoundingBox');

        hardMask = false(H, W);
        softMask = false(H, W);

        for i = 1:length(stats)
            if stats(i).Area < 10
                continue;
            end

            regionPixels = stats(i).PixelIdxList;
            meanB = mean(b(regionPixels));

            % Soft exudates (cotton-wool spots) are white/gray with low yellowness (b* <= pb75)
            % Confluent hard exudates retain high yellowness (b* > pb75) even when large
            if stats(i).Area > 350 && meanB <= pb75
                softMask(regionPixels) = true;
            else
                hardMask(regionPixels) = true;
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
