function results = batchProcessImages(inputDir, outputDir, options)
%BATCHPROCESSIMAGES Process multiple fundus images through the DR pipeline.
%   RESULTS = BATCHPROCESSIMAGES(INPUTDIR) processes all fundus images in
%   INPUTDIR through the complete DR screening pipeline.
%
%   RESULTS = BATCHPROCESSIMAGES(INPUTDIR, OUTPUTDIR) saves reports to
%   OUTPUTDIR. Default is 'results/reports/'.
%
%   RESULTS = BATCHPROCESSIMAGES(INPUTDIR, OUTPUTDIR, OPTIONS) with options:
%     'Extensions'    - Cell array of extensions to process (default: {'.jpg','.png','.tif'})
%     'MaxImages'     - Maximum number of images to process (default: Inf)
%     'ContinueOnError' - Continue processing if an image fails (default: true)
%     'SaveResults'   - Save results struct to .mat file (default: true)
%     'ModelsDir'     - Directory with trained models (default: 'models/')
%     'Parallel'      - Use parallel pool if available (default: false)
%
%   Output RESULTS is a struct array with one entry per image, each
%   containing the full runDRScreening output plus processing metadata.
%
%   Example:
%       results = batchProcessImages('data/raw/idrid/images/', 'results/reports/');
%       fprintf('Processed %d images. Mean time: %.1f sec\n', ...
%           numel(results), mean([results.processingTime.total]));
%
%   See also: RUNDRSCREENING

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Batch Processing
% -------------------------------------------------------------------------

    arguments
        inputDir (1,:) char {mustBeFolder}
        outputDir (1,:) char = ''
        options.Extensions (1,:) cell = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp'}
        options.MaxImages (1,1) double {mustBePositive} = Inf
        options.ContinueOnError (1,1) logical = true
        options.SaveResults (1,1) logical = true
        options.ModelsDir (1,:) char = ''
        options.Parallel (1,1) logical = false
    end

    % Resolve output directory
    projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
    if isempty(outputDir)
        if ~isempty(projectRoot)
            outputDir = fullfile(projectRoot, 'results', 'reports');
        else
            outputDir = fullfile(inputDir, '..', 'reports');
        end
    end

    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    % Find all image files
    allFiles = [];
    for ext = options.Extensions
        allFiles = [allFiles; dir(fullfile(inputDir, ['*', ext{1}]))]; %#ok<AGROW>
    end

    if isempty(allFiles)
        warning('DRPipeline:pipeline:noImages', ...
            'No image files found in %s', inputDir);
        results = struct([]);
        return;
    end

    % Limit number of images
    nImages = min(numel(allFiles), options.MaxImages);
    allFiles = allFiles(1:nImages);

    fprintf('\n╔══════════════════════════════════════════════════════╗\n');
    fprintf('║         Batch DR Screening — %d images              ║\n', nImages);
    fprintf('╚══════════════════════════════════════════════════════╝\n\n');

    % Pre-allocate results
    results(nImages) = struct('imagePath', '', 'grade', NaN, 'gradeName', '', ...
        'confidence', 0, 'isReferable', false, 'reportPath', '', ...
        'processingTime', struct(), 'error', '');

    % Processing loop
    successCount = 0;
    rejectCount = 0;
    errorCount = 0;
    totalTimer = tic;

    for i = 1:nImages
        imgPath = fullfile(allFiles(i).folder, allFiles(i).name);

        fprintf('[Batch %d/%d] %s ... ', i, nImages, allFiles(i).name);

        try
            r = runDRScreening(imgPath, ...
                'ModelsDir', options.ModelsDir, ...
                'OutputDir', outputDir, ...
                'Verbose', false, ...
                'GenerateReport', true);

            results(i).imagePath = imgPath;
            results(i).grade = r.grade;
            results(i).gradeName = r.gradeName;
            results(i).confidence = r.confidence;
            results(i).isReferable = r.isReferable;
            results(i).reportPath = r.reportPath;
            results(i).processingTime = r.processingTime;

            if isnan(r.grade)
                rejectCount = rejectCount + 1;
                fprintf('REJECTED (%.1fs)\n', r.processingTime.total);
            else
                successCount = successCount + 1;
                fprintf('Grade %d (%.1f%% conf, %.1fs)\n', ...
                    r.grade, r.confidence * 100, r.processingTime.total);
            end

        catch ME
            errorCount = errorCount + 1;
            results(i).imagePath = imgPath;
            results(i).error = ME.message;

            fprintf('ERROR: %s\n', ME.message);

            if ~options.ContinueOnError
                error('DRPipeline:pipeline:batchAborted', ...
                    'Batch processing aborted at image %d: %s', i, ME.message);
            end
        end
    end

    batchTime = toc(totalTimer);

    % Summary
    fprintf('\n╔══════════════════════════════════════════════════════╗\n');
    fprintf('║                  BATCH SUMMARY                      ║\n');
    fprintf('╠══════════════════════════════════════════════════════╣\n');
    fprintf('║  Total images    : %d\n', nImages);
    fprintf('║  Successful      : %d\n', successCount);
    fprintf('║  Rejected        : %d\n', rejectCount);
    fprintf('║  Errors          : %d\n', errorCount);
    fprintf('║  Total time      : %.1f sec\n', batchTime);
    fprintf('║  Avg time/image  : %.1f sec\n', batchTime / nImages);
    fprintf('║  Reports saved   : %s\n', outputDir);

    % Grade distribution
    grades = [results.grade];
    grades = grades(~isnan(grades));
    if ~isempty(grades)
        fprintf('║  Grade distribution:\n');
        for g = 0:4
            cnt = sum(grades == g);
            fprintf('║    Level %d: %d (%.1f%%)\n', g, cnt, cnt/numel(grades)*100);
        end
        fprintf('║  Referable (≥2): %d (%.1f%%)\n', ...
            sum(grades >= 2), sum(grades >= 2)/numel(grades)*100);
    end

    fprintf('╚══════════════════════════════════════════════════════╝\n\n');

    % Save results
    if options.SaveResults
        resultsFile = fullfile(outputDir, 'batch_results.mat');
        batchMeta = struct('nImages', nImages, 'successCount', successCount, ...
            'rejectCount', rejectCount, 'errorCount', errorCount, ...
            'totalTime', batchTime, 'timestamp', datetime('now'));
        save(resultsFile, 'results', 'batchMeta');
        fprintf('Results saved to: %s\n', resultsFile);
    end
end
