% Moves 'mom' (Sutter MOM) or 'hex' (Physik-Instrumente hexapod), and a
% 3-vector of target positions (in microns).
function [newpos] = move(motor, target_um)
    global STL;
    hSI = evalin('base', 'hSI');
    
    % if target_um is blank, just return the current position
    if ~exist('target_um', 'var')
        if STL.logistics.simulated
            newpos = STL.logistics.simulated_pos(1:3);
            return;
        end
        
        switch motor
            case 'mom'
                newpos = hSI.hMotors.motorPosition;
            case 'hex'
                for i = 1:3
                    newpos(i) = STL.motors.hex.C887.qPOS(STL.motors.hex.axes(i)) * 1e3;
                end
        end
        return;
    end
    
    % Control just X or XY or XYZ, but only those three.
    if length(target_um) > 3
        target_um = target_um(1:3);
    end

    
    disp(sprintf(' ...moving %s to [%s ]...', motor, sprintf('%g ', target_um)));
    
    if STL.logistics.simulated
        STL.logistics.simulated_pos(1:3) = target_um;
        newpos = target_um;
        
        return;
    end

    anti_backlash = [20 20 20];
    
    switch motor
        case 'mom'
            
            % Go to position-x on all dimensions in order to always
            % complete the move in the same direction.
            hSI.hMotors.motorPosition(1:length(target_um)) = target_um - anti_backlash(1:length(target_um));
            hSI.hMotors.motorPosition(1:length(target_um)) = target_um;
            
            
        case 'hex'
            
            target_mm = target_um / 1e3

            % 0x19001500 (max velocity) qVLS, max seems around 2 (units?
            % should be 10 mm/s!)
            % Parameter 0x19001900 should be 0
            % Parameter 0x19001901 should be 0
            %position = rand(1)*(STL.motors.hex.dAxisMax-STL.motors.hex.dAxisMin)+STL.motors.hex.dAxisMin;
            % Possible to do this as a single command?
            for i = 1:length(target_mm)
                % anti-backlash:
                STL.motors.hex.C887.MOV(STL.motors.hex.axes(i), target_mm(i) - 0.02);
            end
            hexapod_wait();
            
            for i = 1:length(target_mm)
                STL.motors.hex.C887.MOV(STL.motors.hex.axes(i), target_mm(i));
            end
            hexapod_wait();
        otherwise
            
            error('Invalid motor "%s". No movement.',  motor);
            
    end
end
