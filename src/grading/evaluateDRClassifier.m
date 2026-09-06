function evalMetrics = evaluateDRClassifier(trainedModels, testFeatures, testLabels)
%EVALUATEDRCLASSIFIER Evaluate trained DR classifiers on test set.
%
%   evalMetrics = evaluateDRClassifier(trainedModels, testFeatures, testLabels)
%   computes evaluation metrics (AUC, sensitivity, specificity, kappa, etc.) 
%   for both binary and multiclass models and compares against benchmarks.
%
%   Inputs:
%       trainedModels - Struct with multiclass and binary models 
%                       (from trainDRClassifier).
%       testFeatures  - M-by-D feature matrix of test set.
%       testLabels    - M-by-1 true severity labels (0 to 4).
%
%   Outputs:
%       evalMetrics   - Struct containing computed metrics.
%
%   Example:
%       metrics = evaluateDRClassifier(models, testX, testY);

    arguments
        trainedModels struct {mustBeNonempty}
        testFeatures (:,:) double {mustBeReal, mustBeNonmissing}
        testLabels (:,1) double {mustBeInteger, mustBeNonnegative, mustBeLessThanOrEqual(testLabels, 4)}
    end
    
    evalMetrics = struct();
    
    projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
    if isempty(projectRoot) || ~exist(projectRoot, 'dir')
        projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    end
    resDir = fullfile(projectRoot, 'results', 'grading');
    if ~exist(resDir, 'dir')
        mkdir(resDir);
    end
    
    %% Binary Evaluation
    YTestBinary = double(testLabels >= 2);
    binModel = trainedModels.binary.model;
    optThresh = trainedModels.binary.optimalThreshold;
    
    [~, scoreBin] = predict(binModel, testFeatures);
    YPredBin = double(scoreBin(:,2) >= optThresh);
    
    [Xroc, Yroc, ~, AUC] = perfcurve(YTestBinary, scoreBin(:,2), 1);
    
    TP = sum(YPredBin == 1 & YTestBinary == 1);
    TN = sum(YPredBin == 0 & YTestBinary == 0);
    FP = sum(YPredBin == 1 & YTestBinary == 0);
    FN = sum(YPredBin == 0 & YTestBinary == 1);
    
    evalMetrics.binary.AUC = AUC;
    evalMetrics.binary.sensitivity = TP / (TP + FN + eps);
    evalMetrics.binary.specificity = TN / (TN + FP + eps);
    evalMetrics.binary.PPV = TP / (TP + FP + eps);
    evalMetrics.binary.NPV = TN / (TN + FN + eps);
    evalMetrics.binary.F1 = 2 * TP / (2*TP + FP + FN + eps);
    
    %% Multiclass Evaluation
    multiModel = trainedModels.multiclass.model;
    [YPredMulti, scoreMulti] = predict(multiModel, testFeatures);
    
    evalMetrics.multiclass.accuracy = sum(YPredMulti == testLabels) / numel(testLabels);
    evalMetrics.multiclass.confusionMatrix = confusionmat(testLabels, YPredMulti);
    
    % Per-class accuracy
    cm = evalMetrics.multiclass.confusionMatrix;
    for c = 1:size(cm,1)
        TPc = cm(c,c);
        FNc = sum(cm(c,:)) - TPc;
        FPc = sum(cm(:,c)) - TPc;
        TNc = sum(cm(:)) - (TPc + FNc + FPc);
        evalMetrics.multiclass.perClassAccuracy(c) = (TPc + TNc) / sum(cm(:));
    end
    
    % Quadratic Weighted Kappa
    % Calculate observed agreement
    N = numel(testLabels);
    p_obs = cm / N;
    
    % Expected agreement
    marg_row = sum(p_obs, 2);
    marg_col = sum(p_obs, 1);
    p_exp = marg_row * marg_col;
    
    % Weight matrix
    num_classes = size(cm,1);
    W = zeros(num_classes);
    for i = 1:num_classes
        for j = 1:num_classes
            W(i,j) = ((i - j)^2) / ((num_classes - 1)^2);
        end
    end
    
    kappa_num = sum(sum(W .* p_obs));
    kappa_den = sum(sum(W .* p_exp));
    evalMetrics.multiclass.kappa = 1 - (kappa_num / kappa_den);
    
    %% Plot ROC
    fig = figure('Visible', 'off');
    plot(Xroc, Yroc, 'LineWidth', 2);
    hold on;
    plot([0 1], [0 1], 'k--');
    xlabel('False Positive Rate (1 - Specificity)');
    ylabel('True Positive Rate (Sensitivity)');
    title(sprintf('Binary Referable DR ROC (AUC = %.3f)', AUC));
    grid on;
    saveas(fig, fullfile(resDir, 'roc_curves.png'));
    close(fig);
    
    %% Benchmark Comparison Table
    % Define benchmarks
    benchmarks = {
        'Abramoff 2016 (Messidor-2)', 0.968, 0.870, NaN, NaN;
        'Gulshan 2016 (EyePACS+Messidor-2)', 0.975, 0.934, NaN, NaN;
        'IDRiD Challenge 2018', NaN, NaN, 0.950, NaN; % Midpoint of 0.93-0.97
        'Kaggle EyePACS top', NaN, NaN, NaN, 0.850;
        'Our Pipeline (Binary)', evalMetrics.binary.sensitivity, evalMetrics.binary.specificity, evalMetrics.binary.AUC, NaN;
        'Our Pipeline (Multiclass)', NaN, NaN, NaN, evalMetrics.multiclass.kappa
    };
    
    benchTable = cell2table(benchmarks, 'VariableNames', {'Benchmark', 'Sensitivity', 'Specificity', 'AUC', 'Kappa'});
    writetable(benchTable, fullfile(resDir, 'benchmark_comparison.csv'));
    
    evalMetrics.benchmarkTable = benchTable;
    
    % Save full metrics
    try
        save(fullfile(resDir, 'test_metrics.mat'), 'evalMetrics');
    catch ME
        warning('DRPipeline:Grading:MetricsSaveFailed', 'Failed to save test metrics: %s', ME.message);
    end
    
end
