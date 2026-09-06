function corrected = normalizeIllumination(img, sigma)
%NORMALIZEILLUMINATION Correct uneven illumination in fundus images.
%   CORRECTED = NORMALIZEILLUMINATION(IMG) applies illumination
%   normalization to the fundus image IMG using large-kernel Gaussian
%   background estimation and subtraction. This corrects vignetting and
%   uneven flash illumination common in retinal photography.
%
%   CORRECTED = NORMALIZEILLUMINATION(IMG, SIGMA) uses the specified
%   Gaussian kernel standard deviation SIGMA. Default is 1/6 of the image
%   width (empirically optimal for most fundus cameras).
%
%   Method:
%     1. Convert to L*a*b* color space
%     2. Estimate background illumination via large Gaussian blur on L*
%     3. Subtract estimated background from L* channel
%     4. Rescale L* to full dynamic range
%     5. Convert back to RGB
%
%   Example:
%       img = imread('fundus.jpg');
%       corrected = normalizeIllumination(img);
%       imshowpair(img, corrected, 'montage');
%
%   Reference:
%       Foracchia, M., Grisan, E., Ruggeri, A. (2005). "Luminosity and
%       contrast normalization in retinal images." Medical Image Analysis.
%
%   See also: ENHANCEFUNDUSIMAGE, APPLYCLAHE, DENOISEIMAGE

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Quality Assessment Module
% -------------------------------------------------------------------------

    arguments
        img (:,:,3) uint8
        sigma (1,1) double {mustBeNonnegative} = 0
    end

    % Default sigma: 1/6 of image width (captures large-scale illumination)
    if sigma == 0
        sigma = round(size(img, 2) / 6);
    end

    % Ensure sigma is odd and reasonably large
    sigma = max(sigma, 31);

    % Convert to double
    % Convert to L*a*b* color space for illumination normalization (preserves color ratios)
    labImg = rgb2lab(img);
    L = labImg(:,:,1);
    a = labImg(:,:,2);
    b = labImg(:,:,3);

    % Segment circular fundus foreground
    grayImg = rgb2gray(img);
    fundMask = grayImg > 15;
    if exist('imfill', 'file') == 2
        try, fundMask = imfill(fundMask, 'holes'); catch, end
    end
    if exist('strel', 'file') == 2 && exist('imerode', 'file') == 2
        try, fundMask = imerode(fundMask, strel('disk', 8)); catch, end
    end

    % Estimate background illumination on L* channel
    backgroundL = imgaussfilt(L, sigma);

    % Normalize L* within fundus mask
    if any(fundMask(:))
        targetMean = mean(L(fundMask));
        L_norm = L - backgroundL + targetMean;
        L_norm = max(0, min(100, L_norm));
        L(fundMask) = L_norm(fundMask);
    end

    labImg(:,:,1) = L;
    corrected = lab2rgb(labImg, 'OutputType', 'uint8');

    % --- Validation: check that illumination is more uniform ---
    % Compare quadrant mean luminance std before and after
    origGray = im2double(rgb2gray(img));
    corrGray = im2double(rgb2gray(corrected));

    [h, w] = size(origGray);


    origMeans = zeros(1, 4);
    corrMeans = zeros(1, 4);

    % Compute per-quadrant mean luminance
    halfH = round(h/2);
    halfW = round(w/2);
    origMeans(1) = mean(origGray(1:halfH, 1:halfW), 'all');
    origMeans(2) = mean(origGray(1:halfH, halfW+1:w), 'all');
    origMeans(3) = mean(origGray(halfH+1:h, 1:halfW), 'all');
    origMeans(4) = mean(origGray(halfH+1:h, halfW+1:w), 'all');

    corrMeans(1) = mean(corrGray(1:halfH, 1:halfW), 'all');
    corrMeans(2) = mean(corrGray(1:halfH, halfW+1:w), 'all');
    corrMeans(3) = mean(corrGray(halfH+1:h, 1:halfW), 'all');
    corrMeans(4) = mean(corrGray(halfH+1:h, halfW+1:w), 'all');

    origStd = std(origMeans);
    corrStd = std(corrMeans);

    if corrStd > origStd
        warning('DRPipeline:quality:illuminationWorse', ...
            'Illumination normalization increased quadrant variance (%.4f -> %.4f). Check input image.', ...
            origStd, corrStd);
    end
end
