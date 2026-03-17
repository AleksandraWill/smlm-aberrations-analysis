clear all
close all

% Set the full path to the file you want to process:
path_input_data = 'D:\projekt\aberrations_measurement\data\beads_blue_bypass\avg_pos1_blue.tif';
% Set the output folder (can be the same as the input folder):
path_output_data = 'D:\projekt\aberrations_measurement\data\beads_blue_bypass\';


%% Debugging Flag
debug_mode = false;
%% Main script to automate aberration measurement for a single bead Z-stack
%% 1. Load objective and camera
objectiveFile = 'C:\Users\Aleksandra\AppData\Roaming\MathWorks\MATLAB Add-Ons\Apps\AberrationMeasurementAutomationextractedtired\user data\objective lenses\Olympus_100x_1.46NA_SDT1.mat';
cameraFile = 'C:\Users\Aleksandra\AppData\Roaming\MathWorks\MATLAB Add-Ons\Apps\AberrationMeasurementAutomationextractedtired\user data\cameras\Andor_SDT1.mat';

obj = load(objectiveFile, 'obj').obj;
cam = load(cameraFile, 'cam').cam;

disp(['Loaded Objective: ', obj.name]);
disp(['Loaded Camera: ', cam.name]);

%% 2. Add the folder containing create_coord.m, ZernikeCalc.m to the MATLAB path
addpath('C:\Users\Aleksandra\AppData\Roaming\MathWorks\MATLAB Add-Ons\Apps\AberrationMeasurementAutomationextractedtired\functions');
addpath('C:\Users\Aleksandra\AppData\Roaming\MathWorks\MATLAB Add-Ons\Apps\AberrationMeasurementAutomationextractedtired\functions\3rd party functions\ZernikeCalc');

%% 3. Initialize aberration measurement app
try
    app = aberration_measurement_automation(obj, cam);
    % Add this check to ensure the app is initialized
    pause(1);
catch ME
    disp('Error initializing aberration_measurement app:');
    disp(ME.message);
    return;
end
%% 4. Set parameters programmatically
try
    % Check if required properties exist in the app
    if ~isprop(app, 'zincrementmEditField') || ~isprop(app, 'loadzstackButton')
        error('Required properties are missing in the app.');
    end

    % Set GUI values programmatically
    % Set z-increment (µm) and update property (m)
    app.zincrementmEditField.Value = 0.2;
    app.dz = app.zincrementmEditField.Value * 1e-6;

    % Set emission wavelength (µm) and update property (m)
    app.emissionwavelengthmEditField.Value = 0.538;
    app.lambda = app.emissionwavelengthmEditField.Value * 1e-6;

    % Set bead diameter (µm) and update property (m)
    app.beaddiammEditField.Value = 0.1;
    app.dia_bead = app.beaddiammEditField.Value * 1e-6;

    % Set refractive index of fluid
    app.RIfluidEditField.Value = 1.33;
    app.RI_fluid = app.RIfluidEditField.Value;

    % Set Gaussian smoothing sigma (nm) and update property (m)
    app.GausssmoothsigmanmEditField.Value = 130; % Gaussian smoothing sigma in nm
    app.sigma_gauss_x = app.GausssmoothsigmanmEditField.Value * 1e-9;

    % Set 'fit sigma' checkbox and update property
    app.fitsigmaCheckBox.Value = false;
    app.fit_sigma_gauss = app.fitsigmaCheckBox.Value; 

    % Set max radial Zernike order and update Z_max property
    app.maxradZernikeorderEditField.Value = 10;
    val = app.maxradZernikeorderEditField.Value;
    app.Z_max = ((val + 1)^2 + val + 1) / 2; 

    drawnow; % Let all callbacks and updates process
    
    % Set gamma
    app.gammaEditField.Value = 0.5;
    app.gamma = app.gammaEditField.Value;

    % Set relative z-dipole emission power
    app.z_relEditField.Value = 0.4;
    app.mu_z_rel = app.z_relEditField.Value; 

    % Set max iterations
    app.maxiterEditField.Value = 5000;
    app.iter_max = app.maxiterEditField.Value;

    % Set 'fit amplitude transmission' checkbox and update property
    app.fitampltransmCheckBox.Value = true;
    app.fit_amp = app.fitampltransmCheckBox.Value;

    drawnow; % Ensure GUI updates are applied

catch ME
    disp('Error setting parameters:');
    disp(ME.message);
    delete(app);
    return;
end

%% 5. Programmatically press the load Z-stack button (this will open file dialog)
try
    app.zStackFile = 'D:\projekt\aberrations_measurement\data\beads_blue_bypass\avg_pos2_blue_Bead4.tif';
    pause(0.5); % Allow GUI to settle
    app.loadzstackButton.Value = true;
    app.loadzstackButton.ValueChangedFcn(app.loadzstackButton, []);
    drawnow;
    disp(['Loaded Z-stack from file: ', app.zStackFile]);
catch ME
    disp('Error loading Z-stack programmatically:');
    disp(ME.message);
    delete(app);
    return;
end

%% 6. Wait for manual selection and processing
disp('Waiting for Z-stack to load...');
pause(2); % Adjust if needed, or use a flag like app.stack_loaded
zStackFile_cached = app.zStackFile;

% === ADD THIS CHECK ===
if isempty(zStackFile_cached)
    disp('No Z-stack file was selected. Exiting.');
    delete(app);
    return;
end
% =======================

[zstack_path, ~, ~] = fileparts(zStackFile_cached); % You can use this if you need the path later

if debug_mode
    disp('Debugging enabled...');
    disp(['zStackFile_cached: ', zStackFile_cached]);
    disp('Aberration structure:');
    disp(app.aberr); % Display the structure directly
end

%% Slider update
% Preview all frames using the slider and update display
try
    nFrames = size(app.stack, 17); % Number of frames in the stack
    for frameIdx = 1:nFrames
        app.Slider.Value = frameIdx;
        app.Slider.ValueChangedFcn(app.Slider, []);
        drawnow;
        pause(0.1);
    end
catch ME
    disp('Error updating slider and preview:');
    disp(ME.message);
end

%% 7. Normalize the entire stack globally
try
    app.normeachlayerButton.ButtonPushedFcn(app, []); % Trigger the button's callback
    drawnow; % Process GUI updates
    disp('Normalized each layer of the Z-stack.');
    pause(2); % Wait for normalization to complete
catch ME
    disp('Error during normalization:');
    disp(ME.message);
    disp(ME.stack);
    delete(app);
    return;
end


%% 8. Simulate pressing buttons programmatically
try 
    % 8a. Simulate perfect PSF, no aberrations
    maxRadialOrder = app.maxradZernikeorderEditField.Value;
    nModes = (maxRadialOrder + 1)*(maxRadialOrder + 2)/2 - 1;
    Z_modes = 2:(nModes+1);              % Noll indices, skip piston
    Z_magn = zeros(1, nModes);           % All zero coefficients
    app.aberr = struct('Z_modes', Z_modes, 'Z_magn', Z_magn, 'T_coefs', 1);
    
    % Simulate pressing the 'Calculate Model' button
    lastwarn(''); % Clear any old warning
    disp('Triggering the model calculation...');
    app.calculatemodelButton.ButtonPushedFcn(app, []); % Trigger the button's callback
    drawnow; % Process GUI updates
    pause(2); % Wait to ensure the model calculation completes
    disp('Model calculation completed.');

    % Log and check the model calculation result
    [warnMsg, warnId] = lastwarn;
    if contains(warnMsg, 'NaNs detected in phase mask')
        % Log the warning to a text file
        fid = fopen(fullfile(folderPath, 'aberration_log.txt'), 'a');
        if fid == -1
            error('Could not open log file for writing.');
        end
        fprintf(fid, '[%s] WARNING: %s\n', datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'), warnMsg);
        fclose(fid);
        
        % Display the warning in the console and stop execution
        warning('Detected NaNs in the phase mask during model calculation. Review app.defocus or input parameters.');
        delete(app); % Close the app gracefully
        return;
    end

    % Simulate pressing the 'Fit' button with timing and status messages
    disp('Starting fit...');
    app.fit_amp = true;
    tic;
    app.FitButton.ButtonPushedFcn(app, []); % Trigger the button's callback
    drawnow; % Process GUI updates

    % Wait until the model is calculated or a timeout occurs
    timeout = 60;  % seconds
    t_start = tic;

    % Loop to check if the fit is completed
    while true
        currentColor = app.Lamp.Color;

        % Fit has finished if the lamp turned black
        if isequal(currentColor, [0,0,0])
            disp('Fit completed — lamp turned black.');
            break;
        end
    
        % Check for timeout
        if toc(t_start) > timeout
            warning('Fit operation timed out after %.1f seconds.', timeout);
            break;
        end
    
        % Small pause to avoid CPU overload
        pause(0.5);  
        drawnow;  % Ensure GUI stays responsive
    end

    t_fit = toc(t_start);
    disp(['Fit completed in ', num2str(t_fit, '%.1f'), ' seconds (detected via lamp).']);

    % Enhanced PSF Centering Section
    disp('Starting PSF centering...');
    
    % Get image data from UIAxes before centering
    imgObj = findobj(app.UIAxes_1, 'Type', 'Image');
    before_img = imgObj.CData;

    % Save before centering image
    exportgraphics(app.UIAxes_1, 'before_centering.png', 'BackgroundColor', 'white');

    % Execute centering
    app.centerPSFButton.ButtonPushedFcn(app, []); % Trigger the button's callback
    drawnow; % Process GUI updates
    pause(5); % Wait to ensure PSF centering completes

    % Get image data after centering
    imgObj = findobj(app.UIAxes_1, 'Type', 'Image');
    after_img = imgObj.CData;

    % Save after centering image
    exportgraphics(app.UIAxes_1, 'after_centering.png', 'BackgroundColor', 'white');
    

catch ME
    % Check if zstack_path exists (added in Section 7)
    if ~exist('zstack_path', 'var') || isempty(zstack_path)
        zstack_path = pwd; % Default to current directory
    end
    
    fid = fopen(fullfile(zstack_path, 'aberration_log.txt'), 'a');

    if fid == -1
        error('Could not open log file for writing.');
    end
    fprintf(fid, '[%s] ERROR: %s\n', datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'), ME.message);
    fclose(fid);
    
    disp('Error during button pressing:');
    disp(ME.message);
    disp(ME.stack); 
    delete(app);
    return;
end


%% 9. Save Results
try
    % Cache and validate app.aberr
    if isprop(app, 'aberr') && ~isempty(app.aberr)
        aberr_cached = app.aberr;
    else
        warning('Aberration structure is missing. Creating default structure.');
        aberr_cached = struct('Z_modes', [], 'Z_magn', [], 'T_coefs', []);
    end
    
    % Set your desired save directory and base filename
    target_folder = 'D:\projekt\aberrations_measurement\data\aberrations_blue_bypass\';

    % Determine save location and name
    if isprop(app, 'zStackFile') && ~isempty(app.zStackFile)
        [~, zstack_name] = fileparts(app.zStackFile);
    else
        warning('No Z-stack file selected. Using current directory.');
        zstack_name = 'unknown_stack';
    end

    % Generate a timestamp using datetime
    timestamp = datetime('now', 'Format', 'yyyyMMdd_HHmmss');

    % Save aberration structure
    save_name = fullfile(target_folder, sprintf('aberrations_%s_%s.mat', zstack_name, timestamp));
    validateAberrationStructure(aberr_cached, debug_mode);
    save(save_name, 'aberr_cached');
    disp(['Results saved to: ', save_name]);
catch ME
    % Emergency save in case of failure
    emergency_name = fullfile(target_folder, ['EMERGENCY_', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')), '.mat']);
    save(emergency_name, 'aberr_cached');
    warning(['Save failed. Emergency backup saved to: ', emergency_name]);
end

%% 10. Close the App
delete(app);
disp('App closed successfully.');

%% Helper Function: Validate Aberration Structure
function validateAberrationStructure(aberr, debug_mode)
    required_fields = {'Z_modes', 'Z_magn', 'T_coefs'};
    missing = setdiff(required_fields, fieldnames(aberr));

    if ~isempty(missing)
        error('Missing aberration fields: %s', strjoin(missing, ', '));
    end

    if debug_mode
        disp('=== DEBUG: validateAberrationStructure ===');
        disp(['Z_modes size: ', mat2str(size(aberr.Z_modes))]);
        disp(['Z_magn size: ', mat2str(size(aberr.Z_magn))]);
        disp(['T_coefs size: ', mat2str(size(aberr.T_coefs))]);
    end

    if ~isequal(size(aberr.Z_modes), size(aberr.Z_magn))
        error('Mismatched sizes between Z_modes and Z_magn.');
    end

    if ~isvector(aberr.T_coefs) || ~isnumeric(aberr.T_coefs)
        error('T_coefs must be a numeric vector.');
    end
end
