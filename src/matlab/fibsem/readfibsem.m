function FIBSEMData = readfibsem(FullPathFile)
% Read raw data file (*.dat) generated from Neon
% Needs PathName and FileName
%
% Rev history
% 04/17/09 
%   1st rev.
% 07/31/2011
%   converted from script to function
% 11/25/2012
%   added support for file version 5
% 6/20/2013
%   read raw data up to
%   [FIBSEMData.ChanNum,FIBSEMData.XResolution*FIBSEMData.YResolution]
% 6/25/2013
%   added support for file version 6
% 7/10/2013
%   added decimating factor
% 7/1/2014
%   added file version 7 for 8-bit data support
% 7/4/2015
%   added file version 8 support
% 7/25/2017
%   added support for files with partial image
% 4/15/2020
%   revised version 8 16-bit electron counts conversion
% 6/14/2020
%   added a scaling factor of electron counts of 16-bit version 8
%   *.dat files
% 11/17/2020
%   added file version 9 support
%

%% Load raw data file
fid = fopen(FullPathFile,'r', 's'); % Open the file written by LabView (big-endian byte ordering and 64-bit long data type)

% Start header read
fseek(fid,0,'bof'); FIBSEMData.FileMagicNum = fread(fid,1,'uint32'); % Read in magic number, should be 3555587570
fseek(fid,4,'bof'); FIBSEMData.FileVersion = fread(fid,1,'uint16'); % Read in file version number
fseek(fid,6,'bof'); FIBSEMData.FileType = fread(fid,1,'uint16'); % Read in file type, 1 is Zeiss Neon detectors
fseek(fid,8,'bof'); FIBSEMData.SWdate = fread(fid,10,'*char')'; % Read in SW date
fseek(fid,24,'bof'); FIBSEMData.TimeStep = fread(fid,1,'double'); % Read in AI sampling time (including oversampling) in seconds
fseek(fid,32,'bof'); FIBSEMData.ChanNum = fread(fid,1,'uint8'); % Read in number of channels
fseek(fid,33,'bof'); FIBSEMData.EightBit = fread(fid,1,'uint8'); % Read in 8-bit data switch
switch FIBSEMData.FileVersion
  case 1
    fseek(fid,36,'bof'); FIBSEMData.Scaling = single(fread(fid,[4,FIBSEMData.ChanNum],'double')); % Read in AI channel scaling factors, (col#: AI#), (row#: offset, gain, 2nd order, 3rd order)
  case {2,3,4,5,6}
    fseek(fid,36,'bof'); FIBSEMData.Scaling = fread(fid,[4,FIBSEMData.ChanNum],'single');
  otherwise
    fseek(fid,36,'bof'); FIBSEMData.Scaling = fread(fid,[4,2],'single');
end
switch FIBSEMData.FileVersion
  case {1,2,3,4,5,6,7,8}
  otherwise
    fseek(fid,68,'bof'); FIBSEMData.RestartFlag = fread(fid,1,'uint8'); % Read in restart flag
    fseek(fid,69,'bof'); FIBSEMData.StageMove = fread(fid,1,'uint8'); % Read in stage move flag
    fseek(fid,70,'bof'); FIBSEMData.FirstPixelX = fread(fid,1,'int32'); % Read in first pixel X coordinate (center = 0)
    fseek(fid,74,'bof'); FIBSEMData.FirstPixelY = fread(fid,1,'int32'); % Read in first pixel Y coordinate (center = 0)
end
fseek(fid,100,'bof'); FIBSEMData.XResolution = fread(fid,1,'uint32'); % X resolution
fseek(fid,104,'bof'); FIBSEMData.YResolution = fread(fid,1,'uint32'); % Y resolution
switch FIBSEMData.FileVersion
  case {1,2,3}
    fseek(fid,108,'bof'); FIBSEMData.Oversampling = fread(fid,1,'uint8'); % AI oversampling
    fseek(fid,109,'bof'); FIBSEMData.AIDelay = fread(fid,1,'int16'); % Read AI delay (# of samples)
  otherwise
    fseek(fid,108,'bof'); FIBSEMData.Oversampling = fread(fid,1,'uint16'); % AI oversampling
end
fseek(fid,111,'bof'); FIBSEMData.ZeissScanSpeed = fread(fid,1,'uint8'); % Scan speed (Zeiss #)
switch FIBSEMData.FileVersion
  case {1,2,3}
    fseek(fid,112,'bof'); FIBSEMData.ScanRate = fread(fid,1,'double'); % Actual AO (scanning) rate
    fseek(fid,120,'bof'); FIBSEMData.FramelineRampdownRatio = fread(fid,1,'double'); % Frameline rampdown ratio
    fseek(fid,128,'bof'); FIBSEMData.Xmin = fread(fid,1,'double'); % X coil minimum voltage
    fseek(fid,136,'bof'); FIBSEMData.Xmax = fread(fid,1,'double'); % X coil maximum voltage
    FIBSEMData.Detmin = -10; % Detector minimum voltage
    FIBSEMData.Detmax = 10; % Detector maximum voltage
  otherwise
    fseek(fid,112,'bof'); FIBSEMData.ScanRate = fread(fid,1,'single'); % Actual AO (scanning) rate
    fseek(fid,116,'bof'); FIBSEMData.FramelineRampdownRatio = fread(fid,1,'single'); % Frameline rampdown ratio
    fseek(fid,120,'bof'); FIBSEMData.Xmin = fread(fid,1,'single'); % X coil minimum voltage
    fseek(fid,124,'bof'); FIBSEMData.Xmax = fread(fid,1,'single'); % X coil maximum voltage
    fseek(fid,128,'bof'); FIBSEMData.Detmin = fread(fid,1,'single'); % Detector minimum voltage
    fseek(fid,132,'bof'); FIBSEMData.Detmax = fread(fid,1,'single'); % Detector maximum voltage
    fseek(fid,136,'bof'); FIBSEMData.DecimatingFactor = fread(fid,1,'uint16'); % Decimating factor
end
fseek(fid,151,'bof'); FIBSEMData.AI1 = fread(fid,1,'uint8'); % AI Ch1
fseek(fid,152,'bof'); FIBSEMData.AI2 = fread(fid,1,'uint8'); % AI Ch2
fseek(fid,153,'bof'); FIBSEMData.AI3 = fread(fid,1,'uint8'); % AI Ch3
fseek(fid,154,'bof'); FIBSEMData.AI4 = fread(fid,1,'uint8'); % AI Ch4
switch FIBSEMData.FileVersion
  case {1,2,3,4,5,6,7,8}
  otherwise
    fseek(fid,155,'bof'); FIBSEMData.SampleID = fread(fid,25,'*char')'; % Read in Sample ID
end
fseek(fid,180,'bof'); FIBSEMData.Notes = fread(fid,200,'*char')'; % Read in notes

switch FIBSEMData.FileVersion
  case {1,2}
    fseek(fid,380,'bof'); FIBSEMData.DetA = fread(fid,10,'*char')'; % Name of detector A
    fseek(fid,390,'bof'); FIBSEMData.DetB = fread(fid,18,'*char')'; % Name of detector B
    fseek(fid,700,'bof'); FIBSEMData.DetC = fread(fid,20,'*char')'; % Name of detector C
    fseek(fid,720,'bof'); FIBSEMData.DetD = fread(fid,20,'*char')'; % Name of detector D
    fseek(fid,408,'bof'); FIBSEMData.Mag = fread(fid,1,'double'); % Magnification
    fseek(fid,416,'bof'); FIBSEMData.PixelSize = fread(fid,1,'double'); % Pixel size in nm
    fseek(fid,424,'bof'); FIBSEMData.WD = fread(fid,1,'double'); % Working distance in mm
    fseek(fid,432,'bof'); FIBSEMData.EHT = fread(fid,1,'double'); % EHT in kV
    fseek(fid,440,'bof'); FIBSEMData.SEMApr = fread(fid,1,'uint8'); % SEM aperture number
    fseek(fid,441,'bof'); FIBSEMData.HighCurrent = fread(fid,1,'uint8'); % high current mode (1=on, 0=off)
    fseek(fid,448,'bof'); FIBSEMData.SEMCurr = fread(fid,1,'double'); % SEM probe current in A
    fseek(fid,456,'bof'); FIBSEMData.SEMRot = fread(fid,1,'double'); % SEM scan roation in degree
    fseek(fid,464,'bof'); FIBSEMData.ChamVac = fread(fid,1,'double'); % Chamber vacuum
    fseek(fid,472,'bof'); FIBSEMData.GunVac = fread(fid,1,'double'); % E-gun vacuum
    fseek(fid,480,'bof'); FIBSEMData.SEMStiX = fread(fid,1,'double'); % SEM stigmation X
    fseek(fid,488,'bof'); FIBSEMData.SEMStiY = fread(fid,1,'double'); % SEM stigmation Y
    fseek(fid,496,'bof'); FIBSEMData.SEMAlnX = fread(fid,1,'double'); % SEM aperture alignment X
    fseek(fid,504,'bof'); FIBSEMData.SEMAlnY = fread(fid,1,'double'); % SEM aperture alignment Y
    fseek(fid,512,'bof'); FIBSEMData.StageX = fread(fid,1,'double'); % Stage position X in mm
    fseek(fid,520,'bof'); FIBSEMData.StageY = fread(fid,1,'double'); % Stage position Y in mm
    fseek(fid,528,'bof'); FIBSEMData.StageZ = fread(fid,1,'double'); % Stage position Z in mm
    fseek(fid,536,'bof'); FIBSEMData.StageT = fread(fid,1,'double'); % Stage position T in degree
    fseek(fid,544,'bof'); FIBSEMData.StageR = fread(fid,1,'double'); % Stage position R in degree
    fseek(fid,552,'bof'); FIBSEMData.StageM = fread(fid,1,'double'); % Stage position M in mm
    fseek(fid,560,'bof'); FIBSEMData.BrightnessA = fread(fid,1,'double'); % Detector A brightness (%)
    fseek(fid,568,'bof'); FIBSEMData.ContrastA = fread(fid,1,'double'); % Detector A contrast (%)
    fseek(fid,576,'bof'); FIBSEMData.BrightnessB = fread(fid,1,'double'); % Detector B brightness (%)
    fseek(fid,584,'bof'); FIBSEMData.ContrastB = fread(fid,1,'double'); % Detector B contrast (%)
    
    fseek(fid,600,'bof'); FIBSEMData.Mode = fread(fid,1,'uint8'); % FIB mode: 0=SEM, 1=FIB, 2=Milling, 3=SEM+FIB, 4=Mill+SEM, 5=SEM Drift Correction, 6=FIB Drift Correction, 7=No Beam, 8=External, 9=External+SEM
    fseek(fid,608,'bof'); FIBSEMData.FIBFocus = fread(fid,1,'double'); % FIB focus in kV
    fseek(fid,616,'bof'); FIBSEMData.FIBProb = fread(fid,1,'uint8'); % FIB probe number
    fseek(fid,624,'bof'); FIBSEMData.FIBCurr = fread(fid,1,'double'); % FIB emission current
    fseek(fid,632,'bof'); FIBSEMData.FIBRot = fread(fid,1,'double'); % FIB scan rotation
    fseek(fid,640,'bof'); FIBSEMData.FIBAlnX = fread(fid,1,'double'); % FIB aperture alignment X
    fseek(fid,648,'bof'); FIBSEMData.FIBAlnY = fread(fid,1,'double'); % FIB aperture alignment Y
    fseek(fid,656,'bof'); FIBSEMData.FIBStiX = fread(fid,1,'double'); % FIB stigmation X
    fseek(fid,664,'bof'); FIBSEMData.FIBStiY = fread(fid,1,'double'); % FIB stigmation Y
    fseek(fid,672,'bof'); FIBSEMData.FIBShiftX = fread(fid,1,'double'); % FIB beam shift X in micron
    fseek(fid,680,'bof'); FIBSEMData.FIBShiftY = fread(fid,1,'double'); % FIB beam shift Y in micron
  otherwise
    fseek(fid,380,'bof'); FIBSEMData.DetA = fread(fid,10,'*char')'; % Name of detector A
    fseek(fid,390,'bof'); FIBSEMData.DetB = fread(fid,18,'*char')'; % Name of detector B
    fseek(fid,410,'bof'); FIBSEMData.DetC = fread(fid,20,'*char')'; % Name of detector C
    fseek(fid,430,'bof'); FIBSEMData.DetD = fread(fid,20,'*char')'; % Name of detector D
    fseek(fid,460,'bof'); FIBSEMData.Mag = fread(fid,1,'single'); % Magnification
    fseek(fid,464,'bof'); FIBSEMData.PixelSize = fread(fid,1,'single'); % Pixel size in nm
    fseek(fid,468,'bof'); FIBSEMData.WD = fread(fid,1,'single'); % Working distance in mm
    fseek(fid,472,'bof'); FIBSEMData.EHT = fread(fid,1,'single'); % EHT in kV
    fseek(fid,480,'bof'); FIBSEMData.SEMApr = fread(fid,1,'uint8'); % SEM aperture number
    fseek(fid,481,'bof'); FIBSEMData.HighCurrent = fread(fid,1,'uint8'); % high current mode (1=on, 0=off)
    fseek(fid,490,'bof'); FIBSEMData.SEMCurr = fread(fid,1,'single'); % SEM probe current in A
    fseek(fid,494,'bof'); FIBSEMData.SEMRot = fread(fid,1,'single'); % SEM scan roation in degree
    fseek(fid,498,'bof'); FIBSEMData.ChamVac = fread(fid,1,'single'); % Chamber vacuum
    fseek(fid,502,'bof'); FIBSEMData.GunVac = fread(fid,1,'single'); % E-gun vacuum
    fseek(fid,510,'bof'); FIBSEMData.SEMShiftX = fread(fid,1,'single'); % SEM beam shift X
    fseek(fid,514,'bof'); FIBSEMData.SEMShiftY = fread(fid,1,'single'); % SEM beam shift Y
    fseek(fid,518,'bof'); FIBSEMData.SEMStiX = fread(fid,1,'single'); % SEM stigmation X
    fseek(fid,522,'bof'); FIBSEMData.SEMStiY = fread(fid,1,'single'); % SEM stigmation Y
    fseek(fid,526,'bof'); FIBSEMData.SEMAlnX = fread(fid,1,'single'); % SEM aperture alignment X
    fseek(fid,530,'bof'); FIBSEMData.SEMAlnY = fread(fid,1,'single'); % SEM aperture alignment Y
    fseek(fid,534,'bof'); FIBSEMData.StageX = fread(fid,1,'single'); % Stage position X in mm
    fseek(fid,538,'bof'); FIBSEMData.StageY = fread(fid,1,'single'); % Stage position Y in mm
    fseek(fid,542,'bof'); FIBSEMData.StageZ = fread(fid,1,'single'); % Stage position Z in mm
    fseek(fid,546,'bof'); FIBSEMData.StageT = fread(fid,1,'single'); % Stage position T in degree
    fseek(fid,550,'bof'); FIBSEMData.StageR = fread(fid,1,'single'); % Stage position R in degree
    fseek(fid,554,'bof'); FIBSEMData.StageM = fread(fid,1,'single'); % Stage position M in mm
    fseek(fid,560,'bof'); FIBSEMData.BrightnessA = fread(fid,1,'single'); % Detector A brightness (%)
    fseek(fid,564,'bof'); FIBSEMData.ContrastA = fread(fid,1,'single'); % Detector A contrast (%)
    fseek(fid,568,'bof'); FIBSEMData.BrightnessB = fread(fid,1,'single'); % Detector B brightness (%)
    fseek(fid,572,'bof'); FIBSEMData.ContrastB = fread(fid,1,'single'); % Detector B contrast (%)
    
    fseek(fid,600,'bof'); FIBSEMData.Mode = fread(fid,1,'uint8'); % FIB mode: 0=SEM, 1=FIB, 2=Milling, 3=SEM+FIB, 4=Mill+SEM, 5=SEM Drift Correction, 6=FIB Drift Correction, 7=No Beam, 8=External, 9=External+SEM
    fseek(fid,604,'bof'); FIBSEMData.FIBFocus = fread(fid,1,'single'); % FIB focus in kV
    fseek(fid,608,'bof'); FIBSEMData.FIBProb = fread(fid,1,'uint8'); % FIB probe number
    fseek(fid,620,'bof'); FIBSEMData.FIBCurr = fread(fid,1,'single'); % FIB emission current
    fseek(fid,624,'bof'); FIBSEMData.FIBRot = fread(fid,1,'single'); % FIB scan rotation
    fseek(fid,628,'bof'); FIBSEMData.FIBAlnX = fread(fid,1,'single'); % FIB aperture alignment X
    fseek(fid,632,'bof'); FIBSEMData.FIBAlnY = fread(fid,1,'single'); % FIB aperture alignment Y
    fseek(fid,636,'bof'); FIBSEMData.FIBStiX = fread(fid,1,'single'); % FIB stigmation X
    fseek(fid,640,'bof'); FIBSEMData.FIBStiY = fread(fid,1,'single'); % FIB stigmation Y
    fseek(fid,644,'bof'); FIBSEMData.FIBShiftX = fread(fid,1,'single'); % FIB beam shift X in micron
    fseek(fid,648,'bof'); FIBSEMData.FIBShiftY = fread(fid,1,'single'); % FIB beam shift Y in micron
end

switch FIBSEMData.FileVersion
  case {1,2,3,4}
  otherwise
    fseek(fid,652,'bof'); FIBSEMData.MillingXResolution = fread(fid,1,'uint32'); % FIB milling X resolution
    fseek(fid,656,'bof'); FIBSEMData.MillingYResolution = fread(fid,1,'uint32'); % FIB milling Y resolution
    fseek(fid,660,'bof'); FIBSEMData.MillingXSize = fread(fid,1,'single'); % FIB milling X size (um)
    fseek(fid,664,'bof'); FIBSEMData.MillingYSize = fread(fid,1,'single'); % FIB milling Y size (um)
    fseek(fid,668,'bof'); FIBSEMData.MillingULAng = fread(fid,1,'single'); % FIB milling upper left inner angle (deg)
    fseek(fid,672,'bof'); FIBSEMData.MillingURAng = fread(fid,1,'single'); % FIB milling upper right inner angle (deg)
    fseek(fid,676,'bof'); FIBSEMData.MillingLineTime = fread(fid,1,'single'); % FIB line milling time (s)
    fseek(fid,680,'bof'); FIBSEMData.FIBFOV = fread(fid,1,'single'); % FIB FOV (um)
    fseek(fid,684,'bof'); FIBSEMData.MillingLinesPerImage = fread(fid,1,'uint16'); % FIB milling lines per image
    fseek(fid,686,'bof'); FIBSEMData.MillingPIDOn = fread(fid,1,'uint8'); % FIB milling PID on
    fseek(fid,689,'bof'); FIBSEMData.MillingPIDMeasured = fread(fid,1,'uint8'); % FIB milling PID measured (0:specimen, 1:beamdump)
    fseek(fid,690,'bof'); FIBSEMData.MillingPIDTarget = fread(fid,1,'single'); % FIB milling PID target
    fseek(fid,694,'bof'); FIBSEMData.MillingPIDTargetSlope = fread(fid,1,'single'); % FIB milling PID target slope
    fseek(fid,698,'bof'); FIBSEMData.MillingPIDP = fread(fid,1,'single'); % FIB milling PID P
    fseek(fid,702,'bof'); FIBSEMData.MillingPIDI = fread(fid,1,'single'); % FIB milling PID I
    fseek(fid,706,'bof'); FIBSEMData.MillingPIDD = fread(fid,1,'single'); % FIB milling PID D
    fseek(fid,800,'bof'); FIBSEMData.MachineID = fread(fid,30,'*char')'; % Machine ID
    fseek(fid,980,'bof'); FIBSEMData.SEMSpecimenI = fread(fid,1,'single'); % SEM specimen current (nA)
end

switch FIBSEMData.FileVersion
  case {1,2,3,4,5}
  otherwise
    fseek(fid,850,'bof'); FIBSEMData.Temperature = fread(fid,1,'single'); % Temperature (F)
    fseek(fid,854,'bof'); FIBSEMData.FaradayCupI = fread(fid,1,'single'); % Faraday cup current (nA)
    fseek(fid,858,'bof'); FIBSEMData.FIBSpecimenI = fread(fid,1,'single'); % FIB specimen current (nA)
    fseek(fid,862,'bof'); FIBSEMData.BeamDump1I = fread(fid,1,'single'); % Beam dump 1 current (nA)
    fseek(fid,866,'bof'); FIBSEMData.SEMSpecimenI = fread(fid,1,'single'); % SEM specimen current (nA)
    fseek(fid,870,'bof'); FIBSEMData.MillingYVoltage = fread(fid,1,'single'); % Milling Y voltage (V)
    fseek(fid,874,'bof'); FIBSEMData.FocusIndex = fread(fid,1,'single'); % Focus index
    fseek(fid,878,'bof'); FIBSEMData.FIBSliceNum = fread(fid,1,'uint32'); % FIB slice #
end

switch FIBSEMData.FileVersion
  case {1,2,3,4,5,6,7}
  otherwise
    fseek(fid,882,'bof'); FIBSEMData.BeamDump2I = fread(fid,1,'single'); % Beam dump 2 current (nA)
    fseek(fid,886,'bof'); FIBSEMData.MillingI = fread(fid,1,'single'); % Milling current (nA)
end

fseek(fid,1000,'bof'); FIBSEMData.FileLength = fread(fid,1,'int64'); % Read in file length in bytes
% Finish header read

if FIBSEMData.EightBit==1
  fseek(fid,1024,'bof'); Raw = (fread(fid,[FIBSEMData.ChanNum,FIBSEMData.XResolution*FIBSEMData.YResolution],'*uint8'))'; % Read in raw AI the "*" is needed to read long set of data
  missing = uint8(zeros(FIBSEMData.XResolution*FIBSEMData.YResolution-size(Raw,1),2)); % creates missing element array
  Raw = vertcat(Raw, missing); % concatenate zeros to the correct size of raw data
else
  fseek(fid,1024,'bof'); Raw = (fread(fid,[FIBSEMData.ChanNum,FIBSEMData.XResolution*FIBSEMData.YResolution],'*int16'))'; % Read in raw AI the "*" is needed to read long set of data
  missing = int16(zeros(FIBSEMData.XResolution*FIBSEMData.YResolution-size(Raw,1),2)); % creates missing element array
  Raw = vertcat(Raw, missing); % concatenate zeros to the correct size of raw data
end
fclose(fid); % Close the file

%% Convert raw data to electron counts
if FIBSEMData.EightBit==1
  RawTemp=Raw;
  Raw=int16(Raw);
  if FIBSEMData.AI1
    DetectorA = RawTemp(:,1);
    Raw(:,1)=int16(single(Raw(:,1))*FIBSEMData.ScanRate/FIBSEMData.Scaling(1,1)/FIBSEMData.Scaling(3,1)/FIBSEMData.Scaling(4,1)+FIBSEMData.Scaling(2,1));
    if FIBSEMData.AI2
      DetectorB = RawTemp(:,2);
      Raw(:,2)=int16(single(Raw(:,2))*FIBSEMData.ScanRate/FIBSEMData.Scaling(1,2)/FIBSEMData.Scaling(3,2)/FIBSEMData.Scaling(4,2)+FIBSEMData.Scaling(2,2));
    end
  elseif FIBSEMData.AI2
    DetectorB = RawTemp(:,1);
    Raw(:,1)=int16(single(Raw(:,1))*FIBSEMData.ScanRate/FIBSEMData.Scaling(1,2)/FIBSEMData.Scaling(3,2)/FIBSEMData.Scaling(4,2)+FIBSEMData.Scaling(2,2));
  end
else
  switch FIBSEMData.FileVersion
    case {1,2,3,4,5,6}
      if FIBSEMData.AI1
        DetectorA = FIBSEMData.Scaling(1,1)+single(Raw(:,1))*FIBSEMData.Scaling(2,1); % Converts raw I16 data to voltage based on scaling factors
        if FIBSEMData.AI2
          DetectorB = FIBSEMData.Scaling(1,2)+single(Raw(:,2))*FIBSEMData.Scaling(2,2); % Converts raw I16 data to voltage based on scaling factors
          if FIBSEMData.AI3
            DetectorC = FIBSEMData.Scaling(1,3)+single(Raw(:,3))*FIBSEMData.Scaling(2,3);
            if FIBSEMData.AI4
              DetectorD = FIBSEMData.Scaling(1,4)+single(Raw(:,4))*FIBSEMData.Scaling(2,4);
            end
          elseif FIBSEMData.AI4
            DetectorD = FIBSEMData.Scaling(1,3)+single(Raw(:,3))*FIBSEMData.Scaling(2,3);
          end
        elseif FIBSEMData.AI3
          DetectorC = FIBSEMData.Scaling(1,2)+single(Raw(:,2))*FIBSEMData.Scaling(2,2);
          if FIBSEMData.AI4
            DetectorD = FIBSEMData.Scaling(1,3)+single(Raw(:,3))*FIBSEMData.Scaling(2,3);
          end
        elseif FIBSEMData.AI4
          DetectorD = FIBSEMData.Scaling(1,2)+single(Raw(:,2))*FIBSEMData.Scaling(2,2);
        end
      elseif FIBSEMData.AI2
        DetectorB = FIBSEMData.Scaling(1,1)+single(Raw(:,1))*FIBSEMData.Scaling(2,1);
        if FIBSEMData.AI3
          DetectorC = FIBSEMData.Scaling(1,2)+single(Raw(:,2))*FIBSEMData.Scaling(2,2);
          if FIBSEMData.AI4
            DetectorD = FIBSEMData.Scaling(1,3)+single(Raw(:,3))*FIBSEMData.Scaling(2,3);
          end
        elseif FIBSEMData.AI4
          DetectorD = FIBSEMData.Scaling(1,2)+single(Raw(:,2))*FIBSEMData.Scaling(2,2);
        end
      elseif FIBSEMData.AI3
        DetectorC = FIBSEMData.Scaling(1,1)+single(Raw(:,1))*FIBSEMData.Scaling(2,1);
        if FIBSEMData.AI4
          DetectorD = FIBSEMData.Scaling(1,2)+single(Raw(:,2))*FIBSEMData.Scaling(2,2);
        end
      elseif FIBSEMData.AI4
        DetectorD = FIBSEMData.Scaling(1,1)+single(Raw(:,1))*FIBSEMData.Scaling(2,1);
      end
    case {7}
      if FIBSEMData.AI1
        DetectorA = (single(Raw(:,1))-FIBSEMData.Scaling(2,1))*FIBSEMData.Scaling(3,1); % Converts raw I16 data to voltage based on scaling factors
        if FIBSEMData.AI2
          DetectorB = (single(Raw(:,2))-FIBSEMData.Scaling(2,2))*FIBSEMData.Scaling(3,2);
        end
      elseif FIBSEMData.AI2
        DetectorB = (single(Raw(:,1))-FIBSEMData.Scaling(2,2))*FIBSEMData.Scaling(3,2);
      end
    case {8,9} 
      ElectronFactor1=0.1; % 16-bit intensity is 10x electron counts
      FIBSEMData.Scaling(4,1)=ElectronFactor1;
      ElectronFactor2=0.1; % 16-bit intensity is 10x electron counts
      FIBSEMData.Scaling(4,2)=ElectronFactor2;
      if FIBSEMData.AI1
        DetectorA=(single(Raw(:,1))-FIBSEMData.Scaling(2,1))*FIBSEMData.Scaling(3,1)/FIBSEMData.ScanRate*FIBSEMData.Scaling(1,1)/ElectronFactor1;
        if FIBSEMData.AI2
          DetectorB=(single(Raw(:,2))-FIBSEMData.Scaling(2,2))*FIBSEMData.Scaling(3,2)/FIBSEMData.ScanRate*FIBSEMData.Scaling(1,2)/ElectronFactor2;
        end
      elseif FIBSEMData.AI2
        DetectorB=(single(Raw(:,1))-FIBSEMData.Scaling(2,2))*FIBSEMData.Scaling(3,2)/FIBSEMData.ScanRate*FIBSEMData.Scaling(1,2)/ElectronFactor2;
      end 
  end
end
%% Construct image files
if FIBSEMData.AI1
  FIBSEMData.ImageA = (reshape(DetectorA,FIBSEMData.XResolution,FIBSEMData.YResolution))';
  FIBSEMData.RawImageA = (reshape(Raw(:,1),FIBSEMData.XResolution,FIBSEMData.YResolution))';
  if FIBSEMData.AI2
    FIBSEMData.ImageB = (reshape(DetectorB,FIBSEMData.XResolution,FIBSEMData.YResolution))';
    FIBSEMData.RawImageB = (reshape(Raw(:,2),FIBSEMData.XResolution,FIBSEMData.YResolution))';
    if FIBSEMData.AI3
      FIBSEMData.ImageC = (reshape(DetectorC,FIBSEMData.XResolution,FIBSEMData.YResolution))';
      FIBSEMData.RawImageC = (reshape(Raw(:,3),FIBSEMData.XResolution,FIBSEMData.YResolution))';
      if FIBSEMData.AI4
        FIBSEMData.ImageD = (reshape(DetectorD,FIBSEMData.XResolution,FIBSEMData.YResolution))';
        FIBSEMData.RawImageD = (reshape(Raw(:,4),FIBSEMData.XResolution,FIBSEMData.YResolution))';
      end
    elseif FIBSEMData.AI4
      FIBSEMData.ImageD = (reshape(DetectorD,FIBSEMData.XResolution,FIBSEMData.YResolution))';
      FIBSEMData.RawImageD = (reshape(Raw(:,3),FIBSEMData.XResolution,FIBSEMData.YResolution))';
    end
  elseif FIBSEMData.AI3
    FIBSEMData.ImageC = (reshape(DetectorC,FIBSEMData.XResolution,FIBSEMData.YResolution))';
    FIBSEMData.RawImageC = (reshape(Raw(:,2),FIBSEMData.XResolution,FIBSEMData.YResolution))';
    if FIBSEMData.AI4
      FIBSEMData.ImageD = (reshape(DetectorD,FIBSEMData.XResolution,FIBSEMData.YResolution))';
      FIBSEMData.RawImageD = (reshape(Raw(:,3),FIBSEMData.XResolution,FIBSEMData.YResolution))';
    end
  elseif FIBSEMData.AI4
    FIBSEMData.ImageD = (reshape(DetectorD,FIBSEMData.XResolution,FIBSEMData.YResolution))';
    FIBSEMData.RawImageD = (reshape(Raw(:,2),FIBSEMData.XResolution,FIBSEMData.YResolution))';
  end
elseif FIBSEMData.AI2
  FIBSEMData.ImageB = (reshape(DetectorB,FIBSEMData.XResolution,FIBSEMData.YResolution))';
  FIBSEMData.RawImageB = (reshape(Raw(:,1),FIBSEMData.XResolution,FIBSEMData.YResolution))';
  if FIBSEMData.AI3
    FIBSEMData.ImageC = (reshape(DetectorC,FIBSEMData.XResolution,FIBSEMData.YResolution))';
    FIBSEMData.RawImageC = (reshape(Raw(:,2),FIBSEMData.XResolution,FIBSEMData.YResolution))';
    if FIBSEMData.AI4
      FIBSEMData.ImageD = (reshape(DetectorD,FIBSEMData.XResolution,FIBSEMData.YResolution))';
      FIBSEMData.RawImageD = (reshape(Raw(:,3),FIBSEMData.XResolution,FIBSEMData.YResolution))';
    end
  elseif FIBSEMData.AI4
    FIBSEMData.ImageD = (reshape(DetectorD,FIBSEMData.XResolution,FIBSEMData.YResolution))';
    FIBSEMData.RawImageD = (reshape(Raw(:,2),FIBSEMData.XResolution,FIBSEMData.YResolution))';
  end
elseif FIBSEMData.AI3
  FIBSEMData.ImageC = (reshape(DetectorC,FIBSEMData.XResolution,FIBSEMData.YResolution))';
  FIBSEMData.RawImageC = (reshape(Raw(:,1),FIBSEMData.XResolution,FIBSEMData.YResolution))';
  if FIBSEMData.AI4
    FIBSEMData.ImageD = (reshape(DetectorD,FIBSEMData.XResolution,FIBSEMData.YResolution))';
    FIBSEMData.RawImageD = (reshape(Raw(:,2),FIBSEMData.XResolution,FIBSEMData.YResolution))';
  end
elseif FIBSEMData.AI4
  FIBSEMData.ImageD = (reshape(DetectorD,FIBSEMData.XResolution,FIBSEMData.YResolution))';
  FIBSEMData.RawImageD = (reshape(Raw(:,1),FIBSEMData.XResolution,FIBSEMData.YResolution))';
end
  