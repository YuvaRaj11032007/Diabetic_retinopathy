function splitsStruct = generate_splits()
%GENERATE_SPLITS Generate stratified train, validation, and test splits.
%   GENERATE_SPLITS() creates stratified 70/15/15 splits based on the
%   dr_grade column in master_manifest_validated.csv. It works in base
%   MATLAB without requiring the Statistics and Machine Learning Toolbox.
%   It saves the splits as splits.mat and updates master_manifest_validated.csv.
%
%   Example:
%       generate_splits()

    try
        fprintf('=== Generating Stratified Data Splits (70/15/15) ===\n');
        
        % Dynamic project root resolution
        projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
        if isempty(projectRoot) || ~exist(projectRoot, 'dir')
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
        end
        manifestDir = fullfile(projectRoot, 'data', 'manifests');
        
        manifestPath = fullfile(manifestDir, 'master_manifest_validated.csv');
        if ~exist(manifestPath, 'file')
            error('DRPipeline:data:missingValidatedManifest', ...
                'Validated manifest not found at %s. Run validate_data first.', manifestPath);
        end
        
        manifest = readtable(manifestPath, 'TextType', 'string');
        
        % Filter only valid images (if is_valid column exists)
        if ismember('is_valid', manifest.Properties.VariableNames)
            validIdx = find(manifest.is_valid);
        else
            validIdx = (1:height(manifest))';
        end
        
        if isempty(validIdx)
            error('DRPipeline:data:noValidImages', ...
                'No valid images found in %s. Check validate_data output.', manifestPath);
        end
        
        validManifest = manifest(validIdx, :);
        nValid = height(validManifest);
        
        % Initialize split assignments for valid items
        splitAssignment = strings(nValid, 1);
        
        % Reproducible random seed
        rng(42, 'twister');
        
        % Handle grades: group by unique grade (including NaN)
        grades = validManifest.dr_grade;
        nanMask = isnan(grades);
        uniqueGrades = unique(grades(~nanMask));
        
        trainCount = 0; valCount = 0; testCount = 0;
        
        % Stratified split by class
        for g = uniqueGrades'
            classIdx = find(grades == g);
            nClass = numel(classIdx);
            
            % Randomly permute class indices
            perm = classIdx(randperm(nClass));
            
            nTr = round(0.70 * nClass);
            nVal = round(0.15 * nClass);
            % Remaining go to test
            
            trIdx = perm(1:nTr);
            vIdx = perm(nTr+1 : min(nTr+nVal, nClass));
            teIdx = perm(min(nTr+nVal+1, nClass+1) : end);
            
            splitAssignment(trIdx) = "train";
            splitAssignment(vIdx) = "val";
            splitAssignment(teIdx) = "test";
        end
        
        % Handle any unannotated (NaN) images
        if any(nanMask)
            nanIdx = find(nanMask);
            nNan = numel(nanIdx);
            perm = nanIdx(randperm(nNan));
            nTr = round(0.70 * nNan);
            nVal = round(0.15 * nNan);
            
            splitAssignment(perm(1:nTr)) = "train";
            splitAssignment(perm(nTr+1 : min(nTr+nVal, nNan))) = "val";
            splitAssignment(perm(min(nTr+nVal+1, nNan+1) : end)) = "test";
        end
        
        % Update manifest table
        splitsStruct = struct('train', string([]), 'val', string([]), 'test', string([]));
        
        for i = 1:nValid
            origIdx = validIdx(i);
            assigned = splitAssignment(i);
            manifest.split(origIdx) = assigned;
            
            imgId = string(validManifest.image_id(i));
            if assigned == "train"
                splitsStruct.train = [splitsStruct.train; imgId];
            elseif assigned == "val"
                splitsStruct.val = [splitsStruct.val; imgId];
            elseif assigned == "test"
                splitsStruct.test = [splitsStruct.test; imgId];
            end
        end
        
        % Save splits struct
        splitsPath = fullfile(manifestDir, 'splits.mat');
        save(splitsPath, '-struct', 'splitsStruct');
        fprintf('  Splits structure saved to: %s\n', splitsPath);
        
        % Save updated manifest
        writetable(manifest, manifestPath);
        fprintf('  Updated manifest saved to: %s\n', manifestPath);
        
        % Print summary table
        fprintf('\n╔══════════════════════════════════════════════════════╗\n');
        fprintf('║                 SPLIT SUMMARY                        ║\n');
        fprintf('╠══════════════════════════════════════════════════════╣\n');
        fprintf('║  Train images    : %-6d (%5.1f%%)                   ║\n', ...
            numel(splitsStruct.train), numel(splitsStruct.train)/nValid*100);
        fprintf('║  Validation      : %-6d (%5.1f%%)                   ║\n', ...
            numel(splitsStruct.val), numel(splitsStruct.val)/nValid*100);
        fprintf('║  Test images     : %-6d (%5.1f%%)                   ║\n', ...
            numel(splitsStruct.test), numel(splitsStruct.test)/nValid*100);
        fprintf('║  Total valid     : %-6d                            ║\n', nValid);
        fprintf('╚══════════════════════════════════════════════════════╝\n\n');
        
    catch ME
        error('DRPipeline:data:splitGenerationFailed', 'Failed to generate splits: %s', ME.message);
    end
end
