function metrics = computeMetrics(groundTruth, predictions, probabilities)
%COMPUTEMETRICS Compute classification metrics from ground truth and predictions.
%
%   METRICS = computeMetrics(GROUNDTRUTH, PREDICTIONS) calculates evaluation
%   metrics like sensitivity, specificity, precision, F1, accuracy, and confusion
%   matrix based on true labels and predicted labels.
%
%   METRICS = computeMetrics(GROUNDTRUTH, PREDICTIONS, PROBABILITIES) also
%   calculates the Area Under the ROC Curve (AUC).
%
%   Inputs:
%       groundTruth   - Nx1 numeric array of true labels.
%       predictions   - Nx1 numeric array of predicted labels.
%       probabilities - (Optional) Nx1 numeric array of positive class probabilities 
%                       or NxC array for multi-class.
%
%   Outputs:
%       metrics - Struct containing sensitivity, specificity, precision, F1, 
%                 accuracy, AUC, quadraticWeightedKappa, and confusionMatrix.
%
%   Example:
%       trueLabels = [0; 1; 1; 0; 1];
%       predLabels = [0; 1; 0; 0; 1];
%       probs = [0.1; 0.9; 0.4; 0.2; 0.8];
%       metrics = computeMetrics(trueLabels, predLabels, probs);
%
%   See also CONFUSIONMAT, PERFCURVE.

    arguments
        groundTruth (:,1) double
        predictions (:,1) double
        probabilities double = []
    end

    if length(groundTruth) ~= length(predictions)
        error('DRPipeline:utils:SizeMismatch', 'Ground truth and predictions must have the same length.');
    end

    if ~isempty(probabilities) && size(probabilities, 1) ~= length(groundTruth)
        error('DRPipeline:utils:SizeMismatch', 'Probabilities must have the same number of rows as ground truth.');
    end

    % Confusion Matrix
    cm = confusionmat(groundTruth, predictions);
    metrics.confusionMatrix = cm;
    
    % Accuracy
    metrics.accuracy = sum(groundTruth == predictions) / length(groundTruth);
    
    numClasses = size(cm, 1);
    
    if numClasses == 2
        % Binary classification metrics
        TP = cm(2,2);
        TN = cm(1,1);
        FP = cm(1,2);
        FN = cm(2,1);
        
        metrics.sensitivity = TP / (TP + FN + eps);
        metrics.specificity = TN / (TN + FP + eps);
        metrics.precision = TP / (TP + FP + eps);
        metrics.F1 = 2 * (metrics.precision * metrics.sensitivity) / (metrics.precision + metrics.sensitivity + eps);
    else
        % Multi-class metrics (macro-averaged)
        sens = zeros(numClasses, 1);
        spec = zeros(numClasses, 1);
        prec = zeros(numClasses, 1);
        f1 = zeros(numClasses, 1);
        
        for i = 1:numClasses
            TP = cm(i,i);
            FP = sum(cm(:,i)) - TP;
            FN = sum(cm(i,:)) - TP;
            TN = sum(cm(:)) - (TP + FP + FN);
            
            sens(i) = TP / (TP + FN + eps);
            spec(i) = TN / (TN + FP + eps);
            prec(i) = TP / (TP + FP + eps);
            f1(i) = 2 * (prec(i) * sens(i)) / (prec(i) + sens(i) + eps);
        end
        
        metrics.sensitivity = mean(sens);
        metrics.specificity = mean(spec);
        metrics.precision = mean(prec);
        metrics.F1 = mean(f1);
    end

    % AUC
    metrics.AUC = NaN;
    if ~isempty(probabilities)
        try
            if numClasses == 2 && size(probabilities, 2) == 1
                [~,~,~,auc] = perfcurve(groundTruth, probabilities, 1);
                metrics.AUC = auc;
            elseif numClasses > 2 && size(probabilities, 2) == numClasses
                % Simple macro-average one-vs-rest AUC
                aucs = zeros(numClasses, 1);
                classes = unique(groundTruth);
                for i = 1:length(classes)
                    [~,~,~,auc_i] = perfcurve(groundTruth, probabilities(:, i), classes(i));
                    aucs(i) = auc_i;
                end
                metrics.AUC = mean(aucs);
            end
        catch ME
            warning('DRPipeline:utils:AUCError', 'Could not compute AUC: %s', ME.message);
        end
    end
    
    % Quadratic Weighted Kappa
    metrics.quadraticWeightedKappa = NaN;
    if numClasses > 1
        % Calculate QWK
        n = sum(cm(:));
        w = zeros(numClasses, numClasses);
        for i = 1:numClasses
            for j = 1:numClasses
                w(i,j) = ((i - j)^2) / ((numClasses - 1)^2);
            end
        end
        expected = (sum(cm, 2) * sum(cm, 1)) / n;
        num = sum(sum(w .* cm));
        den = sum(sum(w .* expected));
        metrics.quadraticWeightedKappa = 1 - (num / den);
    end
end
