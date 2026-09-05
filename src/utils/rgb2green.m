function greenChannel = rgb2green(rgbImage)
%RGB2GREEN Extract the green channel from an RGB fundus image.
%
%   GREENCHANNEL = rgb2green(RGBIMAGE) extracts the green color channel,
%   which typically provides the highest contrast for retinal structures.
%
%   Inputs:
%       rgbImage - M x N x 3 RGB image.
%
%   Outputs:
%       greenChannel - M x N grayscale image corresponding to the green channel.
%
%   Example:
%       img = imread('sample.jpg');
%       g = rgb2green(img);
%       imshow(g);
%
%   See also RGB2GRAY.

    arguments
        rgbImage (:,:,3) {mustBeNumeric}
    end

    if size(rgbImage, 3) ~= 3
        error('DRPipeline:utils:NotRGB', 'Input image must have 3 channels (RGB).');
    end
    
    greenChannel = rgbImage(:, :, 2);
end
