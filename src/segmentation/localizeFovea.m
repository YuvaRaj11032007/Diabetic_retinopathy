function foveaResult = localizeFovea(imgRGB, odResult)
%LOCALIZEFOVEA Localize the fovea center using anatomical priors
%
%   foveaResult = localizeFovea(imgRGB, odResult) localizes the fovea 
%   using the anatomical prior relative to the optic disc and intensity.
%
%   INPUTS:
%       imgRGB   - Enhanced RGB fundus image (H x W x 3 uint8)
%       odResult - Struct from localizeOpticDisc containing OD center and radius
%
%   OUTPUTS:
%       foveaResult - Struct containing fields:
%           .center          - [x, y] coordinates of Fovea center
%           .confidence      - Confidence score [0, 1]
%           .searchRegionMask- Binary mask of the search region
%
%   EXAMPLE:
%       img = imread('fundus.jpg');
%       odRes = localizeOpticDisc(img);
%       fovRes = localizeFovea(img, odRes);
%       imshow(img); hold on;
%       plot(fovRes.center(1), fovRes.center(2), 'r+', 'MarkerSize', 10);
%
%   See also localizeOpticDisc

    arguments
        imgRGB (:,:,3) uint8
        odResult (1,1) struct
    end
    
    if ~isfield(odResult, 'center') || ~isfield(odResult, 'radius')
        error('DRPipeline:segmentation:localizeFovea:InvalidOD', ...
            'odResult must contain center and radius fields.');
    end

    [H, W, ~] = size(imgRGB);
    
    odCenter = odResult.center;
    odRadius = odResult.radius;
    
    % a. Determine laterality (left/right eye) from OD position
    if odCenter(1) < W/2
        isRightEye = false; 
        direction = 1; 
    else
        isRightEye = true;
        direction = -1;
    end
    
    % b. Compute expected fovea location (2.5 DD temporal, slightly inferior)
    DD = 2 * odRadius;
    expectedDistX = direction * 2.5 * DD;
    expectedDistY = 0.5 * DD;
    
    expectedCenter = [odCenter(1) + expectedDistX, odCenter(2) + expectedDistY];
    
    if expectedCenter(1) < 1 || expectedCenter(1) > W || expectedCenter(2) < 1 || expectedCenter(2) > H
        expectedCenter(1) = max(1, min(expectedCenter(1), W));
        expectedCenter(2) = max(1, min(expectedCenter(2), H));
    end
    
    % c. Create search region (2 DD radius around expected location)
    searchRadius = 2 * DD;
    [X, Y] = meshgrid(1:W, 1:H);
    distSq = (X - expectedCenter(1)).^2 + (Y - expectedCenter(2)).^2;
    searchMask = distSq <= searchRadius^2;
    
    if ~any(searchMask(:))
        error('DRPipeline:segmentation:localizeFovea:InvalidSearchRegion', ...
            'Search region is outside image bounds. Check OD localization.');
    end
    
    % d. Find darkest region in green channel within search region
    greenChannel = im2double(imgRGB(:,:,2));
    greenBlurred = imgaussfilt(greenChannel, 3);
    
    greenSearch = greenBlurred;
    greenSearch(~searchMask) = 1.0;
    
    [minVal, minIdx] = min(greenSearch(:));
    [minY, minX] = ind2sub([H, W], minIdx);
    
    % e. Refine using parabolic fitting of the intensity valley (centroid of darkest pixels)
    maskedVals = greenBlurred(searchMask);
    thresh = prctile(maskedVals, 5);
    
    darkestMask = searchMask & (greenBlurred <= thresh);
    
    props = regionprops(darkestMask, 'Centroid', 'Area');
    if ~isempty(props)
        [~, maxAreaIdx] = max([props.Area]);
        foveaCenter = props(maxAreaIdx).Centroid;
        conf = 1 - minVal;
    else
        foveaCenter = [minX, minY];
        conf = 0.5;
    end
    
    foveaResult.center = foveaCenter;
    foveaResult.confidence = conf;
    foveaResult.searchRegionMask = searchMask;
end
