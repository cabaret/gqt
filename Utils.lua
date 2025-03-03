local addonName, GQT = ...

GQT.Utils = {}

function GQT.Utils:FormatMoney(copper)
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

function GQT.Utils:ApplyBackdrop(frame, backdrop)
  if frame.SetBackdrop then
    frame:SetBackdrop(backdrop)
  else
    if not frame.backdrop then
      frame.backdrop = frame:CreateTexture(nil, 'BACKGROUND')
      frame.backdrop:SetAllPoints(frame)

      frame.bordertop = frame:CreateTexture(nil, 'BORDER')
      frame.borderbottom = frame:CreateTexture(nil, 'BORDER')
      frame.borderleft = frame:CreateTexture(nil, 'BORDER')
      frame.borderright = frame:CreateTexture(nil, 'BORDER')
    end

    frame.backdrop:SetTexture(backdrop.bgFile)
    frame.backdrop:SetTexCoord(0, 1, 0, 1)

    local thickness = backdrop.edgeSize or 1

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

function GQT.Utils:SetBackdropColor(frame, r, g, b, a)
  if frame.SetBackdropColor then
    frame:SetBackdropColor(r, g, b, a)
  else
    if frame.backdrop then
      frame.backdrop:SetColorTexture(r, g, b, a)
    end
  end
end

function GQT.Utils:SetBackdropBorderColor(frame, r, g, b, a)
  if frame.SetBackdropBorderColor then
    frame:SetBackdropBorderColor(r, g, b, a)
  else
    if frame.bordertop then
      frame.bordertop:SetColorTexture(r, g, b, a)
      frame.borderbottom:SetColorTexture(r, g, b, a)
      frame.borderleft:SetColorTexture(r, g, b, a)
      frame.borderright:SetColorTexture(r, g, b, a)
    end
  end
end

function GQT.Utils:PrintTable(tbl, indent)
  if not tbl then
    return
  end

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
