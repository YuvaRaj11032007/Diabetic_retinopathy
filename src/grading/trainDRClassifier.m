function output = trainDRClassifier(fusedFeatures, labels, splits, options)
%TRAINDRCLASSIFIER Train DR severity classifiers (5-class and binary referable).
%
%   output = trainDRClassifier(fusedFeatures, labels, splits, options) trains
%   a 5-class multiclass model and a binary model (referable vs non-referable).
%
%   Inputs:
%       fusedFeatures - N-by-D feature matrix.
%       labels        - N-by-1 true severity labels (0 to 4).
%       splits        - Struct with fields train, val, test containing indices.
%       options       - Struct for optional parameters (e.g., optimize hyperparams).
%
%   Outputs:
%       output - Struct with trained models, validation metrics, and logs.
%
%   Example:
%       models = trainDRClassifier(features, labels, splits);

    arguments
        fusedFeatures (:,:) double {mustBeReal, mustBeNonmissing}
        labels (:,1) double {mustBeInteger, mustBeNonnegative, mustBeLessThanOrEqual(labels, 4)}
        splits struct
        options.optimizeHyperparameters (1,1) logical = false
    end
    
    output = struct();
    tTotal = tic;
    N = size(fusedFeatures, 1);
    
    % Resolve trainIdx and valIdx (handles string IDs, logical masks, or indices)
    trainIdx = [];
    valIdx   = [];
    
    if isfield(splits, 'train')
        sTrain = splits.train;
        sVal   = splits.val;
        
        if isstring(sTrain) || iscellstr(sTrain) || iscell(sTrain)
            % String IDs: map to rows in master manifest
            manifest = [];
            try
                manifest = readtable(fullfile('data', 'manifests', 'master_manifest_validated.csv'), 'TextType', 'string');
            catch
            end
            
            if ~isempty(manifest) && height(manifest) == N && ismember('image_id', manifest.Properties.VariableNames)
                allIds = string(manifest.image_id);
                trainIdx = ismember(allIds, string(sTrain));
                valIdx   = ismember(allIds, string(sVal));
            else
                % Default 80-20 partition
                rng(42);
                perm = randperm(N);
                nTr = round(0.8 * N);
                trainIdx = false(N, 1); trainIdx(perm(1:nTr)) = true;
                valIdx   = false(N, 1); valIdx(perm(nTr+1:end)) = true;
            end
        else
            trainIdx = sTrain;
            valIdx   = sVal;
        end
    else
        rng(42);
        perm = randperm(N);
        nTr = round(0.8 * N);
        trainIdx = false(N, 1); trainIdx(perm(1:nTr)) = true;
        valIdx   = false(N, 1); valIdx(perm(nTr+1:end)) = true;
    end
    
    XTrain = fusedFeatures(trainIdx, :);
    YTrainMulticlass = labels(trainIdx);
    
    XVal = fusedFeatures(valIdx, :);
    YValMulticlass = labels(valIdx);
    
    %% Toolbox Check
    if exist('templateSVM', 'file') ~= 2 || exist('fitcecoc', 'file') ~= 2
        error('DRPipeline:grading:MissingStatsToolbox', ...
            ['\n========================================================================\n' ...
             '  ACTION REQUIRED: Install Statistics and Machine Learning Toolbox\n' ...
             '------------------------------------------------------------------------\n' ...
             '  The final diagnostic classifiers (SVM & AdaBoost) require MATLAB''s\n' ...
             '  Statistics and Machine Learning Toolbox.\n\n' ...
             '  HOW TO INSTALL (Takes ~1 minute):\n' ...
             '  1. In the MATLAB Home tab ribbon, click "Add-Ons" -> "Get Add-Ons".\n' ...
             '  2. Search for: Statistics and Machine Learning Toolbox\n' ...
             '  3. Click "Install".\n' ...
             '========================================================================\n']);
    end

    %% SOTA Step 1: Ordinal Continuous Regressor (Ridge / SVR)
    % Treats DR grading as an ordinal progression scale (0 -> 1 -> 2 -> 3 -> 4)
    fprintf('Training Ordinal Continuous Regressor...\n');
    tReg = tic;
    
    if exist('fitrlinear', 'file') == 2
        regModel = fitrlinear(XTrain, double(YTrainMulticlass), ...
            'Learner', 'leastsquares', 'Regularization', 'ridge');
    else
        regModel = fitrsvm(XTrain, double(YTrainMulticlass), ...
            'KernelFunction', 'linear', 'Standardize', true);
    end
    
    valContinuous = predict(regModel, XVal);
    valContinuous = double(valContinuous(:));
    
    %% SOTA Step 2: OptimizedRounder (QWK Threshold Optimization)
    % Kaggle 1st-place APTOS methodology: optimize cutoffs to directly maximize Quadratic Weighted Kappa
    fprintf('Optimizing Decision Thresholds for Quadratic Weighted Kappa (QWK)...\n');
    [optThresholds, bestQWK] = optimizeThresholds(valContinuous, double(YValMulticlass));
    
    YPredOrdinal = discretizeContinuous(valContinuous, optThresholds);
    valAccOrdinal = sum(YPredOrdinal == YValMulticlass) / numel(YValMulticlass);
    valConfusionOrdinal = confusionmat(YValMulticlass, YPredOrdinal);
    
    fprintf('Ordinal Model Training Done (%.2fs):\n', toc(tReg));
    fprintf('  Validation QWK : %.4f (Industry Benchmark: > 0.85)\n', bestQWK);
    fprintf('  Validation Acc : %.2f%%\n', valAccOrdinal * 100);
    fprintf('  Optimized Cutoffs: [0 < %.2f <= 1 < %.2f <= 2 < %.2f <= 3 < %.2f <= 4]\n', ...
        optThresholds(1), optThresholds(2), optThresholds(3), optThresholds(4));

    %% SOTA Step 3: Cost-Sensitive Multiclass Model (Quadratic Distance Matrix)
    fprintf('Training Cost-Sensitive Multiclass Model (ECOC with Quadratic Distance Penalty)...\n');
    tMulti = tic;
    tMultiOpts = templateSVM('Standardize', true);
    
    % Quadratic cost matrix: misclassifying 4 as 0 costs 16, 4 as 3 costs 1
    [I_grid, J_grid] = meshgrid(0:4, 0:4);
    costMatrix = (I_grid - J_grid).^2;
    
    multiModel = fitcecoc(XTrain, YTrainMulticlass, 'Learners', tMultiOpts, ...
        'Coding', 'onevsall', 'Cost', costMatrix);
    
    YPredMulti = predict(multiModel, XVal);
    valAccMulti = sum(YPredMulti == YValMulticlass) / numel(YValMulticlass);
    valConfusionMulti = confusionmat(YValMulticlass, YPredMulti);
    
    fprintf('Cost-Sensitive ECOC Done (%.2fs), Val Acc: %.2f%%\n', toc(tMulti), valAccMulti * 100);

    % Package Multiclass Output
    output.multiclass.model = regModel;             % Primary continuous ordinal regressor
    output.multiclass.thresholds = optThresholds;   % QWK-optimized decision boundaries
    output.multiclass.classifier = multiModel;      % Cost-sensitive ECOC classifier
    output.multiclass.valMetrics.QWK = bestQWK;
    output.multiclass.valMetrics.accuracy = valAccOrdinal;
    output.multiclass.valMetrics.confusionMatrix = valConfusionOrdinal;
    output.multiclass.valMetrics.ecocAccuracy = valAccMulti;
    output.multiclass.valMetrics.ecocConfusionMatrix = valConfusionMulti;

    %% Binary Model (Referable)
    % Grade >= 2 is Referable (1), < 2 is Non-referable (0)
    YTrainBinary = double(YTrainMulticlass >= 2);
    YValBinary = double(YValMulticlass >= 2);
    
    fprintf('Training Binary Model (Referable DR)...\n');
    tBin = tic;
    
    % Use ensemble to handle imbalance
    binOpts = templateTree('MaxNumSplits', 20);
    
    if options.optimizeHyperparameters
        binModel = fitcensemble(XTrain, YTrainBinary, 'Method', 'AdaBoostM1', 'Learners', binOpts, ...
            'OptimizeHyperparameters', 'auto', ...
            'HyperparameterOptimizationOptions', struct('AcquisitionFunctionName', 'expected-improvement-plus', 'ShowPlots', false));
    else
        binModel = fitcensemble(XTrain, YTrainBinary, 'Method', 'AdaBoostM1', 'Learners', binOpts, 'NumLearningCycles', 100);
    end
    
    [~, scoreBin] = predict(binModel, XVal);
    
    % Find optimal threshold for sensitivity maximizing with specificity >= 0.85
    [Xroc, Yroc, Troc, AUC] = perfcurve(YValBinary, scoreBin(:,2), 1);
    
    optimalThreshold = 0.5; % Default
    bestSens = 0;
    for i = 1:length(Troc)
        spec = 1 - Xroc(i);
        sens = Yroc(i);
        if spec >= 0.85
            if sens > bestSens
                bestSens = sens;
                optimalThreshold = Troc(i);
            end
        end
    end
    
    % If unable to meet specificity >= 0.85 condition, pick closest point to (0,1)
    if bestSens == 0
        dist = Xroc.^2 + (1-Yroc).^2;
        [~, minIdx] = min(dist);
        optimalThreshold = Troc(minIdx);
    end
    
    YPredBin = scoreBin(:,2) >= optimalThreshold;
    
    TP = sum(YPredBin == 1 & YValBinary == 1);
    TN = sum(YPredBin == 0 & YValBinary == 0);
    FP = sum(YPredBin == 1 & YValBinary == 0);
    FN = sum(YPredBin == 0 & YValBinary == 1);
    
    output.binary.model = binModel;
    output.binary.optimalThreshold = optimalThreshold;
    output.binary.valMetrics.AUC = AUC;
    output.binary.valMetrics.Sensitivity = TP / (TP + FN + eps);
    output.binary.valMetrics.Specificity = TN / (TN + FP + eps);
    output.binary.valMetrics.Accuracy = (TP + TN) / (TP + TN + FP + FN);
    
    fprintf('Binary Training Done (%.2fs), Val AUC: %.3f, Opt Thresh: %.3f\n', toc(tBin), AUC, optimalThreshold);
    
    %% Save Models & Metadata
    output.trainingLog.totalTime = toc(tTotal);
    output.trainingLog.timestamp = datetime('now');
    output.trainingLog.options = options;
    
    projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
    if isempty(projectRoot) || ~exist(projectRoot, 'dir')
        projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    end
    outDir = fullfile(projectRoot, 'models', 'grading');
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end
    
    multiModelStruct = output.multiclass;
    binModelStruct = output.binary;
    
    try
        save(fullfile(outDir, 'dr_multiclass.mat'), 'multiModelStruct', '-v7.3');
        save(fullfile(outDir, 'dr_binary_referable.mat'), 'binModelStruct', '-v7.3');
    catch ME
        warning('DRPipeline:Grading:SaveFailed', 'Could not save models: %s', ME.message);
    end
    
    % Plots & Confusion matrices saved to results/grading
    resDir = fullfile(projectRoot, 'results', 'grading');
    if ~exist(resDir, 'dir')
        mkdir(resDir);
    end
    
    fig = figure('Visible', 'off');
    confusionchart(YValMulticlass, YPredOrdinal);
    title(sprintf('Validation Confusion Matrix - Ordinal Regressor (QWK: %.3f)', bestQWK));
    saveas(fig, fullfile(resDir, 'val_confusion_multiclass.png'));
    close(fig);

end

function [optThresholds, bestQWK] = optimizeThresholds(valScores, yTrue)
%OPTIMIZETHRESHOLDS Find 4 cutoffs that maximize Quadratic Weighted Kappa (QWK).
    initT = [0.5, 1.5, 2.5, 3.5];
    
    function loss = objFunc(t)
        st = sort(t);
        preds = discretizeContinuous(valScores, st);
        loss = -computeQWK(preds, yTrue);
    end

    opts = optimset('Display', 'off', 'MaxIter', 500, 'TolX', 1e-4);
    optT = fminsearch(@objFunc, initT, opts);
    optThresholds = sort(optT);
    bestQWK = computeQWK(discretizeContinuous(valScores, optThresholds), yTrue);
end

function preds = discretizeContinuous(scores, thresholds)
%DISCRETIZEONTINUOUS Discretize continuous scores into classes 0, 1, 2, 3, 4.
    preds = zeros(size(scores));
    preds(scores >= thresholds(1)) = 1;
    preds(scores >= thresholds(2)) = 2;
    preds(scores >= thresholds(3)) = 3;
    preds(scores >= thresholds(4)) = 4;
end

function qwk = computeQWK(yPred, yTrue)
%COMPUTEQWK Compute Quadratic Weighted Kappa between predictions and true labels.
    yPred = double(round(max(0, min(4, yPred(:)))));
    yTrue = double(round(max(0, min(4, yTrue(:)))));
    N = numel(yTrue);
    K = 5;
    
    % Confusion matrix O
    O = zeros(K, K);
    for i = 1:N
        O(yTrue(i) + 1, yPred(i) + 1) = O(yTrue(i) + 1, yPred(i) + 1) + 1;
    end
    
    % Expected matrix E
    histTrue = sum(O, 2);
    histPred = sum(O, 1);
    E = (histTrue * histPred) / max(1, N);
    
    % Weight matrix W (quadratic distance penalty)
    [I, J] = meshgrid(0:K-1, 0:K-1);
    W = ((I - J).^2) / ((K - 1)^2);
    
    num = sum(W .* O, 'all');
    den = sum(W .* E, 'all');
    if den == 0
        qwk = 1;
    else
        qwk = 1 - (num / den);
    end
end
