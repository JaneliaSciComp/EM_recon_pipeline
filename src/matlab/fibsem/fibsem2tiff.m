% Converts *.dat raw data files from Neon-NI box to 16bit tiff images. Each
% detector has its own file.
%
% Rev history 05/14/09
%   1st rev.
% 6/17/09
%   added FileNames sorting
% 9/23/2010
%   changed to read3dsem to accomandate new file format from NVision-NI
% 7/31/2011
%   added matlabpool and changed for to parfor
% 7/9/2014
%   added 8-bit data support
% 7/14/2014
%   added tiff tags for electron counts scaling factor and resolution
% 7/4/2015
%   added support for file verions 8 of 16-bit data
% 3/10/2016
%   added interpolation support when a detector calibration file
%   (calibrationA.csv or/and calibrationB.csv) is present in the
%   16-bit *.dat directory
% 11/15/2016
%   revised matlabpool to parpool for v2016b
% 7/25/2017
%   removed FileNames sorting to fix bug for single file
% 11/18/2020
%   added suppot for file version 9
%

clearvars
%% Read in 3DSEM *.dat file
[FileNames,PathName] = uigetfile(...
  {'FileList*.mat; *.dat','Data Files or File Name List (FileList*.mat, *.dat)';...
  'FileList*.mat','File Name List File (FileList*.mat)';...
  '*.dat', 'Select data files';...
  '*.*','All Files (*.*)'},...
  'Multiselect','on',...
  'Select Data Files'); % Display standard dialog box to select files
if ischar(FileNames) && ~isempty(regexpi(FileNames,'FileList')) % extract file names from the file name list
  temp=load([PathName FileNames]);
  FileNames=temp.FileNames;
  clear temp;
end

%% Read in detector calibration file (calibration.csv) if present
ACal=0;   BCal=0; CalibAx=0; CalibAy=0; CalibBx=0; CalibBy=0;
if exist([PathName 'calibrationA.csv'],'file')==2
  ACal=1;
  CalibA=csvread([PathName 'calibrationA.csv']);
  CalibAx=CalibA(:,1);
  CalibAy=CalibA(:,2);
end
if exist([PathName 'calibrationB.csv'],'file')==2
  BCal=1;
  CalibB=csvread([PathName 'calibrationB.csv']);
  CalibBx=CalibB(:,1);
  CalibBy=CalibB(:,2);
end

%% Save images

FileNumber=size(FileNames,2); % Number of files
if ischar(FileNames)==1; FileNumber=1; end

if isempty(gcp('nocreate')) && FileNumber > 8
  parpool
end

parfor FileN=1:FileNumber
  AN=0; BN=0; ARaw=0; BRaw=0; % reset flags for available images
  
  if FileNumber==1
    FileName=char(FileNames);
  else
    FileName=char(FileNames(FileN));
  end
  FIBSEMData=readfibsem([PathName FileName]); % script to read *.dat files
  
  % generate normalized images ImageAN and ImageBN, as well as raw 16 bit
  % images ImageARaw and ImageBRaw if available.
  if FIBSEMData.EightBit==1 % 8-bit *.dat
    if FIBSEMData.AI1
      AN=1;
      ImageAN=FIBSEMData.ImageA;
    end
    if FIBSEMData.AI2
      BN=1;
      ImageBN=FIBSEMData.ImageB;
    end
  else % 16-bit *.dat
    switch FIBSEMData.FileVersion
      case {1,2,3,4,5,6}
        if FIBSEMData.AI1
          AN=1;
          ImageAN=uint16((FIBSEMData.ImageA+10)/20*65535); % normalize image data to uint16
        end
        if FIBSEMData.AI2
          BN=1;
          ImageBN=uint16((FIBSEMData.ImageB+10)/20*65535); % normalize image data to uint16
        end
      otherwise
        if FIBSEMData.AI1
          AN=1;
          ImageAN=uint16(FIBSEMData.ImageA);
          if ACal==1
            AN=0;
            ImageACal=uint16(interp1(CalibAx,CalibAy,single(FIBSEMData.RawImageA),'spline'));
          end
          ARaw=1;
          ImageARaw=uint16(single(FIBSEMData.RawImageA)+32768); % convert raw int16 data to uint16
        end
        if FIBSEMData.AI2
          BN=1;
          ImageBN=uint16(FIBSEMData.ImageB);
          if BCal==1
            BN=0;
            ImageBCal=uint16(interp1(CalibBx,CalibBy,single(FIBSEMData.RawImageB),'spline'));
          end
          BRaw=1;
          ImageBRaw=uint16(single(FIBSEMData.RawImageB)+32768);
        end
    end
  end
  
  % save images with electron counts (scaling factor in Image Description)
  if AN==1
    imwrite(ImageAN,[PathName regexprep(FileName,'.dat',['_' deblank(FIBSEMData.DetA) '.tif'])],...
      'Description',['Electron scaling factor: ', num2str(1/FIBSEMData.Scaling(4,1))],...
      'Resolution',1/FIBSEMData.PixelSize*2.54*10^7);
  end
  if BN==1
    imwrite(ImageBN,[PathName regexprep(FileName,'.dat',['_' deblank(FIBSEMData.DetB) '.tif'])],...
      'Description',['Electron scaling factor: ', num2str(1/FIBSEMData.Scaling(4,2))],...
      'Resolution',1/FIBSEMData.PixelSize*2.54*10^7);
  end
  
  % save raw 16bit images
  if ARaw==1
    imwrite(ImageARaw,[PathName regexprep(FileName,'.dat',['_' deblank(FIBSEMData.DetA) '_raw.tif'])],...
      'Resolution',1/FIBSEMData.PixelSize*2.54*10^7);
  end
  if BRaw==1
    imwrite(ImageBRaw,[PathName regexprep(FileName,'.dat',['_' deblank(FIBSEMData.DetB) '_raw.tif'])],...
      'Resolution',1/FIBSEMData.PixelSize*2.54*10^7);
  end
  
  % save 16bit images calibrated by calibrationA.csv and/or calibrationB.csv
  if ACal==1
    imwrite(ImageACal,[PathName regexprep(FileName,'.dat',['_' deblank(FIBSEMData.DetA) '.tif'])],...
      'Resolution',1/FIBSEMData.PixelSize*2.54*10^7);
  end
  if BCal==1
    imwrite(ImageBCal,[PathName regexprep(FileName,'.dat',['_' deblank(FIBSEMData.DetB) '.tif'])],...
      'Resolution',1/FIBSEMData.PixelSize*2.54*10^7);
  end
  
  
  fprintf(1,'%s%g%s%g%s\n','File ',FileN,' of ',FileNumber,' done.');
  
end

if ~isempty(gcp('nocreate'))
  delete(gcp('nocreate'))
end
