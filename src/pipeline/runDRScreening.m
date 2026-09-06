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
        if ~isempty(options.SegModels)
            segResult = runAllSegmentation(enhancedImg, options.SegModels);
        else
            segResult = runAllSegmentation(enhancedImg);
        end
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
        foveaLoc = [round(size(img, 2)/2), round(size(img, 1)/2)];
        if isfield(segResult, 'fovea') && isfield(segResult.fovea, 'center') && ~isempty(segResult.fovea.center) && numel(segResult.fovea.center) == 2
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
        % Load or use provided grading models
        multiclassPath = fullfile(options.ModelsDir, 'grading', 'dr_multiclass.mat');
        binaryPath = fullfile(options.ModelsDir, 'grading', 'dr_binary_referable.mat');

        grade = 0;
        rawProbs = [1, 0, 0, 0, 0];  % Default: No DR
        isReferable = false;

        % 1. Load Multiclass Model
        multiMdl = [];
        if ~isempty(options.GradingModels) && isfield(options.GradingModels, 'multiclass')
            if isfield(options.GradingModels.multiclass, 'model')
                multiMdl = options.GradingModels.multiclass.model;
            else
                multiMdl = options.GradingModels.multiclass;
            end
        elseif isfile(multiclassPath)
            mdl = load(multiclassPath);
            if isfield(mdl, 'model')
                multiMdl = mdl.model;
            elseif isfield(mdl, 'multiModelStruct') && isfield(mdl.multiModelStruct, 'model')
                multiMdl = mdl.multiModelStruct.model;
            elseif isa(mdl, 'classreg.learning.model.CompactFullClassificationModel') || isa(mdl, 'ClassificationECOC')
                multiMdl = mdl;
            end
        end

        % 2. Load Binary Referable Model
        binMdl = [];
        binThresh = 0.5;
        if ~isempty(options.GradingModels) && isfield(options.GradingModels, 'binary')
            if isfield(options.GradingModels.binary, 'model')
                binMdl = options.GradingModels.binary.model;
                if isfield(options.GradingModels.binary, 'optimalThreshold')
                    binThresh = options.GradingModels.binary.optimalThreshold;
                end
            else
                binMdl = options.GradingModels.binary;
            end
        elseif isfile(binaryPath)
            bData = load(binaryPath);
            if isfield(bData, 'model')
                binMdl = bData.model;
                if isfield(bData, 'optimalThreshold'), binThresh = bData.optimalThreshold; end
            elseif isfield(bData, 'binModelStruct') && isfield(bData.binModelStruct, 'model')
                binMdl = bData.binModelStruct.model;
                if isfield(bData.binModelStruct, 'optimalThreshold')
                    binThresh = bData.binModelStruct.optimalThreshold;
                end
            end
        end

        % 3. Multiclass Prediction with Dynamic Feature Dimension Adaptation
        if ~isempty(multiMdl)
            nExp = 0;
            if isprop(multiMdl, 'NumPredictors')
                nExp = multiMdl.NumPredictors;
            elseif isprop(multiMdl, 'PredictorNames')
                nExp = numel(multiMdl.PredictorNames);
            end

            if nExp == size(deepFeats, 2)
                inputFeats = deepFeats;
            elseif nExp == size(featureVec, 2)
                inputFeats = featureVec;
            elseif nExp == size(clinicalFeats.vector, 2)
                inputFeats = clinicalFeats.vector;
            elseif nExp > 0 && size(featureVec, 2) >= nExp
                inputFeats = featureVec(:, 1:nExp);
            elseif nExp > 0 && size(deepFeats, 2) >= nExp
                inputFeats = deepFeats(:, 1:nExp);
            else
                inputFeats = deepFeats;
            end

            [predGrade, scoreLoss] = predict(multiMdl, inputFeats);
            if iscell(predGrade), predGrade = predGrade{1}; end
            if ischar(predGrade) || isstring(predGrade), predGrade = str2double(predGrade); end
            if iscategorical(predGrade), predGrade = double(string(predGrade)); end
            grade = round(max(0, min(4, double(predGrade))));

            % Normalize loss/scores to proper class probabilities via softmax
            if ~isempty(scoreLoss) && numel(scoreLoss) == 5
                s = scoreLoss(:)';
                expS = exp(s - max(s));
                rawProbs = expS / sum(expS);
            else
                rawProbs = zeros(1, 5);
                rawProbs(grade + 1) = 0.88;
            end
        else
            % Fallback: rule-based grading from lesion counts
            grade = ruleBasedGrading(segResult);
            rawProbs = zeros(1, 5);
            rawProbs(grade + 1) = 0.65;
        end

        % 4. Binary Referable Prediction
        isReferable = (grade >= 2);
        if ~isempty(binMdl)
            try
                nExpBin = 0;
                if isprop(binMdl, 'NumPredictors')
                    nExpBin = binMdl.NumPredictors;
                elseif isprop(binMdl, 'PredictorNames')
                    nExpBin = numel(binMdl.PredictorNames);
                end
                if nExpBin == size(deepFeats, 2)
                    bInput = deepFeats;
                elseif nExpBin == size(featureVec, 2)
                    bInput = featureVec;
                else
                    bInput = deepFeats;
                end
                [~, binScores] = predict(binMdl, bInput);
                if size(binScores, 2) >= 2
                    refScore = binScores(:, 2);
                    isReferable = (refScore >= binThresh) || (grade >= 2);
                end
            catch
            end
        end

        % 5. Clinical Safety Override (ICDR Lesion Verification)
        % The deep learning model is the primary diagnostic classifier.
        % A safety override is only applied when unequivocal, massive lesion clusters
        % are physically detected by segmentation that contradict a false-negative low grade.
        ruleGrade = ruleBasedGrading(segResult);

        if ~isempty(multiMdl)
            % Extract lesion counts for confirmed safety check
            exArea = 0; exCount = 0; heCount = 0; heArea = 0; nvProb = 0; maCount = 0;
            if isfield(segResult, 'exudates') && ~isempty(segResult.exudates)
                if isfield(segResult.exudates, 'totalArea'), try, exArea = segResult.exudates.totalArea; catch, end; end
                if isfield(segResult.exudates, 'count'), try, exCount = segResult.exudates.count; catch, end; end
            end
            if isfield(segResult, 'hemorrhages') && ~isempty(segResult.hemorrhages)
                if isfield(segResult.hemorrhages, 'count'), try, heCount = segResult.hemorrhages.count; catch, end; end
                if isfield(segResult.hemorrhages, 'totalArea'), try, heArea = segResult.hemorrhages.totalArea; catch, end; end
            end
            if isfield(segResult, 'neovascularization') && ~isempty(segResult.neovascularization)
                if isfield(segResult.neovascularization, 'nvProbability'), try, nvProb = segResult.neovascularization.nvProbability; catch, end; end
            end
            if isfield(segResult, 'microaneurysms') && ~isempty(segResult.microaneurysms)
                if isfield(segResult.microaneurysms, 'count'), try, maCount = segResult.microaneurysms.count; catch, end; end
            end

            hasSevereExudates = (exArea > 800 && exCount >= 8);
            hasSevereHemorrhages = (heCount >= 20 || heArea > 1000);
            hasDefinitePDR = (nvProb >= 0.7 && (maCount >= 3 || heCount >= 3));
            hasModerateExudates = (exArea > 350 && exCount >= 5);

            if grade < 3 && (hasSevereExudates || hasSevereHemorrhages)
                if options.Verbose
                    fprintf(' [Clinical Safety Alert: Massive lesion burden confirms Grade 3, upgrading from ML Grade %d]', grade);
                end
                grade = 3;
                rawProbs = zeros(1, 5); rawProbs(grade + 1) = 0.90;
                isReferable = true;
            elseif grade < 2 && hasModerateExudates
                if options.Verbose
                    fprintf(' [Clinical Safety Alert: Substantial exudate clusters confirm Grade 2, upgrading from ML Grade %d]', grade);
                end
                grade = 2;
                rawProbs = zeros(1, 5); rawProbs(grade + 1) = 0.85;
                isReferable = true;
            elseif grade < 4 && hasDefinitePDR
                if options.Verbose
                    fprintf(' [Clinical Safety Alert: Confirmed neovascular fronds indicate Grade 4, upgrading from ML Grade %d]', grade);
                end
                grade = 4;
                rawProbs = zeros(1, 5); rawProbs(grade + 1) = 0.90;
                isReferable = true;
            end
        else
            % Fallback when no ML model is available: use rule-based directly
            grade = ruleGrade;
            rawProbs = zeros(1, 5);
            rawProbs(grade + 1) = 0.70;
            isReferable = (grade >= 2);
        end

        if iscell(grade), grade = grade{1}; end
        if ischar(grade) || isstring(grade), grade = str2double(grade); end
        grade = round(max(0, min(4, grade)));

    catch ME
        warning('DRPipeline:pipeline:gradingFailed', ...
            'DR grading failed: %s. Using rule-based fallback.', ME.message);
        grade = ruleBasedGrading(segResult);
        rawProbs = zeros(1, 5);
        rawProbs(grade + 1) = 0.70;
        isReferable = (grade >= 2);
    end

    timings.grading = toc(stepTimer);

    result.grade = grade;
    result.gradeName = gradeNames{grade + 1};
    result.isReferable = isReferable;
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
%RULEBASEDGRADING Rule-based DR grading based on ICDR criteria from lesion segmentation.
    grade = 0;  % Default: No DR

    % 1. Microaneurysms
    maCount = 0;
    if isfield(segResult, 'microaneurysms') && ~isempty(segResult.microaneurysms) && isfield(segResult.microaneurysms, 'count')
        try, maCount = segResult.microaneurysms.count; catch, end
    elseif isfield(segResult, 'MACount')
        try, maCount = segResult.MACount; catch, end
    end

    % 2. Hemorrhages
    heCount = 0;
    heArea = 0;
    if isfield(segResult, 'hemorrhages') && ~isempty(segResult.hemorrhages)
        if isfield(segResult.hemorrhages, 'count'), try, heCount = segResult.hemorrhages.count; catch, end; end
        if isfield(segResult.hemorrhages, 'totalArea'), try, heArea = segResult.hemorrhages.totalArea; catch, end; end
    elseif isfield(segResult, 'HemorrhageCount')
        try, heCount = segResult.HemorrhageCount; catch, end
    end

    % 3. Exudates (Hard & Soft)
    exArea = 0;
    exCount = 0;
    softExCount = 0;
    if isfield(segResult, 'exudates') && ~isempty(segResult.exudates)
        if isfield(segResult.exudates, 'totalArea'), try, exArea = segResult.exudates.totalArea; catch, end; end
        if isfield(segResult.exudates, 'count'), try, exCount = segResult.exudates.count; catch, end; end
        if isfield(segResult.exudates, 'softExudateMask') && ~isempty(segResult.exudates.softExudateMask)
            try, softExCount = sum(segResult.exudates.softExudateMask(:) > 0); catch, end
        end
    elseif isfield(segResult, 'HardExudateArea')
        try, exArea = segResult.HardExudateArea; catch, end
    end

    % 4. Neovascularization
    nvProb = 0;
    if isfield(segResult, 'neovascularization') && ~isempty(segResult.neovascularization) && isfield(segResult.neovascularization, 'nvProbability')
        try, nvProb = segResult.neovascularization.nvProbability; catch, end
    elseif isfield(segResult, 'NVDProbability')
        try, nvProb = segResult.NVDProbability; catch, end
    end

    % ICDR Clinical Classification Logic:
    % Grade 4 (PDR): Definite neovascularization accompanied by diabetic microvascular lesions
    if nvProb >= 0.7 && (maCount >= 3 || heCount >= 3 || exArea > 100)
        grade = 4;
    % Grade 3 (Severe NPDR): Any of:
    %  - Severe hemorrhages count >= 20 (or large hemorrhage area > 1000 px)
    %  - Extensive hard exudate clusters (area > 800 px AND count >= 8)
    %  - Multiple cotton-wool spots (soft exudates > 200 px)
    elseif heCount >= 20 || heArea > 1000 || (exArea > 800 && exCount >= 8) || softExCount > 200
        grade = 3;
    % Grade 2 (Moderate NPDR):
    %  - Definite hard exudates (area > 150 px AND count >= 3) OR
    %  - Both microaneurysms and hemorrhages (maCount >= 3 AND heCount >= 2) OR
    %  - Multiple microaneurysms (>= 5) or definite hemorrhages (>= 3)
    elseif (exArea > 150 && exCount >= 3) || (maCount >= 3 && heCount >= 2) || heCount >= 3 || maCount >= 5
        grade = 2;
    % Grade 1 (Mild NPDR): Microaneurysms only (at least 2 MAs)
    elseif maCount >= 2
        grade = 1;
    else
        grade = 0;
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
    
    % Use scalar struct assignment to avoid 0x0 empty struct array from {}
    h = struct();
    h.binaryMask = [];
    h.count = 0;
    h.types = {};
    segResult.hemorrhages = h;
    
    segResult.neovascularization = struct('nvProbability', 0, 'nvdFlag', false, 'nveRegions', []);
    segResult.processingTime = struct();
end
