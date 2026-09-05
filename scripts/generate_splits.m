function generate_splits()
%GENERATE_SPLITS Generate train, validation, and test splits.
%   GENERATE_SPLITS() creates stratified 70/15/15 splits based on the
%   dr_grade column in master_manifest_validated.csv. It saves the splits as
%   a .mat file and updates the split column in the CSV.
%
%   Example:
%       generate_splits()

    try
        fprintf('Generating data splits...\n');
        
        projectRoot = fullfile('d:', 'sih_project');
        manifestDir = fullfile(projectRoot, 'data', 'manifests');
        
        manifestPath = fullfile(manifestDir, 'master_manifest_validated.csv');
        if ~exist(manifestPath, 'file')
            error('DRPipeline:data:missingValidatedManifest', 'Validated manifest not found. Run validate_data first.');
        end
        
        manifest = readtable(manifestPath, 'TextType', 'string');
        
        % Filter only valid images
        validIdx = find(manifest.is_valid);
        validManifest = manifest(validIdx, :);
        
        % Stratified split 70/15/15
        % Using cvpartition on the valid subset
        cv1 = cvpartition(validManifest.dr_grade, 'HoldOut', 0.3);
        idxTrain = training(cv1);
        idxRest = test(cv1);
        
        restLabels = validManifest.dr_grade(idxRest);
        cv2 = cvpartition(restLabels, 'HoldOut', 0.5);
        idxValRest = training(cv2);
        idxTestRest = test(cv2);
        
        % Map back to valid subset indices
        restIndices = find(idxRest);
        idxVal = false(size(idxTrain));
        idxVal(restIndices(idxValRest)) = true;
        
        idxTest = false(size(idxTrain));
        idxTest(restIndices(idxTestRest)) = true;
        
        % Update split column
        splitsStruct = struct('train', [], 'val', [], 'test', []);
        
        for i = 1:length(validIdx)
            origIdx = validIdx(i);
            imgId = validManifest.image_id(i);
            
            if idxTrain(i)
                manifest.split(origIdx) = "train";
                splitsStruct.train = [splitsStruct.train; imgId];
            elseif idxVal(i)
                manifest.split(origIdx) = "val";
                splitsStruct.val = [splitsStruct.val; imgId];
            elseif idxTest(i)
                manifest.split(origIdx) = "test";
                splitsStruct.test = [splitsStruct.test; imgId];
            end
        end
        
        % Save splits struct
        splitsPath = fullfile(manifestDir, 'splits.mat');
        save(splitsPath, '-struct', 'splitsStruct');
        fprintf('Splits structure saved to %s\n', splitsPath);
        
        % Save updated manifest
        writetable(manifest, manifestPath);
        fprintf('Updated manifest with splits saved to %s\n', manifestPath);
        
        % Print statistics
        fprintf('\nSplit Statistics:\n');
        fprintf('Train: %d\n', length(splitsStruct.train));
        fprintf('Val: %d\n', length(splitsStruct.val));
        fprintf('Test: %d\n', length(splitsStruct.test));
        
    catch ME
        error('DRPipeline:data:splitGenerationFailed', 'Failed to generate splits: %s', ME.message);
    end
end
