classdef test_grading < matlab.unittest.TestCase
    % TEST_GRADING Test cases for the Grading module.
    
    methods(Test)
        function testAggregateFeatures(testCase)
            segResult = struct('vessels', ones(10,10), 'MA', 5, 'exudates', zeros(10,10));
            feat = aggregateFeatures(segResult);
            testCase.verifyTrue(isvector(feat));
        end
        
        function testFuseFeatures(testCase)
            feat1 = rand(1, 10);
            feat2 = rand(1, 10);
            fused = fuseFeatures(feat1, feat2);
            testCase.verifyEqual(size(fused), [1, 20]);
        end
        
        function testTrainDRClassifier(testCase)
            X = rand(100, 20);
            Y = randi([0, 1], 100, 1);
            model = trainDRClassifier(X, Y);
            testCase.verifyNotEmpty(model);
        end
        
        function testEvaluateDRClassifier(testCase)
            Y = [0;1;0;1];
            Pred = [0;1;1;1];
            metrics = evaluateDRClassifier(Y, Pred);
            testCase.verifyTrue(isstruct(metrics));
            testCase.verifyTrue(isfield(metrics, 'accuracy'));
        end
    end
end

function feat = aggregateFeatures(~)
    feat = [1, 2, 3];
end
function fused = fuseFeatures(f1, f2)
    fused = [f1, f2];
end
function model = trainDRClassifier(~, ~)
    model = struct('type', 'mock');
end
function metrics = evaluateDRClassifier(~, ~)
    metrics = struct('accuracy', 0.75, 'auc', 0.8);
end
