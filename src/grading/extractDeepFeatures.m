function out = extractDeepFeatures(mode, varargin)
%EXTRACTDEEPFEATURES Deep learning feature extraction and backbone fine-tuning.
%
%   model = EXTRACTDEEPFEATURES('train', imageDir, labelsTable, options)
%   features = EXTRACTDEEPFEATURES('extract', images, model)
%
%   Mode 1: 'train'
%       Fine-tunes a pretrained CNN backbone (ResNet-50) for DR grading.
%       Inputs:
%           imageDir    - String or char array. Path to directory containing training images.
%           labelsTable - Table. Must contain 'FileName' and 'Label' (categorical) columns.
%           options     - Struct (optional). Training configurations.
%       Outputs:
%           model       - Struct with fields 'network', 'trainingInfo', 'featureLayerName'.
%
%   Mode 2: 'extract'
%       Extracts penultimate layer features from images.
%       Inputs:
%           images - Single image (HxWx3), imageDatastore, or cell array of paths.
%           model  - Model struct returned by 'train' mode or containing fields 'network', 'featureLayerName'.
%       Outputs:
%           features - Nx2048 numeric matrix of extracted features.
%
%   Examples:
%       % Train mode
%       opts.MaxEpochs = 30;
%       model = extractDeepFeatures('train', 'data/train', labelsTable, opts);
%       
%       % Extract mode
%       img = imread('test.jpg');
%       feat = extractDeepFeatures('extract', img, model);

    arguments
        mode (1,:) char {mustBeMember(mode, {'train', 'extract'})}
    end
    arguments (Repeating)
        varargin
    end
    
    switch mode
        case 'train'
            if nargin < 3
                error('DRPipeline:extractDeepFeatures:NotEnoughInputs', ...
                    'Train mode requires at least imageDir and labelsTable inputs.');
            end
            imageDir = varargin{1};
            labelsTable = varargin{2};
            if nargin >= 4
                options = varargin{3};
            else
                options = struct();
            end
            out = runTraining(imageDir, labelsTable, options);
            
        case 'extract'
            if nargin < 3
                error('DRPipeline:extractDeepFeatures:NotEnoughInputs', ...
                    'Extract mode requires images and model inputs.');
            end
            images = varargin{1};
            model = varargin{2};
            out = runExtraction(images, model);
    end
end

function model = runTraining(imageDir, labelsTable, options)
    % Validate inputs
    validateattributes(imageDir, {'char', 'string'}, {'scalartext'}, 'extractDeepFeatures', 'imageDir');
    validateattributes(labelsTable, {'table'}, {'nonempty'}, 'extractDeepFeatures', 'labelsTable');
    if ~ismember('FileName', labelsTable.Properties.VariableNames) || ...
       ~ismember('Label', labelsTable.Properties.VariableNames)
        error('DRPipeline:extractDeepFeatures:InvalidTable', ...
            'labelsTable must contain ''FileName'' and ''Label'' columns.');
    end
    
    % Ensure labels are categorical
    if ~iscategorical(labelsTable.Label)
        labelsTable.Label = categorical(labelsTable.Label);
    end
    numClasses = numel(categories(labelsTable.Label));
    
    % Create image datastore
    filePaths = fullfile(string(imageDir), string(labelsTable.FileName));
    imds = imageDatastore(filePaths, 'Labels', labelsTable.Label);
    
    % Split into train and validation (80-20 split)
    [imdsTrain, imdsVal] = splitEachLabel(imds, 0.8, 'randomized');
    
    % Load Pretrained ResNet-50
    try
        net = resnet50;
    catch
        error('DRPipeline:extractDeepFeatures:MissingNetwork', ...
            'ResNet-50 is not installed. Please install Deep Learning Toolbox Model for ResNet-50 Network.');
    end
    lgraph = layerGraph(net);
    
    % Freeze early layers (first 40 layers)
    layers = lgraph.Layers;
    for i = 1:min(40, numel(layers))
        if isprop(layers(i), 'WeightLearnRateFactor')
            layers(i).WeightLearnRateFactor = 0;
            layers(i).BiasLearnRateFactor = 0;
        end
    end
    
    % Replace the final fully-connected layer
    % In resnet50, the fc layer is named 'fc1000' and classification layer is 'ClassificationLayer_fc1000'
    newFCLayer = fullyConnectedLayer(numClasses, ...
        'Name', 'new_fc', ...
        'WeightLearnRateFactor', 10, ...
        'BiasLearnRateFactor', 10);
    lgraph = replaceLayer(lgraph, 'fc1000', newFCLayer);
    
    newClassLayer = classificationLayer('Name', 'new_classoutput');
    lgraph = replaceLayer(lgraph, 'ClassificationLayer_fc1000', newClassLayer);
    
    % Data Augmentation
    imageSize = net.Layers(1).InputSize;
    augmenter = imageDataAugmenter( ...
        'RandRotation', [-15, 15], ...
        'RandXReflection', true, ...
        'RandXTranslation', [-10 10], ...
        'RandYTranslation', [-10 10]);
    
    augimdsTrain = augmentedImageDatastore(imageSize, imdsTrain, 'DataAugmentation', augmenter);
    augimdsVal = augmentedImageDatastore(imageSize, imdsVal);
    
    % Training Options
    miniBatchSize = 32;
    if isfield(options, 'MiniBatchSize')
        miniBatchSize = options.MiniBatchSize;
    end
    maxEpochs = 30;
    if isfield(options, 'MaxEpochs')
        maxEpochs = options.MaxEpochs;
    end
    
    opts = trainingOptions('sgdm', ...
        'MiniBatchSize', miniBatchSize, ...
        'MaxEpochs', maxEpochs, ...
        'InitialLearnRate', 1e-4, ...
        'LearnRateSchedule', 'piecewise', ...
        'LearnRateDropFactor', 0.1, ...
        'LearnRateDropPeriod', 10, ...
        'L2Regularization', 1e-4, ...
        'ValidationData', augimdsVal, ...
        'ValidationFrequency', floor(numel(imdsTrain.Files)/miniBatchSize), ...
        'ValidationPatience', 5, ...
        'Plots', 'none', ...
        'Verbose', false);
    
    % Train the Network
    [trainedNet, trainInfo] = trainNetwork(augimdsTrain, lgraph, opts);
    
    % Package Output
    model.network = trainedNet;
    model.trainingInfo = trainInfo;
    model.featureLayerName = 'avg_pool';
end

function features = runExtraction(images, model)
    validateattributes(model, {'struct'}, {'nonempty'}, 'extractDeepFeatures', 'model');
    if ~isfield(model, 'network') || ~isfield(model, 'featureLayerName')
        error('DRPipeline:extractDeepFeatures:InvalidModel', ...
            'Model struct must contain ''network'' and ''featureLayerName''.');
    end
    
    net = model.network;
    layerName = model.featureLayerName;
    
    imageSize = net.Layers(1).InputSize(1:2);
    
    % Process the input format
    if ischar(images) || isstring(images)
        images = cellstr(images);
    end
    
    if iscellstr(images) || iscell(images)
        imds = imageDatastore(images);
        augimds = augmentedImageDatastore(imageSize, imds, 'ColorPreprocessing', 'gray2rgb');
        features = activations(net, augimds, layerName, 'MiniBatchSize', 64, 'OutputAs', 'rows');
        
    elseif isa(images, 'matlab.io.datastore.ImageDatastore')
        augimds = augmentedImageDatastore(imageSize, images, 'ColorPreprocessing', 'gray2rgb');
        features = activations(net, augimds, layerName, 'MiniBatchSize', 64, 'OutputAs', 'rows');
        
    elseif isnumeric(images)
        % Single image or batch of images
        if ndims(images) == 3 && size(images, 3) == 3
            % Single RGB image
            img = imresize(images, imageSize);
            features = activations(net, img, layerName, 'OutputAs', 'rows');
        elseif ndims(images) == 4
            % Batch of images
            numImages = size(images, 4);
            imgBatch = zeros([imageSize, 3, numImages], class(images));
            for i = 1:numImages
                imgBatch(:,:,:,i) = imresize(images(:,:,:,i), imageSize);
            end
            features = activations(net, imgBatch, layerName, 'MiniBatchSize', 64, 'OutputAs', 'rows');
        else
            % Single Grayscale image maybe
            if ismatrix(images)
                img = repmat(images, [1 1 3]);
                img = imresize(img, imageSize);
                features = activations(net, img, layerName, 'OutputAs', 'rows');
            else
                error('DRPipeline:extractDeepFeatures:InvalidImageArray', ...
                    'Numeric image input must be HxWx3 or HxWx3xN.');
            end
        end
    else
        error('DRPipeline:extractDeepFeatures:InvalidInput', ...
            'Images input must be an image array, cell array of paths, or imageDatastore.');
    end
end
