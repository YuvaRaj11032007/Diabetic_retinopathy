function download_datasets()
%DOWNLOAD_DATASETS Download and organize datasets for the DR Screening Pipeline.
%   DOWNLOAD_DATASETS() attempts to download and organize datasets like IDRiD,
%   APTOS 2019, EyePACS, Messidor-2, and DIARETDB1. It provides instructions
%   for datasets that require manual downloading.
%
%   This function creates the required directory structure and validates the
%   availability of each dataset.
%
%   Example:
%       download_datasets()
%
%   See also checkDatasetAvailability.

    try
        % Define project root and data directories
        % Dynamic project root resolution
        projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
        if isempty(projectRoot) || ~exist(projectRoot, 'dir')
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
        end
        rawDataDir = fullfile(projectRoot, 'data', 'raw');
        
        % List of datasets to process
        datasets = {'idrid', 'aptos2019', 'eyepacs', 'messidor2', 'diaretdb1'};
        
        % Create directories
        for i = 1:length(datasets)
            ds = datasets{i};
            imgDir = fullfile(rawDataDir, ds, 'images');
            lblDir = fullfile(rawDataDir, ds, 'labels');
            
            if ~exist(imgDir, 'dir')
                mkdir(imgDir);
            end
            if ~exist(lblDir, 'dir')
                mkdir(lblDir);
            end
        end
        
        fprintf('Directory structure created at %s\n', rawDataDir);
        
        % IDRiD Instructions/Download
        fprintf('\n--- IDRiD Dataset ---\n');
        fprintf('IDRiD requires IEEE Dataport account.\n');
        fprintf('URL: https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid\n');
        fprintf('Extract images to: %s\n', fullfile(rawDataDir, 'idrid', 'images'));
        fprintf('Extract labels to: %s\n', fullfile(rawDataDir, 'idrid', 'labels'));
        
        % APTOS 2019
        fprintf('\n--- APTOS 2019 Dataset ---\n');
        fprintf('Download from Kaggle: kaggle competitions download -c aptos2019-blindness-detection\n');
        fprintf('Extract images to: %s\n', fullfile(rawDataDir, 'aptos2019', 'images'));
        fprintf('Place train.csv in: %s\n', fullfile(rawDataDir, 'aptos2019', 'labels'));
        
        % EyePACS
        fprintf('\n--- EyePACS Dataset ---\n');
        fprintf('Download from Kaggle: kaggle competitions download -c diabetic-retinopathy-detection\n');
        fprintf('Extract images to: %s\n', fullfile(rawDataDir, 'eyepacs', 'images'));
        fprintf('Place trainLabels.csv in: %s\n', fullfile(rawDataDir, 'eyepacs', 'labels'));
        
        % Messidor-2
        fprintf('\n--- Messidor-2 Dataset ---\n');
        fprintf('URL: http://www.adcis.net/en/third-party/messidor2/\n');
        fprintf('Extract images to: %s\n', fullfile(rawDataDir, 'messidor2', 'images'));
        fprintf('Extract labels to: %s\n', fullfile(rawDataDir, 'messidor2', 'labels'));
        
        % DIARETDB1
        fprintf('\n--- DIARETDB1 Dataset ---\n');
        fprintf('URL: https://www.it.lut.fi/project/imageret/diaretdb1/\n');
        fprintf('Extract images to: %s\n', fullfile(rawDataDir, 'diaretdb1', 'images'));
        fprintf('Extract annotations to: %s\n', fullfile(rawDataDir, 'diaretdb1', 'labels'));
        
        fprintf('\nChecking dataset availability...\n');
        checkDatasetAvailability(rawDataDir, datasets);
        
    catch ME
        error('DRPipeline:data:downloadDatasetsFailed', 'Failed to download datasets: %s', ME.message);
    end
end

function checkDatasetAvailability(rawDataDir, datasets)
%CHECKDATASETAVAILABILITY Check which datasets are present in the raw data directory.
%   CHECKDATASETAVAILABILITY(RAWDATADIR, DATASETS) checks if the images
%   folder for each dataset contains any files.
    
    arguments
        rawDataDir (1,:) char
        datasets (1,:) cell
    end
    
    for i = 1:length(datasets)
        ds = datasets{i};
        imgDir = fullfile(rawDataDir, ds, 'images');
        
        if exist(imgDir, 'dir')
            files = dir(fullfile(imgDir, '*.*'));
            % Filter out . and ..
            files = files(~ismember({files.name}, {'.', '..'}));
            
            if ~isempty(files)
                fprintf('[V] %s: Found %d files.\n', ds, length(files));
            else
                fprintf('[X] %s: Directory empty.\n', ds);
            end
        else
            fprintf('[X] %s: Directory not found.\n', ds);
        end
    end
end
