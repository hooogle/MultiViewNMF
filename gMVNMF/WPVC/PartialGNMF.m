function [finalU, finalV, finalcentroidV, weights, log] = PartialGNMF(X, K, W, map, invMap, label, options)
%	Notation:
% 	X ... a cell containing all views for the data
% 	K ... number of hidden factors
% 	W ... weight matrix of the affinity graph 
% 	label ... ground truth labels
%   map ... Contain the mapping for each view to the corresponding data
%           point (An id between (1, totalDataPoints)). map{i} is the
%           mapping for the ith view
%   invMap ... The inverse mapping, invMap{j} represents the views which 
%           have the data point j.
%	Writen by Jialu Liu (jliu64@illinois.edu)
% 	Modified by Zhenfan Wang (zfwang@mail.dlut.edu.cn)
%   Further modified by Nishant Rai (nishantr AT iitk DOT ac.in)

%	References:
% 	J. Liu, C.Wang, J. Gao, and J. Han, ��Multi-view clustering via joint nonnegative matrix factorization,�� in Proc. SDM, Austin, Texas, May 2013, vol. 13, pp. 252�C260.
% 	Zhenfan Wang, Xiangwei Kong, Haiyan Fu, Ming Li, Yujia Zhang, FEATURE EXTRACTION VIA MULTI-VIEW NON-NEGATIVE MATRIX FACTORIZATION WITH LOCAL GRAPH REGULARIZATION, ICIP 2015.

% Weights represent the weights for each view (They are common for both the
% divergence with consensus and also the graph laplacian
% options.gamma represents the parameter for handling the weights
% options.beta is or handling the graph regularization term
% options.varWeight is 1 if we want to weights to be varied, otherise it's 0
% options.delta is the term for handling the consensus matrix

tic;
viewNum = length(X);
Rounds = options.rounds;
gamma = options.gamma;
beta = options.beta;
delta = options.delta;
numData = size(invMap, 2);

U = cell(1, viewNum);
V = cell(1, viewNum);
L = cell(1, viewNum);

log = 0;
ac=0;

%% Compute the graph laplacians
for i = 1:viewNum
    nSmp=size(X{i},2);
    if beta > 0
        Wtemp = beta*W{i};
        DCol = full(sum(Wtemp,2));
        D = spdiags(DCol,0,nSmp,nSmp);
        L{i} = D - Wtemp;
    else
        L{i} = [];
    end
end
%%

%% Initiliaze weights
weights(1:viewNum) = (1/viewNum);
%%

%% initialize basis and coefficient matrices, initialize on the basis of standard GNMF algorithm
tic;
Goptions.alpha = options.alpha*beta;
rand('twister',5489);
[U{1}, V{1}] = GNMF(X{1}, K, W{1}, Goptions);        %In this case, random inits take place
rand('twister',5489);
%printResult(V{1}, label, options.K, options.kmeans);        
for i = 2:viewNum
    [U{i}, V{i}] = GNMF(X{i}, K, W{i}, Goptions);
    rand('twister',5489);
    %printResult(V{i}, label, options.K, options.kmeans);
end
toc;
%%

for i = 1:viewNum
    [U{i}, V{i}] = Normalize(U{i}, V{i});
end

optionsForPerViewNMF = options;
oldac=0;
maxac=0;
j = 0;
sumRound=0;
while j < Rounds
    sumRound=sumRound+1;
    j = j + 1;

    %Update consensus matrix
    centroidV = zeros(numData, K);
    for i=1:numData
        sumID = 0;
        for j=1:size(invMap{i},1)
            id = invMap{i}(j,1);
            row = invMap{i}(j,2);
            centroidV(i,:) = centroidV(i,:) + ((weights(id)^gamma)*delta)*V{id}(row,:);
            sumID = sumID + (weights(id)^gamma)*delta;
        end
        centroidV(i,:) = centroidV(i,:)/sumID;
    end
    
    %Update the weights if the corresponding option is set
    if (options.varWeight > 0)
        H = [];
        for i = 1:viewNum
            tmp1 = (X{i} - U{i}*V{i}');
            tmp2 = (V{i} - centroidV(map{i},:));
            val = gamma*(sum(sum(tmp1.^2))+delta*(sum(sum(tmp2.^2)))+sum(sum((V{i}'*L{i}).*V{i}')));  
            val = val^(1.0/(1-gamma));
            H(end+1) = val;
        end
        tmpSum = sum(H);
        weights = (H./tmpSum);    
    end
    
    %for i=1:viewNum
    %    fprintf('%.3f ',weights(i));
    %end
    %fprintf(' weights: %d | ',j);
    
    %Compute the loss for the current values
    logL = 0;
    for i = 1:viewNum
        alpha = weights(i)^gamma;
        tmp1 = (X{i} - U{i}*V{i}');
        tmp2 = (V{i} - centroidV(map{i},:));
        logL = logL + alpha*(sum(sum(tmp1.^2)) + delta*(sum(sum(tmp2.^2))) + sum(sum((V{i}'*L{i}).*V{i}')));
    end
    fprintf('LOG %.9f, ',logL);
    
    %logL
    log(end+1)=logL;
    rand('twister',5489);
    ac = ComputeStats(centroidV, label, options.K, 5, 2);
    if ac>oldac
        tempac=ac;
        tempU=U;
        tempV=V;
        tempcentroidV=centroidV;

    elseif oldac>maxac
        maxac=oldac;
        maxU=tempU;
        maxV=tempV;
        maxcentroidV=tempcentroidV;
    end
    oldac=ac;
    if(tempac>maxac)
        finalU=tempU;
        finalV=tempV;
        finalcentroidV=tempcentroidV;

    else
        finalU=maxU;
        finalV=maxV;
        finalcentroidV=maxcentroidV;
    end
    
    if sumRound==Rounds
        break;
    end
    
    %Update the individual view, the weights do not have any role here
    for i = 1:viewNum
        rand('twister',5489);
        [U{i}, V{i}] = PartialViewNMF(X{i}, K, centroidV, W{i}, map{i}, optionsForPerViewNMF, finalU{i}, finalV{i}); 
    end
    
end
toc

norm_mat = repmat(sqrt(sum(centroidV.*centroidV,2)),1,size(centroidV,2));
%%avoid divide by zero
for i=1:size(norm_mat,1)
    if (norm_mat(i,1)==0)
        norm_mat(i,:) = 1;
    end
end
centroidV = centroidV./norm_mat;

function [U, V] = Normalize(U, V)
    [U,V] = NormalizeUV(U, V, 0, 1);

function [U, V] = NormalizeUV(U, V, NormV, Norm)
    nSmp = size(V,1);
    mFea = size(U,1);
    if Norm == 2
        if NormV
            norms = sqrt(sum(V.^2,1));
            norms = max(norms,1e-10);
            V = V./repmat(norms,nSmp,1);
            U = U.*repmat(norms,mFea,1);
        else
            norms = sqrt(sum(U.^2,1));
            norms = max(norms,1e-10);
            U = U./repmat(norms,mFea,1);
            V = V.*repmat(norms,nSmp,1);
        end
    else
        if NormV
            norms = sum(abs(V),1);
            norms = max(norms,1e-10);
            V = V./repmat(norms,nSmp,1);
            U = U.*repmat(norms,mFea,1);
        else
            norms = sum(abs(U),1);
            norms = max(norms,1e-10);
            U = U./repmat(norms,mFea,1);
            V = bsxfun(@times, V, norms);
        end
    end