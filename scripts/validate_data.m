function validate_data()
%VALIDATE_DATA Validate images based on the master manifest.
%   VALIDATE_DATA() reads the master_manifest.csv, checks if each image
%   exists, is readable, and extracts its dimensions and size. It saves the
%   result as master_manifest_validated.csv and generates a data audit report.
%
%   Example:
%       validate_data()

    try
        fprintf('Starting data validation...\n');
        
        projectRoot = fullfile('d:', 'sih_project');
        manifestDir = fullfile(projectRoot, 'data', 'manifests');
        reportsDir = fullfile(projectRoot, 'data', 'reports');
        
        if ~exist(reportsDir, 'dir')
            mkdir(reportsDir);
        end
        
        manifestPath = fullfile(manifestDir, 'master_manifest.csv');
        if ~exist(manifestPath, 'file')
            error('DRPipeline:data:missingManifest', 'Master manifest not found. Run create_manifest first.');
        end
        
        manifest = readtable(manifestPath, 'TextType', 'string');
        n = height(manifest);
        
        % Preallocate new columns
        is_valid = false(n, 1);
        width = zeros(n, 1);
        height_img = zeros(n, 1);
        channels = zeros(n, 1);
        file_size_bytes = zeros(n, 1);
        
        % Validate each image
        for i = 1:n
            filePath = manifest.filepath(i);
            
            if exist(filePath, 'file')
                try
                    info = imfinfo(char(filePath));
                    width(i) = info.Width;
                    height_img(i) = info.Height;
                    channels(i) = info.BitDepth / 8; % Rough estimate
                    file_size_bytes(i) = info.FileSize;
                    is_valid(i) = true;
                catch
                    is_valid(i) = false;
                end
            else
                is_valid(i) = false;
            end
            
            if mod(i, 500) == 0
                fprintf('Validated %d / %d images\n', i, n);
            end
        end
        
        % Add columns to table
        manifest.is_valid = is_valid;
        manifest.width = width;
        manifest.height = height_img;
        manifest.channels = channels;
        manifest.file_size_bytes = file_size_bytes;
        
        % Save validated manifest
        valManifestPath = fullfile(manifestDir, 'master_manifest_validated.csv');
        writetable(manifest, valManifestPath);
        fprintf('Validated manifest saved to %s\n', valManifestPath);
        
        % Generate report
        reportPath = fullfile(reportsDir, 'data_audit_report.txt');
        fid = fopen(reportPath, 'w');
        if fid == -1
            error('DRPipeline:data:cannotCreateReport', 'Cannot create audit report file.');
        end
        
        fprintf(fid, 'Data Audit Report\n');
        fprintf(fid, '=================\n');
        fprintf(fid, 'Total images: %d\n', n);
        fprintf(fid, 'Valid images: %d\n', sum(is_valid));
        fprintf(fid, 'Invalid images: %d\n', sum(~is_valid));
        fclose(fid);
        
        fprintf('Data audit report saved to %s\n', reportPath);
        
    catch ME
        error('DRPipeline:data:validationFailed', 'Data validation failed: %s', ME.message);
    end
end
