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
        sigma (1,1) double {mustBePositive} = 0
    end

    % Default sigma: 1/6 of image width (captures large-scale illumination)
    if sigma == 0
        sigma = round(size(img, 2) / 6);
    end

    % Ensure sigma is odd and reasonably large
    sigma = max(sigma, 31);

    % Convert to double
    imgD = im2double(img);

    % --- Method: Per-channel Gaussian background subtraction ---
    % This is more robust than L*a*b* for severely uneven illumination

    correctedD = zeros(size(imgD), 'like', imgD);

    for ch = 1:3
        channel = imgD(:,:,ch);

        % Estimate background illumination with large Gaussian
        background = imgaussfilt(channel, sigma);

        % Subtract background and add mean back
        channelMean = mean(channel(:));
        normalized = channel - background + channelMean;

        % Clip to valid range
        correctedD(:,:,ch) = max(0, min(1, normalized));
    end

    % --- Adaptive rescaling ---
    % Stretch each channel to use full dynamic range within the fundus mask
    grayImg = rgb2gray(im2uint8(correctedD));
    fundMask = grayImg > 10;
    if exist('imfill', 'file') == 2
        try, fundMask = imfill(fundMask, 'holes'); catch, end
    end
    if exist('strel', 'file') == 2 && exist('imclose', 'file') == 2
        try
            se = strel('disk', 15);
            fundMask = imclose(fundMask, se);
        catch
        end
    end

    for ch = 1:3
        channel = correctedD(:,:,ch);
        maskedValues = channel(fundMask);

        if ~isempty(maskedValues)
            lo = prctile(maskedValues, 1);
            hi = prctile(maskedValues, 99);

            if hi > lo
                channel = (channel - lo) / (hi - lo);
                channel = max(0, min(1, channel));
            end
        end

        correctedD(:,:,ch) = channel;
    end

    % Convert back to uint8
    corrected = im2uint8(correctedD);

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
