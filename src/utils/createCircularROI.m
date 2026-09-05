function [mask, circleParams] = createCircularROI(imgOrSize, centerAndRadius)
%CREATECIRCULARROI Create a binary circular mask for fundus ROI extraction.
%
%   [MASK, CIRCLEPARAMS] = createCircularROI(IMG) auto-detects the 
%   fundus circle using intensity thresholding from the input IMG.
%
%   [MASK, CIRCLEPARAMS] = createCircularROI(IMGSIZE, CENTERANDRADIUS) uses
%   the specified center and radius [cx, cy, r] to generate the mask.
%
%   Inputs:
%       imgOrSize       - 2D/3D image array OR 1x2/1x3 numeric array of dimensions.
%       centerAndRadius - (Optional) 1x3 vector [cx, cy, radius].
%
%   Outputs:
%       mask         - Binary mask of size [rows, cols] where ROI is true.
%       circleParams - 1x3 vector [cx, cy, radius] used for the mask.
%
%   Example:
%       [mask, params] = createCircularROI(img);
%       [mask, params] = createCircularROI([512 512], [256 256 250]);
%
%   See also IMBINARIZE, REGIONPROPS.

    arguments
        imgOrSize 
        centerAndRadius double = []
    end
    
    if ~isempty(centerAndRadius) && numel(centerAndRadius) ~= 3
        error('DRPipeline:utils:InvalidCircleParams', 'centerAndRadius must be [cx, cy, radius].');
    end
    
    isImage = ~isvector(imgOrSize) || (isvector(imgOrSize) && length(imgOrSize) > 3);
    
    if isImage
        rows = size(imgOrSize, 1);
        cols = size(imgOrSize, 2);
    else
        rows = imgOrSize(1);
        cols = imgOrSize(2);
    end

    if isempty(centerAndRadius)
        if isImage
            % Auto-detect using intensity thresholding
            if size(imgOrSize, 3) == 3
                grayImg = rgb2gray(imgOrSize);
            else
                grayImg = imgOrSize;
            end
            
            % Thresholding
            thresh = graythresh(grayImg);
            bw = imbinarize(grayImg, max(thresh, 0.05));
            
            % Find largest blob
            bw = bwareafilt(bw, 1);
            
            % Get region properties
            props = regionprops(bw, 'Centroid', 'EquivDiameter');
            if ~isempty(props)
                cx = props.Centroid(1);
                cy = props.Centroid(2);
                r = props.EquivDiameter / 2;
            else
                % Fallback
                cx = cols / 2;
                cy = rows / 2;
                r = min(rows, cols) / 2 * 0.95;
            end
        else
            % Fallback if only size is provided
            cx = cols / 2;
            cy = rows / 2;
            r = min(rows, cols) / 2 * 0.95;
        end
    else
        cx = centerAndRadius(1);
        cy = centerAndRadius(2);
        r = centerAndRadius(3);
    end
    
    circleParams = [cx, cy, r];

    [X, Y] = meshgrid(1:cols, 1:rows);
    squaredDist = (X - cx).^2 + (Y - cy).^2;
    mask = squaredDist <= r^2;
end
