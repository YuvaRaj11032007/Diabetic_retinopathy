function saveFigureReport(outputPath, resolution, format)
%SAVEFIGUREREPORT Save the current figure to a file.
%
%   saveFigureReport(OUTPUTPATH) saves the current figure to the specified
%   OUTPUTPATH. Auto-creates directory if needed. Uses 300 DPI and PNG format.
%
%   saveFigureReport(OUTPUTPATH, RESOLUTION, FORMAT) specifies the DPI
%   resolution and format ('png', 'pdf', 'svg').
%
%   Inputs:
%       outputPath - String or char array specifying output file path.
%       resolution - (Optional) Integer DPI (default 300).
%       format     - (Optional) String format ('png', 'pdf', 'svg') (default 'png').
%
%   Example:
%       plot(1:10);
%       saveFigureReport('reports/fig1.png', 300, 'png');
%
%   See also EXPORTGRAPHICS, MKDIR.

    arguments
        outputPath (1,1) string
        resolution (1,1) double {mustBePositive, mustBeInteger} = 300
        format (1,1) string = "png"
    end

    fig = gcf;
    
    % Ensure directory exists
    outDir = fileparts(outputPath);
    if ~isempty(outDir) && ~isfolder(outDir)
        mkdir(outDir);
    end
    
    % Validate format
    validFormats = ["png", "pdf", "svg"];
    if ~ismember(lower(format), validFormats)
        error('DRPipeline:utils:InvalidFormat', 'Format must be one of: png, pdf, svg.');
    end
    
    try
        if strcmpi(format, 'pdf')
            exportgraphics(fig, outputPath, 'ContentType', 'vector', 'Resolution', resolution);
        else
            exportgraphics(fig, outputPath, 'Resolution', resolution);
        end
    catch ME
        error('DRPipeline:utils:SaveError', 'Failed to save figure: %s', ME.message);
    end
end
