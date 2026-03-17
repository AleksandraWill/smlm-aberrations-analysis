clear all
close all

% Set the full path to the file you want to process:
path_input_data = 'D:\projekt\aberrations_measurement\data\beads_red_bypass\avg_pos3_red.tif';
% Set the output folder (can be the same as the input folder):
path_output_data = 'D:\projekt\aberrations_measurement\data\beads_red_bypass\';

beads_processing(path_input_data, path_output_data);

function beads_processing(path_input_data, path_output_data)
    % Main function to process fluorescence beads from z-stack images
    zStackFile = path_input_data;
    filePath = path_output_data;

    [~, fileName, ext] = fileparts(zStackFile);
    fileName = [fileName ext];

    % Load z-stack images
    zStack = loadZStack(zStackFile);
    [height, width, ~] = size(zStack);

    % Process the middle frame (frame 8)
    middleFrame = 8;
    middleImage = zStack(:, :, middleFrame);

    % Compute dynamic threshold value
    meanIntensity = mean(double(middleImage(:))); % Convert to double
    stdIntensity = std(double(middleImage(:)));  % Convert to double
    thresholdValue = meanIntensity + 6 * stdIntensity;
    disp(['Dynamic Threshold Value: ', num2str(thresholdValue)]);

    % Perform blob detection and centroids calculation
    [centroids, meanIntensities, ~] = processMiddleFrame(middleImage);
    
    % Filter out low-intensity detections
    validIntensityIdx = meanIntensities > thresholdValue; % Only keep beads above the threshold
    centroids = centroids(validIntensityIdx, :); % Filter centroids
    meanIntensities = meanIntensities(validIntensityIdx); % Filter mean intensities

    % Filter out beads too close to the boundaries
    roiSize = 50; % Crop size used in cropAndSaveBeads
    halfSize = roiSize / 2;
    validIdx = (centroids(:, 1) >= halfSize & centroids(:, 1) <= (width - halfSize) & ...
                centroids(:, 2) >= halfSize & centroids(:, 2) <= (height - halfSize));
    filteredCentroids = centroids(validIdx, :);
    filteredMeanIntensities = meanIntensities(validIdx); % Filter mean intensities as well

    % Your filtered centroids and intensities
    xy = filteredCentroids;
    n = size(xy, 1);
    roiSize = 45;
    to_remove = false(n, 1);
    
    for i = 1:n
        if to_remove(i)
            continue;
        end
        for j = i+1:n
            % check if centroid j falls within the 50x50 crop centered at i, and vice versa
            if abs(xy(i,1)-xy(j,1)) < roiSize && abs(xy(i,2)-xy(j,2)) < roiSize
                % If two peaks overlap in their ROI, mark both for removal
                to_remove(i) = true;
                to_remove(j) = true;
            end
        end
    end
    
    filteredCentroids = filteredCentroids(~to_remove, :);
    filteredMeanIntensities = filteredMeanIntensities(~to_remove);


    % Assign consistent numbering to the filtered centroids
    filteredBeadNumbers = (1:size(filteredCentroids, 1))'; % Renumber starting from 1

    % Display results for frame 1 using filtered centroids
    displayResultsFrame1(zStack(:, :, 1), filteredCentroids, filteredBeadNumbers, thresholdValue);

    % Save centroid data
    saveCentroidData(filePath, fileName, filteredCentroids, filteredBeadNumbers, filteredMeanIntensities, height, width);

    % Save cropped beads as z-stacks
    cropAndSaveBeads(zStack, filteredCentroids, filteredBeadNumbers, filePath, fileName);

    % Optional: Display each bead as a separate image
    askToDisplayBeads(zStack(:, :, 1), filteredCentroids, filteredBeadNumbers, height, width);
end

%% Load Z-stack
function zStack = loadZStack(zStackFile)
    % Load z-stack TIFF file
    info = imfinfo(zStackFile);
    numFrames = numel(info);
    zStack = zeros(info(1).Height, info(1).Width, numFrames, 'uint16');
    for i = 1:numFrames
        zStack(:, :, i) = imread(zStackFile, i);
    end
end

%% Process Middle Frame
function [centroids, meanIntensities, labeledImage] = processMiddleFrame(middleImage)
    % Use adaptthresh for adaptive thresholding
    T = adaptthresh(middleImage, 0.5, 'NeighborhoodSize', [15 15], 'ForegroundPolarity', 'bright');
    binaryImage = imbinarize(middleImage, T); % Apply adaptive threshold

    % Label connected components
    labeledImage = logical(bwlabel(binaryImage, 8)); % Use logical to save memory

    % Calculate properties of regions
    props = regionprops(labeledImage, middleImage, 'Centroid', 'MeanIntensity');
    centroids = vertcat(props.Centroid);
    meanIntensities = [props.MeanIntensity]';
end

%% Display Results for Frame 1
function displayResultsFrame1(frame1, centroids, ~, thresholdValue)
    % Display results for Frame 1 with updated plots and logic
    figure(1);
    centerX = size(frame1, 2) / 2; % X-coordinate of the center
    centerY = size(frame1, 1) / 2; % Y-coordinate of the center

    % Create a colormap for assigning different colors to radii
    numColors = size(centroids, 1); % Number of centroids
    colorMap = lines(numColors); % Generate distinct colors

    % 1. Original Image (Frame 1) with Centroids
    subplot(2, 2, 1);
    imshow(frame1, []);
    title('Original Image (Frame 1) with Centroids');
    hold on;
    for i = 1:numColors
        plot(centroids(i, 1), centroids(i, 2), 'r+', 'MarkerSize', 10, 'LineWidth', 2);
    end
    hold off;

    % 2. Histogram of Original Image (Frame 1) with Threshold
    subplot(2, 2, 2);
    histogram(frame1(:), 'BinLimits', [0 max(frame1(:))], 'Normalization', 'probability');
    title('Histogram of Original Image (Frame 1)');
    xlabel('Intensity');
    ylabel('Frequency');
    hold on;
    if thresholdValue > max(frame1(:))
        disp('Warning: Threshold value exceeds intensity range of the image.');
        thresholdValue = max(frame1(:)); % Adjust threshold to maximum intensity
    end
    xline(thresholdValue, 'r', 'LineWidth', 2, 'Label', sprintf('Threshold = %.2f', thresholdValue));
    hold off;

    % 3. Original Image (Frame 1) with Numbered Centroids
    subplot(2, 2, 3);
    imshow(frame1, []);
    title('Original Image (Frame 1) with Numbered Centroids');
    hold on;
    for i = 1:numColors
        plot(centroids(i, 1), centroids(i, 2), 'r+', 'MarkerSize', 10, 'LineWidth', 2);
        text(centroids(i, 1) + 5, centroids(i, 2), sprintf('%d', i), 'Color', 'yellow', 'FontSize', 8, 'FontWeight', 'bold');
    end
    hold off;

    % 4. Original Image (Frame 1) with Center Mark and Radii to Beads
    subplot(2, 2, 4);
    imshow(frame1, []);
    title('Original Image (Frame 1) with Radii and R Values');
    hold on;
    plot(centerX, centerY, 'go', 'MarkerSize', 10, 'LineWidth', 2); % Mark the center
    for i = 1:numColors
        % Draw line from center to centroid in a unique color
        plot([centerX, centroids(i, 1)], [centerY, centroids(i, 2)], '-', 'Color', colorMap(i, :), 'LineWidth', 1.5);
        % Calculate and display distance (R)
        R = sqrt((centroids(i, 1) - centerX)^2 + (centroids(i, 2) - centerY)^2);
        text((centerX + centroids(i, 1)) / 2, (centerY + centroids(i, 2)) / 2, sprintf('R=%.1f', R), ...
            'Color', colorMap(i, :), 'FontSize', 8, 'FontWeight', 'bold');
    end
    hold off;
end

%% Save Centroid Data
function saveCentroidData(filePath, fileName, filteredCentroids, beadNumbers, meanIntensities, height, width)
    % Remove the extension using fileparts
    [~, fileNameWithoutExt, ~] = fileparts(fileName);

    % Calculate distances from the center (R values)
    R = sqrt((filteredCentroids(:, 1) - width / 2).^2 + (filteredCentroids(:, 2) - height / 2).^2);

    % Create a table to store the centroid data
    centroidData = table(beadNumbers, filteredCentroids(:, 1), filteredCentroids(:, 2), meanIntensities, R, ...
        'VariableNames', {'BeadNumber', 'X', 'Y', 'MeanIntensity', 'R'});

    % Save the data to a .mat file
    save(fullfile(filePath, [fileNameWithoutExt, '_centroids.mat']), 'centroidData');
end

%% Crop and Save Beads
function centroids = cropAndSaveBeads(zStack, centroids, beadNumbers, filePath, fileName)
    % Crop and save each bead as a z-stack
    roiSize = 50;
    halfSize = roiSize / 2;
    [height, width, numFrames] = size(zStack);

    % Preallocate deletion vector
    del_idx = false(size(centroids, 1), 1);

    % Remove the .tif extension from fileName
    [~, fileNameWithoutExt, ~] = fileparts(fileName);

    for i = 1:size(centroids, 1)
        x = round(centroids(i, 1));
        y = round(centroids(i, 2));

        % Check if the cropping region is within image boundaries
        if (x - halfSize + 1 < 1 || x + halfSize > width || y - halfSize + 1 < 1 || y + halfSize > height)
            del_idx(i) = true; % Mark molecule for deletion
            continue; % Skip further processing for this molecule
        end

        % Cropping logic
        zStackCrop = zeros(roiSize, roiSize, numFrames, 'uint16');
        for frame = 1:numFrames
            xRange = (x - halfSize +1):(x + halfSize);
            yRange = (y - halfSize +1):(y + halfSize);
            crop = zStack(yRange, xRange, frame);
            zStackCrop(:, :, frame) = crop;
        end

        % Save cropped z-stack using beadNumbers and updated fileName
        outputFileName = fullfile(filePath, sprintf('%s_Bead%d.tif', fileNameWithoutExt, beadNumbers(i)));

        % Debugging output
        fprintf('Saving bead #%d at x=%d, y=%d as %s\n', beadNumbers(i), x, y, outputFileName);

        % Save each frame of the z-stack
        for frame = 1:numFrames
            if frame == 1
                imwrite(zStackCrop(:, :, frame), outputFileName, 'WriteMode', 'overwrite', 'Compression', 'none');
            else
                imwrite(zStackCrop(:, :, frame), outputFileName, 'WriteMode', 'append', 'Compression', 'none');
            end
        end
    end

    % Delete faulty entries
    centroids(del_idx, :) = [];
    % Display the number of beads processed
    disp([num2str(size(centroids, 1)), ' molecules were processed and saved as cropped z-stacks.']);
end

%% Ask to Display Beads
function askToDisplayBeads(frame1, filteredCentroids, beadNumbers, height, width)
    % Optionally display each bead as a separate sub-image
    roiSize = 50;
    halfSize = roiSize / 2;

    % Ask user if they want to display
    reply = questdlg('Would you like to crop out each bead to individual images?', ...
        'Extract Individual Images?', 'Yes', 'No', 'Yes');
    if strcmp(reply, 'Yes')
        figure(2);
        numBeads = size(filteredCentroids, 1); % Use filtered centroids
        for i = 1:numBeads
            x = round(filteredCentroids(i, 1));
            y = round(filteredCentroids(i, 2));
            R = sqrt((x - width / 2)^2 + (y - height / 2)^2);

            % Crop the bead image
            if (x - halfSize + 1 < 1 || x + halfSize > width || y - halfSize +1 < 1 || y + halfSize > height)
                crop = zeros(roiSize, roiSize); % Set the image to zeros if too close to edges
            else
                % Use direct indexing instead of imcrop for more precise control
                xRange = (x - halfSize + 1):(x + halfSize);
                yRange = (y - halfSize + 1):(y + halfSize);
                crop = frame1(yRange, xRange);
            end

            % Display the cropped bead
            subplot(ceil(sqrt(numBeads)), ceil(sqrt(numBeads)), i);
            imshow(crop, []);
            title(sprintf('Bead #%d\nx = %.1f, y = %.1f\nR = %.1f', beadNumbers(i), x, y, R), 'FontSize', 8);
        end
    end
end