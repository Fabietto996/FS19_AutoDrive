function AutoDrive:handleTrailers(vehicle, dt)
    if vehicle.ad.isActive == true and (vehicle.ad.mode == AutoDrive.MODE_DELIVERTO or vehicle.ad.mode == AutoDrive.MODE_PICKUPANDDELIVER) then --and vehicle.isServer == true
        local trailers, trailerCount = AutoDrive:getTrailersOf(vehicle);  		

        if trailerCount == 0 then
            return
        end;        
        
        local leftCapacity = 0;
        for _,trailer in pairs(trailers) do
            for _,fillUnit in pairs(trailer:getFillUnits()) do
                leftCapacity = leftCapacity + trailer:getFillUnitFreeCapacity(_)
            end
        end;

        --check distance to unloading destination, do not unload too far from it. You never know where the tractor might already drive over an unloading trigger before that
        local x,y,z = getWorldTranslation(vehicle.components[1].node);
        local destination = AutoDrive.mapWayPoints[vehicle.ad.targetSelected_Unload];
        if destination == nil then
            return;
        end;
        if vehicle.ad.mode == AutoDrive.MODE_DELIVERTO then
            destination = AutoDrive.mapWayPoints[vehicle.ad.targetSelected];
        end;
        local distance = AutoDrive:getDistance(x,z, destination.x, destination.z);
        if distance < 20 then
            for _,trailer in pairs(trailers) do
                for _,trigger in pairs(AutoDrive.Triggers.tipTriggers) do

                    local currentDischargeNode = trailer:getCurrentDischargeNode()
                    local distanceToTrigger, bestTipReferencePoint = 0, currentDischargeNode;

                    --find the best TipPoint
                    if not trailer:getCanDischargeToObject(currentDischargeNode) then
                        for i=1,#trailer.spec_dischargeable.dischargeNodes do
                            if trailer:getCanDischargeToObject(trailer.spec_dischargeable.dischargeNodes[i])then
                                trailer:setCurrentDischargeNodeIndex(trailer.spec_dischargeable.dischargeNodes[i]);
                                currentDischargeNode = trailer:getCurrentDischargeNode()
                                break
                            end
                        end
                    end
                    
                    if trailer:getCanDischargeToObject(currentDischargeNode) then
                        trailer:setDischargeState(Dischargeable.DISCHARGE_STATE_OBJECT)
                        vehicle.ad.isPaused = true;
                        vehicle.ad.isUnloading = true;
                    end;
                    
                    local dischargeState = trailer:getDischargeState()
                    if dischargeState == Trailer.TIPSTATE_CLOSED or dischargeState == Trailer.TIPSTATE_CLOSING then
                        vehicle.ad.isPaused = false;
                        vehicle.ad.isUnloading = false;
                    end;
                end; 
                
                if trailer.spec_cover ~= nil then
                    if trailer.spec_cover.state == 0 then
                        local newState = 1    
                        if trailer.spec_cover.state ~= newState and trailer:getIsNextCoverStateAllowed(newState) then
                            trailer:setCoverState(newState,true);
                        end
                    end;
                end;               
            end;
        end;

        local x,y,z = getWorldTranslation(vehicle.components[1].node);
        local destination = AutoDrive.mapWayPoints[vehicle.ad.targetSelected];
        if destination == nil then
            return;
        end;
        local distance = AutoDrive:getDistance(x,z, destination.x, destination.z);        
        if distance < 20 then
            for _,trailer in pairs(trailers) do
                for _,trigger in pairs(AutoDrive.Triggers.siloTriggers) do
                    local activate = false;
                    for __,fillableObject in pairs(trigger.fillableObjects) do
                        if fillableObject.object == trailer then   
                            activate = true;    
                        end;
                    end;

                    if activate == true and not trigger.isLoading and leftCapacity > 0 and AutoDrive:fillTypesMatch(vehicle, trigger, trailer) and trigger:getIsActivatable(trailer) then
                        trigger.autoStart = true
                        trigger.selectedFillType = vehicle.ad.unloadFillTypeIndex                         
                        trigger:onActivateObject(vehicle) 
                        trigger.selectedFillType = vehicle.ad.unloadFillTypeIndex 
                        g_effectManager:setFillType(trigger.effects, trigger.selectedFillType)
                        trigger.autoStart = false
                        vehicle.ad.isPaused = true;
                        vehicle.ad.isLoading = true;

                        if g_server == nil and trigger.isLoading then
                            --AutoDriveUpdateEvent:sendEvent(vehicle); --The unload function has to be called on the client side. Therefore the client has to inform the server
                        end;
                    end;

                    if leftCapacity == 0 and vehicle.ad.isPaused then
                        vehicle.ad.isPaused = false;
                        vehicle.ad.isUnloading = false;
                        vehicle.ad.isLoading = false;
                    end;
                end;

                if trailer.spec_cover ~= nil then
                    if trailer.spec_cover.state == 0 then
                        local newState = 1    
                        if trailer.spec_cover.state ~= newState and trailer:getIsNextCoverStateAllowed(newState) then
                            trailer:setCoverState(newState,true);
                        end
                    end;
                end;
            end;
        end;        
    end;
end;

function AutoDrive:fillTypesMatch(vehicle, fillTrigger, workTool,onlyCheckThisFillUnit)
	if fillTrigger ~= nil then
		local typesMatch = false
		local selectedFillType = vehicle.ad.unloadFillTypeIndex or FillType.UNKNOWN;
		local fillUnits = workTool:getFillUnits()
		local checkOnly = onlyCheckThisFillUnit or 0;
		-- go throught the single fillUnits and check:
		-- does the trigger support the tools filltype ?
		-- does the trigger support the single fillUnits filltype ?
		-- does the trigger and the fillUnit match the selectedFilltype or do they ignore it ?
		for i=1,#fillUnits do
			if checkOnly == 0 or i == checkOnly then
				local selectedFillTypeIsNotInMyFillUnit = true
				local matchInThisUnit = false
				for index,_ in pairs(workTool:getFillUnitSupportedFillTypes(i))do 
					--loadTriggers
					if fillTrigger.source ~= nil and fillTrigger.source.providedFillTypes[index] then
						typesMatch = true
						matchInThisUnit =true
					end
					--fillTriggers
					if fillTrigger.sourceObject ~= nil then
						local fillTypes = fillTrigger.sourceObject:getFillUnitSupportedFillTypes(1)  
						if fillTypes[index] then 
							typesMatch = true
							matchInThisUnit =true
						end
					end
					if index == selectedFillType and selectedFillType ~= FillType.UNKNOWN then
						selectedFillTypeIsNotInMyFillUnit = false;
					end
				end
				if matchInThisUnit and selectedFillTypeIsNotInMyFillUnit then
					return false;
				end
			end
		end	
		
		if typesMatch then
			if selectedFillType == FillType.UNKNOWN then
				return true;
			else
				if fillTrigger.source then
					return fillTrigger.source.providedFillTypes[selectedFillType] or false;
				elseif fillTrigger.sourceObject ~= nil then
					local fillType = fillTrigger.sourceObject:getFillUnitFillType(1)  
					return fillType == selectedFillType;
				end
			end		
		end
	end
	return false;
end;

function AutoDrive:getTrailersOf(vehicle)
    local trailers = {};
    local trailerCount = 0;
    local trailer = nil;
    if vehicle.getAttachedImplements ~= nil then
        local hasImplements = true;
        local toCheck = vehicle
        while hasImplements do
            hasImplements = false;
            if toCheck.getAttachedImplements ~= nil then
                for _, implement in pairs(toCheck:getAttachedImplements()) do                    
                    if implement.object ~= nil then
                        --if workTool.spec_dischargeable and workTool.cp.capacity and workTool.cp.capacity > 0.1 then
                        if implement.object.typeDesc == g_i18n:getText("typeDesc_tipper") or implement.object.spec_dischargeable ~= nil then
                            trailer = implement.object;
                            trailerCount = 1;
                            trailers[trailerCount] = trailer;
                            toCheck = implement;
                            hasImplements = true;
                        end;
                        if implement.object.vehicleType.specializationsByName["hookLiftTrailer"] ~= nil then                   
                            trailer = implement.object.spec_hookLiftTrailer.attachedContainer.object
                            trailerCount = 1;
                            trailers[trailerCount] = trailer;
                            toCheck = implement;
                            hasImplements = true;
                        end;
                    end;
                end;
            end;
        end;
    end;

    return trailers, trailerCount;
end;