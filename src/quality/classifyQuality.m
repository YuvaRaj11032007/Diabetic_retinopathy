function [label, scores] = classifyQuality(featureVector, model)
%CLASSIFYQUALITY Classify fundus image quality as adequate or inadequate.
%   [LABEL, SCORES] = CLASSIFYQUALITY(FEATUREVECTOR, MODEL) classifies the
%   quality of a fundus image using a pre-trained classifier MODEL and the
%   6-element quality feature vector FEATUREVECTOR.
%
%   LABEL   - 'adequate' or 'inadequate'
%   SCORES  - [P(inadequate), P(adequate)] posterior probabilities
%
%   Static method CLASSIFYQUALITY.TRAIN(features, labels) trains a quality
%   classifier and saves it.
%
%   Example:
%       features = extractQualityFeatures(img);
%       model = load('models/quality/quality_classifier.mat');
%       [label, scores] = classifyQuality(features.vector, model);
%
%   See also: EXTRACTQUALITYFEATURES, QUALITYGATE

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Quality Assessment Module
% -------------------------------------------------------------------------

    arguments
        featureVector (1,6) double
        model struct
    end

    if ~isfield(model, 'classifier')
        error('DRPipeline:quality:invalidModel', ...
            'Model struct must contain a "classifier" field with a trained classifier.');
    end

    [label, scores] = predict(model.classifier, featureVector);

    if iscell(label)
        label = label{1};
    end
    if isstring(label)
        label = char(label);
    end
end

function model = trainQualityClassifier(features, labels, outputPath)
%TRAINQUALITYCLASSIFIER Train the quality classification model.
%   MODEL = TRAINQUALITYCLASSIFIER(FEATURES, LABELS) trains an SVM-based
%   quality classifier on the given feature matrix and label vector.
%
%   MODEL = TRAINQUALITYCLASSIFIER(FEATURES, LABELS, OUTPUTPATH) also
%   saves the trained model to OUTPUTPATH.
%
%   Inputs:
%     FEATURES  - N×6 matrix of quality features
%     LABELS    - N×1 categorical or cell array: 'adequate' / 'inadequate'
%     OUTPUTPATH- (optional) file path to save the model
%
%   Example:
%       features = rand(500, 6);  % Replace with real features
%       labels = repmat({'adequate'}, 500, 1);
%       model = trainQualityClassifier(features, labels, 'models/quality/quality_classifier.mat');

    arguments
        features (:,6) double
        labels (:,1)
        outputPath (1,:) char = ''
    end

    fprintf('[TrainQuality] Training quality classifier on %d samples...\n', size(features, 1));

    % Convert labels to categorical if needed
    if iscell(labels)
        labels = categorical(labels);
    end

    % Standardize features
    [featNorm, mu, sigma] = zscore(features);

    % Train an ensemble classifier (bagged trees — robust, fast)
    rng(42, 'twister');  % Reproducibility

    % Use 5-fold cross-validation to select hyperparameters
    classifier = fitcensemble(featNorm, labels, ...
        'Method', 'Bag', ...
        'NumLearningCycles', 100, ...
        'Learners', templateTree('MaxNumSplits', 20), ...
        'ClassNames', categorical({'inadequate', 'adequate'}));

    % Cross-validation performance estimate
    cvModel = crossval(classifier, 'KFold', 5);
    cvLoss = kfoldLoss(cvModel);
    fprintf('[TrainQuality] 5-fold CV accuracy: %.2f%%\n', (1 - cvLoss) * 100);

    % Package model
    model.classifier = classifier;
    model.featureMean = mu;
    model.featureStd = sigma;
    model.classNames = categories(labels);
    model.cvAccuracy = 1 - cvLoss;
    model.trainDate = datetime('now');
    model.nSamples = size(features, 1);

    % Save if output path provided
    if ~isempty(outputPath)
        outDir = fileparts(outputPath);
        if ~exist(outDir, 'dir')
            mkdir(outDir);
        end
        save(outputPath, '-struct', 'model');
        fprintf('[TrainQuality] Model saved to: %s\n', outputPath);
    end
end
