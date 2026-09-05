function [enhanced, processLog] = enhanceFundusImage(img, options)
%ENHANCEFUNDUSIMAGE Master preprocessing function for fundus images.
%   ENHANCED = ENHANCEFUNDUSIMAGE(IMG) applies the complete preprocessing
%   pipeline to a fundus image: illumination normalization, CLAHE contrast
%   enhancement, and denoising. Returns the enhanced RGB image.
%
%   [ENHANCED, PROCESSLOG] = ENHANCEFUNDUSIMAGE(IMG) also returns a struct
%   with processing metadata: timing per step, PSNR/SSIM improvements.
%
%   ENHANCED = ENHANCEFUNDUSIMAGE(IMG, OPTIONS) with name-value options:
%     'EnableIllumNorm' (true)  - Enable illumination normalization
%     'EnableCLAHE'     (true)  - Enable CLAHE contrast enhancement
%     'EnableDenoise'   (true)  - Enable denoising
%     'CLAHEClipLimit'  (0.01)  - CLAHE clip limit
%     'CLAHETiles'      ([8 8]) - CLAHE tile grid
%     'DenoiseMethod'   ('nlm') - Denoising method: 'nlm', 'bilateral', 'gaussian'
%     'DenoiseStrength' (1.0)   - Denoising strength [0.5, 5.0]
%     'GaussSigma'      (0)     - Illumination norm Gaussian sigma (0=auto)
%
%   The pipeline is applied in order: Illumination → CLAHE → Denoising
%   This order ensures CLAHE operates on uniformly illuminated data, and
%   denoising cleans up any artifacts introduced by the prior steps.
%
%   Example:
%       img = imread('fundus.jpg');
%       [enhanced, log] = enhanceFundusImage(img);
%       fprintf('PSNR improvement: %.1f dB\n', log.psnr);
%       imshowpair(img, enhanced, 'montage');
%
%   See also: NORMALIZEILLUMINATION, APPLYCLAHE, DENOISEIMAGE, QUALITYGATE

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Quality Assessment Module
% -------------------------------------------------------------------------

    arguments
        img (:,:,3) uint8
        options.EnableIllumNorm (1,1) logical = true
        options.EnableCLAHE (1,1) logical = true
        options.EnableDenoise (1,1) logical = true
        options.CLAHEClipLimit (1,1) double = 0.01
        options.CLAHETiles (1,2) double = [8 8]
        options.DenoiseMethod (1,:) char = 'nlm'
        options.DenoiseStrength (1,1) double = 1.0
        options.GaussSigma (1,1) double = 0
    end

    processLog = struct();
    processLog.steps = {};
    totalTimer = tic;
    current = img;

    % ---- Step 1: Illumination Normalization ----
    if options.EnableIllumNorm
        stepTimer = tic;
        try
            current = normalizeIllumination(current, options.GaussSigma);
            processLog.illuminationTime = toc(stepTimer);
            processLog.steps{end+1} = 'illumination_normalization';
        catch ME
            warning('DRPipeline:quality:illumNormFailed', ...
                'Illumination normalization failed: %s. Skipping.', ME.message);
            processLog.illuminationTime = toc(stepTimer);
            processLog.illuminationError = ME.message;
        end
    end

    % ---- Step 2: CLAHE ----
    if options.EnableCLAHE
        stepTimer = tic;
        try
            current = applyCLAHE(current, options.CLAHEClipLimit, options.CLAHETiles);
            processLog.claheTime = toc(stepTimer);
            processLog.steps{end+1} = 'clahe';
        catch ME
            warning('DRPipeline:quality:claheFailed', ...
                'CLAHE failed: %s. Skipping.', ME.message);
            processLog.claheTime = toc(stepTimer);
            processLog.claheError = ME.message;
        end
    end

    % ---- Step 3: Denoising ----
    if options.EnableDenoise
        stepTimer = tic;
        try
            current = denoiseImage(current, options.DenoiseMethod, ...
                                   options.DenoiseStrength);
            processLog.denoiseTime = toc(stepTimer);
            processLog.steps{end+1} = 'denoising';
        catch ME
            warning('DRPipeline:quality:denoiseFailed', ...
                'Denoising failed: %s. Skipping.', ME.message);
            processLog.denoiseTime = toc(stepTimer);
            processLog.denoiseError = ME.message;
        end
    end

    enhanced = current;
    processLog.totalTime = toc(totalTimer);

    % ---- Quality Metrics: PSNR and SSIM ----
    imgD = im2double(img);
    enhD = im2double(enhanced);

    % PSNR
    mse = mean((imgD(:) - enhD(:)).^2);
    if mse > 0
        processLog.psnr = 10 * log10(1 / mse);
    else
        processLog.psnr = Inf;  % Identical images
    end

    % SSIM
    processLog.ssim = ssim(enhanced, img);

    % Log summary
    processLog.inputSize = size(img);
    processLog.stepsApplied = numel(processLog.steps);
end
