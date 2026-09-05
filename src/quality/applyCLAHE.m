function enhanced = applyCLAHE(img, clipLimit, numTiles)
%APPLYCLAHE Apply Contrast-Limited Adaptive Histogram Equalization.
%   ENHANCED = APPLYCLAHE(IMG) applies CLAHE to the fundus image IMG.
%   Works on the green channel (best contrast for retinal structures) or
%   the L* channel of L*a*b* color space.
%
%   ENHANCED = APPLYCLAHE(IMG, CLIPLIMIT) specifies the contrast clip
%   limit. Default is 0.01 (conservative for medical images).
%
%   ENHANCED = APPLYCLAHE(IMG, CLIPLIMIT, NUMTILES) specifies the number
%   of tiles for CLAHE. Default is [8 8].
%
%   Example:
%       img = imread('fundus.jpg');
%       enhanced = applyCLAHE(img, 0.02, [16 16]);
%       imshowpair(img, enhanced, 'montage');
%
%   See also: ADAPTHISTEQ, ENHANCEFUNDUSIMAGE, DENOISEIMAGE

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Quality Assessment Module
% -------------------------------------------------------------------------

    arguments
        img (:,:,:) uint8
        clipLimit (1,1) double {mustBePositive, mustBeLessThan(clipLimit, 1)} = 0.01
        numTiles (1,2) double {mustBePositive, mustBeInteger} = [8 8]
    end

    if size(img, 3) == 1
        error('DRPipeline:quality:notRGB', ...
            'CLAHE expects an RGB image. Got grayscale.');
    end

    % Convert to L*a*b* color space for perceptually uniform enhancement
    lab = rgb2lab(img);

    % Extract L* channel and normalize to [0, 1] for adapthisteq
    L = lab(:,:,1);
    L_normalized = L / 100;  % L* ranges from 0 to 100

    % Apply CLAHE to the L* channel
    L_enhanced = adapthisteq(L_normalized, ...
        'ClipLimit', clipLimit, ...
        'NumTiles', numTiles, ...
        'Distribution', 'rayleigh', ...
        'Alpha', 0.4, ...
        'Range', 'full');

    % Put enhanced L* back
    lab(:,:,1) = L_enhanced * 100;

    % Convert back to RGB
    enhanced = lab2rgb(lab, 'OutputType', 'uint8');
end
