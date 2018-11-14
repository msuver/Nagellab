%%
% Run single trial, using given stimulus command signal (stimulusFileName).
% Save odor name, concentration, in one data structure with "expNumber."
%
% expNumber = experiment (fly or cell) number
% odor = odor name (string)
% concentration = concentration (number, fraction, e.g. 1:100 = 0.01)
% valveControlSignal = name of stimulus .mat file with variables 'stim' and 'samplerate'
%       'stimTiming' should be a traing of values, 0 and 1 (when this goes
%       high the current valveOn signal will be updated)
%       'valveOn' should be a train of values, 0-10, indicating which valves
%       should be on/off at any given time
%       'samplerate' should be a single number with the samplerate of 'stim' in Hz
%
% stimlus will be upsampled to 10kHz for playback.  Playback and recording
% occur at the same sample rate in 64-bit session based matlab
%
% Raw data sampled at 10kHz and saved as separate waveforms for each trial
%
% Last edited by Marie on 3/27/18. Based on K. Nagel's runNIWCwaveform.m
%   updated frame rate for below-fly-camera acquisition!
%
% Typical use:
% RunSingleTrial_DigitalAnalogOut_SaveData(1, 'ACV', 0.01, '2015_09_29_controlStim.mat', 1)
% RunSingleTrial_DigitalAnalogOut_SaveData(1, '70B12 free, R CB', 0, '2017_04_27_controlStim', 1)
%%

function [] = RunExperiment_WindDirection(TAKE_VIDEO, odor, concentration, stimFilename, expNumber)
AM_SYSTEMS = 0;
if nargin < 5
   display('Please enter the following inputs:')
   display('1: TAKE_VIDEO (int) - 0 for no video, 1 for video on every trial, or N > 1 for another number of sequential videos at the start of the experiment.')
   display('2: odor (string) - name of the odor we are applying, e.g. ''ACV'' or ''ethanol''')
   display('3: concentration (fraction), e.g. 0.01')
   display('4: stimulusFileName (string), e.g. ''2015_09_29_controlStim.mat''')
   display('5: exptNumber (int) - number associated with this set of trials (will append to previous if file exists with this exptNumber already)')
   return
end
%%
formatOut = 'yyyy_mm_dd';
dateStr = datestr(date, formatOut);
dirStr = ['C:\Users\nagellab\Documents\Data\' dateStr]
if ~isdir(dirStr)
    mkdir(dirStr)
end

%% load valve control signal
% if indicate 'random', randomly use one of a set of 5 pre-made random
%pseudo-random presentation sets!
if strcmp(stimFilename, 'random')
    randStimInd = randi(5);
    stimFilename = ['2017_04_27_4sWind_' num2str(randStimInd) '.mat']
end

load(['C:\Users\nagellab\Documents\Data\Stimuli\' stimFilename])
valveOn = controlStim.valveOn;
samplerateIn = controlStim.samplerate;
samplerateOut = 10000;
if samplerateIn ~= samplerateOut
    display('samplerateOut does not match stimulus samplerateIn');
    return
end
%% add time to end of recording equal to the "preStim" (include next
% trials' pre-stim in this one, to increase post-wind baseline recorded
% without increasing length of trials
stimTiming = [controlStim.stimTiming zeros(size(controlStim.stimTiming,1),controlStim.stimPre*samplerateOut)]; %record next signal's "preStim" in this trace as well (increase post-baseline saved)
if size(valveOn,2) ~= size(stimTiming,1)
    display('length of controlStim.valveOn is not equal to number of timing signals (controlStim.stimTiming), returning')
    return
end

%% Open data structure and count trials
% check whether a saved data file exists with today's date
saveStr = ['C:\Users\nagellab\Documents\Data\' dateStr, '/' dateStr,'_E',num2str(expNumber)]
%saveStr = [dateStr '_E',num2str(expNumber)]
directory = dir([saveStr, '.mat']);
if isempty(directory)
    % if no saved data exists, then this is the first trial
    nn = 0;
else
    load(saveStr, 'data'); %load current data file
    nn = length(data);     %most recent piece of data (will append to this)
    display(['Appending to existing data structure for this expt (num trials saved= ' num2str(nn) ')']);
end

%% Reset aquisition engines
daqreset;
sa = daq.createSession('ni'); %establish a connection with the NIDAQ
%% Configure input channels
AIch = sa.addAnalogInputChannel('Dev1',[0:2],'Voltage'); %set up three analog inputs (voltage, current, analogOutput command)

AIch(1).TerminalConfig = 'SingleEnded';
AIch(2).TerminalConfig = 'SingleEnded';
AIch(3).TerminalConfig = 'SingleEnded';
% configure outputs
sd = daq.createSession('ni'); %establish a connection with the NIDAQ
addDigitalChannel(sd,'Dev1','Port0/Line0:3','OutputOnly'); %set up a single digital channel for output
addDigitalChannel(sd,'Dev1','Port0/Line7','OutputOnly');   %set up a fourth digital channel for camera trigger
AOch = sa.addAnalogOutputChannel('Dev1',[0],'Voltage'); %set up one channels for output (1 for valve control)
sa.Rate = samplerateOut; %samplerate (Hz)

%% Iterate through entire stimulus set
for trialNum = 1:length(valveOn)
    nn = nn + 1
    %% Save information about this piece of data
    data(nn).date = dateStr;                          % date of experiment (embedded in filename and directory_
    data(nn).expNumber = expNumber;                   % experiment number (can be multiple for one cell/fly)
    data(nn).trial = nn;                              % trial number within this experiment (can run multiple sets of trials within one experiment)
    data(nn).odorName = odor;                         % odor name, e.g. ethanol
    data(nn).concentration = concentration;           % odor concentration (fraction)
    data(nn).stimName = stimFilename;                      % location of stimulus file
    data(nn).samplerate = samplerateIn;               % samplerate of stimulus and data acquired
    data(nn).stimDurationWind = controlStim.stimDurationWind; % stimulus duration (seconds)
    data(nn).stimDurationOdor = controlStim.stimDurationOdor; % stimulus duration (seconds)
    data(nn).stimPreOdor = controlStim.stimPreOdor; % stimulus duration (seconds)
    data(nn).stimPostOdor = controlStim.stimPostOdor; % stimulus duration (seconds)
    data(nn).stimPre = controlStim.stimPre;           % pre-stimulus duration (seconds)
    data(nn).stimPost = controlStim.stimPost;         % post-stimulus duration (seconds)
    data(nn).numSecOut = data(nn).stimDurationWind+data(nn).stimPost+data(nn).stimPre*2 %*2 to save this trial's pre and through the next one!
    
    data(nn).scaleCurrent = 200;     % scaling factor for picoamps (with MultiClamp 200B!)
    data(nn).scaleVoltage = 10;      % scaling factor for mV (gain = 5; previously set to 10 with gain = 10 - but that was a bit too digitized)
    
%     %% Reset aquisition engines
%     daqreset;
    %% Set up and send digital output via NIDAQ board
%     sd = daq.createSession('ni'); %establish a connection with the NIDAQ
%     addDigitalChannel(sd,'Dev1','Port0/Line0:3','OutputOnly'); %set up a single digital channel for output
%     addDigitalChannel(sd,'Dev1','Port0/Line7','OutputOnly');   %set up a fourth digital channel for camera trigger
    cmdInt = valveOn(trialNum); %convert integer to bit values to send to arduino
    display(['Trial num= ' num2str(trialNum) ' (of ' num2str(length(valveOn)) '), Valve state: ' num2str(cmdInt)])
    if TAKE_VIDEO camTrig = 1; else camTrig = 0; end
    
    %% Set up analog input and output via NIDAQ board
%     sa = daq.createSession('ni'); %establish a connection with the NIDAQ
%     AOch = sa.addAnalogOutputChannel('Dev1',[0],'Voltage'); %set up one channels for output (1 for valve control) 
%     sa.Rate = samplerateOut; %samplerate (Hz)
    analogOutSignal1 = stimTiming(trialNum,:)';
    %analogOutSignal2 = stimTimingMFC(trialNum,:)';
    sa.queueOutputData([analogOutSignal1]); %load this trial's timing signal
    
%     %% Configure input channels
%     AIch = sa.addAnalogInputChannel('Dev1',0:2,'Voltage'); %set up three analog inputs (voltage, current, analogOutput command)
%     AIch(1).TerminalConfig = 'SingleEnded';
%     AIch(2).TerminalConfig = 'SingleEnded';
%     AIch(3).TerminalConfig = 'SingleEnded';
    
    %% Configure video acquisition
    if TAKE_VIDEO > 0
        imaqreset;
        %vid = videoinput('dcam',1,'Y8_640x480');
        vid = videoinput('dcam',2,'Y8_640x480');
        
        % set exposure parameters
        src = getselectedsource(vid);
        src.ShutterMode = 'manual'; %this is important to maintain proper framerate!
        
        % old settings
        %src.Shutter = 170; 
        %src.AutoExposure = 50; %note to user: restart camera if it appears too bright or dark all of a sudden (don't change exposure, etc. settings)
        
        % good settings for IR lighting below fly
        src.Shutter = 800; %any higher than this and we get < 60Hz framerate
        src.AutoExposure = 70;
        
        % good settings for fiber optic IR from behind and below
        %src.Shutter = 800;
        %src.AutoExposure = 50; 
        
        src.GainMode = 'manual';
        src.Gain = 0;
        src.Brightness = 0;

        src.FrameRate = '60';
        FrameRate = 60;
        
        % set number of frames to log 
        % (this will be logged in the video file, but the only command that actually 
        %  determines framerate is set above, i.e. src.FrameRate = '60')
        data(nn).fps = FrameRate;
        data(nn).nframes = data(nn).fps*data(nn).numSecOut;
        framesPerTriggerValue = vid.FramesPerTrigger;
        data(nn).fps*data(nn).numSecOut;
        vid.FramesPerTrigger = data(nn).fps*data(nn).numSecOut; %matlab DOES NOT CARE what we enter here. This is just for our own records.
        
        % set loggingMode and name of video data file
        vid.LoggingMode = 'disk';
        [saveStr '_Video_' num2str(nn)]
        vidfile = [saveStr '_Video_' num2str(nn)];
        logfile = VideoWriter(vidfile, 'Grayscale AVI');
        set(logfile,'FrameRate',FrameRate)
        vid.diskLogger = logfile;
        
        % set to wait for hardware trigger
        triggerconfig(vid,'hardware','risingEdge','externalTrigger')
        vid
        % start the video a moment before trial starts!
        nn
        start(vid);
    end
    
    %% Trigger camera (if taking video) and load the digital control signal for the valves
    outputSingleScan(sd,[decimalToBinaryVector(cmdInt,4) camTrig]); %load this trial's valve state
    
    %% Run trial using analog signal
    dataIn = sa.startForeground; %send the data to NIDAQ analog out
    
    %% Collect data
    voltage = dataIn(:,1)*data(nn).scaleVoltage;
    current = dataIn(:,2)*data(nn).scaleCurrent;
    analogTiming = dataIn(:,3);
    valveState = cmdInt;
    
    data(nn).Vm = voltage; %this is x10 Vm A-M 2400 OUTPUT, x10 by Model 410 amp (x100 total)
    data(nn).I = current;  %Im Fixed Output from A-M 2400, x100 by Model 410 amp
    data(nn).analogTiming = analogTiming;
    data(nn).valveState = cmdInt;
    
    %% Save data
    save(saveStr, 'data');
    if TAKE_VIDEO
        delete(vid); clear vid
    end
    %plot the first two sets of trials to make sure everything looks good
    if trialNum <= 10
        PlotSingleTrial(data(nn), trialNum, 'expt');
    end
    
    %% set camera trigger back to low
    if TAKE_VIDEO
        outputSingleScan(sd,[decimalToBinaryVector(cmdInt,4) 0]); %(continue to) load this trial's valve state plus 0 at the end to reset trigger signal
    end
end

%% Plot the average traces for this set of trials!
PlotTraces_singleFly(dateStr, expNumber, 0, 0, 0)
