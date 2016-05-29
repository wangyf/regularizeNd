function yGrid = RegularizeData3D(x, y, xGrid, smoothness, interpMethod, solver, maxiter)
% RegularizeData3D: Produces a smooth 3D surface from scattered input data.
%
% Arguments: (input)
%  x,y - vectors of equal lengths, containing arbitrary scattered data
%          The only constraint on x and y is they cannot ALL fall on a
%          single line in the x-y plane. Replicate points will be treated
%          in a least squares sense.
%
%          ANY points containing a NaN are ignored in the estimation
%
%  xGrid - cell array containg vectors defining the nodes in the grid in
%          each dimension. xnodes need not be equally spaced. xnodes
%          must completely span the data. If they do not, an error is
%          thrown.
%
%  smoothness - scalar or vector of length 2 - the ratio of
%          smoothness to fidelity of the output surface. This must be a
%          positive real number.
%
%          A smoothness of 1 gives equal weight to fidelity (goodness of fit)
%          and smoothness of the output surface.  This results in noticeable
%          smoothing.  If your input data x,y,z have little or no noise, use
%          0.01 to give smoothness 1% as much weight as goodness of fit.
%          0.1 applies a little bit of smoothing to the output surface.
%
%          If this parameter is a vector of length 2, then it defines
%          the relative smoothing to be associated with the x and y
%          variables. This allows the user to apply a different amount
%          of smoothing in the x dimension compared to the y dimension.
%
%          DEFAULT: 0.01
%
%
%   interpMethod - character, denotes the interpolation scheme used
%          to interpolate the data.
%
%          DEFAULT: 'linear'
%
%          'cubic' - uses cubic interpolation within the grid
%                     This is the most accurate because it accounts
%                     for the fact that the output surface is not flat.
%                     In some cases it may be slower than the other methods.
%
%          'linear' - use bilinear interpolation within the grid
%
%          'nearest' - nearest neighbor interpolation. This will
%                     rarely be a good choice, but I included it
%                     as an option for completeness.
%
%
%   solver - character flag - denotes the solver used for the
%          resulting linear system. Different solvers will have
%          different solution times depending upon the specific
%          problem to be solved. Up to a certain size grid, the
%          direct \ solver will often be speedy, until memory
%          swaps causes problems.
%
%          What solver should you use? Problems with a significant
%          amount of extrapolation should avoid lsqr. \ may be
%          best numerically for small smoothnesss parameters and
%          high extents of extrapolation.
%
%          Large numbers of points will slow down the direct
%          \, but when applied to the normal equations, \ can be
%          quite fast. Since the equations generated by these
%          methods will tend to be well conditioned, the normal
%          equations are not a bad choice of method to use. Beware
%          when a small smoothing parameter is used, since this will
%          make the equations less well conditioned.
%
%          DEFAULT: '\'
%
%          '\' - uses matlab's backslash operator to solve the sparse
%                     system. 'backslash' is an alternate name.
%
%          'lsqr' - uses matlab's iterative lsqr solver
%
%   'maxiter' - only applies to lsqr solvers - defines the maximum number
%          of iterations for an iterative solver
%          DEFAULT: min(10000,length(xnodes)*length(ynodes))
%
%
%
% Arguments: (output)
%  yGrid   - array containing the fitted surface
%
% Speed considerations:
%  Remember that a LARGE system of linear equations needs solved. There
%  will be as many unknowns as the total number of nodes in the final
%  lattice. While these equations may be sparse, solving a system of 10000
%  equations may take a second or so. Very large problems may benefit from
%  the iterative solver lsqr.
%
%
% Example usage:
%
%  x = rand(100,2);
%  y = exp(x(:,1)+2*x(:,2));
%  xnodes = {0:.1:1, 0:.1:1};
%
%  g = regularizeNd(x,y,xnodes);
%
% Note: this is equivalent to the following call:
%
%  g = regularizeNd(x,y,xnodes, 0.01, 'linear', '\');
%


%% Input Checking and Default Values
narginchk(3, 7);


% helper function used mostly for when variables are renamed
getname = @(x) inputname(1);

% Set default input values
if nargin() < 4 || isempty(smoothness)
    smoothness = 0.01;
end

interpMethodsPossible = {'cubic', 'triangle', 'linear', 'nearest'};

if nargin() < 5 || isempty(interpMethod)
    interpMethod = 'linear';
elseif nargin >= 5 && ~any(strcmpi(interpMethod, interpMethodsPossible))
    error('%s is not a possible interpolation method. Check your spelling.', interpMethod);
end

if nargin() < 6
    solver = '\';
end

% Check dimensions
nScatteredPoints = size(x,1);
assert( nScatteredPoints == size(y, 1), '%s must have same number of rows as %s',getname(x), getname(y));
assert(iscell(xGrid), '%s must be a cell array where the ith cell contains  nodes for ith dimension', getname(xGrid));

nGrid = cellfun(@(u) length(u), xGrid);
nTotalGridPoints = prod(nGrid);

if nargin() == 6 && strcmpi('lsqr', solver)
    maxIter = min(1e4, nTotalGridPoints);
end

if (nargin() == 7 && isempty(solver))
    solver = 'lsqr';
elseif nargin()==7 && (~isempty(solver) || ~strcmpi(solver,'lsqr'))
    error('%s set but lsqr solver not selected.', getname(maxiter));
end
    
if nargin()==7 && isempty(maxIter)
    maxIter = min(1e4, nTotalGridPoints);
end

% Check input points are within min and max of grid
xGridMin = cellfun(@(u) min(u), xGrid);
xGridMax = cellfun(@(u) max(u), xGrid);
assert(all(all(bsxfun(@ge, x, xGridMin))) & all(all(bsxfun(@le, x, xGridMax))), 'All %s points must be within the range of %s to %s', getname(x), getname(xGridMin), getname(xGridMax));

% Check for monotonic increasing grid points in each dimension
assert(all(cellfun(@(u) ~any(diff(u)<=0), xGrid)), 'All grid points in %s must be monotonicaly increasing.', getname(xGrid));

% Are there enough output points to form a surface?
% Bicubic interpolation requires a 4x4 output grid.  Other types require a 3x3 output grid.
if strcmpi(interpMethod, 'cubic')
    minAxisLength = 4;
else
    minAxisLength = 3;
end
assert(all(nGrid < minAxisLength), 'Not enough grid points in each dimension. %s interpolation method requires %d points.', interpMethod, minAxisLength);

%% Find cell index
% determine the cell the x-points lie in the xGrid

nDimensions = size(x,2);

% calculate the multipler corresponding to each dimension. For example, if
% x has 2 dimensions and xGrid has 5 points in the first dimension and 7
% ponts in the 2nd dimension, multiplier is [1 4]. If point has an index of
% 3 in the first dimension and 2 in the 2nd dimension then its overall
% index is 3+2*4 = 11.
multiplier = cumprod([1, nGrid(1:nDimensions-1)-1]);

% preallocate before loop
xIndex = nan(nScatteredPoints, nDimensions); 

% find initial index for 1st dimension
xIndex(:,1) = findDimensionIndex(x(:,1), xGrid{1});
xLinearIndex = xIndex(:,1);

% loop over the dimensions accumulating the index calculated for the
% previous dimensions
for iDimension = 2:nDimensions
    xIndex(:,iDimension) = findDimensionIndex(x(:,iDimension), xGrid{iDimension});
    xLinearIndex = xLinearIndex + multiplier(iDimension)*xIndex(:,iDimension);
end

% Adjust the linear index so that first cell is numbered 1 rather than 0.
% This needed since matlab uses 1 as its first index of an array.
% Calculating the overall index across multiple dimensions is easier if the
% index is 0 based. Therefore, the overall 0 based index is calculated
% first and then shifted by 1.
xLinearIndex = xLinearIndex+1;

%%
% interpolation equations for each point
tx = min(1,max(0,(x - xGrid(indx))./dx(indx)));
switch interpMethod
    case 'nearest'
        % nearest neighbor interpolation in a cell
        k = round(1-ty) + round(1-tx)*ny;
        A = sparse((1:n)',ind+k,ones(n,1),n,nGridPoints);
        
    case 'bilinear'
        % bilinear interpolation in a cell
        A = sparse(repmat((1:n)',1,4),[ind,ind+1,ind+ny,ind+ny+1], ...
            [(1-tx).*(1-ty), (1-tx).*ty, tx.*(1-ty), tx.*ty], ...
            n,nGridPoints);
        
    case 'bicubic'
        % Legacy code calculated the starting index ind for bilinear interpolation, but for bicubic interpolation we need to be further away by one
        % row and one column (but not off the grid).  Bicubic interpolation involves a 4x4 grid of coefficients, and we want x,y to be right
        % in the middle of that 4x4 grid if possible.  Use min and max to ensure we won't exceed matrix dimensions.
        % The sparse matrix format has each column of the sparse matrix A assigned to a unique output grid point.  We need to determine which column
        % numbers are assigned to those 16 grid points.
        % What are the first indexes (in x and y) for the points?
        XIndexes = min(max(1, indx - 1), nx - 3);
        YIndexes = min(max(1, indy - 1), ny - 3);
        % These are the first indexes of that 4x4 grid of nodes where we are doing the interpolation.
        AllColumns = (YIndexes + (XIndexes - 1) * ny)';
        % Add in the next three points.  This gives us output nodes in the first row (i.e. along the x direction).
        AllColumns = [AllColumns; AllColumns + ny; AllColumns + 2 * ny; AllColumns + 3 * ny];
        % Add in the next three rows.  This gives us 16 total output points for each input point.
        AllColumns = [AllColumns; AllColumns + 1; AllColumns + 2; AllColumns + 3];
        % Coefficients are calculated based on:
        % http://en.wikipedia.org/wiki/Lagrange_interpolation
        % Calculate coefficients for this point based on its coordinates as if we were doing cubic interpolation in x.
        % Calculate the first coefficients for x and y.
        XCoefficients = (x(:) - xGrid(XIndexes(:) + 1)) .* (x(:) - xGrid(XIndexes(:) + 2)) .* (x(:) - xGrid(XIndexes(:) + 3)) ./ ((xGrid(XIndexes(:)) - xGrid(XIndexes(:) + 1)) .* (xGrid(XIndexes(:)) - xGrid(XIndexes(:) + 2)) .* (xGrid(XIndexes(:)) - xGrid(XIndexes(:) + 3)));
        YCoefficients = (w(:) - ynodes(YIndexes(:) + 1)) .* (w(:) - ynodes(YIndexes(:) + 2)) .* (w(:) - ynodes(YIndexes(:) + 3)) ./ ((ynodes(YIndexes(:)) - ynodes(YIndexes(:) + 1)) .* (ynodes(YIndexes(:)) - ynodes(YIndexes(:) + 2)) .* (ynodes(YIndexes(:)) - ynodes(YIndexes(:) + 3)));
        % Calculate the second coefficients.
        XCoefficients = [XCoefficients, (x(:) - xGrid(XIndexes(:))) .* (x(:) - xGrid(XIndexes(:) + 2)) .* (x(:) - xGrid(XIndexes(:) + 3)) ./ ((xGrid(XIndexes(:) + 1) - xGrid(XIndexes(:))) .* (xGrid(XIndexes(:) + 1) - xGrid(XIndexes(:) + 2)) .* (xGrid(XIndexes(:) + 1) - xGrid(XIndexes(:) + 3)))];
        YCoefficients = [YCoefficients, (w(:) - ynodes(YIndexes(:))) .* (w(:) - ynodes(YIndexes(:) + 2)) .* (w(:) - ynodes(YIndexes(:) + 3)) ./ ((ynodes(YIndexes(:) + 1) - ynodes(YIndexes(:))) .* (ynodes(YIndexes(:) + 1) - ynodes(YIndexes(:) + 2)) .* (ynodes(YIndexes(:) + 1) - ynodes(YIndexes(:) + 3)))];
        % Calculate the third coefficients.
        XCoefficients = [XCoefficients, (x(:) - xGrid(XIndexes(:))) .* (x(:) - xGrid(XIndexes(:) + 1)) .* (x(:) - xGrid(XIndexes(:) + 3)) ./ ((xGrid(XIndexes(:) + 2) - xGrid(XIndexes(:))) .* (xGrid(XIndexes(:) + 2) - xGrid(XIndexes(:) + 1)) .* (xGrid(XIndexes(:) + 2) - xGrid(XIndexes(:) + 3)))];
        YCoefficients = [YCoefficients, (w(:) - ynodes(YIndexes(:))) .* (w(:) - ynodes(YIndexes(:) + 1)) .* (w(:) - ynodes(YIndexes(:) + 3)) ./ ((ynodes(YIndexes(:) + 2) - ynodes(YIndexes(:))) .* (ynodes(YIndexes(:) + 2) - ynodes(YIndexes(:) + 1)) .* (ynodes(YIndexes(:) + 2) - ynodes(YIndexes(:) + 3)))];
        % Calculate the fourth coefficients.
        XCoefficients = [XCoefficients, (x(:) - xGrid(XIndexes(:))) .* (x(:) - xGrid(XIndexes(:) + 1)) .* (x(:) - xGrid(XIndexes(:) + 2)) ./ ((xGrid(XIndexes(:) + 3) - xGrid(XIndexes(:))) .* (xGrid(XIndexes(:) + 3) - xGrid(XIndexes(:) + 1)) .* (xGrid(XIndexes(:) + 3) - xGrid(XIndexes(:) + 2)))];
        YCoefficients = [YCoefficients, (w(:) - ynodes(YIndexes(:))) .* (w(:) - ynodes(YIndexes(:) + 1)) .* (w(:) - ynodes(YIndexes(:) + 2)) ./ ((ynodes(YIndexes(:) + 3) - ynodes(YIndexes(:))) .* (ynodes(YIndexes(:) + 3) - ynodes(YIndexes(:) + 1)) .* (ynodes(YIndexes(:) + 3) - ynodes(YIndexes(:) + 2)))];
        % Allocate space for all of the data we're about to insert.
        AllCoefficients = zeros(16, n);
        % There may be a clever way to vectorize this, but then the code would be unreadable and difficult to debug or upgrade.
        % The matrix solution process will take far longer than this, so it's not worth the effort to vectorize this.
        for i = 1 : n
            % Multiply the coefficients to accommodate bicubic interpolation.  The resulting matrix is a 4x4 of the interpolation coefficients.
            TheseCoefficients = repmat(XCoefficients(i, :)', 1, 4) .* repmat(YCoefficients(i, :), 4, 1);
            % Add these coefficients to the list.
            AllCoefficients(1 : 16, i) = TheseCoefficients(:);
        end
        % Each input point has 16 interpolation coefficients (because of the 4x4 grid).
        AllRows = repmat(1 : n, 16, 1);
        % Now that we have all of the indexes and coefficients, we can create the sparse matrix of equality conditions.
        A = sparse(AllRows(:), AllColumns(:), AllCoefficients(:), n, nGridPoints);
end
rhs = y;

% Do we have relative smoothing parameters?
if numel(smoothness) == 1
    % Nothing special; this is just a scalar quantity that needs to be the same for x and y directions.
    xyRelativeStiffness = [1; 1] * smoothness;
else
    % What the user asked for
    xyRelativeStiffness = smoothness(:);
end

% Build a regularizer using the second derivative.  This used to be called "gradient" even though it uses a second
% derivative, not a first derivative.  This is an important distinction because "gradient" implies a horizontal
% surface, which is not correct.  The second derivative favors flatness, especially if you use a large smoothness
% constant.  Flat and horizontal are two different things, and in this script we are taking an irregular surface and
% flattening it according to the smoothness constant.
% The second-derivative calculation is documented here:
% http://mathformeremortals.wordpress.com/2013/01/12/a-numerical-second-derivative-from-three-points/

% Minimizes the sum of the squares of the second derivatives (wrt x and y) across the grid
[i,j] = meshgrid(1:nx,2:(ny-1));
ind = j(:) + ny*(i(:)-1);
dy1 = dy(j(:)-1);
dy2 = dy(j(:));

Areg = sparse(repmat(ind,1,3),[ind-1,ind,ind+1], ...
    xyRelativeStiffness(2)*[-2./(dy1.*(dy1+dy2)), ...
    2./(dy1.*dy2), -2./(dy2.*(dy1+dy2))],nGridPoints,nGridPoints);

[i,j] = meshgrid(2:(nx-1),1:ny);
ind = j(:) + ny*(i(:)-1);
dx1 = dx(i(:) - 1);
dx2 = dx(i(:));

Areg = [Areg;sparse(repmat(ind,1,3),[ind-ny,ind,ind+ny], ...
    xyRelativeStiffness(1)*[-2./(dx1.*(dx1+dx2)), ...
    2./(dx1.*dx2), -2./(dx2.*(dx1+dx2))],nGridPoints,nGridPoints)];
nreg = size(Areg, 1);

FidelityEquationCount = size(A, 1);
% Number of the second derivative equations in the matrix
RegularizerEquationCount = nx * (ny - 2) + ny * (nx - 2);
% We are minimizing the sum of squared errors, so adjust the magnitude of the squared errors to make second-derivative
% squared errors match the fidelity squared errors.  Then multiply by smoothparam.
NewSmoothnessScale = sqrt(FidelityEquationCount / RegularizerEquationCount);

% Second derivatives scale with z exactly because d^2(K*z) / dx^2 = K * d^2(z) / dx^2.
% That means we've taken care of the z axis.
% The square root of the point/derivative ratio takes care of the grid density.
% We also need to take care of the size of the dataset in x and y.

% The scaling up to this point applies to local variation.  Local means within a domain of [0, 1] or [10, 11], etc.
% The smoothing behavior needs to work for datasets that are significantly larger or smaller than that.
% For example, if x and y span [0 10,000], smoothing local to [0, 1] is insufficient to influence the behavior of
% the whole surface.  For the same reason there would be a problem applying smoothing for [0, 1] to a small surface
% spanning [0, 0.01].  Multiplying the smoothing constant by SurfaceDomainScale compensates for this, producing the
% expected behavior that a smoothing constant of 1 produces noticeable smoothing (when looking at the entire surface
% profile) and that 1% does not produce noticeable smoothing.
SurfaceDomainScale = (max(max(xGrid)) - min(min(xGrid))) * (max(max(ynodes)) - min(min(ynodes)));
NewSmoothnessScale = NewSmoothnessScale *	SurfaceDomainScale;

A = [A; Areg * NewSmoothnessScale];

rhs = [rhs;zeros(nreg,1)];
% solve the full system, with regularizer attached
switch solver
    case {'\' 'backslash'}
        yGrid = reshape(A\rhs,ny,nx);
    case 'lsqr'
        % iterative solver - lsqr. No preconditioner here.
        tol = abs(max(y)-min(y))*1.e-13;
        
        [yGrid,flag] = lsqr(A,rhs,tol,maxiter);
        yGrid = reshape(yGrid,ny,nx);
        
        % display a warning if convergence problems
        switch flag
            case 0
                % no problems with convergence
            case 1
                % lsqr iterated MAXIT times but did not converge.
                warning('GRIDFIT:solver',['Lsqr performed ', ...
                    num2str(maxiter),' iterations but did not converge.'])
            case 3
                % lsqr stagnated, successive iterates were the same
                warning('GRIDFIT:solver','Lsqr stagnated without apparent convergence.')
            case 4
                warning('GRIDFIT:solver',['One of the scalar quantities calculated in',...
                    ' LSQR was too small or too large to continue computing.'])
        end
        
end  % switch solver

% only generate xgrid and ygrid if requested.
if nargout>1
    [xgrid,wgrid]=meshgrid(xGrid,ynodes);
end

end % 

%%
function index = findDimensionIndex(u, uGrid)
% calculates the 0 based index of the points u in uGrid

[~, index] = histc(u, uGrid);

% histc's first bin is numbered 1. I want the first bin to be 0. This helps
% with calculating the index in multiple dimension.
index = index - 1;
end