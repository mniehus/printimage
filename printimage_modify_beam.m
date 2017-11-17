function [ao_volts_out] = printimage_modify_beam(ao_volts_raw);
    global STL;
    
    % Vignetting compensation can be done here, since it's independent of
    % zoom and thus doesn't require re-voxelising. Sinusoidal-velocity
    % compensation is currently in voxelise(); this is awkward for testing
    % and readability, but it's okay, since any change that affects it
    % (besides tweaking parameters) depends on zoom and thus requires
    % re-voxelising anyway.
    VIGNETTING_POWER_COMPENSATION = 'cos3';
    
    % Beam speed compensation was computed with voxelise(), but has not
    % been applied yet.
    BEAM_SPEED_POWER_COMPENSATION = 0.8;
    SHOW_COMPENSATION = 34;
    
    hSI = evalin('base', 'hSI');
    %hSI.hChannels.loggingEnable = false;
    
    if STL.print.voxelise_needed
        voxelise([], 'print');
    end
    
    if STL.print.voxelise_needed
        error('Tried re-voxelising, but was unsuccessful.');
    end
    
    % Pull down which metavoxel we're working on:
    mvx = STL.print.mvx_now;
    mvy = STL.print.mvy_now;
    mvz = STL.print.mvz_now;
    voxelpower = STL.print.metavoxels{mvx, mvy, mvz} * STL.print.power;
    disp(sprintf('~ Voxel power is on [%g, %g]', ...
        min(min(min(voxelpower))), ...
        max(max(max(voxelpower)))));
    

    % Flyback blanking workaround KLUDGE!!! This means that
    % metavoxel_overlap will need to be bigger than it would otherwise need
    % to be, by one voxel.
    workspace_size = size(voxelpower);
    voxelpower(end,:,:) = zeros(workspace_size(2:3));
    
    xc = STL.print.voxelpos_wrt_fov{mvx, mvy, mvz}.x;
    yc = STL.print.voxelpos_wrt_fov{mvx, mvy, mvz}.y;

    if BEAM_SPEED_POWER_COMPENSATION
        % Compensate proportionally--generalise Christos's ad-hoc
        % compensation due to a nonlinearity in polymerisation vs speed
        % e.g., ((v - 1) * 0.5) + 1
        beamspeed = diff(xc) * STL.calibration.pockelsFrequency;
        beamspeed(end+1) = beamspeed(1);
        beam_power_comp_x = ((beamspeed - STL.calibration.beam_speed_max_um) * BEAM_SPEED_POWER_COMPENSATION ...
            + STL.calibration.beam_speed_max_um) ...
            / STL.calibration.beam_speed_max_um;
        adj = repmat(beam_power_comp_x', [1, workspace_size(2), workspace_size(3)]);
        voxelpower = voxelpower .* adj;
        disp(sprintf('~ Beam speed power compensation (factor %g) applied. Adjusted power is on [%g, %g]', ...
            BEAM_SPEED_POWER_COMPENSATION, ...
            min(voxelpower(:)), ...
            max(voxelpower(:))));
        if SHOW_COMPENSATION
            figure(SHOW_COMPENSATION);
            subplot(1,2,1);
            plot(STL.print.voxelpos_wrt_fov{mvx, mvy, mvz}.x, STL.print.power ./ voxelpower(:,256,end));
        end
    else
        adj = ones(workspace_size);
        disp('~ Beam speed power compensation NOT applied.');
    end
    
    
    % Vignetting power compensation lives here.
    switch VIGNETTING_POWER_COMPENSATION
        case 'cos4'
            [vig_x, vig_y] = meshgrid(xc, yc);
            vignetting_falloff = cos(atan(((vig_x.^2 + vig_y.^2).^(1/2))/STL.calibration.lens_optical_working_distance)).^4;
            vignetting_falloff = repmat(vignetting_falloff', [1, 1, size(voxelpower, 3)]);
            voxelpower = voxelpower ./ vignetting_falloff;
            adj = adj ./ vignetting_falloff;
            
            disp(sprintf('~ Vignetting power compensation (cos^4) applied. Adjusted power is on [%g, %g]', ...
                min(voxelpower(:)), ...
                max(voxelpower(:))));

        case 'cos3'
            [vig_x, vig_y] = meshgrid(xc, yc);
            vignetting_falloff = cos(atan(((vig_x.^2 + vig_y.^2).^(1/2))/STL.calibration.lens_optical_working_distance)).^3;
            vignetting_falloff = repmat(vignetting_falloff', [1, 1, size(voxelpower, 3)]);
            voxelpower = voxelpower ./ vignetting_falloff;
            adj = adj ./ vignetting_falloff;
            
            disp(sprintf('~ Vignetting power compensation (cos^3) applied. Adjusted power is on [%g, %g]', ...
                min(voxelpower(:)), ...
                max(voxelpower(:))));
            
        case 'fit'
            disp('~ Using the current curvefit vignetting compensator.');
            if isfield(STL, 'calibration') & isfield(STL.calibration, 'vignetting_fit')
                [vig_x, vig_y] = meshgrid(xc, yc);
                vignetting_falloff = STL.calibration.vignetting_fit(vig_x, vig_y);
                vignetting_falloff = vignetting_falloff / max(max(vignetting_falloff));
            else
                disp('~ No vignetting fit available. Vignetting power compensation NOT applied.');
                vignetting_falloff = ones(STL.print.resolution(1:2));
            end
            % Transpose: xc is the first index of the matrix (row #)
            vignetting_falloff = repmat(vignetting_falloff', [1, 1, size(voxelpower, 3)]);
            adj = adj ./ vignetting_falloff;


            voxelpower = voxelpower ./ vignetting_falloff;
            
        case 'none'
            disp('~ Vignetting power compensation NOT applied.');
            
        otherwise
            warning('~ Illegal value specified. Vignetting power compensation NOT applied.');
    end
    
    % Do not ask for more than 100% power:
    if max(voxelpower(:)) > 1
        warning(sprintf('~ Vignetting compensation is requesting power %g%%! Squashing to 100%%.', 100*max(voxelpower(:))));
        voxelpower = min(voxelpower, 1);
    end
    
    if min(voxelpower(:) < 0)
        error('~ Someone requested power < 0. You''ll want to fix that.');
    end
            
    disp(sprintf('~ Final adjusted power is on [%g, %g]', ...
        min(voxelpower(:)), ...
        max(voxelpower(:))));
    
    if SHOW_COMPENSATION
        figure(SHOW_COMPENSATION);
        if exist('vignetting_falloff', 'var')
            subplot(1,2,1);
            hold on;
            middle = round(size(vignetting_falloff, 2));
            plot(xc, vignetting_falloff(:, middle, end));
            plot(xc, STL.print.power ./ voxelpower(:, middle, end));
            hold off;
            title('Expected energy deposition along Y=0');
            xlabel('X (\mu{}m)');
            ylabel('Total energy');
            legend('speed', 'vignetting', 'both');
            xlim(xc([1 end]));
            yl = get(gca, 'YLim');
            ylim([0 yl(2)]);
            
            subplot(1,2,2);
        else
            subplot(1,1,1);
        end
        
        adj = adj(:,:,1); % Don't need all the repeats!
        
        imagesc(STL.print.voxelpos_wrt_fov{1,1,1}.x, ...
            STL.print.voxelpos_wrt_fov{1,1,1}.y, ...
            adj');
        axis square;
        colorbar;
        colormap(jet);
        title('Power compensation');
        xlabel('X (\mu{}m)');
        ylabel('Y (\mu{}m)');
    end

    % Save for analysis
    STL.print.voxelpower_adjustment = adj;
    STL.print.voxelpower_actual = voxelpower;
    STL.print.ao_volts_out = ao_volts_raw;

    if STL.logistics.simulated
        STL.print.ao_volts_out.B(:, STL.print.whichBeam) = voxelpower(:);
    else
        STL.print.ao_volts_out.B(:, STL.print.whichBeam) = hSI.hBeams.zprpBeamsPowerFractionToVoltage(STL.print.whichBeam, voxelpower(:));
    end
    
    % Decrease power as appropriate for current zoom level. Empirically, this
    % seems to go sublinearly! Not sure why. Perhaps overscanning on Y doesn't
    % happen fast enough to count as more power? Perhaps SUBlinear because I
    % have not calibrated aspect ratio yet? FIXME
    %STL.print.ao_volts_raw.B = STL.print.ao_volts_raw.B / hSI.hRoiManager.scanZoomFactor;
    
    ao_volts_out = STL.print.ao_volts_out;
end
