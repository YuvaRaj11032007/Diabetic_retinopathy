%GENERATE_API_DOCS Auto-generate API reference documentation.
%   This script scans all MATLAB functions in src/ and generates a
%   markdown API reference document at docs/api_reference.md.
%
%   Usage:
%       >> generate_api_docs

% -------------------------------------------------------------------------
%   DR Screening Pipeline — API Documentation Generator
% -------------------------------------------------------------------------

fprintf('[ApiDocs] Generating API reference documentation...\n');

projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
if isempty(projectRoot)
    projectRoot = fileparts(fileparts(mfilename('fullpath')));
end

outputFile = fullfile(projectRoot, 'docs', 'api_reference.md');

% Define modules and their source directories
modules = {
    'Utils',            fullfile(projectRoot, 'src', 'utils')
    'Quality',          fullfile(projectRoot, 'src', 'quality')
    'Segmentation',     fullfile(projectRoot, 'src', 'segmentation')
    'Grading',          fullfile(projectRoot, 'src', 'grading')
    'Explainability',   fullfile(projectRoot, 'src', 'explainability')
    'Pipeline',         fullfile(projectRoot, 'src', 'pipeline')
    'Validation',       fullfile(projectRoot, 'src', 'validation')
};

% Open output file
fid = fopen(outputFile, 'w');
if fid == -1
    error('DRPipeline:docs:cannotWrite', 'Cannot open %s for writing.', outputFile);
end

cleanupObj = onCleanup(@() fclose(fid));

% Header
fprintf(fid, '# API Reference\n\n');
fprintf(fid, '> Auto-generated from source code on %s\n\n', char(datetime('now')));
fprintf(fid, '---\n\n');
fprintf(fid, '## Table of Contents\n\n');

% TOC
for m = 1:size(modules, 1)
    fprintf(fid, '- [%s Module](#%s-module)\n', modules{m, 1}, lower(modules{m, 1}));
end
fprintf(fid, '\n---\n\n');

totalFunctions = 0;

for m = 1:size(modules, 1)
    moduleName = modules{m, 1};
    moduleDir = modules{m, 2};

    fprintf(fid, '## %s Module\n\n', moduleName);
    fprintf(fid, '**Source directory:** `src/%s/`\n\n', lower(moduleName));

    if ~exist(moduleDir, 'dir')
        fprintf(fid, '_Directory not found._\n\n');
        continue;
    end

    mFiles = dir(fullfile(moduleDir, '*.m'));

    if isempty(mFiles)
        fprintf(fid, '_No functions found._\n\n');
        continue;
    end

    for f = 1:numel(mFiles)
        filePath = fullfile(mFiles(f).folder, mFiles(f).name);
        [~, funcName, ~] = fileparts(mFiles(f).name);

        % Read the file and extract help block
        helpText = extractHelpBlock(filePath);

        fprintf(fid, '### `%s`\n\n', funcName);
        fprintf(fid, '**File:** `src/%s/%s`\n\n', lower(moduleName), mFiles(f).name);

        if ~isempty(helpText)
            fprintf(fid, '```\n%s\n```\n\n', helpText);
        else
            fprintf(fid, '_No documentation available._\n\n');
        end

        fprintf(fid, '---\n\n');
        totalFunctions = totalFunctions + 1;
    end
end

fprintf(fid, '---\n\n');
fprintf(fid, '*Total functions documented: %d*\n', totalFunctions);

fprintf('[ApiDocs] Generated %s (%d functions documented)\n', outputFile, totalFunctions);

function helpText = extractHelpBlock(filePath)
%EXTRACTHELPBLOCK Extract the help comment block from a MATLAB file.
    helpText = '';
    fid = fopen(filePath, 'r');
    if fid == -1, return; end
    cleanup = onCleanup(@() fclose(fid));

    lines = {};
    inHelp = false;

    while ~feof(fid)
        line = fgetl(fid);
        if ischar(line)
            trimmed = strtrim(line);

            if ~inHelp
                % Skip the function declaration line
                if startsWith(trimmed, 'function')
                    continue;
                end
                % Start of help block
                if startsWith(trimmed, '%')
                    inHelp = true;
                    lines{end+1} = regexprep(trimmed, '^%\s?', ''); %#ok<AGROW>
                else
                    break;  % No help block
                end
            else
                if startsWith(trimmed, '%')
                    lines{end+1} = regexprep(trimmed, '^%\s?', ''); %#ok<AGROW>
                else
                    break;  % End of help block
                end
            end
        end
    end

    helpText = strjoin(lines, '\n');
end
