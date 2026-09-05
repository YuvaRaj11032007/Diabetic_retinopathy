%DEMO Demonstrate the DR Screening Pipeline on a single image.
%   This script runs one fundus image through the complete pipeline:
%   Quality Assessment → Enhancement → Segmentation → Grading →
%   Explainability → Report Generation.
%
%   Before running, ensure:
%     1. startup.m has been executed
%     2. At least one sample image exists in tests/fixtures/
%     3. All trained models are in models/
%
%   Usage:
%       >> demo

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Demo Script
% -------------------------------------------------------------------------

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════╗\n');
fprintf('║     Diabetic Retinopathy Screening Pipeline Demo    ║\n');
fprintf('╚══════════════════════════════════════════════════════╝\n\n');

%% Setup
projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
if isempty(projectRoot)
    error('DRPipeline:demo:notInitialized', ...
        'Run startup.m before running demo.');
end

% Locate a sample image
sampleImagePath = fullfile(projectRoot, 'tests', 'fixtures', 'sample_good_image.jpg');
if ~isfile(sampleImagePath)
    % Try to find any image in the test fixtures
    fixtureDir = fullfile(projectRoot, 'tests', 'fixtures');
    imgFiles = dir(fullfile(fixtureDir, '*.jpg'));
    if isempty(imgFiles)
        imgFiles = dir(fullfile(fixtureDir, '*.png'));
    end
    if isempty(imgFiles)
        error('DRPipeline:demo:noImage', ...
            'No sample image found in %s. Please add a fundus image.', fixtureDir);
    end
    sampleImagePath = fullfile(fixtureDir, imgFiles(1).name);
end

fprintf('Input image: %s\n\n', sampleImagePath);

%% Run Pipeline
fprintf('--- Running Full DR Screening Pipeline ---\n\n');
tic;

result = runDRScreening(sampleImagePath);

elapsed = toc;
fprintf('\n--- Pipeline Complete (%.1f seconds) ---\n\n', elapsed);

%% Display Results
gradeNames = {'No DR (Level 0)', 'Mild NPDR (Level 1)', ...
              'Moderate NPDR (Level 2)', 'Severe NPDR (Level 3)', ...
              'PDR (Level 4)'};

fprintf('╔══════════════════════════════════════════════════════╗\n');
fprintf('║                    RESULTS                          ║\n');
fprintf('╠══════════════════════════════════════════════════════╣\n');

if isnan(result.grade)
    fprintf('║  Image Quality : REJECTED                           ║\n');
    fprintf('║  Feedback      : %-36s ║\n', result.feedback.reason_text_en);
else
    fprintf('║  DR Grade      : %s\n', gradeNames{result.grade + 1});
    fprintf('║  Confidence    : %.1f%%\n', result.confidence * 100);
    fprintf('║  Referable DR  : %s\n', string(result.grade >= 2));
    fprintf('║  Report        : %s\n', result.reportPath);
    
    % Display evidence summary
    if isfield(result, 'evidence') && ~isempty(result.evidence)
        fprintf('║  Evidence      :\n');
        for i = 1:numel(result.evidence)
            fprintf('║    - %s\n', result.evidence(i).evidence_text);
        end
    end
end

fprintf('╚══════════════════════════════════════════════════════╝\n');

%% Visualize
if ~isnan(result.grade) && isfield(result, 'gradcam')
    figure('Name', 'DR Screening Results', 'NumberTitle', 'off', ...
           'Position', [100 100 1200 400]);
    
    % Original image
    subplot(1, 3, 1);
    imshow(imread(sampleImagePath));
    title('Original Image');
    
    % Enhanced image with segmentation overlay
    subplot(1, 3, 2);
    overlayHeatmap(result.segmentation.vesselMask, 'Segmentation Overlay');
    title('Vessel Segmentation');
    
    % Grad-CAM
    subplot(1, 3, 3);
    overlayHeatmap(result.gradcam, 'Grad-CAM Attention');
    title(sprintf('Grad-CAM — Grade %d', result.grade));
    
    % Save figure
    outputFig = fullfile(projectRoot, 'results', 'demo_output.png');
    exportgraphics(gcf, outputFig, 'Resolution', 150);
    fprintf('\nVisualization saved to: %s\n', outputFig);
end

fprintf('\nDemo complete.\n');
