classdef test_utils < matlab.unittest.TestCase
    %TEST_UTILS Unit tests for Common Utilities Library
    
    properties
        TestDir
        SampleImagePath
    end
    
    methods(TestMethodSetup)
        function createSampleData(testCase)
            testCase.TestDir = fullfile(tempdir, 'DRPipelineTests');
            if ~isfolder(testCase.TestDir)
                mkdir(testCase.TestDir);
            end
            
            % Create a synthetic color fundus image
            img = uint8(zeros(100, 100, 3));
            img(25:75, 25:75, 1) = 150; % Redish
            img(25:75, 25:75, 2) = 50;  % Greenish
            img(25:75, 25:75, 3) = 20;  % Blueish
            
            testCase.SampleImagePath = fullfile(testCase.TestDir, 'sample_fundus.jpg');
            imwrite(img, testCase.SampleImagePath);
        end
    end
    
    methods(TestMethodTeardown)
        function removeSampleData(testCase)
            if isfolder(testCase.TestDir)
                rmdir(testCase.TestDir, 's');
            end
        end
    end
    
    methods(Test)
        
        % loadFundusImage tests
        function testLoadFundusImage_Normal(testCase)
            [img, meta] = loadFundusImage(testCase.SampleImagePath);
            testCase.verifyEqual(size(img), [100, 100, 3]);
            testCase.verifyEqual(meta.width, 100);
            testCase.verifyEqual(meta.height, 100);
            testCase.verifyEqual(meta.channels, 3);
        end
        
        function testLoadFundusImage_Resize(testCase)
            [img, meta] = loadFundusImage(testCase.SampleImagePath, [50, 50]);
            testCase.verifyEqual(size(img), [50, 50, 3]);
            testCase.verifyEqual(meta.width, 50);
            testCase.verifyEqual(meta.height, 50);
        end
        
        function testLoadFundusImage_GrayscaleError(testCase)
            grayPath = fullfile(testCase.TestDir, 'gray.jpg');
            imwrite(uint8(zeros(100, 100)), grayPath);
            testCase.verifyError(@() loadFundusImage(grayPath), 'DRPipeline:utils:InvalidChannels');
        end
        
        % createCircularROI tests
        function testCreateCircularROI_SizeInput(testCase)
            [mask, params] = createCircularROI([100, 100]);
            testCase.verifyEqual(size(mask), [100, 100]);
            testCase.verifyEqual(params(1), 50); % cx
            testCase.verifyEqual(params(2), 50); % cy
        end
        
        function testCreateCircularROI_ImageInput(testCase)
            img = zeros(100, 100, 3, 'uint8');
            [X, Y] = meshgrid(1:100, 1:100);
            circleMask = (X - 50).^2 + (Y - 50).^2 <= 30^2;
            img(repmat(circleMask, [1, 1, 3])) = 200;
            
            [mask, params] = createCircularROI(img);
            testCase.verifyEqual(size(mask), [100, 100]);
            % Auto-detected radius should be around 30
            testCase.verifyEqual(params(3), 30, 'RelTol', 5);
        end
        
        % computeMetrics tests
        function testComputeMetrics_Binary(testCase)
            gt = [0; 1; 1; 0; 1];
            pred = [0; 1; 0; 0; 1];
            metrics = computeMetrics(gt, pred);
            
            testCase.verifyEqual(metrics.accuracy, 0.8);
            testCase.verifyEqual(metrics.sensitivity, 2/3); % TP=2, FN=1
            testCase.verifyEqual(metrics.specificity, 2/2); % TN=2, FP=0
        end
        
        function testComputeMetrics_EmptyProbabilities(testCase)
            gt = [0; 1];
            pred = [0; 1];
            metrics = computeMetrics(gt, pred);
            testCase.verifyTrue(isnan(metrics.AUC));
        end
        
        function testComputeMetrics_AUC(testCase)
            gt = [0; 1; 1; 0; 1];
            pred = [0; 1; 0; 0; 1];
            probs = [0.1; 0.9; 0.4; 0.2; 0.8];
            metrics = computeMetrics(gt, pred, probs);
            testCase.verifyFalse(isnan(metrics.AUC));
        end
        
        % overlayHeatmap tests
        function testOverlayHeatmap_OutputSize(testCase)
            img = uint8(zeros(100, 100, 3));
            hm = rand(100, 100);
            res = overlayHeatmap(img, hm, 0.5);
            testCase.verifyEqual(size(res), [100, 100, 3]);
            testCase.verifyClass(res, 'uint8');
        end
        
        function testOverlayHeatmap_ResizeHeatmap(testCase)
            img = uint8(zeros(100, 100, 3));
            hm = rand(50, 50); % Different size
            res = overlayHeatmap(img, hm, 0.5);
            testCase.verifyEqual(size(res), [100, 100, 3]);
        end
        
        function testOverlayHeatmap_NaNError(testCase)
            img = uint8(zeros(100, 100, 3));
            hm = ones(100, 100);
            hm(1,1) = NaN; % Invalid value for mustBeInRange
            testCase.verifyError(@() overlayHeatmap(img, hm, 0.5), 'MATLAB:validators:mustBeInRange');
        end
        
        % saveFigureReport tests
        function testSaveFigureReport_CreateDir(testCase)
            fig = figure('Visible', 'off');
            plot(1:10);
            outPath = fullfile(testCase.TestDir, 'newdir', 'testfig.png');
            saveFigureReport(outPath);
            testCase.verifyTrue(isfile(outPath));
            close(fig);
        end
        
        function testSaveFigureReport_InvalidFormat(testCase)
            outPath = fullfile(testCase.TestDir, 'testfig.txt');
            testCase.verifyError(@() saveFigureReport(outPath, 300, 'txt'), 'DRPipeline:utils:InvalidFormat');
        end
        
        % rgb2green tests
        function testRgb2green_Extract(testCase)
            img = uint8(zeros(10, 10, 3));
            img(:,:,2) = 125;
            g = rgb2green(img);
            testCase.verifyEqual(size(g), [10, 10]);
            testCase.verifyEqual(g(1,1), uint8(125));
        end
        
        function testRgb2green_NotRgbError(testCase)
            img = uint8(zeros(10, 10, 2));
            testCase.verifyError(@() rgb2green(img), 'DRPipeline:utils:NotRGB');
        end
        
        % normalizeIllumination tests
        function testNormalizeIllumination_Stub(testCase)
            img = zeros(10, 10);
            testCase.verifyWarning(@() normalizeIllumination(img), 'DRPipeline:utils:StubFunction');
            
            % Should return unchanged
            [~, lastWarnId] = lastwarn;
            warning('off', 'DRPipeline:utils:StubFunction');
            res = normalizeIllumination(img);
            warning('on', 'DRPipeline:utils:StubFunction');
            testCase.verifyEqual(res, img);
        end
        
    end
end
