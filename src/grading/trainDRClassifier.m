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
    
    trainIdx = splits.train;
    valIdx = splits.val;
    
    XTrain = fusedFeatures(trainIdx, :);
    YTrainMulticlass = labels(trainIdx);
    
    XVal = fusedFeatures(valIdx, :);
    YValMulticlass = labels(valIdx);
    
    %% Multiclass Model (5-class)
    fprintf('Training Multiclass Model...\n');
    tMulti = tic;
    tMultiOpts = templateSVM('Standardize', true);
    
    if options.optimizeHyperparameters
        multiModel = fitcecoc(XTrain, YTrainMulticlass, 'Learners', tMultiOpts, ...
            'OptimizeHyperparameters', 'auto', ...
            'HyperparameterOptimizationOptions', struct('AcquisitionFunctionName', 'expected-improvement-plus', 'ShowPlots', false));
    else
        multiModel = fitcecoc(XTrain, YTrainMulticlass, 'Learners', tMultiOpts, 'Coding', 'onevsall');
    end
    
    YPredMulti = predict(multiModel, XVal);
    
    output.multiclass.model = multiModel;
    output.multiclass.valMetrics.accuracy = sum(YPredMulti == YValMulticlass) / numel(YValMulticlass);
    output.multiclass.valMetrics.confusionMatrix = confusionmat(YValMulticlass, YPredMulti);
    
    fprintf('Multiclass Training Done (%.2fs), Val Acc: %.2f%%\n', toc(tMulti), output.multiclass.valMetrics.accuracy * 100);

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
    % scoreBin(:,2) is the score for class 1 (Referable)
    
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
    
    % If unable to meet specificity >= 0.85 condition, just pick closest point to (0,1)
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
    
    outDir = fullfile('d:\sih_project', 'models', 'grading');
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
    
    % Optional: Plots & Confusion matrices can be saved here to results/grading
    resDir = fullfile('d:\sih_project', 'results', 'grading');
    if ~exist(resDir, 'dir')
        mkdir(resDir);
    end
    
    fig = figure('Visible', 'off');
    confusionchart(YValMulticlass, YPredMulti);
    title('Validation Confusion Matrix - Multiclass');
    saveas(fig, fullfile(resDir, 'val_confusion_multiclass.png'));
    close(fig);

end
