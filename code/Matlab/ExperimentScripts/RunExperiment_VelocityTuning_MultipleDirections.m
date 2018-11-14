 %%
% Run set of trials for velocity tuning experiment
% Save one data structure named with "expNumber" and date
%
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
% Last edited by Marie on 9/18/18. Added second camera.
%
% Typical use:
% RunExperiment_VelocityTuning_MultipleDirections(1, '70B12 free, R CB', 1)
%%

function [] = RunExperiment_VelocityTuning_MultipleDirections(TAKE_VIDEO, notes, expNumber)
AM_SYSTEMS = 0;
MFC_TYPE = 2;
FrameRate = 60;

if nargin < 3
   display('Please enter the following inputs:')
   display('1: TAKE_VIDEO (int) - 0 for no video, 1 for video on every trial, or N > 1 for another number of sequential videos at the start of the experiment.')
   display('2: notes (string) - any relevant notes regarding this experiment')
   display('5: exptNumber (int) - number associated with this set of trials (will append to previous if file exists with this exptNumber already)')
   return
end
%%
formatOut = 'yyyy_mm_dd';
dateStr = datestr(date, formatOut);
dirStr = ['C:\Users\nagellab\Documents\Data\' dateStr];
if ~isdir(dirStr)
    mkdir(dirStr)
end

%% load valve and MFC control signals %%%%%%%%%%%%
stimNum = randi(5); %select a random stimulus set each time (one of 5 pre-made random sets). This is technically pseudorandom. 
stimulusFilename = ['C:\Users\nagellab\Documents\Data\Stimuli\velocityTuning_MFC_controlStim_2018_08_29_' num2str(stimNum)]
%stimulusFilename = ['C:\Users\nagellab\Documents\Data\Stimuli\velocityTuning_MFC_controlStim_2018_08_23_1Trial_200cmS']
%stimulusFilename = ['C:\Users\nagellab\Documents\Data\Stimuli\velocityTuning_MFC_controlStim_2018_08_24'] %all 2L/min, lots per direction

%stimulusFilename = ['C:\Users\nagellab\Documents\Data\Stimuli\velocityTuning_MFC_controlStim_2018_08_27'] %all 2L/min, one per direction

%stimulusFilename = ['C:\Users\nagellab\Documents\Data\Stimuli\velocityTuning_MFC_controlStim_2018_08_28'] %all 2L/min, one per direction
%stimulusFilename = ['C:\Users\nagellab\Documents\Data\Stimuli\velocityTuning_MFC_controlStim_2018_08_28_1'] % one set of each valve and direction

load(stimulusFilename)
valveStates = stim.valveStates; %random valve states
stimTiming_valve = stim.stimTiming_valve;%analog control signal for valves
stimTiming_MFC = stim.stimTiming_MFC;
MFC_states_VOLTS = stim.MFC_states_VOLTS; %flow control signal (sent to MFC)
MFC_states_CM_PER_S = stim.MFC_states_CM_PER_S; %velocity in cm/s
samplerate = stim.SAMPLERATE; %10000;


%% Open data structure and count trials
% check whether a saved data file exists with today's date
saveStr = ['C:\Users\nagellab\Documents\Data\' dateStr, '\' dateStr,'_E',num2str(expNumber)]
directory = dir([saveStr, '.mat']);
if isempty(directory)
    % if no saved data exists, then this is the first trial
    nn = 0;
else
    load(saveStr, 'data'); %load current data file
    nn = length(data);     %most recent piece of data (will append to this)
    display(['Appending to existing data structure for this expt (num trials saved= ' num2str(nn) ')']);
end

%% Load first MFC control signal (prior to trial, to get up to speed), and make sure valve is OFF
display(['Loading first MFC flow rate (' num2str(MFC_states_CM_PER_S(1)) ')'])

% Reset aquisition engines
daqreset;
% Set up analog input and output via NIDAQ board
sa = daq.createSession('ni'); %establish a connection with the NIDAQ
AOch = sa.addAnalogOutputChannel('Dev1',0:1,'Voltage'); %set up two channels for output (1st for valve control, 2nd for MFC)
sa.Rate = samplerate; %samplerate (Hz)

analogOutSignal2 = ones(size(stimTiming_MFC(1,:)')).*stimTiming_MFC(1); 
analogOutSignal1 = zeros(size(stimTiming_MFC(1,:)'));

%% Set up and send digital output via NIDAQ board
sd = daq.createSession('ni'); %establish a connection with the NIDAQ
addDigitalChannel(sd,'Dev1','Port0/Line0:3','OutputOnly'); %set up digital channels for output
addDigitalChannel(sd,'Dev1','Port0/Line6:7','OutputOnly');   %set up a two more digital channels for camera triggers (2)
cmdInt = 0;%valveStates(trialNum); %convert integer to bit values to send to arduino
sa.queueOutputData([analogOutSignal1 analogOutSignal2]); %load this trial's timing signal
% Load the digital control signal for the valves and camera (to OFF)
outputSingleScan(sd,[decimalToBinaryVector(cmdInt,4) 0 0]); %load this trial's valve state, and set camera triggers to 0
% Send analog signal
dataIn = sa.startForeground; %send the data to NIDAQ analog out
pause(1) %give the MFC a chance to stabilize before beginning the first trial (this buffer is embedded within subsequent 

%% Configure input channels
AIch = sa.addAnalogInputChannel('Dev1',0:2,'Voltage'); %set up three analog inputs (voltage, current, analogOutput command)
AIch(1).TerminalConfig = 'SingleEnded';
AIch(2).TerminalConfig = 'SingleEnded';
AIch(3).TerminalConfig = 'SingleEnded';


%% Iterate through entire stimulus set
for trialNum = 1:length(valveStates)
    nn = nn + 1
    %% Save information about this piece of data
    data(nn).date = dateStr;                                % date of experiment (embedded in filename and directory_
    data(nn).expNumber = expNumber;                         % experiment number (can be multiple for one cell/fly)
    data(nn).stimulusFilename = stimulusFilename;
    data(nn).trial = nn;                                    % trial number within this experiment (can run multiple sets of trials within one experiment)
    data(nn).notes = notes;                                 % notes about experiment, e.g. genotype
    data(nn).stimName = stimulusFilename;                   % location of stimulus file
    data(nn).samplerate = samplerate;                       % samplerate of stimulus and data acquired
    data(nn).TRIAL_TIME_WIND = stim.TRIAL_TIME_WIND;        % stimulus duration (seconds)
    data(nn).PRE_TRIAL_TIME = stim.PRE_TRIAL_TIME;          % pre-stimulus duration (seconds)
    data(nn).POST_TRIAL_TIME = stim.POST_TRIAL_TIME;        % post-stimulus duration (seconds)
    data(nn).numSecOut = stim.PRE_TRIAL_TIME+stim.TRIAL_TIME_WIND+stim.POST_TRIAL_TIME;
    
    data(nn).scaleCurrent = 200;                            % scaling factor for picoamps (with MultiClamp 200B!)
    data(nn).scaleVoltage = 10;                             % scaling factor for mV

    %% Set up analog input and output via NIDAQ board
    analogOutSignal1 = stimTiming_valve(trialNum,:)';
    analogOutSignal2 = stimTiming_MFC(trialNum,:)';
    MFC_cmd = MFC_states_VOLTS(trialNum);
    MFC_LperMin = MFC_cmd./(5/MFC_TYPE);
    velocity = MFC_states_CM_PER_S(trialNum);
    cmdInt = valveStates(trialNum); %convert integer to bit values to send to arduino
    sa.queueOutputData([analogOutSignal1 analogOutSignal2]); %load this trial's timing signal
    
    display(['Trial num= ' num2str(trialNum) ' (of ' num2str(length(valveStates)) '), Valve state: ' num2str(cmdInt) ', velocity: ' num2str(velocity) ' cm/s, ' num2str(MFC_LperMin) ' L/min ( ' num2str(MFC_cmd) ' volts)'])
    
    %% Configure video acquisition
    if TAKE_VIDEO > 0
        imaqreset;
        
        data(nn).fps = FrameRate;
        data(nn).nframes = data(nn).fps*data(nn).numSecOut;
        
        %set up the first camera
        vidSaveStr = [saveStr '_Video_frontal_' num2str(nn)]
        vid1 = videoinput('dcam',1,'Y8_640x480'); %frontal camera       
        % set exposure parameters
        src = getselectedsource(vid1);
        src.ShutterMode = 'manual'; %this is important to maintain proper framerate!
        % good settings for IR lighting below fly
        src.Shutter = 800; %any higher than this and we get < 60Hz framerate
        src.AutoExposure = 70;       
        src.GainMode = 'manual';
        src.Gain = 0;
        src.Brightness = 0;
        src.FrameRate = '60';
        % set number of frames to log 
        % (this will be logged in the video file, but the only command that actually 
        %  determines framerate is set above, i.e. src.FrameRate = '60')
        framesPerTriggerValue = vid1.FramesPerTrigger;
        data(nn).fps*data(nn).numSecOut;
        vid1.FramesPerTrigger = data(nn).fps*data(nn).numSecOut; %matlab DOES NOT CARE what we enter here. This is just for our own records.        
        % set loggingMode and name of video data file
        vid1.LoggingMode = 'disk';
        vidfile = vidSaveStr;
        logfile = VideoWriter(vidfile, 'Grayscale AVI');
        set(logfile,'FrameRate',FrameRate)
        vid1.diskLogger = logfile;
        % set to wait for hardware trigger
        triggerconfig(vid1,'hardware','risingEdge','externalTrigger')
        
        
        % set up the second camera
        vidSaveStr = [saveStr '_Video_dorsal_' num2str(nn)]
        vid2 = videoinput('dcam',2,'Y8_640x480'); %camera from below
        % set exposure parameters
        src = getselectedsource(vid2);
        src.ShutterMode = 'manual'; %this is important to maintain proper framerate!
        % good settings for IR lighting below fly
        src.Shutter = 800; %any higher than this and we get < 60Hz framerate
        src.AutoExposure = 70;       
        src.GainMode = 'manual';
        src.Gain = 0;
        src.Brightness = 0;
        src.FrameRate = '60';
        % set number of frames to log 
        % (this will be logged in the video file, but the only command that actually 
        %  determines framerate is set above, i.e. src.FrameRate = '60')
        framesPerTriggerValue = vid2.FramesPerTrigger;
        data(nn).fps*data(nn).numSecOut;
        vid2.FramesPerTrigger = data(nn).fps*data(nn).numSecOut; %matlab DOES NOT CARE what we enter here. This is just for our own records.        
        % set loggingMode and name of video data file
        vid2.LoggingMode = 'disk';
        vidfile = vidSaveStr;
        logfile = VideoWriter(vidfile, 'Grayscale AVI');
        set(logfile,'FrameRate',FrameRate)
        vid2.diskLogger = logfile;
        % set to wait for hardware trigger
        triggerconfig(vid2,'hardware','risingEdge','externalTrigger')
        
        %display video data at the terminal
        vid1
        vid2
        nn
        % start the video a moment before trial starts!
        start(vid1);
        start(vid2);
    end
    
    %% Trigger camera (if taking video) and load the digital control signal for the valves
    if TAKE_VIDEO camTrig = 1; else camTrig = 0; end
    outputSingleScan(sd,[decimalToBinaryVector(cmdInt,4) camTrig camTrig]); %load this trial's valve state
    
    %% Run trial using analog signal
    dataIn = sa.startForeground; %send the data to NIDAQ analog out
    
    %% Collect data
    voltage = dataIn(:,1)*data(nn).scaleVoltage;
    current = dataIn(:,2)*data(nn).scaleCurrent;
    analogTiming_valve = dataIn(:,3);
    %analogTiming_MFC = stimTiming_MFC(trialNum,:);
    %valveState = cmdInt;
    
    data(nn).Vm = voltage; %this is x10 Vm A-M 2400 OUTPUT, x10 by Model 410 amp (x100 total)
    data(nn).I = current;  %Im Fixed Output from A-M 2400, x100 by Model 410 amp
    data(nn).analogTiming_valve = analogTiming_valve;
    %data(nn).analogTiming_MFC = analogTiming_MFC;
    data(nn).valveState = cmdInt;
    data(nn).velocity = velocity;
    data(nn).MFC_cmd = MFC_cmd;
    
    %% Save data
    save(saveStr, 'data','-v7.3');
    if TAKE_VIDEO
        delete(vid1); clear vid1
        delete(vid2); clear vid2
    end
    %plot the first two sets of trials to make sure everything looks good
    if trialNum <= 10
        PlotSingleTrial_duringExperiment(data(nn), trialNum);
    end
    
    %% set camera trigger back to low
    if TAKE_VIDEO
        outputSingleScan(sd,[decimalToBinaryVector(cmdInt,4) 0 0]); %(continue to) load this trial's valve state plus 0 at the end to reset trigger signal
    end
end

%% Plot the average traces for this set of trials!
PlotResponseTraces_SingleFly(dateStr, expNumber, 0)
