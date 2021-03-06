[![View regularizeNd on File Exchange](https://www.mathworks.com/matlabcentral/images/matlab-file-exchange.svg)](https://www.mathworks.com/matlabcentral/fileexchange/61436-regularizend)

# regularizeNd
Creates a gridded lookup table from scattered data in n dimensions.

regularizeNd is function written in MATLAB that extends functionality of RegularizeData3d from 2-D input to n-D input. More background can be found here:
https://mathformeremortals.wordpress.com/2013/01/29/introduction-to-regularizing-with-2d-data-part-1-of-3/

and here
https://mathformeremortals.wordpress.com/2013/09/02/regularizedata3d-the-excel-spreadsheet-function-to-regularize-3d-data-to-a-smooth-surface/


The basic idea is that a lookup table is fitted to the scattered data with a required level of smoothness. The smoothness parameter trades between goodness of fit and smoothness of the curve (1-D), surface (2-D), or hypersurface (n-D).
