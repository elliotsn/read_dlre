function [core, lon, lat]=read_dlre_gdr(imgpath)

% Reads level 2/3 gridded .IMG files created by the Diviner 
% Lunar Radiometer Experiment (Lunar Reconnaissance Orbiter)
%
% function [core, lon, lat]=read_dlre(imgfile)
%
%Input:
%       -'infile' is the .IMG file to extract the data
%        from. The function assumes that the .LBL file is present in the
%        same directory.
%Output:
%    -'core' is a samples x lines matrix containing the core science values
%    -'lon' is a samples x lines matrix containing longitude for each pixel
%    -'lat' is a samples x lines matrix containing latitude for each pixel
%
% Date created: 23/07/2013
% Author:       Elliot Sefton-Nash
% Institution:  University of California Los Angeles
%

% Read label
lblpath = [imgpath(1:end-3),'lbl'];
lbl = read_pds_lbl(lblpath);

samples = str2double(lbl.uncompressed_file.image.line_samples);
lines = str2double(lbl.uncompressed_file.image.lines);

% Find out the precision based on passing, in this case, the value
% associated with the PDS keyword 'SAMPLE_BITS'.
[precision, ~] = get_precision(lbl.uncompressed_file.image.sample_bits);

% Find out what byte-ordering the data is. The keyword SAMPLE_TYPE tells us
% this. For HRSC it's usually MSB_INTEGER, which is big endian.
endian = get_endian(lbl.uncompressed_file.image.sample_type);

% Open the file as binary read-only, read dns.
fid = fopen(imgpath, 'r', endian);
dn = fread(fid, [samples, lines], precision);

% Rotate by 90 degrees.
dn = dn';

fclose(fid);

% Make a mask of all the pixels equal to the null value.
null_dn = str2double(lbl.uncompressed_file.image.missing_constant);
mask = (dn ~= null_dn);

% Scale to science values:
scaling_factor = str2double(lbl.uncompressed_file.image.scaling_factor);
offset = str2double(lbl.uncompressed_file.image.offset);
core = NaN(size(dn));
core(mask) = (double(dn(mask)) * scaling_factor) + offset;

center_lat = str2double(strtok(lbl.image_map_projection.center_latitude, ' '));

%-----MAP COORDINATES-----
switch lower(strrep(lbl.image_map_projection.map_projection_type, '"',''))
    case 'simple cylindrical'
        
        % Remove units.
        res = str2double(strtok(lbl.image_map_projection.map_resolution, ' '));
        
        % Lat and lon have units after numbers, e.g. '<deg>'
        center_lon = str2double(strtok(lbl.image_map_projection.center_longitude, ' '));

        [lon, lat] = meshgrid(1:samples, 1:lines);
        lon = single(lon);
        lat = single(lat);
        
        spo = str2double(strtok(lbl.image_map_projection.sample_projection_offset, ' '));
        lpo = str2double(strtok(lbl.image_map_projection.line_projection_offset, ' '));
        lon = center_lon + (lon - spo - 1)./ res;
        lat = center_lat - (lat - lpo - 1)./ res;

    case 'polar stereographic'
        
        [psx, psy] = meshgrid(1:samples, 1:lines);
        psx = single(psx);
        psy = single(psy);
        map_scale = str2double(strtok(lbl.image_map_projection.map_scale, ' '));
        
        % Save some memory, move down rows.
        psx = (psx - samples/2 - 0.5).*map_scale;
        psy = (psy - lines/2 - 0.5).*map_scale;
        
        lon = atan2d(psx, psy);
        R = sqrt(psx.^2 + psy.^2);
        
        % Use center lat to determine hemisphere and therefore projection
        if center_lat >= 0
            % Assume north polar stereographic
            lat = 90 - 2*atand(0.5 * R/1737400);
        else
            lat = -90 + 2*atand(0.5 * R/1737400);
        end
end