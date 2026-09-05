function [decision, qualityResult, enhancedImg] = qualityGate(img, model, options)
%QUALITYGATE Assess fundus image quality and apply enhancement if needed.
%   [DECISION, RESULT, ENHANCED] = QUALITYGATE(IMG) evaluates the quality
%   of fundus image IMG and returns:
%     DECISION    - 'accept', 'enhanced', or 'reject'
%     RESULT      - struct with quality features, scores, and decision info
%     ENHANCED    - the enhanced image (if borderline) or original (if good)
%
%   The quality gate implements a three-tier decision:
%     1. Good quality (score ≥ 0.7)     → Accept as-is
%     2. Borderline (0.4 ≤ score < 0.7) → Enhance and recheck
%     3. Poor quality (score < 0.4)     → Reject with feedback
%
%   [DECISION, RESULT, ENHANCED] = QUALITYGATE(IMG, MODEL) uses a
%   pre-trained quality classifier MODEL. If omitted, uses heuristic rules.
%
%   Example:
%       img = imread('fundus.jpg');
%       [decision, result, enhanced] = qualityGate(img);
%       if strcmp(decision, 'reject')
%           feedback = generateRecaptureFeedback(result);
%           fprintf('Rejected: %s\n', feedback.reason_text_en);
%       end
%
%   See also: EXTRACTQUALITYFEATURES, CLASSIFYQUALITY, ENHANCEFUNDUSIMAGE,
%             GENERATERECAPTUREFEEDBACK

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Quality Assessment Module
% -------------------------------------------------------------------------

    arguments
        img (:,:,:) uint8
        model = []  % Pre-trained classifier (optional)
        options.AcceptThreshold (1,1) double = 0.7
        options.BorderlineThreshold (1,1) double = 0.4
        options.Verbose (1,1) logical = true
    end

    if size(img, 3) ~= 3
        error('DRPipeline:quality:notRGB', ...
            'Input must be an RGB image. Got %d channels.', size(img, 3));
    end

    % Step 1: Extract quality features
    features = extractQualityFeatures(img);
    qualityResult.features = features;
    qualityResult.featureVector = features.vector;

    % Step 2: Compute quality score
    if ~isempty(model) && isstruct(model) && isfield(model, 'classifier')
        % Use trained classifier
        [label, score] = predict(model.classifier, features.vector);
        qualityScore = score(2);  % Probability of "adequate" class
        qualityResult.method = 'trained_classifier';
    else
        % Heuristic scoring (weighted combination of features)
        weights = [0.30, 0.15, 0.10, 0.20, 0.10, 0.15];
        % focus, luminance_mean, luminance_std, fov, entropy, contrast

        % Penalize extreme luminance (too dark or too bright)
        lumScore = 1 - 2 * abs(features.luminanceMean - 0.45);
        lumScore = max(0, min(1, lumScore));

        % Penalize low focus
        focusOK = min(1, features.focusScore / 0.5);

        % Penalize small FOV
        fovOK = min(1, features.fovCoverage / 0.5);

        % Penalize low entropy
        entOK = min(1, features.histEntropy / 0.7);

        % Penalize low contrast
        contOK = min(1, features.contrastScore / 0.5);

        % Penalize uneven illumination (high std)
        uniformOK = 1 - min(1, features.luminanceStd / 0.5);

        componentScores = [focusOK, lumScore, uniformOK, fovOK, entOK, contOK];
        qualityScore = sum(weights .* componentScores);
        qualityResult.method = 'heuristic';
        qualityResult.componentScores = componentScores;
    end

    qualityResult.qualityScore = qualityScore;

    % Step 3: Three-tier decision
    if qualityScore >= options.AcceptThreshold
        % Good quality - accept as-is
        decision = 'accept';
        enhancedImg = img;
        qualityResult.decision = 'accept';
        qualityResult.reason = 'Image quality is adequate for analysis.';

        if options.Verbose
            fprintf('[QualityGate] ACCEPT (score=%.3f)\n', qualityScore);
        end

    elseif qualityScore >= options.BorderlineThreshold
        % Borderline - enhance and recheck
        if options.Verbose
            fprintf('[QualityGate] BORDERLINE (score=%.3f) — enhancing...\n', qualityScore);
        end

        enhancedImg = enhanceFundusImage(img);

        % Recheck quality after enhancement
        featuresPost = extractQualityFeatures(enhancedImg);

        if ~isempty(model) && isstruct(model) && isfield(model, 'classifier')
            [~, scorePost] = predict(model.classifier, featuresPost.vector);
            qualityScorePost = scorePost(2);
        else
            lumScorePost = 1 - 2 * abs(featuresPost.luminanceMean - 0.45);
            lumScorePost = max(0, min(1, lumScorePost));
            focusPost = min(1, featuresPost.focusScore / 0.5);
            fovPost = min(1, featuresPost.fovCoverage / 0.5);
            entPost = min(1, featuresPost.histEntropy / 0.7);
            contPost = min(1, featuresPost.contrastScore / 0.5);
            uniformPost = 1 - min(1, featuresPost.luminanceStd / 0.5);
            compPost = [focusPost, lumScorePost, uniformPost, fovPost, entPost, contPost];
            weights = [0.30, 0.15, 0.10, 0.20, 0.10, 0.15];
            qualityScorePost = sum(weights .* compPost);
        end

        qualityResult.postEnhancementScore = qualityScorePost;
        qualityResult.featuresPost = featuresPost;

        if qualityScorePost >= options.BorderlineThreshold
            decision = 'enhanced';
            qualityResult.decision = 'enhanced';
            qualityResult.reason = 'Image enhanced to meet quality threshold.';
            if options.Verbose
                fprintf('[QualityGate] ACCEPT after enhancement (score=%.3f → %.3f)\n', ...
                    qualityScore, qualityScorePost);
            end
        else
            decision = 'reject';
            enhancedImg = img;
            qualityResult.decision = 'reject';
            qualityResult.reason = 'Image quality inadequate even after enhancement.';
            if options.Verbose
                fprintf('[QualityGate] REJECT (post-enhancement score=%.3f)\n', qualityScorePost);
            end
        end

    else
        % Poor quality - reject immediately
        decision = 'reject';
        enhancedImg = img;
        qualityResult.decision = 'reject';
        qualityResult.reason = 'Image quality too poor for reliable analysis.';

        % Identify specific failure reasons for feedback
        qualityResult.failureReasons = identifyFailureReasons(features);

        if options.Verbose
            fprintf('[QualityGate] REJECT (score=%.3f)\n', qualityScore);
        end
    end
end

function reasons = identifyFailureReasons(features)
%IDENTIFYFAILUREREASONS Determine why an image failed quality assessment.
    reasons = {};

    if features.focusScore < 0.3
        reasons{end+1} = 'blurry';
    end
    if features.luminanceMean < 0.2
        reasons{end+1} = 'too_dark';
    end
    if features.luminanceMean > 0.8
        reasons{end+1} = 'too_bright';
    end
    if features.fovCoverage < 0.3
        reasons{end+1} = 'small_fov';
    end
    if features.contrastScore < 0.2
        reasons{end+1} = 'low_contrast';
    end
    if features.luminanceStd > 0.8
        reasons{end+1} = 'uneven_illumination';
    end

    if isempty(reasons)
        reasons{end+1} = 'general_poor_quality';
    end
end
