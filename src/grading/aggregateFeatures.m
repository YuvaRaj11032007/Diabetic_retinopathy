function featuresStruct = aggregateFeatures(segResult, foveaLocation)
%AGGREGATEFEATURES Extract clinical feature vector from segmentation results.
%
%   featuresStruct = AGGREGATEFEATURES(segResult, foveaLocation)
%
%   Inputs:
%       segResult - Struct containing segmentation results with fields such as
%                   MACount, HardExudateArea, HardExudatesMask, SoftExudateCount,
%                   HemorrhageCount, HemorrhageArea, DotBlotCount, FlameCount,
%                   NVDProbability, NVDFlag, VesselDensity, VesselTortuosity,
%                   VesselBranchPoints, FundusArea.
%       foveaLocation - 1x2 numeric array [x, y] of fovea center coordinates.
%
%   Outputs:
%       featuresStruct - Struct containing 'vector' (1xD normalized feature vector)
%                        and named fields for each extracted clinical feature.
%
%   Example:
%       segRes.MACount = 12;
%       segRes.FundusArea = 50000;
%       fovea = [256, 256];
%       feats = aggregateFeatures(segRes, fovea);

    arguments
        segResult (1,1) struct
        foveaLocation (1,2) double {mustBeReal, mustBeFinite}
    end
    
    % Initialize default values for features
    feat.maCount = 0;
    feat.maDensity = 0;
    feat.hardExudateArea = 0;
    feat.hardExudateDistFovea = 1000; % Default large distance
    feat.softExudateCount = 0;
    feat.hemorrhageCount = 0;
    feat.hemorrhageArea = 0;
    feat.dotBlotCount = 0;
    feat.flameCount = 0;
    feat.nvdProbability = 0;
    feat.nvdFlag = 0;
    feat.vesselDensity = 0;
    feat.vesselTortuosity = 0;
    feat.vesselBranchPoints = 0;
    
    % 1. MA Count
    if isfield(segResult, 'MACount')
        feat.maCount = segResult.MACount;
    else
        warning('DRPipeline:aggregateFeatures:MissingField', 'MACount missing in segResult.');
    end
    
    % 2. MA Density
    if isfield(segResult, 'FundusArea') && segResult.FundusArea > 0
        feat.maDensity = feat.maCount / segResult.FundusArea;
    elseif isfield(segResult, 'FundusArea')
        warning('DRPipeline:aggregateFeatures:InvalidArea', 'FundusArea is 0 or missing.');
    end
    
    % 3. Hard Exudate Area
    if isfield(segResult, 'HardExudateArea')
        feat.hardExudateArea = segResult.HardExudateArea;
    end
    
    % 4. Hard exudate distance to fovea
    if isfield(segResult, 'HardExudatesMask') && any(segResult.HardExudatesMask(:))
        [r, c] = find(segResult.HardExudatesMask);
        distances = sqrt((c - foveaLocation(1)).^2 + (r - foveaLocation(2)).^2);
        feat.hardExudateDistFovea = min(distances);
    end
    
    % 5. Soft exudate count
    if isfield(segResult, 'SoftExudateCount')
        feat.softExudateCount = segResult.SoftExudateCount;
    end
    
    % 6. Hemorrhage count
    if isfield(segResult, 'HemorrhageCount')
        feat.hemorrhageCount = segResult.HemorrhageCount;
    end
    
    % 7. Hemorrhage area
    if isfield(segResult, 'HemorrhageArea')
        feat.hemorrhageArea = segResult.HemorrhageArea;
    end
    
    % 8. Dot/blot hemorrhage count
    if isfield(segResult, 'DotBlotCount')
        feat.dotBlotCount = segResult.DotBlotCount;
    end
    
    % 9. Flame hemorrhage count
    if isfield(segResult, 'FlameCount')
        feat.flameCount = segResult.FlameCount;
    end
    
    % 10. Neovascularization probability
    if isfield(segResult, 'NVDProbability')
        feat.nvdProbability = segResult.NVDProbability;
    end
    
    % 11. NVD flag
    if isfield(segResult, 'NVDFlag')
        feat.nvdFlag = segResult.NVDFlag;
    end
    
    % 12. Vessel density
    if isfield(segResult, 'VesselDensity')
        feat.vesselDensity = segResult.VesselDensity;
    end
    
    % 13. Vessel tortuosity
    if isfield(segResult, 'VesselTortuosity')
        feat.vesselTortuosity = segResult.VesselTortuosity;
    end
    
    % 14. Vessel branch points
    if isfield(segResult, 'VesselBranchPoints')
        feat.vesselBranchPoints = segResult.VesselBranchPoints;
    end
    
    % Creating the raw vector
    rawVector = [ ...
        feat.maCount, ...
        feat.maDensity, ...
        feat.hardExudateArea, ...
        feat.hardExudateDistFovea, ...
        feat.softExudateCount, ...
        feat.hemorrhageCount, ...
        feat.hemorrhageArea, ...
        feat.dotBlotCount, ...
        feat.flameCount, ...
        feat.nvdProbability, ...
        feat.nvdFlag, ...
        feat.vesselDensity, ...
        feat.vesselTortuosity, ...
        feat.vesselBranchPoints ...
    ];

    % Empirical max values for normalization [0, 1]
    empiricalMax = [ ...
        100, ...      % maCount
        0.001, ...    % maDensity
        10000, ...    % hardExudateArea
        2000, ...     % hardExudateDistFovea
        50, ...       % softExudateCount
        50, ...       % hemorrhageCount
        20000, ...    % hemorrhageArea
        30, ...       % dotBlotCount
        20, ...       % flameCount
        1.0, ...      % nvdProbability
        1.0, ...      % nvdFlag
        0.2, ...      % vesselDensity
        1.5, ...      % vesselTortuosity
        300 ...       % vesselBranchPoints
    ];
    
    normVector = min(rawVector ./ empiricalMax, 1.0); % Cap at 1.0
    
    featuresStruct = feat;
    featuresStruct.vector = normVector;
end
