function [img, metadata] = loadFundusImage(imagePath, targetSize)
%LOADFUNDUSIMAGE Load a fundus image and optionally resize it.
%
%   [IMG, METADATA] = loadFundusImage(IMAGEPATH) loads the image from the
%   specified path. It validates that the image is RGB.
%
%   [IMG, METADATA] = loadFundusImage(IMAGEPATH, TARGETSIZE) optionally 
%   resizes the image to TARGETSIZE, specified as a 1x2 vector [rows, cols].
%
%   Inputs:
%       imagePath  - String or char array specifying the path to the image.
%       targetSize - (Optional) 1x2 numeric array [rows, cols] for resizing.
%
%   Outputs:
%       img      - M x N x 3 uint8 image array.
%       metadata - Struct containing width, height, channels, and fileSize.
%
%   Example:
%       [img, meta] = loadFundusImage('sample.jpg', [512 512]);
%
%   See also IMREAD, IMRESIZE.

    arguments
        imagePath
        targetSize double = []
    end

    imagePath = char(imagePath);
    if ~isfile(imagePath)
        error('DRPipeline:utils:FileNotFound', 'File does not exist: %s', imagePath);
    end
    if ~isempty(targetSize) && numel(targetSize) ~= 2
        error('DRPipeline:utils:InvalidTargetSize', 'targetSize must be a 1x2 vector [rows, cols].');
    end

    try
        info = imfinfo(imagePath);
        img = imread(imagePath);
    catch ME
        error('DRPipeline:utils:LoadError', 'Failed to load image: %s', ME.message);
    end

    if size(img, 3) ~= 3
        error('DRPipeline:utils:InvalidChannels', 'Fundus image must be an RGB image with 3 channels.');
    end

    if ~isempty(targetSize)
        img = imresize(img, targetSize);
    end

    metadata = struct();
    metadata.width = size(img, 2);
    metadata.height = size(img, 1);
    metadata.channels = size(img, 3);
    metadata.fileSize = info.FileSize;
end
