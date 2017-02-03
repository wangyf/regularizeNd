function yGrid = regularizeNd(x, y, xGrid, smoothness, interpMethod, solver)
% regularizeNd  Produces a smooth nD surface from scattered input data.
%
%   yGrid = regularizeNd(x, y, xGrid)
%   yGrid = regularizeNd(x, y, xGrid, smoothness)
%   yGrid = regularizeNd(x, y, xGrid, smoothness, interpMethod)
%   yGrid = regularizeNd(x, y, xGrid, smoothness, interpMethod, solver)
%
%% Inputs
%      x - column vector or matrix of column vectors, containing scattered
%          data. Each row contains one point. Each column corresponds to a
%          dimension.
%
%      y - vector containing the corresponds values to x. y has the same
%          number of rows as x.
%
%  xGrid - cell array containing vectors defining the nodes in the grid in
%          each dimension. xGrid{1} corresponds with x(:,1) for instance.
%          Unequal spacing in the grid vectors is allowed. The grid vectors
%          must completely span x. For instance the values of x(:,1) must
%          be within the bounds of xGrid{1}. If xGrid does not span x,
%          an error is thrown. 
%
%  smoothness - scalar or vector. - The numerical "measure" of what we want
%          to achieve along an axis/dimension, regardless of the
%          resolution, the aspect ratio between axes, or the scale of the
%          overall problem. The ratio of smoothness to fidelity of the
%          output surface, a.k.a. ration of smoothness to "goodness of
%          fit." This must be a positive real number. If it is a vector, it
%          must have same number of elements as columns in x.
%
%          A smoothness of 1 gives equal weight to fidelity (goodness of fit)
%          and smoothness of the output surface.  This results in noticeable
%          smoothing.  If your input data has little or no noise, use
%          0.01 to give smoothness 1% as much weight as goodness of fit.
%          0.1 applies a little bit of smoothing to the output surface.
%
%          If this parameter is a vector, then it defines the relative
%          smoothing to be associated with each axis/dimension. This allows
%          the user to apply a different amount of smoothing in the each
%          axis/dimension.
%
%          DEFAULT: 0.01
%
%   interpMethod - character, denotes the interpolation scheme used
%          to interpolate the data.
%
%
%          'linear' - Uses linear interpolation within the grid
%
%          'nearest' - nearest neighbor interpolation. This will
%                     rarely be a good choice, but I included it
%                     as an option for completeness.
%
%          DEFAULT: 'linear'
%
%
%   solver - character flag - denotes the solver used for the
%          resulting linear system. The default is most often the best
%          choice.

%          What solver should you use? '\' may be best numerically for most
%          smoothness parameters and high extents of extrapolation.
%
%          Large numbers of points will slow down the direct \, but when
%          applied to the normal equations, \ can be quite fast. Since the
%          equations generated by this regularization method tends to be
%          well conditioned, the normal equations are not a bad choice of
%          method to use. Beware when a small smoothing parameter is used,
%          since this will make the equations less well conditioned. The
%          normal equation on fairly large grids is 3x faster than the \
%          alone.
%
%          '\' - uses matlab's backslash operator to solve the sparse
%                system.
%
%
%          'normal' - Constructs the normal equation and solves.
%                     x = (A'A)\(A'*y). From testing, this seems to be a well
%                     conditioned and faster way to solve this type of
%                     equation system than backslash x = A\y. Testing shows
%                     that the normal equation is 3x faster than the \
%                     solver for this type of problem. This isn't true in
%                     most other problem types and is a bit unusual.
%
%          DEFAULT: 'normal'
%
%
%
%% Output
%  yGrid   - array containing the fitted surface correspond to the grid
%            points xGrid.
%
%% Description
% regularizeNd answers the question what is the best possible lookup table
% that the scattered data x and y in the least squares sense with
% smoothing? regularizeNd is meant to calculate a smooth lookup table given
% n-D scattered data. regularizeNd supports extrapolation from a scattered
% data set.
%
% The calculated lookup table yGrid is meant to be used with
% griddedInterpolant class with the conservative memory form. Call
% griddedInterpolant like F = griddedInterpolant(xGrid, yGrid).
% 
% Desirable properties of regularizeNd
%     - Calculates a relationship between the input x and the output y
%       without definition of the functional form of x to y. 
%     - Extrapolation is possible from a scattered data set. 
%     - After creating the lookup table yGrid and using it with
%       griddedInterpolant, as the query point moves away from the
%       scattered data, the relationship between the input x and output y
%       becomes more linear because of the smoothness equations and no
%       nearby fidelity equations. The linear relationship is a good
%       choice when the relationship between x and y is unknown in
%       extrapolation.
%
%  For introduction on regularization works, start here:
%  https://mathformeremortals.wordpress.com/2013/01/29/introduction-to-regularizing-with-2d-data-part-1-of-3/
%
%
%% Example
%
%  x = rand(100,2);
%  y = exp(x(:,1)+2*x(:,2));
%  xGrid = {0:.1:1, 0:.1:1};
%
%  g = regularizeNd(x, y, xGrid);
%
%  % Note: this is equivalent to the following call:
%
%  g = regularizeNd(x, y, xGrid, 0.01, 'linear', 'normal');
%

%% TODO
% TODO Added support for cubic interpolation. Note that cubic interpolation is very expensive as the number of dimensions increases. 
% TODO Consider adding support for the lsqr solver. However, I don't see this as necessary.

%% Input Checking and Default Values
narginchk(3, 7);
nargoutchk(0,1);

% helper function used mostly for when variables are renamed
getname = @(x) inputname(1);

% Set default smoothness or check smoothness
if nargin() < 4 || isempty(smoothness)
    smoothness = 0.01;
else
    assert(all(smoothness>=0), '%s must be positive in all components.', getname(smoothness));
end

% check that the grid is of the right type
assert(iscell(xGrid), '%s must be a cell array.', getname(xGrid));

% calculate the number of dimension
nDimensions = size(x,2);

% check for the matching dimensionality
assert(nDimensions == numel(xGrid), 'Dimensionality mismatch. The number of columns in %s does not match the number of cells in %s.', getname(x), getname(xGrid));

% Check if smoothness is a scalar. If it is convert it to a vector
if isscalar(smoothness)
    smoothness = ones(nDimensions,1).*smoothness;
end

% Set default interp method or check method
if nargin() < 5 || isempty(interpMethod)
    interpMethod = 'linear';
else
    interpMethodsPossible = {'linear', 'nearest'};
    assert(any(strcmpi(interpMethod, interpMethodsPossible)), '%s is not a possible interpolation method. Check your spelling.', interpMethod);
    interpMethod = lower(interpMethod);
end

% Set default solver or check the solver
if nargin() < 6 || (nargin()==6 && isempty(solver))
    solver = 'normal';
else
    solversPossible = {'\', 'normal'};
    assert(any(strcmpi(solver, solversPossible)), '%s is not an acceptable %s. Check spelling and try again.', solver, getname(solver));
end

% Check y rows matches the number in x
nScatteredPoints = size(x,1);
assert( nScatteredPoints == size(y, 1), '%s must have same number of rows as %s',getname(x), getname(y));

% Check the grid vectors is a cell array
assert(iscell(xGrid), '%s must be a cell array where the ith cell contains nodes for ith dimension', getname(xGrid));

% arrange xGrid as a row cell array. This helps with cellfun and arrayfun
% later because the shape is always the same. From here on, the shape is
% known.
xGrid = reshape(xGrid,1,[]);

% arrange the grid vector as column vectors. This is helpful with arrayfun
% and cellfun calls because the shape is always the same. From here on the
% grid vectors shape is a known.
xGrid = cellfun(@(u) reshape(u,[],1), xGrid, 'UniformOutput', false);

% calculate the number of points in each dimension of the grid
nGrid = cellfun(@(u) length(u), xGrid);
nTotalGridPoints = prod(nGrid);

% Check input points are within min and max of grid.
xGridMin = cellfun(@(u) min(u), xGrid);
xGridMax = cellfun(@(u) max(u), xGrid);
assert(all(all(bsxfun(@ge, x, xGridMin))) & all(all(bsxfun(@le, x, xGridMax))), 'All %s points must be within the range of the grid vectors', getname(x));

% calculate the difference between grid points for each dimension
dx = cellfun(@(uGrid) diff(uGrid), xGrid, 'UniformOutput', false);

% Check for monotonic increasing grid points in each dimension
assert(all(cellfun(@(du) ~any(du<=0), dx)), 'All grid points in %s must be monotonically increasing.', getname(xGrid));

% Check that there are enough points to form an output surface. Linear and
% nearest interpolation types require 3 points in each output grid
% dimension because of the numerical 2nd derivative needs three points.
switch interpMethod
    case 'linear'
        minGridVectorLength = 3;
    case 'nearest'
        minGridVectorLength = 3;
end
assert(all(nGrid >= minGridVectorLength), 'Not enough grid points in each dimension. %s interpolation method and numerical 2nd derivatives requires %d points.', interpMethod, minGridVectorLength);
        

%% Calculate Fidelity Equations

% preallocate
xIndex = cell(1,nDimensions);
cellFraction = cell(1, nDimensions);

% loop over dimensions calculating subscript index in each dimension for
% scattered points.
for iDimension = 1:nDimensions
    % Find cell index
    % determine the cell the x-points lie in the xGrid
    % loop over the dimensions/columns, calculating cell index
    [~,xIndex{iDimension}] = histc(x(:,iDimension), xGrid{iDimension});
    
    % For points that lie ON the max value of xGrid{iDimension} (i.e. the
    % last value), histc returns an index that is equal to the length of
    % xGrid{iDimension}. xGrid{iDimension} describes nGrid(iDimension)-1
    % cells. Therefore, we need to find when a cell has an index equal to
    % the length of nGrid(iDimension) and reduce the index by 1.
    xIndex{iDimension}(xIndex{iDimension} == nGrid(iDimension))=nGrid(iDimension)-1;
    
    % Calculate the cell fraction. This corresponds to a value between 0 and 1.
    % 0 corresponds to the beginning of the cell. 1 corresponds to the end of
    % the cell. The min and max functions help ensure the output is always
    % between 0 and 1.
    cellFraction{iDimension} = min(1,max(0,(x(:,iDimension) - xGrid{iDimension}(xIndex{iDimension}))./dx{iDimension}(xIndex{iDimension})));
end

switch interpMethod
    case 'nearest' % nearest neighbor interpolation in a cell
        
        % calculate the index of nearest point
        xWeightIndex = cellfun(@(fraction, index) round(fraction)+index, cellFraction, xIndex, 'UniformOutput', false);
        
        % clean up a little
        clear(getname(cellFraction));
        
        % calculate linear index
        xWeightIndex = subscript2index(nGrid, xWeightIndex{:});
        
        % the weight for nearest interpolation is just 1
        weight  = 1;
        
        % Form the sparse A matrix for fidelity equations
        A = sparse((1:nScatteredPoints)', xWeightIndex, weight, nScatteredPoints, nTotalGridPoints);
        
        % clean up a little
        clear(getname(xWeightIndex), getname(weight));
        
    case 'linear'  % linear interpolation in a cell
        
        % In linear interpolation, there is two weights per dimension
        %                              weight 1    weight 2
        weights = cellfun(@(fraction) [1-fraction, fraction], cellFraction, 'UniformOutput', false);
        
        % clean up a little
        clear(getname(cellFraction));
        
        % Each cell has 2^nDimension nodes. The local dimension index label is 1 or 2 for each dimension. For instance, cells in 2d
        % have 4 nodes with the following indexes:
        % node label  =  1  2  3  4
        % index label = [1, 1, 2, 2;
        %                1, 2, 1, 2]
        % Said in words, node 1 is one, one. node 2 is one, two. node
        % three is two, one. node 4 is two, two.
        localCellIndex = (arrayfun(@(digit) str2double(digit), dec2bin(0:2^nDimensions-1))+1)';
        
        % preallocate before loop
        weight = ones(nScatteredPoints, 2^nDimensions);
        xWeightIndex = cell(1, nDimensions);
        
        % Calculate weight for each point in the local cell
        % After the for loop finishes, the rows of weight sum to 1 as a check.
        for iDimension = 1:nDimensions
            % multiply the weights from each dimension
            weight = weight.*weights{iDimension}(:, localCellIndex(iDimension,:));
            % compute the index corresponding to the weight
            xWeightIndex{iDimension} = bsxfun(@plus, xIndex{iDimension}, localCellIndex(iDimension,:)-1);
        end
        
        % calculate linear index
        xWeightIndex = subscript2index(nGrid, xWeightIndex{:});
        
        % Form the sparse A matrix for fidelity equations
        A = sparse(repmat((1:nScatteredPoints)',1,2^nDimensions), xWeightIndex, weight, nScatteredPoints, nTotalGridPoints);
        
        % clean up a little
        clear(getname(xWeightIndex), getname(weight), getname(localCellIndex));
    otherwise
        error('Code should never reach this point. If it does, there is a bug.');
end

%% Smoothness Equations

%%% calculate the number of smoothness equations in each dimension

% nEquations is a square matrix where the ith row contains
% number of smoothing equations in each dimension. For instance, if the
% nGrid is [ 3 6 7 8] and ith row is 2, nEquationPerDimension contains
% [3 4 7 8]. Therefore, the nSmoothnessEquations is 3*4*7*8=672 for 2nd dimension (2nd row).
nEquationsPerDimension = repmat(nGrid, nDimensions,1);
nEquationsPerDimension = nEquationsPerDimension - 2*ones(nDimensions);
nSmoothnessEquations = prod(nEquationsPerDimension,2);

% Calculate the total number of Smooth equations
nTotalSmoothnessEquations = sum(nSmoothnessEquations);

%%% Calculate regularization matrices

% Preallocate the regularization equations
Areg = cell(nDimensions, 1);

% compute the index multiplier for each dimension. This is used for
% calculating the linear index.
multiplier = cumprod(nGrid);

% loop over each dimension. calcuate numerical 2nd derivatives weights. Place them in Areg cell array.
for iDimension=1:nDimensions
    if smoothness(iDimension) == 0
        nTotalSmoothnessEquations = nTotalSmoothnessEquations - nSmoothnessEquations(iDimension);
        Areg{iDimension} = [];
    else
        % initialize the index for the first grid vector
        if iDimension==1
            index1 = (1:nGrid(1)-2)';
            index2 = (2:nGrid(1)-1)';
            index3 = (3:nGrid(1))';
        else
            index1 = (1:nGrid(1))';
            index2 = index1;
            index3 = index1;
        end
        
        % loop over dimensions accumulating the contribution to the linear
        % index vector in each dimension. Note this section of code works very
        % similar to combining ndgrid and sub2ind. Basically, inspiration came
        % from looking at ndgrid and sub2ind.
        for iCell = 2:nDimensions
            if iCell == iDimension
                index1 = reshape(bsxfun(@(indx, currentIndex) indx + (currentIndex-1)*multiplier(iCell-1), index1, (1:nGrid(iCell)-2)), [], 1);
                index2 = reshape(bsxfun(@(indx, currentIndex) indx + (currentIndex-1)*multiplier(iCell-1), index2, (2:nGrid(iCell)-1)), [], 1);
                index3 = reshape(bsxfun(@(indx, currentIndex) indx + (currentIndex-1)*multiplier(iCell-1), index3, (3:nGrid(iCell))), [], 1);
            else
                currentDimensionIndex = 1:nGrid(iCell);
                index1 = reshape(bsxfun(@(indx, currentIndex) indx + (currentIndex-1)*multiplier(iCell-1), index1, currentDimensionIndex), [], 1);
                index2 = reshape(bsxfun(@(indx, currentIndex) indx + (currentIndex-1)*multiplier(iCell-1), index2, currentDimensionIndex), [], 1);
                index3 = reshape(bsxfun(@(indx, currentIndex) indx + (currentIndex-1)*multiplier(iCell-1), index3, currentDimensionIndex), [], 1);
            end
        end
        
        
        % Scales as if there is the same number of residuals along the
        % current dimension as there are fidelity equations total; use the
        % square root because the residuals will be squared to minimize
        % squared error.
        smoothnessScale = sqrt(nScatteredPoints/nSmoothnessEquations(iDimension));
        
        % Axis Scaling. This is equivalent to normalizing the current axis
        % to 0 to 1. i.e. If you scale one axis, the same smoothness factor
        % can be used to get similar shaped topology.
        axisScale = (xGridMax(iDimension) - xGridMin(iDimension)).^2;

        
        % Create the Areg for each dimension and store it a cell array.
        Areg{iDimension} = sparse(repmat((1:nSmoothnessEquations(iDimension))',1,3), ...
            [index1, index2, index3], ...
            smoothness(iDimension)*smoothnessScale*axisScale*secondDerivativeWeights(xGrid{iDimension},nGrid(iDimension), iDimension, nGrid), ...
            nSmoothnessEquations(iDimension), ...
            nTotalGridPoints);
    end
end

%% Assemble and Solve the Overall Equation System

% concatenate the fidelity equations and smoothing equations together
A = vertcat(A, Areg{:});

% clean up
clear(getname(Areg)); 

% solve the full system
switch solver
    case '\'
        if nDimensions == 1
            yGrid = A\[y;zeros(nTotalSmoothnessEquations,1)];
        elseif nDimensions > 1
            yGrid = reshape(A\[y;zeros(nTotalSmoothnessEquations,1)], nGrid);
        end
    case 'normal'
        if nDimensions == 1
            yGrid = (A'*A)\(A'*[y;zeros(nTotalSmoothnessEquations,1)]);
        elseif nDimensions > 1
            yGrid = reshape((A'*A)\(A'*[y;zeros(nTotalSmoothnessEquations,1)]), nGrid);
        end
    otherwise
        error('Code should never reach this line. If it does, there is a bug.');
end  % switch solver

end %


%%
function weights = secondDerivativeWeights(x, nX, dim, arraySize)
% calculates the weights for a 2nd order numerical 2nd derivative
%
% Inputs
% x - grid vector
% nX - The length of x.
% dim - The dimension for which the numerical 2nd derivative is calculated
% arraySize - The size of the grid.
% Outputs
% weights  - weights of the numerical second derivative in a column vector
% form

% Calculate the numerical second derivative weights.
% The weights come from differentiating the parabolic Lagrange polynomial twice.
%
% parabolic Lagrange polynomial through 3 points:
% y = [(x-x2)*(x-x3)/((x1-x2)*(x1-x3)), (x-x1)*(x-x3)/((x2-x1)*(x2-x3)), (x-x1)*(x-x2)/((x3-x1)*(x3-x2))]*[y1;y2;y3];
%
% differentiating twice:
% y'' = 2./[(x1-x2)*(x1-x3), (x2-x1)*(x2-x3), (x3-x1)*(x3-x2)]*[y1;y2;y3];
%
x1 = x(1:nX-2);
x2 = x(2:nX-1);
x3 = x(3:nX);
weights = 2./[(x1-x3).*(x1-x2), (x2-x1).*(x2-x3), (x3-x1).*(x3-x2)];

% expand the weights across other dimensions and convert to  column vectors
weights = [reshape(ndGrid1D(weights(:,1), dim, arraySize),[], 1), ...
           reshape(ndGrid1D(weights(:,2), dim, arraySize),[], 1), ...
           reshape(ndGrid1D(weights(:,3), dim, arraySize),[], 1)];
end
 
 %%
 function xx = ndGrid1D(x, dim,  arraySize)
 % copies x along all dimensions except the dimension dim
 %
 % Inputs
 % x - column vector
 % dim - The dimension that x is not copied
 % arraySize - The size of the output array. arraySize(dim) is not used.
 %
 % Outputs
 % xx - array with size arraySize except for the dimension dim. The length
 % of dimension dim is numel(x).
 %
 % Description
 % This is very similar to ndgrid except that ndgrid returns all arrays for
 % each input vector. This algorithm returns only one array. The nth output
 % array of ndgrid is same as this algoritm when dim = n. For instance, if
 % ndgrid is given three input vectors, the output size will be arraySize.
 % Calling ndGrid1D(x,3, arraySize) will return the same values as the 3rd
 % output of ndgrid.
 %
 
 % reshape x into a vector with the proper dimensions. All dimensions are 1
 % expect the dimension dim.
 s = ones(1,length(arraySize));
 s(dim) = numel(x);
 if length(arraySize) == 1
     xx = x;
 else
     x = reshape(x,s);
     % expand x along all the dimensions except dim
     arraySize(dim) = 1;
     xx = repmat(x, arraySize);
 end % end if
 end % end function
 
 %%
 function ndx = subscript2index(siz,varargin)
% Computes the linear index from the subscripts for an n dimensional array
%
% Inputs
% siz - The size of the array.
% varargin - has the same length as length(siz). Contains the subscript in
% each dimension.
% 
% Description
% This algorithm is very similar sub2ind. However, it will work for 1-D and
% all of the extra functionality for other data types is removed.

k = cumprod(siz);

%Compute linear indices
ndx = varargin{1};
for i = 2:length(varargin)
    ndx = ndx + (varargin{i}-1)*k(i-1);
end
end