function denoised = denoiseImage(img, method, strength)
%DENOISEIMAGE Apply denoising to a fundus image.
%   DENOISED = DENOISEIMAGE(IMG) applies non-local means denoising to the
%   fundus image IMG with default parameters optimized for retinal images.
%
%   DENOISED = DENOISEIMAGE(IMG, METHOD) specifies the denoising method:
%     'nlm'      - Non-local means filtering (default, best quality)
%     'bilateral' - Bilateral filtering (fast, edge-preserving)
%     'gaussian'  - Simple Gaussian smoothing (fastest, least effective)
%
%   DENOISED = DENOISEIMAGE(IMG, METHOD, STRENGTH) specifies the denoising
%   strength as a scalar in [0.5, 5.0]. Default is 1.0. Higher values
%   remove more noise but may blur fine structures.
%
%   Example:
%       img = imread('fundus.jpg');
%       denoised = denoiseImage(img, 'nlm', 1.5);
%       imshowpair(img, denoised, 'montage');
%
%   See also: IMNLMFILT, IMBILATFILT, ENHANCEFUNDUSIMAGE, APPLYCLAHE

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Quality Assessment Module
% -------------------------------------------------------------------------

    arguments
        img (:,:,:) uint8
        method (1,:) char {mustBeMember(method, {'nlm', 'bilateral', 'gaussian'})} = 'nlm'
        strength (1,1) double {mustBePositive} = 1.0
    end

    switch method
        case 'nlm'
            % Non-local means denoising
            % DegreeOfSmoothing controls noise removal (higher = more)
            % SearchWindowSize and ComparisonWindowSize affect quality vs speed
            degreeOfSmoothing = strength * 0.005;  % Scale to reasonable range

            denoised = imnlmfilt(img, ...
                'DegreeOfSmoothing', degreeOfSmoothing, ...
                'SearchWindowSize', 21, ...
                'ComparisonWindowSize', 5);

        case 'bilateral'
            % Bilateral filtering - edge-preserving smoothing
            spatialSigma = 2.0 * strength;
            imgD = im2double(img);
            denoisedD = zeros(size(imgD), 'like', imgD);

            for ch = 1:size(imgD, 3)
                denoisedD(:,:,ch) = imbilatfilt(imgD(:,:,ch), ...
                    0.1 * strength, spatialSigma);
            end

            denoised = im2uint8(denoisedD);

        case 'gaussian'
            % Simple Gaussian smoothing
            sigma = 0.5 * strength;
            denoised = imgaussfilt(img, sigma);
    end

    % Validate output
    if any(isnan(denoised(:)))
        warning('DRPipeline:quality:denoisingNaN', ...
            'Denoising produced NaN values. Returning original image.');
        denoised = img;
    end
end
