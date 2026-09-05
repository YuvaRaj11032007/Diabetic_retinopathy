function create_manifest()
%CREATE_MANIFEST Create master manifest for DR Screening Pipeline.
%   CREATE_MANIFEST() reads native labels from all available datasets (IDRiD,
%   APTOS 2019, EyePACS, Messidor-2, DIARETDB1) and unifies them into a
%   single master CSV file.
%
%   The output master_manifest.csv contains columns:
%   image_id, dataset, filepath, dr_grade, has_ma, has_ex, has_he, has_nv, split
%
%   Example:
%       create_manifest()

    try
        fprintf('Creating master manifest...\n');
        
        projectRoot = fullfile('d:', 'sih_project');
        rawDataDir = fullfile(projectRoot, 'data', 'raw');
        manifestDir = fullfile(projectRoot, 'data', 'manifests');
        
        if ~exist(manifestDir, 'dir')
            mkdir(manifestDir);
        end
        
        % Initialize empty table for the manifest
        varNames = {'image_id', 'dataset', 'filepath', 'dr_grade', 'has_ma', 'has_ex', 'has_he', 'has_nv', 'split'};
        varTypes = {'string', 'string', 'string', 'double', 'logical', 'logical', 'logical', 'logical', 'string'};
        manifest = table('Size', [0, length(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
        
        % Process APTOS 2019
        aptosLblPath = fullfile(rawDataDir, 'aptos2019', 'labels', 'train.csv');
        if exist(aptosLblPath, 'file')
            fprintf('Processing APTOS 2019...\n');
            aptosTbl = readtable(aptosLblPath, 'TextType', 'string');
            for i = 1:height(aptosTbl)
                imgId = aptosTbl.id_code(i);
                drGrade = aptosTbl.diagnosis(i);
                filepath = fullfile(rawDataDir, 'aptos2019', 'images', imgId + ".png");
                
                newRow = {imgId, "aptos2019", filepath, drGrade, NaN, NaN, NaN, NaN, ""};
                manifest = [manifest; newRow]; %#ok<AGROW>
            end
        end
        
        % Process EyePACS
        eyepacsLblPath = fullfile(rawDataDir, 'eyepacs', 'labels', 'trainLabels.csv');
        if exist(eyepacsLblPath, 'file')
            fprintf('Processing EyePACS...\n');
            eyepacsTbl = readtable(eyepacsLblPath, 'TextType', 'string');
            for i = 1:height(eyepacsTbl)
                imgId = eyepacsTbl.image(i);
                drGrade = eyepacsTbl.level(i);
                filepath = fullfile(rawDataDir, 'eyepacs', 'images', imgId + ".jpeg");
                
                newRow = {imgId, "eyepacs", filepath, drGrade, NaN, NaN, NaN, NaN, ""};
                manifest = [manifest; newRow]; %#ok<AGROW>
            end
        end
        
        % Save manifest
        manifestPath = fullfile(manifestDir, 'master_manifest.csv');
        writetable(manifest, manifestPath);
        fprintf('Manifest saved to %s (Total records: %d)\n', manifestPath, height(manifest));
        
    catch ME
        error('DRPipeline:data:createManifestFailed', 'Failed to create manifest: %s', ME.message);
    end
end
