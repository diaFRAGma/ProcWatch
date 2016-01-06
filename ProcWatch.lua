--[[

	ProcWatch
	v1.1

	This AddOn is intended to determine proc rates of weapon procs.

	Once installed, set up a key binding in-game to Toggle ProcWatch.

	Alternately, you can use these commands:
	/procwatch : shows the window
	/procwatch hide : hides the window but keeps monitoring procs
	/procwatch show : shows the window (same as no arguments)
	/procwatch exit : stops monitoring procs and shuts down
	/procwatch (text) : defines a proc event (same as clicking on event)

	3/22/05 - updated toc
	3/21/05 - initial build

	- Gello, Hyjal

]]


--[[ Variables saved to SavedVariables.lua ]]

ProcWatch = {};
ProcWatch.Enabled = false; -- if we are in an idle or active state
ProcWatch.Minimized = false; -- if the window is minimized
ProcWatch.Sticky = false; -- if window can be dismissed with ESC
ProcWatch.Paused = "disabled"; -- "disabled" "enabled" "paused"

ProcWatch.ProcString = ""; -- the (text) of /procwatch (text)

ProcWatch.BeginTime = 0; -- time of the first hit in current fight
ProcWatch.EndTime = 0; -- time of the last hit in current fight
ProcWatch.Hits = 0; -- number of hits in current fight
ProcWatch.Procs = 0; -- number of procs in current fight

ProcWatch.LastHits = 0; -- number of hits in last fight
ProcWatch.LastProcs = 0; -- number of procs in last fight
ProcWatch.LastTime = 0; -- duration of last fight

ProcWatch.TotalHits = 0; -- running total of hits
ProcWatch.TotalProcs = 0; -- running total of procs
ProcWatch.TotalTime = 0; -- running total of fight durations

ProcWatch.OptionsOpen = false; -- whether the options "drawer" is open
ProcWatch.IgnoreOneHitFights = false; -- option to ignore fights with 0 duration
ProcWatch.NotifyOnProc = false; -- option to send a proc alert to the HUD
ProcWatch.ShowTooltips = true; -- option to show the tooltips
ProcWatch.WatchAllCombat = false; -- option to determine fight start time

ProcWatchDamage = {}
--ProcWatch_Damage = ProcWatch:NewModule("damage")
--ProcWatch_Damage.Damage = {}
--ProcWatch.Damage = "" -- records damage of the proc

--[[ Other Variables ]]

b_ProcWatchLoaded = false;
f_ProcWatchOriginalChatFrame_OnEvent = nil;

BINDING_HEADER_PROCWATCH = "ProcWatch";


--[[ Functions called by the game ]]

function ProcWatch_OnLoad()

    this:RegisterEvent("VARIABLES_LOADED");
    this:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS");
    this:RegisterEvent("PLAYER_REGEN_ENABLED");
    this:RegisterEvent("PLAYER_REGEN_DISABLED");
end

function ProcWatch_OnEvent(event)
    if (event == "VARIABLES_LOADED") then
        b_ProcWatchLoaded = true
		if ProcWatch.Enabled then
			-- if .Enabled, it means we had ProcWatch running when variables
			-- were last saved.  So pick up from where we were in idle mode.
			ProcWatchEventString_Text:SetText(ProcWatch.ProcString)
			ProcWatchStatusTexture:SetTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Idle")
			ProcWatch_SetPause()
			ProcWatch_SetOptions()
			if not ProcWatch.Sticky then
				tinsert(UISpecialFrames, "ProcWatchFrame")
			end	
			if not ProcWatch.Minimized then
				ProcWatch_Minimize() -- clean up display
				ProcWatch_Maximize()
			else
				ProcWatch_Minimize()
			end
			ProcWatchFrame:Show() -- show display
		else
			ProcWatch_Shutdown() -- if not enabled from SavedVariables, start anew
		end	
		-- register /procwatch command
		SlashCmdList["ProcWatchCOMMAND"] = ProcWatch_SlashHandler
		SLASH_ProcWatchCOMMAND1 = "/procwatch"
	end
    if b_ProcWatchLoaded and ProcWatch.Enabled and (ProcWatch.Paused~="paused") then
		if (event == "CHAT_MSG_COMBAT_SELF_HITS") then
			ProcWatch.Hits = ProcWatch.Hits + 1
			if (ProcWatch.BeginTime==0) then
				ProcWatch_SetPause("disabled")
				ProcWatch.BeginTime = GetTime() -- note time of first hit
				ProcWatch.EndTime = ProcWatch.BeginTime -- first hit could be last also
				ProcWatch_HookChat() -- begin watching for procs
			else
			ProcWatch.EndTime = GetTime() -- assume each hit after first can be last
	    end
	elseif (event == "PLAYER_REGEN_DISABLED") then
	    if ProcWatch.WatchAllCombat and (ProcWatch.BeginTime==0) then
			ProcWatch_SetPause("disabled")
			ProcWatch.BeginTime = GetTime()
			ProcWatch.EndTime = ProcWatch.BeginTime
			ProcWatch_HookChat()
	    end
    elseif (event == "PLAYER_REGEN_ENABLED") then
	    if (ProcWatch.BeginTime > 0) then
			ProcWatch_ReleaseChat() -- stop watching for procs
				if ProcWatch.WatchAllCombat then
					ProcWatch.EndTime = GetTime()
				end
				ProcWatchStatusTexture:SetTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Idle")
				ProcWatch_SetPause("enabled")
				if not ProcWatch.IgnoreOneHitFights or (ProcWatch.Hits>1) then
					ProcWatch.LastHits = ProcWatch.Hits
					ProcWatch.TotalHits = ProcWatch.TotalHits + ProcWatch.LastHits
					ProcWatch.LastProcs = ProcWatch.Procs
					ProcWatch.TotalProcs = ProcWatch.TotalProcs + ProcWatch.LastProcs
					ProcWatch.LastTime = ProcWatch.EndTime - ProcWatch.BeginTime
					ProcWatch.TotalTime = ProcWatch.TotalTime + ProcWatch.LastTime
					ProcWatch_UpdateDisplay()
				end
				ProcWatch.Hits = 0
				ProcWatch.Procs = 0
				ProcWatch.BeginTime = 0
			end
		end
    end
end

function ProcWatch_SlashHandler(arg1)

    -- arg1 is a string that immediately follows "/procwatch "
    if arg1 and string.find(arg1,"(%w+)") then

	if (string.lower(arg1)=="hide") then
	    ProcWatchFrame:Hide();
	elseif (string.lower(arg1)=="show") then
	    ProcWatchFrame:Show();
	elseif (string.lower(arg1)=="exit") then
	    ProcWatch_Shutdown();
	elseif (string.lower(arg1)=="close") then
	    ProcWatch_Shutdown();
	else
	    ProcWatch_Startup(arg1);
	end

    else

	ProcWatchFrame:Show(); -- if no arguments, pretend we did a "/procwatch show"

    end
end

-- To ensure all chat is monitored for a proc event, we hook ChatFrame_OnEvent to
-- this function on the first hit, then release it when we leave combat.
-- It is not hooked in idle or stopped mode.
function ProcWatch_ChatFrame_OnEvent()
    f_ProcWatchOriginalChatFrame_OnEvent(event,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9)
    if event and (string.sub(event,1,14)=="CHAT_MSG_SPELL" or string.sub(event,1,15)=="CHAT_MSG_COMBAT") then
        if string.find(string.lower(arg1),string.lower(ProcWatch.ProcString)) then
			ProcWatch.Procs = ProcWatch.Procs + 1
			ProcWatchDamage[ProcWatch.ProcString.."("..ProcWatch.TotalProcs + ProcWatch.Procs..")"] = arg1
			if ProcWatch.NotifyOnProcs then
				UIErrorsFrame:AddMessage(arg1,1,1,0,1,UIERRORS_HOLD_TIME)
			end
		end
    end
end

--[[ Helper functions called from within ProcWatch ]]

-- Start up a new ProcWatch to watch for arg1
function ProcWatch_Startup(arg1)

    if arg1 then
        ProcWatch_Shutdown();
        ProcWatch.ProcString = arg1;
        ProcWatchEventString_Text:SetText(ProcWatch.ProcString);
        ProcWatchStatusTexture:SetTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Idle");
        ProcWatch_SetPause("enabled");
        ProcWatchFrame:Show(); -- show the window
        ProcWatch_Maximize(); -- the whole window
        ProcWatch.Enabled = true;
    end
end

-- Bring everything to a closed state: zeroed, disabled, hidden, stopped, unhooked
function ProcWatch_Shutdown()

    ProcWatch.TotalHits = 0;
    ProcWatch.TotalProcs = 0;
    ProcWatch.TotalTime = 0;
    ProcWatch.LastHits = 0;
    ProcWatch.LastProcs = 0;
    ProcWatch.LastTime = 0;
    ProcWatch.ProcString = "None (Click Here)";
    ProcWatch.BeginTime = 0;
    ProcWatch.EndTime = 0;
    ProcWatch.Hits = 0;
    ProcWatch.Procs = 0;
    ProcWatch.Enabled = false;
    ProcWatch_SetPause("disabled");
    ProcWatch.Minimized = false;
    ProcWatchFrame:Hide();
    ProcWatch_SetOptions();
    ProcWatch_Minimize(); -- re-establish hidden window's dialog in this reset state
    ProcWatch_Maximize();
    ProcWatch_ReleaseChat();
end

-- Sets the checked/unchecked state of options
function ProcWatch_SetOptions()

    if ProcWatch.IgnoreOneHitFights then
	ProcWatchIgnoreOneHitFightsCheckButton:SetChecked(1);
    else
	ProcWatchIgnoreOneHitFightsCheckButton:SetChecked(0);
    end

    if ProcWatch.NotifyOnProcs then
	ProcWatchNotifyOnProcsCheckButton:SetChecked(1);
    else
	ProcWatchNotifyOnProcsCheckButton:SetChecked(0);
    end

    if ProcWatch.ShowTooltips then
	ProcWatchShowTooltipsCheckButton:SetChecked(1);
    else
	ProcWatchShowTooltipsCheckButton:SetChecked(0);
    end

    if ProcWatch.WatchAllCombat then
	ProcWatchWatchAllCombatCheckButton:SetChecked(1);
    else
	ProcWatchWatchAllCombatCheckButton:SetChecked(0);
    end

    if ProcWatch.Sticky then
        ProcWatchStickyButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-StickyButton-Down");
    else
        ProcWatchStickyButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-StickyButton-Up");
    end

end

-- Happens on first hit in CHAT_MSG_COMBAT_SELF HITS, or
-- if .WatchAllCombat then happens in PLAYER_REGEN_DISABLED
function ProcWatch_HookChat()

    if not f_ProcWatchOriginalChatFrame_OnEvent then
	f_ProcWatchOriginalChatFrame_OnEvent = ChatFrame_OnEvent;
	ChatFrame_OnEvent = ProcWatch_ChatFrame_OnEvent;
    elseif DEFAULT_CHAT_FRAME then
	-- this error should never been seen
	DEFAULT_CHAT_FRAME:AddMessage("Error in ProcWatch_HookChat(): Chat already hooked.");
    end
end

-- Happens only when we leave combat in PLAYER_REGEN_ENABLED
function ProcWatch_ReleaseChat()

    if f_ProcWatchOriginalChatFrame_OnEvent then
	ChatFrame_OnEvent = f_ProcWatchOriginalChatFrame_OnEvent;
	f_ProcWatchOriginalChatFrame_OnEvent = nil;
    end
end

function ProcWatch_Tooltip(arg1,arg2)

    if ProcWatch.ShowTooltips then
	GameTooltip_SetDefaultAnchor(GameTooltip,this);
	GameTooltip:SetText(arg1);
	GameTooltip:AddLine(arg2, .75, .75, .75, 1);
	GameTooltip:Show();
    end
end

function ProcWatch_Minimize()

    ProcWatch.Minimized = true;
    ProcWatchEventLabel_Static:Hide();
    ProcWatchEventString_Static:Hide();
    ProcWatchHitsLabel_Static:Hide();
    ProcWatchProcsLabel_Static:Hide();
    ProcWatchTimeLabel_Static:Hide();
    ProcWatchHitsPerProcLabel_Static:Hide();
    ProcWatchProcsPerMinLabel_Static:Hide();
    ProcWatchResetLabel_Static:Hide();
    ProcWatchLastFightLabel_Static:Hide();
    ProcWatchTotalsLabel_Static:Hide();
    ProcWatchLastHits_Static:Hide();
    ProcWatchLastProcs_Static:Hide();
    ProcWatchLastTime_Static:Hide();
    ProcWatchLastHitsPerProc_Static:Hide();
    ProcWatchLastProcsPerMin_Static:Hide();
    ProcWatchLastResetButton:Hide();
    ProcWatchTotalHits_Static:Hide();
    ProcWatchTotalProcs_Static:Hide();
    ProcWatchTotalTime_Static:Hide();
    ProcWatchTotalHitsPerProc_Static:Hide();
    ProcWatchTotalProcsPerMin_Static:Hide();
    ProcWatchTotalResetButton:Hide();
    ProcWatchOptionsButton:Hide();
    ProcWatchIgnoreOneHitFightsCheckButton:Hide();
    ProcWatchIgnoreOneHitFightsLabel_Static:Hide();
    ProcWatchNotifyOnProcsCheckButton:Hide();
    ProcWatchNotifyOnProcsLabel_Static:Hide();
    ProcWatchShowTooltipsCheckButton:Hide();
    ProcWatchShowTooltipsLabel_Static:Hide();
    ProcWatchWatchAllCombatCheckButton:Hide();
    ProcWatchWatchAllCombatLabel_Static:Hide();
    ProcWatchEditBox:Hide();
    ProcWatchExitButton:Hide()
    ProcWatchFrame:SetHeight(32);
end

function ProcWatch_Maximize()

    ProcWatch.Minimized = false;
    ProcWatch_UpdateDisplay();
    ProcWatchEventLabel_Static:Show();
    ProcWatchEventString_Static:Show();
    ProcWatchHitsLabel_Static:Show();
    ProcWatchProcsLabel_Static:Show();
    ProcWatchTimeLabel_Static:Show();
    ProcWatchHitsPerProcLabel_Static:Show();
    ProcWatchProcsPerMinLabel_Static:Show();
    ProcWatchResetLabel_Static:Show();
    ProcWatchLastFightLabel_Static:Show();
    ProcWatchTotalsLabel_Static:Show();
    ProcWatchLastHits_Static:Show();
    ProcWatchLastProcs_Static:Show();
    ProcWatchLastTime_Static:Show();
    ProcWatchLastHitsPerProc_Static:Show();
    ProcWatchLastProcsPerMin_Static:Show();
    ProcWatchLastResetButton:Show();
    ProcWatchTotalHits_Static:Show();
    ProcWatchTotalProcs_Static:Show();
    ProcWatchTotalTime_Static:Show();
    ProcWatchTotalHitsPerProc_Static:Show();
    ProcWatchTotalProcsPerMin_Static:Show();
    ProcWatchTotalResetButton:Show();
    ProcWatchOptionsButton:Show();
    ProcWatchEditBox:Hide();

    if ProcWatch.OptionsOpen then
        ProcWatchFrame:SetHeight(228);
	ProcWatchIgnoreOneHitFightsCheckButton:Show();
	ProcWatchIgnoreOneHitFightsLabel_Static:Show();
	ProcWatchNotifyOnProcsCheckButton:Show();
	ProcWatchNotifyOnProcsLabel_Static:Show();
	ProcWatchShowTooltipsCheckButton:Show();
	ProcWatchShowTooltipsLabel_Static:Show();
	ProcWatchWatchAllCombatCheckButton:Show();
	ProcWatchWatchAllCombatLabel_Static:Show();
	ProcWatchExitButton:Show();
    else
	ProcWatchFrame:SetHeight(155);
    end
end

-- returns a string of seconds converted to 0:00:00 format
function ProcWatch_FormatTime(arg1)

    local hours;
    local minutes;
    local seconds;
    local text;

    seconds = math.floor(arg1);
    hours = math.floor(seconds/3600);
    seconds = seconds - hours*3600;
    minutes = math.floor(seconds/60);
    seconds = seconds - minutes*60;

    text = "";
    if (hours>0) then text = text .. format("%d",hours) .. ":"; end
    text = text .. format("%02d",minutes) .. ":";
    text = text .. format("%02d",seconds);

    return text;
end

function ProcWatch_UpdateDisplay()

    ProcWatchEventString_Text:SetText(ProcWatch.ProcString);
    ProcWatchLastHits_Text:SetText(ProcWatch.LastHits);
    ProcWatchLastProcs_Text:SetText(ProcWatch.LastProcs);
    ProcWatchLastTime_Text:SetText(ProcWatch_FormatTime(ProcWatch.LastTime));

    if (ProcWatch.LastProcs>0) then
	ProcWatchLastHitsPerProc_Text:SetText(math.floor((ProcWatch.LastHits/ProcWatch.LastProcs)*10)/10);
    else
	ProcWatchLastHitsPerProc_Text:SetText("--");
    end

    if (ProcWatch.LastTime>0) then
	ProcWatchLastProcsPerMin_Text:SetText(math.floor((ProcWatch.LastProcs/ProcWatch.LastTime)*600)/10);
    else
	ProcWatchLastProcsPerMin_Text:SetText("--");
    end

    ProcWatchTotalHits_Text:SetText(ProcWatch.TotalHits);
    ProcWatchTotalProcs_Text:SetText(ProcWatch.TotalProcs);
    ProcWatchTotalTime_Text:SetText(ProcWatch_FormatTime(ProcWatch.TotalTime));

    if (ProcWatch.TotalProcs>0) then
	ProcWatchTotalHitsPerProc_Text:SetText(math.floor((ProcWatch.TotalHits/ProcWatch.TotalProcs)*10)/10);
    else
	ProcWatchTotalHitsPerProc_Text:SetText("--");
    end

    if (ProcWatch.TotalTime>0) then
	ProcWatchTotalProcsPerMin_Text:SetText(math.floor((ProcWatch.TotalProcs/ProcWatch.TotalTime)*600)/10);
    else
	ProcWatchTotalProcsPerMin_Text:SetText("--");
    end
end    

-- this sets the state for the pause button: "disable" "pause" "resume"
function ProcWatch_SetPause(arg1)

    if arg1 then
	ProcWatch.Paused = arg1;
    end

    if (ProcWatch.Paused=="paused") then
	ProcWatchPauseButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Pause-Down");
	ProcWatchPauseButton:SetPushedTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Pause-Up");
        ProcWatchStatusTexture:SetTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Paused");
    elseif (ProcWatch.Paused=="enabled") then
	ProcWatchPauseButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Pause-Up");
	ProcWatchPauseButton:SetPushedTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Pause-Down");
	ProcWatchStatusTexture:SetTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Idle");
    else
	ProcWatchPauseButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Pause-Disabled");
	ProcWatchPauseButton:SetPushedTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Pause-Disabled");
	if ProcWatch.Enabled then
	    ProcWatchStatusTexture:SetTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Event");
	else
	    ProcWatchStatusTexture:SetTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Stopped");
	end
    end
end

--[[ Debug function to be called from in-game: /script ProcWatch_Debug() ]]

function ProcWatch_Debug()

    local text;

    if DEFAULT_CHAT_FRAME then
        text = "BeginTime: "..ProcWatch.BeginTime..", EndTime: "..ProcWatch.EndTime..", Hooked: "..type(f_ProcWatchOriginalChatFrame_OnEvent);
	DEFAULT_CHAT_FRAME:AddMessage(text);
	text = "LastTime: "..ProcWatch.LastTime..", TotalTime: "..ProcWatch.TotalTime;
	DEFAULT_CHAT_FRAME:AddMessage(text);
    end

end
    

--[[ Window movement functions ]]

function ProcWatch_OnMouseDown(arg1)

    if (b_ProcWatchLoaded == true) then
        if (arg1=="LeftButton") and not ProcWatch.Sticky then
	    ProcWatchEditBox_OnEscapePressed();
            ProcWatchFrame:StartMoving();
	end
    end
end

function ProcWatch_OnMouseUp(arg1)

    if (b_ProcWatchLoaded == true) then
	if (arg1=="LeftButton") and not ProcWatch.Sticky then
	    ProcWatchFrame:StopMovingOrSizing();
	end
    end
end


--[[ Dialog control functions ]]

function ProcWatchCloseButton_OnClick()
    ProcWatchEditBox_OnEscapePressed();
    ProcWatchFrame:Hide();
end

function ProcWatchMinimizeButton_OnClick()

    if (ProcWatch.Minimized == false) then
        ProcWatch.Minimized = true;
        ProcWatchMinimizeButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\MinimizeButton-Down");
	ProcWatch_Minimize();
	GameTooltip:Hide();
	ProcWatchMinimizeButton_OnEnter()
    else
	ProcWatch.Minimized = false;
	ProcWatchMinimizeButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\MinimizeButton-Up");
	ProcWatch_Maximize();
	GameTooltip:Hide();
	ProcWatchMinimizeButton_OnEnter()
    end
end

-- sticky button pins and unpins window for ESC functionality
function ProcWatchStickyButton_OnClick()

    local x;
    local found_index = nil;

    ProcWatchEditBox_OnEscapePressed();

    for x=1,getn(UISpecialFrames) do
	if (UISpecialFrames[x]=="ProcWatchFrame") then
	    found_index = x;
	end
    end

    if found_index then -- we are in sticky mode
	tremove(UISpecialFrames, found_index, "ProcWatchFrame"); -- disables ESC functionality
        ProcWatchStickyButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-StickyButton-Down");
	ProcWatch.Sticky = true;
    else
	tinsert(UISpecialFrames, "ProcWatchFrame"); -- enables ESC functionality
        ProcWatchStickyButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-StickyButton-Up");
	ProcWatch.Sticky = false;
    end
    ProcWatchStickyButton_OnEnter(); -- show tooltip of button's new state
end

-- reset button for the "Last" column
function ProcWatchLastResetButton_OnClick()

    ProcWatchEditBox_OnEscapePressed();
    ProcWatch.TotalHits = ProcWatch.TotalHits - ProcWatch.LastHits;
    ProcWatch.TotalProcs = ProcWatch.TotalProcs - ProcWatch.LastProcs;
    ProcWatch.TotalTime = ProcWatch.TotalTime - ProcWatch.LastTime;
    ProcWatch.LastHits = 0;
    ProcWatch.LastProcs = 0;
    ProcWatch.LastTime = 0;
    ProcWatch_UpdateDisplay();
end

-- reset button for the "Totals" column
function ProcWatchTotalResetButton_OnClick()

    ProcWatchEditBox_OnEscapePressed();
    ProcWatch.TotalHits = 0;
    ProcWatch.TotalProcs = 0;
    ProcWatch.TotalTime = 0;
    ProcWatch.LastHits = 0;
    ProcWatch.LastProcs = 0;
    ProcWatch.LastTime = 0;
	ProcWatchDamage = {nil}
    ProcWatch_UpdateDisplay();
end

function ProcWatchOptionsButton_OnClick()

    if ProcWatch.OptionsOpen then
	ProcWatch.OptionsOpen = false;
        ProcWatchOptionsButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Options-Up");
	ProcWatch_Minimize();
	ProcWatch_Maximize();
	ProcWatchOptionsButton_OnEnter();
    else
	ProcWatch.OptionsOpen = true;
        ProcWatchOptionsButton:SetNormalTexture("Interface\\AddOns\\ProcWatch\\ProcWatch-Options-Down");
	ProcWatch_Minimize();
	ProcWatch_Maximize();
	ProcWatchOptionsButton_OnEnter();
    end
end

-- user toggled 'Ignore one-hit fights' option
function ProcWatchIgnoreOneHitFightsCheckButton_OnClick()

    if (ProcWatchIgnoreOneHitFightsCheckButton:GetChecked()==1) then
	ProcWatch.IgnoreOneHitFights = true;
    else
	ProcWatch.IgnoreOneHitFights = false;
    end
end

-- user toggled 'Notify on procs' option
function ProcWatchNotifyOnProcsCheckButton_OnClick()

    if (ProcWatchNotifyOnProcsCheckButton:GetChecked()==1) then
	ProcWatch.NotifyOnProcs = true;
    else
	ProcWatch.NotifyOnProcs = false;
    end
end

-- user toggled 'Show tooltips' option
function ProcWatchShowTooltipsCheckButton_OnClick()

    if (ProcWatchShowTooltipsCheckButton:GetChecked()==1) then
	ProcWatch.ShowTooltips = true;
	ProcWatchShowTooltipsCheckButton_OnEnter();
    else
	ProcWatch.ShowTooltips = false;
	GameTooltip:Hide();	
    end
	
end

-- user toggled 'Watch All Combat' option
function ProcWatchWatchAllCombatCheckButton_OnClick()

    if (ProcWatchWatchAllCombatCheckButton:GetChecked()==1) then
	ProcWatch.WatchAllCombat = true;
    else
	ProcWatch.WatchAllCombat = false;
    end
end

-- user clicked the "event" text to change the text
function ProcWatchEventString_OnClick()

    ProcWatchEventString_Static:Hide();
    if ProcWatch.Enabled then
	ProcWatchEditBox:SetText(ProcWatch.ProcString);
    else
        ProcWatchEditBox:SetText("");
    end
    ProcWatchEditBox:Show();
end

-- user entered new text into "event" textbox
function ProcWatchEditBox_OnEnterPressed()

    local text;

    text = ProcWatchEditBox:GetText();
    if text and string.find(text,"(.+)") and (text ~= ProcWatch.ProcString) then
	ProcWatch_Startup(text); -- start watching for new text
    else
	ProcWatchEditBox:Hide();
	ProcWatchEventString_Static:Show();
    end
end

-- user hit escape or we want to dismiss edit box
-- call this anytime to abort any possible editing in progress
function ProcWatchEditBox_OnEscapePressed()

    ProcWatchEditBox:Hide();
    if not ProcWatch.Minimized then
	ProcWatchEventString_Static:Show();
    end
end

function ProcWatchExitButton_OnClick()
    ProcWatch_Shutdown();
end

function ProcWatchPauseButton_OnClick()

    if ProcWatch.Paused and (ProcWatch.Paused~="disabled") then

	if (ProcWatch.Paused=="enabled") then
	    ProcWatch_SetPause("paused");
	elseif (ProcWatch.Paused=="paused") then
	    ProcWatch_SetPause("enabled");
	end
        ProcWatchPauseButton_OnEnter();

    end

end


--[[ Tooltip OnEnter functions ]]

function ProcWatchCloseButton_OnEnter()
    ProcWatch_Tooltip("Hide Window","Keep monitoring procs, but hide this window.  Hit Exit in options or enter '/procwatch exit' to stop monitoring procs completely.");
end

function ProcWatchMinimizeButton_OnEnter()

    if ProcWatch.Minimized then
	ProcWatch_Tooltip("Restore Window","Expand window to show proc totals.");
    else
	ProcWatch_Tooltip("Minimize Window","Keep monitoring procs, but minimize window.");
    end
end

function ProcWatchStickyButton_OnEnter()

    if ProcWatch.Sticky then
	ProcWatch_Tooltip("Unpin Window", "Allow this window to be moved and dismissed with ESC.");
    else
	ProcWatch_Tooltip("Pin Window", "Prevent this window from moving or being dismissed with ESC.");
    end
end

function ProcWatchStatusButton_OnEnter()

    local state = "";
    local text = "";

    if (ProcWatch.Paused=="enabled") then
	state = "Idle";
	text = "ProcWatch is currently idle and waiting for you to hit something.";
    elseif (ProcWatch.Paused=="paused") then
	state = "Paused";
	text = "ProcWatch is current paused and all monitoring is suspended.  You can resume by hitting the 'Play' button to the right.";
    elseif (ProcWatch.Paused=="disabled") then
	if not ProcWatch.Enabled then
	    state = "Stopped";
	    text = "ProcWatch is currently stopped and waiting for you to tell it what to look for.";
	else
	    state = "Active";
	    text = "ProcWatch is currently active and monitoring combat spam for proc events.";
	end
    end

    ProcWatch_Tooltip("Status: "..state,text.."\n\nRed is Stopped.\nYellow is Paused.\nGrey is Idle.\nGreen is Active");

end

function ProcWatchEventString_OnEnter()

    ProcWatchEventString_Text:SetTextColor(1.0, 1.0, 1.0);
    if ProcWatch.Enabled then
        ProcWatch_Tooltip("Event: \""..ProcWatch.ProcString.."\"", "During melee, each line of combat spam that contains this text is considered a proc event.\n\nChanging this text will reset totals.");
    else
	ProcWatch_Tooltip("Event: None defined yet.", "Click here or use '/procwatch (text)' to define a proc event.\n\nIt can be partial text, such as 'Your Fiery Weapon', or it can be a complete line, such as 'You gain 50 Mana.'.  Text is case insensitive.\n\nSome wildcards:\n(.+) : any string of characters\n(%d+) : any string of digits\n(%w+) : any string of alphanumeric");
    end
end

function ProcWatchEventString_OnLeave()

    GameTooltip:Hide();
    ProcWatchEventString_Text:SetTextColor(0.75, 0.75, 0.75);
end


function ProcWatchLastResetButton_OnEnter()
    ProcWatch_Tooltip("Reset Last Fight","This will remove the last fight from the running totals.  Useful for anomalous results such as disarmed or wrong weapon equipped.");
end

function ProcWatchTotalResetButton_OnEnter()
    ProcWatch_Tooltip("Reset Totals","This will remove all proc data and begin watching for the defined proc event as if all previous fights never happened.");
end

function ProcWatchOptionsButton_OnEnter()

    if ProcWatch.OptionsOpen then
	ProcWatch_Tooltip("Hide Options","Hide ProcWatch settings.");
    else
        ProcWatch_Tooltip("Show Options","Open ProcWatch settings.");
    end
end

function ProcWatchIgnoreOneHitFightsCheckButton_OnEnter()
    ProcWatch_Tooltip("Ignore One-Hit Fights","Fights are ordinarily timed from the first hit to the last hit.  Checking this will ensure only fights with at least two hits are totalled.");
end

function ProcWatchNotifyOnProcsCheckButton_OnEnter()
    ProcWatch_Tooltip("Notify on Procs", "Checking this will cause a proc alert to momentarily appear on the screen in the event of a proc.");
end

function ProcWatchShowTooltipsCheckButton_OnEnter()
    ProcWatch_Tooltip("Show Tooltips", "Checking this will enable tooltips like the one you're reading.");
end

function ProcWatchEditBox_OnEnter()
    ProcWatch_Tooltip("Enter Event Definition", "Enter text to define a proc event.\n\nIt can be partial text, such as 'Your Fiery Weapon', or it can be a complete line, such as 'You gain 50 Mana.'.  Text is case insensitive.\n\nSome wildcards:\n(.+) : any string of characters\n(%d+) : any string of digits\n(%w+) : any string of alphanumeric");
end

function ProcWatchWatchAllCombatCheckButton_OnEnter()
    ProcWatch_Tooltip("Watch All Combat", "Fights are ordinarily timed from the first hit.  Checking this will begin the timer and watch for procs when you enter combat mode for any reason.");
end

function ProcWatchExitButton_OnEnter()
    ProcWatch_Tooltip("Exit ProcWatch", "This completely shuts down ProcWatch.  All monitoring will cease and all totals are lost.");
end

function ProcWatchPauseButton_OnEnter()

    if (ProcWatch.Paused=="enabled") then
	ProcWatch_Tooltip("Pause ProcWatch", "Suspend monitoring until you resume or start a new watch.");
    elseif (ProcWatch.Paused=="paused") then
	ProcWatch_Tooltip("Resume ProcWatch", "Resume monitoring for procs.");
    elseif (ProcWatch.Paused=="disabled") then
	if not ProcWatch.Enabled then
	    ProcWatch_Tooltip("Pause Disabled", "Monitoring is already suspended.  Once ProcWatch has an event to watch for, this button can be used to pause and resume monitoring without affecting totals.");
	else
	    ProcWatch_Tooltip("Pause Disabled", "ProcWatch is active and watching for procs in the current fight.  When the fight is over you can pause.");
	end
    end

end
