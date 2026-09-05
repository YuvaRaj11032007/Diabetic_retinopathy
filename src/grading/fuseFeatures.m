function fusedResult = fuseFeatures(clinicalFeatures, deepFeatures, options)
%FUSEFEATURES Concatenate clinical and deep features, optionally applying PCA.
%
%   fusedResult = FUSEFEATURES(clinicalFeatures, deepFeatures)
%   fusedResult = FUSEFEATURES(clinicalFeatures, deepFeatures, 'Name', Value)
%
%   Inputs:
%       clinicalFeatures - NxD_c numeric matrix of clinical features.
%       deepFeatures     - NxD_d numeric matrix of deep features.
%       options          - Name-Value arguments:
%           'UsePCA'            - (logical) Apply PCA. Default true.
%           'ExplainedVariance' - (numeric) Fraction of variance to retain. Default 0.95.
%           'Standardize'       - (logical) Standardize features before PCA. Default true.
%
%   Outputs:
%       fusedResult - Struct containing:
%           fusedMatrix         - NxD_fused numeric matrix of combined (and PCA-reduced) features
%           pcaCoeffs           - PCA coefficients (empty if PCA not used)
%           featureMean         - Mean used for centering (empty if PCA not used)
%           featureStd          - Standard deviation used for scaling (empty if Standardize false)
%           nComponentsRetained - Number of PCA components kept
%
%   Example:
%       clinicalFeats = rand(100, 14);
%       deepFeats = rand(100, 2048);
%       out = fuseFeatures(clinicalFeats, deepFeats, 'UsePCA', true, 'ExplainedVariance', 0.95);

    arguments
        clinicalFeatures (:,:) double {mustBeReal, mustBeFinite}
        deepFeatures (:,:) double {mustBeReal, mustBeFinite}
        options.UsePCA (1,1) logical = true
        options.ExplainedVariance (1,1) double {mustBeGreaterThan(options.ExplainedVariance, 0), mustBeLessThanOrEqual(options.ExplainedVariance, 1)} = 0.95
        options.Standardize (1,1) logical = true
    end
    
    if size(clinicalFeatures, 1) ~= size(deepFeatures, 1)
        error('DRPipeline:fuseFeatures:SizeMismatch', ...
            'Number of observations (rows) in clinicalFeatures and deepFeatures must match.');
    end
    
    % Concatenate features
    concatFeatures = [clinicalFeatures, deepFeatures];
    
    % Initialize output struct
    fusedResult.fusedMatrix = concatFeatures;
    fusedResult.pcaCoeffs = [];
    fusedResult.featureMean = [];
    fusedResult.featureStd = [];
    fusedResult.nComponentsRetained = size(concatFeatures, 2);
    
    % PCA requires at least 2 samples to fit
    if options.UsePCA && size(concatFeatures, 1) > 1
        % Calculate Mean
        mu = mean(concatFeatures, 1);
        fusedResult.featureMean = mu;
        
        % Standardize if requested
        if options.Standardize
            sigma = std(concatFeatures, 0, 1);
            sigma(sigma == 0) = 1; % Prevent division by zero
            fusedResult.featureStd = sigma;
            centeredData = (concatFeatures - mu) ./ sigma;
        else
            centeredData = concatFeatures - mu;
        end
        
        % Apply PCA (using pca if available, else native SVD)
        if exist('pca', 'file') == 2
            [coeff, score, ~, ~, explained] = pca(centeredData, 'Algorithm', 'svd', 'Economy', true);
            cumulativeVar = cumsum(explained) / 100;
            nComponents = find(cumulativeVar >= options.ExplainedVariance, 1);
            if isempty(nComponents), nComponents = length(cumulativeVar); end
            
            fusedResult.fusedMatrix = score(:, 1:nComponents);
            fusedResult.pcaCoeffs = coeff(:, 1:nComponents);
            fusedResult.nComponentsRetained = nComponents;
        else
            % Native SVD fallback (no toolbox required)
            [~, S, V] = svd(centeredData, 'econ');
            singularVals = diag(S);
            explained = (singularVals.^2) / sum(singularVals.^2);
            cumulativeVar = cumsum(explained);
            nComponents = find(cumulativeVar >= options.ExplainedVariance, 1);
            if isempty(nComponents), nComponents = length(cumulativeVar); end
            
            coeff = V;
            score = centeredData * V;
            fusedResult.fusedMatrix = score(:, 1:nComponents);
            fusedResult.pcaCoeffs = coeff(:, 1:nComponents);
            fusedResult.nComponentsRetained = nComponents;
        end
    else
        % N = 1 or UsePCA = false: retain concatenated feature vector directly
        fusedResult.fusedMatrix = concatFeatures;
        fusedResult.pcaCoeffs = [];
        fusedResult.nComponentsRetained = size(concatFeatures, 2);
    end
end
