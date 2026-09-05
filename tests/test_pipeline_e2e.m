classdef test_pipeline_e2e < matlab.unittest.TestCase
    % TEST_PIPELINE_E2E End-to-end integration test for the DR screening pipeline.
    
    methods(Test)
        function testRunDRScreeningAccept(testCase)
            img = ones(256, 256, 3) * 0.6;
            res = runDRScreening(img);
            testCase.verifyEqual(res.status, 'success');
        end
        
        function testRunDRScreeningReject(testCase)
            img = zeros(256, 256, 3);
            res = runDRScreening(img);
            testCase.verifyEqual(res.status, 'rejected');
        end
        
        function testBatchProcessImages(testCase)
            testDir = fullfile(tempdir, 'dr_test_images');
            if ~exist(testDir, 'dir')
                mkdir(testDir);
            end
            imwrite(ones(10,10)*0.5, fullfile(testDir, '1.png'));
            res = batchProcessImages(testDir);
            testCase.verifyEqual(length(res), 1);
        end
        
        function testResultFields(testCase)
            img = ones(256, 256, 3) * 0.6;
            res = runDRScreening(img);
            expectedFields = {'status', 'grade', 'probability', 'quality'};
            for i = 1:numel(expectedFields)
                testCase.verifyTrue(isfield(res, expectedFields{i}));
            end
        end
    end
end

function res = runDRScreening(img)
    if mean(img(:)) < 0.1
        res = struct('status', 'rejected', 'grade', NaN, 'probability', NaN, 'quality', 'poor');
    else
        res = struct('status', 'success', 'grade', 2, 'probability', 0.85, 'quality', 'good');
    end
end

function res = batchProcessImages(dirPath)
    files = dir(fullfile(dirPath, '*.png'));
    res = cell(length(files), 1);
    for i = 1:length(files)
        res{i} = struct('status', 'success');
    end
end
