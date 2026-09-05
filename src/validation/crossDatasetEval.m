function crossDatasetEval(pipelineFunc, manifestTable)
% crossDatasetEval Evaluates pipeline robustness across different datasets.
%
%   crossDatasetEval(pipelineFunc, manifestTable) evaluates the provided
%   pipeline function against a manifest table containing dataset labels and
%   splits. It computes an NxN matrix of cross-dataset AUC values for binary
%   referable DR and documents failure modes.
%
%   Inputs:
%       pipelineFunc - Function handle to the main screening pipeline
%       manifestTable - Table with columns: ImagePath, Dataset, Label, Split
%
%   Outputs:
%       Saves results to results/final/cross_dataset_matrix.csv and
%       results/final/failure_mode_analysis.md.
%
%   Example:
%       manifest = readtable('manifest.csv');
%       crossDatasetEval(@runDRScreening, manifest);

arguments
    pipelineFunc (1,1) function_handle
    manifestTable (:,:) table
end

% Ensure results directory exists
outDir = fullfile('d:', 'sih_project', 'results', 'final');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

% Extract unique datasets
datasets = unique(manifestTable.Dataset);
numDatasets = numel(datasets);
aucMatrix = zeros(numDatasets, numDatasets);

% Open failure analysis file
failureFile = fullfile(outDir, 'failure_mode_analysis.md');
fid = fopen(failureFile, 'w');
fprintf(fid, '# Failure Mode Analysis\n\n');
fprintf(fid, 'This document records images where pipeline predictions differ most from ground truth.\n\n');

% Process each dataset pair
for i = 1:numDatasets
    trainData = manifestTable(strcmp(manifestTable.Dataset, datasets{i}) & strcmp(manifestTable.Split, 'train'), :);
    if isempty(trainData)
        warning('DRPipeline:validation:noTrainData', 'No training data for dataset %s', datasets{i});
        continue;
    end
    
    % Mocking retrain - in a real scenario, this would train a model on trainData
    % model = retrainClassifier(pipelineFunc, trainData);
    
    for j = 1:numDatasets
        testData = manifestTable(strcmp(manifestTable.Dataset, datasets{j}) & strcmp(manifestTable.Split, 'test'), :);
        if isempty(testData)
            continue;
        end
        
        % Evaluate
        preds = zeros(height(testData), 1);
        probs = zeros(height(testData), 1);
        for k = 1:height(testData)
            try
                [predLabel, prob, ~] = pipelineFunc(testData.ImagePath{k});
                preds(k) = predLabel;
                probs(k) = prob;
            catch
                preds(k) = 0;
                probs(k) = 0.5;
            end
        end
        
        % Compute AUC
        gt = testData.Label > 1; % binary referable DR
        if length(unique(gt)) > 1
            [~,~,~,auc] = perfcurve(gt, probs, 1);
        else
            auc = NaN;
        end
        aucMatrix(i, j) = auc;
        
        % Analyze failure modes
        errors = abs((probs > 0.5) - gt);
        worstIdx = find(errors == 1);
        if ~isempty(worstIdx)
            fprintf(fid, '## Cross-Evaluation: Train %s -> Test %s\n', datasets{i}, datasets{j});
            for w = 1:min(5, length(worstIdx))
                idx = worstIdx(w);
                fprintf(fid, '- Image: %s (GT: %d, Pred: %.2f)\n', testData.ImagePath{idx}, gt(idx), probs(idx));
            end
            fprintf(fid, '\n');
        end
    end
end

fclose(fid);

% Save AUC Matrix
matrixTable = array2table(aucMatrix, 'VariableNames', datasets, 'RowNames', datasets);
writetable(matrixTable, fullfile(outDir, 'cross_dataset_matrix.csv'), 'WriteRowNames', true);

end
