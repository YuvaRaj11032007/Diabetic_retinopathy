function blendedImg = overlayHeatmap(baseImage, heatmap, alpha)
%OVERLAYHEATMAP Overlay a 2D heatmap onto a fundus image.
%
%   BLENDEDIMG = overlayHeatmap(BASEIMAGE, HEATMAP) overlays the HEATMAP
%   onto BASEIMAGE using a 'jet' colormap and 0.4 opacity.
%
%   BLENDEDIMG = overlayHeatmap(BASEIMAGE, HEATMAP, ALPHA) uses the specified
%   opacity ALPHA (between 0 and 1).
%
%   Inputs:
%       baseImage - M x N x 3 uint8 RGB image.
%       heatmap   - M x N numeric array, normalized [0, 1].
%       alpha     - (Optional) Scalar double between 0 and 1 for heatmap opacity.
%
%   Outputs:
%       blendedImg - M x N x 3 uint8 blended image.
%
%   Example:
%       img = imread('sample.jpg');
%       hm = rand(size(img,1), size(img,2));
%       result = overlayHeatmap(img, hm, 0.5);
%
%   See also IND2RGB, JET.

    arguments
        baseImage (:,:,3) uint8
        heatmap (:,:) double {mustBeInRange(heatmap, 0, 1)}
        alpha (1,1) double {mustBeInRange(alpha, 0, 1)} = 0.4
    end

    [h, w, ~] = size(baseImage);
    
    if size(heatmap, 1) ~= h || size(heatmap, 2) ~= w
        heatmap = imresize(heatmap, [h, w]);
    end
    
    % Convert heatmap to RGB using jet colormap
    numColors = 256;
    cmap = jet(numColors);
    
    % Scale heatmap to indices
    hmIndices = round(heatmap * (numColors - 1)) + 1;
    hmRgb = ind2rgb(hmIndices, cmap);
    hmRgb = im2uint8(hmRgb);
    
    % Blend images
    blendedImg = imlincomb(1 - alpha, baseImage, alpha, hmRgb);
    
    if nargout == 0
        imshow(blendedImg);
    end
end
