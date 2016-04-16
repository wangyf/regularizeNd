function [ yGrid, xGrid] = regularizeNdEven(x, y, xGridMin, xGridMax, nGrid, smoothness, interpMethod)
%regularizeNd  Produces a smooth nD gridded surface from scattered input data.
% 

%% Input Checking
narginchk(5, 7);

% helper function used mostly for when variables are renamed
getname = @(x) inputname(1);

% Check dimensions
nDimensions = size(x,2);
assert(nDimensions == numel(xGridMin) & nDimensions == numel(xGridMax) & nDimensions == numel(nGrid),'The length of %s, %s, and %s should be the same as the number of rows in %s',getname(xGridMin), getname(xGridMax), getname(nGrid), getname(x));
assert(isvector(xGridMin) & isvector(xGridMax) & isvector(nGrid),'%s, %s, and %s must vectors', getname(xGridMin), getname(xGridMax), getname(nGrid));
nScatteredPoints = size(x,1);
assert( nScatteredPoints == size(y, 1), '%s must have same number of rows as %s',getname(x), getname(y));
xGridMin = reshape(xGridMin,1,[]);
xGridMax = reshape(xGridMax,1,[]);
nGrid = reshape(nGrid,1,[]);

% Check input points are within min and max of grid
assert(all(all(bsxfun(@ge, x, xGridMin))) & all(all(bsxfun(@le, x, xGridMax))), 'All %s points must be within the range of %s to %s', getname(x), getname(xGridMin), getname(xGridMax));


% check smoothness parameter
if ~isscalar(smoothness)
    assert(nDimensions == numel(smoothness), 'If %s is not a scalar, then it must have same number of elements as %s has columns.', getname(smoothness), getname(x));
    smoothness = reshape(smoothness,1, []);
else
    smoothness = smoothness*ones(1, nDimensions);
end

% check interp method
if isa(interpMethod, 'function_handle')
    interp = interpMethod;
elseif strcmpi(interpMethod, 'linear')
    interp = @linear;
elseif strcmpi(interpMethod, 'cubic')
    interp = @cubic;
elseif strcmpi(interpMethod, 'nearest')
    interp = @nearest;
else
    error('%s must be ''cubic'', ''linear'', ''nearest'', or a custom interp function_handle', getname(interpMethod));
end

%% Begin Calculations
[index, weights] = interp(x,y,xGridMin,xGridMax, nGrid);

end

%%
function [index, weight] = linear(x,y,xGridMin,xGridMax, nGrid)
dx = (xGridMax - xGridMin)./nGrid;
fractionalIndex = bsxfunbsxfun(@rdivide,  bsxfun(@minus, x, xGridMin), dx);
lowerIndex = fix(fractionalIndex);
fraction = fractionalIndex - lowerIndex;
end
