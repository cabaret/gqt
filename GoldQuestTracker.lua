local addonName, GQT = ...
local icon = LibStub 'LibDBIcon-1.0'
local LDB = LibStub 'LibDataBroker-1.1'

-- Zones to track (with their map IDs)
local trackedZones = {
  [2339] = 'Dornogal',
  [2248] = 'Isle of Dorn',
  [2214] = 'The Ringing Deeps',
  [2215] = 'Hallowfall',
  [2255] = 'Azj-Kahet',
  [2369] = 'Siren Isle',
  [2346] = 'Undermine',
}

GQT.pendingQuestData = {}
GQT.totalQuestsToLoad = 0
GQT.loadedQuests = {}
GQT.goldQuests = {}
GQT.isProcessing = false
GQT.zonesScanned = 0
GQT.totalZones = 0
GQT.scanActive = false
GQT.scanAttempt = 0
GQT.dataReady = false
GQT.debug = true -- Set to false to disable debug messages

local defaults = {
  minimap = {
    hide = false,
  },
  quests = {},
}

function GQT:Initialize()
  self.db = _G.GoldQuestTrackerDB or CopyTable(defaults)
  _G.GoldQuestTrackerDB = self.db

  print '|cFFFFD700Gold Quest Tracker:|r Addon loaded.'

  self:CreateMinimapIcon()
  self:CreateMainFrame()

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
  -- Wait a bit after player enters world to ensure all APIs are fully ready
  C_Timer.After(5, function()
    self.dataReady = true
    print '|cFFFFD700Gold Quest Tracker:|r World data loaded and ready.'

    self:PreCacheQuestData()
  end)
end

function GQT:PreCacheQuestData()
  for mapID, _ in pairs(trackedZones) do
    local zoneQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
    for _, questData in ipairs(zoneQuests) do
      if questData.mapID == mapID and C_QuestLog.IsWorldQuest(questData.questID) then
        C_TaskQuest.RequestPreloadRewardData(questData.questID)
      end
    end
  end

  if self.debug then
    print '|cFFFFD700Gold Quest Tracker:|r Pre-cached quest data for faster response.'
  end
end

function GQT:ScanForGoldQuests()
  -- Don't start a new scan if one is already active
  if self.scanActive then
    print '|cFFFFD700Gold Quest Tracker:|r Scan already in progress. Please wait...'
    return
  end

  -- Check if data is ready
  if not self.dataReady then
    print '|cFFFFD700Gold Quest Tracker:|r World data not fully loaded yet. Please try again in a few seconds.'
    return
  end

  self.scanActive = true
  self.pendingQuestData = {} -- Reset
  self.loadedQuests = {}     -- Reset
  self.goldQuests = {}       -- Reset
  self.totalQuestsToLoad = 0 -- Reset
  self.isProcessing = false  -- Reset
  self.zonesScanned = 0      -- Track how many zones we've scanned
  self.totalZones = 0        -- Track total zones to scan
  self.scanAttempt = 1       -- Reset scan attempts

  if self.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Starting scan for gold quests (attempt ' .. self.scanAttempt .. ')...')
  end

  -- Count total zones
  for _ in pairs(trackedZones) do
    self.totalZones = self.totalZones + 1
  end

  -- Initial scan
  self:PerformZoneScan()

  -- Add multiple retry attempts with increasing delays
  C_Timer.After(1, function()
    if #self.goldQuests < 1 and self.scanActive then
      self.scanAttempt = self.scanAttempt + 1
      print('|cFFFFD700Gold Quest Tracker:|r Retry scan (attempt ' .. self.scanAttempt .. ')...')
      self:PerformZoneScan()
    end
  end)

  C_Timer.After(2, function()
    if #self.goldQuests < 2 and self.scanActive then
      self.scanAttempt = self.scanAttempt + 1
      print('|cFFFFD700Gold Quest Tracker:|r Retry scan (attempt ' .. self.scanAttempt .. ')...')
      self:PerformZoneScan()
    end
  end)

  -- Final safety timer
  C_Timer.After(3, function()
    if self.scanActive then
      print '|cFFFFD700Gold Quest Tracker:|r Finalizing scan (all attempts completed)...'
      self.isProcessing = true
      self:ProcessLoadedQuests()
    end
  end)
end

function GQT:PerformZoneScan()
  for mapID, zoneName in pairs(trackedZones) do
    self:ScanForGoldQuestsInZone(mapID, zoneName)
  end

  -- If we didn't find any quests at all in this scan attempt, handle that
  if self.totalQuestsToLoad == 0 and self.scanAttempt >= 3 then
    print '|cFFFFD700Gold Quest Tracker:|r No quests found to track after multiple attempts.'
    self:DisplayQuests() -- Will show empty state
    self.scanActive = false
  end
end

function GQT:ScanForGoldQuestsInZone(mapID, zoneName)
  local zoneQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
  local filteredQuests = {}

  for _, questData in ipairs(zoneQuests) do
    if questData.mapID == mapID and C_QuestLog.IsWorldQuest(questData.questID) then
      table.insert(filteredQuests, questData)
    end
  end

  if self.debug then
    print('|cFFFFD700GQT Debug:|r Found ' .. #filteredQuests .. ' quests in ' .. zoneName)
  end

  self.totalQuestsToLoad = self.totalQuestsToLoad + #filteredQuests
  self.zonesScanned = self.zonesScanned + 1

  if #filteredQuests > 0 then
    for _, questData in ipairs(filteredQuests) do
      local questID = questData.questID
      if C_QuestLog.IsWorldQuest(questID) then
        self.pendingQuestData[questID] = true
        if HaveQuestData(questID) then
          -- Process immediately if we already have data
          C_Timer.After(0.1, function()
            self:QUEST_DATA_LOAD_RESULT(questID, true)
          end)
        else
          -- Request data load
          C_TaskQuest.RequestPreloadRewardData(questID)
        end
      end
    end
  end

  -- If all zones scanned and no quests to load, process (empty) results
  if self.zonesScanned == self.totalZones and self.totalQuestsToLoad == 0 then
    self.isProcessing = true
    self:ProcessLoadedQuests()
  end
end

function GQT:QUEST_DATA_LOAD_RESULT(questID, success)
  if not self.pendingQuestData[questID] or not self.scanActive then
    return
  end

  if success then
    self.pendingQuestData[questID] = nil
    self.loadedQuests[questID] = true

    local loadedCount = 0
    for _ in pairs(self.loadedQuests) do
      loadedCount = loadedCount + 1
    end

    local allLoaded = loadedCount == self.totalQuestsToLoad
    local allZonesScanned = self.zonesScanned == self.totalZones

    -- Only process when all data is loaded or all zones scanned
    if allLoaded and allZonesScanned and not self.isProcessing then
      self.isProcessing = true
      self:ProcessLoadedQuests()
    end
  else
    -- Handle failed quest data load
    if self.debug then
      print('|cFFFFD700Gold Quest Tracker:|r Failed to load data for quest ID: ' .. questID)
    end
    self.pendingQuestData[questID] = nil

    -- Check if this was the last quest we were waiting for
    local pendingCount = 0
    for _ in pairs(self.pendingQuestData) do
      pendingCount = pendingCount + 1
    end

    if pendingCount == 0 and self.zonesScanned == self.totalZones and not self.isProcessing then
      self.isProcessing = true
      self:ProcessLoadedQuests()
    end
  end
end

function GQT:ProcessLoadedQuests()
  if not self.scanActive then
    return
  end

  for questID in pairs(self.loadedQuests) do
    local questName = C_TaskQuest.GetQuestInfoByQuestID(questID)
    local mapID = C_TaskQuest.GetQuestZoneID(questID)
    local locationX, locationY = C_TaskQuest.GetQuestLocation(questID, mapID)
    local location = { x = locationX, y = locationY }

    -- Skip if we can't get valid data
    if not questName or not mapID then
      if self.debug then
        print('|cFFFFD700Gold Quest Tracker:|r Missing data for quest ID: ' .. questID)
      end
    else
      local mapInfo = C_Map.GetMapInfo(mapID)
      local zoneName = mapInfo and mapInfo.name or 'Unknown Zone'
      local moneyReward = GetQuestLogRewardMoney(questID)

      if moneyReward and moneyReward > 0 then
        if self.debug then
          print('Processing quest: ' .. questName .. ' - Gold: ' .. moneyReward)
        end
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
        end
      end
    end
  end

  -- Clear scan status
  self.scanActive = false

  -- Sort and display quests
  self:DisplayQuests()
end

function GQT:DisplayQuests()
  if self.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Found ' .. #self.goldQuests .. ' gold quests.')
  end

  if #self.goldQuests == 0 then
    -- Show empty state
    self:ShowEmptyState()
    return
  end

  -- Sort by gold amount (highest first)
  table.sort(self.goldQuests, function(a, b)
    return a.gold > b.gold
  end)

  -- Make sure we have a main frame
  self:CreateMainFrame()

  -- Update title with count
  self.mainFrame.title:SetText('Gold World Quests (' .. #self.goldQuests .. ')')

  -- Clear existing content
  local content = self.mainFrame.content
  -- Store a temporary table of children to avoid modification during iteration
  local children = {}
  for i = 1, content:GetNumChildren() do
    local child = select(i, content:GetChildren())
    if child then
      table.insert(children, child)
    end
  end

  -- Now hide and unparent them
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end

  -- Calculate total gold
  local totalGold = 0
  for _, quest in ipairs(self.goldQuests) do
    totalGold = totalGold + quest.gold
  end

  -- Show total gold
  self.mainFrame.totalGoldText:SetText('Total Gold: ' .. self:FormatMoney(totalGold))

  local yOffset = -10
  for i, quest in ipairs(self.goldQuests) do
    local questID = quest.id -- Store the ID in a local variable for closure

    local entry = CreateFrame('Button', 'GQTQuestEntry' .. i, content, BackdropTemplateMixin and 'BackdropTemplate')
    entry:SetSize(content:GetWidth() - 20, 40)
    entry:SetPoint('TOPLEFT', content, 'TOPLEFT', 5, yOffset)

    -- Modern entry background
    local entryBackdrop = {
      bgFile = 'Interface\\Buttons\\WHITE8x8',
      edgeFile = 'Interface\\Buttons\\WHITE8x8',
      tile = false,
      tileSize = 0,
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
    self:ApplyBackdrop(entry, entryBackdrop)
    self:SetBackdropColor(entry, 0.15, 0.15, 0.15, 0.7)
    self:SetBackdropBorderColor(entry, 0.3, 0.3, 0.3, 0.5)

    -- Highlight on mouse over
    entry:SetScript('OnEnter', function(self)
      GQT:SetBackdropColor(self, 0.25, 0.25, 0.25, 0.9)
      GQT:SetBackdropBorderColor(self, 0.6, 0.6, 0.6, 0.8)

      GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
      GameTooltip:SetText(quest.title, 1, 0.8, 0)
      GameTooltip:AddLine(quest.zone, 0.7, 0.7, 1)
      GameTooltip:AddLine('Reward: ' .. GQT:FormatMoney(quest.gold), 1, 0.8, 0)
      GameTooltip:AddLine('Time remaining: ' .. quest.timeLeft, 1, 0.7, 0.7)
      GameTooltip:AddLine ' '
      GameTooltip:AddLine('Click to track this quest', 0, 1, 0)
      GameTooltip:Show()
    end)

    entry:SetScript('OnLeave', function(self)
      GQT:SetBackdropColor(self, 0.15, 0.15, 0.15, 0.7)
      GQT:SetBackdropBorderColor(self, 0.3, 0.3, 0.3, 0.5)
      GameTooltip:Hide()
    end)

    -- Quest title with better font
    local title = entry:CreateFontString(nil, 'OVERLAY')
    title:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
    title:SetPoint('TOPLEFT', entry, 'TOPLEFT', 8, -5)
    title:SetText(quest.title)
    title:SetTextColor(1, 1, 1)

    -- Zone name
    local zone = entry:CreateFontString(nil, 'OVERLAY')
    zone:SetFont('Fonts\\ARIALN.TTF', 10, 'NONE')
    zone:SetPoint('BOTTOMLEFT', entry, 'BOTTOMLEFT', 8, 5)
    zone:SetText(quest.zone)
    zone:SetTextColor(0.7, 0.7, 1)

    -- Reward amount
    local reward = entry:CreateFontString(nil, 'OVERLAY')
    reward:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
    reward:SetPoint('TOPRIGHT', entry, 'TOPRIGHT', -16, -5)
    reward:SetText(self:FormatMoney(quest.gold))
    reward:SetTextColor(1, 0.8, 0)

    -- Time remaining
    local time = entry:CreateFontString(nil, 'OVERLAY')
    time:SetFont('Fonts\\ARIALN.TTF', 10, 'NONE')
    time:SetPoint('BOTTOMRIGHT', entry, 'BOTTOMRIGHT', -16, 5)
    time:SetText(quest.timeLeft)
    time:SetTextColor(1, 0.7, 0.7)

    -- Click effect
    entry:SetScript('OnMouseDown', function(self)
      GQT:SetBackdropColor(self, 0.1, 0.1, 0.1, 0.9)
    end)

    entry:SetScript('OnMouseUp', function(self)
      GQT:SetBackdropColor(self, 0.25, 0.25, 0.25, 0.9)
    end)

    -- Make clickable to track quest - fixed to properly track
    entry:SetScript('OnClick', function(self)
      if questID then
        -- Debug output
        print('|cFFFFD700Gold Quest Tracker:|r Tracking quest: ' .. quest.title .. ' (ID: ' .. questID .. ')')

        C_QuestLog.AddWorldQuestWatch(questID) -- Add to watched quests

        print(quest.mapID, quest.location.x, quest.location.y)
        local waypoint = UiMapPoint.CreateFromCoordinates(quest.mapID, quest.location.x, quest.location.y)
        C_Map.SetUserWaypoint(waypoint)

        -- Visual feedback
        local r, g, b = 0.2, 0.8, 0.2 -- Green highlight color
        GQT:SetBackdropColor(self, r, g, b, 0.3)

        C_Timer.After(0.3, function()
          if self:IsShown() then -- Only reset if still visible
            GQT:SetBackdropColor(self, 0.15, 0.15, 0.15, 0.7)
          end
        end)
      else
        print '|cFFFFD700Gold Quest Tracker:|r Unable to track quest: Missing quest ID'
      end
    end)

    yOffset = yOffset - 45
  end

  -- Set content height
  content:SetHeight(math.abs(yOffset) + 10)

  -- Update scrollbar
  if self.mainFrame.UpdateScrollbar then
    self.mainFrame.UpdateScrollbar()
  end

  -- Show frame
  self.mainFrame:Show()
end

function GQT:PrintTable(tbl, indent)
  if not tbl then
    return
  end

  -- Check if the input is actually a table
  if type(tbl) ~= 'table' then
    print(tostring(tbl) .. " is not a table, it's a " .. type(tbl))
    return
  end

  indent = indent or 0
  local spaces = string.rep('  ', indent)

  for k, v in pairs(tbl) do
    if type(v) == 'table' then
      print(spaces .. tostring(k) .. ' = {')
      self:PrintTable(v, indent + 1)
      print(spaces .. '}')
    else
      print(spaces .. tostring(k) .. ' = ' .. tostring(v))
    end
  end
end

function GQT:ShowEmptyState()
  -- Make sure we have a main frame
  self:CreateMainFrame()

  -- Update title
  self.mainFrame.title:SetText 'Gold World Quests (0)'

  -- Clear existing content
  local content = self.mainFrame.content
  for i = 1, content:GetNumChildren() do
    local child = select(i, content:GetChildren())
    if child then
      child:Hide()
      child:SetParent(nil)
    end
  end

  -- Show empty message with modern style
  local emptyFrame = CreateFrame('Frame', nil, content, BackdropTemplateMixin and 'BackdropTemplate')
  emptyFrame:SetSize(content:GetWidth() - 20, 80)
  emptyFrame:SetPoint('CENTER', content, 'CENTER', 0, 0)

  -- Empty frame background
  local emptyBackdrop = {
    bgFile = 'Interface\\Buttons\\WHITE8x8',
    edgeFile = 'Interface\\Buttons\\WHITE8x8',
    tile = false,
    tileSize = 0,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  }
  self:ApplyBackdrop(emptyFrame, emptyBackdrop)
  self:SetBackdropColor(emptyFrame, 0.1, 0.1, 0.1, 0.5)
  self:SetBackdropBorderColor(emptyFrame, 0.3, 0.3, 0.3, 0.3)

  -- Empty state text
  local emptyText = emptyFrame:CreateFontString(nil, 'OVERLAY')
  emptyText:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
  emptyText:SetPoint('CENTER', emptyFrame, 'CENTER', 0, 0)
  emptyText:SetText 'No gold quests found'
  emptyText:SetTextColor(0.7, 0.7, 0.7)

  -- Show frame
  self.mainFrame:Show()

  -- Set content height and update scrollbar
  content:SetHeight(100)
  if self.mainFrame.UpdateScrollbar then
    self.mainFrame.UpdateScrollbar()
  end
end

function GQT:CreateMinimapIcon()
  local brokerObject = LDB:NewDataObject('GoldQuestTracker', {
    type = 'data source',
    text = 'Gold Quests',
    icon = 'Interface\\Icons\\INV_Misc_Coin_01',
    OnClick = function(_, button)
      if button == 'LeftButton' then
        if self.mainFrame and self.mainFrame:IsShown() then
          self.mainFrame:Hide()
          self:PreCacheQuestData()
        elseif self.mainFrame then
          self:ScanForGoldQuests()
          self.mainFrame:Show()
        end
      end
    end,
    OnTooltipShow = function(tooltip)
      tooltip:AddLine 'Gold Quest Tracker'
      tooltip:AddLine ' '
      tooltip:AddLine 'Left-click to scan for gold quests'
      tooltip:AddLine 'Right-click to toggle display'
    end,
  })

  icon:Register('GoldQuestTracker', brokerObject, self.db.minimap)
end

function GQT:CreateMainFrame()
  if self.mainFrame then
    return
  end

  -- Create main frame
  self.mainFrame = CreateFrame('Frame', 'GoldQuestTrackerFrame', UIParent, BackdropTemplateMixin and 'BackdropTemplate')
  self.mainFrame:SetSize(400, 250)
  self.mainFrame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
  self.mainFrame:SetMovable(true)
  self.mainFrame:EnableMouse(true)
  self.mainFrame:RegisterForDrag 'LeftButton'
  self.mainFrame:SetScript('OnDragStart', self.mainFrame.StartMoving)
  self.mainFrame:SetScript('OnDragStop', self.mainFrame.StopMovingOrSizing)

  -- Modern semi-transparent background using our custom function
  local mainBackdrop = {
    bgFile = 'Interface\\Buttons\\WHITE8x8',
    edgeFile = 'Interface\\Buttons\\WHITE8x8',
    tile = false,
    tileSize = 0,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  }
  self:ApplyBackdrop(self.mainFrame, mainBackdrop)
  self:SetBackdropColor(self.mainFrame, 0.1, 0.1, 0.1, 0.9)       -- Dark background
  self:SetBackdropBorderColor(self.mainFrame, 0.6, 0.6, 0.6, 0.8) -- Subtle border

  -- Add header background
  local headerBg = self.mainFrame:CreateTexture(nil, 'BACKGROUND')
  headerBg:SetPoint('TOPLEFT', 0, 0)
  headerBg:SetPoint('TOPRIGHT', 0, 0)
  headerBg:SetHeight(40)
  headerBg:SetColorTexture(0.15, 0.15, 0.15, 1) -- Slightly darker than main frame

  -- Close button (modern X)
  local closeButton = CreateFrame('Button', nil, self.mainFrame)
  closeButton:SetSize(20, 20)
  closeButton:SetPoint('TOPRIGHT', self.mainFrame, 'TOPRIGHT', -10, -10)

  closeButton.text = closeButton:CreateFontString(nil, 'OVERLAY')
  closeButton.text:SetFont('Fonts\\ARIALN.TTF', 24, 'OUTLINE')
  closeButton.text:SetPoint('CENTER', 0, 0)
  closeButton.text:SetText '×'
  closeButton.text:SetTextColor(0.7, 0.7, 0.7)

  closeButton:SetScript('OnEnter', function(self)
    self.text:SetTextColor(1, 0.3, 0.3)
  end)

  closeButton:SetScript('OnLeave', function(self)
    self.text:SetTextColor(0.7, 0.7, 0.7)
  end)

  closeButton:SetScript('OnClick', function()
    self.mainFrame:Hide()
  end)

  -- Title
  self.mainFrame.title = self.mainFrame:CreateFontString(nil, 'OVERLAY')
  self.mainFrame.title:SetFont('Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
  self.mainFrame.title:SetPoint('TOP', self.mainFrame, 'TOP', 0, -15)
  self.mainFrame.title:SetText 'Gold World Quests'
  self.mainFrame.title:SetTextColor(1, 0.8, 0)

  -- Total gold display
  self.mainFrame.totalGoldText = self.mainFrame:CreateFontString(nil, 'OVERLAY')
  self.mainFrame.totalGoldText:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
  self.mainFrame.totalGoldText:SetPoint('BOTTOMRIGHT', self.mainFrame, 'BOTTOMRIGHT', -15, 15)
  self.mainFrame.totalGoldText:SetText 'Total Gold: 0g 0s 0c'
  self.mainFrame.totalGoldText:SetTextColor(1, 0.8, 0)

  -- Content area with custom background
  local content = CreateFrame('Frame', nil, self.mainFrame)
  content:SetSize(380, 325)
  content:SetPoint('TOP', self.mainFrame.title, 'BOTTOM', 0, -10)
  -- Adjusted to leave more space above the refresh button
  content:SetPoint('BOTTOM', self.mainFrame, 'BOTTOM', 0, 50) -- Changed from 40 to 50

  -- Content background
  local bg = content:CreateTexture(nil, 'BACKGROUND')
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.05, 0.7) -- Darker than main frame background

  -- Custom scroll frame
  local scrollFrame = CreateFrame('ScrollFrame', nil, content)
  scrollFrame:SetPoint('TOPLEFT', content, 'TOPLEFT', 5, -5)
  scrollFrame:SetPoint('BOTTOMRIGHT', content, 'BOTTOMRIGHT', -5, 5)

  -- Scroll child
  local scrollChild = CreateFrame('Frame', nil, scrollFrame)
  scrollFrame:SetScrollChild(scrollChild)
  scrollChild:SetWidth(scrollFrame:GetWidth())
  scrollChild:SetHeight(1) -- Will be resized as needed

  -- Custom scrollbar
  -- Create a slimmer, more modern scrollbar
  local scrollbar = CreateFrame('Slider', nil, scrollFrame, 'UIPanelScrollBarTemplate')
  scrollbar:SetPoint('TOPRIGHT', scrollFrame, 'TOPRIGHT', 20, 0) -- Inside the frame
  scrollbar:SetPoint('BOTTOMRIGHT', scrollFrame, 'BOTTOMRIGHT', 20, 0)
  scrollbar:SetMinMaxValues(0, 0)
  scrollbar:SetValueStep(1)
  scrollbar:SetValue(0)
  scrollbar:SetWidth(8) -- Much slimmer width

  -- Make the scroll buttons smaller and less obtrusive
  scrollbar.ScrollUpButton:SetSize(8, 8)
  scrollbar.ScrollDownButton:SetSize(8, 8)

  -- Create a smaller, more subtle thumb texture
  scrollbar.ThumbTexture:SetSize(8, 30)
  scrollbar.ThumbTexture:SetColorTexture(0.4, 0.4, 0.4, 0.6) -- Subtle gray

  -- Add a very subtle background for the scrollbar track
  local scrollBg = scrollbar:CreateTexture(nil, 'BACKGROUND')
  scrollBg:SetAllPoints()
  scrollBg:SetColorTexture(0.1, 0.1, 0.1, 0.2) -- Almost invisible background

  -- You might also need to adjust the content width to accommodate the scrollbar
  content:SetWidth(370)                                               -- Slightly smaller to make room for scrollbar
  scrollFrame:SetPoint('BOTTOMRIGHT', content, 'BOTTOMRIGHT', -10, 5) -- Give space for scrollbar
  -- Add a background to the scrollbar track
  local scrollBg = scrollbar:CreateTexture(nil, 'BACKGROUND')
  scrollBg:SetAllPoints()
  scrollBg:SetColorTexture(0.1, 0.1, 0.1, 0.4)

  -- Make the scrollbar react to the mouse wheel
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript('OnMouseWheel', function(self, delta)
    local current = scrollbar:GetValue()
    local min, max = scrollbar:GetMinMaxValues()

    if delta < 0 and current < max then
      scrollbar:SetValue(current + 20)
    elseif delta > 0 and current > min then
      scrollbar:SetValue(current - 20)
    end
  end)

  -- Update the function to handle scrolling
  local function UpdateScrollbar()
    local height = scrollChild:GetHeight()
    local visible = scrollFrame:GetHeight()
    if height > visible then
      scrollbar:SetMinMaxValues(0, height - visible)
      scrollbar:Show()
    else
      scrollbar:SetMinMaxValues(0, 0)
      scrollbar:Hide()
    end
  end

  scrollChild:SetScript('OnSizeChanged', UpdateScrollbar)

  self.mainFrame.content = scrollChild
  self.mainFrame.scrollFrame = scrollFrame
  self.mainFrame.UpdateScrollbar = UpdateScrollbar

  -- Modern refresh button with more space above it
  local refreshButton = CreateFrame('Button', nil, self.mainFrame, BackdropTemplateMixin and 'BackdropTemplate')
  refreshButton:SetSize(100, 25)
  refreshButton:SetPoint('BOTTOMLEFT', self.mainFrame, 'BOTTOMLEFT', 15, 15)

  -- Button background
  local buttonBackdrop = {
    bgFile = 'Interface\\Buttons\\WHITE8x8',
    edgeFile = 'Interface\\Buttons\\WHITE8x8',
    tile = false,
    tileSize = 0,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  }
  self:ApplyBackdrop(refreshButton, buttonBackdrop)
  self:SetBackdropColor(refreshButton, 0.2, 0.2, 0.2, 1)
  self:SetBackdropBorderColor(refreshButton, 0.7, 0.7, 0.7, 0.8)

  -- Button text
  local btnText = refreshButton:CreateFontString(nil, 'OVERLAY')
  btnText:SetFont('Fonts\\FRIZQT__.TTF', 10, 'OUTLINE')
  btnText:SetPoint('CENTER', 0, 0)
  btnText:SetText 'Refresh'
  btnText:SetTextColor(0.9, 0.9, 0.9)

  -- Button hover effect
  refreshButton:SetScript('OnEnter', function(self)
    GQT:SetBackdropColor(self, 0.3, 0.3, 0.3, 1)
    btnText:SetTextColor(1, 1, 1)
  end)

  refreshButton:SetScript('OnLeave', function(self)
    GQT:SetBackdropColor(self, 0.2, 0.2, 0.2, 1)
    btnText:SetTextColor(0.9, 0.9, 0.9)
  end)

  refreshButton:SetScript('OnClick', function()
    self:PreCacheQuestData()
    self:ScanForGoldQuests()
  end)

  -- Hidden by default
  self.mainFrame:Hide()
end

function GQT:FormatMoney(copper)
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local copperRem = copper % 100

  if gold > 0 then
    return string.format('%d|cFFFFD700g|r %d|cFFC0C0C0s|r %d|cFFB87333c|r', gold, silver, copperRem)
  elseif silver > 0 then
    return string.format('%d|cFFC0C0C0s|r %d|cFFB87333c|r', silver, copperRem)
  else
    return string.format('%d|cFFB87333c|r', copperRem)
  end
end

-- Create a backdrop handling utility function at the top of your addon
function GQT:ApplyBackdrop(frame, backdrop)
  if frame.SetBackdrop then
    -- Pre-Shadowlands API
    frame:SetBackdrop(backdrop)
  else
    -- Shadowlands and beyond
    if not frame.backdrop then
      frame.backdrop = frame:CreateTexture(nil, 'BACKGROUND')
      frame.backdrop:SetAllPoints(frame)

      frame.bordertop = frame:CreateTexture(nil, 'BORDER')
      frame.borderbottom = frame:CreateTexture(nil, 'BORDER')
      frame.borderleft = frame:CreateTexture(nil, 'BORDER')
      frame.borderright = frame:CreateTexture(nil, 'BORDER')
    end

    -- Set background
    frame.backdrop:SetTexture(backdrop.bgFile)
    frame.backdrop:SetTexCoord(0, 1, 0, 1)

    -- Border thickness
    local thickness = backdrop.edgeSize or 1

    -- Set borders
    frame.bordertop:SetTexture(backdrop.edgeFile)
    frame.bordertop:SetHeight(thickness)
    frame.bordertop:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    frame.bordertop:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)

    frame.borderbottom:SetTexture(backdrop.edgeFile)
    frame.borderbottom:SetHeight(thickness)
    frame.borderbottom:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
    frame.borderbottom:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)

    frame.borderleft:SetTexture(backdrop.edgeFile)
    frame.borderleft:SetWidth(thickness)
    frame.borderleft:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    frame.borderleft:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)

    frame.borderright:SetTexture(backdrop.edgeFile)
    frame.borderright:SetWidth(thickness)
    frame.borderright:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    frame.borderright:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
  end
end

-- And similarly for colors
function GQT:SetBackdropColor(frame, r, g, b, a)
  if frame.SetBackdropColor then
    -- Pre-Shadowlands API
    frame:SetBackdropColor(r, g, b, a)
  else
    -- Shadowlands and beyond
    if frame.backdrop then
      frame.backdrop:SetColorTexture(r, g, b, a)
    end
  end
end

function GQT:SetBackdropBorderColor(frame, r, g, b, a)
  if frame.SetBackdropBorderColor then
    -- Pre-Shadowlands API
    frame:SetBackdropBorderColor(r, g, b, a)
  else
    -- Shadowlands and beyond
    if frame.bordertop then
      frame.bordertop:SetColorTexture(r, g, b, a)
      frame.borderbottom:SetColorTexture(r, g, b, a)
      frame.borderleft:SetColorTexture(r, g, b, a)
      frame.borderright:SetColorTexture(r, g, b, a)
    end
  end
end

local function OnAddonLoaded(self, event, loadedAddonName)
  if loadedAddonName == addonName then
    GQT:Initialize()
    self:UnregisterEvent 'ADDON_LOADED'
  end
end

local initFrame = CreateFrame 'Frame'
initFrame:RegisterEvent 'ADDON_LOADED'
initFrame:SetScript('OnEvent', function(self, event, ...)
  if event == 'ADDON_LOADED' then
    OnAddonLoaded(self, event, ...)
  end
end)
