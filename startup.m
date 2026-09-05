%STARTUP Add all DR Screening Pipeline source directories to the MATLAB path.
%   Run this script once per MATLAB session (or add to your MATLAB startup)
%   to make all pipeline functions available.
%
%   Usage:
%       >> startup
%
%   See also: RUNDRSSCREENING, DEMO

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Startup Script
%   Copyright (c) 2026. All rights reserved.
% -------------------------------------------------------------------------

fprintf('=== DR Screening Pipeline — Initializing ===\n');

% Get the project root (directory containing this script)
projectRoot = fileparts(mfilename('fullpath'));

% Define all source directories to add
srcDirs = {
    fullfile(projectRoot, 'src', 'utils')
    fullfile(projectRoot, 'src', 'quality')
    fullfile(projectRoot, 'src', 'segmentation')
    fullfile(projectRoot, 'src', 'grading')
    fullfile(projectRoot, 'src', 'explainability')
    fullfile(projectRoot, 'src', 'pipeline')
    fullfile(projectRoot, 'src', 'simulink', 'params')
    fullfile(projectRoot, 'src', 'simulink', 'models')
    fullfile(projectRoot, 'src', 'simulink', 'dashboard')
    fullfile(projectRoot, 'src', 'validation')
    fullfile(projectRoot, 'models', 'quality')
    fullfile(projectRoot, 'models', 'segmentation')
    fullfile(projectRoot, 'models', 'grading')
    fullfile(projectRoot, 'scripts')
    fullfile(projectRoot, 'tests')
};

% Add each directory to path
addedCount = 0;
for i = 1:numel(srcDirs)
    dirPath = srcDirs{i};
    if exist(dirPath, 'dir') == 7
        addpath(dirPath);
        addedCount = addedCount + 1;
    else
        warning('DRPipeline:startup:missingDir', ...
            'Directory not found: %s', dirPath);
    end
end

% Also add the project root itself
addpath(projectRoot);

% Set global configuration
setappdata(0, 'DRPipeline_ProjectRoot', projectRoot);
setappdata(0, 'DRPipeline_DataDir', fullfile(projectRoot, 'data'));
setappdata(0, 'DRPipeline_ModelsDir', fullfile(projectRoot, 'models'));
setappdata(0, 'DRPipeline_ResultsDir', fullfile(projectRoot, 'results'));

fprintf('  Project root : %s\n', projectRoot);
fprintf('  Directories  : %d / %d added to path\n', addedCount, numel(srcDirs));
fprintf('=== Initialization Complete ===\n\n');
