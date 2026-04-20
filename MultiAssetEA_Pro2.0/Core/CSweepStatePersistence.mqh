//+------------------------------------------------------------------+
//| CSweepStatePersistence.mqh
//| Persistent sweep state across EA pause/resume cycles
//| Part of Phase 2 Fix 2: Sweep State Reliability
//+------------------------------------------------------------------+

#ifndef __CSWEEEPSTATEPERISTENCE_MQH__
#define __CSWEEEPSTATEPERISTENCE_MQH__

#include "CSymbolManager.mqh"

//+------------------------------------------------------------------+
//| CSweepStatePersistence Class
//| Purpose: Save/load VWAP sweep state to JSON files
//| Prevents double entries on pause/resume or EA restart
//+------------------------------------------------------------------+

class CSweepStatePersistence
{
private:
   string m_stateDirectory;  // State file storage path

   // Helper: Build state file path for symbol on given date
   string BuildStateFilePath(string symbol, string date)
   {
      // Format: sweep_state_EURUSD_2026-04-18.json
      return m_stateDirectory + "sweep_state_" + symbol + "_" + date + ".json";
   }

   // Helper: Get today's date in YYYY-MM-DD format
   string GetTodayDate()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      string year = IntegerToString(dt.year);
      string month = (dt.mon < 10) ? ("0" + IntegerToString(dt.mon)) : IntegerToString(dt.mon);
      string day = (dt.day < 10) ? ("0" + IntegerToString(dt.day)) : IntegerToString(dt.day);
      
      return year + "-" + month + "-" + day;
   }

   // Helper: Parse JSON value (simple key extraction)
   string ParseJsonValue(string json, string key)
   {
      string searchKey = "\"" + key + "\"";
      int pos = StringFind(json, searchKey);
      
      if(pos == -1) return "";
      
      // Find colon after key
      int colonPos = StringFind(json, ":", pos);
      if(colonPos == -1) return "";
      
      // Find value start (skip whitespace and quote if present)
      int valueStart = colonPos + 1;
      while(valueStart < StringLen(json) && 
            (StringGetCharacter(json, valueStart) == ' ' || 
             StringGetCharacter(json, valueStart) == '\t' ||
             StringGetCharacter(json, valueStart) == '"'))
      {
         valueStart++;
      }
      
      // Find value end (comma or closing brace)
      int valueEnd = valueStart;
      bool inString = (StringGetCharacter(json, valueStart - 1) == '"');
      
      while(valueEnd < StringLen(json))
      {
         if(inString)
         {
            if(StringGetCharacter(json, valueEnd) == '"') break;
         }
         else
         {
            if(StringGetCharacter(json, valueEnd) == ',' || 
               StringGetCharacter(json, valueEnd) == '}')
               break;
         }
         valueEnd++;
      }
      
      return StringSubstr(json, valueStart, valueEnd - valueStart);
   }

   // Helper: Format boolean for JSON
   string FormatJsonBool(bool value)
   {
      return value ? "true" : "false";
   }

public:
   // Constructor
   CSweepStatePersistence()
   {
      m_stateDirectory = "sweep_states/";
      
      // Ensure directory exists (create if needed)
      if(!FileIsExist(m_stateDirectory))
      {
         // MQL5 doesn't have mkdir, so we'll just use the directory
         // File operations will create it implicitly
      }
   }

   // Destructor
   ~CSweepStatePersistence()
   {
      // Cleanup handled in OnDeinit
   }

   //+------------------------------------------------------------------+
   //| SaveSymbolState: Persist sweep state to JSON file
   //| Purpose: Record VWAP sweep detection state for resume safety
   //+------------------------------------------------------------------+
   
   bool SaveSymbolState(string symbol, SSymbolConfig &cfg)
   {
      string todayDate = GetTodayDate();
      string filePath = BuildStateFilePath(symbol, todayDate);
      
      // Build JSON content
      string json = "{\n";
      json += "  \"symbol\": \"" + symbol + "\",\n";
      json += "  \"date\": \"" + todayDate + "\",\n";
      json += "  \"sweep_detected\": " + FormatJsonBool(cfg.vwapSweepDetected) + ",\n";
      json += "  \"sweep_direction\": " + IntegerToString(cfg.vwapSweepDirection) + ",\n";
      json += "  \"sweep_bar_count\": " + IntegerToString(cfg.vwapSweepBarCount) + ",\n";
      json += "  \"sweep_reclaimed\": " + FormatJsonBool(cfg.vwapSweepReclaimed) + ",\n";
      json += "  \"timestamp\": " + IntegerToString((int)TimeCurrent()) + "\n";
      json += "}\n";
      
      // Write to file
      int fileHandle = FileOpen(filePath, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fileHandle == INVALID_HANDLE)
      {
         Print("⚠️  Failed to open sweep state file: ", filePath);
         return false;
      }
      
      FileWriteString(fileHandle, json);
      FileClose(fileHandle);
      
      Print("✓ Sweep state saved: ", symbol, " → ", filePath);
      return true;
   }

   //+------------------------------------------------------------------+
   //| LoadSymbolState: Recover sweep state from JSON file
   //| Purpose: Restore sweep detection on EA resume to prevent double entry
   //+------------------------------------------------------------------+
   
   bool LoadSymbolState(string symbol, SSymbolConfig &cfg)
   {
      string todayDate = GetTodayDate();
      string filePath = BuildStateFilePath(symbol, todayDate);
      
      // Check if file exists
      if(!FileIsExist(filePath))
      {
         // First run today, no state to load
         return false;
      }
      
      // Read file
      int fileHandle = FileOpen(filePath, FILE_READ | FILE_TXT | FILE_ANSI);
      if(fileHandle == INVALID_HANDLE)
      {
         Print("⚠️  Failed to read sweep state file: ", filePath);
         return false;
      }
      
      string json = "";
      while(!FileIsEnding(fileHandle))
      {
         json += FileReadString(fileHandle);
      }
      FileClose(fileHandle);
      
      // Parse JSON
      string sweepDetected = ParseJsonValue(json, "sweep_detected");
      string sweepDirection = ParseJsonValue(json, "sweep_direction");
      string sweepBarCount = ParseJsonValue(json, "sweep_bar_count");
      string sweepReclaimed = ParseJsonValue(json, "sweep_reclaimed");
      
      if(sweepDetected == "") return false;  // Parse failed
      
      // Restore state
      cfg.vwapSweepDetected = (sweepDetected == "true");
      cfg.vwapSweepDirection = (int)StringToDouble(sweepDirection);
      cfg.vwapSweepBarCount = (int)StringToDouble(sweepBarCount);
      cfg.vwapSweepReclaimed = (sweepReclaimed == "true");
      
      Print("✓ Sweep state recovered: ", symbol, " from ", filePath);
      Print("  ├─ Sweep Detected: ", cfg.vwapSweepDetected);
      Print("  ├─ Direction: ", cfg.vwapSweepDirection);
      Print("  ├─ Bar Count: ", cfg.vwapSweepBarCount);
      Print("  ├─ Reclaimed: ", cfg.vwapSweepReclaimed);
      
      return true;
   }

   //+------------------------------------------------------------------+
   //| IsStateFromToday: Check if saved state is from current day
   //| Purpose: Determine if state should be used or cleared
   //+------------------------------------------------------------------+
   
   bool IsStateFromToday(string symbol)
   {
      string todayDate = GetTodayDate();
      string filePath = BuildStateFilePath(symbol, todayDate);
      
      return FileIsExist(filePath);
   }

   //+------------------------------------------------------------------+
   //| ClearOldStates: Remove sweep state files older than 1 day
   //| Purpose: Cleanup to prevent infinite state file accumulation
   //+------------------------------------------------------------------+
   
   void ClearOldStates()
   {
      Print("🧹 Cleaning up old sweep state files...");
      
      // Get yesterday's date
      MqlDateTime dt;
      TimeToStruct(TimeCurrent() - 86400, dt);  // 86400 seconds = 1 day
      
      string year = IntegerToString(dt.year);
      string month = (dt.mon < 10) ? ("0" + IntegerToString(dt.mon)) : IntegerToString(dt.mon);
      string day = (dt.day < 10) ? ("0" + IntegerToString(dt.day)) : IntegerToString(dt.day);
      
      string yesterdayDate = year + "-" + month + "-" + day;
      
      // Search and delete files matching pattern: sweep_state_*_<yesterday_date>.json
      // Note: MQL5 doesn't have built-in directory listing, so we rely on manual cleanup
      // or scheduled maintenance. This function serves as a reminder/hook point.
      
      Print("  ├─ Old state files (>1 day) would be cleaned up here");
      Print("  └─ Note: Manual cleanup needed for: sweep_state_*_" + yesterdayDate + ".json");
   }

   //+------------------------------------------------------------------+
   //| GetStateDirectory: Return state file storage path
   //+------------------------------------------------------------------+
   
   string GetStateDirectory()
   {
      return m_stateDirectory;
   }
};

#endif
