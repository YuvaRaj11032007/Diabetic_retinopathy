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
    
    vars = labelsTable.Properties.VariableNames;
    
    % Find file path column (flexible)
    fileCol = '';
    for v = {'filepath', 'FilePath', 'FileName', 'filename', 'image_id', 'id_code'}
        if ismember(v{1}, vars)
            fileCol = v{1};
            break;
        end
    end
    if isempty(fileCol)
        error('DRPipeline:extractDeepFeatures:InvalidTable', ...
            'labelsTable must contain ''filepath'', ''FileName'', or ''image_id'' column.');
    end
    
    % Find label column (flexible)
    labelCol = '';
    for v = {'dr_grade', 'Label', 'label', 'diagnosis', 'level'}
        if ismember(v{1}, vars)
            labelCol = v{1};
            break;
        end
    end
    if isempty(labelCol)
        error('DRPipeline:extractDeepFeatures:InvalidTable', ...
            'labelsTable must contain ''dr_grade'' or ''Label'' column.');
    end
    
    % Filter out unannotated (NaN) images
    validMask = ~isnan(double(labelsTable.(labelCol)));
    subTable = labelsTable(validMask, :);
    
    % Resolve file paths on disk
    rawPaths = string(subTable.(fileCol));
    resolvedPaths = strings(height(subTable), 1);
    existsMask = false(height(subTable), 1);
    
    for i = 1:height(subTable)
        p = rawPaths(i);
        if isfile(p)
            resolvedPaths(i) = p;
            existsMask(i) = true;
        elseif isfile(fullfile(string(imageDir), p))
            resolvedPaths(i) = fullfile(string(imageDir), p);
            existsMask(i) = true;
        elseif isfile(fullfile(string(imageDir), "train_images", p))
            resolvedPaths(i) = fullfile(string(imageDir), "train_images", p);
            existsMask(i) = true;
        elseif isfile(fullfile(string(imageDir), p + ".png"))
            resolvedPaths(i) = fullfile(string(imageDir), p + ".png");
            existsMask(i) = true;
        elseif isfile(fullfile(string(imageDir), "train_images", p + ".png"))
            resolvedPaths(i) = fullfile(string(imageDir), "train_images", p + ".png");
            existsMask(i) = true;
        end
    end
    
    if ~any(existsMask)
        error('DRPipeline:extractDeepFeatures:ImagesNotFound', ...
            'None of the images listed in the table could be found in "%s".', imageDir);
    end
    
    subTable = subTable(existsMask, :);
    resolvedPaths = resolvedPaths(existsMask);
    labels = categorical(subTable.(labelCol));
    
    fprintf('[DeepFeatures] Indexed %d valid training images across %d classes.\n', ...
        height(subTable), numel(categories(labels)));
    
    % Datastores: use 'split' column if present
    if ismember('split', subTable.Properties.VariableNames) && any(subTable.split == "train")
        trainMask = subTable.split == "train";
        valMask   = subTable.split == "val";
        if ~any(valMask)
            % Fallback if val split empty
            [imdsTrain, imdsVal] = splitEachLabel(imageDatastore(resolvedPaths, 'Labels', labels), 0.8, 'randomized');
        else
            imdsTrain = imageDatastore(resolvedPaths(trainMask), 'Labels', labels(trainMask));
            imdsVal   = imageDatastore(resolvedPaths(valMask),   'Labels', labels(valMask));
        end
    else
        imds = imageDatastore(resolvedPaths, 'Labels', labels);
        [imdsTrain, imdsVal] = splitEachLabel(imds, 0.8, 'randomized');
    end
    
    numClasses = numel(categories(labels));
    
    % Load Pretrained ResNet-50
    try
        net = resnet50;
    catch
        error('DRPipeline:extractDeepFeatures:MissingNetwork', ...
            'ResNet-50 is not installed. Please install "Deep Learning Toolbox Model for ResNet-50 Network" from Add-On Explorer.');
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
    miniBatchSize = 16;
    if isfield(options, 'MiniBatchSize'), miniBatchSize = options.MiniBatchSize; end
    
    maxEpochs = 15;
    if isfield(options, 'MaxEpochs'), maxEpochs = options.MaxEpochs; end
    
    valFreq = max(5, floor(numel(imdsTrain.Files) / miniBatchSize));
    
    plotsSetting = 'training-progress';
    if isfield(options, 'Plots'), plotsSetting = options.Plots; end
    
    opts = trainingOptions('sgdm', ...
        'MiniBatchSize', miniBatchSize, ...
        'MaxEpochs', maxEpochs, ...
        'InitialLearnRate', 1e-4, ...
        'LearnRateSchedule', 'piecewise', ...
        'LearnRateDropFactor', 0.1, ...
        'LearnRateDropPeriod', 10, ...
        'L2Regularization', 1e-4, ...
        'ValidationData', augimdsVal, ...
        'ValidationFrequency', valFreq, ...
        'ValidationPatience', 5, ...
        'Plots', plotsSetting, ...
        'Verbose', true);
    
    fprintf('[DeepFeatures] Starting ResNet-50 fine-tuning on %d images (BatchSize=%d, Epochs=%d)...\n', ...
        numel(imdsTrain.Files), miniBatchSize, maxEpochs);
    
    % Train the Network
    [trainedNet, trainInfo] = trainNetwork(augimdsTrain, lgraph, opts);
    
    % Package Output
    model.network = trainedNet;
    model.trainingInfo = trainInfo;
    model.featureLayerName = 'avg_pool';
    
    % Automatically save model to models/grading/backbone_finetuned.mat
    projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
    if isempty(projectRoot) || ~exist(projectRoot, 'dir')
        projectRoot = fileparts(fileparts(mfilename('fullpath')));
    end
    modelDir = fullfile(projectRoot, 'models', 'grading');
    if ~exist(modelDir, 'dir'), mkdir(modelDir); end
    savePath = fullfile(modelDir, 'backbone_finetuned.mat');
    save(savePath, '-struct', 'model');
    fprintf('[DeepFeatures] Model successfully fine-tuned and saved to:\n  %s\n', savePath);
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
