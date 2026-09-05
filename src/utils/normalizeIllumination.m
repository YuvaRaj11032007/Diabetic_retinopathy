function normImg = normalizeIllumination(img)
%NORMALIZEILLUMINATION Normalize the illumination of a fundus image.
%
%   NORMIMG = normalizeIllumination(IMG) returns the image unchanged
%   and throws a warning. This is a STUB function.
%
%   Inputs:
%       img - Input image.
%
%   Outputs:
%       normImg - The unchanged input image.
%
%   Example:
%       img = imread('sample.jpg');
%       res = normalizeIllumination(img);
%
%   See also ADAPTHISTEQ.

    arguments
        img
    end
    
    warning('DRPipeline:utils:StubFunction', 'normalizeIllumination is currently a STUB. Implementation will be added in T-07.');
    normImg = img;
end
