local addonName, GQT = ...

GQT.pendingQuestData = {}
GQT.totalQuestsToLoad = 0
GQT.loadedQuests = {}
GQT.goldQuests = {}
GQT.isProcessing = false
GQT.zonesScanned = 0
GQT.totalZones = 0
GQT.scanActive = false
GQT.forceRefresh = false

GQT.dataReady = false

function GQT:Initialize()
  self.db = _G.GoldQuestTrackerDB or CopyTable(GQT.Config.defaults)
  _G.GoldQuestTrackerDB = self.db

  print '|cFFFFD700Gold Quest Tracker:|r Addon loaded.'

  GQT.UI:CreateMinimapIcon()
  GQT.UI:CreateMainFrame()

  self.frame = CreateFrame 'Frame'
  self.frame:RegisterEvent 'QUEST_DATA_LOAD_RESULT'
  self.frame:RegisterEvent 'PLAYER_ENTERING_WORLD'
  self.frame:SetScript('OnEvent', function(_, event, ...)
    if self[event] then
      self[event](self, ...)
    end
  end)
end

function GQT:PLAYER_ENTERING_WORLD()
  C_Timer.After(5, function()
    self.dataReady = true
    print '|cFFFFD700Gold Quest Tracker:|r World data loaded and ready.'

    self:PreCacheQuestData()
  end)
end

function GQT:PreCacheQuestData()
  local questCount = 0
  
  for mapID, _ in pairs(GQT.Config.trackedZones) do
    local zoneQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
    for _, questData in ipairs(zoneQuests) do
      if questData.mapID == mapID and C_QuestLog.IsWorldQuest(questData.questID) then
        questCount = questCount + 1
        C_TaskQuest.RequestPreloadRewardData(questData.questID)
      end
    end
  end

  if GQT.Config.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Pre-cached ' .. questCount .. ' quests for faster response.')
  end
end

-- Completely revamped ScanForGoldQuests function with direct approach and safeguards
function GQT:ScanForGoldQuests()
  -- Always allow a fresh scan by resetting state
  if self.scanActive then
    self.scanActive = false
  end

  -- Reset state completely
  self.scanActive = true
  self.scanStartTime = GetTime()
  self.goldQuests = {}
  self.processedQuests = {}
  self.forceRefresh = false

  -- Set a loading state in the UI
  if self.UI then
    self.UI:ShowEmptyState(true)
  end


  -- Preload quest data first
  self:PreCacheQuestData()
  
  -- Wait a moment for precaching, then scan
  C_Timer.After(1.0, function()
    if not self.scanActive then return end
    self:DirectScan()
  end)
  
  -- Guaranteed completion safety timeout
  C_Timer.After(8, function()
    if self.scanActive then
      self.scanActive = false
      self.UI:DisplayQuests()
    end
  end)
end

-- New direct scanning approach that doesn't rely on complex callbacks
function GQT:DirectScan()
  if GQT.Config.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Directly scanning for gold quests...')
  end
  
  local totalQuests = 0
  local worldQuests = 0
  
  -- First pass - request all quest data
  for mapID, zoneName in pairs(GQT.Config.trackedZones) do
    local zoneQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
    totalQuests = totalQuests + #zoneQuests
    
    if GQT.Config.debug then
      print('|cFFFFD700Gold Quest Tracker:|r Found ' .. #zoneQuests .. ' quests in ' .. zoneName)
    end
    
    -- Request data for all world quests
    for _, questData in ipairs(zoneQuests) do
      local questID = questData.questID
      if questID and C_QuestLog.IsWorldQuest(questID) then
        worldQuests = worldQuests + 1
        C_TaskQuest.RequestPreloadRewardData(questID)
      end
    end
  end
  
  
  -- Multiple processing passes with longer delays
  local function ProcessAllQuests(passNumber)
    if not self.scanActive then return end
    
    
    for mapID, _ in pairs(GQT.Config.trackedZones) do
      local zoneQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
      
      for _, questData in ipairs(zoneQuests) do
        local questID = questData.questID
        if questID and C_QuestLog.IsWorldQuest(questID) then
          self:ProcessQuest(questID, mapID)
        end
      end
    end
    
    -- If this is the final pass, complete the scan
    if passNumber >= 3 then
      self.scanActive = false
      self.UI:DisplayQuests()
    else
      -- Schedule next pass
      C_Timer.After(1.5, function()
        ProcessAllQuests(passNumber + 1)
      end)
    end
  end
  
  -- Start first processing pass after initial delay
  C_Timer.After(2.0, function()
    ProcessAllQuests(1)
  end)
end

-- Process a single quest directly without callbacks
function GQT:ProcessQuest(questID, mapID)
  -- Skip if already processed
  if self.processedQuests and self.processedQuests[questID] then
    return
  end
  
  -- Initialize the processed quests table if needed
  if not self.processedQuests then
    self.processedQuests = {}
  end
  
  -- Mark as processed
  self.processedQuests[questID] = true
  
  -- Check if data is available
  if not HaveQuestData(questID) then
    return
  end
  
  -- Get basic quest info
  local questName = C_TaskQuest.GetQuestInfoByQuestID(questID)
  if not questName then return end
  
  -- Check if we need to get mapID
  if not mapID then
    mapID = C_TaskQuest.GetQuestZoneID(questID)
    if not mapID then return end
  end
  
  -- Get location
  local locationX, locationY = C_TaskQuest.GetQuestLocation(questID, mapID)
  local location = { x = locationX or 0.5, y = locationY or 0.5 }
  
  -- Get the zone name
  local mapInfo = C_Map.GetMapInfo(mapID)
  local zoneName = mapInfo and mapInfo.name or 'Unknown Zone'
  
  -- Check for gold reward using modern APIs
  local moneyReward = GetQuestLogRewardMoney(questID)
  
  -- For world quests, try the modern C_QuestLog API
  if not moneyReward or moneyReward <= 0 then
    -- Get quest log index for this quest
    local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if questLogIndex then
      -- Select this quest and get rewards
      C_QuestLog.SetSelectedQuest(questID)
      moneyReward = GetQuestLogRewardMoney()
    end
  end
  
  -- For debugging, let's see what we get
  if GQT.Config.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Quest ' .. questID .. ' (' .. questName .. ') - Money reward: ' .. (moneyReward or 0))
  end
  
  if not moneyReward or moneyReward <= 0 then
    return
  end
  
  -- Get time left
  local timeLeft = 'Unknown'
  local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
  
  if timeLeftMinutes then
    if timeLeftMinutes <= 60 then
      timeLeft = string.format('%d mins', timeLeftMinutes)
    else
      local hours = math.floor(timeLeftMinutes / 60)
      local mins = timeLeftMinutes % 60
      timeLeft = string.format('%dh %dm', hours, mins)
    end
    
    -- Add to results
    table.insert(self.goldQuests, {
      id = questID,
      mapID = mapID,
      title = questName,
      zone = zoneName,
      gold = moneyReward,
      timeLeft = timeLeft,
      location = location,
      link = GetQuestLink(questID) or 'Quest Link',
    })
    
    if GQT.Config.debug then
      print('|cFFFFD700Gold Quest Tracker:|r Found gold quest: ' .. questName .. ' (' .. self:FormatMoney(moneyReward) .. ')')
    end
  end
end

-- Legacy event handler - simplified to avoid stuck states
function GQT:QUEST_DATA_LOAD_RESULT(questID, success)
  -- If scanning, try to process this quest
  if self.scanActive and success and C_QuestLog.IsWorldQuest(questID) then
    local mapID = C_TaskQuest.GetQuestZoneID(questID)
    if mapID and GQT.Config.trackedZones[mapID] then
      self:ProcessQuest(questID, mapID)
    end
  end
end

-- Helper function to format money for debugging
function GQT:FormatMoney(copper)
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  return gold .. "g " .. silver .. "s"
end

local function SlashCommandHandler(msg)
  msg = msg and msg:lower() or ''

  if msg == '' then
    if GQT.UI.mainFrame and GQT.UI.mainFrame:IsShown() then
      GQT.UI.mainFrame:Hide()
      GQT:PreCacheQuestData()
    else
      GQT:ScanForGoldQuests()
      GQT.UI.mainFrame:Show()
    end
  elseif msg == 'help' then
    print '|cFFFFD700Gold Quest Tracker:|r Commands:'
    print '  /gqt - Scan for gold world quests'
    print '  /gqt help - Show this help message'
  else
    print '|cFFFFD700Gold Quest Tracker:|r Unknown command. Type /gqt help for available commands.'
  end

  if ChatFrameEditBox then
    ChatFrameEditBox:Hide()  -- For older versions of WoW
  elseif ChatFrame1EditBox then
    ChatFrame1EditBox:Hide() -- Alternative in case the previous doesn't work
  else
    ChatFrame_CloseChat()    -- Works for newer versions of WoW
  end
end

SLASH_GOLDQUESTTRACKER1 = '/gqt'
SLASH_GOLDQUESTTRACKER2 = '/goldquest'
SlashCmdList['GOLDQUESTTRACKER'] = SlashCommandHandler

local initFrame = CreateFrame 'Frame'
initFrame:RegisterEvent 'ADDON_LOADED'
initFrame:SetScript('OnEvent', function(self, event, ...)
  if event == 'ADDON_LOADED' and ... == addonName then
    GQT:Initialize()
    self:UnregisterEvent 'ADDON_LOADED'
  end
end)
