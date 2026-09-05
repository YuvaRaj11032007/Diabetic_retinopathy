function features = extractQualityFeatures(img, mask)
%EXTRACTQUALITYFEATURES Compute image quality features for fundus images.
%   FEATURES = EXTRACTQUALITYFEATURES(IMG) computes a set of quality
%   features for the fundus image IMG. Returns a struct with numeric
%   features indicating focus, illumination, contrast, and FOV coverage.
%
%   FEATURES = EXTRACTQUALITYFEATURES(IMG, MASK) uses the binary MASK to
%   restrict analysis to the fundus region only.
%
%   Quality Features Computed:
%     1. focusScore     - Laplacian variance (higher = sharper)
%     2. luminanceMean  - Mean luminance in the ROI (0-1)
%     3. luminanceStd   - Luminance std deviation (uniformity)
%     4. fovCoverage    - Fraction of image area covered by fundus
%     5. histEntropy    - Histogram entropy of green channel
%     6. contrastScore  - Michelson contrast in the green channel
%
%   Example:
%       img = imread('fundus.jpg');
%       features = extractQualityFeatures(img);
%       fprintf('Focus: %.4f\n', features.focusScore);
%
%   See also: QUALITYGATE, CLASSIFYQUALITY, ENHANCEFUNDUSIMAGE

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Quality Assessment Module
% -------------------------------------------------------------------------

    arguments
        img (:,:,:) uint8
        mask (:,:) logical = logical([])
    end

    % Validate image is RGB
    if size(img, 3) ~= 3
        error('DRPipeline:quality:notRGB', ...
            'Input image must be RGB (3 channels). Got %d channels.', size(img, 3));
    end

    % Convert to double for computation
    imgD = im2double(img);

    % Auto-generate mask if not provided
    if isempty(mask)
        grayImg = rgb2gray(img);
        mask = grayImg > 15;  % Simple threshold to find fundus region
        mask = imfill(mask, 'holes');
        mask = bwareaopen(mask, round(numel(grayImg) * 0.01));
        % Morphological smoothing
        se = strel('disk', 15);
        mask = imclose(mask, se);
        mask = imopen(mask, se);
    end

    % Validate mask dimensions
    if ~isequal(size(mask), size(img, 1:2))
        error('DRPipeline:quality:maskSizeMismatch', ...
            'Mask dimensions [%d,%d] must match image [%d,%d].', ...
            size(mask, 1), size(mask, 2), size(img, 1), size(img, 2));
    end

    % Extract green channel (highest contrast for retinal structures)
    greenCh = imgD(:,:,2);

    % ---- Feature 1: Focus Score (Laplacian Variance) ----
    lapKernel = fspecial('laplacian', 0.2);
    lapResponse = imfilter(greenCh, lapKernel, 'symmetric');
    maskedLap = lapResponse(mask);
    features.focusScore = var(maskedLap(:));

    % ---- Feature 2: Mean Luminance ----
    grayD = rgb2gray(imgD);
    maskedGray = grayD(mask);
    features.luminanceMean = mean(maskedGray);

    % ---- Feature 3: Luminance Std (uniformity indicator) ----
    features.luminanceStd = std(maskedGray);

    % ---- Feature 4: FOV Coverage ----
    totalPixels = numel(mask);
    fundusPixels = sum(mask(:));
    features.fovCoverage = fundusPixels / totalPixels;

    % ---- Feature 5: Histogram Entropy ----
    greenUint8 = im2uint8(greenCh);
    maskedGreen = greenUint8(mask);
    % Compute histogram manually for masked region
    counts = histcounts(maskedGreen, 0:256);
    probabilities = counts / sum(counts);
    probabilities(probabilities == 0) = [];  % Remove zeros for log
    features.histEntropy = -sum(probabilities .* log2(probabilities));

    % ---- Feature 6: Contrast Score (Michelson) ----
    Imax = prctile(maskedGray, 99);  % Use 99th percentile to avoid outliers
    Imin = prctile(maskedGray, 1);
    if (Imax + Imin) > 0
        features.contrastScore = (Imax - Imin) / (Imax + Imin);
    else
        features.contrastScore = 0;
    end

    % ---- Normalize all features to [0, 1] range ----
    % Store raw values for debugging, but also provide normalized version
    features.raw = features;  % Save raw copy

    % Normalization ranges based on empirical observation across datasets
    features.focusScore     = min(1, features.focusScore / 0.05);     % 0.05 = very sharp
    features.luminanceMean  = features.luminanceMean;                  % Already [0,1]
    features.luminanceStd   = min(1, features.luminanceStd / 0.3);    % 0.3 = high variation
    features.fovCoverage    = features.fovCoverage;                    % Already [0,1]
    features.histEntropy    = features.histEntropy / 8;                % Max entropy = 8 bits
    features.contrastScore  = features.contrastScore;                  % Already [0,1]

    % ---- Feature vector for classifier ----
    features.vector = [features.focusScore, features.luminanceMean, ...
                       features.luminanceStd, features.fovCoverage, ...
                       features.histEntropy, features.contrastScore];
end
