function manifest = create_manifest()
%CREATE_MANIFEST Create master manifest for DR Screening Pipeline.
%   CREATE_MANIFEST() scans all available datasets in data/raw/
%   (APTOS 2019, IDRiD, EyePACS, Messidor-2, DIARETDB1) and unifies them into
%   a single master CSV file at data/manifests/master_manifest.csv.
%
%   The output master_manifest.csv contains columns:
%   image_id, dataset, filepath, dr_grade, has_ma, has_ex, has_he, has_nv, split
%
%   Example:
%       create_manifest()

    try
        fprintf('=== Creating Master Manifest ===\n');
        
        % Dynamic project root resolution
        projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
        if isempty(projectRoot) || ~exist(projectRoot, 'dir')
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
        end
        fprintf('  Project Root: %s\n', projectRoot);
        
        rawDataDir = fullfile(projectRoot, 'data', 'raw');
        manifestDir = fullfile(projectRoot, 'data', 'manifests');
        
        if ~exist(rawDataDir, 'dir')
            mkdir(rawDataDir);
        end
        if ~exist(manifestDir, 'dir')
            mkdir(manifestDir);
        end
        
        % Initialize empty table for the manifest
        varNames = {'image_id', 'dataset', 'filepath', 'dr_grade', 'has_ma', 'has_ex', 'has_he', 'has_nv', 'split'};
        varTypes = {'string', 'string', 'string', 'double', 'double', 'double', 'double', 'double', 'string'};
        manifest = table('Size', [0, length(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
        
        % -----------------------------------------------------------------
        % 1. Process APTOS 2019 (supports aptos2019, aptos2019-blindness-detection, etc.)
        % -----------------------------------------------------------------
        aptosCandidateDirs = {
            fullfile(rawDataDir, 'aptos2019-blindness-detection')
            fullfile(rawDataDir, 'aptos2019')
        };
        aptosDir = '';
        for d = 1:numel(aptosCandidateDirs)
            if exist(aptosCandidateDirs{d}, 'dir')
                aptosDir = aptosCandidateDirs{d};
                break;
            end
        end
        % Also check any folder matching *aptos* in rawDataDir
        if isempty(aptosDir)
            dList = dir(fullfile(rawDataDir, '*aptos*'));
            for d = 1:numel(dList)
                if dList(d).isdir && ~startsWith(dList(d).name, '.')
                    aptosDir = fullfile(dList(d).folder, dList(d).name);
                    break;
                end
            end
        end
        
        if ~isempty(aptosDir)
            % Look for train.csv in aptos root, labels, or recursively
            possibleCsvs = {
                fullfile(aptosDir, 'train.csv')
                fullfile(aptosDir, 'labels', 'train.csv')
            };
            aptosCsvPath = '';
            for c = 1:numel(possibleCsvs)
                if exist(possibleCsvs{c}, 'file')
                    aptosCsvPath = possibleCsvs{c};
                    break;
                end
            end
            if isempty(aptosCsvPath)
                rCsv = dir(fullfile(aptosDir, '**', 'train.csv'));
                if ~isempty(rCsv)
                    aptosCsvPath = fullfile(rCsv(1).folder, rCsv(1).name);
                end
            end
            
            if ~isempty(aptosCsvPath)
                fprintf('  Found APTOS 2019 labels: %s\n', aptosCsvPath);
                aptosTbl = readtable(aptosCsvPath, 'TextType', 'string');
                
                % Check image directories
                imgDirs = {
                    fullfile(aptosDir, 'train_images')
                    fullfile(aptosDir, 'images')
                    aptosDir
                };
                
                foundCount = 0;
                for i = 1:height(aptosTbl)
                    imgId = string(aptosTbl.id_code(i));
                    drGrade = double(aptosTbl.diagnosis(i));
                    
                    imgPath = '';
                    for d = 1:numel(imgDirs)
                        for ext = [".png", ".jpg", ".jpeg"]
                            candidate = fullfile(imgDirs{d}, imgId + ext);
                            if exist(candidate, 'file')
                                imgPath = candidate;
                                break;
                            end
                        end
                        if ~isempty(imgPath), break; end
                    end
                    
                    if isempty(imgPath)
                        % Default expected path if file not yet downloaded
                        imgPath = fullfile(aptosDir, 'train_images', imgId + ".png");
                    else
                        foundCount = foundCount + 1;
                    end
                    
                    newRow = {imgId, "aptos2019", string(imgPath), drGrade, NaN, NaN, NaN, NaN, ""};
                    manifest = [manifest; newRow]; %#ok<AGROW>
                end
                fprintf('    Indexed %d APTOS images (%d exist on disk)\n', height(aptosTbl), foundCount);
            end
        end
        
        % -----------------------------------------------------------------
        % 2. Process IDRiD
        % -----------------------------------------------------------------
        idridDir = fullfile(rawDataDir, 'idrid');
        if exist(idridDir, 'dir')
            % Search for grading CSVs
            gradingFiles = [dir(fullfile(idridDir, '*Grading*.csv')); ...
                            dir(fullfile(idridDir, 'labels', '*Grading*.csv')); ...
                            dir(fullfile(idridDir, 'labels', '*.csv'))];
            if ~isempty(gradingFiles)
                idridCsvPath = fullfile(gradingFiles(1).folder, gradingFiles(1).name);
                fprintf('  Found IDRiD labels: %s\n', idridCsvPath);
                try
                    idridTbl = readtable(idridCsvPath, 'TextType', 'string');
                    % Common IDRiD column names: Image_name, Retinopathy_grade
                    imgCol = ''; gradeCol = '';
                    vars = string(idridTbl.Properties.VariableNames);
                    for v = vars
                        if contains(lower(v), 'image'), imgCol = v; end
                        if contains(lower(v), 'grade') || contains(lower(v), 'retinopathy'), gradeCol = v; end
                    end
                    
                    if ~isempty(imgCol) && ~isempty(gradeCol)
                        for i = 1:height(idridTbl)
                            imgId = string(idridTbl.(imgCol)(i));
                            drGrade = double(idridTbl.(gradeCol)(i));
                            imgPath = fullfile(idridDir, 'images', imgId + ".jpg");
                            newRow = {imgId, "idrid", string(imgPath), drGrade, NaN, NaN, NaN, NaN, ""};
                            manifest = [manifest; newRow]; %#ok<AGROW>
                        end
                        fprintf('    Indexed %d IDRiD images\n', height(idridTbl));
                    end
                catch err
                    warning('DRPipeline:manifest:idridParseError', 'Could not parse IDRiD labels: %s', err.message);
                end
            end
        end
        
        % -----------------------------------------------------------------
        % 3. Process EyePACS
        % -----------------------------------------------------------------
        eyepacsDir = fullfile(rawDataDir, 'eyepacs');
        if exist(eyepacsDir, 'dir')
            eyepacsLblPath = fullfile(eyepacsDir, 'labels', 'trainLabels.csv');
            if ~exist(eyepacsLblPath, 'file')
                eyepacsLblPath = fullfile(eyepacsDir, 'trainLabels.csv');
            end
            if exist(eyepacsLblPath, 'file')
                fprintf('  Found EyePACS labels: %s\n', eyepacsLblPath);
                eyepacsTbl = readtable(eyepacsLblPath, 'TextType', 'string');
                for i = 1:height(eyepacsTbl)
                    imgId = string(eyepacsTbl.image(i));
                    drGrade = double(eyepacsTbl.level(i));
                    filepath = fullfile(eyepacsDir, 'images', imgId + ".jpeg");
                    newRow = {imgId, "eyepacs", string(filepath), drGrade, NaN, NaN, NaN, NaN, ""};
                    manifest = [manifest; newRow]; %#ok<AGROW>
                end
                fprintf('    Indexed %d EyePACS images\n', height(eyepacsTbl));
            end
        end
        
        % -----------------------------------------------------------------
        % 4. Fallback: Direct scan of any images in data/raw/ if manifest is empty
        % -----------------------------------------------------------------
        if height(manifest) == 0
            fprintf('  Scanning data/raw for uncataloged images...\n');
            exts = {'*.jpg', '*.jpeg', '*.png', '*.tif', '*.tiff'};
            rawFiles = [];
            for e = 1:numel(exts)
                rawFiles = [rawFiles; dir(fullfile(rawDataDir, '**', exts{e}))]; %#ok<AGROW>
            end
            
            if ~isempty(rawFiles)
                fprintf('  Found %d images across data/raw subdirectories.\n', numel(rawFiles));
                for i = 1:numel(rawFiles)
                    [~, name, ~] = fileparts(rawFiles(i).name);
                    fpath = fullfile(rawFiles(i).folder, rawFiles(i).name);
                    % Guess dataset from folder
                    relPath = extractAfter(fpath, rawDataDir);
                    parts = split(string(relPath), filesep);
                    if numel(parts) >= 2 && strlength(parts(2)) > 0
                        dsName = parts(2);
                    else
                        dsName = "custom";
                    end
                    newRow = {string(name), dsName, string(fpath), NaN, NaN, NaN, NaN, NaN, ""};
                    manifest = [manifest; newRow]; %#ok<AGROW>
                end
            else
                fprintf('  Note: No images found in %s yet.\n', rawDataDir);
                fprintf('  Please place your dataset (e.g. aptos2019, idrid) inside data/raw/\n');
            end
        end
        
        % Save manifest
        manifestPath = fullfile(manifestDir, 'master_manifest.csv');
        writetable(manifest, manifestPath);
        fprintf('Master manifest saved successfully to:\n  %s\n  (Total records: %d)\n', manifestPath, height(manifest));
        
    catch ME
        error('DRPipeline:data:createManifestFailed', 'Failed to create manifest: %s', ME.message);
    end
end
