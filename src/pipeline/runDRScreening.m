function result = runDRScreening(imagePath, options)
%RUNDRSCREENING Run the complete DR screening pipeline on a single image.
%   RESULT = RUNDRSCREENING(IMAGEPATH) processes a single fundus image
%   through the complete pipeline: Quality Assessment → Enhancement →
%   Segmentation → Feature Extraction → Grading → Explainability → Report.
%
%   RESULT = RUNDRSCREENING(IMAGEPATH, OPTIONS) with options:
%     'ModelsDir'      - Directory containing trained models (default: 'models/')
%     'OutputDir'      - Directory for output reports (default: 'results/reports/')
%     'GenerateReport' - Whether to generate PDF/HTML report (default: true)
%     'Verbose'        - Print progress messages (default: true)
%     'QualityModel'   - Pre-loaded quality classifier model (default: [])
%     'SegModels'      - Pre-loaded segmentation models struct (default: [])
%     'GradingModels'  - Pre-loaded grading models struct (default: [])
%     'CalibParams'    - Pre-loaded calibration parameters (default: [])
%
%   Output RESULT struct fields:
%     .grade           - DR grade (0-4), or NaN if image rejected
%     .gradeName       - Human-readable grade name
%     .confidence      - Calibrated confidence score [0-1]
%     .isReferable     - Boolean: true if grade >= 2
%     .reportPath      - Path to generated report (or '' if not generated)
%     .qualityResult   - Quality assessment details
%     .segmentation    - All segmentation results
%     .evidence        - Lesion-level evidence mapping
%     .gradcam         - Grad-CAM attention heatmap
%     .processingTime  - Per-module timing breakdown
%     .feedback        - Recapture feedback (if rejected)
%
%   Example:
%       result = runDRScreening('data/raw/idrid/images/IDRiD_001.jpg');
%       fprintf('Grade: %d (%s), Confidence: %.1f%%\n', ...
%           result.grade, result.gradeName, result.confidence * 100);
%
%   See also: QUALITYGATE, RUNALLSEGMENTATION, EVALUATEDRCLASSIFIER,
%             GENERATEREPORT, BATCHPROCESSIMAGES

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Master Orchestrator
% -------------------------------------------------------------------------

    arguments
        imagePath (1,:) char {mustBeFile}
        options.ModelsDir (1,:) char = ''
        options.OutputDir (1,:) char = ''
        options.GenerateReport (1,1) logical = true
        options.Verbose (1,1) logical = true
        options.QualityModel = []
        options.SegModels = []
        options.GradingModels = []
        options.CalibParams = []
    end

    % Initialize result
    result = struct();
    result.imagePath = imagePath;
    result.timestamp = datetime('now');
    timings = struct();
    totalTimer = tic;

    % Resolve directories
    projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
    if isempty(projectRoot)
        projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    end

    if isempty(options.ModelsDir)
        options.ModelsDir = fullfile(projectRoot, 'models');
    end
    if isempty(options.OutputDir)
        options.OutputDir = fullfile(projectRoot, 'results', 'reports');
    end

    gradeNames = {'No DR (Level 0)', 'Mild NPDR (Level 1)', ...
                  'Moderate NPDR (Level 2)', 'Severe NPDR (Level 3)', ...
                  'PDR (Level 4)'};

    if options.Verbose
        fprintf('\n[DRScreening] Processing: %s\n', imagePath);
        fprintf('[DRScreening] %-30s', 'Loading image...');
    end

    % =====================================================================
    % STEP 1: Load Image
    % =====================================================================
    stepTimer = tic;
    try
        img = loadFundusImage(imagePath);
    catch ME
        result.grade = NaN;
        result.gradeName = 'Error';
        result.confidence = 0;
        result.isReferable = false;
        result.error = ME.message;
        result.reportPath = '';
        if options.Verbose
            fprintf('FAILED (%s)\n', ME.message);
        end
        return;
    end
    timings.imageLoad = toc(stepTimer);
    if options.Verbose, fprintf('done (%.2fs)\n', timings.imageLoad); end

    % =====================================================================
    % STEP 2: Quality Assessment
    % =====================================================================
    if options.Verbose
        fprintf('[DRScreening] %-30s', 'Quality assessment...');
    end
    stepTimer = tic;

    try
        [decision, qualityResult, enhancedImg] = qualityGate(img, options.QualityModel, ...
            'Verbose', false);
    catch ME
        warning('DRPipeline:pipeline:qualityFailed', ...
            'Quality assessment failed: %s. Proceeding with original image.', ME.message);
        decision = 'accept';
        qualityResult = struct('decision', 'accept', 'qualityScore', NaN, 'error', ME.message);
        enhancedImg = img;
    end

    timings.quality = toc(stepTimer);
    result.qualityResult = qualityResult;

    if options.Verbose
        fprintf('%s (%.2fs)\n', upper(decision), timings.quality);
    end

    % Handle rejection
    if strcmp(decision, 'reject')
        result.grade = NaN;
        result.gradeName = 'Rejected';
        result.confidence = 0;
        result.isReferable = false;
        result.reportPath = '';
        result.feedback = generateRecaptureFeedback(qualityResult);
        result.processingTime = timings;
        result.processingTime.total = toc(totalTimer);

        if options.Verbose
            fprintf('[DRScreening] Image REJECTED: %s\n', result.feedback.reason_text_en);
        end
        return;
    end

    % =====================================================================
    % STEP 3: Segmentation
    % =====================================================================
    if options.Verbose
        fprintf('[DRScreening] %-30s', 'Running segmentation...');
    end
    stepTimer = tic;

    try
        segResult = runAllSegmentation(enhancedImg, options.SegModels);
    catch ME
        warning('DRPipeline:pipeline:segFailed', ...
            'Segmentation failed: %s. Using empty results.', ME.message);
        segResult = createEmptySegResult();
    end

    timings.segmentation = toc(stepTimer);
    result.segmentation = segResult;

    if options.Verbose
        fprintf('done (%.2fs)\n', timings.segmentation);
    end

    % =====================================================================
    % STEP 4: Feature Extraction
    % =====================================================================
    if options.Verbose
        fprintf('[DRScreening] %-30s', 'Extracting features...');
    end
    stepTimer = tic;

    % Clinical features from segmentation
    try
        foveaLoc = [];
        if isfield(segResult, 'fovea') && isfield(segResult.fovea, 'center')
            foveaLoc = segResult.fovea.center;
        end
        clinicalFeats = aggregateFeatures(segResult, foveaLoc);
    catch ME
        warning('DRPipeline:pipeline:clinFeatFailed', ...
            'Clinical feature extraction failed: %s', ME.message);
        clinicalFeats = struct('vector', zeros(1, 14));
    end

    % Deep features from CNN backbone
    try
        backbonePath = fullfile(options.ModelsDir, 'grading', 'backbone_finetuned.mat');
        if ~isempty(options.GradingModels) && isfield(options.GradingModels, 'network')
            deepFeats = extractDeepFeatures('extract', enhancedImg, options.GradingModels);
        elseif isfile(backbonePath)
            backbone = load(backbonePath);
            deepFeats = extractDeepFeatures('extract', enhancedImg, backbone);
        else
            warning('DRPipeline:pipeline:noBackbone', ...
                'No trained backbone found. Using zero deep features.');
            deepFeats = zeros(1, 2048);
        end
    catch ME
        warning('DRPipeline:pipeline:deepFeatFailed', ...
            'Deep feature extraction failed: %s', ME.message);
        deepFeats = zeros(1, 2048);
    end

    % Fuse features
    try
        fusedFeats = fuseFeatures(clinicalFeats.vector, deepFeats);
        featureVec = fusedFeats.fusedMatrix;
    catch ME
        warning('DRPipeline:pipeline:fusionFailed', ...
            'Feature fusion failed: %s', ME.message);
        featureVec = [clinicalFeats.vector, deepFeats];
    end

    timings.featureExtraction = toc(stepTimer);
    if options.Verbose, fprintf('done (%.2fs)\n', timings.featureExtraction); end

    % =====================================================================
    % STEP 5: DR Grading
    % =====================================================================
    if options.Verbose
        fprintf('[DRScreening] %-30s', 'Classifying DR grade...');
    end
    stepTimer = tic;

    try
        % Load or use provided grading model
        multiclassPath = fullfile(options.ModelsDir, 'grading', 'dr_multiclass.mat');
        binaryPath = fullfile(options.ModelsDir, 'grading', 'dr_binary_referable.mat');

        grade = 0;
        rawProbs = [1, 0, 0, 0, 0];  % Default: No DR

        if ~isempty(options.GradingModels) && isfield(options.GradingModels, 'multiclass')
            [grade, rawProbs] = predict(options.GradingModels.multiclass.model, featureVec);
        elseif isfile(multiclassPath)
            mdl = load(multiclassPath);
            if isfield(mdl, 'model')
                [grade, rawProbs] = predict(mdl.model, featureVec);
            end
        else
            % Fallback: rule-based grading from lesion counts
            grade = ruleBasedGrading(segResult);
            rawProbs = zeros(1, 5);
            rawProbs(grade + 1) = 0.6;  % Low confidence for rule-based
        end

        if iscell(grade), grade = grade{1}; end
        if ischar(grade) || isstring(grade), grade = str2double(grade); end
        grade = round(max(0, min(4, grade)));

    catch ME
        warning('DRPipeline:pipeline:gradingFailed', ...
            'DR grading failed: %s. Using rule-based fallback.', ME.message);
        grade = ruleBasedGrading(segResult);
        rawProbs = zeros(1, 5);
        rawProbs(grade + 1) = 0.5;
    end

    timings.grading = toc(stepTimer);

    result.grade = grade;
    result.gradeName = gradeNames{grade + 1};
    result.isReferable = grade >= 2;
    result.rawProbabilities = rawProbs;

    if options.Verbose
        fprintf('%s (%.2fs)\n', result.gradeName, timings.grading);
    end

    % =====================================================================
    % STEP 6: Confidence Calibration
    % =====================================================================
    stepTimer = tic;

    try
        calibPath = fullfile(options.ModelsDir, 'grading', 'calibration_params.mat');
        if ~isempty(options.CalibParams)
            calibratedProbs = calibrateConfidence('apply', rawProbs, options.CalibParams);
        elseif isfile(calibPath)
            cp = load(calibPath);
            calibratedProbs = calibrateConfidence('apply', rawProbs, cp);
        else
            calibratedProbs = rawProbs;  % Use raw if no calibration available
        end
        result.confidence = max(calibratedProbs);
    catch
        result.confidence = max(rawProbs);
    end

    timings.calibration = toc(stepTimer);

    % =====================================================================
    % STEP 7: Explainability
    % =====================================================================
    if options.Verbose
        fprintf('[DRScreening] %-30s', 'Generating explanations...');
    end
    stepTimer = tic;

    % Grad-CAM
    try
        if ~isempty(options.GradingModels) && isfield(options.GradingModels, 'network')
            result.gradcam = computeGradCAM(enhancedImg, options.GradingModels.network, grade);
        elseif isfile(fullfile(options.ModelsDir, 'grading', 'backbone_finetuned.mat'))
            bb = load(fullfile(options.ModelsDir, 'grading', 'backbone_finetuned.mat'));
            if isfield(bb, 'network')
                result.gradcam = computeGradCAM(enhancedImg, bb.network, grade);
            else
                result.gradcam = generateSyntheticHeatmap(enhancedImg, segResult);
            end
        else
            result.gradcam = generateSyntheticHeatmap(enhancedImg, segResult);
        end
    catch ME
        warning('DRPipeline:pipeline:gradcamFailed', ...
            'Grad-CAM failed: %s. Using synthetic heatmap.', ME.message);
        result.gradcam = generateSyntheticHeatmap(enhancedImg, segResult);
    end

    % Lesion evidence mapping
    try
        result.evidence = mapLesionEvidence(segResult, grade);
    catch ME
        warning('DRPipeline:pipeline:evidenceFailed', ...
            'Evidence mapping failed: %s', ME.message);
        result.evidence = struct('criterion', 'N/A', 'evidence_text', ...
            sprintf('Grade %d assigned by classifier', grade));
    end

    timings.explainability = toc(stepTimer);
    if options.Verbose, fprintf('done (%.2fs)\n', timings.explainability); end

    % =====================================================================
    % STEP 8: Report Generation
    % =====================================================================
    result.reportPath = '';

    if options.GenerateReport
        if options.Verbose
            fprintf('[DRScreening] %-30s', 'Generating report...');
        end
        stepTimer = tic;

        try
            [~, imgName, ~] = fileparts(imagePath);
            reportFile = fullfile(options.OutputDir, [imgName, '_report.html']);

            if ~exist(options.OutputDir, 'dir')
                mkdir(options.OutputDir);
            end

            reportPath = generateReport(imagePath, enhancedImg, result.gradcam, ...
                result.evidence, grade, result.confidence, reportFile);
            result.reportPath = reportPath;
        catch ME
            warning('DRPipeline:pipeline:reportFailed', ...
                'Report generation failed: %s', ME.message);
        end

        timings.reportGeneration = toc(stepTimer);
        if options.Verbose, fprintf('done (%.2fs)\n', timings.reportGeneration); end
    end

    % =====================================================================
    % Finalize
    % =====================================================================
    timings.total = toc(totalTimer);
    result.processingTime = timings;

    if options.Verbose
        fprintf('\n[DRScreening] === COMPLETE ===\n');
        fprintf('  Grade       : %d — %s\n', grade, result.gradeName);
        fprintf('  Confidence  : %.1f%%\n', result.confidence * 100);
        fprintf('  Referable   : %s\n', string(result.isReferable));
        fprintf('  Total time  : %.1f sec\n', timings.total);
        if ~isempty(result.reportPath)
            fprintf('  Report      : %s\n', result.reportPath);
        end
        fprintf('\n');
    end
end

% =========================================================================
% Helper Functions
% =========================================================================

function grade = ruleBasedGrading(segResult)
%RULEBASEDGRADING Fallback rule-based DR grading from lesion counts.
    grade = 0;  % Default: No DR

    % Check for microaneurysms
    maCount = 0;
    if isfield(segResult, 'microaneurysms') && isfield(segResult.microaneurysms, 'count')
        maCount = segResult.microaneurysms.count;
    end

    % Check for hemorrhages
    heCount = 0;
    if isfield(segResult, 'hemorrhages') && isfield(segResult.hemorrhages, 'count')
        heCount = segResult.hemorrhages.count;
    end

    % Check for exudates
    exPresent = false;
    if isfield(segResult, 'exudates') && isfield(segResult.exudates, 'totalArea')
        exPresent = segResult.exudates.totalArea > 0;
    end

    % Check for neovascularization
    nvProb = 0;
    if isfield(segResult, 'neovascularization') && isfield(segResult.neovascularization, 'nvProbability')
        nvProb = segResult.neovascularization.nvProbability;
    end

    % Apply ICDR rules
    if nvProb > 0.5
        grade = 4;  % PDR
    elseif heCount > 20
        grade = 3;  % Severe NPDR
    elseif (maCount > 0 && heCount > 0) || exPresent
        grade = 2;  % Moderate NPDR
    elseif maCount > 0
        grade = 1;  % Mild NPDR
    end
end

function heatmap = generateSyntheticHeatmap(img, segResult)
%GENERATESYNTHETICHEMAP Create a heatmap from segmentation results when
%   Grad-CAM is unavailable (no trained network).
    [h, w, ~] = size(img);
    heatmap = zeros(h, w);

    % Overlay lesion regions as hot zones
    if isfield(segResult, 'microaneurysms') && isfield(segResult.microaneurysms, 'binaryMask')
        mask = segResult.microaneurysms.binaryMask;
        if isequal(size(mask), [h, w])
            heatmap = heatmap + 0.5 * double(mask);
        end
    end

    if isfield(segResult, 'hemorrhages') && isfield(segResult.hemorrhages, 'binaryMask')
        mask = segResult.hemorrhages.binaryMask;
        if isequal(size(mask), [h, w])
            heatmap = heatmap + 0.7 * double(mask);
        end
    end

    if isfield(segResult, 'exudates') && isfield(segResult.exudates, 'hardExudateMask')
        mask = segResult.exudates.hardExudateMask;
        if isequal(size(mask), [h, w])
            heatmap = heatmap + 0.6 * double(mask);
        end
    end

    % Gaussian smoothing to create heatmap-like appearance
    if any(heatmap(:) > 0)
        heatmap = imgaussfilt(heatmap, max(h, w) / 50);
    end

    % Normalize to [0, 1]
    maxVal = max(heatmap(:));
    if maxVal > 0
        heatmap = heatmap / maxVal;
    end
end

function segResult = createEmptySegResult()
%CREATEEMPTYSEGRESULT Create an empty segmentation result struct.
    segResult = struct();
    segResult.opticDisc = struct('center', [0, 0], 'radius', 0, 'mask', [], 'confidence', 0);
    segResult.fovea = struct('center', [0, 0], 'confidence', 0);
    segResult.vessels = struct('binaryMask', [], 'vesselDensity', 0);
    segResult.vesselMask = [];
    segResult.microaneurysms = struct('centroids', [], 'count', 0, 'binaryMask', []);
    segResult.exudates = struct('hardExudateMask', [], 'softExudateMask', [], 'totalArea', 0);
    segResult.hemorrhages = struct('binaryMask', [], 'count', 0, 'types', {});
    segResult.neovascularization = struct('nvProbability', 0, 'nvdFlag', false, 'nveRegions', []);
    segResult.processingTime = struct();
end
