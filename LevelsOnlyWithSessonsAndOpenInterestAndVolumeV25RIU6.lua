require "QL"
require "iuplua"
require "w32"


local ACCOUNT = "A901KS9"       
local CLASS_CODE = "SPBFUT"
local SEC_CODE = "RIU6"
local PRICE_DELTA = 50          -- отступление от цены, для точного исполнения заявки
local g_FORTS = 1               -- если скрипт играет на фортс, то эта константа равна 1 , для игры на акциях ее значение необходимо установить в 0
local g_isRealOrder = 0         -- 1 если с реальными заявками, ноль без реальных заявок
local g_TickVolumeMoreThan = 10 -- во сколько раз тиковый объем больше чем средний за день 

local t = QTable:new()

local g_RowIndex = 0

local g_theHighestCloseOfOneMinuteGreenCandleInNewSession = -1
local g_theLowestCloseOfOneMinuteRedCandleInNewSesson = 1000000
local g_isShort = false
local g_isLong = false
local g_levelForClosePosition = -1
local g_stoplossLevel = -1
local g_bestPrice = -1

local g_curOpenInterest = -1
local g_maxOpenInterest = -1

local g_TickVolume = 0
local g_TickCntPerDay = 0
local g_TickVolumeMaxCnt = 0
local dtForOpenInterest = os.date("*t")

local g_canTrade = false


-- Виды операций
local OrderOperations = {
    ["Buy"] = "B";              -- Заявка на покупку
    ["Sell"] = "S";             -- Заявка на продажу
}


function OnStop(stop_flag)
  t:delete()
end 

local function beep(n)
  for i=1, n do
    w32.MessageBeep(w32.MB_OK)
    sleep(200)
  end
end  

function addToMyTable() 
  table.sort(t_globalSupportLine)
  table.sort(t_globalResistanseLine)
  
  for i=1, #t_globalSupportLine do
    local rows, _ = t:GetSize()
    if (i>rows) then 
      t:AddLine()
    end
    t:SetValue(i, "SupportLine", tostring(t_globalSupportLine[i]))
  end
  
  for i=1, #t_globalResistanseLine do
    local rows, _ = t:GetSize()
    if (i>rows) then 
      t:AddLine()
    end
    t:SetValue(i, "ResistanseLine", tostring(t_globalResistanseLine[i]))
  end 
end
  
  
  function wasLineBreakdown(index, canTrade)
    if (not canTrade) then return false end
    local curTime = tostring(ds5:T(index).hour)..":"..tostring(ds5:T(index).min)
    local oPrice = ds5:O(index)
    local cPrice =ds5:C(index)
    local hPrice = ds5:H(index)
    local lPrice = ds5:L(index)
    local hPriceBefore = ds5:H(index-1)
    local lPriceBefore = ds5:L(index-1)
    local cPriceBefore = ds5:C(index-1)
    if cPrice == oPrice then return false end
    if (lPriceBefore < cPrice) then
        local tableSize = #t_globalResistanseLine
        for i=1, tableSize do
          if (((lPriceBefore < t_globalResistanseLine[i]) and (cPrice > t_globalResistanseLine[i]))
             or ((lPriceBefore == cPriceBefore) and (lPriceBefore == t_globalResistanseLine[i]) and (ds5:C(index-2) < t_globalResistanseLine[i])))  then
            g_CurrentLevel = t_globalResistanseLine[i]
            local tempg_CurrentLevel = g_CurrentLevel
            local localPrice = (g_FORTS == 1) and (g_bestPrice + PRICE_DELTA) or 0
            if ((not g_isLong) and (not g_isShort)) then
              g_levelForClosePosition = g_CurrentLevel + 2*(g_CurrentLevel - g_theLowestCloseOfOneMinuteRedCandleInNewSesson)
              g_stoplossLevel = g_theLowestCloseOfOneMinuteRedCandleInNewSesson
              if cPrice > g_levelForClosePosition then 
                startNewSession(true)
                showInformation(curTime, "NEW SESSION, UP LEVEL EXEEDED", tempg_CurrentLevel)
              else
                if ((g_curOpenInterest ~= nil) and (g_curOpenInterest >= g_maxOpenInterest) and (g_curOpenInterest > -1)) then 
                  showInformation(curTime, "UP", g_CurrentLevel)
                else
                  g_canTrade = true 
                  showInformation(curTime, "UP, NO ORDER ", g_CurrentLevel)
                end
                TransactionSend(1, OrderOperations.Buy, 1, localPrice)
                
                startNewSession(false)
                g_isLong = true
              end
            elseif ((not g_isLong) and (g_isShort)) then
              TransactionSend(1, OrderOperations.Buy, 2, localPrice)
              g_levelForClosePosition = g_CurrentLevel + 2*(g_CurrentLevel - g_theLowestCloseOfOneMinuteRedCandleInNewSesson)
              g_stoplossLevel = g_theLowestCloseOfOneMinuteRedCandleInNewSesson
              startNewSession(false)
              g_isLong = true
              showInformation(tostring(dt.hour)..":"..tostring(dt.min), "NEW SESSION, REVERSE POSITION, UP", tempg_CurrentLevel)
            end 
            return true 
          end
        end
        return false
    elseif (hPriceBefore > cPrice) then
        local tableSize = #t_globalSupportLine
        for i=tableSize, 1, -1 do
          if (((hPriceBefore > t_globalSupportLine[i]) and (cPrice < t_globalSupportLine[i]))
             or ((hPriceBefore == cPriceBefore) and (hPriceBefore == t_globalSupportLine[i]) and (ds5:C(index-2) > t_globalSupportLine[i])))  then
            g_CurrentLevel = t_globalSupportLine[i]
            local tempg_CurrentLevel = g_CurrentLevel
            local localPrice = (g_FORTS == 1) and (g_bestPrice - PRICE_DELTA) or 0
            if ((not g_isLong) and (not g_isShort)) then
              g_levelForClosePosition = g_CurrentLevel - 2*(g_theHighestCloseOfOneMinuteGreenCandleInNewSession - g_CurrentLevel)
              g_stoplossLevel = g_theHighestCloseOfOneMinuteGreenCandleInNewSession
              if cPrice < g_levelForClosePosition then 
                startNewSession(true)
                showInformation(curTime, "NEW SESSION, DOWN LEVEL EXEEDED", tempg_CurrentLevel)
              else
                if ((g_curOpenInterest ~= nil) and (g_curOpenInterest >= g_maxOpenInterest) and (g_curOpenInterest > -1)) then 
                  showInformation(curTime, "DOWN", g_CurrentLevel)
                else
                  g_canTrade = true 
                  showInformation(curTime, "DOWN, NO ORDER", g_CurrentLevel)
                end
                TransactionSend(1, OrderOperations.Sell, 1, localPrice)
                startNewSession(false)
                g_isShort = true
              end
            elseif ((g_isLong) and (not g_isShort)) then
              g_levelForClosePosition = g_CurrentLevel - 2*(g_theHighestCloseOfOneMinuteGreenCandleInNewSession - g_CurrentLevel)
              g_stoplossLevel = g_theHighestCloseOfOneMinuteGreenCandleInNewSession
              TransactionSend(1, OrderOperations.Sell, 2, localPrice)
              startNewSession(false)
              g_isShort = true
              showInformation(tostring(dt.hour)..":"..tostring(dt.min), "NEW SESSION, REVERSE POSITION, DOWN", tempg_CurrentLevel)
            end 
            return true 
          end
        end
        return false
    end
  end  
  
 -- Функция постановки новой заявки
function TransactionSend(trans_id, operation, quantity, price)
     if (g_isRealOrder == 0) then return end
     if (not g_canTrade) then return end 
     
     local trans_params = {
        ["TRANS_ID"] = tostring(trans_id);
        ["ACTION"] = "NEW_ORDER";
        ["ACCOUNT"] = ACCOUNT;
        ["CLASSCODE"] = CLASS_CODE;
        ["SECCODE"] = SEC_CODE;
        ["CLIENT_CODE"] = CLIENT_CODE;
        ["OPERATION"] = operation;
        ["QUANTITY"] = tostring(quantity);
        ["PRICE"] = tostring(math.floor(price / 10) * 10);
        ["TYPE"] = "M";
    };

    return sendTransaction(trans_params);
end;
  
  function startNewSession(allLevelsDelete)
    --получим время 
    dt = os.date("*t")
    
    t_greenCandles1 = {}
    t_redCandles1 = {}
    t_supportLine1 = {}
    t_resistanseLine1 = {}

    t_greenCandles5 = {}
    t_redCandles5 = {}
    t_supportLine5 = {}
    t_resistanseLine5 = {}

    t_globalSupportLine = {}
    t_globalResistanseLine = {}

    t_globalSupportLineND = {}
    t_globalResistanseLineND = {}


    g_CurrentLevel = 0
    g_isShort = false
    g_isLong = false
    
    if (allLevelsDelete) then
      g_theHighestCloseOfOneMinuteGreenCandleInNewSession = -1
      g_theLowestCloseOfOneMinuteRedCandleInNewSesson = 1000000 
      g_levelForClosePosition = -1
      g_stoplossLevel = -1
      
      g_curOpenInterest = -1
      g_canTrade = false
    end
    
    local rows, _ = t:GetSize()
    for i=1, rows do
      t:SetValue(i, "SupportLine", " ")
      t:SetValue(i, "ResistanseLine", " ")
    end
  end  
  
  
  function showInformation(time, direction, level)
      g_RowIndex = g_RowIndex + 1
      local rows, _ = t:GetSize()
      while (g_RowIndex>rows) do
          t:AddLine()
          rows, _ = t:GetSize()          
      end
      t:SetValue(g_RowIndex, "Time", time)
      t:SetValue(g_RowIndex, "Direction", direction)
      t:SetValue(g_RowIndex, "Level", tostring(level))
      message(direction.." "..SEC_CODE, 2)
      beep(5) 
  end
  

function handleTheCandle1(index, canTrade)
      if ((ds:C(index) - ds:O(index))>0) then               --candle is green
            if (ds:C(index) > g_theHighestCloseOfOneMinuteGreenCandleInNewSession) then g_theHighestCloseOfOneMinuteGreenCandleInNewSession = ds:C(index) end
          --message(tostring(g_theHighestCloseOfOneMinuteGreenCandleInNewSession).."hiGreen", 1)
          if t_greenCandles1[ds:C(index)] ~=1 then          --if candle is not in green candles array        
            t_greenCandles1[ds:C(index)] = 1                --add this candle in green candles array
          else                                              --else (if this candle already in green candles array) 
            t_resistanseLine1[ds:C(index)] = 1              --add this candle as resistanseLine1
            checkGlobalResistanseLines(ds:C(index))
          end
      elseif ((ds:C(index) - ds:O(index))<0) then
            if (ds:C(index) < g_theLowestCloseOfOneMinuteRedCandleInNewSesson) then g_theLowestCloseOfOneMinuteRedCandleInNewSesson = ds:C(index) end
          --message(tostring(g_theLowestCloseOfOneMinuteRedCandleInNewSesson).."lowGed", 1)
          if t_redCandles1[ds:C(index)] ~= 1 then
            t_redCandles1[ds:C(index)] = 1
          else
            t_supportLine1[ds:C(index)] = 1
            checkGlobalSupportLines(ds:C(index))
          end
      end
end

function checkGlobalResistanseLines(close)
    if ((t_resistanseLine1[close] == 1) and (t_resistanseLine5[close] == 1)) then                 --if 
      if  (t_globalResistanseLineND[close] ~= 1) then
          t_globalResistanseLineND[close] = 1
          table.insert(t_globalResistanseLine, close) 
          addToMyTable() 
      end
    end
end  

function checkGlobalSupportLines(close)
    if ((t_supportLine1[close] == 1) and (t_supportLine5[close] == 1)) then
      if (t_globalSupportLineND[close] ~= 1) then
          t_globalSupportLineND[close] = 1
          table.insert(t_globalSupportLine, close)
          addToMyTable()
      end  
    end
end  

function handleTheCandle5(index, canTrade)
    if ((ds5:C(index) - ds5:O(index))>=0) then                             --candle is green
        if t_greenCandles5[ds5:C(index)] ~=1 then                          --if candle is not green candles array
            t_greenCandles5[ds5:C(index)] = 1                              --add this candles in green candles array
        else                                                               --else (if this candle already in green candles array)
            t_resistanseLine5[ds5:C(index)] = 1                            --add this candle as resistanseLine5
            checkGlobalResistanseLines(ds5:C(index))
        end
    end
    if ((ds5:C(index) - ds5:O(index))<=0) then
        if t_redCandles5[ds5:C(index)] ~= 1 then
            t_redCandles5[ds5:C(index)] = 1
        else
            t_supportLine5[ds5:C(index)] = 1
            checkGlobalSupportLines(ds5:C(index)) 
        end
    end
    _ = wasLineBreakdown(index, canTrade)
end  
    
function cbTick(index)
  local i = index
  if ((dtForOpenInterest.year == dsTick:T(i).year) and (dtForOpenInterest.month == dsTick:T(i).month) and (dtForOpenInterest.day == dsTick:T(i).day)) then
      
      if ((g_TickCntPerDay ~= 0) and (g_TickVolume ~= 0) and (math.floor(dsTick:V(i)*g_TickCntPerDay/g_TickVolume) >= g_TickVolumeMoreThan)) then
        
        g_TickVolumeMaxCnt = g_TickVolumeMaxCnt + 1
        local rows, _ = t:GetSize()
        if (g_TickVolumeMaxCnt>rows) then 
          t:AddLine()
        end
       
        
        t:SetValue(g_TickVolumeMaxCnt, "VolumeMax", tostring(dsTick:V(i)).."        "..tostring(dsTick:T(i).hour..":"..tostring(dsTick:T(i).min)..":"..tostring(dsTick:T(i).sec)))
        t:SetValue(g_TickVolumeMaxCnt, "VolumeAver", tostring(math.floor(g_TickVolume/g_TickCntPerDay)))

      end  
      
      g_TickVolume = g_TickVolume + dsTick:V(i)
      g_TickCntPerDay = g_TickCntPerDay + 1
    end
end 


function cb1(index)
    if (index == 1) then return end
    g_bestPrice = ds:C(index)
    local i = index - 1
    if (g_isLong and ((ds:C(index))~=nil) and ((ds:C(index)) >= g_levelForClosePosition) and (isCandleInNewSesson1(i))) then
      local localPrice = (g_FORTS == 1) and (g_bestPrice - PRICE_DELTA) or 0
      TransactionSend(1, OrderOperations.Sell, 1, localPrice)
      startNewSession(true)
      showInformation(tostring(dt.hour)..":"..tostring(dt.min), "NEW SESSION, CLOSE LONG POSITION", ds:C(index))
    end
    if (g_isShort and ((ds:C(index))~=nil) and ((ds:C(index)) <= g_levelForClosePosition) and (isCandleInNewSesson1(i))) then
      local localPrice = (g_FORTS == 1) and (g_bestPrice + PRICE_DELTA) or 0
      TransactionSend(1, OrderOperations.Buy, 1, localPrice)
      startNewSession(true)
      showInformation(tostring(dt.hour)..":"..tostring(dt.min), "NEW SESSION, CLOSE SHORT POSITION", ds:C(index))
    end
    
    if ((i>dsSize) and isCandleInNewSesson1(i) and ((ds:C(i))~=nil) and ((ds:C(i)) ~= (ds:O(i)))) then
      dsSize = i
      --message(tostring(ds:T(i).day)..tostring(ds:T(i).hour)..tostring(ds:T(i).min).."Candle1", 1)
      handleTheCandle1(dsSize, true)
    end  
end


function cb5(index)
    if (index == 1) then return end
    local i = index - 1 
    if ((i>dsSize5) and isCandleInNewSesson5(i) and ((ds5:C(i))~=nil)) then  
      dsSize5 = i
      --message(tostring(ds5:T(i).day)..tostring(ds5:T(i).hour)..tostring(ds5:T(i).min).."Candle5", 1)
      handleTheCandle5(dsSize5, true)
    end  
end
 

function isCandleInNewSesson1(i)
  local newSessionYear = dt.year
  local newSessionMonth = dt.month
  local newSessionDay = dt.day
  local newSessionHour = dt.hour
  local newSessionMin = dt.min
  local candleYear = ds:T(i).year
  local candleMonth = ds:T(i).month
  local candleDay = ds:T(i).day
  local candleHour = ds:T(i).hour
  local candleMin = ds:T(i).min
  if candleYear > newSessionYear then return true end
  if candleYear < newSessionYear then return false end
  if candleMonth > newSessionMonth then return true end
  if candleMonth < newSessionMonth then return false end
  if candleDay > newSessionDay then return true end
  if candleDay < newSessionDay then return false end
  if candleHour > newSessionHour then return true end
  if candleHour < newSessionHour then return false end
  if candleMin >= newSessionMin then return true end
  if candleMin < newSessionMin then return false end
end 

function isCandleInNewSesson5(i)
  local newSessionYear = dt.year
  local newSessionMonth = dt.month
  local newSessionDay = dt.day
  local newSessionHour = dt.hour
  local newSessionMin = dt.min
  local candleYear = ds5:T(i).year
  local candleMonth = ds5:T(i).month
  local candleDay = ds5:T(i).day
  local candleHour = ds5:T(i).hour
  local candleMin = ds5:T(i).min
  if candleYear > newSessionYear then return true end
  if candleYear < newSessionYear then return false end
  if candleMonth > newSessionMonth then return true end
  if candleMonth < newSessionMonth then return false end
  if candleDay > newSessionDay then return true end
  if candleDay < newSessionDay then return false end
  if candleHour > newSessionHour then return true end
  if candleHour < newSessionHour then return false end
  if candleMin >= newSessionMin then return true end
  if candleMin < newSessionMin then return false end
end 


function OnConnected()
  newCalc()
end
  
function newCalc()
  t:AddLine()
  isRun = true;
  t_greenCandles1 = {}
  t_redCandles1 = {}
  t_supportLine1 = {}
  t_resistanseLine1 = {}

  t_greenCandles5 = {}
  t_redCandles5 = {}
  t_supportLine5 = {}
  t_resistanseLine5 = {}

  t_globalSupportLine = {}
  t_globalResistanseLine = {}

  t_globalSupportLineND = {}
  t_globalResistanseLineND = {}

  g_CurrentLevel = 0
     
  g_curOpenInterest = -1 
  
  g_TickVolume = 0
  g_TickCntPerDay = 0
  g_TickVolumeMaxCnt = 0
  dtForOpenInterest = os.date("*t")
    
   
   --обработаем тики для получения объема
  dsTick = CreateDataSource(CLASS_CODE, SEC_CODE, INTERVAL_TICK)
  
  dsTickSize = dsTick:Size()
  for i=1, dsTickSize do
    if ((dtForOpenInterest.year == dsTick:T(i).year) and (dtForOpenInterest.month == dsTick:T(i).month) and (dtForOpenInterest.day == dsTick:T(i).day)) then
      g_TickVolume = g_TickVolume + dsTick:V(i)
      g_TickCntPerDay = g_TickCntPerDay + 1
    end
  end  
  
  dsTick:SetUpdateCallback(cbTick)
    
  --обработаем минутные свечи
  ds = CreateDataSource(CLASS_CODE, SEC_CODE, INTERVAL_M1);
  dsSize = ds:Size()-1;
  for i=1, dsSize do
    if (isCandleInNewSesson1(i) and ((ds:C(i))~=nil) and ((ds:C(i)) ~= (ds:O(i)))) then
      handleTheCandle1(i, false)
    end
  end
  
  ds:SetUpdateCallback(cb1);
  
  --обработаем пятиминутные свечи
  ds5 = CreateDataSource(CLASS_CODE, SEC_CODE, INTERVAL_M5);
  dsSize5 = ds5:Size()-1;
  for i=1, dsSize5 do
    if (isCandleInNewSesson5(i) and ((ds5:C(i))~=nil)) then
      handleTheCandle5(i, false)
    end
  end
  
  ds5:SetUpdateCallback(cb5);
  
end  
  

function main()
  
  --получим время 
  dt = os.date("*t")
  
  --таблицa 
  
  t:AddColumn("ResistanseLine", QTABLE_STRING_TYPE, 25)
  t:AddColumn("SupportLine", QTABLE_STRING_TYPE, 25)
  t:AddColumn("Time", QTABLE_STRING_TYPE, 25)
  t:AddColumn("Direction", QTABLE_STRING_TYPE, 70)
  t:AddColumn("Level", QTABLE_STRING_TYPE, 25)
  t:AddColumn("OpenInterest", QTABLE_STRING_TYPE, 25)
  t:AddColumn("MaxOpenInterest", QTABLE_STRING_TYPE, 25)
  t:AddColumn("VolumeMax", QTABLE_STRING_TYPE, 25)
  t:AddColumn("VolumeAver", QTABLE_STRING_TYPE, 25)
  t:SetCaption(SEC_CODE)
  t:SetPosition(0, 0, 500, 700)
  t:Show()
  
  
  newCalc()
  
  showInformation(tostring(dt.hour)..":"..tostring(dt.min), "NEW SESSION, SCRIPT START", 0)
  
  while isRun do
    
  --получим время 
  dtForOpenInterest = os.date("*t")
    
    sleep(1000);
    
    
    g_curOpenInterest = tonumber(getParamEx(CLASS_CODE, SEC_CODE, "NUMCONTRACTS").param_value)
    if (dtForOpenInterest.hour < 10)  then 
      g_curOpenInterest = -1
      g_maxOpenInterest = -1
    end
    if ((g_curOpenInterest ~= nil) and (g_curOpenInterest > g_maxOpenInterest) and (dtForOpenInterest.hour == 10) and (dtForOpenInterest.min < 15))  then
      g_maxOpenInterest = g_curOpenInterest
    end  
    t:SetValue(1, "OpenInterest", tostring(g_curOpenInterest))
    t:SetValue(1, "MaxOpenInterest", tostring(g_maxOpenInterest))
  
  end
end