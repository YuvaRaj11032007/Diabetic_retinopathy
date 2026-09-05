function reportPath = generateReport(imagePath, enhancedImg, gradcamMap, evidence, grade, confidence, outputPath)
%GENERATEREPORT Generate a single-page annotated clinical report as HTML file.
%
%   reportPath = GENERATEREPORT(imagePath, enhancedImg, gradcamMap, evidence, grade, confidence, outputPath)
%
%   Inputs:
%       imagePath   - string path to original image
%       enhancedImg - uint8 RGB enhanced image
%       gradcamMap  - 2D double heatmap
%       evidence    - struct array from mapLesionEvidence
%       grade       - integer 0-4
%       confidence  - double (0-1)
%       outputPath  - string path to save HTML file
%
%   Outputs:
%       reportPath  - path to the generated HTML file

    arguments
        imagePath {mustBeTextScalar}
        enhancedImg (:,:,:) uint8
        gradcamMap (:,:) double
        evidence struct
        grade (1,1) {mustBeInteger, mustBeInRange(grade, 0, 4)}
        confidence (1,1) double
        outputPath {mustBeTextScalar}
    end

    reportPath = char(outputPath);
    [outDir, imgName, ~] = fileparts(reportPath);
    if ~isempty(outDir) && ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    gradeNames = {'No Diabetic Retinopathy', 'Mild NPDR', 'Moderate NPDR', 'Severe NPDR', 'Proliferative DR (PDR)'};
    gradeColors = {'#2e7d32', '#f9a825', '#ef6c00', '#c62828', '#b71c1c'};
    recommendations = {
        'Routine annual screening recommended.'
        'Follow-up examination in 6-12 months.'
        'Referral to an ophthalmologist within 2-4 weeks.'
        'Prompt referral to a retina specialist within 1-2 weeks.'
        'Urgent referral to a retina specialist within 24-48 hours.'
    };

    % Save preview images for report
    origPreviewPath = fullfile(outDir, [imgName, '_orig.jpg']);
    enhPreviewPath  = fullfile(outDir, [imgName, '_enh.jpg']);
    gradPreviewPath = fullfile(outDir, [imgName, '_grad.jpg']);

    try
        copyfile(char(imagePath), origPreviewPath);
    catch
        try, imwrite(imread(char(imagePath)), origPreviewPath); catch, end
    end
    try, imwrite(enhancedImg, enhPreviewPath); catch, end

    % Blend gradcam with enhanced image if available
    try
        if ~isempty(gradcamMap)
            hResized = imresize(gradcamMap, [size(enhancedImg, 1), size(enhancedImg, 2)]);
            hJet = uint8(255 * colormap_jet_fast(hResized));
            blended = uint8(0.6 * double(enhancedImg) + 0.4 * double(hJet));
            imwrite(blended, gradPreviewPath);
        else
            imwrite(enhancedImg, gradPreviewPath);
        end
    catch
        imwrite(enhancedImg, gradPreviewPath);
    end

    % Build evidence table HTML
    evidenceHtml = '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse; width:100%;">';
    evidenceHtml = [evidenceHtml, '<tr style="background:#f0f0f0;"><th>Criterion</th><th>Severity</th><th>Findings</th></tr>'];
    if isempty(evidence) || (numel(evidence) == 1 && isfield(evidence, 'criterion') && strcmp(evidence(1).criterion, 'N/A'))
        evidenceHtml = [evidenceHtml, '<tr><td colspan="3" style="text-align:center;">No significant DR lesion patterns flagged.</td></tr>'];
    else
        for k = 1:numel(evidence)
            crit = ''; sev = ''; txt = '';
            if isfield(evidence(k), 'criterion'), crit = string(evidence(k).criterion); end
            if isfield(evidence(k), 'severity'),  sev  = string(evidence(k).severity);  end
            if isfield(evidence(k), 'evidence_text'), txt = string(evidence(k).evidence_text); end
            evidenceHtml = [evidenceHtml, sprintf('<tr><td>%s</td><td>%s</td><td>%s</td></tr>', crit, sev, txt)]; %#ok<AGROW>
        end
    end
    evidenceHtml = [evidenceHtml, '</table>'];

    % Load template or build HTML
    templatePath = fullfile(fileparts(mfilename('fullpath')), 'report_template.html');
    if exist(templatePath, 'file')
        htmlContent = fileread(templatePath);
        htmlContent = strrep(htmlContent, '{{IMAGE_ID}}', imgName);
        htmlContent = strrep(htmlContent, '{{DATE}}', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')));
        htmlContent = strrep(htmlContent, '{{ORIGINAL_IMG}}', [imgName, '_orig.jpg']);
        htmlContent = strrep(htmlContent, '{{ENHANCED_IMG}}', [imgName, '_enh.jpg']);
        htmlContent = strrep(htmlContent, '{{GRADCAM_IMG}}', [imgName, '_grad.jpg']);
        htmlContent = strrep(htmlContent, '{{DR_GRADE}}', num2str(grade));
        htmlContent = strrep(htmlContent, '{{GRADE_NAME}}', gradeNames{grade + 1});
        htmlContent = strrep(htmlContent, '{{GRADE_COLOR}}', gradeColors{grade + 1});
        htmlContent = strrep(htmlContent, '{{CONFIDENCE}}', sprintf('%.1f%%', confidence * 100));
        htmlContent = strrep(htmlContent, '{{EVIDENCE_TABLE}}', evidenceHtml);
        htmlContent = strrep(htmlContent, '{{RECOMMENDATION}}', recommendations{grade + 1});
        htmlContent = strrep(htmlContent, '{{PROCESSING_TIME}}', char(datetime('now')));
    else
        htmlContent = sprintf(['<!DOCTYPE html><html><head><title>DR Report - %s</title></head>' ...
            '<body style="font-family:Arial,sans-serif;padding:20px;">' ...
            '<h2>Diabetic Retinopathy Screening Report</h2>' ...
            '<p><strong>Image:</strong> %s | <strong>Date:</strong> %s</p>' ...
            '<h3 style="color:%s">DR Grade: Level %d (%s)</h3>' ...
            '<p><strong>Confidence:</strong> %.1f%%</p>' ...
            '<p><strong>Recommendation:</strong> %s</p>' ...
            '<h3>Evidence Summary</h3>%s</body></html>'], ...
            imgName, imgName, char(datetime('now')), gradeColors{grade+1}, grade, gradeNames{grade+1}, ...
            confidence*100, recommendations{grade+1}, evidenceHtml);
    end

    fid = fopen(reportPath, 'w');
    if fid ~= -1
        fwrite(fid, htmlContent);
        fclose(fid);
    end
end

function rgbMap = colormap_jet_fast(grayImg)
% Helper to map 0-1 grayscale into jet-like RGB without external toolbox
    X = double(grayImg);
    r = clamp_val(1.5 - abs(4*X - 3));
    g = clamp_val(1.5 - abs(4*X - 2));
    b = clamp_val(1.5 - abs(4*X - 1));
    rgbMap = cat(3, r, g, b);
end

function v = clamp_val(v)
    v(v < 0) = 0;
    v(v > 1) = 1;
end
